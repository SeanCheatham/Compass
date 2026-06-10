import Foundation

// MARK: - Overview

/// `FileExplainer` is the central orchestrator of the Explore layer — it is the
/// single entry point used by the UI for both the changed-file list and the
/// per-file explanation pipeline.
///
/// ## Public interface
///
/// - ``changes(for:commits:)`` — collects all files modified across a commit
///   range and pairs each with its line-count stats and codemap summary.  This
///   powers the Explore popover file list and never touches generated narration.
///
/// - ``explain(file:repoURL:commits:)`` — runs `git diff` for a single file and
///   delegates the raw diff to ``CommitExplainer`` for an AI-generated plain-
///   English summary, bridging the Explore layer into generated narration.
///
/// ## Position in the Explore architecture
///
/// FileExplainer sits above three other Explore components: ``CommitExplainer``
/// (per-commit diff summarization), ``CommitTourGenerator`` (guided code tours),
/// and ``RepoQnA`` (repository-scale Q&A).  ``changes(for:commits:)`` is purely
/// a git/codemap query; ``explain(file:repoURL:commits:)`` is the crossing point
/// into the model-driven components downstream.

/// Represents a single changed file with its metadata and optional codemap summary.
struct FileChange: Identifiable, Equatable {
  let id: String
  let relativePath: String
  let language: CodemapLanguage?
  let additions: Int
  let deletions: Int
  let summary: String?
  let explanation: String?
  let explanationReason: ExplainUnavailableReason?

  var category: FileChangeCategory {
    FileChangeCategory.categorize(relativePath)
  }

  init(
    relativePath: String,
    additions: Int,
    deletions: Int,
    language: CodemapLanguage?,
    summary: String?,
    explanation: String? = nil,
    explanationReason: ExplainUnavailableReason? = nil
  ) {
    self.id = relativePath
    self.relativePath = relativePath
    self.additions = additions
    self.deletions = deletions
    self.language = language
    self.summary = summary
    self.explanation = explanation
    self.explanationReason = explanationReason
  }

  /// One-line file name without any directory prefix.
  var fileName: String {
    (relativePath as NSString).lastPathComponent
  }

  /// Short "+N/-N" line-count label.
  var lineCountLabel: String {
    "\(Self.additionLabel(additions))/\(Self.deletionLabel(deletions))"
  }

  private static func additionLabel(_ value: Int) -> String {
    value == 0 ? "0" : "+\(value)"
  }

  private static func deletionLabel(_ value: Int) -> String {
    value == 0 ? "0" : "-\(value)"
  }
}

/// Category for grouping file changes in the explore popover.
enum FileChangeCategory: String, CaseIterable {
  case source = "Sources"
  case test = "Tests"
  case config = "Config"
  case other = "Other"

  /// Stable display name used in tool output. Distinct from the `rawValue`
  /// so renaming the case (e.g. `source` → `src`) doesn't churn cached files.
  var displayName: String {
    switch self {
    case .source: return "Sources"
    case .test: return "Tests"
    case .config: return "Config"
    case .other: return "Other"
    }
  }

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
    let dirLower = dir.lowercased()
    let dirComponents = dirLower.split(separator: "/").map(String.init)

    // Tests — test dirs and test files
    if dirComponents.contains("test") || dirComponents.contains("tests") {
      return .test
    }
    if lower.hasSuffix("_tests.swift")
      || lower.hasSuffix("_test.swift")
      || lower.hasSuffix(".test.swift")
      || lower.hasSuffix(".spec.swift")
    {
      return .test
    }
    if lower.hasPrefix("test_") || lower.hasPrefix("test.") || lower.hasPrefix("test-") {
      return .test
    }
    if dirLower.hasPrefix("test") {
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
/// ## Generated narration boundary
///
/// ``explain(file:repoURL:commits:)`` crosses into generated narration via
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
  /// - Returns: A tuple `(explanation, reason)`. The explanation is an
  ///   AI-generated plain-English string, or `nil` when unavailable. The
  ///   `reason` carries a user-facing message explaining why the feature
  ///   did not activate (e.g. `.foundationModelsUnavailable`).
  static func explain(
    file relativePath: String,
    repoURL: URL,
    commits: [SessionCommit]
  ) async -> (String?, ExplainUnavailableReason?) {
    await explainDiff(
      await CommitExplainer.commitDiffRange(
        commits: commits,
        repoURL: repoURL,
        relativePath: relativePath
      ),
      using: CommitExplainer.summarize(diff:)
    )
  }

  /// Returns a purpose-focused explanation for a single changed file:
  /// why the file was generated and what role it plays in the codebase.
  /// This is distinct from ``explain(file:repoURL:commits:)`` which describes
  /// "what changed" — this method explains "why it exists".
  ///
  /// - Parameters:
  ///   - relativePath: The repo-relative path of the file to explain.
  ///   - repoURL: The working-copy root of the repository.
  ///   - commits: Commits to diff, in insertion order (newest first).  Single-
  ///     commit uses `sha^..sha`; multi-commit uses `newest..oldest` internally.
  /// - Returns: A tuple `(explanation, reason)`. The explanation is an
  ///   AI-generated plain-English string, or `nil` when unavailable. The
  ///   `reason` carries a user-facing message explaining why the feature
  ///   did not activate (e.g. `.foundationModelsUnavailable`).
  static func whyGenerated(
    file relativePath: String,
    repoURL: URL,
    commits: [SessionCommit]
  ) async -> (String?, ExplainUnavailableReason?) {
    await explainDiff(
      await CommitExplainer.commitDiffRange(
        commits: commits,
        repoURL: repoURL,
        relativePath: relativePath
      ),
      using: CommitExplainer.summarizeWhyGenerated(diff:)
    )
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
  /// - Returns: An array of `FileChange` objects, each with line-count stats
  ///   (`additions`/`deletions`) and a codemap summary when the file has been
  ///   indexed. Returns an empty array if git fails or no files were changed.
  ///   The caller is responsible for grouping results by ``FileChangeCategory``.
  ///
  /// - Note: This method is purely a git/codemap operation. It never invokes
  ///   generated narration — the AI-powered explanations are produced by
  ///   ``explain(file:repoURL:commits:)`` instead.
  static func changes(for repoURL: URL, commits: [SessionCommit]) async -> [FileChange] {
    guard let first = commits.first, let oldestCommit = commits.last else { return [] }

    let diffStat: String
    if commits.count == 1 {
      diffStat = await gitDiffStatImpl(sha: first.sha, repoURL: repoURL)
    } else {
      diffStat = await gitDiffStatImpl(from: oldestCommit.sha, to: first.sha, repoURL: repoURL)
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

  static func explainDiff(
    _ diff: String?,
    using summarize: (String) async -> (String?, ExplainUnavailableReason?)
  ) async -> (String?, ExplainUnavailableReason?) {
    guard let diff else { return (nil, .noDiff) }
    guard !diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return (nil, .emptyDiff)
    }
    return await summarize(diff)
  }

  /// Parse `git diff --stat` output into FileChange objects.
  /// Each line of --stat output looks like:
  ///   Sources/Compass/AppModel.swift       |  24 +++++++++++++++--
  /// or for renames:
  ///   old/path.rs => new/path.rs           |   4 ++-
  // MARK: - parseGitDiffStat
  static func parseGitDiffStat(_ diffStat: String) -> [FileChange] {
    var changes: [FileChange] = []

    for line in diffStat.split(whereSeparator: \.isNewline) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty else { continue }

      // Format: "<filename> | <N> <additions>/<deletions>"
      // e.g. "Sources/App.swift        |  12 ++++++----"
      let parts = trimmed.split(separator: "|", omittingEmptySubsequences: false)
      guard parts.count >= 2 else { continue }

      let pathPart = parts[0].trimmingCharacters(in: .whitespaces)
      // Handle "a => b" renames by taking the right-hand side
      let relativePath: String
      if let arrowRange = pathPart.range(of: " => ") {
        relativePath = String(pathPart[arrowRange.upperBound...]).trimmingCharacters(
          in: .whitespaces)
      } else {
        relativePath = pathPart
      }
      let raw = relativePath
      let strippedPath = raw.hasPrefix("a/") || raw.hasPrefix("b/") ? String(raw.dropFirst(2)) : raw

      guard !strippedPath.isEmpty else { continue }

      var additions = 0
      var deletions = 0

      if parts.count >= 2 {
        let statsPart = parts[1].trimmingCharacters(in: .whitespaces)
        let nums = extractLineCounts(from: statsPart)
        additions = nums.additions
        deletions = nums.deletions
      }

      let language = CodemapLanguage.forRelativePath(strippedPath)
      changes.append(
        FileChange(
          relativePath: strippedPath,
          additions: additions,
          deletions: deletions,
          language: language,
          summary: nil,  // Populated later via codemap lookup
          explanation: nil,
          explanationReason: nil
        ))
    }

    return changes
  }

  // MARK: - extractLineCounts

  /// Extract addition/deletion counts from a stat line like "24 +++++++++++++++------"
  static func extractLineCounts(from statPart: String) -> (additions: Int, deletions: Int) {
    if statPart.localizedCaseInsensitiveContains("bin") {
      return (0, 0)
    }

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

  /// Returns the diff stat output for a single commit using `--first-parent`.
  /// Returns an empty string if git fails or the commit has no changes on the mainline.
  static func gitDiffStat(sha: String, repoURL: URL) async -> String {
    await gitDiffStatImpl(sha: sha, repoURL: repoURL)
  }

  private static func gitDiffStatImpl(
    sha: String? = nil,
    from: String? = nil,
    to: String? = nil,
    repoURL: URL
  ) async -> String {
    let args: [String]
    if let sha = sha {
      args = ["diff-tree", "--stat=9999", "--root", "--first-parent", "--no-commit-id", sha]
    } else if let from = from, let to = to {
      args = ["diff", "--stat=9999", "--first-parent", "\(from)..\(to)"]
    } else {
      return ""
    }
    let result = try? await ProcessRunner.runEnv(
      "git", args,
      workingDirectory: repoURL
    )
    return result?.stdout ?? ""
  }
}
