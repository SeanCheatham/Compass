import Foundation

/// Exact find/replace on an existing UTF-8 text file. The model must supply
/// enough surrounding context that `oldString` is unique in the file, or
/// pass `replaceAll: true` to substitute every occurrence. Matches the
/// semantics the Plan/Reflect lesson-edit JSON contract already uses for
/// `.compass/lessons.md`, so the same mental model applies here.
struct AgentEditFileTool: AgentTool {
    static let toolName = "edit_file"

    struct Arguments: Codable {
        let path: String
        let oldString: String
        let newString: String
        let replaceAll: Bool?
    }

    let spec: AgentToolSpec

    init() {
        let schema = try! AgentToolParametersSchema([
            "type": "object",
            "additionalProperties": false,
            "required": ["path", "oldString", "newString"],
            "properties": [
                "path": [
                    "type": "string",
                    "description": "Path to the existing file to edit. May be absolute (must resolve inside the working directory) or relative to it."
                ],
                "oldString": [
                    "type": "string",
                    "description": "Exact substring to replace. Must be unique in the file unless replaceAll is true."
                ],
                "newString": [
                    "type": "string",
                    "description": "Replacement text. Must be different from oldString."
                ],
                "replaceAll": [
                    "type": "boolean",
                    "description": "Replace every occurrence instead of requiring uniqueness. Defaults to false."
                ]
            ]
        ])
        spec = AgentToolSpec(
            name: Self.toolName,
            description: "Edit an existing UTF-8 text file by exact find/replace. By default oldString must appear exactly once; set replaceAll to substitute every occurrence.",
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

        if args.oldString == args.newString {
            return .failure("oldString and newString are identical; no edit needed")
        }
        if args.oldString.isEmpty {
            return .failure("oldString is empty; use write_file to create a file from scratch")
        }

        let url: URL
        do {
            url = try context.resolvePath(args.path)
        } catch let error as AgentToolError {
            return .failure(error.errorDescription ?? "path resolution failed")
        } catch {
            return .failure("path resolution failed: \(error.localizedDescription)")
        }

        let originalData: Data
        do {
            originalData = try await context.filesystem.readFile(at: url)
        } catch let error as AgentFilesystemError {
            switch error {
            case .notFound:
                return .failure(AgentToolError.fileNotFound(args.path).errorDescription ?? "not found")
            case .notRegularFile:
                return .failure(AgentToolError.notRegularFile(args.path).errorDescription ?? "not a regular file")
            default:
                return .failure(error.errorDescription ?? "I/O failure")
            }
        } catch {
            return .failure("read failed: \(error.localizedDescription)")
        }
        if originalData.prefix(8192).contains(0) {
            return .failure(AgentToolError.binaryFile(args.path).errorDescription ?? "binary file")
        }
        let original = String(decoding: originalData, as: UTF8.self)
        let occurrences = original.ranges(of: args.oldString).count
        let replaceAll = args.replaceAll ?? false

        if occurrences == 0 {
            return .failure("oldString not found in \(context.relativize(url))")
        }
        if occurrences > 1 && !replaceAll {
            return .failure("oldString matches \(occurrences) places in \(context.relativize(url)); include more surrounding context or set replaceAll: true")
        }

        let updated: String
        let replaced: Int
        if replaceAll {
            updated = original.replacingOccurrences(of: args.oldString, with: args.newString)
            replaced = occurrences
        } else {
            // single occurrence
            if let range = original.range(of: args.oldString) {
                updated = original.replacingCharacters(in: range, with: args.newString)
            } else {
                return .failure("oldString not found in \(context.relativize(url))")
            }
            replaced = 1
        }

        do {
            try await context.filesystem.writeFile(Data(updated.utf8), at: url)
        } catch let error as AgentFilesystemError {
            return .failure(error.errorDescription ?? "I/O failure")
        } catch {
            return .failure("write failed: \(error.localizedDescription)")
        }

        let plural = replaced == 1 ? "" : "s"
        return .ok("replaced \(replaced) occurrence\(plural) in \(context.relativize(url))")
    }
}

private extension String {
    /// Foundation's `ranges(of:)` is Swift 5.7+ but only on String<-->String
    /// search via `Substring` indices, so we implement a small finder that
    /// returns all non-overlapping ranges of `target`.
    func ranges(of target: String) -> [Range<String.Index>] {
        guard !target.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        var searchStart = startIndex
        while searchStart < endIndex,
              let found = range(of: target, range: searchStart..<endIndex) {
            ranges.append(found)
            searchStart = found.upperBound
        }
        return ranges
    }
}
