import Foundation

/// Path allowlists for health agent writes, keyed by focus.
public enum HealthWritePolicy {
  public static func allows(relativePath: String, focus: HealthFocus) -> Bool {
    let path = normalize(relativePath)
    guard !path.isEmpty, !path.hasPrefix(".git/"), path != ".git" else { return false }
    if path.hasPrefix(".compass/") || path == ".compass" { return false }

    switch focus {
    case .bugHunt:
      let name = (path as NSString).lastPathComponent
      return path.hasPrefix("tests/") && HealthPaths.isGeneratedTestFileName(name)
    case .test:
      return path.hasPrefix("tests/")
    case .docs:
      if path.hasPrefix("docs/") { return true }
      let name = (path as NSString).lastPathComponent.lowercased()
      if name.hasPrefix("readme") { return true }
      return name.hasSuffix(".md")
    case .cleanup:
      // Behavior-preserving cleanup may touch sources; still block VCS/Compass state.
      return true
    }
  }

  public static func rejectionMessage(relativePath: String, focus: HealthFocus) -> String {
    "Health focus `\(focus.rawValue)` refuses writes to `\(relativePath)`."
  }

  private static func normalize(_ raw: String) -> String {
    var path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if path.hasPrefix("./") { path = String(path.dropFirst(2)) }
    while path.hasPrefix("/") { path = String(path.dropFirst()) }
    return path.replacingOccurrences(of: "\\", with: "/")
  }
}
