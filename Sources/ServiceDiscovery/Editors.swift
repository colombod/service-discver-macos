import SwiftUI
import DirectoryCore

struct ConnectionEditor: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var connection: DirectoryConnection
    @State private var readToken = ""
    @State private var writeToken = ""
    @State private var error: String?
    @State private var credentialsLoaded = false
    @State private var confirmRemoval = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Directory connection").font(.title2.bold())
            Form {
                TextField("Name", text: $connection.name)
                TextField("Directory URL", text: $connection.address, prompt: Text("https://node.your-tailnet.ts.net"))
                SecureField("Read peer token (optional)", text: $readToken)
                SecureField("Maintenance write token (optional)", text: $writeToken)
            }.textFieldStyle(.roundedBorder)
            Text("Use your LAN or Tailscale directory URL. Credentials are stored in macOS Keychain and sent only to this directory. Leave the read token empty for an open catalogue.")
                .font(.callout).foregroundStyle(.secondary)
            Text("Hosted services have their own sign-ins. The directory token does not sign you into them.")
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                if model.preferences.connections.contains(where: { $0.id == connection.id }) {
                    Button("Remove…", role: .destructive) { confirmRemoval = true }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    do {
                        try model.saveConnection(connection, readToken: readToken, writeToken: writeToken)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction).disabled(!credentialsLoaded || connection.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }.padding(24).frame(width: 570)
        .task {
            do {
                readToken = try model.token(connection) ?? ""
                writeToken = try model.token(connection, write: true) ?? ""
                credentialsLoaded = true
            } catch { self.error = error.localizedDescription }
        }
        .confirmationDialog("Remove this directory and its saved credentials?", isPresented: $confirmRemoval) {
            Button("Remove Directory", role: .destructive) {
                do { try model.removeConnection(connection.id); dismiss() } catch { self.error = error.localizedDescription }
            }
        }
    }
}

struct ShortcutEditor: View {
    let model: AppModel
    let storageKey: String
    let initial: TerminalShortcut
    @Environment(\.dismiss) private var dismiss
    @State private var shortcut = TerminalShortcut()
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("System shortcuts").font(.title2.bold())
            Form {
                TextField("SSH host or config alias", text: $shortcut.host)
                TextField("SSH user (optional)", text: $shortcut.user)
                TextField("SSH port", value: $shortcut.port, format: .number.grouping(.never))
                TextField("tmux session", text: $shortcut.session)
            }.textFieldStyle(.roundedBorder)
            Text("SSH opens in Terminal using your existing SSH config, keys, and agent. tmux connects over SSH, attaches to the named session, or creates it when needed. tmux must be installed on the remote system.")
                .font(.callout).foregroundStyle(.secondary)
            if let command = try? shortcut.command(tmux: true) {
                Text(command).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary)
            }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                if model.preferences.shortcuts[storageKey] != nil {
                    Button("Remove", role: .destructive) {
                        model.preferences.shortcuts.removeValue(forKey: storageKey)
                        do { try model.save(); dismiss() } catch { self.error = error.localizedDescription }
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save Shortcuts") {
                    do {
                        _ = try shortcut.command(tmux: true)
                        model.preferences.shortcuts[storageKey] = shortcut
                        try model.save(); dismiss()
                    } catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 570).onAppear { shortcut = initial }
    }
}

struct MaintenanceView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmUpdate = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Directory maintenance").font(.title2.bold())
            Text(model.connection?.name ?? "Directory").font(.headline)
            Text(model.connection?.address ?? "").foregroundStyle(.secondary).textSelection(.enabled)
            Text("This manages the connected directory. To manage a different system, add its directory URL with its own credentials.")
                .font(.callout).foregroundStyle(.secondary)
            if let state = model.maintenance {
                LabeledContent("Running version", value: state.version)
                LabeledContent("Installation", value: state.install_kind)
                LabeledContent("Update", value: state.update_available.map { $0 ? "Available" : "Up to date" } ?? "Not checked / unknown")
                if let latest = state.latest_version { LabeledContent("Latest version", value: latest) }
                if let reason = state.unsupported_reason { Text(reason).font(.callout).foregroundStyle(.secondary) }
                if let job = state.job {
                    GroupBox("Update \(job.status)") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(job.message)
                            Text(job.steps.joined(separator: " → ")).font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                HStack {
                    Button("Check for Updates") { Task { await model.loadMaintenance(action: "check") } }
                    Button("Update Directory…") { confirmUpdate = true }
                        .disabled(!state.update_supported || state.job?.isActive == true)
                }.disabled(model.maintenanceBusy)
            }
            if let message = model.maintenanceMessage { Text(message).font(.callout).textSelection(.enabled) }
            GroupBox("Upgrade over SSH") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("On the remote system, run:").foregroundStyle(.secondary)
                    Text("service-directory upgrade").font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    Text("Open the system’s configured SSH shortcut to run it. The app never runs updates automatically.")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                if model.maintenanceBusy { ProgressView().controlSize(.small) }
                Button("Refresh Status") { Task { await model.loadMaintenance() } }.disabled(model.maintenanceBusy)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(24).frame(width: 590)
        .task {
            await model.loadMaintenance()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                if model.maintenance?.job?.isActive == true { await model.loadMaintenance() }
            }
        }
        .confirmationDialog("Update \(model.connection?.name ?? "directory")?", isPresented: $confirmUpdate) {
            Button("Update and Restart Directory") { Task { await model.loadMaintenance(action: "update") } }
        } message: {
            Text("The node will install from its configured source and briefly disconnect while restarting. Hosted services are managed separately.")
        }
    }
}
