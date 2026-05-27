import Foundation
import FoundationModels

/// Summarizes git diffs using Apple's on-device Foundation Models.
/// Available only on macOS 26.0 and later.
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