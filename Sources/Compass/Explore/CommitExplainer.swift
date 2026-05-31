import Foundation

/// # Explore Layer
///
/// `CommitExplainer` provides per-commit diff summarization for the Explore layer.
/// It converts a raw `git diff` into plain-English prose so users can understand what
/// changed in a given file without reading the diff themselves.
///
/// ## Role in the Explore layer
///
/// ``CommitExplainer`` is called by ``FileExplainer/explain(file:repoURL:commits:)`` when
/// the UI requests a per-file AI explanation. Unlike ``CommitTourGenerator`` (which covers
/// an entire multi-commit range) or ``RepoQnA`` (free-form questions), it focuses on the
/// single-file diff for a single commit — the most targeted explanation in the layer.
///
/// ## Foundation Models boundary
///
/// The ``summarize(diff:)`` method is gated ``@available(macOS 26.0, *)`` and streams
/// directly to Foundation Models with a fixed 3-sentence prompt template. Output is
/// capped at ~600 tokens. Returns `nil` when Foundation Models is unavailable or
/// produces no content.

#if canImport(FoundationModels)
  import FoundationModels
#endif

/// Summarizes a single-file git diff for use in the Explore Q&A pipeline.
///
/// ## Data flow
///
/// `CommitExplainer` is called by ``FileExplainer/explain(file:repoURL:commits:)``
/// when the UI requests a per-file AI explanation. The caller holds the commit
/// list (newest first) and passes it directly; this enum handles the
/// single-file ``git diff`` call internally.
///
/// ## Foundation Models boundary
///
/// The diff text is streamed directly to Foundation Models with a fixed
/// 3-sentence prompt template. Output is capped at ~600 tokens. Returns `nil`
/// when Foundation Models is unavailable or produces no content, with a
/// non-nil ``ExplainUnavailableReason`` in the second tuple position to
/// enable user-facing messaging in the UI.
///
/// ## Results
///
/// The plain-English summary is stored on the `FileChange.explanation`
/// field and displayed alongside the file in the Explore popover. When
/// `nil`, the UI surfaces the associated reason to explain why the feature
/// did not activate.
@available(macOS 26.0, *)
enum CommitExplainer {
  /// Produces a plain-English summary of the given git diff text.
  /// The summary is kept to roughly three sentences and caps output
  /// at approximately 600 tokens.
  ///
  /// Returns `(nil, reason)` when Foundation Models is unavailable or
  /// produces no content; `reason` carries a user-facing message explaining
  /// why the feature did not activate.
  static func summarize(diff: String) async -> (String?, ExplainUnavailableReason?) {
    return await summarize(diff: diff, prompt: whatChangedPrompt(diff: diff))
  }

  /// Produces a purpose-focused explanation of a file: why it was generated
  /// and what role it plays in the codebase. Distinct from the diff-based
  /// "what changed" summary.
  ///
  /// Returns `(nil, reason)` when Foundation Models is unavailable or produces
  /// no content; `reason` carries a user-facing message.
  static func summarizeWhyGenerated(diff: String) async -> (String?, ExplainUnavailableReason?) {
    return await summarize(
      diff: diff,
      prompt: """
        You are a software engineer explaining why a source file was generated and what role it plays in the codebase.
        Answer the question: "Why was this file generated and what is its role in the codebase?"
        Keep the answer to roughly 3 sentences and focus on the file's purpose and architectural role.
        Do not describe the diff mechanically — explain the reason the file exists.

        Diff:
        """ + diff)
  }

  // MARK: - Private

  private static func summarize(diff: String, prompt: String) async -> (
    String?, ExplainUnavailableReason?
  ) {
    let trimmed = diff.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return (nil, .emptyDiff) }

    guard FoundationModelsAvailability.isAvailable else {
      return (nil, .foundationModelsUnavailable)
    }

    if let result = await FoundationModelsAvailability._streamText(prompt: prompt) {
      return (result, nil)
    }
    return (nil, .emptyResponse)
  }

  private static func whatChangedPrompt(diff: String) -> String {
    return """
      You are a software engineer explaining a git diff to a non-technical project owner.
      Provide a clear, concise summary (~3 sentences) of what changed.
      Focus on the intent and effect of the changes, not the mechanical details.

      Diff:
      """ + diff
  }

  /// Git's well-known empty-tree object, used as the base for root commits.
  private static let emptyTreeObjectSHA = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"

  /// Returns the first parent of `sha`, or the empty tree when `sha` is a root commit.
  private static func baseRevisionBefore(sha: String, repoURL: URL) async -> String? {
    let trimmedSHA = sha.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedSHA.isEmpty else { return nil }

    guard
      let exists = try? await ProcessRunner.runEnv(
        "git", ["cat-file", "-e", "\(trimmedSHA)^{commit}"],
        workingDirectory: repoURL
      ),
      exists.exitCode == 0
    else {
      return nil
    }

    guard
      let parent = try? await ProcessRunner.runEnv(
        "git", ["rev-parse", "\(trimmedSHA)^"],
        workingDirectory: repoURL
      ),
      parent.exitCode == 0
    else {
      return emptyTreeObjectSHA
    }

    let parentSHA = parent.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    return parentSHA.isEmpty ? emptyTreeObjectSHA : parentSHA
  }

  private static func isAncestor(_ ancestor: String, of descendant: String, repoURL: URL) async
    -> Bool
  {
    let trimmedAncestor = ancestor.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedDescendant = descendant.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedAncestor.isEmpty, !trimmedDescendant.isEmpty else { return false }

    guard
      let result = try? await ProcessRunner.runEnv(
        "git", ["merge-base", "--is-ancestor", trimmedAncestor, trimmedDescendant],
        workingDirectory: repoURL
      )
    else {
      return false
    }
    return result.exitCode == 0
  }

  private static func diffArguments(base: String, tip: String, relativePath: String?) -> [String] {
    var args = ["diff", "--no-color", base, tip]
    let trimmedPath = relativePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !trimmedPath.isEmpty {
      args += ["--", trimmedPath]
    }
    return args
  }

  /// Fetches the diff for a single commit against its first parent.
  /// Root commits are diffed against git's empty tree so their changes are visible.
  static func gitDiff(sha: String, repoURL: URL, relativePath: String? = nil) async -> String {
    let trimmedSHA = sha.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let base = await baseRevisionBefore(sha: trimmedSHA, repoURL: repoURL) else {
      return ""
    }

    guard
      let result = try? await ProcessRunner.runEnv(
        "git", diffArguments(base: base, tip: trimmedSHA, relativePath: relativePath),
        workingDirectory: repoURL
      ),
      result.exitCode == 0
    else {
      return ""
    }
    return result.stdout
  }

  /// Fetches an inclusive diff for a commit range, including changes from the oldest commit.
  static func gitDiffRange(
    newest: String,
    oldest: String,
    repoURL: URL,
    relativePath: String? = nil
  ) async -> String {
    let trimmedNewest = newest.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedOldest = oldest.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedNewest.isEmpty, !trimmedOldest.isEmpty else { return "" }

    let baseSource: String
    let tip: String
    if await isAncestor(trimmedOldest, of: trimmedNewest, repoURL: repoURL) {
      baseSource = trimmedOldest
      tip = trimmedNewest
    } else if await isAncestor(trimmedNewest, of: trimmedOldest, repoURL: repoURL) {
      baseSource = trimmedNewest
      tip = trimmedOldest
    } else {
      baseSource = trimmedNewest
      tip = trimmedOldest
    }

    guard let base = await baseRevisionBefore(sha: baseSource, repoURL: repoURL) else {
      return ""
    }

    guard
      let result = try? await ProcessRunner.runEnv(
        "git", diffArguments(base: base, tip: tip, relativePath: relativePath),
        workingDirectory: repoURL
      ),
      result.exitCode == 0
    else {
      return ""
    }
    return result.stdout
  }

  /// Returns the git diff text for a commit range, delegating to the appropriate
  /// single- or multi-commit helper based on commit count.
  ///
  /// - Returns: `nil` when commits is empty; otherwise the diff text (may be empty
  ///   if git produced no output).
  static func commitDiffRange(
    commits: [SessionCommit],
    repoURL: URL,
    relativePath: String? = nil
  ) async -> String? {
    guard let first = commits.first else { return nil }
    if commits.count == 1 {
      return await gitDiff(sha: first.sha, repoURL: repoURL, relativePath: relativePath)
    }
    guard let oldest = commits.last else { return nil }
    return await gitDiffRange(
      newest: first.sha,
      oldest: oldest.sha,
      repoURL: repoURL,
      relativePath: relativePath
    )
  }

  /// Produces a plain-English summary of a single commit by fetching the full
  /// first-parent diff and passing it to ``summarize(diff:)``.
  ///
  /// This method is the single-commit counterpart to the multi-commit path
  /// used in ``FileExplainer/explain(file:repoURL:commits:)``.  Callers that
  /// already hold a `SessionCommit` can use this directly rather than
  /// constructing a single-element array.
  ///
  /// Returns `nil` when the diff is empty, git fails, or Foundation Models
  /// is unavailable.
  static func explain(commit: SessionCommit, repoURL: URL) async -> (
    String?, ExplainUnavailableReason?
  ) {
    let diff = await gitDiff(sha: commit.sha, repoURL: repoURL)
    let trimmed = diff.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return (nil, .emptyDiff) }
    return await summarize(diff: trimmed)
  }
}
