import Foundation

#if canImport(FoundationModels)
  import FoundationModels
#endif

/// Unified availability guard for Apple's on-device Foundation Models.
///
/// Direct call sites — `CommitExplainer`, `CommitTourGenerator`, `RepoQnA`,
/// and `FoundationModelsAgentRuntime` — check this guard before invoking the
/// Foundation Models stack.  `FileExplainer.explain()` delegates to
/// `CommitExplainer.summarize(diff:)` and is not a direct call site; its
/// availability is implied by the delegate.  `LiveActivitySummary` uses
/// `SystemLanguageModel.default.isAvailable` directly and is not covered by
/// this enum.
enum FoundationModelsAvailability {
  /// `true` when the on-device Foundation Models stack is available and
  /// ready to handle requests on this system.
  ///
  /// Combines two preconditions:
  /// - `FoundationModels` module is present at compile time
  /// - `SystemLanguageModel.default.isAvailable` returns `true` at runtime
  static var isAvailable: Bool {
    #if canImport(FoundationModels)
      if #available(macOS 26.0, *) {
        return SystemLanguageModel.default.isAvailable
      }
    #endif
    return false
  }

  #if canImport(FoundationModels)
  /// Streams a prompt through `LanguageModelSession` and returns the
  /// accumulated, trimmed text.  Returns `nil` on error or when the
  /// result is empty.
  @available(macOS 26.0, *)
  static func _streamText(prompt: String) async -> String? {
    do {
      let session = LanguageModelSession(model: .default)
      var fullText = ""
      for try await snapshot in session.streamResponse(to: prompt) {
        fullText += snapshot.content
      }
      let result = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
      return result.isEmpty ? nil : result
    } catch {
      return nil
    }
  }
  #endif
}