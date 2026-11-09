import Foundation

public struct HealthTarget: Sendable {
    public let origin: String
    public let deviceID: String?
    public let base: URL
    public let token: String?
    public let serviceURLs: [String: URL]

    public init(origin: String, deviceID: String?, base: URL, token: String?, serviceURLs: [String: URL] = [:]) {
        self.origin = origin; self.deviceID = deviceID; self.base = base; self.token = token
        self.serviceURLs = serviceURLs
    }

    /// Credentials belong to a saved directory URL, never to a peer name.
    public static func credentialKey(_ url: URL) -> String {
        let port = url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80)
        let endpoint = url.appendingPathComponent("api/health")
        let path = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? endpoint.path
        return "\(url.scheme?.lowercased() ?? "")://\(url.host?.lowercased() ?? ""):\(port)\(path)"
    }
}

public enum FederationHealth {
    public static func fetch(_ targets: [HealthTarget], api: DirectoryAPI) async -> [String: [String: String]] {
        var result: [String: [String: String]] = [:]
        // Bound concurrency even when a federation advertises many nodes.
        for offset in stride(from: 0, to: targets.count, by: 8) {
            if Task.isCancelled { break }
            let batch = Array(targets[offset..<min(offset + 8, targets.count)])
            await withTaskGroup(of: (String, [String: String]?).self) { group in
                for target in batch {
                    group.addTask {
                        do {
                            let info = try await api.fetch(InstanceInfo.self, base: target.base,
                                                           path: "api/instance-info", token: nil)
                            guard info.name == target.origin,
                                  target.deviceID == nil || info.device_id == target.deviceID else {
                                return (target.origin, nil)
                            }
                            var health = try await api.fetch([String: String].self, base: target.base,
                                                             path: "api/health", token: target.token)
                            await withTaskGroup(of: (String, String).self) { probes in
                                // Bound the number of simultaneous HEAD probes per node.
                                let entries = target.serviceURLs.filter { health[$0.key] == "up" }.sorted { $0.key < $1.key }
                                var next = 0
                                for (name, url) in entries.prefix(4) {
                                    probes.addTask { (name, await api.serviceAvailability(url)) }
                                    next += 1
                                }
                                for await (name, availability) in probes {
                                    if health[name] == "up" { health[name] = availability }
                                    if next < entries.count {
                                        let entry = entries[next]; next += 1
                                        probes.addTask { (entry.key, await api.serviceAvailability(entry.value)) }
                                    }
                                }
                            }
                            return (target.origin, health)
                        } catch { return (target.origin, nil) }
                    }
                }
                for await (origin, health) in group { result[origin] = health }
            }
        }
        return result
    }
}
