import Foundation
@testable import Compass
import XCTest

final class CinematicRunRecapSharePlanTests: XCTestCase {
    func testAvailableShareOutputIncludesCopyAndVisualDescriptors() throws {
        let session = makeSession(
            21,
            commits: [
                SessionCommit(
                    sha: "abcdef1234567890",
                    short: "abcdef1",
                    subject: "Ship recap share export"
                )
            ],
            endedAt: 21_500
        )
        let state = PlanState(
            completed: ["Completed recap share export"],
            immediate: nil,
            midTerm: "",
            longTerm: ""
        )
        let commitPlan = CinematicCommitConstellationPlan(sessions: [session])
        let recapPlan = CinematicRunRecapPlanner.plan(
            state: state,
            sessions: [session],
            isRunning: false,
            isAutoPlaying: false,
            recentRunCues: [
                21: runCue(
                    kind: .failedVerify,
                    severity: .failure,
                    label: "Retry Develop",
                    detail: "verify failed before share",
                    systemImage: "checkmark.seal.fill"
                )
            ],
            commitConstellationPlan: commitPlan,
            nativeFeedbackLifecycle: CinematicNativeFeedbackCueLifecycle()
        )
        let timelinePlan = CinematicSessionTimelinePlan(sessions: [session])
        let focusPlan = CinematicRunRecapSceneFocusPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: recapPlan,
            commitConstellationPlan: commitPlan,
            timelinePlan: timelinePlan
        )
        let endCardPlan = CinematicRunRecapEndCardPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: recapPlan
        )
        let focusDescriptor = try XCTUnwrap(focusPlan.descriptor)
        let endCardDescriptor = try XCTUnwrap(endCardPlan.descriptor)

        let share = CinematicRunRecapSharePlanner.plan(
            recapPlan: recapPlan,
            recapFocusDescriptor: focusDescriptor,
            endCardDescriptor: endCardDescriptor
        )

        XCTAssertTrue(share.isAvailable)
        XCTAssertEqual(share.availabilityIdentifier, "available")
        XCTAssertEqual(share.availabilityReason, "available")
        XCTAssertEqual(share.recapIdentifier, recapPlan.identifier)
        XCTAssertEqual(share.recapFocusIdentifier, focusDescriptor.identifier)
        XCTAssertEqual(share.endCardIdentifier, endCardDescriptor.identifier)
        XCTAssertEqual(share.title, recapPlan.title)
        XCTAssertEqual(share.detail, recapPlan.detail)
        XCTAssertEqual(share.status, recapPlan.status)
        XCTAssertEqual(share.commitHighlight, "Ship recap share export")
        XCTAssertEqual(share.eventSummaryCount, 1)
        XCTAssertTrue(share.eventSummaries.first?.contains("Retry Develop") == true)
        XCTAssertTrue(share.visualDescriptorTokens.contains("style:success"))
        XCTAssertTrue(share.visualDescriptorTokens.contains("focus-shot:victory"))
        XCTAssertTrue(share.visualDescriptorTokens.contains("end-card-anchor:victory-arch"))
        XCTAssertTrue(share.visualDescriptorTokens.contains("end-card-treatment:verify-seal"))
        XCTAssertTrue(share.text.contains("Compass Run Recap"))
        XCTAssertTrue(share.text.contains("Share: \(share.identifier)"))
        XCTAssertTrue(share.text.contains("Availability: available"))
        XCTAssertTrue(share.text.contains("Title: \(recapPlan.title)"))
        XCTAssertTrue(share.text.contains("Status: \(recapPlan.status)"))
        XCTAssertTrue(share.text.contains("Detail: \(recapPlan.detail)"))
        XCTAssertTrue(share.text.contains("Commit: Ship recap share export"))
        XCTAssertTrue(share.text.contains("Visual:"))
    }

    func testUnavailableShareExplainsAvailabilityReasonWithoutEventPayload() {
        let recapPlan = CinematicRunRecapPlan.empty(reason: "active-run")

        let share = CinematicRunRecapSharePlanner.plan(recapPlan: recapPlan)

        XCTAssertFalse(share.isAvailable)
        XCTAssertEqual(share.availabilityIdentifier, "active-run")
        XCTAssertEqual(share.availabilityReason, "active-run")
        XCTAssertEqual(share.recapIdentifier, recapPlan.identifier)
        XCTAssertNil(share.recapFocusIdentifier)
        XCTAssertNil(share.endCardIdentifier)
        XCTAssertEqual(share.eventSummaryCount, 0)
        XCTAssertTrue(share.visualDescriptorTokens.contains("style:empty"))
        XCTAssertTrue(share.text.contains("Availability: unavailable (active-run)"))
        XCTAssertTrue(share.text.contains("Title: Run recap unavailable"))
        XCTAssertTrue(share.text.contains("Events: none"))
        XCTAssertLessThanOrEqual(share.identifier.count, CinematicRunRecapSharePlan.identifierMaxCharacters)
        XCTAssertLessThanOrEqual(share.textLength, CinematicRunRecapSharePlan.textMaxCharacters)
    }

    func testShareIdentifiersAndBoundedTextAreDeterministicallyStable() {
        let session = makeSession(
            22,
            commits: [
                SessionCommit(
                    sha: "feedface1234567890",
                    short: "feedfac",
                    subject: String(repeating: "Long recap share commit ", count: 8)
                )
            ],
            endedAt: 22_500
        )
        let longCopy = String(repeating: "Completed deterministic share export ", count: 10)
        let recapPlan = makeRecapPlan(
            session: session,
            state: PlanState(completed: [longCopy], immediate: nil, midTerm: "", longTerm: "")
        )

        let first = CinematicRunRecapSharePlanner.plan(recapPlan: recapPlan)
        let repeated = CinematicRunRecapSharePlanner.plan(recapPlan: recapPlan)
        let changed = CinematicRunRecapSharePlanner.plan(
            recapPlan: recapPlan,
            recapFocusDescriptor: CinematicRunRecapSceneFocusPlanner.plan(
                isRecapOverlaySelected: true,
                recapPlan: recapPlan,
                commitConstellationPlan: CinematicCommitConstellationPlan(sessions: [session]),
                timelinePlan: CinematicSessionTimelinePlan(sessions: [session])
            ).descriptor
        )

        XCTAssertEqual(first, repeated)
        XCTAssertEqual(first.identifier, repeated.identifier)
        XCTAssertNotEqual(first.identifier, changed.identifier)
        XCTAssertLessThanOrEqual(first.identifier.count, CinematicRunRecapSharePlan.identifierMaxCharacters)
        XCTAssertLessThanOrEqual(first.textLength, CinematicRunRecapSharePlan.textMaxCharacters)
        XCTAssertLessThanOrEqual(first.title.count, CinematicRunRecapPlan.titleLimit)
        XCTAssertLessThanOrEqual(first.detail.count, CinematicRunRecapPlan.detailLimit)
        XCTAssertLessThanOrEqual(first.status.count, CinematicRunRecapPlan.statusLimit)
        XCTAssertLessThanOrEqual(
            first.commitHighlight?.count ?? 0,
            CinematicRunRecapPlan.commitHighlightLimit
        )
        XCTAssertTrue(
            first.eventSummaries.allSatisfy {
                $0.count <= CinematicRunRecapSharePlan.eventSummaryMaxCharacters
            }
        )
        XCTAssertTrue(
            first.visualDescriptorTokens.allSatisfy {
                $0.count <= CinematicRunRecapSharePlan.visualDescriptorTokenMaxCharacters
            }
        )
    }

    func testGeneratedFlavorAndDescriptorTokensPropagateIntoSharePlan() throws {
        let session = makeSession(
            23,
            commits: [
                SessionCommit(
                    sha: "1234567890abcdef",
                    short: "1234567",
                    subject: "Share generated recap flavor"
                )
            ],
            endedAt: 23_500
        )
        let state = PlanState(
            completed: ["Completed generated share flavor"],
            immediate: nil,
            midTerm: "",
            longTerm: ""
        )
        let commitPlan = CinematicCommitConstellationPlan(sessions: [session])
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
            title: "Generated Share Recap",
            detail: "Compass prepared a bounded generated share recap.",
            titleSource: .generated
        )
        let recapPlan = CinematicRunRecapPlanner.plan(
            state: state,
            sessions: [session],
            isRunning: false,
            isAutoPlaying: false,
            recentRunCues: [:],
            commitConstellationPlan: commitPlan,
            nativeFeedbackLifecycle: CinematicNativeFeedbackCueLifecycle(),
            flavor: flavor
        )
        let focusDescriptor = try XCTUnwrap(
            CinematicRunRecapSceneFocusPlanner.plan(
                isRecapOverlaySelected: true,
                recapPlan: recapPlan,
                commitConstellationPlan: commitPlan,
                timelinePlan: CinematicSessionTimelinePlan(sessions: [session])
            ).descriptor
        )
        let endCardDescriptor = try XCTUnwrap(
            CinematicRunRecapEndCardPlanner.plan(
                isRecapOverlaySelected: true,
                recapPlan: recapPlan
            ).descriptor
        )

        let share = CinematicRunRecapSharePlanner.plan(
            recapPlan: recapPlan,
            recapFocusDescriptor: focusDescriptor,
            endCardDescriptor: endCardDescriptor
        )

        XCTAssertEqual(share.title, "Generated Share Recap")
        XCTAssertTrue(share.text.contains("Title: Generated Share Recap"))
        XCTAssertTrue(share.visualDescriptorTokens.contains("title-source:generated"))
        XCTAssertTrue(share.visualDescriptorTokens.contains("flavor-state:applied"))
        XCTAssertTrue(share.visualDescriptorTokens.contains { $0.hasPrefix("flavor-id:") })
        XCTAssertTrue(share.visualDescriptorTokens.contains { $0.hasPrefix("flavor-source:") })
        XCTAssertTrue(share.visualDescriptorTokens.contains("focus-light:verify"))
        XCTAssertTrue(share.visualDescriptorTokens.contains("focus-effect:victory"))
        XCTAssertTrue(share.visualDescriptorTokens.contains("end-card-glyph:recap.success.seal"))
        XCTAssertTrue(share.visualDescriptorTokens.contains("end-card-route:recap.success"))
    }

    func testSharePlanningPreservesTimelineSelectionFlavorStateAndIdleCycle() throws {
        let session = makeSession(24, endedAt: 24_500)
        let state = PlanState(
            completed: ["Preserve share invariants"],
            immediate: nil,
            midTerm: "",
            longTerm: ""
        )
        let commitPlan = CinematicCommitConstellationPlan(sessions: [session])
        let recapPlan = makeRecapPlan(session: session, state: state)
        let recapBefore = recapPlan
        let baseTimelinePlan = CinematicSessionTimelinePlan(sessions: [session])
        let selectedBeatID = try XCTUnwrap(baseTimelinePlan.beats.first?.stableID)
        let timelineBefore = CinematicSessionTimelinePlan(
            sessions: [session],
            selectedBeatID: selectedBeatID
        )
        let focusPlan = CinematicRunRecapSceneFocusPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: recapPlan,
            commitConstellationPlan: commitPlan,
            timelinePlan: timelineBefore
        )
        let endCardPlan = CinematicRunRecapEndCardPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: recapPlan
        )
        let idleInput = CinematicIdleStoryCyclePlan.SessionInput(
            elapsedTime: 42,
            sessionOrdinal: session.session
        )
        let idleBefore = CinematicIdleStoryCyclePlanner.plan(
            session: idleInput,
            isLiveFollowActive: false,
            hasExplicitUserFocus: false,
            influenceSettings: CinematicInfluenceSettings(),
            commitConstellationPlan: commitPlan,
            timelineSceneFocusPlan: .none,
            nativeFeedbackCue: nil,
            nativeFeedbackPlaqueDescriptor: nil,
            runRecapPlan: recapPlan,
            runRecapSceneFocusPlan: focusPlan,
            runRecapEndCardPlan: endCardPlan
        )

        _ = CinematicRunRecapSharePlanner.plan(
            recapPlan: recapPlan,
            recapFocusDescriptor: focusPlan.descriptor,
            endCardDescriptor: endCardPlan.descriptor
        )

        XCTAssertEqual(recapPlan, recapBefore)
        XCTAssertEqual(
            CinematicSessionTimelinePlan(sessions: [session], selectedBeatID: selectedBeatID),
            timelineBefore
        )
        XCTAssertEqual(
            CinematicIdleStoryCyclePlanner.plan(
                session: idleInput,
                isLiveFollowActive: false,
                hasExplicitUserFocus: false,
                influenceSettings: CinematicInfluenceSettings(),
                commitConstellationPlan: commitPlan,
                timelineSceneFocusPlan: .none,
                nativeFeedbackCue: nil,
                nativeFeedbackPlaqueDescriptor: nil,
                runRecapPlan: recapPlan,
                runRecapSceneFocusPlan: focusPlan,
                runRecapEndCardPlan: endCardPlan
            ),
            idleBefore
        )
    }

    private func makeRecapPlan(
        session: SessionRecord,
        state: PlanState
    ) -> CinematicRunRecapPlan {
        CinematicRunRecapPlanner.plan(
            state: state,
            sessions: [session],
            isRunning: false,
            isAutoPlaying: false,
            recentRunCues: [:],
            commitConstellationPlan: CinematicCommitConstellationPlan(sessions: [session]),
            nativeFeedbackLifecycle: CinematicNativeFeedbackCueLifecycle()
        )
    }

    private func makeSession(
        _ number: Int,
        status: SessionStatus = .succeeded,
        commits: [SessionCommit] = [],
        endedAt: Double? = nil
    ) -> SessionRecord {
        SessionRecord(
            session: number,
            startedAt: Double(number * 1_000),
            endedAt: endedAt,
            plan: "Implement recap share export",
            verify: "swift test --filter CinematicRunRecapSharePlanTests",
            beforeSha: nil,
            afterSha: nil,
            commits: commits,
            status: status,
            notes: [],
            verifyOutput: nil,
            feedback: nil
        )
    }

    private func runCue(
        kind: PlanReliabilityFeedback.Kind,
        severity: PlanReliabilityFeedback.Severity,
        label: String,
        detail: String,
        systemImage: String
    ) -> PlanReliabilityFeedback.RunCue {
        PlanReliabilityFeedback.RunCue(
            notice: PlanReliabilityFeedback.Notice(
                id: "\(kind.rawValue)-share-test",
                kind: kind,
                severity: severity,
                sessionNumber: 0,
                title: label,
                detail: detail,
                actionLabel: label,
                metadata: nil,
                systemImage: systemImage
            )
        )
    }
}
