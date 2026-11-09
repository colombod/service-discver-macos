import Foundation
import Testing
@testable import DirectoryCore

@Test func jsonTreePreservesTypesPathsAndOriginalText() throws {
    let source = #" {"status":"healthy","metrics":{"ready":true,"count":1,"fraction":1.5},"sessions":[{"id":"alpha"}],"a/b":{"~key":null},"":"<script>alert(1)</script>"} "#
    let document = try JSONDocument(data: Data(source.utf8))
    #expect(document.originalText == source)
    #expect(document.nodes.first { $0.id == "/metrics/ready" }?.kind == .boolean)
    #expect(document.nodes.first { $0.id == "/metrics/count" }?.kind == .number)
    #expect(document.nodes.first { $0.id == "/metrics/count" }?.text == "1")
    #expect(document.nodes.first { $0.id == "/a~1b/~0key" }?.kind == .null)
    #expect(document.nodes.first { $0.id == "/" }?.text == "<script>alert(1)</script>")
    #expect(document.nodes.first { $0.id == "/sessions" }?.childCount == 1)
    #expect(document.formattedText.contains("\n"))
    #expect(try JSONSerialization.jsonObject(with: Data(document.formattedText.utf8)) as? NSDictionary != nil)
}

@Test func jsonExpansionAndSearchRetainContext() throws {
    let document = try JSONDocument(data: Data(#"{"status":"ok","metrics":{"count":7},"sessions":[{"last_event":"flush","secret":"not-a-match"}]}"#.utf8))
    let collapsed = document.visibleNodes(expanded: [], query: "")
    #expect(Set(collapsed.map(\.id)) == ["/status", "/metrics", "/sessions"])
    let expanded = document.visibleNodes(expanded: ["/sessions", "/sessions/0"], query: "")
    #expect(expanded.contains { $0.id == "/sessions/0/last_event" })
    #expect(!expanded.contains { $0.id == "/metrics/count" })
    let searched = document.visibleNodes(expanded: [], query: " FLUSH ")
    #expect(searched.map(\.id) == ["/sessions", "/sessions/0", "/sessions/0/last_event"])
    #expect(document.visibleNodes(expanded: [], query: "metrics").map(\.id) == ["/metrics", "/metrics/count"])
    #expect(document.visibleNodes(expanded: [], query: "missing").isEmpty)
}

@Test(arguments: ["null", "true", "1", "\"hello\"", "[]", "{}"])
func jsonFragmentsAndEmptyContainersRemainVisible(_ source: String) throws {
    let document = try JSONDocument(data: Data(source.utf8))
    #expect(document.visibleNodes(expanded: [], query: "").count == 1)
    #expect(document.nodes[0].key == "$")
}

@Test func jsonLimitsAndInvalidPayloadsFailClearly() throws {
    #expect(throws: JSONDisplayError.invalidJSON) { try JSONDocument(data: Data("<html>Sign in</html>".utf8)) }
    #expect(throws: JSONDisplayError.tooLarge) { try JSONDocument(data: Data(repeating: 32, count: JSONDocument.maximumBytes + 1)) }
    let deep = String(repeating: "[", count: 66) + "0" + String(repeating: "]", count: 66)
    #expect(throws: JSONDisplayError.tooComplex) { try JSONDocument(data: Data(deep.utf8)) }
    let broad = "[" + Array(repeating: "0", count: 20_001).joined(separator: ",") + "]"
    #expect(throws: JSONDisplayError.tooComplex) { try JSONDocument(data: Data(broad.utf8)) }
}

@Test func jsonMediaTypesAndRefreshMetadataAreRecognized() throws {
    #expect(JSONMediaType.matches("application/json; charset=utf-8"))
    #expect(JSONMediaType.matches("application/problem+json"))
    #expect(!JSONMediaType.matches("text/html"))
    #expect(!JSONMediaType.matches("application/jsonp"))
    let service = try JSONDecoder().decode(DirectoryService.self, from: Data(#"{"name":"Context Intelligence","links":[],"view_kind":"json","view_refresh_seconds":5}"#.utf8))
    #expect(service.view_refresh_seconds == 5)
}

@Test func serviceCookiesRespectHostPathSecureAndExpiryBoundaries() throws {
    func cookie(_ name: String, domain: String, path: String = "/", secure: Bool = false, expired: Bool = false) -> HTTPCookie {
        var properties: [HTTPCookiePropertyKey: Any] = [.name:name, .value:"test", .domain:domain, .path:path]
        if secure { properties[.secure] = "TRUE" }
        if expired { properties[.expires] = Date(timeIntervalSince1970: 1) }
        return HTTPCookie(properties: properties)!
    }
    let cookies = [cookie("host", domain:"node.example.com"), cookie("domain", domain:".example.com"),
                   cookie("other", domain:"other.example.com"), cookie("wrongpath", domain:"node.example.com", path:"/api-other"),
                   cookie("secure", domain:"node.example.com", secure:true), cookie("expired", domain:"node.example.com", expired:true)]
    let https = ServiceCookies.matching(cookies, url: URL(string:"https://node.example.com/api/status")!)
    #expect(Set(https.map(\.name)) == ["host", "domain", "secure"])
    let http = ServiceCookies.matching(cookies, url: URL(string:"http://node.example.com/api/status")!)
    #expect(Set(http.map(\.name)) == ["host", "domain"])
    #expect(ServiceCookies.matching(cookies, url: URL(string:"https://node.example.com.evil/api")!).isEmpty)
    #expect(ServiceCookies.matching([cookie("path", domain:"node.example.com", path:"/api")],
                                  url: URL(string:"https://node.example.com/api-other")!).isEmpty)
}
