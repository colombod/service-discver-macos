import Foundation

public struct TerminalShortcut: Codable, Equatable, Sendable {
    public var host: String = ""
    public var user: String = ""
    public var port: Int = 22
    public var session: String = "main"
    public init(host: String = "", user: String = "", port: Int = 22, session: String = "main") {
        self.host = host; self.user = user; self.port = port; self.session = session
    }
    public static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    public func command(tmux: Bool) throws -> String {
        func valid(_ text: String, characters: String) -> Bool {
            !text.isEmpty && !text.hasPrefix("-") && text.unicodeScalars.allSatisfy {
                CharacterSet(charactersIn: characters).contains($0)
            }
        }
        let alphanumeric = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        guard valid(host, characters: alphanumeric + ".-_:") else {
            throw DirectoryError.invalidShortcut("Use a hostname, IPv4/IPv6 address, or SSH config alias without spaces or shell syntax.")
        }
        guard user.isEmpty || valid(user, characters: alphanumeric + "._-") else {
            throw DirectoryError.invalidShortcut("The SSH user contains unsupported characters.")
        }
        guard (1...65535).contains(port) else { throw DirectoryError.invalidShortcut("SSH port must be between 1 and 65535.") }
        if tmux && !valid(session, characters: alphanumeric + "_-") {
            throw DirectoryError.invalidShortcut("Use letters, numbers, underscores, or hyphens for the tmux session name.")
        }
        var args = ["/usr/bin/ssh"]
        if tmux { args.append("-t") }
        args += ["-p", String(port)]
        if !user.isEmpty { args += ["-l", user] }
        args += ["--", host]
        if tmux { args.append("tmux new-session -A -s \(Self.quote(session))") }
        return args.map(Self.quote).joined(separator: " ")
    }
}
