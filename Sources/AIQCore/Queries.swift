import Foundation

public struct QueryOptions: Sendable {
    public var dbPath: String

    public init(dbPath: String) {
        self.dbPath = dbPath
    }
}

public final class AIQQuerier {
    public init() {}

    public func queryType(name: String, options: QueryOptions, membersLimit: Int = 0) throws -> [AIQSymbolRow] {
        let db = try SQLiteDB(path: options.dbPath)
        var rows = try query(db: db, kind: "type", name: name)
        guard membersLimit > 0 else { return rows }

        let memberStmt = try db.prepare("""
        SELECT declaration
        FROM symbols
        WHERE parent_usr = ? AND kind = 'method'
        ORDER BY name, file, line
        LIMIT ?;
        """)

        for i in rows.indices {
            guard let usr = rows[i].usr, !usr.isEmpty else { continue }
            memberStmt.bindText(1, usr)
            memberStmt.bindInt(2, membersLimit)

            var members: [String] = []
            while memberStmt.stepRow() {
                let decl = memberStmt.colText(0)
                if !decl.isEmpty {
                    members.append(decl)
                }
            }
            memberStmt.reset()

            if !members.isEmpty {
                rows[i].members = members
            }
        }
        return rows
    }

    public func queryMethod(name: String, options: QueryOptions) throws -> [AIQSymbolRow] {
        let db = try SQLiteDB(path: options.dbPath)
        return try query(db: db, kind: "method", name: name)
    }

    private func query(db: SQLiteDB, kind: String, name: String) throws -> [AIQSymbolRow] {
        let stmt = try db.prepare("""
        SELECT usr, kind, name, type_kind, file, line, declaration, doc
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
                    usr: stmt.colText(0),
                    kind: stmt.colText(1),
                    name: stmt.colText(2),
                    typeKind: stmt.colText(3),
                    file: stmt.colText(4),
                    line: stmt.colInt(5),
                    declaration: stmt.colText(6),
                    doc: stmt.colText(7)
                )
            )
        }
        return out
    }
}
