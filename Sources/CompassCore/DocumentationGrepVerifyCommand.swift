import Foundation

package struct DocumentationGrepVerifyCommand: Equatable, Sendable {
  package var pattern: String
  package var path: String
  package var flags: String

  package static func parse(_ command: String) -> DocumentationGrepVerifyCommand? {
    let pattern =
      #"^\s*(?:/usr/bin/)?grep\s+(-[A-Za-z]*q[A-Za-z]*)\s+("[^"]+"|'[^']+'|[^\s;&|]+)\s+([\w./-]+\.(?:md|markdown|txt|rst))\s*$"#
    guard
      let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
      let match = regex.firstMatch(
        in: command,
        range: NSRange(command.startIndex..<command.endIndex, in: command)
      ),
      match.numberOfRanges == 4,
      let flagsRange = Range(match.range(at: 1), in: command),
      let patternRange = Range(match.range(at: 2), in: command),
      let pathRange = Range(match.range(at: 3), in: command)
    else {
      return nil
    }

    let flags = String(command[flagsRange]).dropFirst()
    guard flags.contains("q") else { return nil }
    let allowedFlags = Set("qiEF")
    guard flags.allSatisfy({ allowedFlags.contains($0) }) else { return nil }

    let path = String(command[pathRange])
    guard isSafeRelativeDocumentationPath(path) else { return nil }

    return DocumentationGrepVerifyCommand(
      pattern: unquote(String(command[patternRange])),
      path: path,
      flags: String(flags)
    )
  }

  package var grepArguments: [String] {
    var arguments = ["-\(flags)", "--", pattern, path]
    if !flags.contains("q") {
      arguments[0] += "q"
    }
    return arguments
  }

  package func run(in repoURL: URL, timeoutSeconds: TimeInterval) async throws -> ProcessResult {
    try await ProcessRunner.runEnv(
      "grep",
      grepArguments,
      workingDirectory: repoURL,
      timeout: timeoutSeconds
    )
  }

  private static func unquote(_ raw: String) -> String {
    guard raw.count >= 2 else { return raw }
    let first = raw.first
    let last = raw.last
    if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
      return String(raw.dropFirst().dropLast())
    }
    return raw
  }

  private static func isSafeRelativeDocumentationPath(_ path: String) -> Bool {
    guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("-") else { return false }
    let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    guard !components.isEmpty else { return false }
    return components.allSatisfy { component in
      !component.isEmpty && component != "." && component != ".."
    }
  }
}
