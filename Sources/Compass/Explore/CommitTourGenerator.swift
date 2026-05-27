import Foundation
import FoundationModels

/// Generates a guided-tour narrative from a multi-commit diff using Apple's
/// on-device Foundation Models. Produces 3-5 sentences explaining what was
/// built, why it was built that way, and how the pieces fit together.
///
/// Unlike `CommitExplainer` (per-file diff summary), this synthesizes the full
/// commit range into a cohesive architectural narrative for the changed files.
/// Available only on macOS 26.0 and later.
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