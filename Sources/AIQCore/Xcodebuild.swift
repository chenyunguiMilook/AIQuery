import Foundation

public enum AIQXcodebuild {
    public static func listSchemes(projectOrWorkspacePath: String) throws -> [String] {
        let path = URL(fileURLWithPath: projectOrWorkspacePath).standardizedFileURL.path
        let (flag, value) = xcodebuildContainerArgs(for: path)

        let output = try runXcodebuild(arguments: ["-list", flag, value])
        return parseSchemes(from: output)
    }

    public static func buildEmitSymbolGraph(
        projectOrWorkspacePath: String,
        scheme: String,
        destination: String,
        symbolGraphDir: String,
        log: @escaping (String) -> Void
    ) throws {
        let path = URL(fileURLWithPath: projectOrWorkspacePath).standardizedFileURL.path
        let (flag, value) = xcodebuildContainerArgs(for: path)

        let sgDir = URL(fileURLWithPath: symbolGraphDir).standardizedFileURL.path

        let otherSwiftFlags = "$(inherited) -emit-symbol-graph -emit-symbol-graph-dir \(sgDir)"
        let swiftFlags = "-emit-symbol-graph -emit-symbol-graph-dir \(sgDir)"

        _ = try runXcodebuild(
            arguments: [
                "-scheme", scheme,
                "-destination", destination,
                "clean", "build",
                flag, value,
                "OTHER_SWIFT_FLAGS=\(otherSwiftFlags)",
                "SWIFT_FLAGS=\(swiftFlags)"
            ],
            log: log
        )
    }

    public static func buildEmitSymbolGraphCommand(
        projectOrWorkspacePath: String,
        scheme: String,
        destination: String,
        symbolGraphDir: String
    ) -> String {
        let path = URL(fileURLWithPath: projectOrWorkspacePath).standardizedFileURL.path
        let (flag, value) = xcodebuildContainerArgs(for: path)

        let sgDir = URL(fileURLWithPath: symbolGraphDir).standardizedFileURL.path
        
        func escape(_ s: String) -> String {
            if s.contains(" ") { return "\"\(s)\"" }
            return s
        }

        let safeSgDir = escape(sgDir)
        
        let cmd = [
            "xcodebuild",
            "-scheme", "\"\(scheme)\"",
            "-destination", "\"\(destination)\"",
            "clean", "build",
            flag, "\"\(value)\"",
            "\"OTHER_SWIFT_FLAGS=$(inherited) -emit-symbol-graph -emit-symbol-graph-dir \(safeSgDir)\"",
            "\"SWIFT_FLAGS=-emit-symbol-graph -emit-symbol-graph-dir \(safeSgDir)\""
        ]
        
        return cmd.joined(separator: " ")
    }

    private static func xcodebuildContainerArgs(for path: String) -> (String, String) {
        if path.hasSuffix(".xcworkspace") {
            return ("-workspace", path)
        }
        if path.hasSuffix(".xcodeproj") {
            return ("-project", path)
        }
        // Fallback: treat as a folder containing an xcodeproj; xcodebuild will error clearly.
        return ("-project", path)
    }

    private static func runXcodebuild(arguments: [String], log: ((String) -> Void)? = nil) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["xcodebuild"] + arguments

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe

        try p.run()

        // Stream output line-by-line when logging is requested.
        if let log {
            let handle = pipe.fileHandleForReading
            while true {
                let data = try handle.read(upToCount: 64 * 1024) ?? Data()
                if data.isEmpty { break }
                if let s = String(data: data, encoding: .utf8), !s.isEmpty {
                    // Avoid keeping huge buffers; forward chunks.
                    log(s.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
            p.waitUntilExit()
            if p.terminationStatus != 0 {
                throw AIQError.message("xcodebuild failed (status \(p.terminationStatus))")
            }
            return ""
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()

        let out = String(data: data, encoding: .utf8) ?? ""
        if p.terminationStatus != 0 {
            throw AIQError.message("xcodebuild failed (status \(p.terminationStatus))\n\(out)")
        }
        return out
    }

    private static func parseSchemes(from output: String) -> [String] {
        let lines = output
            .split(whereSeparator: \.isNewline)
            .map { String($0) }

        var schemes: [String] = []
        var inSchemes = false

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line == "Schemes:" {
                inSchemes = true
                continue
            }
            if inSchemes {
                if line.isEmpty { break }
                // xcodebuild prints schemes as indented lines.
                if raw.hasPrefix("    ") || raw.hasPrefix("\t") {
                    schemes.append(line)
                } else {
                    // Next section.
                    break
                }
            }
        }

        // De-dup while preserving order.
        var seen = Set<String>()
        return schemes.filter { seen.insert($0).inserted }
    }
}
