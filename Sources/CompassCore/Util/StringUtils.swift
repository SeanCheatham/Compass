import Foundation

public struct StringUtils {
  /// Collapses whitespace and newlines, then truncates at `limit`, preferring a
  /// word boundary when one exists inside the budget. Does not append an
  /// ellipsis so callers that embed the result in identifiers stay stable.
  public static func boundedText(_ text: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    let normalized =
      text
      .replacingOccurrences(of: "\r", with: " ")
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalized.count > limit else { return normalized }

    let end = normalized.index(normalized.startIndex, offsetBy: limit)
    let prefix = normalized[..<end]
    // Only retreat to a prior word boundary when the cut lands mid-word.
    if end < normalized.endIndex, normalized[end] != " ",
      let lastSpace = prefix.lastIndex(where: { $0 == " " }), lastSpace > prefix.startIndex
    {
      let cut = String(prefix[..<lastSpace]).trimmingCharacters(in: .whitespacesAndNewlines)
      if !cut.isEmpty { return cut }
    }
    return String(prefix).trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

extension String {
  /// Trimmed contents, or nil when the string is only whitespace.
  var nilIfBlank: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
