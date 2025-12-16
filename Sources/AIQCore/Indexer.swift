import Foundation

public struct IndexOptions: Sendable {
    public var packagePath: String
    public var dbPath: String
    public var symbolGraphDir: String

    public init(packagePath: String, dbPath: String, symbolGraphDir: String) {
        self.packagePath = packagePath
        self.dbPath = dbPath
        self.symbolGraphDir = symbolGraphDir
    }
}

public final class AIQIndexer {
    public init() {}

    public func runSwiftBuildEmitSymbolGraph(packagePath: String, symbolGraphDir: String, log: (String) -> Void) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: symbolGraphDir) {
            try fm.createDirectory(atPath: symbolGraphDir, withIntermediateDirectories: true)
        }

        let p = Process()
        p.currentDirectoryURL = URL(fileURLWithPath: packagePath)
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = [
            "swift", "build",
            "-Xswiftc", "-Xfrontend", "-Xswiftc", "-emit-symbol-graph",
            "-Xswiftc", "-Xfrontend", "-Xswiftc", "-emit-symbol-graph-dir",
            "-Xswiftc", "-Xfrontend", "-Xswiftc", symbolGraphDir
        ]

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe

        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()

        if !data.isEmpty, let s = String(data: data, encoding: .utf8) {
            log(s.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if p.terminationStatus != 0 {
            throw AIQError.message("swift build failed (status \(p.terminationStatus))")
        }
    }

    public func indexSymbolGraphs(options: IndexOptions, log: (String) -> Void) throws {
        let fm = FileManager.default
        let dbDir = (options.dbPath as NSString).deletingLastPathComponent
        if !fm.fileExists(atPath: dbDir) {
            try fm.createDirectory(atPath: dbDir, withIntermediateDirectories: true)
        }

        let db = try SQLiteDB(path: options.dbPath)
        try createSchema(db)

        let graphFiles = try findSymbolGraphFiles(root: options.symbolGraphDir)
        if graphFiles.isEmpty {
            throw AIQError.message("No *.symbols.json found under: \(options.symbolGraphDir)")
        }

        log("Found \(graphFiles.count) symbol graph files")

        try db.withTransaction {
            for file in graphFiles {
                let data = try Data(contentsOf: URL(fileURLWithPath: file))
                let graph = try JSONDecoder().decode(SymbolGraphFile.self, from: data)
                let moduleName = graph.module?.name ?? ""
                let memberOf = buildMemberOfMap(graph.relationships)
                try ingest(graph: graph, module: moduleName, memberOf: memberOf, packagePath: options.packagePath, db: db)
            }
        }

        log("Indexing complete: \(options.dbPath)")
    }

    private func createSchema(_ db: SQLiteDB) throws {
        try db.exec("""
        CREATE TABLE IF NOT EXISTS symbols (
            usr TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            kind TEXT NOT NULL,
            type_kind TEXT NOT NULL,
            file TEXT NOT NULL,
            line INTEGER NOT NULL,
            declaration TEXT NOT NULL,
            doc TEXT NOT NULL,
            parent_usr TEXT NOT NULL,
            module TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_symbols_name_kind ON symbols(name, kind);
        CREATE INDEX IF NOT EXISTS idx_symbols_parent ON symbols(parent_usr);
        """)
    }

    private func findSymbolGraphFiles(root: String) throws -> [String] {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: root)
        let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        var out: [String] = []
        while let u = enumerator?.nextObject() as? URL {
            if u.pathExtension == "json" && u.lastPathComponent.hasSuffix(".symbols.json") {
                out.append(u.path)
            }
        }
        return out.sorted()
    }

    private func buildMemberOfMap(_ rels: [SymbolGraphFile.Relationship]?) -> [String: String] {
        guard let rels else { return [:] }
        var map: [String: String] = [:]
        for r in rels where r.kind == "memberOf" {
            map[r.source] = r.target
        }
        return map
    }

    private func ingest(graph: SymbolGraphFile, module: String, memberOf: [String: String], packagePath: String, db: SQLiteDB) throws {
        let insert = try db.prepare("""
        INSERT OR REPLACE INTO symbols
        (usr, name, kind, type_kind, file, line, declaration, doc, parent_usr, module)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """)

        for s in graph.symbols {
            let usr = s.identifier.precise
            let name = s.names.title
            let (kind, typeKind) = AIQKind.classify(kindIdentifier: s.kind.identifier)
            if kind != "type" && kind != "method" {
                continue
            }

            let rawPath = AIQPaths.normalizeFileURI(s.location?.uri ?? "")
            let abs = rawPath.isEmpty ? "" : rawPath
            let file = abs.isEmpty ? "" : AIQPaths.relativize(path: abs, to: packagePath)
            let line = s.location?.position.line ?? 0
            let decl = s.declarationString
            let doc = s.docString
            let parent = memberOf[usr] ?? ""

            insert.bindText(1, usr)
            insert.bindText(2, name)
            insert.bindText(3, kind)
            insert.bindText(4, typeKind)
            insert.bindText(5, file)
            insert.bindInt(6, line)
            insert.bindText(7, decl)
            insert.bindText(8, doc)
            insert.bindText(9, parent)
            insert.bindText(10, module)

            try insert.stepDone()
            insert.reset()
        }
    }
}
