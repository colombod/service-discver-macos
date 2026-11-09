import Foundation
import Testing
@testable import DirectoryCore

@Test func jsonTransportPreservesStatusAndIsolatesCookiesAndRedirects() async throws {
    let server = Process()
    server.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    server.arguments = ["python3", "-u", "-c", #"""
from http.server import HTTPServer, BaseHTTPRequestHandler
import json
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_): pass
    def do_GET(self):
        status = 200
        headers = {}
        body = json.dumps({'cookie':self.headers.get('Cookie'), 'authorization':self.headers.get('Authorization')}).encode()
        if self.path == '/api/redirect':
            status = 302; headers['Location'] = '/trap'
        elif self.path == '/api/error':
            status = 503; body = b'{"detail":"temporarily unavailable"}'
        elif self.path == '/api/too-large':
            headers['Content-Length'] = '5000000'; body = b' '
        elif self.path == '/api/stream-too-large':
            body = b' ' * (4 * 1024 * 1024 + 64)
        elif self.path == '/api/status':
            headers['Set-Cookie'] = 'rotated=updated; Path=/api; HttpOnly'
        self.send_response(status)
        self.send_header('Content-Type','application/problem+json')
        for key,value in headers.items(): self.send_header(key,value)
        self.end_headers()
        try: self.wfile.write(body)
        except (BrokenPipeError,ConnectionResetError): pass
s = HTTPServer(('127.0.0.1',0),Handler)
print(s.server_port,flush=True)
s.serve_forever()
"""#]
    let pipe = Pipe(); server.standardOutput = pipe
    try server.run()
    defer { server.terminate(); server.waitUntilExit() }
    let port = try #require(Int(String(data: pipe.fileHandleForReading.availableData, encoding:.utf8)!.trimmingCharacters(in:.whitespacesAndNewlines)))
    let base = URL(string:"http://127.0.0.1:\(port)")!
    let own = HTTPCookie(properties:[.name:"service",.value:"site-session",.domain:"127.0.0.1",.path:"/api"])!
    let other = HTTPCookie(properties:[.name:"other",.value:"private",.domain:"other.invalid",.path:"/"])!
    let client = JSONEndpointClient()
    let response = try await client.fetch(base.appendingPathComponent("api/status"), cookies:[own,other])
    let payload = try #require(JSONSerialization.jsonObject(with:response.data) as? [String:Any])
    #expect(payload["cookie"] as? String == "service=site-session")
    #expect(payload["authorization"] is NSNull)
    #expect(response.cookies.first?.name == "rotated")
    #expect(JSONMediaType.matches(response.mimeType))
    let redirect = try await client.fetch(base.appendingPathComponent("api/redirect"), cookies:[own])
    #expect(redirect.status == 302)
    let error = try await client.fetch(base.appendingPathComponent("api/error"))
    #expect(error.status == 503)
    #expect(try JSONDocument(data:error.data).nodes.contains { $0.text == "temporarily unavailable" })
    for path in ["api/too-large", "api/stream-too-large"] {
        do {
            _ = try await client.fetch(base.appendingPathComponent(path))
            Issue.record("Oversized JSON response unexpectedly accepted")
        } catch JSONDisplayError.tooLarge { }
    }
}
