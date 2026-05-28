/// # Explore Layer
///
/// Explore is an AI-powered explanation system for the software Compass produces.  It
/// exists to solve a fundamental problem with generated code: the humans responsible
/// for it often cannot explain it.  As the Vision puts it, Explore "helps the user
/// understand what was built, why it was built that way, and how the pieces fit
/// together — turning opaque generated code into something a human can inspect,
/// navigate, and confidently stand behind."
///
/// ## Components
///
/// Explore is composed of four Foundation Models-driven components:
///
/// | Component | Role | Foundation Models entry point |
/// |---|---|---|
/// | ``FileExplainer`` | Orchestrator — UI entry point for changed-file lists and per-file explanations (``changes(for:commits:)``, ``explain(file:repoURL:commits:)``) | Delegates to ``CommitExplainer`` |
/// | ``CommitExplainer`` | Per-commit diff summarization — converts a raw `git diff` into plain-English prose | ``summarize(diff:)`` |
/// | ``CommitTourGenerator`` | Guided code tours — produces a narrative walk-through of a multi-commit span | ``generateTour(commits:repoURL:)`` |
/// | ``RepoQnA`` | Repository-scale Q&A — answers natural-language questions grounded in the actual codebase | ``answer(question:repoURL:)`` |
///
/// ## Composition
///
/// - **FileExplainer → CommitExplainer**: When the user selects a file, FileExplainer
///   runs `git diff` and passes the result to CommitExplainer for an AI summary of
///   what changed in that file.
/// - **FileExplainer → CommitTourGenerator**: For multi-commit ranges FileExplainer
///   can route the commit list to CommitTourGenerator to produce a guided tour.
/// - **RepoQnA**: Available independently for free-form questions about the repository.
///
/// ``FileExplainer`` is the only component the UI directly depends on; the other three
/// are called through it.
///
/// ## Source material
///
/// All four components operate on live repository data — git commits, file diffs, and
/// the codemap — so their output is always validated against the actual codebase rather
/// than hallucinated from training data.

import Foundation

#if canImport(FoundationModels)
  import FoundationModels
#endif

// MARK: - Overview

/// `FileExplainer` is the central orchestrator of the Explore layer — it is the
/// single entry point used by the UI for both the changed-file list and the
/// per-file explanation pipeline.
///
/// ## Public interface
///
/// - ``changes(for:commits:)`` — collects all files modified across a commit
///   range and pairs each with its line-count stats and codemap summary.  This
///   powers the Explore popover file list and never touches Foundation Models.
///
/// - ``explain(file:repoURL:commits:)`` — runs `git diff` for a single file and
///   delegates the raw diff to ``CommitExplainer`` for an AI-generated plain-
///   English summary, bridging the Explore layer into Foundation Models.
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

  var category: FileChangeCategory {
    FileChangeCategory.categorize(relativePath)
  }

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
        "git", ["diff", "\(first.sha)..\(last.sha)", "--", relativePath],
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
  /// - Returns: An array of `FileChange` objects, each with line-count stats
  ///   (`additions`/`deletions`) and a codemap summary when the file has been
  ///   indexed. Returns an empty array if git fails or no files were changed.
  ///   The caller is responsible for grouping results by ``FileChangeCategory``.
  ///
  /// - Note: This method is purely a git/codemap operation. It never invokes
  ///   Foundation Models — the AI-powered explanations are produced by
  ///   ``explain(file:repoURL:commits:)`` instead.
  static func changes(for repoURL: URL, commits: [SessionCommit]) async -> [FileChange] {
    guard let first = commits.first else { return [] }

    let diffStat: String
    if commits.count == 1 {
      diffStat = await gitDiffStatImpl(sha: first.sha, repoURL: repoURL)
    } else {
      let last = commits.last!
      diffStat = await gitDiffStatImpl(from: last.sha, to: first.sha, repoURL: repoURL)
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
  // MARK: - parseGitDiffStat
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
      if let arrowRange = pathPart.range(of: " => ") {
        relativePath = String(pathPart[arrowRange.upperBound...]).trimmingCharacters(in: .whitespaces)
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
      changes.append(FileChange(
        relativePath: strippedPath,
        additions: additions,
        deletions: deletions,
        language: language,
        summary: nil // Populated later via codemap lookup
      ))
    }

    return changes
  }

  // MARK: - extractLineCounts

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
      args = ["diff", "--stat=9999", "--first-parent", sha]
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
