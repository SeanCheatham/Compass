import Foundation

/// VCS-agnostic revision metadata for `file_history`.
public struct RepoRevisionSummary: Equatable, Sendable {
  public var id: String
  public var shortId: String
  public var date: String
  public var author: String
  public var subject: String

  public init(id: String, shortId: String, date: String, author: String, subject: String) {
    self.id = id
    self.shortId = shortId
    self.date = date
    self.author = author
    self.subject = subject
  }
}

/// VCS-agnostic per-line annotation for `annotate`.
public struct RepoAnnotationLine: Equatable, Sendable {
  public var line: Int
  public var shortId: String
  public var date: String
  public var author: String
  public var subject: String
  public var text: String

  public init(
    line: Int,
    shortId: String,
    date: String,
    author: String,
    subject: String,
    text: String
  ) {
    self.line = line
    self.shortId = shortId
    self.date = date
    self.author = author
    self.subject = subject
    self.text = text
  }
}

public enum RepoHistoryError: LocalizedError, Equatable, Sendable {
  case unavailable(String)
  case commandFailed(String)

  public var errorDescription: String? {
    switch self {
    case .unavailable(let detail):
      return detail
    case .commandFailed(let detail):
      return detail
    }
  }
}

/// Host-side version history backed by Git today. Tool names stay VCS-agnostic.
public enum RepoHistoryProvider {
  public static let defaultHistoryLimit = 20
  public static let maxHistoryLimit = 50
  public static let defaultAnnotateMaxLines = 400
  public static let maxAnnotateOutputBytes = 50_000
  public static let timeoutSeconds: TimeInterval = 30

  public static func hasVersionHistory(at repoRoot: URL) async -> Bool {
    let result = try? await runGit(
      repoRoot: repoRoot,
      args: ["rev-parse", "--is-inside-work-tree"]
    )
    guard let result, result.exitCode == 0 else { return false }
    return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
  }

  public static func fileHistory(
    repoRoot: URL,
    relativePath: String,
    limit: Int = defaultHistoryLimit
  ) async throws -> [RepoRevisionSummary] {
    guard await hasVersionHistory(at: repoRoot) else {
      throw RepoHistoryError.unavailable(
        "No version history available for this workspace (not a Git repository on the host)."
      )
    }
    let capped = min(max(1, limit), maxHistoryLimit)
    let result = try await runGit(
      repoRoot: repoRoot,
      args: [
        "log",
        "--follow",
        "-n", "\(capped)",
        "--date=short",
        "--format=%H\t%h\t%ad\t%an\t%s",
        "--",
        relativePath,
      ]
    )
    guard result.exitCode == 0 else {
      let detail = (result.stderr.isEmpty ? result.stdout : result.stderr)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      throw RepoHistoryError.commandFailed(
        detail.isEmpty ? "Unable to read file history for \(relativePath)." : detail
      )
    }
    return result.stdout.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
      let parts = line.split(separator: "\t", maxSplits: 4, omittingEmptySubsequences: false)
      guard parts.count == 5 else { return nil }
      return RepoRevisionSummary(
        id: String(parts[0]),
        shortId: String(parts[1]),
        date: String(parts[2]),
        author: String(parts[3]),
        subject: String(parts[4])
      )
    }
  }

  public static func annotate(
    repoRoot: URL,
    relativePath: String,
    startLine: Int?,
    endLine: Int?
  ) async throws -> [RepoAnnotationLine] {
    guard await hasVersionHistory(at: repoRoot) else {
      throw RepoHistoryError.unavailable(
        "No version history available for this workspace (not a Git repository on the host)."
      )
    }

    var args = ["blame", "--line-porcelain"]
    let range = blameRange(startLine: startLine, endLine: endLine)
    args += ["-L", "\(range.start),\(range.end)", "--", relativePath]

    let result = try await runGit(repoRoot: repoRoot, args: args)
    guard result.exitCode == 0 else {
      let detail = (result.stderr.isEmpty ? result.stdout : result.stderr)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      throw RepoHistoryError.commandFailed(
        detail.isEmpty ? "Unable to annotate \(relativePath)." : detail
      )
    }
    return parseBlamePorcelain(result.stdout)
  }

  public static func formatHistory(_ revisions: [RepoRevisionSummary], displayPath: String) -> String
  {
    if revisions.isEmpty {
      return "No revisions found for \(displayPath)."
    }
    var lines = ["History for \(displayPath) (\(revisions.count) revision(s)):"]
    for rev in revisions {
      lines.append("\(rev.shortId)  \(rev.date)  \(rev.author)  \(rev.subject)")
    }
    return lines.joined(separator: "\n")
  }

  public static func formatAnnotations(
    _ annotations: [RepoAnnotationLine],
    displayPath: String
  ) -> String {
    if annotations.isEmpty {
      return "No annotations for \(displayPath)."
    }
    var lines = ["Annotations for \(displayPath):"]
    for row in annotations {
      let text = row.text.replacingOccurrences(of: "\t", with: " ")
      lines.append(
        "\(row.line)\t\(row.shortId)\t\(row.date)\t\(row.author)\t\(row.subject)\t\(text)"
      )
    }
    var body = lines.joined(separator: "\n")
    if body.utf8.count > maxAnnotateOutputBytes {
      body = String(body.prefix(maxAnnotateOutputBytes))
      body += "\n… truncated (annotation output limit)."
    }
    return body
  }

  /// Clamp optional line range; default window is the first `defaultAnnotateMaxLines` lines.
  public static func blameRange(startLine: Int?, endLine: Int?) -> (start: Int, end: Int) {
    let start = max(1, startLine ?? 1)
    let requestedEnd = endLine ?? (start + defaultAnnotateMaxLines - 1)
    let end = max(start, min(requestedEnd, start + defaultAnnotateMaxLines - 1))
    return (start, end)
  }

  static func parseBlamePorcelain(_ stdout: String) -> [RepoAnnotationLine] {
    var rows: [RepoAnnotationLine] = []
    var currentSHA = ""
    var currentLine = 0
    var author = ""
    var authorTime = ""
    var summary = ""
    let lines = stdout.split(separator: "\n", omittingEmptySubsequences: false)

    for raw in lines {
      let line = String(raw)
      if line.hasPrefix("\t") {
        let text = String(line.dropFirst())
        let shortId = currentSHA.isEmpty ? "?" : String(currentSHA.prefix(8))
        let date = formatUnixDate(authorTime)
        rows.append(
          RepoAnnotationLine(
            line: currentLine,
            shortId: shortId,
            date: date,
            author: author.isEmpty ? "?" : author,
            subject: summary.isEmpty ? "?" : summary,
            text: text
          )
        )
        continue
      }

      if line.hasPrefix("author ") {
        author = String(line.dropFirst("author ".count))
        continue
      }
      if line.hasPrefix("author-time ") {
        authorTime = String(line.dropFirst("author-time ".count))
        continue
      }
      if line.hasPrefix("summary ") {
        summary = String(line.dropFirst("summary ".count))
        continue
      }
      // Header: <sha> <orig> <final> [<num>]
      let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
      if parts.count >= 3, parts[0].count >= 7, parts[0].allSatisfy({ $0.isHexDigit }) {
        currentSHA = String(parts[0])
        currentLine = Int(parts[2]) ?? currentLine
        // New blame hunk resets metadata that follows.
        author = ""
        authorTime = ""
        summary = ""
      }
    }
    return rows
  }

  private static func formatUnixDate(_ raw: String) -> String {
    guard let epoch = TimeInterval(raw) else { return raw.isEmpty ? "?" : raw }
    let date = Date(timeIntervalSince1970: epoch)
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }

  private static func runGit(repoRoot: URL, args: [String]) async throws -> ProcessResult {
    try await ProcessRunner.run(
      executable: "/usr/bin/git",
      arguments: ["-C", repoRoot.path] + args,
      workingDirectory: repoRoot,
      timeout: timeoutSeconds
    )
  }
}

extension Character {
  fileprivate var isHexDigit: Bool {
    ("0"..."9").contains(self) || ("a"..."f").contains(self) || ("A"..."F").contains(self)
  }
}
