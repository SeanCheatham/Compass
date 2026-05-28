import Foundation
import Testing

@testable import Compass

struct DraftRefinementTests {
  @Test func testParserAcceptsGeneratedJSONRefinement() throws {
    let context = makeContext()
    let refinement = #require(
      DraftRefinementService.parseGeneratedRefinement(
        #"{"refined":"Add parser tests for Package.swift."}"#,
        draft: "add parser tests for Package.swift",
        context: context
      )
    )

    #require(refinement.originalDraft == "add parser tests for Package.swift")
    #require(refinement.refinedText == "Add parser tests for Package.swift.")
    #require(refinement.source == .generated)
  }

  @Test func testParserAcceptsGeneratedRefinedLine() throws {
    let context = makeContext()
    let refinement = #require(
      DraftRefinementService.parseGeneratedRefinement(
        "Refined: Add parser tests for Package.swift.",
        draft: "add parser tests for Package.swift",
        context: context
      )
    )

    #require(refinement.refinedText == "Add parser tests for Package.swift.")
  }

  @Test func testParserRejectsInventedFilesNumbersAndConstraints() {
    let context = makeContext()
    let draft = "add parser tests"

    #require(
      DraftRefinementService.parseGeneratedRefinement(
        "Refined: Add parser tests in Sources/App.swift.",
        draft: draft,
        context: context
      ) ==
      nil
    )
    #require(
      DraftRefinementService.parseGeneratedRefinement(
        "Refined: Add 3 parser tests.",
        draft: draft,
        context: context
      ) ==
      nil
    )
    #require(
      DraftRefinementService.parseGeneratedRefinement(
        "Refined: Add parser tests that must pass.",
        draft: draft,
        context: context
      ) ==
      nil
    )
  }

  @Test func testParserAcceptsRefinedLineAfterPreamble() throws {
    let context = makeContext()
    let refinement = #require(
      DraftRefinementService.parseGeneratedRefinement(
        """
        Here is a clearer version:
        Refined: Add parser tests for Package.swift.
        """,
        draft: "add parser tests for Package.swift",
        context: context
      )
    )

    #require(refinement.refinedText == "Add parser tests for Package.swift.")
    #require(refinement.source == .generated)
  }

  @Test func testParserIgnoresTrailingCommentaryAfterRefinedLine() throws {
    let context = makeContext()
    let refinement = #require(
      DraftRefinementService.parseGeneratedRefinement(
        """
        Refined: Add parser tests for Package.swift.
        Note: Also update docs.
        """,
        draft: "add parser tests for Package.swift",
        context: context
      )
    )

    #require(refinement.refinedText == "Add parser tests for Package.swift.")
  }

  @Test func testParserRejectsInventedOutcomeAndExtraStructure() {
    let context = makeContext()
    let draft = "add parser tests"

    #require(
      DraftRefinementService.parseGeneratedRefinement(
        "Refined: Completed parser tests.",
        draft: draft,
        context: context
      ) ==
      nil
    )
    #require(
      DraftRefinementService.parseGeneratedRefinement(
        #"{"refined":"Add parser tests.","note":"extra commentary"}"#,
        draft: draft,
        context: context
      ) ==
      nil
    )
    #require(
      DraftRefinementService.parseGeneratedRefinement(
        """
        Add parser tests for Package.swift.
        Also update docs.
        """,
        draft: draft,
        context: context
      ) ==
      nil
    )
  }

  @Test func testDeterministicFallbackNormalizesWithoutInventingDetails() throws {
    let context = makeContext()
    let refinement = #require(
      DraftRefinementService.deterministicRefinement(
        draft: "  - review Package.swift in 2 areas  ",
        context: context
      )
    )

    #require(refinement.refinedText == "Review Package.swift in 2 areas.")
    #require(refinement.source == .deterministic)
    #require(refinement.refinedText.contains("Package.swift"))
    #require(refinement.refinedText.contains("2"))
    #require(!refinement.refinedText.contains("Sources/App.swift"))
    #require(!refinement.refinedText.contains("must"))
  }

  @Test func testPreviewPlannerDebouncesAndUsesCacheKey() {
    let context = makeContext()
    let plan = DraftRefinementPreviewPlanner.plan(
      draft: "  add parser tests  ",
      context: context,
      isModelAvailable: true,
      cachedKeys: []
    )

    #require(plan.visibility == .debounce)
    #require(plan.delayNanoseconds == 600_000_000)

    let key = DraftRefinementPreviewKey(trimmedDraft: "add parser tests", context: context)
    #require(plan.cacheKey == key)

    let cachedPlan = DraftRefinementPreviewPlanner.plan(
      draft: "add parser tests",
      context: context,
      isModelAvailable: true,
      cachedKeys: [key]
    )

    #require(cachedPlan.visibility == .cached)
    #require(cachedPlan.delayNanoseconds == 0)
    #require(cachedPlan.cacheKey == key)
    #require(cachedPlan.shouldShowPreviewSurface)
  }

  @Test func testPreviewPlannerHidesForEmptyDraftAndUnavailableModel() {
    let context = makeContext()
    let emptyPlan = DraftRefinementPreviewPlanner.plan(
      draft: "   ",
      context: context,
      isModelAvailable: true,
      cachedKeys: []
    )
    let unavailablePlan = DraftRefinementPreviewPlanner.plan(
      draft: "add parser tests",
      context: context,
      isModelAvailable: false,
      cachedKeys: []
    )

    #require(emptyPlan.visibility == .hiddenEmptyDraft)
    #require(!emptyPlan.shouldShowPreviewSurface)
    #require(unavailablePlan.visibility == .hiddenUnavailableModel)
    #require(!unavailablePlan.shouldShowPreviewSurface)
  }

  private func makeContext() -> DraftRefinementContext {
    DraftRefinementContext(
      repoName: "Compass",
      immediatePlan: "Add parser tests for Package.swift",
      midTermPlan: "Refine drafts",
      longTermPlan: "Keep Compass read-only until explicit actions",
      primaryLanguage: "Swift"
    )
  }
}