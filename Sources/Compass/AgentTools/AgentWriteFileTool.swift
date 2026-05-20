import Foundation

/// Create or overwrite a UTF-8 text file. Intermediate directories are
/// created automatically. The model uses this for net-new files; in-place
/// edits should go through `AgentEditFileTool`, which preserves the rest of
/// the file and forces a contextual `oldString` match.
struct AgentWriteFileTool: AgentTool {
    static let toolName = "write_file"

    struct Arguments: Codable {
        let path: String
        let content: String
    }

    let spec: AgentToolSpec

    init() {
        let schema = try! AgentToolParametersSchema([
            "type": "object",
            "additionalProperties": false,
            "required": ["path", "content"],
            "properties": [
                "path": [
                    "type": "string",
                    "description": "Destination path. May be absolute (must resolve inside the working directory) or relative to it. Intermediate directories are created automatically."
                ],
                "content": [
                    "type": "string",
                    "description": "UTF-8 contents to write. Existing files are overwritten."
                ]
            ]
        ])
        spec = AgentToolSpec(
            name: Self.toolName,
            description: "Create or overwrite a UTF-8 text file at the given path. Intermediate directories are created. Use `edit_file` for in-place edits.",
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

        let parent = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true
            )
        } catch {
            return .failure(AgentToolError.ioFailure(error.localizedDescription).errorDescription ?? "I/O failure")
        }

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return .failure(AgentToolError.notRegularFile(args.path).errorDescription ?? "not a regular file")
        }

        let data = Data(args.content.utf8)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return .failure(AgentToolError.ioFailure(error.localizedDescription).errorDescription ?? "I/O failure")
        }

        let relative = context.relativize(url)
        return .ok("wrote \(data.count) bytes to \(relative)")
    }
}
