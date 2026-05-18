import Foundation
@testable import Compass
import XCTest

final class CinematicIdleStoryCyclePlanTests: XCTestCase {
    func testPhaseOrderingRotatesThroughAvailableDescriptors() throws {
        let context = try makeContext()
        let descriptors = try cycleDescriptors(context: context)

        let phases = descriptors.map(\.phase)
        let cycleDuration = descriptors.map(\.cadence).reduce(0, +)

        XCTAssertEqual(phases, CinematicIdleStoryCyclePlan.Descriptor.Phase.allCases)
        XCTAssertEqual(
            plan(context: context, elapsedTime: cycleDuration + 0.01).descriptor?.phase,
            .commitConstellation
        )
    }

    func testPhaseChoreographyTimingIsDistinctAndOrdered() throws {
        let context = try makeContext()
        let descriptors = try cycleDescriptors(context: context)
        let byPhase = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.phase, $0) })
        let commit = try XCTUnwrap(byPhase[.commitConstellation])
        let timeline = try XCTUnwrap(byPhase[.timelineFocus])
        let native = try XCTUnwrap(byPhase[.nativeFeedbackPlaque])
        let diagnostics = try XCTUnwrap(byPhase[.diagnosticsWarningPulse])
        let recapFocus = try XCTUnwrap(byPhase[.runRecapFocus])
        let recapEnd = try XCTUnwrap(byPhase[.runRecapEndCard])
        let artifactTour = try XCTUnwrap(byPhase[.savedRecapArtifactTour])

        XCTAssertGreaterThan(commit.cadence, timeline.cadence)
        XCTAssertGreaterThan(recapEnd.cadence, recapFocus.cadence)
        XCTAssertGreaterThan(recapFocus.cadence, native.cadence)
        XCTAssertLessThan(diagnostics.cadence, commit.cadence)
        XCTAssertEqual(diagnostics.choreography.cameraPressureIdentifier, "diagnostics-warning")
        XCTAssertGreaterThan(artifactTour.cadence, native.cadence)
        XCTAssertEqual(artifactTour.choreography.cameraPressureIdentifier, "archive-tour")
        XCTAssertGreaterThan(recapEnd.choreography.dwellDuration, native.choreography.dwellDuration)
        XCTAssertLessThan(timeline.choreography.transitionDurationScale, commit.choreography.transitionDurationScale)
        XCTAssertLessThan(native.choreography.transitionDurationScale, recapEnd.choreography.transitionDurationScale)
        XCTAssertEqual(Set(descriptors.map(\.choreography.identifier)).count, descriptors.count)
        XCTAssertEqual(Set(descriptors.map(\.choreography.cameraPressureIdentifier)).count, descriptors.count)
    }

    func testIdleOnlyActivationSuppressesLiveFollowAndExplicitUserFocus() throws {
        let context = try makeContext()

        let idle = plan(context: context)
        let liveFollow = plan(context: context, isLiveFollowActive: true)
        let userFocus = plan(context: context, hasExplicitUserFocus: true)
        let empty = CinematicIdleStoryCyclePlanner.plan(
            session: .init(),
            isLiveFollowActive: false,
            hasExplicitUserFocus: false,
            influenceSettings: .init(),
            commitConstellationPlan: .empty,
            timelineSceneFocusPlan: .none,
            nativeFeedbackCue: nil,
            nativeFeedbackPlaqueDescriptor: nil,
            runRecapPlan: .empty(reason: "no-finished-session"),
            runRecapSceneFocusPlan: .none,
            runRecapEndCardPlan: .none
        )

        XCTAssertTrue(idle.isActive)
        XCTAssertFalse(liveFollow.isActive)
        XCTAssertEqual(liveFollow.suppressionReason, "live-follow")
        XCTAssertFalse(userFocus.isActive)
        XCTAssertEqual(userFocus.suppressionReason, "user-focus")
        XCTAssertFalse(empty.isActive)
        XCTAssertEqual(empty.suppressionReason, "no-descriptors")
    }

    func testRecapAvailabilityGatesRecapFocusAndEndCardPhases() throws {
        var context = try makeContext()
        context.recapPlan = .empty(reason: "active-run")
        context.recapFocusPlan = .none
        context.recapEndCardPlan = .none

        let phases = (0..<CinematicIdleStoryCyclePlan.Descriptor.Phase.allCases.count).compactMap {
            plan(context: context, elapsedMultiplier: $0).descriptor?.phase
        }

        XCTAssertFalse(phases.contains(.runRecapFocus))
        XCTAssertFalse(phases.contains(.runRecapEndCard))
        XCTAssertTrue(phases.contains(.commitConstellation))
        XCTAssertTrue(phases.contains(.timelineFocus))
        XCTAssertTrue(phases.contains(.nativeFeedbackPlaque))
    }

    func testCriticalNativeFeedbackPlaqueTakesPriority() throws {
        var context = try makeContext()
        let criticalCue = try makeNativeFeedbackCue(
            milestone: .developRetrying,
            recentRunCues: [
                7: runCue(
                    kind: .failedVerify,
                    severity: .failure,
                    label: "Retry Develop",
                    detail: "swift test exited 65",
                    systemImage: "checkmark.seal.fill"
                )
            ]
        )
        context.nativeFeedbackCue = criticalCue
        context.nativeFeedbackPlaqueDescriptor = try XCTUnwrap(
            nativeFeedbackPlaqueDescriptor(for: criticalCue)
        )

        let selected = plan(context: context, elapsedMultiplier: 0)
        let descriptor = try XCTUnwrap(selected.descriptor)

        XCTAssertEqual(descriptor.phase, .nativeFeedbackPlaque)
        XCTAssertEqual(descriptor.targetKindIdentifier, "native-feedback-failure")
        XCTAssertEqual(descriptor.cameraShot, .failure)
        XCTAssertEqual(descriptor.lightFamily, .failure)
        XCTAssertTrue(descriptor.phaseCopy.contains("Retry"))
        XCTAssertNotEqual(descriptor.phase, .diagnosticsWarningPulse)
    }

    func testQuietModeSuppressesOnlyNonCriticalNativeFeedbackPlaques() throws {
        var context = try makeContext(
            settings: CinematicInfluenceSettings(cameraStyle: .follow, comfortMode: .quiet)
        )
        context.diagnosticsWarningBundleHistory = CinematicDiagnosticsWarningBundleHistory()

        let nativeSlot = plan(context: context, elapsedMultiplier: 2)
        XCTAssertNotEqual(nativeSlot.descriptor?.phase, .nativeFeedbackPlaque)
        XCTAssertTrue(nativeSlot.isActive)

        context.commitConstellationPlan = .empty
        context.timelineFocusPlan = .none
        context.recapPlan = .empty(reason: "no-finished-session")
        context.recapFocusPlan = .none
        context.recapEndCardPlan = .none
        context.tourPlan = nil
        let suppressedNativeOnly = plan(context: context, elapsedMultiplier: 2)
        XCTAssertFalse(suppressedNativeOnly.isActive)
        XCTAssertEqual(suppressedNativeOnly.suppressionReason, "quiet-noncritical-native-feedback")

        let criticalCue = try makeNativeFeedbackCue(
            milestone: .postChecksFailed,
            recentRunCues: [:]
        )
        context.nativeFeedbackCue = criticalCue
        context.nativeFeedbackPlaqueDescriptor = try XCTUnwrap(
            nativeFeedbackPlaqueDescriptor(
                for: criticalCue,
                settings: CinematicInfluenceSettings(cameraStyle: .follow, comfortMode: .quiet)
            )
        )
        let critical = plan(context: context, elapsedMultiplier: 0)
        XCTAssertEqual(critical.descriptor?.phase, .nativeFeedbackPlaque)
        XCTAssertEqual(critical.suppressionReason, "none")
    }

    func testDiagnosticsWarningPulseRequiresCurrentBundle() throws {
        var context = try makeContext(diagnosticsWarningBundleHistory: CinematicDiagnosticsWarningBundleHistory())
        context.commitConstellationPlan = .empty
        context.timelineFocusPlan = .none
        context.nativeFeedbackCue = nil
        context.nativeFeedbackPlaqueDescriptor = nil
        context.recapPlan = .empty(reason: "no-finished-session")
        context.recapFocusPlan = .none
        context.recapEndCardPlan = .none
        context.tourPlan = nil

        let noHistory = plan(context: context)
        XCTAssertFalse(noHistory.isActive)
        XCTAssertEqual(noHistory.suppressionReason, "no-descriptors")

        var staleHistory = makeDiagnosticsWarningBundleHistory()
        staleHistory.record(CinematicDiagnosticsSummary.AttentionSummary(targets: []))
        context.diagnosticsWarningBundleHistory = staleHistory
        let stale = plan(context: context)
        XCTAssertFalse(stale.isActive)
        XCTAssertEqual(stale.suppressionReason, "no-descriptors")

        context.diagnosticsWarningBundleHistory = makeDiagnosticsWarningBundleHistory()
        let active = plan(context: context)
        let descriptor = try XCTUnwrap(active.descriptor)
        let warningDescriptor = try XCTUnwrap(descriptor.diagnosticsWarningPulseDescriptor)

        XCTAssertEqual(descriptor.phase, .diagnosticsWarningPulse)
        XCTAssertEqual(descriptor.lightFamily, .pressure)
        XCTAssertEqual(descriptor.arenaEffect, .activityPulse)
        XCTAssertEqual(descriptor.targetKindIdentifier, "diagnostics-warning-\(warningDescriptor.bundleIdentifier)")
        XCTAssertEqual(warningDescriptor.warningIdentifiers, ["visual-smoke.idle-story-cycle"])
    }

    func testDiagnosticsWarningPulseCarriesBoundedDuplicateMetadataWithoutBodyText() throws {
        let secret = "SECRET_NATIVE_NOTIFICATION_BODY_SHOULD_NOT_LEAK"
        var history = makeDiagnosticsWarningBundleHistory(
            warnings: ["visual-smoke.shared-warning", "visual-smoke.shared-warning"],
            detail: "body \(secret)",
            copyText: "copy \(secret)"
        )
        history.record(
            diagnosticsWarningAttentionSummary(
                "idle-warning",
                warnings: ["visual-smoke.shared-warning", "visual-smoke.shared-warning"],
                detail: "body \(secret)",
                copyText: "copy \(secret)"
            )
        )
        var context = try makeContext(diagnosticsWarningBundleHistory: history)
        context.commitConstellationPlan = .empty
        context.timelineFocusPlan = .none
        context.nativeFeedbackCue = nil
        context.nativeFeedbackPlaqueDescriptor = nil
        context.recapPlan = .empty(reason: "no-finished-session")
        context.recapFocusPlan = .none
        context.recapEndCardPlan = .none
        context.tourPlan = nil

        let descriptor = try XCTUnwrap(plan(context: context).descriptor)
        let warningDescriptor = try XCTUnwrap(descriptor.diagnosticsWarningPulseDescriptor)

        XCTAssertEqual(warningDescriptor.captureCount, 2)
        XCTAssertEqual(warningDescriptor.warningCount, 2)
        XCTAssertEqual(warningDescriptor.warningIdentifiers, ["visual-smoke.shared-warning"])
        XCTAssertEqual(warningDescriptor.repeatedWarningIdentifiers, ["visual-smoke.shared-warning"])
        XCTAssertEqual(warningDescriptor.targetAnchors, ["visual-smoke-check-idle-warning"])
        XCTAssertEqual(warningDescriptor.relatedRowAnchors, ["diagnostics-row-idle-story-cycle"])
        XCTAssertFalse(descriptor.identifier.contains(secret))
        XCTAssertFalse(descriptor.phaseCopy.contains(secret))
        XCTAssertLessThanOrEqual(
            warningDescriptor.warningIdentifiers.first?.count ?? 0,
            CinematicDiagnosticsWarningBundleHistory.identifierMaxCharacters
        )
    }

    func testDiagnosticsWarningPulseUsesComfortDampingWithoutQuietSuppression() throws {
        var standardContext = try makeContext(
            settings: CinematicInfluenceSettings(cameraStyle: .dramatic, comfortMode: .standard, intensity: 1)
        )
        var reducedContext = try makeContext(
            settings: CinematicInfluenceSettings(cameraStyle: .dramatic, comfortMode: .reducedMotion, intensity: 1)
        )
        var quietContext = try makeContext(
            settings: CinematicInfluenceSettings(cameraStyle: .dramatic, comfortMode: .quiet, intensity: 1)
        )

        prepareDiagnosticsWarningOnlyContext(&standardContext)
        prepareDiagnosticsWarningOnlyContext(&reducedContext)
        prepareDiagnosticsWarningOnlyContext(&quietContext)

        let standard = try XCTUnwrap(plan(context: standardContext).descriptor)
        let reduced = try XCTUnwrap(plan(context: reducedContext).descriptor)
        let quiet = try XCTUnwrap(plan(context: quietContext).descriptor)

        XCTAssertEqual(standard.phase, .diagnosticsWarningPulse)
        XCTAssertEqual(reduced.phase, .diagnosticsWarningPulse)
        XCTAssertEqual(quiet.phase, .diagnosticsWarningPulse)
        XCTAssertLessThan(reduced.choreography.comfortDamping, standard.choreography.comfortDamping)
        XCTAssertLessThan(quiet.choreography.comfortDamping, reduced.choreography.comfortDamping)
        XCTAssertGreaterThan(reduced.choreography.transitionDurationScale, standard.choreography.transitionDurationScale)
        XCTAssertGreaterThan(quiet.choreography.transitionDurationScale, reduced.choreography.transitionDurationScale)
        XCTAssertLessThan(
            try XCTUnwrap(quiet.choreography.pulseHint).orbBoost,
            try XCTUnwrap(reduced.choreography.pulseHint).orbBoost
        )
    }

    func testIdentifiersAreStableBoundedAndReflectSelectedPhase() throws {
        let context = try makeContext()
        let first = plan(context: context, elapsedMultiplier: 1)
        let repeated = plan(context: context, elapsedMultiplier: 1)
        let changed = plan(context: context, elapsedMultiplier: 2)
        let descriptor = try XCTUnwrap(first.descriptor)

        XCTAssertEqual(first, repeated)
        XCTAssertEqual(first.identifier, repeated.identifier)
        XCTAssertNotEqual(first.identifier, changed.identifier)
        XCTAssertLessThanOrEqual(first.identifier.count, CinematicIdleStoryCyclePlan.identifierMaxCharacters)
        XCTAssertLessThanOrEqual(descriptor.identifier.count, CinematicIdleStoryCyclePlan.identifierMaxCharacters)
        XCTAssertLessThanOrEqual(
            descriptor.sourceDescriptorIdentifier.count,
            CinematicIdleStoryCyclePlan.sourceDescriptorMaxCharacters
        )
        XCTAssertLessThanOrEqual(descriptor.phaseCopy.count, CinematicIdleStoryCyclePlan.phaseCopyMaxCharacters)
        XCTAssertInRange(descriptor.cadence, CinematicIdleStoryCyclePlan.cadenceRange)
        XCTAssertLessThanOrEqual(
            descriptor.choreography.identifier.count,
            CinematicIdleStoryCyclePlan.choreographyIdentifierMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            descriptor.choreography.cameraTreatmentIdentifier.count,
            CinematicIdleStoryCyclePlan.choreographyTreatmentIdentifierMaxCharacters
        )
        XCTAssertInRange(descriptor.choreography.phaseCadence, CinematicIdleStoryCyclePlan.cadenceRange)
        XCTAssertInRange(descriptor.choreography.dwellDuration, CinematicIdleStoryCyclePlan.dwellDurationRange)
        XCTAssertInRange(
            descriptor.choreography.transitionDurationScale,
            CinematicIdleStoryCyclePlan.transitionDurationScaleRange
        )
        XCTAssertInRange(descriptor.choreography.targetBias, CinematicIdleStoryCyclePlan.targetBiasRange)
        XCTAssertInRange(descriptor.choreography.comfortDamping, CinematicIdleStoryCyclePlan.comfortDampingRange)
        if let pulseHint = descriptor.choreography.pulseHint {
            XCTAssertLessThanOrEqual(
                pulseHint.identifier.count,
                CinematicIdleStoryCyclePlan.choreographyHintIdentifierMaxCharacters
            )
            XCTAssertInRange(
                pulseHint.intensityScale,
                CinematicIdleStoryCyclePlan.pulseIntensityScaleRange
            )
            XCTAssertInRange(pulseHint.orbBoost, CinematicIdleStoryCyclePlan.pulseOrbBoostRange)
        }
    }

    func testComfortModeDampsChoreographyWithoutSuppressingIdleRoutes() throws {
        let standardContext = try makeContext(
            settings: CinematicInfluenceSettings(cameraStyle: .dramatic, comfortMode: .standard, intensity: 1)
        )
        let reducedContext = try makeContext(
            settings: CinematicInfluenceSettings(cameraStyle: .dramatic, comfortMode: .reducedMotion, intensity: 1)
        )
        let quietContext = try makeContext(
            settings: CinematicInfluenceSettings(cameraStyle: .dramatic, comfortMode: .quiet, intensity: 1)
        )
        let standard = try descriptor(
            for: .commitConstellation,
            in: standardContext
        ).choreography
        let reduced = try descriptor(
            for: .commitConstellation,
            in: reducedContext
        ).choreography
        let quiet = try descriptor(
            for: .commitConstellation,
            in: quietContext
        ).choreography

        XCTAssertLessThan(reduced.comfortDamping, standard.comfortDamping)
        XCTAssertLessThan(quiet.comfortDamping, reduced.comfortDamping)
        XCTAssertGreaterThan(reduced.transitionDurationScale, standard.transitionDurationScale)
        XCTAssertGreaterThan(quiet.transitionDurationScale, reduced.transitionDurationScale)
        XCTAssertLessThan(reduced.targetBias, standard.targetBias)
        XCTAssertLessThan(quiet.targetBias, reduced.targetBias)
        XCTAssertLessThan(
            try XCTUnwrap(quiet.pulseHint).orbBoost,
            try XCTUnwrap(reduced.pulseHint).orbBoost
        )
    }

    func testPlanningDoesNotMutateTimelineSelectionOrRecapPlanning() throws {
        let context = try makeContext(selectedBeatID: "session-42-plan")
        let timelineBefore = context.timelinePlan
        let timelineFocusBefore = context.timelineFocusPlan
        let recapBefore = context.recapPlan
        let recapFocusBefore = context.recapFocusPlan
        let recapEndCardBefore = context.recapEndCardPlan
        let tourBefore = context.tourPlan

        _ = plan(context: context, elapsedMultiplier: 4)

        XCTAssertEqual(context.timelinePlan, timelineBefore)
        XCTAssertEqual(context.timelinePlan.selectedBeatID, "session-42-plan")
        XCTAssertEqual(context.timelineFocusPlan, timelineFocusBefore)
        XCTAssertEqual(context.recapPlan, recapBefore)
        XCTAssertEqual(context.recapFocusPlan, recapFocusBefore)
        XCTAssertEqual(context.recapEndCardPlan, recapEndCardBefore)
        XCTAssertEqual(context.tourPlan, tourBefore)
    }

    func testSavedRecapArtifactTourCandidateCarriesArtifactContext() throws {
        var context = try makeContext()
        let history = makePinnedComparisonHistory()
        let pinned = try XCTUnwrap(history.entries.first { $0.sessionNumber == 40 })
        let libraryContext = CinematicRunRecapShareArtifactLibraryContext(
            selectedEntryIdentifier: history.entries.first?.identifier,
            searchText: "idle pinned comparison body",
            pinnedEntryIdentifiers: [pinned.identifier, "stale-idle-tour-pin"]
        )
        context.tourPlan = CinematicRunRecapShareArtifactTourPlanner.plan(
            historyPlan: history,
            libraryContext: libraryContext
        )

        let descriptor = try descriptor(for: .savedRecapArtifactTour, in: context)
        let tourPlan = try XCTUnwrap(descriptor.runRecapShareArtifactTourPlan)

        XCTAssertEqual(descriptor.phase, .savedRecapArtifactTour)
        XCTAssertEqual(descriptor.targetKindIdentifier, "saved-recap-artifact-pinned")
        XCTAssertEqual(descriptor.cameraShot, .overShoulder)
        XCTAssertEqual(descriptor.lightFamily, .git)
        XCTAssertEqual(descriptor.arenaEffect, .historyChains)
        XCTAssertEqual(tourPlan.selectedEntryIdentifier, pinned.identifier)
        XCTAssertEqual(tourPlan.retainedPinnedEntryIdentifiers, [pinned.identifier])
        XCTAssertEqual(tourPlan.missingPinnedEntryIdentifiers, ["stale-idle-tour-pin"])
        XCTAssertEqual(libraryContext.pinnedEntryIdentifiers, [pinned.identifier, "stale-idle-tour-pin"])
        XCTAssertEqual(libraryContext.searchText, "idle pinned comparison body")
    }

    func testRunRecapEndCardCandidateCarriesPinnedComparisonCue() throws {
        var context = try makeContext()
        let history = makePinnedComparisonHistory()
        let selected = try XCTUnwrap(history.entries.first { $0.sessionNumber == 42 })
        let target = try XCTUnwrap(history.entries.first { $0.sessionNumber == 40 })
        let comparison = CinematicRunRecapShareArtifactComparisonPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: selected.identifier,
            targetMode: .pinnedReference,
            pinnedEntryIdentifiers: [target.identifier]
        )
        context.recapEndCardPlan = CinematicRunRecapEndCardPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: context.recapPlan,
            artifactComparisonPlan: comparison
        )

        let descriptor = try descriptor(for: .runRecapEndCard, in: context)
        let endCardPlan = try XCTUnwrap(descriptor.runRecapEndCardPlan)
        let endCardDescriptor = try XCTUnwrap(endCardPlan.descriptor)
        let cue = try XCTUnwrap(endCardDescriptor.pinnedComparisonCue)

        XCTAssertEqual(descriptor.phase, .runRecapEndCard)
        XCTAssertTrue(
            descriptor.sourceDescriptorIdentifier.hasPrefix(
                String(endCardDescriptor.identifier.prefix(64))
            )
        )
        XCTAssertEqual(cue.modeIdentifier, "pinned_reference")
        XCTAssertEqual(cue.stateIdentifier, "visible-pinned-target")
        XCTAssertEqual(cue.selectedSessionNumber, 42)
        XCTAssertEqual(cue.targetSessionNumber, 40)
        XCTAssertEqual(cue.railTreatmentIdentifier, "pin-bridge-rail")
    }

    private struct Context {
        var settings: CinematicInfluenceSettings
        var session: SessionRecord
        var commitConstellationPlan: CinematicCommitConstellationPlan
        var timelinePlan: CinematicSessionTimelinePlan
        var timelineFocusPlan: CinematicTimelineSceneFocusPlan
        var nativeFeedbackCue: CinematicNativeFeedbackCuePlan?
        var nativeFeedbackPlaqueDescriptor: CinematicIdleStoryCyclePlan.NativeFeedbackPlaqueDescriptor?
        var diagnosticsWarningBundleHistory: CinematicDiagnosticsWarningBundleHistory
        var recapPlan: CinematicRunRecapPlan
        var recapFocusPlan: CinematicRunRecapSceneFocusPlan
        var recapEndCardPlan: CinematicRunRecapEndCardPlan
        var tourPlan: CinematicRunRecapShareArtifactTourPlan?
    }

    private func makeContext(
        selectedBeatID: String? = nil,
        settings: CinematicInfluenceSettings = CinematicInfluenceSettings(),
        diagnosticsWarningBundleHistory: CinematicDiagnosticsWarningBundleHistory? = nil
    ) throws -> Context {
        let session = makeSession(
            42,
            status: .succeeded,
            commits: [
                SessionCommit(
                    sha: "1234567890abcdef",
                    short: "1234567",
                    subject: "Add idle story cycle"
                )
            ],
            endedAt: 42_500
        )
        let commitConstellationPlan = CinematicCommitConstellationPlan(sessions: [session])
        let timelinePlan = CinematicSessionTimelinePlan(
            sessions: [session],
            selectedBeatID: selectedBeatID
        )
        let timelineFocusPlan = CinematicTimelineSceneFocusPlanner.plan(
            selectedBeat: timelinePlan.selectedBeat,
            commitConstellationPlan: commitConstellationPlan,
            recoveryCuePlan: .none
        )
        let nativeCue = try makeNativeFeedbackCue(milestone: .verifyStarted, recentRunCues: [:])
        let recapPlan = CinematicRunRecapPlanner.plan(
            state: recapState(),
            sessions: [session],
            isRunning: false,
            isAutoPlaying: false,
            recentRunCues: [:],
            commitConstellationPlan: commitConstellationPlan,
            nativeFeedbackLifecycle: CinematicNativeFeedbackCueLifecycle()
        )
        let recapFocusPlan = CinematicRunRecapSceneFocusPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: recapPlan,
            commitConstellationPlan: commitConstellationPlan,
            timelinePlan: timelinePlan
        )
        let recapEndCardPlan = CinematicRunRecapEndCardPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: recapPlan
        )
        let tourHistoryPlan = makePinnedComparisonHistory()
        let tourPlan = CinematicRunRecapShareArtifactTourPlanner.plan(
            historyPlan: tourHistoryPlan,
            libraryContext: .empty
        )

        return Context(
            settings: settings,
            session: session,
            commitConstellationPlan: commitConstellationPlan,
            timelinePlan: timelinePlan,
            timelineFocusPlan: timelineFocusPlan,
            nativeFeedbackCue: nativeCue,
            nativeFeedbackPlaqueDescriptor: try XCTUnwrap(
                nativeFeedbackPlaqueDescriptor(for: nativeCue, settings: settings)
            ),
            diagnosticsWarningBundleHistory: diagnosticsWarningBundleHistory ?? makeDiagnosticsWarningBundleHistory(),
            recapPlan: recapPlan,
            recapFocusPlan: recapFocusPlan,
            recapEndCardPlan: recapEndCardPlan,
            tourPlan: tourPlan
        )
    }

    private func plan(
        context: Context,
        elapsedMultiplier: Int = 0,
        elapsedTime: TimeInterval? = nil,
        isLiveFollowActive: Bool = false,
        hasExplicitUserFocus: Bool = false
    ) -> CinematicIdleStoryCyclePlan {
        CinematicIdleStoryCyclePlanner.plan(
            session: .init(
                elapsedTime: elapsedTime
                    ?? Double(elapsedMultiplier) * CinematicIdleStoryCyclePlan.defaultCadence,
                sessionOrdinal: 0
            ),
            isLiveFollowActive: isLiveFollowActive,
            hasExplicitUserFocus: hasExplicitUserFocus,
            influenceSettings: context.settings,
            commitConstellationPlan: context.commitConstellationPlan,
            timelineSceneFocusPlan: context.timelineFocusPlan,
            nativeFeedbackCue: context.nativeFeedbackCue,
            nativeFeedbackPlaqueDescriptor: context.nativeFeedbackPlaqueDescriptor,
            diagnosticsWarningBundleHistory: context.diagnosticsWarningBundleHistory,
            runRecapPlan: context.recapPlan,
            runRecapSceneFocusPlan: context.recapFocusPlan,
            runRecapEndCardPlan: context.recapEndCardPlan,
            runRecapShareArtifactTourPlan: context.tourPlan
        )
    }

    private func cycleDescriptors(
        context: Context
    ) throws -> [CinematicIdleStoryCyclePlan.Descriptor] {
        var elapsed: TimeInterval = 0
        var descriptors: [CinematicIdleStoryCyclePlan.Descriptor] = []
        for _ in CinematicIdleStoryCyclePlan.Descriptor.Phase.allCases {
            let descriptor = try XCTUnwrap(plan(context: context, elapsedTime: elapsed).descriptor)
            descriptors.append(descriptor)
            elapsed += descriptor.cadence + 0.01
        }
        return descriptors
    }

    private func descriptor(
        for phase: CinematicIdleStoryCyclePlan.Descriptor.Phase,
        in context: Context
    ) throws -> CinematicIdleStoryCyclePlan.Descriptor {
        try XCTUnwrap(cycleDescriptors(context: context).first { $0.phase == phase })
    }

    private func nativeFeedbackPlaqueDescriptor(
        for cue: CinematicNativeFeedbackCuePlan,
        settings: CinematicInfluenceSettings = CinematicInfluenceSettings()
    ) -> CinematicIdleStoryCyclePlan.NativeFeedbackPlaqueDescriptor? {
        CinematicIdleStoryCyclePlanner.nativeFeedbackPlaqueDescriptor(
            phase: cue.phase,
            languageProfile: languageProfile(primaryLanguage: .swift),
            activityProfile: activityProfile(recentCommitCount: 1),
            influenceSettings: settings,
            worldText: .placeholder,
            briefing: .placeholder,
            recoveryCuePlan: .none,
            nativeFeedbackCue: cue
        )
    }

    private func prepareDiagnosticsWarningOnlyContext(_ context: inout Context) {
        context.commitConstellationPlan = .empty
        context.timelineFocusPlan = .none
        context.nativeFeedbackCue = nil
        context.nativeFeedbackPlaqueDescriptor = nil
        context.recapPlan = .empty(reason: "no-finished-session")
        context.recapFocusPlan = .none
        context.recapEndCardPlan = .none
        context.tourPlan = nil
    }

    private func makeDiagnosticsWarningBundleHistory(
        warnings: [String] = ["visual-smoke.idle-story-cycle"],
        detail: String = "diagnostics warning",
        copyText: String = "diagnostics warning copy"
    ) -> CinematicDiagnosticsWarningBundleHistory {
        var history = CinematicDiagnosticsWarningBundleHistory()
        history.record(
            diagnosticsWarningAttentionSummary(
                "idle-warning",
                warnings: warnings,
                detail: detail,
                copyText: copyText
            )
        )
        return history
    }

    private func diagnosticsWarningAttentionSummary(
        _ suffix: String,
        warnings: [String],
        detail: String,
        copyText: String
    ) -> CinematicDiagnosticsSummary.AttentionSummary {
        CinematicDiagnosticsSummary.AttentionSummary(
            targets: [
                CinematicDiagnosticsSummary.AttentionTarget(
                    id: "target-\(suffix)",
                    targetGroupID: "visual-smoke",
                    targetAnchorID: "visual-smoke-check-\(suffix)",
                    relatedGroupID: "repository-context",
                    relatedRowID: "idle-story-cycle",
                    label: "Warning \(suffix)",
                    detail: detail,
                    warningCount: warnings.count,
                    visibleWarningIdentifiers: warnings,
                    copyText: copyText
                )
            ]
        )
    }

    private func makeNativeFeedbackCue(
        milestone: NativeFeedbackMilestone,
        recentRunCues: [Int: PlanReliabilityFeedback.RunCue]
    ) throws -> CinematicNativeFeedbackCuePlan {
        try XCTUnwrap(
            CinematicNativeFeedbackCuePlanner.plan(
                milestone: milestone,
                content: NativeFeedbackContent(milestone: milestone, projectName: "Idle Story"),
                phase: milestone == .postChecksFailed ? .failed : .verifying,
                feedbackMode: .notifications,
                recentRunCues: recentRunCues
            )
        )
    }

    private func recapState() -> PlanState {
        PlanState(
            completed: ["Completed idle story cycle"],
            immediate: nil,
            midTerm: "",
            longTerm: ""
        )
    }

    private func makeSession(
        _ number: Int,
        status: SessionStatus,
        commits: [SessionCommit],
        endedAt: Double?
    ) -> SessionRecord {
        SessionRecord(
            session: number,
            startedAt: Double(number * 1_000),
            endedAt: endedAt,
            plan: "Stage idle story cycle",
            verify: "swift test --filter CinematicIdleStoryCyclePlanTests",
            beforeSha: nil,
            afterSha: nil,
            commits: commits,
            status: status,
            notes: [],
            verifyOutput: nil,
            feedback: nil
        )
    }

    private func makePinnedComparisonHistory() -> CinematicRunRecapShareArtifactHistoryPlan {
        let entries = [42, 41, 40].map { session in
            let filename = "\(session)-idle-pinned-comparison.md"
            let markdown = """
            # Compass Run Recap Share

            - Artifact: idle-pinned-\(session)
            - Availability: available
            - Session: \(session)
            - Filename: \(filename)
            - Share: share-id
            - Recap: recap-id
            - Focus: focus-id
            - End card: end-card-id
            - Title: Idle pinned \(session)
            - Status: succeeded
            - Detail: Idle pinned comparison detail
            - Commit: Idle pinned commit \(session)

            ## Events
            - event

            ## Share Text

            ```text
            Idle pinned comparison body \(session)
            ```
            """
            return CinematicRunRecapShareArtifactHistoryPlan.Entry(
                identifier: "idle-pinned-entry-\(session)",
                sessionNumber: session,
                filename: filename,
                url: URL(fileURLWithPath: "/tmp/\(filename)"),
                pathDisplayText: "/tmp/\(filename)",
                titleSnippet: "Idle pinned \(session)",
                statusSnippet: "succeeded",
                commitSnippet: "Idle pinned commit \(session)",
                markdownContents: markdown,
                markdownLength: markdown.count
            )
        }
        return CinematicRunRecapShareArtifactHistoryPlan(
            identifier: "idle-pinned-history",
            isAvailable: true,
            availabilityReason: "available",
            storageRootDisplayText: "/tmp/idle-pinned",
            sessionsDisplayText: "/tmp/idle-pinned/sessions",
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
            exportIdentifier: "idle-pinned-history-export",
            combinedMarkdownExport: entries.map(\.markdownContents).joined(separator: "\n\n")
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
                id: "\(kind.rawValue)-idle-story-test",
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

private func languageProfile(primaryLanguage: RepositoryLanguage) -> RepositoryLanguageProfile {
    var counts = RepositoryLanguageCounts()
    counts[primaryLanguage] = primaryLanguage == .unknown ? 0 : 4
    return RepositoryLanguageProfile(
        counts: counts,
        manifestHints: [],
        primaryLanguage: primaryLanguage,
        scannedFileCount: primaryLanguage == .unknown ? 0 : 4,
        scannedDirectoryCount: primaryLanguage == .unknown ? 0 : 1,
        wasTruncated: false
    )
}

private func activityProfile(
    recentCommitCount: Int = 0
) -> RepositoryActivityProfile {
    RepositoryActivityProfile(
        isAvailable: true,
        worktreeChanges: RepositoryWorktreeChangeCounts(),
        recentSessionCount: 1,
        recentSucceededCount: 0,
        recentFailedCount: 0,
        recentCommitCount: recentCommitCount,
        lastTerminalStatus: nil,
        lastSuccessfulSession: nil,
        lastFailedSession: nil,
        successStreak: 0,
        failureStreak: 0,
        recoveredFromFailure: false
    )
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
