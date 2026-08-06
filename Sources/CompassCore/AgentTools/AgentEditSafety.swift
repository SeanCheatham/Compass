import Foundation

/// Shared post-edit safety checks used by both the native string-replace
/// `edit_file` tool and the legacy line-range editor.
public enum AgentEditSafety {
  public struct PlaceholderMarker: Equatable, Sendable {
    public let lineNumber: Int
    public let preview: String
  }

  /// Returns a rejection message when the edit would leave a non-empty
  /// source file empty, introduce a new TODO/placeholder implementation
  /// marker, or otherwise look like a stubbed rewrite. `nil` means OK.
  public static func validatePostEdit(
    relativePath: String,
    sourceURL: URL,
    originalText: String,
    editedText: String
  ) -> String? {
    guard isSourceFile(sourceURL) else { return nil }

    if !originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return
        "edit_file would leave \(relativePath) empty after editing a non-empty source file. Do not clear a source file as a placeholder; provide complete replacementLines for the implementation, or submit status=failed/status=blocked if you cannot reconstruct it."
    }

    if let placeholder = newPlaceholderImplementationMarker(
      originalText: originalText,
      editedText: editedText
    ) {
      return
        "edit_file would introduce placeholder implementation code in \(relativePath) at line \(placeholder.lineNumber): \(placeholder.preview). Do not replace working source with TODO/not-implemented placeholders; provide the complete implementation now, or submit status=failed/status=blocked if you cannot."
    }

    return nil
  }

  public static func isSourceFile(_ url: URL) -> Bool {
    [
      "c", "cc", "cpp", "css", "go", "h", "hpp", "html", "js", "jsx", "mjs", "mts", "py", "rs",
      "swift", "ts", "tsx",
    ].contains(url.pathExtension.lowercased())
  }

  public static func isTestFile(_ url: URL) -> Bool {
    let path = url.path.lowercased()
    let filename = url.lastPathComponent.lowercased()
    return path.contains("/tests/")
      || filename.hasSuffix("_test.rs")
      || filename.contains(".test.")
      || filename.contains(".spec.")
      || path.contains("/__tests__/")
  }

  /// Returns a short preview when `text` contains bare `#[test]` / `mod tests`
  /// outside a `#[cfg(test)]` module in production Rust sources. Allows the
  /// grandfathered unit-test pattern:
  /// `#[cfg(test)] mod tests { #[test] fn ... }`.
  public static func inappropriateBareRustTestCode(in text: String) -> String? {
    var pendingCfgTest = false
    var cfgTestDepth: Int? = nil
    for rawLine in text.components(separatedBy: "\n") {
      let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.hasPrefix("#[cfg(test)]") {
        pendingCfgTest = true
      }

      let opens = rawLine.filter { $0 == "{" }.count
      let closes = rawLine.filter { $0 == "}" }.count

      if pendingCfgTest,
        trimmed.range(of: #"^mod\s+\w+"#, options: .regularExpression) != nil
      {
        pendingCfgTest = false
        cfgTestDepth = 0
      }

      let isBareTest =
        trimmed.hasPrefix("#[test]")
        || trimmed.hasPrefix("#[tokio::test]")
        || trimmed.range(of: #"^mod\s+tests\b"#, options: .regularExpression) != nil

      if isBareTest, cfgTestDepth == nil {
        return "`\(String(trimmed.prefix(120)))`"
      }

      if var depth = cfgTestDepth {
        depth += opens - closes
        cfgTestDepth = depth > 0 ? depth : nil
      } else if pendingCfgTest, opens > 0 {
        // `#[cfg(test)]` followed by an inline block without `mod`.
        pendingCfgTest = false
        let depth = opens - closes
        cfgTestDepth = depth > 0 ? depth : nil
      }
    }
    return nil
  }

  public static func newPlaceholderImplementationMarker(
    originalText: String,
    editedText: String
  ) -> PlaceholderMarker? {
    let originalFingerprints = Set(
      placeholderImplementationMarkers(in: originalText).map(\.fingerprint)
    )
    return placeholderImplementationMarkers(in: editedText).first {
      !originalFingerprints.contains($0.fingerprint)
    }.map {
      PlaceholderMarker(lineNumber: $0.lineNumber, preview: $0.preview)
    }
  }

  private struct InternalPlaceholder {
    let lineNumber: Int
    let preview: String
    let fingerprint: String
  }

  private static func placeholderImplementationMarkers(in text: String) -> [InternalPlaceholder] {
    text.components(separatedBy: "\n").enumerated().compactMap { offset, line in
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      let fingerprint = trimmed.lowercased()
      guard looksLikePlaceholderImplementation(fingerprint) else { return nil }
      return InternalPlaceholder(
        lineNumber: offset + 1,
        preview: "`\(String(trimmed.prefix(120)))`",
        fingerprint: fingerprint
      )
    }
  }

  private static func looksLikePlaceholderImplementation(_ lowercasedLine: String) -> Bool {
    (lowercasedLine.contains("todo")
      && (lowercasedLine.contains("implement") || lowercasedLine.contains("placeholder")))
      || lowercasedLine.contains("not implemented")
      || lowercasedLine.contains("unimplemented")
      || lowercasedLine.contains("placeholder implementation")
      || (lowercasedLine.contains("replace this with")
        && lowercasedLine.contains("implementation"))
      || lowercasedLine.contains("implement the logic")
      || lowercasedLine.contains("implement logic")
  }
}
