import Foundation

public struct QueryOptions: Sendable {
    public var dbPath: String

    public init(dbPath: String) {
        self.dbPath = dbPath
    }
}

public final class AIQQuerier {
    public init() {}

    public func queryType(name: String, options: QueryOptions) throws -> [AIQSymbolRow] {
        try query(kind: "type", name: name, options: options)
    }

    public func queryMethod(name: String, options: QueryOptions) throws -> [AIQSymbolRow] {
        try query(kind: "method", name: name, options: options)
    }

    private func query(kind: String, name: String, options: QueryOptions) throws -> [AIQSymbolRow] {
        let db = try SQLiteDB(path: options.dbPath)
        let stmt = try db.prepare("""
        SELECT kind, name, type_kind, file, line, declaration, doc
        FROM symbols
        WHERE name = ? AND kind = ?
        ORDER BY file, line;
        """)
        stmt.bindText(1, name)
        stmt.bindText(2, kind)

        var out: [AIQSymbolRow] = []
        while stmt.stepRow() {
            out.append(
                AIQSymbolRow(
                    kind: stmt.colText(0),
                    name: stmt.colText(1),
                    typeKind: stmt.colText(2),
                    file: stmt.colText(3),
                    line: stmt.colInt(4),
                    declaration: stmt.colText(5),
                    doc: stmt.colText(6)
                )
            )
        }
        return out
    }
}
