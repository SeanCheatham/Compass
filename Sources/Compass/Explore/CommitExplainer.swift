import Foundation

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
/// when Foundation Models is unavailable or produces no content.
///
/// ## Results
///
/// The resulting plain-English summary is stored on the `FileChange.explanation`
/// field and displayed alongside the file in the Explore popover.
@available(macOS 26.0, *)
enum CommitExplainer {
  /// Produces a plain-English summary of the given git diff text.
  /// The summary is kept to roughly three sentences and caps output
  /// at approximately 600 tokens.
  ///
  /// Returns `nil` when Foundation Models is unavailable or produces
  /// no content.
  static func summarize(diff: String) async -> String? {
    guard FoundationModelsAvailability.isAvailable else { return nil }

    let trimmed = diff.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let prompt = """
      You are a software engineer explaining a git diff to a non-technical project owner.
      Provide a clear, concise summary (~3 sentences) of what changed.
      Focus on the intent and effect of the changes, not the mechanical details.

      Diff:
      \(trimmed)
      """

    return await FoundationModelsAvailability._streamText(prompt: prompt)
  }
}