import Foundation

public struct JSONEndpointResponse: @unchecked Sendable {
    public let data: Data
    public let status: Int
    public let mimeType: String?
    public let cookies: [HTTPCookie]
}

public enum ServiceCookies {
    public static func matching(_ cookies: [HTTPCookie], url: URL, now: Date = Date()) -> [HTTPCookie] {
        guard let host = url.host?.lowercased() else { return [] }
        let path = url.path.isEmpty ? "/" : url.path
        return cookies.filter { cookie in
            let domain = cookie.domain.lowercased()
            let domainMatches = domain.hasPrefix(".")
                ? host == String(domain.dropFirst()) || host.hasSuffix(domain)
                : host == domain
            let cookiePath = cookie.path.isEmpty ? "/" : cookie.path
            let pathMatches = path == cookiePath || (path.hasPrefix(cookiePath) &&
                (cookiePath.hasSuffix("/") || path.dropFirst(cookiePath.count).hasPrefix("/")))
            return domainMatches && pathMatches && (!cookie.isSecure || url.scheme?.lowercased() == "https") &&
                (cookie.expiresDate == nil || cookie.expiresDate! > now)
        }
    }
}

public final class JSONEndpointClient: @unchecked Sendable {
    private let session: URLSession
    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }
    public func fetch(_ url: URL, cookies: [HTTPCookie] = []) async throws -> JSONEndpointResponse {
        guard URLPolicy.webURL(url.absoluteString) != nil else { throw DirectoryError.invalidURL }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        request.setValue("application/json, */*;q=0.5", forHTTPHeaderField: "Accept")
        for (header, value) in HTTPCookie.requestHeaderFields(with: ServiceCookies.matching(cookies, url: url)) {
            request.setValue(value, forHTTPHeaderField: header)
        }
        let (stream, response) = try await session.bytes(for: request)
        defer { stream.task.cancel() }
        guard let http = response as? HTTPURLResponse else { throw DirectoryError.invalidResponse }
        guard http.expectedContentLength <= JSONDocument.maximumBytes else { throw JSONDisplayError.tooLarge }
        var data = Data()
        data.reserveCapacity(min(JSONDocument.maximumBytes, max(0, Int(http.expectedContentLength))))
        for try await byte in stream {
            guard data.count < JSONDocument.maximumBytes else { throw JSONDisplayError.tooLarge }
            data.append(byte)
        }
        let headers = http.allHeaderFields.reduce(into: [String: String]()) { result, item in
            if let key = item.key as? String, let value = item.value as? String { result[key] = value }
        }
        // JSON endpoints may refresh host cookies, but cannot broaden the scope
        // of the WebKit cookie store by setting a parent-domain cookie here.
        let receivedCookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url).filter {
            $0.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased() == url.host?.lowercased()
        }
        return JSONEndpointResponse(data: data, status: http.statusCode, mimeType: http.mimeType,
                                    cookies: ServiceCookies.matching(receivedCookies, url: url))
    }
}
