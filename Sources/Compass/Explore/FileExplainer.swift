import Foundation

#if canImport(FoundationModels)
  import FoundationModels
#endif

/// Represents a single changed file with its metadata and optional codemap summary.
struct FileChange: Identifiable, Equatable {
  let id: String
  let relativePath: String
  let language: CodemapLanguage?
  let additions: Int
  let deletions: Int
  let summary: String?
  let explanation: String?
  let category: FileChangeCategory

  init(
    relativePath: String,
    additions: Int,
    deletions: Int,
    language: CodemapLanguage?,
    summary: String?,
    explanation: String? = nil
  ) {
    self.id = relativePath
    self.relativePath = relativePath
    self.additions = additions
    self.deletions = deletions
    self.language = language
    self.summary = summary
    self.explanation = explanation
    self.category = FileChangeCategory.categorize(relativePath)
  }

  /// One-line file name without any directory prefix.
  var fileName: String {
    (relativePath as NSString).lastPathComponent
  }

  /// Short "+N/-N" line-count label.
  var lineCountLabel: String {
    "\(additions > 0 ? "+\(additions)" : "0")/\(deletions > 0 ? "-\(deletions)" : "0")"
  }
}

/// Category for grouping file changes in the explore popover.
enum FileChangeCategory: String, CaseIterable {
  case source = "Sources"
  case test = "Tests"
  case config = "Config"
  case other = "Other"

  /// Sort order used for consistent presentation ordering.
  var sortOrder: Int {
    switch self {
    case .source: return 0
    case .test: return 1
    case .config: return 2
    case .other: return 3
    }
  }

  /// Classify a file path into a category.
  static func categorize(_ relativePath: String) -> FileChangeCategory {
    let dir = (relativePath as NSString).deletingLastPathComponent
    let lower = relativePath.lowercased()

    // Tests — test dirs and test files
    if dir.hasPrefix("Tests") || dir.contains("/Tests/") || dir.contains("\\Tests\\") {
      return .test
    }
    if lower.hasSuffix("_tests.swift")
      || lower.hasSuffix(".test.swift")
      || lower.hasSuffix(".spec.swift")
    {
      return .test
    }
    if lower.hasPrefix("test"),
      lower.contains("test_") || lower.hasSuffix("_test.swift")
    {
      return .test
    }
    if dir.hasPrefix("test") {
      return .test
    }

    // Config — explicit config files or common config directories
    let configDirs = [
      "Config", "config", ".config", "configs", "settings",
      ".vscode", ".idea", ".github", ".gitlab",
    ]
    if configDirs.contains(where: {
      dir.hasPrefix($0) || dir.hasPrefix("\($0)/") || dir.hasPrefix("\($0)\\")
    }) {
      return .config
    }
    let configFiles = [
      "package.json", "tsconfig.json", "build.gradle", "Makefile", "Dockerfile",
      ".gitignore", ".gitattributes", ".env", ".env.local", ".env.development",
      "podfile", "cartfile", "module.modulemap", "Sources/Compass/Compass.entitlements",
      ".swift-format", ".swiftlint.yml", "dangerfile", "mint.yml", "Package.swift",
      "project.yml", "Appfile",
    ]
    if configFiles.contains((relativePath as NSString).lastPathComponent) {
      return .config
    }

    // Source code — anything with a known language extension
    if CodemapLanguage.forRelativePath(relativePath) != nil {
      return .source
    }

    return .other
  }
}


/// Provides the two-contract interface for exploring changed files in a commit range.
///
/// ## Two-method contract
///
/// - ``changes(for:commits:)``: Returns all changed files with line-count stats
///   and codemap summaries. The result feeds directly into the Explore popover
///   file list (codemap entry → `FileChange` → UI).
///
/// - ``explain(file:repoURL:commits:)``: Returns a plain-English AI summary for
///   a single file by running `git diff` over the relevant commit range and
///   passing the result to ``CommitExplainer/summarize(diff:)``.
///
/// ## Commit ordering rule
///
/// Callers pass the commit list in insertion order — newest first. Internally,
/// ``changes(for:commits:)`` does NOT reverse the array; the git range it
/// passes is `newest..oldest`. Single-commit calls use `sha^..sha` directly.
///
/// ## Foundation Models boundary
///
/// ``explain(file:repoURL:commits:)`` crosses into Foundation Models via
/// ``CommitExplainer``. ``changes(for:commits:)`` is purely a git/codemap
/// operation and never calls the model.
enum FileExplainer {
  /// Returns a plain-English explanation for a single changed file by running
  /// `git diff` over the relevant commit range and passing the result to
  /// `CommitExplainer.summarize(diff:)`.
  ///
  /// - Parameters:
  ///   - relativePath: The repo-relative path of the file to explain.
  ///   - repoURL: The working-copy root of the repository.
  ///   - commits: Commits to diff, in insertion order (newest first).  Single-
  ///     commit uses `sha^..sha`; multi-commit uses `newest..oldest` internally.
  /// - Returns: An AI-generated explanation, or `nil` if no commits are
  ///   available, no diff exists for the file, or Foundation Models is
  ///   unavailable
  static func explain(
    file relativePath: String,
    repoURL: URL,
    commits: [SessionCommit]
  ) async -> String? {
    guard let first = commits.first else { return nil }

    let diff: String
    if commits.count == 1 {
      let result = try? await ProcessRunner.runEnv(
        "git", ["diff", "\(first.sha)^..\(first.sha)", "--", relativePath],
        workingDirectory: repoURL
      )
      diff = result?.stdout ?? ""
    } else if let last = commits.last {
      let result = try? await ProcessRunner.runEnv(
        "git", ["diff", "\(last.sha)..\(first.sha)", "--", relativePath],
        workingDirectory: repoURL
      )
      diff = result?.stdout ?? ""
    } else {
      return nil
    }

    if diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return nil
    }

    return await CommitExplainer.summarize(diff: diff)
  }

  /// Returns all files changed across the given commits, with their line counts
  /// and codemap summaries (when the file has already been indexed).
  ///
  /// - Parameters:
  ///   - repoURL: The working-copy root of the repository.
  ///   - commits: Commits to diff, in insertion order (newest first).  For a
  ///     multi-commit range the method internally passes `newest..oldest` to
  ///     git so the diff is computed in reverse-chronological order; callers
  ///     pass the array as-is without reversing it.
  /// - Returns: An array of `FileChange` objects grouped by category in the
  ///     caller. Returns an empty array if git fails or no files were changed.
  static func changes(for repoURL: URL, commits: [SessionCommit]) async -> [FileChange] {
    guard let first = commits.first else { return [] }

    let diffStat: String
    if commits.count == 1 {
      diffStat = await gitDiffStat(sha: first.sha, repoURL: repoURL)
    } else if let last = commits.last {
      // commits is in insertion order (newest first).  Use last..first so
      // git processes in reverse-chronological order (newest..oldest).
      diffStat = await gitDiffStatRange(from: last.sha, to: first.sha, repoURL: repoURL)
    } else {
      return []
    }

    let rawChanges = parseGitDiffStat(diffStat)
    let workspace = CompassWorkspace(repoURL: repoURL)
    let codemapDir = CodemapStore.defaultDirectory(forWorkspace: workspace)
    let codemapStore = CodemapStore(directory: codemapDir)

    return rawChanges.map { change in
      let entry = codemapStore.loadEntry(forRelativePath: change.relativePath)
      return FileChange(
        relativePath: change.relativePath,
        additions: change.additions,
        deletions: change.deletions,
        language: change.language,
        summary: entry?.summary
      )
    }
  }

  // MARK: - Private

  /// Parse `git diff --stat` output into FileChange objects.
  /// Each line of --stat output looks like:
  ///   Sources/Compass/AppModel.swift       |  24 +++++++++++++++--
  /// or for renames:
  ///   old/path.go => new/path.go           |   4 ++-
  static func parseGitDiffStat(_ diffStat: String) -> [FileChange] {
    var changes: [FileChange] = []

    for line in diffStat.split(whereSeparator: \.isNewline) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty else { continue }

      // Format: "<filename> | <N> <additions>/<deletions>"
      // e.g. "Sources/App.swift        |  12 ++++++----"
      let parts = trimmed.split(separator: "|")
      guard parts.count >= 1 else { continue }

      let pathPart = parts[0].trimmingCharacters(in: .whitespaces)
      // Handle "a => b" renames by taking the right-hand side
      let relativePath: String
      if pathPart.contains("=>") {
        let renameParts = pathPart.split(separator: ">")
        relativePath = renameParts.last?.trimmingCharacters(in: .whitespaces) ?? pathPart
      } else {
        relativePath = pathPart
      }

      guard !relativePath.isEmpty else { continue }

      var additions = 0
      var deletions = 0

      if parts.count >= 2 {
        let statsPart = parts[1].trimmingCharacters(in: .whitespaces)
        let nums = extractLineCounts(from: statsPart)
        additions = nums.additions
        deletions = nums.deletions
      }

      let language = CodemapLanguage.forRelativePath(relativePath)
      changes.append(FileChange(
        relativePath: relativePath,
        additions: additions,
        deletions: deletions,
        language: language,
        summary: nil // Populated later via codemap lookup
      ))
    }

    return changes
  }

  /// Extract addition/deletion counts from a stat line like "24 +++++++++++++++------"
  static func extractLineCounts(from statPart: String) -> (additions: Int, deletions: Int) {
    let tokens = statPart.split(separator: " ")
    var numericCount = 0
    for token in tokens {
      if let n = Int(token) {
        numericCount = n
      }
    }

    let barChars = statPart.filter { $0 == "+" || $0 == "-" }
    let additions = barChars.filter { $0 == "+" }.count
    let deletions = barChars.filter { $0 == "-" }.count

    // Fallback: if the bar chart is empty but we have a numeric count, treat it as additions
    if additions == 0 && deletions == 0 && numericCount > 0 {
      return (numericCount, 0)
    }

    return (additions, deletions)
  }

  private static func gitDiffStat(sha: String, repoURL: URL) async -> String {
    let result = try? await ProcessRunner.runEnv(
      "git", ["diff", "--stat=9999", "--first-parent", sha],
      workingDirectory: repoURL
    )
    return result?.stdout ?? ""
  }

  private static func gitDiffStatRange(from: String, to: String, repoURL: URL) async -> String {
    let result = try? await ProcessRunner.runEnv(
      "git", ["diff", "--stat=9999", "--first-parent", "\(from)..\(to)"],
      workingDirectory: repoURL
    )
    return result?.stdout ?? ""
  }
}
