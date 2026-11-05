import Foundation
import Testing
@testable import DirectoryCore

@Test func cataloguePreservesNamesakesAndOptionalMetadata() throws {
    let data = Data(#"[{"name":"muxplex","origin":"alpha","description":null,"links":[{"label":"Tailnet","host":"alpha.ts.net","url":"http://alpha.ts.net:8080"}]},{"name":"muxplex","origin":"beta","links":[]}]"#.utf8)
    let services = try JSONDecoder().decode([DirectoryService].self, from: data)
    #expect(services.count == 2)
    #expect(services[0].id != services[1].id)
    #expect(services[0].preferredURL?.host == "alpha.ts.net")
    #expect(services[1].preferredURL == nil)
}

@Test func peerVersionCanBeUnknown() throws {
    let node = try JSONDecoder().decode(FederationNode.self, from: Data(#"{"name":"peer","device_id":"abc","base_url":"http://peer","reachable":false,"version":null}"#.utf8))
    #expect(node.version == nil)
    #expect(!node.reachable)
}

@Test(arguments: ["file:///etc/passwd", "javascript:alert(1)", "ssh://root@server", "https://user:secret@node", "https:///", "https://node?token=secret", "https://node/#fragment"])
func invalidDirectoryAddressesAreRejected(_ address: String) {
    #expect(throws: (any Error).self) { try URLPolicy.baseURL(address) }
}

@Test func privateNetworkURLsAndOriginComparison() throws {
    #expect(try URLPolicy.baseURL(" http://100.100.1.2:8085 ").port == 8085)
    #expect(try URLPolicy.baseURL("http://[::1]:8085").host != nil)
    #expect(URLPolicy.sameOrigin(URL(string: "https://node")!, URL(string: "https://NODE:443/path")!))
    #expect(!URLPolicy.sameOrigin(URL(string: "https://node")!, URL(string: "http://node")!))
    #expect(!URLPolicy.sameOrigin(URL(string: "https://node")!, URL(string: "https://node:444")!))
}

@Test func requestKeepsTokenInHeaderAndBuildsPath() throws {
    let request = DirectoryAPI.request(base: try URLPolicy.baseURL("https://node/directory/"),
        path: "api/services", token: "private-value")
    #expect(request.url?.absoluteString == "https://node/directory/api/services")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer private-value")
    #expect(!(request.url?.absoluteString.contains("private-value") ?? true))
    let open = DirectoryAPI.request(base: URL(string: "http://node")!, path: "api/instance-info", token: nil)
    #expect(open.value(forHTTPHeaderField: "Authorization") == nil)
}

@Test(arguments: ["-oProxyCommand=touch", "node; touch /tmp/evil", "$(whoami)", "node\nwhoami", "user@host", "node name", "`id`", "node'", "node/../../"])
func shortcutRejectsInjectionAndSSHOptions(_ host: String) {
    #expect(throws: (any Error).self) { try TerminalShortcut(host: host).command(tmux: false) }
}

@Test func shortcutBuildsExplicitSSHAndRemoteTmux() throws {
    let shortcut = TerminalShortcut(host: "wintermute", user: "diego", port: 2222, session: "work")
    let command = try shortcut.command(tmux: true)
    #expect(command.hasPrefix("'/usr/bin/ssh' '-t' '-p' '2222' '-l' 'diego' '--' 'wintermute'"))
    #expect(command.contains("tmux new-session -A -s"))
    #expect(throws: (any Error).self) { try TerminalShortcut(host: "node", port: 0).command(tmux: false) }
    #expect(throws: (any Error).self) { try TerminalShortcut(host: "node", session: "-bad").command(tmux: true) }
    #expect(throws: (any Error).self) { try TerminalShortcut(host: "node", session: "a;id").command(tmux: true) }
    #expect(throws: (any Error).self) { try TerminalShortcut(host: "node", user: "root;id").command(tmux: false) }
}

@Test func shellQuoteRoundTripsUntrustedText() throws {
    let payload = "a' b\n$(printf injected); `printf injected`"
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", "printf '%s' " + TerminalShortcut.quote(payload)]
    process.standardOutput = pipe
    try process.run()
    let result = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
    #expect(result == payload)
}

@Test func maintenanceUnknownDoesNotMeanUpToDate() throws {
    let state = try JSONDecoder().decode(MaintenanceState.self, from: Data(#"{"version":"0.1.0","install_kind":"git","update_supported":false,"update_available":null,"unsupported_reason":"No worker"}"#.utf8))
    #expect(state.update_available == nil)
    #expect(!state.update_supported)
    let job = try JSONDecoder().decode(MaintenanceJob.self, from: Data(#"{"id":"abcd","status":"running","message":"Restarting","steps":["stop"]}"#.utf8))
    #expect(job.isActive)
}
