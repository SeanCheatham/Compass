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

    func testPinnedComparisonCueGatesAndBoundsRealityDescriptorMetadata() throws {
        let session = makeSession(6, status: .succeeded, endedAt: 6_500)
        let recapPlan = makeRecapPlan(session: session)
        let history = makeArtifactHistory(
            caseIdentifier: "cue-gating",
            sessions: [12, 11, 10],
            bodyForSession: { session in
                session == 12
                    ? "selected bridge beacon for cue gating"
                    : "archived target body \(session)"
            }
        )
        let selected = try XCTUnwrap(history.entries.first { $0.sessionNumber == 12 })
        let target = try XCTUnwrap(history.entries.first { $0.sessionNumber == 10 })
        let staleIdentifier = "missing-pinned-end-card-cue"

        let activeComparison = CinematicRunRecapShareArtifactComparisonPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: selected.identifier,
            targetMode: .pinnedReference,
            pinnedEntryIdentifiers: [target.identifier, staleIdentifier]
        )
        let adjacentComparison = CinematicRunRecapShareArtifactComparisonPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: selected.identifier,
            targetMode: .adjacent,
            pinnedEntryIdentifiers: [target.identifier]
        )
        let selectedOnlyComparison = CinematicRunRecapShareArtifactComparisonPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: selected.identifier,
            targetMode: .pinnedReference,
            pinnedEntryIdentifiers: [selected.identifier]
        )
        let noMatchComparison = CinematicRunRecapShareArtifactComparisonPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: selected.identifier,
            searchQuery: "missing end card cue query",
            targetMode: .pinnedReference,
            pinnedEntryIdentifiers: [target.identifier]
        )
        let staleComparison = CinematicRunRecapShareArtifactComparisonPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: selected.identifier,
            targetMode: .pinnedReference,
            pinnedEntryIdentifiers: [staleIdentifier]
        )
        let filteredComparison = CinematicRunRecapShareArtifactComparisonPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: selected.identifier,
            searchQuery: "selected bridge beacon",
            targetMode: .pinnedReference,
            pinnedEntryIdentifiers: [target.identifier]
        )
        let promotedHoldComparison = CinematicRunRecapShareArtifactComparisonPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: selected.identifier,
            targetMode: .pinnedReference,
            pinnedEntryIdentifiers: [target.identifier],
            savedTourHoldEntryIdentifier: target.identifier
        )
        let filteredPromotedHoldComparison = CinematicRunRecapShareArtifactComparisonPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: selected.identifier,
            searchQuery: "selected bridge beacon",
            targetMode: .pinnedReference,
            pinnedEntryIdentifiers: [target.identifier],
            savedTourHoldEntryIdentifier: target.identifier
        )

        let noComparisonCard = CinematicRunRecapEndCardPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: recapPlan
        )
        let adjacentCard = CinematicRunRecapEndCardPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: recapPlan,
            artifactComparisonPlan: adjacentComparison
        )
        let activeCard = CinematicRunRecapEndCardPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: recapPlan,
            artifactComparisonPlan: activeComparison
        )
        let selectedOnlyCard = CinematicRunRecapEndCardPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: recapPlan,
            artifactComparisonPlan: selectedOnlyComparison
        )
        let noMatchCard = CinematicRunRecapEndCardPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: recapPlan,
            artifactComparisonPlan: noMatchComparison
        )
        let staleCard = CinematicRunRecapEndCardPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: recapPlan,
            artifactComparisonPlan: staleComparison
        )
        let filteredCard = CinematicRunRecapEndCardPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: recapPlan,
            artifactComparisonPlan: filteredComparison
        )
        let promotedHoldCard = CinematicRunRecapEndCardPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: recapPlan,
            artifactComparisonPlan: promotedHoldComparison
        )
        let filteredPromotedHoldCard = CinematicRunRecapEndCardPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: recapPlan,
            artifactComparisonPlan: filteredPromotedHoldComparison
        )

        let noComparisonDescriptor = try XCTUnwrap(noComparisonCard.descriptor)
        let adjacentDescriptor = try XCTUnwrap(adjacentCard.descriptor)
        let activeDescriptor = try XCTUnwrap(activeCard.descriptor)
        let selectedOnlyDescriptor = try XCTUnwrap(selectedOnlyCard.descriptor)
        let noMatchDescriptor = try XCTUnwrap(noMatchCard.descriptor)
        let staleDescriptor = try XCTUnwrap(staleCard.descriptor)
        let filteredDescriptor = try XCTUnwrap(filteredCard.descriptor)
        let promotedHoldDescriptor = try XCTUnwrap(promotedHoldCard.descriptor)
        let filteredPromotedHoldDescriptor = try XCTUnwrap(filteredPromotedHoldCard.descriptor)
        let activeCue = try XCTUnwrap(activeDescriptor.pinnedComparisonCue)
        let filteredCue = try XCTUnwrap(filteredDescriptor.pinnedComparisonCue)
        let promotedHoldCue = try XCTUnwrap(promotedHoldDescriptor.pinnedComparisonCue)
        let filteredPromotedHoldCue = try XCTUnwrap(filteredPromotedHoldDescriptor.pinnedComparisonCue)

        XCTAssertNil(noComparisonDescriptor.pinnedComparisonCue)
        XCTAssertNil(adjacentDescriptor.pinnedComparisonCue)
        XCTAssertEqual(noComparisonDescriptor.identifier, adjacentDescriptor.identifier)
        XCTAssertEqual(noComparisonCard.identifier, adjacentCard.identifier)
        XCTAssertEqual(adjacentDescriptor.pinnedComparisonCueModeIdentifier, "adjacent")
        XCTAssertEqual(adjacentDescriptor.pinnedComparisonCueStateIdentifier, "inactive")
        XCTAssertNotEqual(activeCard.identifier, adjacentCard.identifier)

        XCTAssertEqual(activeDescriptor.pinnedComparisonCueModeIdentifier, "pinned_reference")
        XCTAssertEqual(activeDescriptor.pinnedComparisonCueStateIdentifier, "visible-pinned-target")
        XCTAssertEqual(activeCue.comparisonIdentifier, activeComparison.identifier)
        XCTAssertEqual(activeCue.comparisonExportIdentifier, activeComparison.exportIdentifier)
        XCTAssertEqual(activeCue.selectedEntryIdentifier, selected.identifier)
        XCTAssertEqual(activeCue.targetEntryIdentifier, target.identifier)
        XCTAssertEqual(activeCue.selectedSessionNumber, 12)
        XCTAssertEqual(activeCue.targetSessionNumber, 10)
        XCTAssertEqual(activeCue.deltaLabel, "delta 2 sessions")
        XCTAssertEqual(activeCue.pinnedEntryCount, 2)
        XCTAssertEqual(activeCue.retainedPinnedEntryCount, 1)
        XCTAssertEqual(activeCue.missingPinnedEntryCount, 1)
        XCTAssertEqual(activeCue.filteredPinnedEntryCount, 0)
        XCTAssertEqual(activeCue.warningStateIdentifier, "clear")
        XCTAssertEqual(activeCue.noMatchStateIdentifier, "none")
        XCTAssertEqual(activeCue.glyphIdentifier, "pin.bridge.stale")
        XCTAssertEqual(activeCue.railTreatmentIdentifier, "stale-pin-rail")
        XCTAssertLessThanOrEqual(activeCue.identifier.count, CinematicRunRecapEndCardPlan.identifierMaxCharacters)
        XCTAssertLessThanOrEqual(activeCue.labelLength, CinematicRunRecapEndCardPlan.pinnedComparisonLabelMaxCharacters)
        XCTAssertLessThanOrEqual(activeCue.detailLength, CinematicRunRecapEndCardPlan.pinnedComparisonDetailMaxCharacters)
        XCTAssertLessThanOrEqual(
            activeCue.deltaLabelLength,
            CinematicRunRecapEndCardPlan.pinnedComparisonDeltaLabelMaxCharacters
        )

        XCTAssertNil(selectedOnlyDescriptor.pinnedComparisonCue)
        XCTAssertEqual(
            selectedOnlyDescriptor.pinnedComparisonCueStateIdentifier,
            "selected-only-pinned-recap-share-artifact"
        )
        XCTAssertNil(noMatchDescriptor.pinnedComparisonCue)
        XCTAssertEqual(noMatchDescriptor.pinnedComparisonCueStateIdentifier, "no-selected-recap-share-artifact")
        XCTAssertEqual(
            noMatchDescriptor.pinnedComparisonCueNoMatchStateIdentifier,
            "no-matching-recap-share-artifacts"
        )
        XCTAssertNil(staleDescriptor.pinnedComparisonCue)
        XCTAssertEqual(staleDescriptor.pinnedComparisonCueStateIdentifier, "pinned-recap-share-artifacts-missing")
        XCTAssertEqual(filteredDescriptor.pinnedComparisonCueStateIdentifier, "filtered-pinned-target")
        XCTAssertEqual(filteredCue.filteredPinnedEntryCount, 1)
        XCTAssertEqual(filteredCue.glyphIdentifier, "pin.bridge.filtered")
        XCTAssertEqual(filteredCue.railTreatmentIdentifier, "filtered-pin-rail")

        XCTAssertEqual(promotedHoldComparison.promotedHoldStateIdentifier, "retained-promoted-hold-target")
        XCTAssertEqual(promotedHoldCue.promotedHoldStateIdentifier, "retained-promoted-hold-target")
        XCTAssertEqual(promotedHoldCue.promotedHoldEntryIdentifier, target.identifier)
        XCTAssertEqual(promotedHoldCue.glyphIdentifier, "hold.pin.bridge.active")
        XCTAssertEqual(promotedHoldCue.railTreatmentIdentifier, "promoted-hold-rail")
        XCTAssertTrue(promotedHoldCue.label.contains("Promoted hold"))
        XCTAssertTrue(promotedHoldCue.detail.contains("held artifact"))
        XCTAssertNotEqual(promotedHoldCue.identifier, activeCue.identifier)

        XCTAssertEqual(
            filteredPromotedHoldComparison.promotedHoldStateIdentifier,
            "filtered-promoted-hold-target"
        )
        XCTAssertEqual(filteredPromotedHoldCue.promotedHoldStateIdentifier, "filtered-promoted-hold-target")
        XCTAssertEqual(filteredPromotedHoldCue.glyphIdentifier, "hold.pin.bridge.filtered")
        XCTAssertEqual(filteredPromotedHoldCue.railTreatmentIdentifier, "filtered-promoted-hold-rail")
    }

    func testAdjacentComparisonCuePathKeepsShareTextTimelineFocusAndPinPlannerStable() throws {
        let session = makeSession(7, status: .succeeded, endedAt: 7_500)
        let recapPlan = makeRecapPlan(session: session)
        let history = makeArtifactHistory(
            caseIdentifier: "cue-invariants",
            sessions: [3, 2, 1],
            bodyForSession: { "invariant body \($0)" }
        )
        let selected = try XCTUnwrap(history.entries.first { $0.sessionNumber == 3 })
        let pinned = try XCTUnwrap(history.entries.first { $0.sessionNumber == 1 })
        let pinPlanBefore = CinematicRunRecapShareArtifactPinnedReferencePlanner.plan(
            historyPlan: history,
            pinnedEntryIdentifiers: [pinned.identifier],
            selectedEntryIdentifier: selected.identifier
        )
        let timelinePlan = CinematicSessionTimelinePlan(
            sessions: [session],
            selectedBeatID: "session-7-plan"
        )
        let timelineFocusBefore = CinematicTimelineSceneFocusPlanner.plan(
            selectedBeat: timelinePlan.selectedBeat,
            commitConstellationPlan: .empty,
            recoveryCuePlan: .none
        )
        let baseEndCard = CinematicRunRecapEndCardPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: recapPlan
        )
        let adjacentComparison = CinematicRunRecapShareArtifactComparisonPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: selected.identifier,
            targetMode: .adjacent,
            pinnedEntryIdentifiers: [pinned.identifier]
        )
        let adjacentEndCard = CinematicRunRecapEndCardPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: recapPlan,
            artifactComparisonPlan: adjacentComparison
        )
        let baseShare = CinematicRunRecapSharePlanner.plan(
            recapPlan: recapPlan,
            endCardDescriptor: baseEndCard.descriptor
        )
        let adjacentShare = CinematicRunRecapSharePlanner.plan(
            recapPlan: recapPlan,
            endCardDescriptor: adjacentEndCard.descriptor
        )

        XCTAssertEqual(baseEndCard.identifier, adjacentEndCard.identifier)
        XCTAssertEqual(baseShare, adjacentShare)
        XCTAssertEqual(timelinePlan.selectedBeatID, "session-7-plan")
        XCTAssertEqual(
            CinematicTimelineSceneFocusPlanner.plan(
                selectedBeat: timelinePlan.selectedBeat,
                commitConstellationPlan: .empty,
                recoveryCuePlan: .none
            ),
            timelineFocusBefore
        )
        XCTAssertEqual(
            CinematicRunRecapShareArtifactPinnedReferencePlanner.plan(
                historyPlan: history,
                pinnedEntryIdentifiers: [pinned.identifier],
                selectedEntryIdentifier: selected.identifier
            ),
            pinPlanBefore
        )
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

    private func makeArtifactHistory(
        caseIdentifier: String,
        sessions: [Int],
        bodyForSession: (Int) -> String
    ) -> CinematicRunRecapShareArtifactHistoryPlan {
        let entries = sessions.sorted(by: >).map { session in
            let filename = "\(session)-recap-share-\(caseIdentifier).md"
            let markdown = """
            # Compass Run Recap Share

            - Artifact: \(caseIdentifier)-artifact-\(session)
            - Availability: available
            - Session: \(session)
            - Filename: \(filename)
            - Share: share-id
            - Recap: recap-id
            - Focus: focus-id
            - End card: end-card-id
            - Title: \(caseIdentifier) \(session)
            - Status: succeeded
            - Detail: End card cue detail
            - Commit: Cue commit \(session)

            ## Events
            - event

            ## Share Text

            ```text
            \(bodyForSession(session))
            ```
            """
            return CinematicRunRecapShareArtifactHistoryPlan.Entry(
                identifier: "\(caseIdentifier)-entry-\(session)",
                sessionNumber: session,
                filename: filename,
                url: URL(fileURLWithPath: "/tmp/\(filename)"),
                pathDisplayText: "/tmp/\(filename)",
                titleSnippet: "\(caseIdentifier) \(session)",
                statusSnippet: "succeeded",
                commitSnippet: "Cue commit \(session)",
                markdownContents: markdown,
                markdownLength: markdown.count
            )
        }

        return CinematicRunRecapShareArtifactHistoryPlan(
            identifier: "\(caseIdentifier)-history",
            isAvailable: true,
            availabilityReason: "available",
            storageRootDisplayText: "/tmp/\(caseIdentifier)",
            sessionsDisplayText: "/tmp/\(caseIdentifier)/sessions",
            retentionLimit: CinematicRunRecapShareArtifactHistoryPlan.retentionLimit,
            entries: entries,
            totalCount: entries.count,
            hiddenCount: 0,
            cleanupCandidateCount: 0,
            hiddenCleanupCandidateCount: 0,
            cleanupCandidateIdentifiers: [],
            warnings: [],
            warningCount: 0,
            hiddenWarningCount: 0,
            exportIdentifier: "\(caseIdentifier)-history-export",
            combinedMarkdownExport: entries.map(\.markdownContents).joined(separator: "\n\n")
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
