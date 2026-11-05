import SwiftUI
import Sparkle

@MainActor
final class AppUpdater: ObservableObject {
    private let controller: SPUStandardUpdaterController
    @Published var canCheck = false
    private var observation: NSKeyValueObservation?
    init() {
        // swift run is useful for development; updates only work in a packaged app.
        let packaged = Bundle.main.bundleURL.pathExtension == "app"
        controller = SPUStandardUpdaterController(startingUpdater: packaged, updaterDelegate: nil, userDriverDelegate: nil)
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
            Task { @MainActor in self?.canCheck = change.newValue ?? false }
        }
    }
    func check() { controller.checkForUpdates(nil) }
}

struct AppUpdateCommands: Commands {
    @ObservedObject var updater: AppUpdater
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for App Updates…") { updater.check() }.disabled(!updater.canCheck)
        }
    }
}
