import Foundation

/// Shared helpers used by the codemap-backed tools so they accept the
/// loose path forms a model is likely to send (absolute, leading "./",
/// trailing "/") and normalize them to the repo-relative form the store
/// keys on.
package enum AgentCodemapPath {
  /// Reduce `raw` to the repo-relative form `CodemapStore` indexes on.
  /// - Absolute paths under `workingDirectory` are made relative.
  /// - Leading `./` and trailing slashes are trimmed.
  /// - Anything not under the working directory is returned trimmed but
  ///   otherwise as-is; the caller will get a "no entry" miss, which is
  ///   the right behavior.
  package static func normalize(_ raw: String, workingDirectory: URL) -> String {
    var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.isEmpty { return s }
    if s.hasPrefix("./") { s.removeFirst(2) }
    while s.hasSuffix("/") { s.removeLast() }

    if s.hasPrefix("/") {
      let workingPath = workingDirectory.standardizedFileURL.path
      let prefix = workingPath.hasSuffix("/") ? workingPath : workingPath + "/"
      if s.hasPrefix(prefix) {
        return String(s.dropFirst(prefix.count))
      }
      if s == workingPath { return "" }
    }
    return s
  }

  /// Strip the file extension from a relative path. Used by
  /// `importers_of` to match import strings that omit the suffix.
  package static func stripExtension(_ relative: String) -> String {
    let ns = relative as NSString
    let stem = ns.deletingPathExtension
    return stem
  }

  /// Last component (filename) without its extension. Used by
  /// `importers_of` to match bare-module imports against a file's name.
  package static func basenameWithoutExtension(_ relative: String) -> String {
    let ns = (relative as NSString).lastPathComponent as NSString
    return ns.deletingPathExtension
  }

  /// Normalize a raw import string for matching. Strips `./`/`../`
  /// prefixes, trailing `/`, quotes the parser left behind, and known
  /// extensions. Lowercase-comparison is done by the caller.
  package static func normalizeImportSource(_ raw: String) -> String {
    var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    while s.hasPrefix("\"") || s.hasPrefix("'") || s.hasPrefix("`") { s.removeFirst() }
    while s.hasSuffix("\"") || s.hasSuffix("'") || s.hasSuffix("`") { s.removeLast() }
    while s.hasPrefix("./") { s.removeFirst(2) }
    while s.hasPrefix("../") { s.removeFirst(3) }
    while s.hasSuffix("/") { s.removeLast() }
    let ns = s as NSString
    let ext = ns.pathExtension.lowercased()
    let importExtensions: Set<String> = [
      "py", "pyi", "swift", "tes",
    ]
    if importExtensions.contains(ext) {
      s = ns.deletingPathExtension
    }
    return s
  }
}
