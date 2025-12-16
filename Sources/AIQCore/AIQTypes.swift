import Foundation

public struct AIQSymbolRow: Codable, Sendable {
    public var kind: String            // "type" | "method"
    public var name: String
    public var typeKind: String        // e.g. "struct" | "class" | "func" ...
    public var file: String
    public var line: Int
    public var declaration: String
    public var doc: String

    public init(kind: String, name: String, typeKind: String, file: String, line: Int, declaration: String, doc: String) {
        self.kind = kind
        self.name = name
        self.typeKind = typeKind
        self.file = file
        self.line = line
        self.declaration = declaration
        self.doc = doc
    }
}

public enum AIQError: Error, CustomStringConvertible {
    case message(String)

    public var description: String {
        switch self {
        case .message(let s): return s
        }
    }
}

public enum AIQKind {
    public static func classify(kindIdentifier: String) -> (kind: String, typeKind: String) {
        let raw = kindIdentifier.lowercased()
        if raw.contains(".func") || raw.contains(".method") || raw.contains(".init") {
            return ("method", "func")
        }
        if raw.hasPrefix("swift.") {
            let t = raw.replacingOccurrences(of: "swift.", with: "")
            if ["struct", "class", "enum", "protocol", "actor", "typealias"].contains(t) {
                return ("type", t)
            }
        }
        // Fallbacks
        if raw.contains("var") || raw.contains("property") {
            return ("property", "var")
        }
        return ("other", raw)
    }
}

public enum AIQPaths {
    public static func normalizeFileURI(_ uri: String) -> String {
        if uri.hasPrefix("file://") {
            let trimmed = uri.replacingOccurrences(of: "file://", with: "")
            return trimmed.removingPercentEncoding ?? trimmed
        }
        return uri
    }

    public static func relativize(path: String, to base: String) -> String {
        let baseURL = URL(fileURLWithPath: base).standardizedFileURL
        let fileURL = URL(fileURLWithPath: path).standardizedFileURL
        let basePath = baseURL.path
        let filePath = fileURL.path
        if filePath.hasPrefix(basePath.hasSuffix("/") ? basePath : basePath + "/") {
            let prefix = basePath.hasSuffix("/") ? basePath : basePath + "/"
            return String(filePath.dropFirst(prefix.count))
        }
        return filePath
    }
}

public enum AIQJSONL {
    public static func encodeLines<T: Encodable>(_ items: [T]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return try items.map { item in
            let data = try encoder.encode(item)
            guard let s = String(data: data, encoding: .utf8) else {
                throw AIQError.message("Failed to encode JSON")
            }
            return s
        }.joined(separator: "\n")
    }
}
