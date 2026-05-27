import Foundation

#if canImport(FoundationModels)
  import FoundationModels
#endif

/// Unified availability guard for Apple's on-device Foundation Models.
///
/// All five call sites — `CommitExplainer`, `CommitTourGenerator`, `RepoQnA`,
/// `FoundationModelsAgentRuntime`, and `DraftRefinement` — check
/// `SystemLanguageModel.default.isAvailable` independently.  This enum
/// centralises that check so the gate is uniform and easy to update.
///
/// Note: `FileExplainer.explain()` delegates to `CommitExplainer.summarize(diff:)`
/// and is not a direct call site; its availability is implied by the delegate.
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
}