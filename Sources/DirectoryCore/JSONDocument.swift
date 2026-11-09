import Foundation
import CoreFoundation

public enum JSONDisplayError: LocalizedError {
    case invalidJSON, tooLarge, tooComplex
    public var errorDescription: String? {
        switch self {
        case .invalidJSON: return "This response is not valid JSON. Try opening the service in Web view."
        case .tooLarge: return "The response exceeds the 4 MB JSON viewer limit. Open it in Web view instead."
        case .tooComplex: return "This JSON has too many values or nesting levels for the inspector. Open it in Web view instead."
        }
    }
}

public enum JSONKind: String, Sendable {
    case object, array, string, number, boolean, null
}

public struct JSONNode: Identifiable, Sendable {
    public let id: String
    public let parentID: String?
    public let key: String
    public let kind: JSONKind
    public let text: String
    public let depth: Int
    public let childCount: Int
    public var isExpandable: Bool { childCount > 0 }
    public var displayKey: String { key.isEmpty ? "(empty key)" : key }
}

public struct JSONDocument: Sendable {
    public static let maximumBytes = 4 * 1024 * 1024
    public let nodes: [JSONNode]
    public let originalText: String
    public let formattedText: String
    public let byteCount: Int

    public init(data: Data) throws {
        guard data.count <= Self.maximumBytes else { throw JSONDisplayError.tooLarge }
        let value: Any
        do { value = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) }
        catch { throw JSONDisplayError.invalidJSON }
        var result: [JSONNode] = []
        func append(_ value: Any, key: String, id: String, parent: String?, depth: Int) throws {
            guard depth <= 64, result.count < 20_000 else { throw JSONDisplayError.tooComplex }
            func childID(_ key: String) -> String {
                id + "/" + key.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
            }
            if let object = value as? [String: Any] {
                result.append(JSONNode(id: id, parentID: parent, key: key, kind: .object,
                                       text: "\(object.count) fields", depth: depth, childCount: object.count))
                for child in object.keys.sorted() {
                    try append(object[child]!, key: child, id: childID(child), parent: id, depth: depth + 1)
                }
            } else if let array = value as? [Any] {
                result.append(JSONNode(id: id, parentID: parent, key: key, kind: .array,
                                       text: "\(array.count) items", depth: depth, childCount: array.count))
                for (index, child) in array.enumerated() {
                    try append(child, key: "[\(index)]", id: childID(String(index)), parent: id, depth: depth + 1)
                }
            } else {
                let kind: JSONKind
                let text: String
                if value is NSNull { kind = .null; text = "null" }
                else if let number = value as? NSNumber {
                    if CFGetTypeID(number) == CFBooleanGetTypeID() {
                        kind = .boolean; text = number.boolValue ? "true" : "false"
                    } else { kind = .number; text = number.stringValue }
                } else if let string = value as? String { kind = .string; text = string }
                else { throw JSONDisplayError.invalidJSON }
                result.append(JSONNode(id: id, parentID: parent, key: key, kind: kind,
                                       text: text, depth: depth, childCount: 0))
            }
        }
        try append(value, key: "$", id: "", parent: nil, depth: 0)
        let formatted = try JSONSerialization.data(withJSONObject: value,
            options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes])
        self.nodes = result
        self.formattedText = String(decoding: formatted, as: UTF8.self)
        self.originalText = String(data: data, encoding: .utf8) ?? self.formattedText
        self.byteCount = data.count
    }

    public func visibleNodes(expanded: Set<String>, query: String) -> [JSONNode] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let hidesRoot = nodes.first?.isExpandable == true
        if !query.isEmpty {
            var included: Set<String> = []
            for node in nodes where node.key.localizedCaseInsensitiveContains(query) ||
                node.text.localizedCaseInsensitiveContains(query) || node.id.localizedCaseInsensitiveContains(query) {
                var current: JSONNode? = node
                while let item = current {
                    if !included.insert(item.id).inserted { break }
                    current = item.parentID.flatMap { byID[$0] }
                }
            }
            return nodes.filter { included.contains($0.id) && (!hidesRoot || !$0.id.isEmpty) }
        }
        return nodes.filter { node in
            if hidesRoot && node.id.isEmpty { return false }
            var parent = node.parentID
            while let id = parent, !id.isEmpty {
                guard expanded.contains(id) else { return false }
                parent = byID[id]?.parentID
            }
            return true
        }
    }

    public var summaryNodes: [JSONNode] {
        let priorities = ["status", "server_version", "version", "uptime_seconds", "active_sessions", "error_count_last_hour"]
        let scalars = nodes.filter { $0.depth == 1 && $0.kind != .object && $0.kind != .array && $0.kind != .null }
        return Array(scalars.sorted {
            let left = priorities.firstIndex(of: $0.key) ?? priorities.count
            let right = priorities.firstIndex(of: $1.key) ?? priorities.count
            return left == right ? $0.key < $1.key : left < right
        }.prefix(6))
    }
}

public enum JSONMediaType {
    public static func matches(_ type: String?) -> Bool {
        let mime = type?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        return mime == "application/json" || (mime.hasPrefix("application/") && mime.hasSuffix("+json"))
    }
}
