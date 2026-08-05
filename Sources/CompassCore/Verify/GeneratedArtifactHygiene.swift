import Foundation

public struct GeneratedArtifactHygieneIssue: Equatable {
  public var path: String
  public var reason: String
}

public enum GeneratedArtifactHygiene {
  private static let generatedRootDirectories: Set<String> = [
    ".build",
    ".dart_tool",
    ".next",
    ".svelte-kit",
    ".turbo",
    ".venv",
    "DerivedData",
    "build",
    "coverage",
    "dist",
    "node_modules",
    "target",
    "venv",
  ]

  /// Directory names that flag a generated path anywhere in the tree (not only
  /// as the repository root). Kept stricter than root directories so source
  /// folders named `build/` are not over-matched mid-tree.
  private static let generatedPathComponents: Set<String> = [
    ".build",
    ".dart_tool",
    ".next",
    ".svelte-kit",
    ".turbo",
    ".venv",
    "DerivedData",
    "__pycache__",
    "coverage",
    "dist",
    "node_modules",
    "target",
    "venv",
    "xcuserdata",
  ]

  private static let generatedFileNames: Set<String> = [
    "__.SYMDEF",
    "__.SYMDEF SORTED",
    "CACHEDIR.TAG",
  ]

  private static let generatedExtensions: Set<String> = [
    "a",
    "class",
    "d",
    "dll",
    "dylib",
    "o",
    "pyc",
    "pyo",
    "rlib",
    "rmeta",
    "so",
    "swiftmodule",
    "swiftdoc",
    "swiftsourceinfo",
  ]

  public static func issues(fromGitNameStatus output: String) -> [GeneratedArtifactHygieneIssue] {
    let paths = changedPaths(fromGitNameStatus: output)
    return issues(forChangedPaths: paths)
  }

  public static func issues(forChangedPaths paths: [String]) -> [GeneratedArtifactHygieneIssue] {
    paths.compactMap { path in
      guard let reason = generatedArtifactReason(for: path) else { return nil }
      return GeneratedArtifactHygieneIssue(path: path, reason: reason)
    }
  }

  public static func formattedIssue(from issues: [GeneratedArtifactHygieneIssue], limit: Int = 12)
    -> String?
  {
    guard !issues.isEmpty else { return nil }
    let shown = issues.prefix(max(1, limit))
      .map { "- `\($0.path)`: \($0.reason)" }
      .joined(separator: "\n")
    let hiddenCount = max(0, issues.count - max(1, limit))
    let hiddenLine = hiddenCount > 0 ? "\n- ...and \(hiddenCount) more generated artifact(s)" : ""
    return """
      [artifact-hygiene] Generated build artifacts were changed by this increment:
      \(shown)\(hiddenLine)

      Remove generated outputs from the commit and add or update `.gitignore` so future verify/build runs do not land them.
      """
  }

  private static func changedPaths(fromGitNameStatus output: String) -> [String] {
    output
      .split(whereSeparator: \.isNewline)
      .compactMap { line -> String? in
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard let status = fields.first else { return nil }
        if status.hasPrefix("D") { return nil }
        guard let rawPath = fields.last else { return nil }
        return String(rawPath).trimmingCharacters(in: .whitespacesAndNewlines)
      }
      .filter { !$0.isEmpty }
  }

  private static func generatedArtifactReason(for path: String) -> String? {
    let normalized = path.replacingOccurrences(of: "\\", with: "/")
    let components = normalized.split(separator: "/", omittingEmptySubsequences: true)
      .map(String.init)
    guard !components.isEmpty else { return nil }

    if let first = components.first, generatedRootDirectories.contains(first) {
      return "inside generated directory `\(first)/`"
    }
    if let component = components.first(where: { generatedPathComponents.contains($0) }) {
      return "inside generated directory component `\(component)/`"
    }
    if let component = components.first(where: { $0.hasSuffix(".egg-info") }) {
      return "inside generated directory component `\(component)/`"
    }
    if let fileName = components.last, generatedFileNames.contains(fileName) {
      return "generated archive/cache marker"
    }

    let fileName = components.last ?? normalized
    let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
    if generatedExtensions.contains(ext) {
      return "generated binary/build artifact extension `.\(ext)`"
    }
    return nil
  }
}
