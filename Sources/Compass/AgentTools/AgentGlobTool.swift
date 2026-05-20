import Foundation

/// Find files under the working directory whose path matches a glob.
/// Supports `**` (any number of path components), `*` (any chars within a
/// component), and `?` (single char within a component). Results are
/// returned newest-first by modification time.
struct AgentGlobTool: AgentTool {
    static let toolName = "glob"
    static let maxResults = 200
    static let walkCap = 10_000

    struct Arguments: Codable {
        let pattern: String
        let path: String?
    }

    let spec: AgentToolSpec

    init() {
        let schema = try! AgentToolParametersSchema([
            "type": "object",
            "additionalProperties": false,
            "required": ["pattern"],
            "properties": [
                "pattern": [
                    "type": "string",
                    "description": "Glob pattern, relative to the search root. Supports `**`, `*`, and `?`. Example: `**/*.swift`."
                ],
                "path": [
                    "type": "string",
                    "description": "Subdirectory under the working directory to scope the search to. Defaults to the working directory."
                ]
            ]
        ])
        spec = AgentToolSpec(
            name: Self.toolName,
            description: "Find files matching a glob pattern. Results are sorted newest-first by modification time and capped at 200 matches.",
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
        let pattern = args.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else {
            return .failure("pattern is empty")
        }

        let root: URL
        if let raw = args.path?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            do {
                root = try context.resolvePath(raw)
            } catch let error as AgentToolError {
                return .failure(error.errorDescription ?? "path resolution failed")
            } catch {
                return .failure("path resolution failed: \(error.localizedDescription)")
            }
        } else {
            root = context.workingDirectory
        }

        let regex: NSRegularExpression
        do {
            regex = try Self.regex(forGlob: pattern)
        } catch {
            return .failure("invalid glob pattern: \(error.localizedDescription)")
        }

        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .failure(AgentToolError.notDirectory(args.path ?? ".").errorDescription ?? "not a directory")
        }

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: []
        ) else {
            return .failure("could not enumerate \(root.path)")
        }

        var matches: [(url: URL, mtime: Date)] = []
        var visited = 0
        while let next = enumerator.nextObject() {
            visited += 1
            if visited > Self.walkCap { break }
            guard let fileURL = next as? URL else { continue }

            let relative = relativePath(of: fileURL, under: root)
            let nsRelative = relative as NSString
            let range = NSRange(location: 0, length: nsRelative.length)
            if regex.firstMatch(in: relative, options: [], range: range) == nil { continue }

            let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            if resourceValues?.isRegularFile != true { continue }
            let mtime = resourceValues?.contentModificationDate ?? Date.distantPast
            matches.append((fileURL, mtime))
        }

        let sorted = matches.sorted { lhs, rhs in
            if lhs.mtime == rhs.mtime { return lhs.url.path < rhs.url.path }
            return lhs.mtime > rhs.mtime
        }
        let displayed = sorted.prefix(Self.maxResults).map { context.relativize($0.url) }
        var body = displayed.joined(separator: "\n")
        if sorted.count > Self.maxResults {
            body += "\n... \(sorted.count - Self.maxResults) more matches"
        }
        if body.isEmpty {
            body = "(no matches)"
        }
        return .ok(body)
    }

    private func relativePath(of url: URL, under root: URL) -> String {
        let absolutePath = url.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        if absolutePath == rootPath { return "." }
        if absolutePath.hasPrefix(rootPath + "/") {
            return String(absolutePath.dropFirst(rootPath.count + 1))
        }
        return absolutePath
    }

    /// Translate a glob pattern into an anchored regex.
    /// - `**` matches any sequence of characters (including `/`).
    /// - `*` matches any characters except `/`.
    /// - `?` matches a single character except `/`.
    /// - All other regex metacharacters are escaped.
    static func regex(forGlob pattern: String) throws -> NSRegularExpression {
        var regex = "^"
        var i = pattern.startIndex
        while i < pattern.endIndex {
            let c = pattern[i]
            if c == "*" {
                let next = pattern.index(after: i)
                if next < pattern.endIndex, pattern[next] == "*" {
                    regex += ".*"
                    i = pattern.index(after: next)
                    if i < pattern.endIndex && pattern[i] == "/" {
                        i = pattern.index(after: i)
                    }
                    continue
                }
                regex += "[^/]*"
            } else if c == "?" {
                regex += "[^/]"
            } else if ".^$+(){}|[]\\".contains(c) {
                regex.append("\\")
                regex.append(c)
            } else {
                regex.append(c)
            }
            i = pattern.index(after: i)
        }
        regex += "$"
        return try NSRegularExpression(pattern: regex)
    }
}
