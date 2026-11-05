import Foundation
import Testing
@testable import DirectoryCore

@Test func realHTTPTransportAuthenticatesAndRefusesRedirects() async throws {
    // A real loopback fixture verifies URLSession delegate behavior, which a
    // URLProtocol mock would bypass. Never reaches the tailnet or a real service.
    let server = Process()
    server.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    server.arguments = ["python3", "-u", "-c", #"""
from http.server import HTTPServer, BaseHTTPRequestHandler
import json
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_): pass
    def do_GET(self):
        if self.path == '/api/redirect':
            self.send_response(302)
            self.send_header('Location', '/trap')
            self.end_headers()
        elif self.path == '/trap':
            self.send_response(200); self.end_headers(); self.wfile.write(b'[]')
        elif self.headers.get('Authorization') != 'Bearer fixture-token':
            self.send_response(401); self.end_headers()
        else:
            self.send_response(200); self.send_header('Content-Type', 'application/json')
            self.end_headers(); self.wfile.write(b'[{"name":"Service","origin":"node","links":[]}]')
s = HTTPServer(('127.0.0.1', 0), Handler)
print(s.server_port, flush=True)
s.serve_forever()
"""#]
    let pipe = Pipe(); server.standardOutput = pipe
    try server.run()
    defer { server.terminate(); server.waitUntilExit() }
    let output = pipe.fileHandleForReading.availableData
    let port = try #require(Int(String(data: output, encoding: .utf8)!.trimmingCharacters(in: .whitespacesAndNewlines)))
    let base = URL(string: "http://127.0.0.1:\(port)")!
    let api = DirectoryAPI()
    do {
        let _ = try await api.fetch([DirectoryService].self, base: base, path: "api/services", token: nil)
        Issue.record("Unauthenticated fixture request unexpectedly succeeded")
    } catch DirectoryError.unauthorized { }
    let catalogue = try await api.fetch([DirectoryService].self, base: base, path: "api/services", token: "fixture-token")
    #expect(catalogue.count == 1)
    do {
        let _ = try await api.fetch([DirectoryService].self, base: base, path: "api/redirect", token: "fixture-token")
        Issue.record("Directory request followed a redirect with its credential")
    } catch DirectoryError.http(302) { }
}
