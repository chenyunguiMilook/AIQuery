import Foundation
import SQLite3

public final class SQLiteDB {
    private var db: OpaquePointer?

    public init(path: String) throws {
        var ptr: OpaquePointer?
        if sqlite3_open(path, &ptr) != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(ptr))
            sqlite3_close(ptr)
            throw AIQError.message("SQLite open failed: \(msg)")
        }
        self.db = ptr
        try exec("PRAGMA journal_mode=WAL;")
        try exec("PRAGMA synchronous=NORMAL;")
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    public func exec(_ sql: String) throws {
        guard let db else { throw AIQError.message("SQLite not open") }
        var err: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw AIQError.message("SQLite exec failed: \(msg)\nSQL: \(sql)")
        }
    }

    public func prepare(_ sql: String) throws -> SQLiteStmt {
        guard let db else { throw AIQError.message("SQLite not open") }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(db))
            throw AIQError.message("SQLite prepare failed: \(msg)\nSQL: \(sql)")
        }
        return SQLiteStmt(db: db, stmt: stmt)
    }

    public func withTransaction<T>(_ body: () throws -> T) throws -> T {
        try exec("BEGIN IMMEDIATE;")
        do {
            let out = try body()
            try exec("COMMIT;")
            return out
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }
}

public final class SQLiteStmt {
    private let db: OpaquePointer
    private let stmt: OpaquePointer?

    fileprivate init(db: OpaquePointer, stmt: OpaquePointer?) {
        self.db = db
        self.stmt = stmt
    }

    deinit {
        sqlite3_finalize(stmt)
    }

    public func reset() {
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
    }

    public func bindText(_ index: Int32, _ value: String) {
        sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
    }

    public func bindInt(_ index: Int32, _ value: Int) {
        sqlite3_bind_int64(stmt, index, sqlite3_int64(value))
    }

    public func bindNull(_ index: Int32) {
        sqlite3_bind_null(stmt, index)
    }

    public func stepDone() throws {
        let rc = sqlite3_step(stmt)
        if rc != SQLITE_DONE {
            let msg = String(cString: sqlite3_errmsg(db))
            throw AIQError.message("SQLite step failed: \(msg)")
        }
    }

    public func stepRow() -> Bool {
        sqlite3_step(stmt) == SQLITE_ROW
    }

    public func colText(_ index: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: c)
    }

    public func colInt(_ index: Int32) -> Int {
        Int(sqlite3_column_int64(stmt, index))
    }
}
