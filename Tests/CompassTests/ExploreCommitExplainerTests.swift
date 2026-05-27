import Foundation
import Testing

@testable import Compass

struct ExploreCommitExplainerTests {
  private var temporaryDirectory: URL!

  private mutating func setUp() {
    temporaryDirectory = try! makeTempDir()
  }

  private mutating func tearDown() {
    if let temporaryDirectory {
      try? FileManager.default.removeItem(at: temporaryDirectory)
    }
    temporaryDirectory = nil
  }

  // MARK: - Empty input guard

  @Test
  func summarize_emptyString_returnsNil() {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let result = CommitExplainer.summarize(diff: "")
    #require(result == nil)
  }

  @Test
  func summarize_whitespaceOnly_returnsNil() {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let result = CommitExplainer.summarize(diff: "   \n\t  ")
    #require(result == nil)
  }

  // MARK: - Diff length filter (max ~600 tokens)

  @Test
  func summarize_largeDiff_stillAcceptsInput() {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

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
    let result = CommitExplainer.summarize(diff: largeDiff)
    // Result may be nil in test environments where Foundation Models
    // is unavailable, but the call itself must not throw.
    _ = result
  }

  @Test
  func summarize_normalDiff_doesNotThrow() {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    let diff = """
    Sources/App.swift        |  12 ++++++------
    Sources/Model.swift      |   4 ++++++
    """
    // May return nil in CI / test environments without Foundation Models,
    // but must not throw.
    let result = CommitExplainer.summarize(diff: diff)
    _ = result
  }

  // MARK: - isAvailable guard

  @Test
  func summarize_returnsNilWhenModelUnavailable() {
    var test = Self()
    test.setUp()
    defer { test.tearDown() }

    // When SystemLanguageModel.default.isAvailable is false (e.g. on a
    // older macOS version or a simulator), summarize returns nil without
    // attempting to create a session.
    let diff = """
    Sources/App.swift        |   2 ++
    """
    let result = CommitExplainer.summarize(diff: diff)
    // Either Foundation Models is available and we get a string (or nil
    // from an error), or it is unavailable and we definitely get nil.
    if !SystemLanguageModel.default.isAvailable {
      #require(result == nil)
    }
  }
}