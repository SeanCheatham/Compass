import Darwin
import Foundation

/// Minimal `.env` file loader for headless CLI runs.
///
/// Parses `KEY=VALUE` lines (supporting `export ` prefixes, `#` comments, and
/// single/double quoted values) and applies them via `setenv` without
/// overriding variables already present in the process environment.
public enum DotEnvLoader {
  public static func loadIntoEnvironment(from directory: URL) -> [String] {
    var applied: [String] = []
    for name in [".env.local", ".env"] {
      let url = directory.appending(path: name)
      guard let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }
      for (key, value) in parse(contents) where getenv(key) == nil {
        setenv(key, value, 0)
        applied.append(key)
      }
    }
    return applied
  }

  public static func parse(_ contents: String) -> [(key: String, value: String)] {
    var pairs: [(String, String)] = []
    for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
      var line = rawLine.trimmingCharacters(in: .whitespaces)
      if line.isEmpty || line.hasPrefix("#") { continue }
      if line.hasPrefix("export ") {
        line = String(line.dropFirst("export ".count))
          .trimmingCharacters(in: .whitespaces)
      }
      guard let separator = line.firstIndex(of: "=") else { continue }
      let key = String(line[line.startIndex..<separator]).trimmingCharacters(in: .whitespaces)
      guard !key.isEmpty,
        key.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil
      else { continue }
      var value = String(line[line.index(after: separator)...])
        .trimmingCharacters(in: .whitespaces)
      if let first = value.first, first == "\"" || first == "'" {
        let rest = value.dropFirst()
        if let closing = rest.firstIndex(of: first) {
          value = String(rest[rest.startIndex..<closing])
        }
      } else if let comment = value.range(of: " #") {
        value = String(value[value.startIndex..<comment.lowerBound])
          .trimmingCharacters(in: .whitespaces)
      }
      pairs.append((key, value))
    }
    return pairs
  }
}
