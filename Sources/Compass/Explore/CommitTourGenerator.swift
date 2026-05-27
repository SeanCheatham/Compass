import Foundation

#if canImport(FoundationModels)
  import FoundationModels
#endif

/// Synthesizes a full multi-commit diff into a 3–5 sentence architectural narrative.
///
/// ## Data flow
///
/// `CommitTourGenerator` receives the raw combined diff of an entire commit
/// range and produces a coherent guided-tour description of what was built,
/// why, and how the pieces fit together — going well beyond per-file summaries.
///
/// ## Foundation Models boundary
///
/// The full diff text is streamed to Foundation Models with a structured
/// architectural-tour prompt. Output is capped at ~800 tokens to keep
/// responses navigable. Returns `nil` when Foundation Models is unavailable
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
  /// The narrative is 3-5 sentences and caps output at approximately 800 tokens.
  ///
  /// Returns `nil` when Foundation Models is unavailable or produces no content.
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
}