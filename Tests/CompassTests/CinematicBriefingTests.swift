import Foundation
@testable import Compass
import XCTest

final class CinematicBriefingDeterministicTests: XCTestCase {
    func testFallbackUsesStableEmptyProjectCopy() {
        let briefing = CinematicBriefingService.deterministicBriefing(
            for: CinematicBriefingInput(
                repoName: "",
                currentPhase: "Idle",
                immediatePlanTitle: "",
                completedCount: 0,
                latestEvent: nil
            )
        )

        XCTAssertEqual(briefing.title, "Project: Awaiting the next quest")
        XCTAssertEqual(
            briefing.detail,
            "Idle with 0 completed milestones. Awaiting the first live signal."
        )
    }

    func testFallbackFitsLongRepositoryAndPlanText() {
        let briefing = CinematicBriefingService.deterministicBriefing(
            for: CinematicBriefingInput(
                repoName: "Hyperbolic Navigation Console Repository With Overflowing Name",
                currentPhase: "Developing",
                immediatePlanTitle: "Implement cinematic briefing tests that deliberately overflow the HUD title limit",
                completedCount: 3,
                latestEvent: nil
            )
        )

        XCTAssertLessThanOrEqual(briefing.title.count, 68)
        XCTAssertEqual(
            briefing.title,
            "Hyperbolic Navigation Console: cinematic briefing tests that"
        )
        XCTAssertLessThanOrEqual(briefing.detail.count, 150)
    }

    func testFallbackPluralizesCompletedMilestones() {
        let singular = CinematicBriefingService.deterministicBriefing(
            for: CinematicBriefingInput(
                repoName: "Compass",
                currentPhase: "Verifying",
                immediatePlanTitle: "Add coverage",
                completedCount: 1,
                latestEvent: nil
            )
        )
        let plural = CinematicBriefingService.deterministicBriefing(
            for: CinematicBriefingInput(
                repoName: "Compass",
                currentPhase: "Verifying",
                immediatePlanTitle: "Add coverage",
                completedCount: 2,
                latestEvent: nil
            )
        )

        XCTAssertTrue(singular.detail.contains("1 completed milestone."))
        XCTAssertTrue(plural.detail.contains("2 completed milestones."))
    }

    func testFallbackIncludesLatestLiveEvent() {
        let event = CinematicBriefingEvent(
            line: LiveLine(
                level: .success,
                text: "Develop finished",
                detail: "Generated tests for cinematic briefing.",
                kind: .agentMessage,
                status: .completed
            )
        )

        let briefing = CinematicBriefingService.deterministicBriefing(
            for: CinematicBriefingInput(
                repoName: "Compass",
                currentPhase: "Developing",
                immediatePlanTitle: "Add coverage",
                completedCount: 4,
                latestEvent: event
            )
        )

        XCTAssertTrue(
            briefing.detail.contains("Latest signal: Generated tests for cinematic briefing.")
        )
    }

    func testFallbackIncludesBoundedLatestCommitSubject() {
        let briefing = CinematicBriefingService.deterministicBriefing(
            for: CinematicBriefingInput(
                repoName: "Compass",
                currentPhase: "Developing",
                immediatePlanTitle: "Add commit-aware cinematic copy",
                completedCount: 5,
                latestEvent: nil,
                latestCommitSubject: #"Add [unsafe] `HUD` {"json":true} details at https://example.com with a deliberately overflowing subject line"#
            )
        )

        XCTAssertLessThanOrEqual(briefing.detail.count, CinematicBriefingService.detailMaxCharacters)
        XCTAssertTrue(briefing.detail.contains("Latest commit: Add unsafe HUD json:true details"))
        XCTAssertFalse(briefing.detail.contains("https://"))
        XCTAssertFalse(briefing.detail.contains("["))
        XCTAssertFalse(briefing.detail.contains("]"))
        XCTAssertFalse(briefing.detail.contains("`"))
        XCTAssertFalse(briefing.detail.contains("{"))
        XCTAssertFalse(briefing.detail.contains("}"))
        XCTAssertFalse(briefing.detail.contains("\""))
    }
}

final class CinematicBriefingInputTests: XCTestCase {
    func testInputEqualityIncludesLatestCommitSubject() {
        let base = CinematicBriefingInput(
            repoName: "Compass",
            currentPhase: "Developing",
            immediatePlanTitle: "Add commit-aware cinematic copy",
            completedCount: 2,
            latestEvent: nil,
            latestCommitSubject: "Ship commit-aware copy"
        )

        XCTAssertEqual(base, base)

        var changed = base
        changed.latestCommitSubject = "Refine world-text copy"
        XCTAssertNotEqual(base, changed)
    }
}

final class CinematicBriefingEventTests: XCTestCase {
    func testShortTextPrefersFirstDetailLineAndFitsHudCopy() {
        let event = CinematicBriefingEvent(
            line: LiveLine(
                level: .info,
                text: "Fallback event text should not be used",
                detail: """
                First detail line should be preferred because it carries the live HUD context and is intentionally far too long for the overlay
                Second detail line should be ignored
                """,
                kind: .command,
                status: .running
            )
        )

        XCTAssertEqual(
            event.shortText,
            "First detail line should be preferred because it carries the live HUD"
        )
        XCTAssertLessThanOrEqual(event.shortText.count, 72)
        XCTAssertFalse(event.shortText.contains("Fallback event text"))
        XCTAssertFalse(event.shortText.contains("Second detail line"))
    }
}

final class CinematicBriefingGeneratedParsingTests: XCTestCase {
    func testAcceptsGeneratedJSONBriefing() throws {
        let briefing = try XCTUnwrap(
            CinematicBriefingService.parseGeneratedBriefing(
                """
                {"title":"Compass Forge Ready","detail":"Repository signals align for the next careful implementation pass."}
                """
            )
        )

        XCTAssertEqual(briefing.title, "Compass Forge Ready")
        XCTAssertEqual(
            briefing.detail,
            "Repository signals align for the next careful implementation pass."
        )
    }

    func testAcceptsGeneratedTitleAndDetailLines() throws {
        let briefing = try XCTUnwrap(
            CinematicBriefingService.parseGeneratedBriefing(
                """
                Title: Compass Forge Ready
                Detail: Repository signals align for the next careful implementation pass.
                """
            )
        )

        XCTAssertEqual(briefing.title, "Compass Forge Ready")
        XCTAssertEqual(
            briefing.detail,
            "Repository signals align for the next careful implementation pass."
        )
    }

    func testRejectsMarkdownFences() {
        XCTAssertNil(
            CinematicBriefingService.parseGeneratedBriefing(
                """
                ```json
                {"title":"Compass Forge Ready","detail":"Repository signals align for the next careful implementation pass."}
                ```
                """
            )
        )
    }

    func testRejectsURLs() {
        XCTAssertNil(
            CinematicBriefingService.parseGeneratedBriefing(
                """
                Title: Compass Forge Ready
                Detail: Review https://example.com for the next implementation pass.
                """
            )
        )
    }

    func testRejectsRepeatedTitleAndDetailLines() {
        XCTAssertNil(
            CinematicBriefingService.parseGeneratedBriefing(
                """
                Title: Compass Forge Ready
                Detail: Repository signals align for the next careful implementation pass.
                Title: Compass Forge Ready
                Detail: Repository signals align for the next careful implementation pass.
                """
            )
        )
    }

    func testRejectsRepeatedTitleAsDetail() {
        XCTAssertNil(
            CinematicBriefingService.parseGeneratedBriefing(
                """
                Title: Compass Forge Ready
                Detail: Compass Forge Ready
                """
            )
        )
    }

    func testRejectsExcessiveWordCounts() {
        XCTAssertNil(
            CinematicBriefingService.parseGeneratedBriefing(
                """
                Title: Compass Forge Ready With Too Many Words For The Bounded Cinematic Overlay
                Detail: Repository signals align for the next careful implementation pass.
                """
            )
        )
        XCTAssertNil(
            CinematicBriefingService.parseGeneratedBriefing(
                """
                Title: Compass Forge Ready
                Detail: One two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty twentyone twentytwo twentythree twentyfour twentyfive twentysix twentyseven twentyeight twentynine.
                """
            )
        )
    }
}
