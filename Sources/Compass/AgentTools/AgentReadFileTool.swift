import Foundation

/// Read a UTF-8 text file from the working directory with optional line
/// offset/limit. Mirrors the line-numbered output the model is used to from
/// other agent Read tools so prompt fragments stay consistent across runtimes.
struct AgentReadFileTool: AgentTool {
    static let toolName = "read_file"
    static let defaultLineCount = 2_000
    static let maxLineLength = 2_000

    struct Arguments: Codable {
        let path: String
        let offset: Int?
        let limit: Int?
    }

    let spec: AgentToolSpec

    init() {
        let schema = try! AgentToolParametersSchema([
            "type": "object",
            "additionalProperties": false,
            "required": ["path"],
            "properties": [
                "path": [
                    "type": "string",
                    "description": "Path to the file to read. May be absolute (must resolve inside the working directory) or relative to it."
                ],
                "offset": [
                    "type": "integer",
                    "minimum": 1,
                    "description": "1-indexed line to start reading from. Defaults to 1."
                ],
                "limit": [
                    "type": "integer",
                    "minimum": 1,
                    "description": "Maximum number of lines to return. Defaults to 2000."
                ]
            ]
        ])
        spec = AgentToolSpec(
            name: Self.toolName,
            description: "Read a UTF-8 text file from the working directory. Returns line-numbered content. Optional 1-indexed offset and limit narrow the slice. Refuses binary files.",
            parameters: schema
        )
    }

    func invoke(arguments: Data, context: AgentToolContext) async throws -> AgentToolInvocationResult {
        let args: Arguments
        do {
            args = try JSONDecoder().decode(Arguments.self, from: arguments)
        } catch {
            return .failure("Failed to decode arguments: \(error.localizedDescription)")
        }

        let url: URL
        do {
            url = try context.resolvePath(args.path)
        } catch let error as AgentToolError {
            return .failure(error.errorDescription ?? "path resolution failed")
        } catch {
            return .failure("path resolution failed: \(error.localizedDescription)")
        }

        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return .failure(AgentToolError.fileNotFound(args.path).errorDescription ?? "not found")
        }
        if isDirectory.boolValue {
            return .failure(AgentToolError.notRegularFile(args.path).errorDescription ?? "not a regular file")
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return .failure(AgentToolError.ioFailure(error.localizedDescription).errorDescription ?? "I/O failure")
        }

        if data.prefix(8192).contains(0) {
            return .failure(AgentToolError.binaryFile(args.path).errorDescription ?? "binary file")
        }

        let text = String(decoding: data, as: UTF8.self)
        let allLines = text.components(separatedBy: "\n")
        let totalLines = allLines.count

        let offset = max(args.offset ?? 1, 1)
        let startIndex = offset - 1
        guard startIndex < totalLines else {
            return .ok("(file has \(totalLines) lines; offset \(offset) is past the end)")
        }

        let limit = max(args.limit ?? Self.defaultLineCount, 1)
        let endIndex = min(totalLines, startIndex + limit)
        let slice = allLines[startIndex..<endIndex]

        let rendered = slice.enumerated().map { idx, line in
            let lineNumber = idx + offset
            let truncatedLine: String
            if line.count > Self.maxLineLength {
                truncatedLine = String(line.prefix(Self.maxLineLength)) + "  ... [line truncated]"
            } else {
                truncatedLine = line
            }
            return String(format: "%6d\t", lineNumber) + truncatedLine
        }.joined(separator: "\n")

        var output = rendered
        if endIndex < totalLines {
            output += "\n... \(totalLines - endIndex) more lines"
        }
        return .ok(output)
    }
}
