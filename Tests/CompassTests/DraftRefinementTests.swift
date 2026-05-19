import Foundation
@testable import Compass
import XCTest

final class DraftRefinementTests: XCTestCase {
    func testParserAcceptsGeneratedJSONRefinement() throws {
        let context = makeContext()
        let refinement = try XCTUnwrap(
            DraftRefinementService.parseGeneratedRefinement(
                #"{"refined":"Add parser tests for Package.swift."}"#,
                draft: "add parser tests for Package.swift",
                context: context
            )
        )

        XCTAssertEqual(refinement.originalDraft, "add parser tests for Package.swift")
        XCTAssertEqual(refinement.refinedText, "Add parser tests for Package.swift.")
        XCTAssertEqual(refinement.source, .generated)
    }

    func testParserAcceptsGeneratedRefinedLine() throws {
        let context = makeContext()
        let refinement = try XCTUnwrap(
            DraftRefinementService.parseGeneratedRefinement(
                "Refined: Add parser tests for Package.swift.",
                draft: "add parser tests for Package.swift",
                context: context
            )
        )

        XCTAssertEqual(refinement.refinedText, "Add parser tests for Package.swift.")
    }

    func testParserRejectsInventedFilesNumbersAndConstraints() {
        let context = makeContext()
        let draft = "add parser tests"

        XCTAssertNil(
            DraftRefinementService.parseGeneratedRefinement(
                "Refined: Add parser tests in Sources/App.swift.",
                draft: draft,
                context: context
            )
        )
        XCTAssertNil(
            DraftRefinementService.parseGeneratedRefinement(
                "Refined: Add 3 parser tests.",
                draft: draft,
                context: context
            )
        )
        XCTAssertNil(
            DraftRefinementService.parseGeneratedRefinement(
                "Refined: Add parser tests that must pass.",
                draft: draft,
                context: context
            )
        )
    }

    func testParserRejectsInventedOutcomeAndExtraStructure() {
        let context = makeContext()
        let draft = "add parser tests"

        XCTAssertNil(
            DraftRefinementService.parseGeneratedRefinement(
                "Refined: Completed parser tests.",
                draft: draft,
                context: context
            )
        )
        XCTAssertNil(
            DraftRefinementService.parseGeneratedRefinement(
                #"{"refined":"Add parser tests.","note":"extra commentary"}"#,
                draft: draft,
                context: context
            )
        )
        XCTAssertNil(
            DraftRefinementService.parseGeneratedRefinement(
                """
                Refined: Add parser tests.
                Note: Also update docs.
                """,
                draft: draft,
                context: context
            )
        )
    }

    func testDeterministicFallbackNormalizesWithoutInventingDetails() throws {
        let context = makeContext()
        let refinement = try XCTUnwrap(
            DraftRefinementService.deterministicRefinement(
                draft: "  - review Package.swift in 2 areas  ",
                context: context
            )
        )

        XCTAssertEqual(refinement.refinedText, "Review Package.swift in 2 areas.")
        XCTAssertEqual(refinement.source, .deterministic)
        XCTAssertTrue(refinement.refinedText.contains("Package.swift"))
        XCTAssertTrue(refinement.refinedText.contains("2"))
        XCTAssertFalse(refinement.refinedText.contains("Sources/App.swift"))
        XCTAssertFalse(refinement.refinedText.contains("must"))
    }

    func testPreviewPlannerDebouncesAndUsesCacheKey() {
        let context = makeContext()
        let plan = DraftRefinementPreviewPlanner.plan(
            draft: "  add parser tests  ",
            context: context,
            isModelAvailable: true,
            cachedKeys: []
        )

        XCTAssertEqual(plan.visibility, .debounce)
        XCTAssertEqual(plan.delayNanoseconds, 600_000_000)

        let key = DraftRefinementPreviewKey(trimmedDraft: "add parser tests", context: context)
        XCTAssertEqual(plan.cacheKey, key)

        let cachedPlan = DraftRefinementPreviewPlanner.plan(
            draft: "add parser tests",
            context: context,
            isModelAvailable: true,
            cachedKeys: [key]
        )

        XCTAssertEqual(cachedPlan.visibility, .cached)
        XCTAssertEqual(cachedPlan.delayNanoseconds, 0)
        XCTAssertEqual(cachedPlan.cacheKey, key)
        XCTAssertTrue(cachedPlan.shouldShowPreviewSurface)
    }

    func testPreviewPlannerHidesForEmptyDraftAndUnavailableModel() {
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

        XCTAssertEqual(emptyPlan.visibility, .hiddenEmptyDraft)
        XCTAssertFalse(emptyPlan.shouldShowPreviewSurface)
        XCTAssertEqual(unavailablePlan.visibility, .hiddenUnavailableModel)
        XCTAssertFalse(unavailablePlan.shouldShowPreviewSurface)
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
