import Foundation

enum PlanVerifyCommandPolicy {
  static let placeholderExamples =
    "`true`, `exit 0`, `echo no tests`, `none`, `n/a`, or `not-running-tests`"
  static let failureMaskingExamples =
    "`swift test || true`, `swift test; true`, or `swift test || echo no tests`"

  static func normalizedCommand(_ rawCommand: String?) -> String? {
    let command = rawCommand?
      .replacingOccurrences(of: "\r", with: " ")
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return command?.isEmpty == false ? command : nil
  }

  static func isPlaceholder(_ command: String) -> Bool {
    let key = placeholderKey(command)
    if placeholderCommandKeys.contains(key) {
      return true
    }

    guard let echoMessage = shellEchoMessage(from: key) else {
      return false
    }
    return placeholderMessageKeys.contains(echoMessage)
  }

  static func masksFailures(_ command: String) -> Bool {
    let key = placeholderKey(command)
    return hasFallbackMask(in: key) || hasTrailingSequenceMask(in: key)
  }

  private static let placeholderCommandKeys: Set<String> = [
    ":",
    "/usr/bin/true",
    "builtin true",
    "command true",
    "exit 0",
    "n/a",
    "na",
    "no tests",
    "no tests available",
    "none",
    "not applicable",
    "not running tests",
    "not-running-tests",
    "return 0",
    "skip tests",
    "skipping tests",
    "true",
  ]

  private static let placeholderMessageKeys: Set<String> = [
    "done",
    "n/a",
    "na",
    "no test",
    "no tests",
    "no tests available",
    "none",
    "not applicable",
    "not running tests",
    "not-running-tests",
    "ok",
    "pass",
    "passed",
    "skip tests",
    "skipping tests",
    "success",
    "successful",
    "tests pass",
    "tests passed",
    "tests skipped",
    "true",
    "verification pass",
    "verification passed",
    "verification skipped",
    "verify skipped",
  ]

  private static func shellEchoMessage(from key: String) -> String? {
    for prefix in ["echo ", "/bin/echo ", "/usr/bin/echo "] where key.hasPrefix(prefix) {
      var message = String(key.dropFirst(prefix.count))
      while let flag = ["-e", "-n", "-ne", "-en"].first(where: {
        message == $0 || message.hasPrefix("\($0) ")
      }) {
        message = message == flag
          ? ""
          : String(message.dropFirst(flag.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
      }
      return placeholderKey(message)
    }
    return nil
  }

  private static func hasFallbackMask(in key: String) -> Bool {
    let clauses = key.components(separatedBy: "||")
    guard clauses.count > 1 else { return false }
    return clauses.dropFirst().contains { clauseStartsWithPlaceholder($0) }
  }

  private static func hasTrailingSequenceMask(in key: String) -> Bool {
    let clauses = key.components(separatedBy: ";")
    guard clauses.count > 1, let trailing = clauses.last else { return false }
    return isPlaceholderClause(trailing)
  }

  private static func clauseStartsWithPlaceholder(_ clause: String) -> Bool {
    let trimmed = placeholderKey(clause)
    if isPlaceholderClause(trimmed) {
      return true
    }
    for separator in ["&&", ";"] {
      guard let range = trimmed.range(of: separator) else { continue }
      let prefix = String(trimmed[..<range.lowerBound])
      if isPlaceholderClause(prefix) {
        return true
      }
    }
    return false
  }

  private static func isPlaceholderClause(_ clause: String) -> Bool {
    let key = placeholderKey(clause)
    if placeholderCommandKeys.contains(key) {
      return true
    }
    guard let echoMessage = shellEchoMessage(from: key) else {
      return false
    }
    return placeholderMessageKeys.contains(echoMessage)
  }

  private static func placeholderKey(_ text: String) -> String {
    var key = text
      .lowercased()
      .replacingOccurrences(of: #"\s+#.*$"#, with: "", options: .regularExpression)
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    key = stripWrappingQuotes(key)
    key = key.trimmingCharacters(
      in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ";."))
    )
    return stripWrappingQuotes(key)
  }

  private static func stripWrappingQuotes(_ text: String) -> String {
    var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let quotes: Set<Character> = ["\"", "'", "`"]
    while result.count >= 2,
      let first = result.first,
      let last = result.last,
      first == last,
      quotes.contains(first)
    {
      result = String(result.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return result
  }
}
