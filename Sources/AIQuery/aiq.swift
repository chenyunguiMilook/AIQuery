import Foundation
import ArgumentParser
import AIQCore

@main
struct AIQ: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "AI Code Query Tool (Symbol Graph → SQLite → JSONL)",
        subcommands: [Index.self, TypeQuery.self, MethodQuery.self]
    )
}

struct Index: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Build symbol graphs and index into SQLite")

    @Argument(help: "Path to the Swift Package")
    var packagePath: String

    @Option(name: .long, help: "Path to SQLite db (default: <package>/.aiq/index.sqlite)")
    var db: String?

    @Option(name: .long, help: "Symbol graph output dir (default: <package>/.build/aiq-symbol-graphs)")
    var symbolGraphDir: String?

    func run() throws {
        let pkg = URL(fileURLWithPath: packagePath).standardizedFileURL.path
        let dbPath = db ?? (pkg as NSString).appendingPathComponent(".aiq/index.sqlite")
        let sgDir = symbolGraphDir ?? (pkg as NSString).appendingPathComponent(".build/aiq-symbol-graphs")

        let indexer = AIQIndexer()
        try indexer.runSwiftBuildEmitSymbolGraph(packagePath: pkg, symbolGraphDir: sgDir) { line in
            if !line.isEmpty { FileHandle.standardError.write((line + "\n").data(using: .utf8)!) }
        }

        try indexer.indexSymbolGraphs(options: IndexOptions(packagePath: pkg, dbPath: dbPath, symbolGraphDir: sgDir)) { line in
            if !line.isEmpty { FileHandle.standardError.write((line + "\n").data(using: .utf8)!) }
        }

        FileHandle.standardOutput.write((dbPath + "\n").data(using: .utf8)!)
    }
}

struct TypeQuery: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "type", abstract: "Query type symbols")

    @Argument(help: "Type name")
    var name: String

    @Option(name: .long, help: "Path to SQLite db (default: ./.aiq/index.sqlite)")
    var db: String?

    @Option(name: .long, help: "Include top N method declarations as members (default: 5; 0 disables)")
    var membersLimit: Int = 5

    func run() throws {
        let dbPath = try resolveDBPath(db)
        let q = AIQQuerier()
        let rows = try q.queryType(name: name, options: QueryOptions(dbPath: dbPath), membersLimit: max(0, membersLimit))
        let out = try AIQJSONL.encodeLines(rows)
        if !out.isEmpty { print(out) }
    }
}

struct MethodQuery: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "method", abstract: "Query method symbols")

    @Argument(help: "Method name")
    var name: String

    @Option(name: .long, help: "Path to SQLite db (default: ./.aiq/index.sqlite)")
    var db: String?

    func run() throws {
        let dbPath = try resolveDBPath(db)
        let q = AIQQuerier()
        let rows = try q.queryMethod(name: name, options: QueryOptions(dbPath: dbPath))
        let out = try AIQJSONL.encodeLines(rows)
        if !out.isEmpty { print(out) }
    }
}

private func resolveDBPath(_ override: String?) throws -> String {
    if let override {
        return URL(fileURLWithPath: override).standardizedFileURL.path
    }

    let env = ProcessInfo.processInfo.environment
    if let dbPath = env["AIQ_DB_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines), !dbPath.isEmpty {
        let expanded = (dbPath as NSString).expandingTildeInPath
        let p = URL(fileURLWithPath: expanded).standardizedFileURL.path
        if FileManager.default.fileExists(atPath: p) {
            return p
        }
    }

    if let root = env["AIQ_PROJECT_ROOT"]?.trimmingCharacters(in: .whitespacesAndNewlines), !root.isEmpty {
        let expandedRoot = (root as NSString).expandingTildeInPath
        if let p = firstExistingProjectDB(under: expandedRoot) {
            return p
        }
    }

    if let p = firstExistingDBWalkingUp(from: FileManager.default.currentDirectoryPath) {
        return p
    }

    if let p = firstExistingHomeDB() {
        return p
    }

    throw AIQError.message(
        "No db found. Pass --db <path>, set AIQ_DB_PATH/AIQ_PROJECT_ROOT, or run from project root with .ai/index.sqlite (or .aiq/index.sqlite). " +
        "Fallback locations checked: <cwd and parents>, ~/.ai/index.sqlite, ~/.aiq/index.sqlite"
    )
}

private func firstExistingProjectDB(under root: String) -> String? {
    let fm = FileManager.default
    let ai = (root as NSString).appendingPathComponent(".ai/index.sqlite")
    if fm.fileExists(atPath: ai) { return ai }
    let aiq = (root as NSString).appendingPathComponent(".aiq/index.sqlite")
    if fm.fileExists(atPath: aiq) { return aiq }
    return nil
}

private func firstExistingDBWalkingUp(from startDir: String) -> String? {
    var dir = URL(fileURLWithPath: startDir).standardizedFileURL.path
    let fm = FileManager.default

    for _ in 0..<64 {
        let ai = (dir as NSString).appendingPathComponent(".ai/index.sqlite")
        if fm.fileExists(atPath: ai) { return ai }

        let aiq = (dir as NSString).appendingPathComponent(".aiq/index.sqlite")
        if fm.fileExists(atPath: aiq) { return aiq }

        let parent = (dir as NSString).deletingLastPathComponent
        if parent.isEmpty || parent == dir { break }
        dir = parent
    }
    return nil
}

private func firstExistingHomeDB() -> String? {
    let home = NSHomeDirectory()
    let fm = FileManager.default

    let homeAi = (home as NSString).appendingPathComponent(".ai/index.sqlite")
    if fm.fileExists(atPath: homeAi) { return homeAi }

    let homeAiq = (home as NSString).appendingPathComponent(".aiq/index.sqlite")
    if fm.fileExists(atPath: homeAiq) { return homeAiq }

    return nil
}
