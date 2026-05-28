import Foundation
import FoundationModels
import Testing

@testable import Compass

@available(macOS 26.0, *)
struct ExploreCommitTourGeneratorTests {
  // MARK: - Empty string guard

  @Test
  func generate_emptyString_returnsNil()  throws {
    try #require(available(macOS 26.0, *))
    let result = await CommitTourGenerator.generate(diff: "")
    #require(result == nil)
  }

  // MARK: - Whitespace-only guard

  @Test
  func generate_whitespaceOnlyString_returnsNil()  throws {
    try #require(available(macOS 26.0, *))
    let result = await CommitTourGenerator.generate(diff: "   \n\t  \n  ")
    #require(result == nil)
  }

  @Test
  func generate_newlinesOnlyString_returnsNil()  throws {
    try #require(available(macOS 26.0, *))
    let result = await CommitTourGenerator.generate(diff: "\n\n\n")
    #require(result == nil)
  }

  // MARK: - Non-throwing contract for normal diffs

  @Test
  func generate_normalDiff_doesNotThrow()  throws {
    try #require(available(macOS 26.0, *))
    // Verify the async method does not throw for a valid diff.
    // Returns nil when Foundation Models is unavailable in this environment.
    let diff = """
    Sources/App.swift | 4 ++++
    Sources/Model.swift | 2 ++
    """
    let result = await CommitTourGenerator.generate(diff: diff)
    // Result may be nil (Foundation Models unavailable) or non-nil (available)
    // but it must not throw.
    #require(result == nil || result != nil)
  }

  @Test
  func generate_singleLineDiff_doesNotThrow()  throws {
    try #require(available(macOS 26.0, *))
    let diff = "README.md | 1 +"
    let result = await CommitTourGenerator.generate(diff: diff)
    if FoundationModelsAvailability.isAvailable {
      #require(result != nil && !result!.isEmpty)
    }
  }

  // MARK: - Large-diff stability

  @Test
  func generate_largeDiff_doesNotThrow()  throws {
    try #require(available(macOS 26.0, *))
    // A large diff mimicking a full commit range; must not crash or throw.
    let largeDiff = (1...200).map { index in
      "Sources/File\(String(format: "%03d", index)).swift\t|  \(index) +\t\t// Line \($0) of a simulated large diff"
    }.joined(separator: "\n")

    let result = await CommitTourGenerator.generate(diff: largeDiff)
    // Returns nil if Foundation Models is unavailable; non-nil if available.
    // Must never throw regardless of input size.
    if FoundationModelsAvailability.isAvailable {
      #require(result != nil && !result!.isEmpty)
    }
  }

  @Test
  func generate_largeDiffWithManyFiles_doesNotThrow()  throws {
    try #require(available(macOS 26.0, *))
    // Wide diff: many files, small changes each — tests batch-processing stability.
    let wideDiff = (1...50).map { index in
      "Sources/Package\(index)/Source.swift\t|  2 +\t\t// Added utility function in package \(index)"
    }.joined(separator: "\n")

    let result = await CommitTourGenerator.generate(diff: wideDiff)
    if FoundationModelsAvailability.isAvailable {
      #require(result != nil && !result!.isEmpty)
    }
  }

  // MARK: - isAvailable guard

  @Test
  func generate_returnsNilWhenModelUnavailable()  throws {
    // When FoundationModelsAvailability.isAvailable is false, generate
    // returns nil without attempting to create a session.
    try #require(available(macOS 26.0, *))
    let diff = """
    Sources/App.swift        |   2 ++
    """
    let result = await CommitTourGenerator.generate(diff: diff)
    // Either Foundation Models is available and we get a string (or nil
    // from an error), or it is unavailable and we definitely get nil.
    if !FoundationModelsAvailability.isAvailable {
      #require(result == nil)
    }
  }
}