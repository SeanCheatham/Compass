import Foundation

/// # Explore Layer
///
/// `CommitTourGenerator` provides guided code tours for the Explore layer.
/// It synthesizes a full multi-commit diff into a 3–5 sentence architectural narrative,
/// giving users a high-level walk-through of what was built, why, and how the pieces fit
/// together — going well beyond per-file summaries.
///
/// ## Role in the Explore layer
///
/// ``CommitTourGenerator`` is called through ``FileExplainer`` when the user wants a
/// high-level tour of an entire commit range rather than per-file explanations from
/// ``CommitExplainer``. It is distinct from ``RepoQnA`` (free-form questions) and
/// ``ArchitectureGraph`` (static import-graph analysis) — its strength is narrative
/// coherence across time.
///
/// ## Generated narration boundary
///
/// The ``generateTour(commits:repoURL:)`` method is gated ``@available(macOS 26.0, *)``
/// and streams through the narration shim with a structured architectural-tour prompt.
/// Output is capped at ~800 tokens to keep responses navigable. Returns `nil` when
/// generated narration is unavailable or produces no content.

/// Synthesizes a full multi-commit diff into a 3–5 sentence architectural narrative.
///
/// ## Data flow
///
/// `CommitTourGenerator` receives the raw combined diff of an entire commit
/// range and produces a coherent guided-tour description of what was built,
/// why, and how the pieces fit together — going well beyond per-file summaries.
///
/// ## Generated narration boundary
///
/// The full diff text is streamed through the narration shim with a structured
/// architectural-tour prompt. Output is capped at ~800 tokens to keep
/// responses navigable. Returns `nil` when generated narration is unavailable
/// or produces no content.
///
/// ## Position in the pipeline
///
/// Unlike ``CommitExplainer`` (which handles one file at a time from
/// `FileExplainer.explain()`), this operates on the complete commit range
/// and is used when the user wants a high-level tour rather than per-file
/// details.
@available(macOS 26.0, *)
enum CommitTourGenerator {
  /// Produces a guided-tour narrative for the given git diff text.
  /// The narrative is 3–5 sentences and caps output at approximately 800 tokens
  /// to keep responses navigable.
  ///
  /// Returns `nil` when generated narration is unavailable, the input is empty
  /// or whitespace-only, or when the model produces no content.
  static func generate(diff: String) async -> String? {
    guard FoundationModelsAvailability.isAvailable else { return nil }

    let trimmed = diff.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let prompt = """
      You are a software architect explaining a multi-commit diff to a technical but non-authoritative audience
      (e.g., a project owner, a new team member, or a senior engineer reviewing unfamiliar code).
      Provide a guided-tour narrative of 3-5 sentences that explains what was built, why it was built that way, and how the pieces fit together. Go beyond surface-level changes to capture the architectural intent and how files collaborate.

      Diff:
      \(trimmed)
      """

    return await FoundationModelsAvailability._streamText(prompt: prompt)
  }

  /// Generates a guided-tour narrative from a list of commits on a repository.
  ///
  /// - Parameters:
  ///   - commits: The commits to include, ordered newest-first (as returned by
  ///     `PlanSessionHistoryItem.commits`).
  ///   - repoURL: The local URL of the repository.
  ///
  /// Computes the appropriate git diff range internally and delegates to
  /// ``generate(diff:)``. Returns `nil` when generated narration is unavailable
  /// or when the diff is empty.
  static func generateTour(commits: [SessionCommit], repoURL: URL) async -> String? {
    guard let firstCommit = commits.first, let oldestCommit = commits.last else { return nil }
    let diff: String
    if commits.count == 1 {
      diff = await CommitExplainer.gitDiff(sha: firstCommit.sha, repoURL: repoURL)
    } else {
      diff = await CommitExplainer.gitDiffRange(
        newest: firstCommit.sha, oldest: oldestCommit.sha, repoURL: repoURL)
    }
    guard !diff.isEmpty else { return nil }
    return await generate(diff: diff)
  }
}
