import SwiftUI
import DirectoryCore

private enum Editor: Identifiable {
    case connection(DirectoryConnection), shortcut(String, TerminalShortcut), maintenance
    var id: String {
        switch self {
        case .connection(let c): return c.id.uuidString
        case .shortcut(let key, _): return key
        case .maintenance: return "maintenance"
        }
    }
}

struct DirectoryView: View {
    @Bindable var model: AppModel
    @State private var editor: Editor?
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                connectionSelector
                List(selection: $model.selectedNode) {
                    Label("All services", systemImage: "square.grid.2x2").tag(Optional<String>.none)
                    Section("Federation") {
                        ForEach(model.origins, id: \.self) { origin in
                            HStack {
                                Image(systemName: "server.rack")
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(origin).lineLimit(1)
                                    if let node = model.nodes.first(where: { $0.name == origin }) {
                                        Text(node.reachable ? "Reachable from directory" : "Unreachable from directory")
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text("\(model.services.filter { $0.origin == origin }.count)")
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }.tag(Optional(origin))
                        }
                    }
                }.listStyle(.sidebar)
                sidebarFooter
            }
            .navigationTitle("Systems")
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 350)
        } content: {
            VStack(spacing: 0) {
                if model.connection == nil {
                    ContentUnavailableView {
                        Label("Connect your directory", systemImage: "network")
                    } description: {
                        Text("Add one Service Directory URL to browse its federated systems and hosted services.")
                    } actions: {
                        Button("Add Directory") { addConnection() }.buttonStyle(.borderedProminent)
                    }
                } else {
                    nodeActions
                    if let error = model.error {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(error, systemImage: "exclamationmark.triangle")
                            if model.lastRefresh != nil { Text("Showing the last successful snapshot.").font(.caption) }
                            Button("Retry") { Task { await model.refresh() } }
                        }.font(.callout).padding().frame(maxWidth: .infinity, alignment: .leading)
                            .background(.orange.opacity(0.12))
                    }
                    if model.filteredServices.isEmpty && !model.loading {
                        ContentUnavailableView("No services found", systemImage: "magnifyingglass",
                                               description: Text("Try another system or search, or refresh the directory."))
                    } else {
                        List(model.filteredServices, selection: $model.selectedService) { service in
                            ServiceRow(service: service, health: model.healthLabel(service))
                                .tag(service.id)
                                .padding(.vertical, 7)
                        }.listStyle(.inset)
                    }
                }
            }
            .navigationTitle(model.selectedNode ?? "All services")
            .navigationSubtitle("\(model.filteredServices.count) services")
            .searchable(text: $model.query, prompt: "Find services")
            .navigationSplitViewColumnWidth(min: 300, ideal: 350, max: 500)
        } detail: {
            if let service = model.currentService {
                ServiceDetail(service: service).id(service.id)
            } else {
                ContentUnavailableView("Your systems, one place", systemImage: "rectangle.connected.to.line.below",
                                       description: Text("Choose a service to open it here, or select a system for SSH and tmux shortcuts."))
            }
        }
        .toolbar {
            ToolbarItem {
                if model.loading { ProgressView().controlSize(.small) }
                else { Button { Task { await model.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") } }
            }
        }
        .sheet(item: $editor) { item in
            switch item {
            case .connection(let connection): ConnectionEditor(model: model, connection: connection)
            case .shortcut(let key, let shortcut): ShortcutEditor(model: model, storageKey: key, initial: shortcut)
            case .maintenance: MaintenanceView(model: model)
            }
        }
        .onChange(of: model.selectedNode) { _, _ in model.selectedService = nil }
    }
    private var connectionSelector: some View {
        HStack {
            Picker("Directory", selection: Binding(get: { model.connection?.id }, set: { model.selectConnection($0) })) {
                if model.preferences.connections.isEmpty { Text("No directories").tag(Optional<UUID>.none) }
                ForEach(model.preferences.connections) { Text($0.name).tag(Optional($0.id)) }
            }.labelsHidden()
            Button { addConnection() } label: { Image(systemName: "plus") }.help("Add directory")
            if let connection = model.connection {
                Button { editor = .connection(connection) } label: { Image(systemName: "pencil") }.help("Edit directory and credentials")
            }
        }.padding(12)
    }
    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.connection != nil {
                Button { editor = .maintenance } label: { Label("Directory maintenance", systemImage: "arrow.down.circle") }
                if let date = model.lastRefresh {
                    Text("Updated \(date.formatted(date: .omitted, time: .shortened)) · refreshes every 30s")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder private var nodeActions: some View {
        if let node = model.currentNode, let key = model.shortcutKey {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(node.name, systemImage: "server.rack").font(.headline)
                    Spacer()
                    Text(node.version.map { "v\($0)" } ?? "Version unknown").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("SSH") { model.launch(tmux: false) }.disabled(model.shortcut == nil)
                    Button("tmux") { model.launch(tmux: true) }.disabled(model.shortcut == nil)
                    Spacer()
                    Button("Configure…") {
                        editor = .shortcut(key, model.shortcut ?? TerminalShortcut(host: URL(string: node.base_url)?.host ?? ""))
                    }
                }
            }.padding().background(.quaternary.opacity(0.4))
        }
    }
    private func addConnection() { editor = .connection(DirectoryConnection(name: "My directory", address: "")) }
}

private struct ServiceRow: View {
    let service: DirectoryService
    let health: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "app.connected.to.app.below.fill").font(.title2).foregroundStyle(.tint).frame(width: 28)
            VStack(alignment: .leading, spacing: 5) {
                Text(service.name).font(.headline)
                Text(service.description ?? "Hosted service").font(.callout).foregroundStyle(.secondary).lineLimit(2)
                HStack {
                    Text(service.origin ?? "Local")
                    Spacer()
                    Text(health).foregroundStyle(health == "Up" ? .green : health == "Down" ? .orange : .secondary)
                }.font(.caption)
            }
        }
    }
}

private struct ServiceDetail: View {
    let service: DirectoryService
    @State private var openedURL: URL?
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(service.name).font(.title2.bold())
                        Text([service.origin, service.category].compactMap { $0 }.joined(separator: " · "))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let url = openedURL ?? service.preferredURL {
                        Button { NSWorkspace.shared.open(url) } label: { Label("Browser", systemImage: "arrow.up.right.square") }
                            .help("Open in the default browser, which uses its own login sessions")
                    }
                }
                if let description = service.description, !description.isEmpty { Text(description).font(.callout) }
                HStack {
                    if let url = service.preferredURL {
                        Button("Open Service") { openedURL = url }.buttonStyle(.borderedProminent)
                    }
                    if !service.links.isEmpty {
                        Menu("Addresses") {
                            ForEach(Array(service.links.enumerated()), id: \.offset) { _, link in
                                if let url = link.webURL { Button("\(link.label) · \(url.host ?? "")") { openedURL = url } }
                            }
                        }
                    }
                    if let docs = service.docs_url.flatMap(URLPolicy.webURL) {
                        Link("Documentation", destination: docs)
                    }
                }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            if let url = openedURL { ServiceBrowser(url: url).id(url) }
            else {
                ContentUnavailableView("Open \(service.name)", systemImage: "globe",
                    description: Text("Sign in to this service once. The app retains its website session across launches, until the service expires it."))
            }
        }
    }
}
