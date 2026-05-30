import Foundation

/// # Explore Layer
///
/// `CommitNarrator` produces a single concise sentence describing a commit,
/// suitable for notification banners, inline commit-list labels, or tour
/// step headers.
///
/// Unlike ``CommitExplainer/summarize(diff:)`` which generates ~3 sentences
/// for Explore popovers, `CommitNarrator` is optimised for compact display
/// where only one sentence of context is appropriate.
///
/// ## Foundation Models boundary
///
/// The ``narrate(commit:diff:)`` method is gated ``@available(macOS 26.0, *)``
/// and streams directly to Foundation Models with a single-sentence prompt
/// template. Returns `nil` when Foundation Models is unavailable or
/// produces no content.

#if canImport(FoundationModels)
  import FoundationModels
#endif

/// Narrates a single commit as one plain-English sentence.
///
/// Distinct from ``CommitExplainer/summarize(diff:)`` which produces ~3 sentences
/// and requires the caller to compute the diff separately.
///
/// Returns `nil` when Foundation Models is unavailable or produces no content.
@available(macOS 26.0, *)
enum CommitNarrator {
  /// Narrates a single commit as one plain-English sentence.
  ///
  /// The returned string is a single concise sentence suitable for use in
  /// notification banners, inline commit-list labels, or tour step headers.
  ///
  /// Returns `nil` when Foundation Models is unavailable or produces no content.
  static func narrate(commit: SessionCommit, diff: String) async -> String? {
    let trimmed = diff.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    guard FoundationModelsAvailability.isAvailable else {
      return nil
    }

    return await FoundationModelsAvailability._streamText(
      prompt: narratePrompt(commit: commit, diff: trimmed)
    )
  }

  // MARK: - Private

  private static func narratePrompt(commit: SessionCommit, diff: String) -> String {
    """
    You are a software engineer describing a git commit in a single concise sentence.
    State clearly and plainly what this commit does in one sentence only.
    Do not list files or mechanically describe line counts.

    Commit subject: \(commit.subject)

    Diff:
    """ + diff
  }
}
