import Foundation

/// Search files for a regex pattern. Shells out to `rg` when present (faster
/// and respects `.gitignore` by default), else falls back to BSD `grep -rnE`.
/// Both implementations are read-only — the model does not get a generic
/// shell through this tool, only this narrow filter.
struct AgentGrepTool: AgentTool {
    static let toolName = "grep"
    static let maxBytes = 50_000
    static let timeoutSeconds: TimeInterval = 30

    struct Arguments: Codable {
        let pattern: String
        let path: String?
        let glob: String?
        let caseInsensitive: Bool?
    }

    enum Executable {
        case ripgrep(String)
        case grep(String)

        var path: String {
            switch self {
            case let .ripgrep(p): return p
            case let .grep(p): return p
            }
        }
    }

    let spec: AgentToolSpec
    private let executable: Executable

    init(executable: Executable = AgentGrepTool.locateExecutable()) {
        let schema = try! AgentToolParametersSchema([
            "type": "object",
            "additionalProperties": false,
            "required": ["pattern"],
            "properties": [
                "pattern": [
                    "type": "string",
                    "description": "Regex pattern to search for (extended POSIX / Rust regex syntax)."
                ],
                "path": [
                    "type": "string",
                    "description": "File or directory to search. Defaults to the working directory."
                ],
                "glob": [
                    "type": "string",
                    "description": "Optional glob restricting which files are searched (e.g. `*.swift`)."
                ],
                "caseInsensitive": [
                    "type": "boolean",
                    "description": "Set to true for a case-insensitive match. Defaults to false."
                ]
            ]
        ])
        spec = AgentToolSpec(
            name: Self.toolName,
            description: "Search files under the working directory for a regex pattern. Uses ripgrep when installed, otherwise BSD grep. Output is capped at 50KB.",
            parameters: schema
        )
        self.executable = executable
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

        let searchURL: URL
        if let path = args.path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
            do {
                searchURL = try context.resolvePath(path)
            } catch let error as AgentToolError {
                return .failure(error.errorDescription ?? "path resolution failed")
            } catch {
                return .failure("path resolution failed: \(error.localizedDescription)")
            }
        } else {
            searchURL = context.workingDirectory
        }

        let invocationArgs: [String]
        switch executable {
        case .ripgrep:
            var rgArgs = [
                "--no-config",
                "--with-filename",
                "--line-number",
                "--color", "never"
            ]
            if args.caseInsensitive == true { rgArgs.append("--ignore-case") }
            if let glob = args.glob?.trimmingCharacters(in: .whitespacesAndNewlines), !glob.isEmpty {
                rgArgs += ["--glob", glob]
            }
            rgArgs += [pattern, searchURL.path]
            invocationArgs = rgArgs

        case .grep:
            var grepArgs = ["-rnE"]
            if args.caseInsensitive == true { grepArgs.append("-i") }
            if let glob = args.glob?.trimmingCharacters(in: .whitespacesAndNewlines), !glob.isEmpty {
                grepArgs += ["--include=\(glob)"]
            }
            grepArgs += [pattern, searchURL.path]
            invocationArgs = grepArgs
        }

        let result: ProcessResult
        do {
            result = try await ProcessRunner.run(
                executable: executable.path,
                arguments: invocationArgs,
                workingDirectory: context.workingDirectory,
                timeout: Self.timeoutSeconds
            )
        } catch {
            return .failure("grep launch failed: \(error.localizedDescription)")
        }

        // Both rg and grep exit 1 to mean "no matches".
        if result.exitCode == 1 && result.stdout.isEmpty {
            return .ok("(no matches)")
        }
        if result.exitCode != 0 && result.exitCode != 1 {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure("grep exited \(result.exitCode): \(stderr)")
        }

        var body = result.stdout
        body = stripPrefix(body, prefix: context.workingDirectory.path + "/")
        if body.utf8.count > Self.maxBytes {
            let truncated = Data(body.utf8.prefix(Self.maxBytes))
            body = String(decoding: truncated, as: UTF8.self)
                + "\n... [truncated at \(Self.maxBytes) bytes]"
        }
        return .ok(body.isEmpty ? "(no matches)" : body)
    }

    private func stripPrefix(_ text: String, prefix: String) -> String {
        guard !prefix.isEmpty else { return text }
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)) : String(line)
            }
            .joined(separator: "\n")
    }

    static func locateExecutable() -> Executable {
        let rgCandidates = ["/opt/homebrew/bin/rg", "/usr/local/bin/rg"]
        for path in rgCandidates where FileManager.default.isExecutableFile(atPath: path) {
            return .ripgrep(path)
        }
        return .grep("/usr/bin/grep")
    }
}
