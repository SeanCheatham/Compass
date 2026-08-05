import Foundation

public enum PlainTextListPrefix {
  public static func strippedEntry(from rawLine: String) -> String? {
    let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !line.isEmpty else { return nil }

    if let range = line.range(of: #"^[-*•◦▪▫–—]\s+"#, options: .regularExpression) {
      return cleanedTaskPrefix(
        String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
      )
    }

    if let range = line.range(of: #"^\d{1,3}[\.)]\s+"#, options: .regularExpression) {
      return cleanedTaskPrefix(
        String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
      )
    }

    guard let task = strippedTaskPrefix(from: line) else { return nil }
    return task
  }

  public static func cleanedLine(_ rawLine: String) -> String {
    strippedEntry(from: rawLine)
      ?? rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func cleanedTaskPrefix(_ line: String) -> String {
    strippedTaskPrefix(from: line) ?? line
  }

  private static func strippedTaskPrefix(from line: String) -> String? {
    guard let range = line.range(of: #"^\[( |x|X)\]\s*"#, options: .regularExpression)
    else { return nil }
    return String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
