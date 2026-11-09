import Foundation
import Testing
@testable import DirectoryCore

@Test func healthCredentialsRequireTheSameDirectoryAddress() throws {
    let base = try URLPolicy.baseURL("https://node/directory/")
    #expect(HealthTarget.credentialKey(base) == HealthTarget.credentialKey(URL(string: "https://NODE:443/directory")!))
    for other in ["http://node/directory", "https://node:444/directory", "https://other/directory", "https://node/other"] {
        #expect(HealthTarget.credentialKey(base) != HealthTarget.credentialKey(URL(string: other)!))
    }
}

@Test func registeredHealthEndpointTakesPriorityOverBrowserAddress() async throws {
    let service = try JSONDecoder().decode(DirectoryService.self, from: Data(#"""
    {"name":"Plex Media Server","origin":"wintermute",
     "links":[{"label":"Tailnet","url":"http://wintermute:32400/"}],
     "health_url":"http://wintermute:32400/identity"}
    """#.utf8))
    #expect(service.preferredURL?.path == "/")
    #expect(service.healthProbeURL?.path == "/identity")
    let withoutHealth = try JSONDecoder().decode(DirectoryService.self, from: Data(#"""
    {"name":"Web service","links":[{"label":"Web","url":"https://node/"}]}
    """#.utf8))
    #expect(withoutHealth.healthProbeURL == withoutHealth.preferredURL)
}

@Test func healthIsScopedByNodeAndNeverBorrowsAnotherNodesToken() async throws {
    let server = Process()
    server.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    server.arguments = ["python3", "-u", "-c", #"""
from http.server import HTTPServer, BaseHTTPRequestHandler
import json
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_): pass
    def do_HEAD(self):
        status = {'/proxy-down':502, '/auth':401, '/healthy':200, '/head-unsupported':405, '/redirect':302}.get(self.path,404)
        if self.headers.get('Authorization') or self.headers.get('Cookie'): status = 418
        self.send_response(status)
        if status == 302: self.send_header('Location','http://127.0.0.1:1/not-followed')
        self.end_headers()
    def do_GET(self):
        node = self.path.split('/')[1]
        token = self.headers.get('Authorization')
        if self.path.endswith('/instance-info'):
            if token is not None:
                self.send_response(400); self.end_headers(); return
            data = {'name':node, 'device_id':node+'-device', 'version':'1', 'federation_enabled':True}
        elif self.path.endswith('/health'):
            expected = {'alpha':'Bearer alpha-secret', 'beta':None, 'gated':'Bearer gated-secret'}
            if node not in expected or token != expected[node]:
                self.send_response(401); self.end_headers(); return
            data = {'Namesake':'down' if node == 'beta' else 'up'}
        else:
            self.send_response(404); self.end_headers(); return
        self.send_response(200); self.end_headers(); self.wfile.write(json.dumps(data).encode())
s = HTTPServer(('127.0.0.1',0),Handler)
print(s.server_port,flush=True)
s.serve_forever()
"""#]
    let pipe = Pipe(); server.standardOutput = pipe
    try server.run()
    defer { server.terminate(); server.waitUntilExit() }
    let output = pipe.fileHandleForReading.availableData
    let port = try #require(Int(String(data: output, encoding: .utf8)!.trimmingCharacters(in: .whitespacesAndNewlines)))
    func target(_ name: String, token: String?, deviceID: String? = nil) -> HealthTarget {
        HealthTarget(origin: name, deviceID: deviceID ?? name + "-device",
                     base: URL(string: "http://127.0.0.1:\(port)/\(name)")!, token: token)
    }
    let api = DirectoryAPI()
    let health = await FederationHealth.fetch([
        target("alpha", token: "alpha-secret"), target("beta", token: nil),
        target("gated", token: nil), target("impostor", token: nil, deviceID: "different-device")
    ], api: api)
    #expect(health["alpha"]?["Namesake"] == "up")
    #expect(health["beta"]?["Namesake"] == "down")
    #expect(health["gated"] == nil)
    #expect(health["impostor"] == nil)
    let authenticated = await FederationHealth.fetch([target("gated", token: "gated-secret")], api: api)
    #expect(authenticated["gated"]?["Namesake"] == "up")
    let root = URL(string: "http://127.0.0.1:\(port)")!
    for (path, expected) in [("proxy-down", "down"), ("auth", "signin"), ("healthy", "up"), ("head-unsupported", "up"), ("redirect", "up")] {
        #expect(await api.serviceAvailability(root.appendingPathComponent(path)) == expected)
    }
    let checked = await FederationHealth.fetch([
        HealthTarget(origin: "alpha", deviceID: "alpha-device", base: root.appendingPathComponent("alpha"),
                     token: "alpha-secret", serviceURLs: ["Namesake": root.appendingPathComponent("proxy-down")])
    ], api: api)
    #expect(checked["alpha"]?["Namesake"] == "down")
}

private final class CertificateFailureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.serverCertificateUntrusted)) }
    override func stopLoading() { }
}

@Test func browserFacingHealthRejectsUntrustedCertificates() async {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [CertificateFailureProtocol.self]
    let session = URLSession(configuration: config)
    defer { session.invalidateAndCancel() }
    let api = DirectoryAPI(session: session)
    #expect(await api.serviceAvailability(URL(string: "https://untrusted.invalid")!) == "tls_error")
}
