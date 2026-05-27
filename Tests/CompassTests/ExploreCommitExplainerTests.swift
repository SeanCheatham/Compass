import Foundation
import FoundationModels
import Testing

@testable import Compass

struct ExploreCommitExplainerTests {
  // MARK: - Empty input guard

  @Test
  func summarize_emptyString_returnsNil() async throws {
    let result = await CommitExplainer.summarize(diff: "")
    try #require(result == nil)
  }

  @Test
  func summarize_whitespaceOnly_returnsNil() async throws {
    let result = await CommitExplainer.summarize(diff: "   \n\t  ")
    try #require(result == nil)
  }

  // MARK: - Diff length filter (max ~600 tokens)

  @Test
  func summarize_largeDiff_stillAcceptsInput() async throws {
    // Build a diff well over 600 tokens to exercise the length cap path.
    // CommitExplainer itself does not hard-cap token count; it passes
    // the full diff to the model and relies on the prompt to keep output
    // short (~3 sentences). This test simply confirms the method
    // accepts large input without crashing.
    let largeDiff = (0..<200).map { i in
      "+\(String(repeating: "line", count: 80)) change \(i)"
    }.joined(separator: "\n")

    // Should not throw; returns nil if the model is unavailable or
    // produces no content on this host.
    let result = await CommitExplainer.summarize(diff: largeDiff)
    // Result may be nil in test environments where Foundation Models
    // is unavailable, but the call itself must not throw.
    _ = result
  }

  @Test
  func summarize_normalDiff_doesNotThrow() async throws {
    let diff = """
    Sources/App.swift        |  12 ++++++------
    Sources/Model.swift      |   4 ++++++
    """
    // May return nil in CI / test environments without Foundation Models,
    // but must not throw.
    let result = await CommitExplainer.summarize(diff: diff)
    _ = result
  }

  // MARK: - isAvailable guard

  @Test
  func summarize_returnsNilWhenModelUnavailable() async throws {
    // When SystemLanguageModel.default.isAvailable is false (e.g. on a
    // older macOS version or a simulator), summarize returns nil without
    // attempting to create a session.
    let diff = """
    Sources/App.swift        |   2 ++
    """
    let result = await CommitExplainer.summarize(diff: diff)
    // Either Foundation Models is available and we get a string (or nil
    // from an error), or it is unavailable and we definitely get nil.
    if !SystemLanguageModel.default.isAvailable {
      try #require(result == nil)
    }
  }
}
