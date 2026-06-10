import Foundation

/// Describes why an Explore explanation could not be generated.
///
/// The original case name is kept for persistence/UI compatibility while
/// generated narration is paused during the MLX runtime migration.
enum ExplainUnavailableReason: Sendable, CaseIterable {
  case foundationModelsUnavailable
  case noDiff
  case emptyDiff
  case emptyResponse
  case unavailable

  var message: String {
    switch self {
    case .foundationModelsUnavailable:
      return "Generated explanation is unavailable until local MLX narration is migrated."
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

/// Compatibility shim for older narration helpers.
///
/// Agent execution no longer uses this path. Lightweight explanatory helpers
/// either receive an explicit test override or return unavailable until they
/// are moved onto the MLX text runtime.
enum FoundationModelsAvailability {
  static let generatedExploreUnavailableMessage =
    "Generated Explore insight is unavailable until local MLX narration is migrated. Deterministic change details remain available."

  struct TextProvider: Sendable {
    var isAvailable: @Sendable () -> Bool
    var streamText: @Sendable (_ prompt: String) async -> String?

    init(
      isAvailable: @escaping @Sendable () -> Bool,
      streamText: @escaping @Sendable (_ prompt: String) async -> String?
    ) {
      self.isAvailable = isAvailable
      self.streamText = streamText
    }
  }

  @TaskLocal private static var textProviderOverride: TextProvider?

  static func withTextProvider<T>(
    _ provider: TextProvider,
    operation: () async throws -> T
  ) async rethrows -> T {
    try await $textProviderOverride.withValue(provider) {
      try await operation()
    }
  }

  static var isAvailable: Bool {
    textProviderOverride?.isAvailable() ?? false
  }

  static func _streamText(prompt: String) async -> String? {
    if let textProviderOverride {
      return await textProviderOverride.streamText(prompt)
    }
    return nil
  }
}
