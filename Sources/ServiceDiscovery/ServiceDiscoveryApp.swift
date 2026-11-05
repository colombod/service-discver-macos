import SwiftUI

@main
struct ServiceDiscoveryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var model = AppModel()
    @StateObject private var updater = AppUpdater()
    var body: some Scene {
        WindowGroup {
            DirectoryView(model: model)
                .frame(minWidth: 1050, minHeight: 650)
                .task(id: model.connection) {
                    await model.refresh()
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .seconds(30)) } catch { return }
                        await model.refresh()
                    }
                }
        }
        .defaultSize(width: 1300, height: 820)
        .commands {
            AppUpdateCommands(updater: updater)
            CommandGroup(after: .newItem) {
                Button("Refresh Directory") { Task { await model.refresh() } }
                    .keyboardShortcut("r")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
