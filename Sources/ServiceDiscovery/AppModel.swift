import SwiftUI
import DirectoryCore

@MainActor @Observable
final class AppModel {
    var preferences = Preferences()
    var services: [DirectoryService] = []
    var nodes: [FederationNode] = []
    var health: [String: String] = [:]
    var localOrigin: String?
    var selectedNode: String?
    var selectedService: String?
    var query = ""
    var loading = false
    var error: String?
    var lastRefresh: Date?
    var maintenance: MaintenanceState?
    var maintenanceMessage: String?
    var maintenanceBusy = false
    private let api = DirectoryAPI()
    private var refreshID = UUID()
    private var maintenanceID = UUID()

    init() {
        do { preferences = try LocalStore.load() }
        catch { self.error = "Could not read saved settings: \(error.localizedDescription)" }
    }
    var connection: DirectoryConnection? {
        preferences.connections.first { $0.id == preferences.selectedConnection } ?? preferences.connections.first
    }
    var filteredServices: [DirectoryService] {
        services.filter { service in
            (selectedNode == nil || service.origin == selectedNode) &&
            (query.isEmpty || [service.name, service.description ?? "", service.origin ?? "", service.category ?? ""]
                .joined(separator: " ").localizedCaseInsensitiveContains(query) || (service.tags ?? []).joined(separator: " ").localizedCaseInsensitiveContains(query))
        }.sorted { ($0.origin ?? "", $0.name) < ($1.origin ?? "", $1.name) }
    }
    var origins: [String] { Set(services.compactMap(\.origin) + nodes.map(\.name)).sorted() }
    var currentService: DirectoryService? { services.first { $0.id == selectedService } }
    var currentNode: FederationNode? { nodes.first { $0.name == selectedNode } }
    var shortcutKey: String? {
        guard let connection, let node = currentNode else { return nil }
        return "\(connection.id.uuidString)/\(node.id)"
    }
    var shortcut: TerminalShortcut? { shortcutKey.flatMap { preferences.shortcuts[$0] } }
    func token(_ connection: DirectoryConnection, write: Bool = false) throws -> String? {
        try Keychain.read("\(write ? "write" : "read"):\(connection.id.uuidString)")
    }
    func save() throws { try LocalStore.save(preferences) }

    func selectConnection(_ id: UUID?) {
        preferences.selectedConnection = id
        services = []; nodes = []; health = [:]; selectedNode = nil; selectedService = nil
        localOrigin = nil; lastRefresh = nil; maintenance = nil; maintenanceMessage = nil
        maintenanceID = UUID()
        do { try save() } catch { self.error = error.localizedDescription }
    }
    func saveConnection(_ value: DirectoryConnection, readToken: String, writeToken: String) throws {
        _ = try URLPolicy.baseURL(value.address)
        try Keychain.write(readToken.trimmingCharacters(in: .whitespacesAndNewlines), account: "read:\(value.id.uuidString)")
        try Keychain.write(writeToken.trimmingCharacters(in: .whitespacesAndNewlines), account: "write:\(value.id.uuidString)")
        if let index = preferences.connections.firstIndex(where: { $0.id == value.id }) {
            preferences.connections[index] = value
        } else { preferences.connections.append(value) }
        selectConnection(value.id)
        try save()
    }
    func removeConnection(_ id: UUID) throws {
        try Keychain.write("", account: "read:\(id.uuidString)")
        try Keychain.write("", account: "write:\(id.uuidString)")
        preferences.connections.removeAll { $0.id == id }
        preferences.shortcuts = preferences.shortcuts.filter { !$0.key.hasPrefix(id.uuidString + "/") }
        selectConnection(preferences.connections.first?.id)
        try save()
    }
    func refresh() async {
        let requestID = UUID(); refreshID = requestID
        guard let connection else { loading = false; return }
        loading = true
        defer { if refreshID == requestID { loading = false } }
        do {
            let base = try URLPolicy.baseURL(connection.address)
            let credential = try token(connection)
            async let catalogue = api.fetch([DirectoryService].self, base: base, path: "api/services", token: credential)
            async let federation = api.fetch([FederationNode].self, base: base, path: "api/federation/nodes", token: credential)
            async let identity = api.fetch(InstanceInfo.self, base: base, path: "api/instance-info", token: nil)
            let (newServices, newNodes, info) = try await (catalogue, federation, identity)
            guard connection.id == self.connection?.id, refreshID == requestID else { return }
            services = newServices; nodes = newNodes; localOrigin = info.name
            error = nil; lastRefresh = Date()
            if let id = selectedService, !services.contains(where: { $0.id == id }) { selectedService = nil }
            // /api/health describes only the directory's OWN services. Never apply it to peer namesakes.
            let newHealth = try? await api.fetch([String: String].self, base: base, path: "api/health", token: credential)
            guard connection.id == self.connection?.id, refreshID == requestID else { return }
            health = newHealth ?? [:]
        } catch is CancellationError { }
        catch {
            guard connection.id == self.connection?.id, refreshID == requestID else { return }
            self.error = error.localizedDescription
        }
    }
    func healthLabel(_ service: DirectoryService) -> String {
        guard service.origin == localOrigin else { return "Health unknown" }
        switch health[service.name] {
        case "up": return "Up"
        case "down": return "Down"
        default: return "Health unknown"
        }
    }
    // Maintenance always targets the explicitly configured directory. A directory's
    // credentials are never sent to a discovered peer, even when its name matches.
    func loadMaintenance(action: String? = nil) async {
        guard let connection else { return }
        let requestID = UUID(); maintenanceID = requestID
        maintenanceBusy = true
        defer { if maintenanceID == requestID { maintenanceBusy = false } }
        do {
            let base = try URLPolicy.baseURL(connection.address)
            if action == "update" {
                let job = try await api.fetch(MaintenanceJob.self, base: base, path: "api/maintenance/update",
                                             token: token(connection, write: true), method: "POST")
                guard connection.id == self.connection?.id, requestID == maintenanceID else { return }
                maintenance?.job = job; maintenanceMessage = nil
                return
            }
            let state = try await api.fetch(MaintenanceState.self, base: base,
                path: "api/maintenance" + (action.map { "/\($0)" } ?? ""),
                token: token(connection, write: action != nil), method: action == nil ? "GET" : "POST")
            guard connection.id == self.connection?.id, requestID == maintenanceID else { return }
            maintenance = state; maintenanceMessage = nil
        } catch DirectoryError.http(404) {
            guard requestID == maintenanceID else { return }
            maintenance = nil
            maintenanceMessage = "This node does not yet support maintenance from the app. Its SSH upgrade command is available below."
        } catch {
            guard requestID == maintenanceID else { return }
            maintenanceMessage = error.localizedDescription
        }
    }
    func launch(tmux: Bool) {
        guard let shortcut else { return }
        do { try TerminalLauncher.open(shortcut, tmux: tmux) }
        catch { self.error = error.localizedDescription }
    }
}
