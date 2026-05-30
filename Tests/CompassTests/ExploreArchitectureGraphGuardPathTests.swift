import Foundation
import FoundationModels
import Testing

@testable import Compass

/// Compile-only test file covering the `isAvailable` guard path in
/// ``ArchitectureGraph/explain(graph:repoURL:)``.
///
/// ## Guard path covered
///
/// `ArchitectureGraph.explain(graph:repoURL:)` at line 264:
///
/// ```swift
/// guard FoundationModelsAvailability.isAvailable else { return nil }
/// ```
///
/// When Foundation Models is unavailable (e.g. on an older macOS version or
/// a simulator), the guard fires and `explain` returns `nil` without
/// attempting to contact the model. This mirrors the guard-path pattern
/// established in `ExploreCommitExplainerTests.summarize_returnsNilWhenModelUnavailable`
/// and `ExploreFileExplainerGuardPathTests.whyGenerated_returnsNilWhenModelUnavailable`.
///
/// This test uses the same helper pattern established across all other
/// Explore guard-path test files.
struct ExploreArchitectureGraphGuardPathTests {

  // MARK: - isAvailable guard

  /// Verifies `explain` returns `nil` when Foundation Models is unavailable.
  ///
  /// `ArchitectureGraph.explain(graph:repoURL:)` has a
  /// `guard FoundationModelsAvailability.isAvailable else { return nil }`
  /// guard at line 264. When the model is unavailable the guard fires and
  /// `explain` returns `nil` without throwing.
  @Test
  func explain_returnsNilWhenModelUnavailable() async throws {
    let temporaryDirectory = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    try CompassTests.initGitRepo(at: temporaryDirectory)
    _ = try CompassTests.makeSingleCommit(at: temporaryDirectory)

    // Build a minimal non-empty ImportGraph with at least one node and edge.
    let node = ImportGraph.Node(path: "Sources/App.swift")
    let edge = ImportGraph.Edge(source: node, target: node, rawImport: "import Foundation")
    let graph = ImportGraph(nodes: [node], edges: [edge])

    let result = await ArchitectureGraph.explain(graph: graph, repoURL: temporaryDirectory)
    if !FoundationModelsAvailability.isAvailable {
      try #require(result == nil)
    }
  }
}
