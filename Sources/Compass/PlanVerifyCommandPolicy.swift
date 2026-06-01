import Foundation

enum PlanVerifyCommandPolicy {
  static let placeholderExamples =
    "`true`, `exit 0`, `echo no tests`, `none`, `n/a`, or `not-running-tests`"

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
    "skip tests",
    "skipping tests",
    "tests skipped",
    "true",
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
