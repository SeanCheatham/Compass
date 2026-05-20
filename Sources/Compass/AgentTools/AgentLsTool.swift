import Foundation

/// List directory entries (one per line). Directories carry a trailing `/`
/// so the model can tell apart entries without a second call.
struct AgentLsTool: AgentTool {
    static let toolName = "ls"
    static let maxEntries = 1_000

    struct Arguments: Codable {
        let path: String?
    }

    let spec: AgentToolSpec

    init() {
        let schema = try! AgentToolParametersSchema([
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "path": [
                    "type": "string",
                    "description": "Directory to list. Defaults to the working directory."
                ]
            ]
        ])
        spec = AgentToolSpec(
            name: Self.toolName,
            description: "List entries in a directory. Returns one name per line, with a trailing `/` on directories. Hidden entries are included.",
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
        if let path = args.path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
            do {
                url = try context.resolvePath(path)
            } catch let error as AgentToolError {
                return .failure(error.errorDescription ?? "path resolution failed")
            } catch {
                return .failure("path resolution failed: \(error.localizedDescription)")
            }
        } else {
            url = context.workingDirectory
        }

        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return .failure(AgentToolError.fileNotFound(args.path ?? ".").errorDescription ?? "not found")
        }
        if !isDirectory.boolValue {
            return .failure(AgentToolError.notDirectory(args.path ?? ".").errorDescription ?? "not a directory")
        }

        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            )
        } catch {
            return .failure(AgentToolError.ioFailure(error.localizedDescription).errorDescription ?? "I/O failure")
        }

        let sorted = entries.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let limited = Array(sorted.prefix(Self.maxEntries))

        let lines = limited.map { entryURL -> String in
            var isDirInner: ObjCBool = false
            fileManager.fileExists(atPath: entryURL.path, isDirectory: &isDirInner)
            return isDirInner.boolValue
                ? entryURL.lastPathComponent + "/"
                : entryURL.lastPathComponent
        }

        var output = lines.joined(separator: "\n")
        if sorted.count > Self.maxEntries {
            output += "\n... \(sorted.count - Self.maxEntries) more entries"
        }
        if output.isEmpty {
            output = "(empty directory)"
        }
        return .ok(output)
    }
}
