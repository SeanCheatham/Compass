import Foundation

/// Exact-span dead-code seed from rustc lint diagnostics.
public struct DeadCodeCandidate: Codable, Equatable, Sendable, Identifiable {
  public var id: String
  public var file: String
  public var startLine: Int
  public var endLine: Int
  public var symbol: String?
  public var lint: String
  public var message: String

  public init(
    id: String = UUID().uuidString,
    file: String,
    startLine: Int,
    endLine: Int,
    symbol: String? = nil,
    lint: String,
    message: String
  ) {
    self.id = id
    self.file = file.trimmingCharacters(in: .whitespacesAndNewlines)
    self.startLine = max(1, startLine)
    self.endLine = max(self.startLine, endLine)
    let trimmedSymbol = symbol?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    self.symbol = trimmedSymbol.isEmpty ? nil : trimmedSymbol
    self.lint = lint.trimmingCharacters(in: .whitespacesAndNewlines)
    self.message = message.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public var lineCount: Int { endLine - startLine + 1 }

  public var shortLabel: String {
    if let symbol, !symbol.isEmpty {
      return "`\(symbol)` @ \(file):\(startLine)"
    }
    return "\(file):\(startLine)-\(endLine) (\(lint))"
  }
}

public enum DeadCodeCandidateParser {
  public static let watchedLints: Set<String> = [
    "dead_code",
    "unused_imports",
    "unused_macros",
    "unused",
  ]

  /// Parse `cargo check --message-format=json` stdout (NDJSON) into dead-code candidates.
  public static func parse(cargoJSONLines: String) -> [DeadCodeCandidate] {
    var candidates: [DeadCodeCandidate] = []
    var seen = Set<String>()
    for rawLine in cargoJSONLines.split(separator: "\n", omittingEmptySubsequences: true) {
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !line.isEmpty,
        let data = line.data(using: .utf8),
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      else { continue }
      guard (obj["reason"] as? String) == "compiler-message",
        let message = obj["message"] as? [String: Any]
      else { continue }

      let lint = lintCode(from: message)
      guard watchedLints.contains(lint) else { continue }
      let level = (message["level"] as? String)?.lowercased() ?? ""
      // Accept warnings and errors; skip notes/help.
      guard level == "warning" || level == "error" else { continue }

      let text = (message["message"] as? String) ?? ""
      let spans = (message["spans"] as? [[String: Any]]) ?? []
      let primary =
        spans.first(where: { ($0["is_primary"] as? Bool) == true }) ?? spans.first
      guard let primary,
        let file = primary["file_name"] as? String,
        let start = primary["line_start"] as? Int,
        let end = primary["line_end"] as? Int
      else { continue }

      // Skip dependency / build-script noise outside the workspace sources.
      if file.contains("/.cargo/") || file.hasPrefix("/rustc/") { continue }

      let symbol = extractSymbol(from: text)
      let key = "\(file)|\(start)|\(end)|\(lint)|\(symbol ?? "")"
      guard !seen.contains(key) else { continue }
      seen.insert(key)

      candidates.append(
        DeadCodeCandidate(
          file: normalizeRepoRelativePath(file),
          startLine: start,
          endLine: end,
          symbol: symbol,
          lint: lint,
          message: text
        )
      )
    }
    return candidates.sorted {
      if $0.file != $1.file { return $0.file < $1.file }
      return $0.startLine < $1.startLine
    }
  }

  public static let checkCommand =
    "cargo check --workspace --all-targets --message-format=json 2>/dev/null | tail -c 4000000"

  private static func lintCode(from message: [String: Any]) -> String {
    if let code = message["code"] as? [String: Any], let name = code["code"] as? String {
      return name
    }
    return ""
  }

  private static func extractSymbol(from message: String) -> String? {
    // function `foo` is never used / struct `Bar` is never constructed / unused import: `baz`
    let patterns = [
      #"`([^`]+)` is never"#,
      #"unused import: `([^`]+)`"#,
      #"unused imports: `([^`]+)`"#,
      #"unused macro definition: `([^`]+)`"#,
    ]
    for pattern in patterns {
      guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
      let range = NSRange(message.startIndex..<message.endIndex, in: message)
      if let match = regex.firstMatch(in: message, range: range), match.numberOfRanges > 1,
        let r = Range(match.range(at: 1), in: message)
      {
        return String(message[r])
      }
    }
    return nil
  }

  private static func normalizeRepoRelativePath(_ path: String) -> String {
    // cargo may emit absolute paths; prefer the trailing crates/... or src/... segment.
    if path.hasPrefix("/") {
      for marker in ["/crates/", "/src/", "/apps/", "/tests/"] {
        if let range = path.range(of: marker) {
          return String(path[range.lowerBound...].dropFirst())  // drop leading /
        }
      }
      return (path as NSString).lastPathComponent
    }
    return path
  }
}
