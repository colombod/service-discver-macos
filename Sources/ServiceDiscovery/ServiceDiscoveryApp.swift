import SwiftUI

@main
struct ServiceDiscoveryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var model = AppModel()
    @StateObject private var updater = AppUpdater()
    @StateObject private var loginItem = LoginItemController()
    var body: some Scene {
        Window("Service Discovery", id: "directory") {
            DirectoryView(model: model)
                .frame(minWidth: 1050, minHeight: 650)
                .modifier(DirectoryReopenAction(delegate: delegate))
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
            CommandGroup(after: .appSettings) {
                LoginItemControls(loginItem: loginItem)
            }
            CommandGroup(after: .newItem) {
                Button("Refresh Directory") { Task { await model.refresh() } }
                    .keyboardShortcut("r")
            }
        }
        MenuBarExtra {
            MenuBarContent(model: model, updater: updater, loginItem: loginItem)
        } label: {
            Label("Services", systemImage: "server.rack")
                .labelStyle(.titleAndIcon)
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var openDirectory: (() -> Void)?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { openDirectory?() }
        return true
    }
}

private struct DirectoryReopenAction: ViewModifier {
    let delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow
    func body(content: Content) -> some View {
        content.onAppear {
            let action = openWindow
            delegate.openDirectory = { action(id: "directory") }
        }
    }
}
