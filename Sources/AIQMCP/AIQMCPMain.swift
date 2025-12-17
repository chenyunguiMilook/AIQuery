//
//  main.swift
//  AIQuery
//
//  Created by chenyungui on 2025/12/17.
//

import Foundation

import Logging
import MCP

private enum AIQMCPTool {
	static let queryType = "query_type"
	static let queryMethod = "query_method"
}

private struct AIQExecResult: Sendable {
	var stdout: String
	var stderr: String
	var exitCode: Int32
}

@main
struct AIQMCPMain {
	static let queryTypeSchema: Value = [
		"type": "object",
		"properties": [
			"name": [
				"type": "string",
				"description": "Type name (exact match, e.g. Bezier3Segment)"
			],
			"membersLimit": [
				"type": "integer",
				"description": "Include top N method declarations as members (0 disables)",
				"minimum": 0
			],
		],
		"required": ["name"],
	]

	static let queryMethodSchema: Value = [
		"type": "object",
		"properties": [
			"name": [
				"type": "string",
				"description": "Method name (exact match, e.g. render)"
			],
		],
		"required": ["name"],
	]

	static func main() async {
		LoggingSystem.bootstrap { label in
			var handler = StreamLogHandler.standardError(label: label)
			handler.logLevel = .info
			return handler
		}

		let logger = Logger(label: "aiq.mcp")

		let server = Server(
			name: "aiq-mcp",
			version: "0.1.0",
			instructions: "Use tools query_type/query_method to query symbols indexed by aiq (.ai/index.sqlite).",
			capabilities: .init(tools: .init(listChanged: false)),
			configuration: .default
		)

		await server.withMethodHandler(ListTools.self) { _ in
			return .init(tools: [
				Tool(
					name: AIQMCPTool.queryType,
					description: "Query a type by exact name via aiq and return JSON array.",
					inputSchema: Self.queryTypeSchema,
					annotations: Tool.Annotations(title: "Query Type", readOnlyHint: true, destructiveHint: false, openWorldHint: false)
				),
				Tool(
					name: AIQMCPTool.queryMethod,
					description: "Query a method by exact name via aiq and return JSON array.",
					inputSchema: Self.queryMethodSchema,
					annotations: Tool.Annotations(title: "Query Method", readOnlyHint: true, destructiveHint: false, openWorldHint: false)
				),
			])
		}

		await server.withMethodHandler(CallTool.self) { params in
			do {
				switch params.name {
				case AIQMCPTool.queryType:
					let name = try requireStringArg(params.arguments, key: "name")
					let membersLimit = optionalIntArg(params.arguments, key: "membersLimit")

					var args = ["type", name]
					if let membersLimit {
						args += ["--members-limit", String(membersLimit)]
					}

					let res = try runAIQ(args: args)
					guard res.exitCode == 0 else {
						return .init(content: [.text(formatProcessError(res))], isError: true)
					}

					let jsonText = try jsonArrayFromJSONL(res.stdout)
					return .init(content: [.text(jsonText)], isError: false)

				case AIQMCPTool.queryMethod:
					let name = try requireStringArg(params.arguments, key: "name")

					let res = try runAIQ(args: ["method", name])
					guard res.exitCode == 0 else {
						return .init(content: [.text(formatProcessError(res))], isError: true)
					}

					let jsonText = try jsonArrayFromJSONL(res.stdout)
					return .init(content: [.text(jsonText)], isError: false)

				default:
					return .init(content: [.text("Unknown tool: \(params.name)")], isError: true)
				}
			} catch {
				return .init(content: [.text("Error: \(error)")], isError: true)
			}
		}

		do {
			let transport = StdioTransport(logger: logger)
			try await server.start(transport: transport)

			// Keep the process alive until externally terminated.
			await server.waitUntilCompleted()
		} catch {
			logger.error("MCP server failed: \(String(describing: error))")
		}
	}
}

private func requireStringArg(_ args: [String: Value]?, key: String) throws -> String {
	guard let v = args?[key], let s = v.stringValue, !s.isEmpty else {
		throw MCPError.invalidParams("Missing required argument: \(key)")
	}
	return s
}

private func optionalIntArg(_ args: [String: Value]?, key: String) -> Int? {
	guard let v = args?[key] else { return nil }
	return v.intValue ?? Int(v, strict: false)
}

private func runAIQ(args: [String]) throws -> AIQExecResult {
	let aiqPath = "/usr/local/bin/aiq"
	let fm = FileManager.default
	let env = ProcessInfo.processInfo.environment

	let p = Process()
	if let root = env["AIQ_PROJECT_ROOT"]?.trimmingCharacters(in: .whitespacesAndNewlines),
		!root.isEmpty
	{
		let expanded = (root as NSString).expandingTildeInPath
		var isDir: ObjCBool = false
		guard fm.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue else {
			throw MCPError.invalidRequest(
				"AIQ_PROJECT_ROOT does not exist or is not a directory: \(expanded)"
			)
		}
		p.currentDirectoryURL = URL(fileURLWithPath: expanded, isDirectory: true)
	}

	if fm.isExecutableFile(atPath: aiqPath) {
		p.executableURL = URL(fileURLWithPath: aiqPath)
		p.arguments = args
	} else {
		// Fallback to PATH lookup.
		p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
		p.arguments = ["aiq"] + args
	}

	// Avoid Pipe + readabilityHandler. Swift 6 treats readabilityHandler closures as
	// concurrently-executing, which forbids mutating captured vars.
	// Redirect output to temp files instead.
	let tmpDir = fm.temporaryDirectory.appendingPathComponent(
		"aiq-mcp-\(UUID().uuidString)",
		isDirectory: true
	)
	try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
	defer { try? fm.removeItem(at: tmpDir) }

	let stdoutURL = tmpDir.appendingPathComponent("stdout.txt")
	let stderrURL = tmpDir.appendingPathComponent("stderr.txt")
	fm.createFile(atPath: stdoutURL.path, contents: nil)
	fm.createFile(atPath: stderrURL.path, contents: nil)

	let stdoutWriteHandle = try FileHandle(forWritingTo: stdoutURL)
	let stderrWriteHandle = try FileHandle(forWritingTo: stderrURL)
	p.standardOutput = stdoutWriteHandle
	p.standardError = stderrWriteHandle

	try p.run()
	p.waitUntilExit()

	try? stdoutWriteHandle.close()
	try? stderrWriteHandle.close()

	let outData = (try? Data(contentsOf: stdoutURL)) ?? Data()
	let errData = (try? Data(contentsOf: stderrURL)) ?? Data()

	let stdout = String(data: outData, encoding: .utf8) ?? ""
	let stderr = String(data: errData, encoding: .utf8) ?? ""

	return AIQExecResult(stdout: stdout, stderr: stderr, exitCode: p.terminationStatus)
}

private func formatProcessError(_ res: AIQExecResult) -> String {
	let err = res.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
	if !err.isEmpty {
		return "aiq failed (exit \(res.exitCode)): \(err)"
	}
	let out = res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
	if !out.isEmpty {
		return "aiq failed (exit \(res.exitCode)): \(out)"
	}
	return "aiq failed (exit \(res.exitCode))"
}

private func jsonArrayFromJSONL(_ jsonl: String) throws -> String {
	let lines = jsonl
		.split(whereSeparator: \.isNewline)
		.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
		.filter { !$0.isEmpty }

	if lines.isEmpty {
		return "[]"
	}

	var array: [Any] = []
	array.reserveCapacity(lines.count)

	for line in lines {
		let data = line.data(using: String.Encoding.utf8) ?? Data()
		let obj = try JSONSerialization.jsonObject(with: data, options: [])
		array.append(obj)
	}

	let out = try JSONSerialization.data(withJSONObject: array, options: [])
	return String(data: out, encoding: .utf8) ?? "[]"
}
