import Foundation

#if canImport(FoundationModels)
  import FoundationModels

  /// Serializes lightweight `LanguageModelSession` use (draft preview, Explore,
  /// live summaries). The on-device stack misbehaves when multiple sessions
  /// run concurrently; the agent runtime owns its own long-lived session.
  @available(macOS 26.0, *)
  actor FoundationModelsSessionGate {
    static let shared = FoundationModelsSessionGate()

    func withExclusiveAccess<T: Sendable>(
      _ operation: @Sendable () async throws -> T
    ) async rethrows -> T {
      try await operation()
    }
  }
#endif

/// Unified availability guard and streaming entry point for Apple's on-device
/// Foundation Models in the Explore layer.
///
/// ## Availability check (`isAvailable`)
///
/// `isAvailable` combines two preconditions:
/// 1. **Compile-time**: `FoundationModels` module is present — guarded by `#if canImport(FoundationModels)`.
///    This prevents linkage errors on systems without the framework.
/// 2. **Runtime**: `SystemLanguageModel.default.isAvailable` returns `true` — checked inside the
///    `#available(macOS 26.0, *)` guard.  A `false` return means the model is not installed or
///    cannot run on this device.
///
/// ## Streaming entry point (`_streamText(prompt:)`)
///
/// `_streamText(prompt:)` is the single streaming entry point used by all four Explore
/// components:
/// - ``CommitExplainer`` — explains individual commits
/// - ``CommitTourGenerator`` — generates guided repository tours
/// - ``RepoQnA`` — answers questions grounded in repository state
/// - ``FoundationModelsAgentRuntime`` — primary agent runtime backed by Foundation Models
///
/// Internally it opens a ``LanguageModelSession``, accumulates every content snapshot from the
/// streaming response, and returns the final text after trimming trailing whitespace.  There is
/// no explicit token-cap: the session collects all snapshots emitted by the model and the caller
/// is responsible for truncating the result if needed.
///
/// ## `nil` return contract
///
/// `_streamText(prompt:)` returns `nil` in two cases:
/// - **Error**: any ``Error`` thrown during session creation or streaming results in `nil`.
/// - **Empty result**: after trimming, if the accumulated text is empty, `nil` is returned.
///
/// Callers (`CommitExplainer`, `CommitTourGenerator`, `RepoQnA`) treat a `nil` result uniformly
/// as "no explanation / tour / answer available" and fall back gracefully.

/// Describes why an Explore explanation could not be generated.
///
/// The UI uses these cases to show a specific, actionable message to the user
/// instead of a generic "unavailable" notice.
enum ExplainUnavailableReason: Sendable {
  /// Foundation Models is not available on this system (not installed or
  /// cannot run on this device).
  case foundationModelsUnavailable

  /// No git diff was available for the requested file and commit range.
  case noDiff

  /// The diff was empty after trimming whitespace.
  case emptyDiff

  /// The model returned an empty response.
  case emptyResponse

  /// A placeholder reason used when the available text could not be loaded.
  case unavailable

  /// A human-readable message suitable for display in the Explore popover.
  var message: String {
    switch self {
    case .foundationModelsUnavailable:
      return "Explanation requires Apple Intelligence, which is not available on this device."
    case .noDiff:
      return "No commit diff available for this file."
    case .emptyDiff:
      return "No content changes found in this file."
    case .emptyResponse:
      return "The model did not produce an explanation. Please try again."
    case .unavailable:
      return "Explanation unavailable."
    }
  }
}

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
      await FoundationModelsSessionGate.shared.withExclusiveAccess {
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
    }
  #endif
}
