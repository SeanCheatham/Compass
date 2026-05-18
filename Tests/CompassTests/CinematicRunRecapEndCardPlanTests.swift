import Foundation
@testable import Compass
import XCTest

final class CinematicRunRecapEndCardPlanTests: XCTestCase {
    func testPlanIsRecapOnlyAndRequiresAvailableRecap() throws {
        let session = makeSession(1, status: .succeeded, endedAt: 1_500)
        let recapPlan = makeRecapPlan(session: session)

        XCTAssertEqual(
            CinematicRunRecapEndCardPlanner.plan(
                isRecapOverlaySelected: false,
                recapPlan: recapPlan
            ),
            .none
        )

        let runningRecap = CinematicRunRecapPlanner.plan(
            state: recapState(),
            sessions: [session],
            isRunning: true,
            isAutoPlaying: false,
            recentRunCues: [:],
            commitConstellationPlan: .empty,
            nativeFeedbackLifecycle: CinematicNativeFeedbackCueLifecycle()
        )
        XCTAssertEqual(
            CinematicRunRecapEndCardPlanner.plan(
                isRecapOverlaySelected: true,
                recapPlan: runningRecap
            ),
            .none
        )

        let emptyRecap = CinematicRunRecapPlan.empty(reason: "active-run")
        XCTAssertEqual(
            CinematicRunRecapEndCardPlanner.plan(
                isRecapOverlaySelected: true,
                recapPlan: emptyRecap
            ),
            .none
        )

        let endCard = CinematicRunRecapEndCardPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: recapPlan
        )
        let descriptor = try XCTUnwrap(endCard.descriptor)

        XCTAssertTrue(endCard.isActive)
        XCTAssertEqual(descriptor.recapIdentifier, recapPlan.identifier)
        XCTAssertEqual(descriptor.title, "Run #1 succeeded")
        XCTAssertEqual(descriptor.detail, "Completed recap end card")
        XCTAssertEqual(descriptor.status, "0 commit highlights - 1 completed item - 0 events")
        XCTAssertEqual(descriptor.titleSourceIdentifier, "deterministic")
        XCTAssertEqual(descriptor.flavorStateIdentifier, "deterministic")
    }

    func testStyleTreatmentsDriveAnchorsGlyphsAndPlaqueRecipes() throws {
        let cases: [
            (
                status: SessionStatus,
                style: String,
                color: String,
                anchor: String,
                light: String,
                tint: String,
                glyph: String,
                accent: String,
                route: String,
                primitives: [String]
            )
        ] = [
            (
                .succeeded,
                "success",
                "green",
                "victory-arch",
                "verify",
                "git",
                "recap.success.seal",
                "verify-seal",
                "recap.success",
                ["rail.top", "rail.bottom", "seal.left", "seal.right"]
            ),
            (
                .failed,
                "failure",
                "red",
                "fracture-gate",
                "failure",
                "failure",
                "recap.failure.fracture",
                "failure-fracture",
                "recap.failure",
                ["rail.top", "rail.bottom", "fracture.diagonal.a", "fracture.diagonal.b"]
            ),
            (
                .cancelled,
                "warning",
                "orange",
                "right-warning-pylon",
                "pressure",
                "failure",
                "recap.warning.rails",
                "warning-rails",
                "recap.warning",
                ["rail.top", "rail.bottom", "warning.left", "warning.right"]
            )
        ]

        for expected in cases {
            let session = makeSession(2, status: expected.status, endedAt: 2_500)
            let endCard = CinematicRunRecapEndCardPlanner.plan(
                isRecapOverlaySelected: true,
                recapPlan: makeRecapPlan(session: session)
            )
            let descriptor = try XCTUnwrap(endCard.descriptor)

            XCTAssertEqual(descriptor.styleIdentifier, expected.style)
            XCTAssertEqual(descriptor.colorIdentifier, expected.color)
            XCTAssertEqual(descriptor.anchorIdentifier, expected.anchor)
            XCTAssertEqual(descriptor.lightFamilyIdentifier, expected.light)
            XCTAssertEqual(descriptor.tintFamilyIdentifier, expected.tint)
            XCTAssertEqual(descriptor.glyphIdentifier, expected.glyph)
            XCTAssertEqual(descriptor.plaqueTreatmentAccentIdentifier, expected.accent)
            XCTAssertEqual(descriptor.plaqueTreatmentRouteIdentifier, expected.route)
            XCTAssertEqual(descriptor.plaqueTreatmentRenderPrimitiveIdentifiers, expected.primitives)
            XCTAssertInRange(descriptor.scale, CinematicRunRecapEndCardPlan.scaleRange)
            XCTAssertInRange(descriptor.cadence, CinematicRunRecapEndCardPlan.cadenceRange)
            XCTAssertEndCardLayoutInRange(descriptor.layout)
        }
    }

    func testGeneratedRecapCopyRefreshesEndCardIdentifierWithoutChangingTimelineFocus() throws {
        let session = makeSession(
            3,
            status: .succeeded,
            commits: [
                SessionCommit(
                    sha: "1234567890abcdef",
                    short: "1234567",
                    subject: "Refresh recap copy"
                )
            ],
            endedAt: 3_500
        )
        let state = recapState()
        let commitPlan = CinematicCommitConstellationPlan(sessions: [session])
        let deterministicRecap = CinematicRunRecapPlanner.plan(
            state: state,
            sessions: [session],
            isRunning: false,
            isAutoPlaying: false,
            recentRunCues: [:],
            commitConstellationPlan: commitPlan,
            nativeFeedbackLifecycle: CinematicNativeFeedbackCueLifecycle()
        )
        let flavorInput = try XCTUnwrap(
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
        let flavor = CinematicRunRecapFlavor(
            sourceIdentifier: flavorInput.sourceIdentifier,
            title: "Generated Recap Card",
            detail: "A generated recap card refreshed without moving timeline focus.",
            titleSource: .generated
        )
        let generatedRecap = CinematicRunRecapPlanner.plan(
            state: state,
            sessions: [session],
            isRunning: false,
            isAutoPlaying: false,
            recentRunCues: [:],
            commitConstellationPlan: commitPlan,
            nativeFeedbackLifecycle: CinematicNativeFeedbackCueLifecycle(),
            flavor: flavor
        )
        let deterministicCard = CinematicRunRecapEndCardPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: deterministicRecap
        )
        let generatedCard = CinematicRunRecapEndCardPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: generatedRecap
        )
        let generatedDescriptor = try XCTUnwrap(generatedCard.descriptor)
        let timelineBefore = CinematicSessionTimelinePlan(
            sessions: [session],
            selectedBeatID: "session-3-plan"
        )
        let timelineFocusBefore = CinematicTimelineSceneFocusPlanner.plan(
            selectedBeat: timelineBefore.selectedBeat,
            commitConstellationPlan: commitPlan,
            recoveryCuePlan: .none
        )

        XCTAssertNotEqual(deterministicCard.identifier, generatedCard.identifier)
        XCTAssertEqual(generatedDescriptor.title, "Generated Recap Card")
        XCTAssertEqual(generatedDescriptor.detail, "A generated recap card refreshed without moving timeline focus.")
        XCTAssertEqual(generatedDescriptor.titleSourceIdentifier, "generated")
        XCTAssertEqual(generatedDescriptor.flavorStateIdentifier, "applied")

        let timelineAfter = CinematicSessionTimelinePlan(
            sessions: [session],
            selectedBeatID: "session-3-plan"
        )
        let timelineFocusAfter = CinematicTimelineSceneFocusPlanner.plan(
            selectedBeat: timelineAfter.selectedBeat,
            commitConstellationPlan: commitPlan,
            recoveryCuePlan: .none
        )

        XCTAssertEqual(timelineAfter, timelineBefore)
        XCTAssertEqual(timelineAfter.selectedBeatID, "session-3-plan")
        XCTAssertEqual(timelineFocusAfter, timelineFocusBefore)
    }

    func testIdentifiersAreStableBoundedAndReflectBoundedCopy() throws {
        let session = makeSession(4, status: .failed, endedAt: 4_500)
        let longRecap = CinematicRunRecapPlan.available(
            session: session,
            latestCompletedSummary: String(repeating: "Completed a very long recap end card line ", count: 8),
            newestCommitHighlight: String(repeating: "Commit highlight ", count: 10),
            commitHighlightCount: 12,
            completedCount: 9,
            eventChips: []
        )

        let first = CinematicRunRecapEndCardPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: longRecap
        )
        let repeated = CinematicRunRecapEndCardPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: longRecap
        )
        var changedRecap = longRecap
        changedRecap.status = "Different bounded status"
        let changed = CinematicRunRecapEndCardPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: changedRecap
        )
        let descriptor = try XCTUnwrap(first.descriptor)

        XCTAssertEqual(first, repeated)
        XCTAssertEqual(first.identifier, repeated.identifier)
        XCTAssertNotEqual(first.identifier, changed.identifier)
        XCTAssertLessThanOrEqual(first.identifier.count, CinematicRunRecapEndCardPlan.identifierMaxCharacters)
        XCTAssertLessThanOrEqual(descriptor.identifier.count, CinematicRunRecapEndCardPlan.identifierMaxCharacters)
        XCTAssertLessThanOrEqual(descriptor.titleLength, CinematicRunRecapEndCardPlan.titleMaxCharacters)
        XCTAssertLessThanOrEqual(descriptor.detailLength, CinematicRunRecapEndCardPlan.detailMaxCharacters)
        XCTAssertLessThanOrEqual(descriptor.statusLength, CinematicRunRecapEndCardPlan.statusMaxCharacters)
    }

    func testStaleGeneratedFlavorStaysHiddenBehindRecapPlanCopy() throws {
        let session = makeSession(5, status: .succeeded, endedAt: 5_500)
        let state = recapState()
        let flavorInput = try XCTUnwrap(
            CinematicRunRecapPlanner.flavorInput(
                state: state,
                sessions: [session],
                isRunning: false,
                isAutoPlaying: false,
                recentRunCues: [:],
                commitConstellationPlan: .empty,
                nativeFeedbackLifecycle: CinematicNativeFeedbackCueLifecycle()
            )
        )
        let staleFlavor = CinematicRunRecapFlavor(
            sourceIdentifier: "\(flavorInput.sourceIdentifier)|stale",
            title: "Stale Generated Title",
            detail: "Stale generated detail should not reach the end card.",
            titleSource: .generated
        )
        let staleRecap = CinematicRunRecapPlanner.plan(
            state: state,
            sessions: [session],
            isRunning: false,
            isAutoPlaying: false,
            recentRunCues: [:],
            commitConstellationPlan: .empty,
            nativeFeedbackLifecycle: CinematicNativeFeedbackCueLifecycle(),
            flavor: staleFlavor
        )
        let staleCard = CinematicRunRecapEndCardPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: staleRecap
        )
        let descriptor = try XCTUnwrap(staleCard.descriptor)

        XCTAssertEqual(staleRecap.flavorStateIdentifier, "stale")
        XCTAssertEqual(staleRecap.titleSourceIdentifier, "deterministic")
        XCTAssertEqual(descriptor.flavorStateIdentifier, "stale")
        XCTAssertEqual(descriptor.titleSourceIdentifier, "deterministic")
        XCTAssertEqual(descriptor.title, "Run #5 succeeded")
        XCTAssertEqual(descriptor.detail, "Completed recap end card")
        XCTAssertFalse(descriptor.title.contains("Stale Generated"))
        XCTAssertFalse(descriptor.detail.contains("Stale generated"))
    }

    private func makeRecapPlan(session: SessionRecord) -> CinematicRunRecapPlan {
        CinematicRunRecapPlanner.plan(
            state: recapState(),
            sessions: [session],
            isRunning: false,
            isAutoPlaying: false,
            recentRunCues: [:],
            commitConstellationPlan: .empty,
            nativeFeedbackLifecycle: CinematicNativeFeedbackCueLifecycle()
        )
    }

    private func recapState() -> PlanState {
        PlanState(
            completed: ["Completed recap end card"],
            immediate: nil,
            midTerm: "",
            longTerm: ""
        )
    }

    private func makeSession(
        _ number: Int,
        status: SessionStatus,
        commits: [SessionCommit] = [],
        endedAt: Double?
    ) -> SessionRecord {
        SessionRecord(
            session: number,
            startedAt: Double(number * 1_000),
            endedAt: endedAt,
            plan: "Stage recap end card",
            verify: "swift test --filter CinematicRunRecapEndCardPlanTests",
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

private func XCTAssertInRange<T: Comparable>(
    _ value: T,
    _ range: ClosedRange<T>,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertGreaterThanOrEqual(value, range.lowerBound, file: file, line: line)
    XCTAssertLessThanOrEqual(value, range.upperBound, file: file, line: line)
}

private func XCTAssertEndCardLayoutInRange(
    _ layout: CinematicRunRecapEndCardPlan.LayoutDescriptor,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertInRange(layout.anchorPosition.x, CinematicSceneNarrativeCuePlan.cueAnchorXRange, file: file, line: line)
    XCTAssertInRange(layout.anchorPosition.y, CinematicSceneNarrativeCuePlan.cueAnchorYRange, file: file, line: line)
    XCTAssertInRange(layout.anchorPosition.z, CinematicSceneNarrativeCuePlan.cueAnchorZRange, file: file, line: line)
    XCTAssertInRange(layout.plateSize.x, CinematicSceneNarrativeCuePlan.cuePlateWidthRange, file: file, line: line)
    XCTAssertInRange(layout.plateSize.y, CinematicSceneNarrativeCuePlan.cuePlateHeightRange, file: file, line: line)
    XCTAssertInRange(layout.primaryTextWidth, CinematicSceneNarrativeCuePlan.cueTextWidthRange, file: file, line: line)
    XCTAssertInRange(layout.secondaryTextWidth, CinematicSceneNarrativeCuePlan.cueTextWidthRange, file: file, line: line)
    XCTAssertInRange(layout.primaryFontSize, CinematicSceneNarrativeCuePlan.cueFontSizeRange, file: file, line: line)
    XCTAssertInRange(layout.secondaryFontSize, CinematicSceneNarrativeCuePlan.cueFontSizeRange, file: file, line: line)
    XCTAssertInRange(layout.backingOpacity, CinematicSceneNarrativeCuePlan.cueBackingOpacityRange, file: file, line: line)
    XCTAssertInRange(layout.plateDepth, CinematicSceneNarrativeCuePlan.cuePlateDepthRange, file: file, line: line)
    XCTAssertInRange(layout.plateZOffset, CinematicSceneNarrativeCuePlan.cueLayerZRange, file: file, line: line)
}
