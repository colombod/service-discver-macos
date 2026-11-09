import SwiftUI
import ServiceManagement
import Combine

@MainActor
final class LoginItemController: ObservableObject {
    @Published private(set) var status = SMAppService.mainApp.status
    @Published private(set) var error: String?
    private var activation: AnyCancellable?

    init() {
        activation = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.refresh() }
    }

    var requested: Bool { status == .enabled || status == .requiresApproval }
    func refresh() { status = SMAppService.mainApp.status }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch {
            self.error = "Login startup: \(error.localizedDescription)"
        }
        refresh()
    }
}

struct MenuBarContent: View {
    let model: AppModel
    @ObservedObject var updater: AppUpdater
    @ObservedObject var loginItem: LoginItemController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Service Discovery") {
            openWindow(id: "directory")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }.keyboardShortcut("o")
        if let connection = model.connection {
            Text(connection.name)
            Text("\(model.services.count) services · \(model.nodes.count) systems")
        }
        Divider()
        LoginItemControls(loginItem: loginItem)
        Button("Check for App Updates…") { updater.check() }.disabled(!updater.canCheck)
        Divider()
        Button("Quit Service Discovery") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
    }
}

struct LoginItemControls: View {
    @ObservedObject var loginItem: LoginItemController
    var body: some View {
        Toggle("Start at Login", isOn: Binding(
            get: { loginItem.requested },
            set: { loginItem.setEnabled($0) }
        ))
        if loginItem.status == .requiresApproval {
            Button("Approve Start at Login…") { SMAppService.openSystemSettingsLoginItems() }
        }
        if let error = loginItem.error { Text(error) }
    }
}
