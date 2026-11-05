import Foundation

// API tokens must never follow redirects to another service or sign-in host.
private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public final class DirectoryAPI: @unchecked Sendable {
    private let session: URLSession
    public init(session: URLSession? = nil) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 25
        self.session = session ?? URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }
    public static func request(base: URL, path: String, token: String?, method: String = "GET") -> URLRequest {
        let url = base.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }
    public func fetch<T: Decodable>(_ type: T.Type, base: URL, path: String,
                                    token: String?, method: String = "GET") async throws -> T {
        let (data, response) = try await session.data(for: Self.request(base: base, path: path, token: token, method: method))
        guard let http = response as? HTTPURLResponse else { throw DirectoryError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw DirectoryError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw DirectoryError.http(http.statusCode) }
        return try JSONDecoder().decode(type, from: data)
    }
}
