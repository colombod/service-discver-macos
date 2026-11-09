import Foundation

public struct DirectoryConnection: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var address: String
    public init(id: UUID = UUID(), name: String, address: String) {
        self.id = id; self.name = name; self.address = address
    }
}

public struct ServiceLink: Codable, Hashable, Sendable {
    public var label: String
    public var host: String?
    public var url: String
    public var webURL: URL? { URLPolicy.webURL(url) }
}

public struct DirectoryService: Codable, Identifiable, Hashable, Sendable {
    public var name: String
    public var description: String?
    public var links: [ServiceLink]
    public var origin: String?
    public var category: String?
    public var tags: [String]?
    public var owner: String?
    public var docs_url: String?
    public var view_url: String?
    public var view_kind: String?
    public var view_refresh_seconds: Int?
    public var health_url: String?
    // JSON encoding avoids collisions when either component contains a separator.
    public var id: String { String(data: try! JSONEncoder().encode([origin ?? "", name]), encoding: .utf8)! }
    public var preferredURL: URL? { view_url.flatMap(URLPolicy.webURL) ?? links.compactMap(\.webURL).first }
    public var healthProbeURL: URL? { health_url.flatMap(URLPolicy.webURL) ?? preferredURL }
}

public struct FederationNode: Codable, Identifiable, Hashable, Sendable {
    public var name: String
    public var device_id: String?
    public var base_url: String
    public var reachable: Bool
    public var version: String?
    public var description: String?
    public var role: String?
    public var id: String { device_id ?? base_url }
}

public struct InstanceInfo: Codable, Sendable {
    public var name: String
    public var device_id: String
    public var version: String?
    public var federation_enabled: Bool
}

public struct MaintenanceJob: Codable, Identifiable, Sendable {
    public var id: String
    public var status: String
    public var message: String
    public var steps: [String]
    public var isActive: Bool { ["queued", "running"].contains(status) }
}

public struct MaintenanceState: Codable, Sendable {
    public var version: String
    public var install_kind: String
    public var update_supported: Bool
    public var unsupported_reason: String?
    public var update_available: Bool?
    public var current_revision: String?
    public var latest_revision: String?
    public var latest_version: String?
    public var job: MaintenanceJob?
}

public enum DirectoryError: LocalizedError {
    case invalidURL, unauthorized, http(Int), invalidResponse, invalidShortcut(String)
    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Enter an HTTP or HTTPS URL with a host, without credentials, a query, or a fragment."
        case .unauthorized: return "Authentication required. Check the credential saved for this directory. Read access needs a peer token; maintenance actions need the node’s write token."
        case .http(let status): return "The directory returned HTTP \(status)."
        case .invalidResponse: return "The directory returned an unexpected response."
        case .invalidShortcut(let message): return message
        }
    }
}

public enum URLPolicy {
    public static func webURL(_ value: String) -> URL? {
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        return url
    }
    public static func baseURL(_ value: String) throws -> URL {
        guard let url = webURL(value.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.query == nil, url.fragment == nil else { throw DirectoryError.invalidURL }
        return url
    }
    public static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        func port(_ u: URL) -> Int { u.port ?? (u.scheme?.lowercased() == "https" ? 443 : 80) }
        return lhs.scheme?.lowercased() == rhs.scheme?.lowercased() && lhs.host?.lowercased() == rhs.host?.lowercased() && port(lhs) == port(rhs)
    }
}
