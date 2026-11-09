import SwiftUI
import WebKit
import DirectoryCore

@MainActor
private final class BrowserSession: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    @Published var error: String?
    @Published var address = ""
    @Published var loading = false
    private let onJSON: ((URL) -> Void)?
    private var popups: [NSWindow] = []
    init(url: URL, onJSON: ((URL) -> Void)?) {
        self.onJSON = onJSON
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loading = true; error = nil; address = webView.url?.absoluteString ?? ""
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loading = false; address = webView.url?.absoluteString ?? ""
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loading = false
        if (error as NSError).code != NSURLErrorCancelled { self.error = error.localizedDescription }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loading = false; self.error = error.localizedDescription
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        // Do not let service pages launch arbitrary native URL schemes or local files.
        if URLPolicy.webURL(url.absoluteString) != nil || url.absoluteString == "about:blank" {
            decisionHandler(.allow)
        } else {
            error = "This page requested an unsupported link. Use Open in Browser if its sign-in requires another app."
            decisionHandler(.cancel)
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if webView === self.webView, navigationResponse.isForMainFrame,
           JSONMediaType.matches(navigationResponse.response.mimeType),
           let url = navigationResponse.response.url, URLPolicy.webURL(url.absoluteString) != nil,
           let onJSON {
            onJSON(url)
            decisionHandler(.cancel)
        } else { decisionHandler(.allow) }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // OAuth popup flows need a real child window and the supplied configuration.
        let popup = WKWebView(frame: .zero, configuration: configuration)
        popup.navigationDelegate = self; popup.uiDelegate = self
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 720),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Service sign-in"; window.contentView = popup
        window.isReleasedWhenClosed = false
        popups.append(window); window.center(); window.makeKeyAndOrderFront(nil)
        return popup
    }
    func webViewDidClose(_ webView: WKWebView) { webView.window?.close() }
}

struct ServiceBrowser: View {
    let url: URL
    @StateObject private var session: BrowserSession
    init(url: URL, onJSON: ((URL) -> Void)? = nil) {
        self.url = url
        _session = StateObject(wrappedValue: BrowserSession(url: url, onJSON: onJSON))
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { session.webView.goBack() } label: { Image(systemName: "chevron.left") }.help("Back")
                Button { session.webView.goForward() } label: { Image(systemName: "chevron.right") }.help("Forward")
                Button { session.webView.reload() } label: { Image(systemName: "arrow.clockwise") }.help("Reload service")
                Text(session.address.isEmpty ? url.absoluteString : session.address)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                Spacer()
                if session.loading { ProgressView().controlSize(.small) }
                Button {
                    if let current = session.webView.url, URLPolicy.webURL(current.absoluteString) != nil {
                        NSWorkspace.shared.open(current)
                    }
                } label: { Image(systemName: "arrow.up.right.square") }.help("Open current page in browser")
            }.buttonStyle(.borderless).padding(10).background(.bar)
            if let error = session.error {
                Label(error, systemImage: "exclamationmark.triangle").font(.callout)
                    .padding().frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.1))
            }
            WebSurface(webView: session.webView)
        }
    }
}

private struct WebSurface: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) { }
}
