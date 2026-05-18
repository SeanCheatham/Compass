import Foundation
@testable import Compass
import XCTest

final class CinematicRunRecapFlavorTests: XCTestCase {
    func testAcceptsStrictGeneratedTitleAndDetailLines() throws {
        let input = makeFlavorInput()

        let flavor = try XCTUnwrap(
            CinematicRunRecapFlavorService.parseGeneratedFlavor(
                """
                Title: Verification Gate Sealed
                Detail: Compass finished the recap overlay and preserved the newest commit signal.
                """,
                sourceIdentifier: input.sourceIdentifier
            )
        )

        XCTAssertEqual(flavor.sourceIdentifier, input.sourceIdentifier)
        XCTAssertEqual(flavor.title, "Verification Gate Sealed")
        XCTAssertEqual(
            flavor.detail,
            "Compass finished the recap overlay and preserved the newest commit signal."
        )
        XCTAssertEqual(flavor.titleSource, .generated)
        XCTAssertEqual(flavor.titleSourceIdentifier, "generated")
        XCTAssertLessThanOrEqual(flavor.title.count, CinematicRunRecapFlavor.titleMaxCharacters)
        XCTAssertLessThanOrEqual(flavor.detail.count, CinematicRunRecapFlavor.detailMaxCharacters)
        XCTAssertLessThanOrEqual(flavor.tokenIdentifier.count, CinematicRunRecapFlavor.tokenMaxCharacters)
    }

    func testRejectsMarkdownURLsJSONQuotesAndOversizedGeneratedCopy() {
        let sourceIdentifier = makeFlavorInput().sourceIdentifier
        let invalidOutputs = [
            """
            Title: **Verification Gate Sealed**
            Detail: Compass finished the recap overlay.
            """,
            """
            Title: Verification Gate Sealed
            Detail: Review https://example.com before trusting the recap.
            """,
            """
            {"title":"Verification Gate Sealed","detail":"Compass finished the recap overlay."}
            """,
            """
            Title: "Verification Gate Sealed"
            Detail: Compass finished the recap overlay.
            """,
            """
            Title: One two three four five six seven eight nine
            Detail: Compass finished the recap overlay.
            """,
            """
            Title: Verification Gate Sealed
            Detail: One two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty one
            """
        ]

        for output in invalidOutputs {
            XCTAssertNil(
                CinematicRunRecapFlavorService.parseGeneratedFlavor(
                    output,
                    sourceIdentifier: sourceIdentifier
                ),
                output
            )
        }
    }

    func testDeterministicFallbackMatchesCurrentRecapCopyAndIdentifier() throws {
        let session = makeSession(3, endedAt: 3_500)
        let state = PlanState(
            completed: ["Finished deterministic fallback parity"],
            immediate: nil,
            midTerm: "",
            longTerm: ""
        )
        let commitPlan = CinematicCommitConstellationPlan(sessions: [session])
        let input = try XCTUnwrap(
            CinematicRunRecapPlanner.flavorInput(
                state: state,
                sessions: [session],
                isRunning: false,
                isAutoPlaying: false,
                recentRunCues: [:],
                commitConstellationPlan: commitPlan,
                nativeFeedbackLifecycle: CinematicNativeFeedbackCueLifecycle()
            )
        )
        let deterministicFlavor = CinematicRunRecapFlavorService.deterministicFlavor(for: input)

        let withoutFlavor = CinematicRunRecapPlanner.plan(
            state: state,
            sessions: [session],
            isRunning: false,
            isAutoPlaying: false,
            recentRunCues: [:],
            commitConstellationPlan: commitPlan,
            nativeFeedbackLifecycle: CinematicNativeFeedbackCueLifecycle()
        )
        let withFallback = CinematicRunRecapPlanner.plan(
            state: state,
            sessions: [session],
            isRunning: false,
            isAutoPlaying: false,
            recentRunCues: [:],
            commitConstellationPlan: commitPlan,
            nativeFeedbackLifecycle: CinematicNativeFeedbackCueLifecycle(),
            flavor: deterministicFlavor
        )

        XCTAssertEqual(deterministicFlavor.titleSource, .deterministic)
        XCTAssertEqual(withFallback.title, withoutFlavor.title)
        XCTAssertEqual(withFallback.detail, withoutFlavor.detail)
        XCTAssertEqual(withFallback.identifier, withoutFlavor.identifier)
        XCTAssertEqual(withFallback.flavorStateIdentifier, "deterministic")
        XCTAssertEqual(withFallback.titleSourceIdentifier, "deterministic")
    }

    func testRefreshInputEqualityIncludesRunRecapFlavorInput() throws {
        let firstFlavor = makeFlavorInput(sessionNumber: 4, completed: ["First recap input"])
        var secondFlavor = firstFlavor
        secondFlavor.sourceIdentifier += "|changed"
        secondFlavor.latestCompletedSummary = "Changed recap input"
        let briefing = CinematicBriefingInput(
            repoName: "Compass",
            currentPhase: "Succeeded",
            immediatePlanTitle: "Add recap flavor",
            completedCount: 1,
            latestEvent: nil,
            latestCommitSubject: "Ship flavor"
        )
        let worldText = CinematicWorldTextInput(
            repoName: briefing.repoName,
            currentPhase: briefing.currentPhase,
            immediatePlanTitle: briefing.immediatePlanTitle,
            completedCount: briefing.completedCount,
            latestEvent: briefing.latestEvent,
            latestCommitSubject: briefing.latestCommitSubject,
            languageProfile: .empty,
            activityProfile: .empty
        )

        let first = CinematicRefreshInput(
            briefing: briefing,
            worldText: worldText,
            commitConstellationIdentifier: "commit-constellation-focus.empty",
            runRecapFlavor: firstFlavor
        )
        let repeated = CinematicRefreshInput(
            briefing: briefing,
            worldText: worldText,
            commitConstellationIdentifier: "commit-constellation-focus.empty",
            runRecapFlavor: firstFlavor
        )
        let changed = CinematicRefreshInput(
            briefing: briefing,
            worldText: worldText,
            commitConstellationIdentifier: "commit-constellation-focus.empty",
            runRecapFlavor: secondFlavor
        )
        let activeRun = CinematicRefreshInput(
            briefing: briefing,
            worldText: worldText,
            commitConstellationIdentifier: "commit-constellation-focus.empty",
            runRecapFlavor: nil
        )

        XCTAssertEqual(first, repeated)
        XCTAssertNotEqual(first, changed)
        XCTAssertNotEqual(first, activeRun)
    }

    private func makeFlavorInput(
        sessionNumber: Int = 2,
        completed: [String] = ["Completed recap flavor"]
    ) -> CinematicRunRecapFlavorInput {
        let session = makeSession(
            sessionNumber,
            commits: [
                SessionCommit(
                    sha: "abcdef1234567890",
                    short: "abcdef1",
                    subject: "Ship flavor"
                )
            ],
            endedAt: Double(sessionNumber * 1_000 + 500)
        )
        return CinematicRunRecapPlanner.flavorInput(
            state: PlanState(completed: completed, immediate: nil, midTerm: "", longTerm: ""),
            sessions: [session],
            isRunning: false,
            isAutoPlaying: false,
            recentRunCues: [:],
            commitConstellationPlan: CinematicCommitConstellationPlan(sessions: [session]),
            nativeFeedbackLifecycle: CinematicNativeFeedbackCueLifecycle()
        )!
    }

    private func makeSession(
        _ number: Int,
        status: SessionStatus = .succeeded,
        commits: [SessionCommit] = [],
        endedAt: Double?
    ) -> SessionRecord {
        SessionRecord(
            session: number,
            startedAt: Double(number * 1_000),
            endedAt: endedAt,
            plan: "Add recap flavor",
            verify: "swift test --filter CinematicRunRecapFlavorTests",
            beforeSha: nil,
            afterSha: nil,
            commits: commits,
            status: status,
            notes: [],
            verifyOutput: nil,
            feedback: nil
        )
    }
}
