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
    return await summarize(diff: diff, prompt: whyGeneratedPrompt(diff: diff))
  }

  // MARK: - Private

  private static func summarize(diff: String, prompt: String) async -> (String?, ExplainUnavailableReason?) {
    guard FoundationModelsAvailability.isAvailable else {
      return (nil, .foundationModelsUnavailable)
    }

    let trimmed = diff.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return (nil, .emptyDiff) }

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

  private static func whyGeneratedPrompt(diff: String) -> String {
    return """
      You are a software engineer explaining why a source file was generated and what role it plays in the codebase.
      Answer the question: "Why was this file generated and what is its role in the codebase?"
      Keep the answer to roughly 3 sentences and focus on the file's purpose and architectural role.
      Do not describe the diff mechanically \u{2014} explain the reason the file exists.

      Diff:
      """ + diff
  }

  /// Fetches the diff for a single commit via `git diff <sha>^..<sha>`.
  static func gitDiff(sha: String, repoURL: URL) async -> String {
    let result = try? await ProcessRunner.runEnv(
      "git", ["diff", "\(sha)^..\(sha)"],
      workingDirectory: repoURL
    )
    return result?.stdout ?? ""
  }

  /// Fetches the diff for a commit range via `git diff <newest>..<oldest>`.
  static func gitDiffRange(newest: String, oldest: String, repoURL: URL) async -> String {
    let result = try? await ProcessRunner.runEnv(
      "git", ["diff", "--no-color", "\(oldest)..\(newest)"],
      workingDirectory: repoURL
    )
    return result?.stdout ?? ""
  }

  /// Returns the git diff text for a commit range, delegating to the appropriate
  /// single- or multi-commit helper based on commit count.
  ///
  /// - Returns: `nil` when commits is empty; otherwise the diff text (may be empty
  ///   if git produced no output).
  static func commitDiffRange(commits: [SessionCommit], repoURL: URL) async -> String? {
    guard let first = commits.first else { return nil }
    if commits.count == 1 {
      return await gitDiff(sha: first.sha, repoURL: repoURL)
    }
    guard let oldest = commits.last else { return nil }
    return await gitDiffRange(newest: first.sha, oldest: oldest.sha, repoURL: repoURL)
  }

  /// Result of a commit explanation attempt, carrying either the explanation
  /// string or a reason for failure.
  struct ExplanationResult: Sendable {
    let explanation: String?
    let reason: ExplainUnavailableReason?

    static func success(_ text: String) -> ExplanationResult {
      ExplanationResult(explanation: text, reason: nil)
    }

    static func failure(_ reason: ExplainUnavailableReason) -> ExplanationResult {
      ExplanationResult(explanation: nil, reason: reason)
    }
  }

  /// Produces a plain-English summary of a single commit by fetching the full
  /// diff via `git diff <sha>^..<sha>` and passing it to ``summarize(diff:)``.
  ///
  /// This method is the single-commit counterpart to the multi-commit path
  /// used in ``FileExplainer/explain(file:repoURL:commits:)``.  Callers that
  /// already hold a `SessionCommit` can use this directly rather than
  /// constructing a single-element array.
  ///
  /// Returns `nil` when the diff is empty, git fails, or Foundation Models
  /// is unavailable.
  static func explain(commit: SessionCommit, repoURL: URL) async -> (String?, ExplainUnavailableReason?) {
    let diff = await gitDiff(sha: commit.sha, repoURL: repoURL)
    let trimmed = diff.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return (nil, .emptyDiff) }
    return await summarize(diff: trimmed)
  }
}
