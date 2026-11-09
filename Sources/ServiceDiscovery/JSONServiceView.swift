import SwiftUI
import WebKit
import DirectoryCore

@MainActor @Observable
private final class JSONServiceModel {
    var document: JSONDocument?
    var loading = false
    var error: String?
    var status: Int?
    var lastUpdated: Date?
    var stale = false
    private let client = JSONEndpointClient()

    func refresh(_ url: URL) async {
        guard !loading else { return }
        loading = true
        status = nil
        defer { loading = false }
        do {
            let store = WKWebsiteDataStore.default().httpCookieStore
            let cookies = await withCheckedContinuation { continuation in
                store.getAllCookies { continuation.resume(returning: $0) }
            }
            try Task.checkCancellation()
            let response = try await client.fetch(url, cookies: cookies)
            try Task.checkCancellation()
            status = response.status
            for cookie in response.cookies { await store.setCookie(cookie) }
            if (300..<400).contains(response.status) {
                throw ViewerError("The service redirected this request. Use Web to complete sign-in, then retry JSON.")
            }
            let parsed: JSONDocument
            do {
                parsed = try await Task.detached(priority: .userInitiated) {
                    try JSONDocument(data: response.data)
                }.value
            } catch {
                if [401, 403].contains(response.status) {
                    throw ViewerError("Sign-in required (HTTP \(response.status)). Use Web to sign in to this service, then retry JSON.")
                }
                if !(200..<300).contains(response.status) {
                    throw ViewerError("The service returned HTTP \(response.status) rather than a JSON response.")
                }
                throw error
            }
            try Task.checkCancellation()
            document = parsed; lastUpdated = Date(); stale = false
            if [401, 403].contains(response.status) {
                error = "Sign-in required (HTTP \(response.status)). Use Web to sign in, then retry JSON. The error response is shown below."
            } else {
                error = (200..<300).contains(response.status) ? nil : "The service returned HTTP \(response.status). Its JSON error response is shown below."
            }
        } catch is CancellationError { }
        catch let error as URLError where error.code == .cancelled { }
        catch {
            self.error = error.localizedDescription
            stale = document != nil
        }
    }
}

private struct ViewerError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct JSONServiceView: View {
    let url: URL
    private let interval: Int
    @State private var model = JSONServiceModel()
    @State private var autoRefresh: Bool
    @State private var format = JSONFormat.tree
    @State private var expanded: Set<String> = []
    @State private var query = ""
    @State private var copied = false

    init(url: URL, refreshSeconds: Int?) {
        self.url = url
        self.interval = min(3600, max(2, refreshSeconds ?? 30))
        _autoRefresh = State(initialValue: (refreshSeconds ?? 0) > 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            viewerToolbar
            if let error = model.error {
                VStack(alignment: .leading, spacing: 5) {
                    Label(error, systemImage: "exclamationmark.triangle")
                    if model.stale { Text("Showing the last successful response.").font(.caption) }
                }.font(.callout).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.12))
            }
            if let document = model.document {
                if !document.summaryNodes.isEmpty { summary(document) }
                if format == .tree { tree(document) }
                else { JSONTextSurface(text: document.formattedText) }
                footer(document)
            } else if model.loading {
                ProgressView("Loading JSON…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("No JSON response", systemImage: "curlybraces",
                    description: Text("Retry the request or switch to Web if this endpoint needs a browser sign-in."))
            }
        }
        .task(id: url) {
            await model.refresh(url)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(interval)) } catch { return }
                if autoRefresh { await model.refresh(url) }
            }
        }
        .onChange(of: model.lastUpdated) { _, _ in copied = false }
    }

    private var viewerToolbar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label("JSON", systemImage: "curlybraces").font(.headline)
                if let status = model.status {
                    Text("HTTP \(status)").font(.caption.monospaced())
                        .foregroundStyle((200..<300).contains(status) ? .green : .orange)
                }
                Spacer()
                if model.loading { ProgressView().controlSize(.small) }
                Button { Task { await model.refresh(url) } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .disabled(model.loading)
                Button {
                    guard let document = model.document else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(document.originalText, forType: .string)
                    copied = true
                } label: { Label(copied ? "Copied" : "Copy JSON", systemImage: copied ? "checkmark" : "doc.on.doc") }
                    .disabled(model.document == nil)
            }
            Text(url.absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                .truncationMode(.middle).textSelection(.enabled)
            HStack {
                Picker("JSON format", selection: $format) {
                    Text("Tree").tag(JSONFormat.tree)
                    Text("Formatted").tag(JSONFormat.formatted)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 180)
                Spacer()
                Toggle("Auto-refresh · \(interval)s", isOn: $autoRefresh).toggleStyle(.checkbox).font(.caption)
            }
        }.padding(12).background(.bar)
    }

    private func summary(_ document: JSONDocument) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), alignment: .leading, spacing: 8) {
            ForEach(document.summaryNodes) { node in
                VStack(alignment: .leading, spacing: 5) {
                    Text(node.key == "uptime_seconds" ? "Uptime" : node.key.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Text(summaryText(node)).font(.system(.body, design: .monospaced).weight(.semibold))
                        .lineLimit(1).textSelection(.enabled).help(String(node.text.prefix(4000)))
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
            }
        }.padding(12)
    }

    private func tree(_ document: JSONDocument) -> some View {
        let rows = document.visibleNodes(expanded: expanded, query: query)
        return VStack(spacing: 0) {
            HStack {
                TextField("Search keys and values", text: $query).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("json-search")
                Button("Expand All") { expanded = Set(document.nodes.filter(\.isExpandable).map(\.id)) }
                Button("Collapse All") { expanded = [] }
            }.padding(.horizontal, 12).padding(.bottom, 10)
            Table(rows) {
                TableColumn("Field") { node in
                    HStack(spacing: 5) {
                        if node.isExpandable {
                            Button {
                                if !expanded.insert(node.id).inserted { expanded.remove(node.id) }
                            } label: {
                                Image(systemName: !query.isEmpty || expanded.contains(node.id) ? "chevron.down" : "chevron.right")
                                    .font(.caption2).frame(width: 12)
                            }.buttonStyle(.plain).disabled(!query.isEmpty)
                                .accessibilityLabel("\(expanded.contains(node.id) ? "Collapse" : "Expand") \(node.displayKey)")
                        } else { Color.clear.frame(width: 12, height: 1) }
                        Text(node.displayKey).font(.system(.callout, design: .monospaced)).lineLimit(1)
                            .textSelection(.enabled).help(node.id.isEmpty ? "$" : node.id)
                    }.padding(.leading, CGFloat(min(12, max(0, node.depth - 1))) * 12)
                }.width(min: 180, ideal: 250)
                TableColumn("Value") { node in
                    Text(node.kind == .string ? "\"\(String(node.text.prefix(1024)))\"" : String(node.text.prefix(1024)))
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(valueColor(node.kind)).lineLimit(2).textSelection(.enabled)
                        .help(String(node.text.prefix(4000)))
                        .contextMenu {
                            Button("Copy Path") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(node.id.isEmpty ? "$" : node.id, forType: .string)
                            }
                            if node.kind != .object && node.kind != .array {
                                Button("Copy Value") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(node.text, forType: .string)
                                }
                            }
                        }
                }.width(min: 150, ideal: 350)
            }
            if rows.isEmpty { Text("No matching keys or values").font(.callout).foregroundStyle(.secondary).padding() }
        }
    }

    private func footer(_ document: JSONDocument) -> some View {
        HStack {
            Text("\(document.nodes.count) values · \(ByteCountFormatter.string(fromByteCount: Int64(document.byteCount), countStyle: .file))")
            Spacer()
            if let updated = model.lastUpdated {
                Text("\(model.stale ? "Last success" : "Updated") \(updated.formatted(date: .omitted, time: .standard))")
            }
        }.font(.caption2).foregroundStyle(.secondary).padding(10).background(.bar)
    }

    private func valueColor(_ kind: JSONKind) -> Color {
        switch kind {
        case .boolean: return .purple
        case .number: return .blue
        case .null, .object, .array: return .secondary
        case .string: return .primary
        }
    }

    private func summaryText(_ node: JSONNode) -> String {
        guard node.key == "uptime_seconds", let seconds = Double(node.text), seconds.isFinite,
              seconds >= 0, let total = Int(exactly: seconds.rounded(.towardZero)) else {
            return String(node.text.prefix(160))
        }
        if total >= 86_400 { return "\(total / 86_400)d \((total % 86_400) / 3600)h" }
        if total >= 3600 { return "\(total / 3600)h \((total % 3600) / 60)m" }
        if total >= 60 { return "\(total / 60)m \(total % 60)s" }
        return "\(total)s"
    }
}

private enum JSONFormat: Hashable { case tree, formatted }

private struct JSONTextSurface: NSViewRepresentable {
    let text: String
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        let view = NSTextView()
        view.isEditable = false; view.isSelectable = true; view.isRichText = false
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        view.textColor = .textColor; view.backgroundColor = .textBackgroundColor
        view.textContainerInset = NSSize(width: 14, height: 14)
        view.isHorizontallyResizable = true; view.isVerticallyResizable = true
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = view
        view.string = text
        return scroll
    }
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let view = nsView.documentView as? NSTextView, view.string != text else { return }
        let offset = nsView.contentView.bounds.origin
        view.string = text
        nsView.contentView.scroll(to: offset)
    }
}
