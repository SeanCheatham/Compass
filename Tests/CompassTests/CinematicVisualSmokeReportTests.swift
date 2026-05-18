import Foundation
@testable import Compass
import XCTest

final class CinematicVisualSmokeReportTests: XCTestCase {
    func testRepresentativeReportIsDeterministicAndPasses() {
        let first = CinematicVisualSmokeReport.representative()
        let repeated = CinematicVisualSmokeReport.representative()

        XCTAssertEqual(first, repeated)
        XCTAssertEqual(first.status, .pass)
        XCTAssertEqual(first.warningIdentifiers, [])
        XCTAssertEqual(
            first.checks.map(\.id),
            [
                "run-recap-artifact-command-availability",
                "narrative-cue-readability",
                "overlay-fallback-usage",
                "chrome-strength",
                "text-bounds",
                "asset-availability",
                "texture-role-coverage",
                "language-layout-coverage",
                "activity-material-treatment",
                "camera-phase-coverage",
                "pressure-influence-spread",
                "recovery-cue-coverage",
                "native-feedback-cue-coverage",
                "native-feedback-treatment-coverage",
                "idle-story-cycle-coverage",
                "run-recap-saved-artifact-tour",
                "timeline-focus-coverage",
                "run-recap-focus-coverage",
                "run-recap-end-card-coverage",
                "run-recap-pinned-comparison-cue"
            ]
        )
        XCTAssertTrue(first.checks.allSatisfy { $0.status == .pass })
    }

    func testRepresentativeReportCoversExpectedVisualPaths() throws {
        let smoke = CinematicVisualSmokeReport.representative()
        let recapCommands = try XCTUnwrap(
            smoke.checks.first { $0.id == "run-recap-artifact-command-availability" }
        )
        let overlay = try XCTUnwrap(smoke.checks.first { $0.id == "overlay-fallback-usage" })
        let chrome = try XCTUnwrap(smoke.checks.first { $0.id == "chrome-strength" })
        let assets = try XCTUnwrap(smoke.checks.first { $0.id == "asset-availability" })
        let textureRoles = try XCTUnwrap(smoke.checks.first { $0.id == "texture-role-coverage" })
        let languageLayouts = try XCTUnwrap(smoke.checks.first { $0.id == "language-layout-coverage" })
        let materialTreatments = try XCTUnwrap(smoke.checks.first { $0.id == "activity-material-treatment" })
        let pressure = try XCTUnwrap(smoke.checks.first { $0.id == "pressure-influence-spread" })
        let recoveryCue = try XCTUnwrap(smoke.checks.first { $0.id == "recovery-cue-coverage" })
        let nativeFeedback = try XCTUnwrap(smoke.checks.first { $0.id == "native-feedback-cue-coverage" })
        let nativeFeedbackTreatment = try XCTUnwrap(
            smoke.checks.first { $0.id == "native-feedback-treatment-coverage" }
        )
        let idleStoryCycle = try XCTUnwrap(smoke.checks.first { $0.id == "idle-story-cycle-coverage" })
        let savedArtifactTour = try XCTUnwrap(smoke.checks.first { $0.id == "run-recap-saved-artifact-tour" })
        let timelineFocus = try XCTUnwrap(smoke.checks.first { $0.id == "timeline-focus-coverage" })
        let runRecapFocus = try XCTUnwrap(smoke.checks.first { $0.id == "run-recap-focus-coverage" })
        let runRecapEndCard = try XCTUnwrap(smoke.checks.first { $0.id == "run-recap-end-card-coverage" })
        let pinnedComparisonCue = try XCTUnwrap(
            smoke.checks.first { $0.id == "run-recap-pinned-comparison-cue" }
        )

        XCTAssertEqual(recapCommands.status, .pass)
        XCTAssertTrue(recapCommands.detail.contains("available"))
        XCTAssertTrue(recapCommands.detail.contains("unavailable"))
        XCTAssertTrue(recapCommands.detail.contains("no-match"))
        XCTAssertTrue(recapCommands.detail.contains("stale-pin"))
        XCTAssertTrue(recapCommands.detail.contains("filtered-hold"))
        XCTAssertTrue(recapCommands.detail.contains("promoted-hold"))
        XCTAssertTrue(recapCommands.detail.contains("cleanup-omitted"))
        XCTAssertTrue(recapCommands.detail.contains("collisions clear"))
        XCTAssertTrue(recapCommands.detail.contains("bounded"))
        XCTAssertEqual(overlay.status, .pass)
        XCTAssertTrue(overlay.detail.contains("compact"))
        XCTAssertTrue(overlay.detail.contains("full"))
        XCTAssertTrue(overlay.detail.contains("fallback"))
        XCTAssertTrue(overlay.detail.contains("missing-repository"))
        XCTAssertTrue(chrome.detail.contains("compact-active"))
        XCTAssertTrue(chrome.detail.contains("full-readable"))
        XCTAssertTrue(chrome.detail.contains("fallback-readable"))
        XCTAssertTrue(assets.detail.contains("gen backdrops 8/8"))
        XCTAssertTrue(assets.detail.contains("gen arenas 8/8"))
        XCTAssertTrue(assets.detail.contains("packaged backdrops 8/8"))
        XCTAssertTrue(assets.detail.contains("packaged arenas 8/8"))
        XCTAssertTrue(textureRoles.detail.contains("backdrop 8/8"))
        XCTAssertTrue(textureRoles.detail.contains("gen backdrop 8/8"))
        XCTAssertTrue(textureRoles.detail.contains("arena 8/8"))
        XCTAssertTrue(textureRoles.detail.contains("gen arena 8/8"))
        XCTAssertTrue(textureRoles.detail.contains("direct"))
        XCTAssertTrue(languageLayouts.detail.contains("pedestals 8/8"))
        XCTAssertTrue(languageLayouts.detail.contains("shards 8/8"))
        XCTAssertTrue(languageLayouts.detail.contains("bounds"))
        XCTAssertTrue(materialTreatments.detail.contains("materials 5/5"))
        XCTAssertTrue(materialTreatments.detail.contains("treatments 5/5"))
        XCTAssertTrue(materialTreatments.detail.contains("bounds"))
        XCTAssertTrue(pressure.detail.contains("clean"))
        XCTAssertTrue(pressure.detail.contains("heavy"))
        XCTAssertTrue(pressure.detail.contains("steady"))
        XCTAssertTrue(pressure.detail.contains("dramatic"))
        XCTAssertTrue(recoveryCue.detail.contains("failedVerify"))
        XCTAssertTrue(recoveryCue.detail.contains("dirtyWorktree"))
        XCTAssertTrue(recoveryCue.detail.contains("promotionFailed"))
        XCTAssertTrue(recoveryCue.detail.contains("history-chains"))
        XCTAssertTrue(nativeFeedback.detail.contains("active 4"))
        XCTAssertTrue(nativeFeedback.detail.contains("styles 3/3"))
        XCTAssertTrue(nativeFeedback.detail.contains("sources native,run-cue"))
        XCTAssertTrue(nativeFeedback.detail.contains("desc 3/3"))
        XCTAssertTrue(nativeFeedback.detail.contains("routes fracture,seal,warning"))
        XCTAssertTrue(nativeFeedback.detail.contains("visible 4/4"))
        XCTAssertTrue(nativeFeedback.detail.contains("life 4/4"))
        XCTAssertTrue(nativeFeedback.detail.contains("expired 1"))
        XCTAssertEqual(nativeFeedbackTreatment.status, .pass)
        XCTAssertTrue(nativeFeedbackTreatment.detail.contains("active 4"))
        XCTAssertTrue(nativeFeedbackTreatment.detail.contains("accents 4/4"))
        XCTAssertTrue(nativeFeedbackTreatment.detail.contains("routes 4/4"))
        XCTAssertTrue(nativeFeedbackTreatment.detail.contains("pairs 4/4"))
        XCTAssertTrue(nativeFeedbackTreatment.detail.contains("surfaces 4/4"))
        XCTAssertTrue(nativeFeedbackTreatment.detail.contains("params 4/4"))
        XCTAssertTrue(nativeFeedbackTreatment.detail.contains("prims 4/4"))
        XCTAssertEqual(idleStoryCycle.status, .pass)
        XCTAssertTrue(idleStoryCycle.detail.contains("commit-constellation"))
        XCTAssertTrue(idleStoryCycle.detail.contains("timeline-focus"))
        XCTAssertTrue(idleStoryCycle.detail.contains("native-feedback-plaque"))
        XCTAssertTrue(idleStoryCycle.detail.contains("diagnostics-warning-pulse"))
        let idlePhaseCount = CinematicIdleStoryCyclePlan.Descriptor.Phase.allCases.count
        XCTAssertTrue(idleStoryCycle.detail.contains("phases \(idlePhaseCount)/\(idlePhaseCount)"))
        XCTAssertTrue(idleStoryCycle.detail.contains("routes"))
        XCTAssertEqual(savedArtifactTour.status, .pass)
        XCTAssertTrue(savedArtifactTour.detail.contains("recent"))
        XCTAssertTrue(savedArtifactTour.detail.contains("pinned"))
        XCTAssertTrue(savedArtifactTour.detail.contains("held"))
        XCTAssertTrue(savedArtifactTour.detail.contains("filtered-pin"))
        XCTAssertTrue(savedArtifactTour.detail.contains("filtered-hold"))
        XCTAssertTrue(savedArtifactTour.detail.contains("no-match"))
        XCTAssertTrue(savedArtifactTour.detail.contains("missing-pin"))
        XCTAssertTrue(savedArtifactTour.detail.contains("missing-hold"))
        XCTAssertTrue(savedArtifactTour.detail.contains("warnings"))
        XCTAssertTrue(savedArtifactTour.detail.contains("bounded"))
        XCTAssertTrue(timelineFocus.detail.contains("commit"))
        XCTAssertTrue(timelineFocus.detail.contains("recovery"))
        XCTAssertTrue(timelineFocus.detail.contains("failed-verify"))
        XCTAssertTrue(timelineFocus.detail.contains("commit-constellation"))
        XCTAssertEqual(runRecapFocus.status, .pass)
        XCTAssertTrue(runRecapFocus.detail.contains("active"))
        XCTAssertTrue(runRecapFocus.detail.contains("empty"))
        XCTAssertTrue(runRecapFocus.detail.contains("success"))
        XCTAssertTrue(runRecapFocus.detail.contains("failure"))
        XCTAssertTrue(runRecapFocus.detail.contains("warning"))
        XCTAssertTrue(runRecapFocus.detail.contains("commit nodes"))
        XCTAssertTrue(runRecapFocus.detail.contains("fallbacks"))
        XCTAssertEqual(runRecapEndCard.status, .pass)
        XCTAssertTrue(runRecapEndCard.detail.contains("active"))
        XCTAssertTrue(runRecapEndCard.detail.contains("empty"))
        XCTAssertTrue(runRecapEndCard.detail.contains("success"))
        XCTAssertTrue(runRecapEndCard.detail.contains("failure"))
        XCTAssertTrue(runRecapEndCard.detail.contains("warning"))
        XCTAssertTrue(runRecapEndCard.detail.contains("deterministic"))
        XCTAssertTrue(runRecapEndCard.detail.contains("generated"))
        XCTAssertTrue(runRecapEndCard.detail.contains("bounded"))
        XCTAssertEqual(pinnedComparisonCue.status, .pass)
        XCTAssertTrue(pinnedComparisonCue.detail.contains("active"))
        XCTAssertTrue(pinnedComparisonCue.detail.contains("inactive"))
        XCTAssertTrue(pinnedComparisonCue.detail.contains("selected-only"))
        XCTAssertTrue(pinnedComparisonCue.detail.contains("no-match"))
        XCTAssertTrue(pinnedComparisonCue.detail.contains("stale"))
        XCTAssertTrue(pinnedComparisonCue.detail.contains("filtered-pin"))
        XCTAssertTrue(pinnedComparisonCue.detail.contains("promoted-hold"))
        XCTAssertTrue(pinnedComparisonCue.detail.contains("filtered-promoted-hold"))
        XCTAssertTrue(pinnedComparisonCue.detail.contains("bounded"))
    }

    func testNativeFeedbackCoverageWarnsForMissingOrInconsistentRouteData() throws {
        let completeReports = CinematicDiagnostics.representativeNativeFeedbackSmokeReports()
        let completeSmoke = CinematicVisualSmokeReport(reports: completeReports)
        let completeCheck = try XCTUnwrap(
            completeSmoke.checks.first { $0.id == "native-feedback-cue-coverage" }
        )
        let completeTreatmentCheck = try XCTUnwrap(
            completeSmoke.checks.first { $0.id == "native-feedback-treatment-coverage" }
        )
        XCTAssertEqual(completeCheck.status, .pass)
        XCTAssertEqual(completeTreatmentCheck.status, .pass)

        var inconsistentReports = completeReports
        let activeIndex = try XCTUnwrap(
            inconsistentReports.firstIndex { $0.nativeFeedback.lifecycleStateIdentifier == "active" }
        )
        inconsistentReports[activeIndex].overlayDisplay.nativeFeedbackCueIdentifier = "none"
        let inconsistentSmoke = CinematicVisualSmokeReport(reports: inconsistentReports)
        let inconsistentCheck = try XCTUnwrap(
            inconsistentSmoke.checks.first { $0.id == "native-feedback-cue-coverage" }
        )

        XCTAssertEqual(inconsistentCheck.status, .warning)
        XCTAssertEqual(
            inconsistentCheck.warningIdentifier,
            "visual-smoke.native-feedback-cue-coverage"
        )
        XCTAssertTrue(
            inconsistentSmoke.warningIdentifiers.contains("visual-smoke.native-feedback-cue-coverage")
        )
        XCTAssertLessThanOrEqual(
            inconsistentCheck.warningIdentifier?.count ?? 0,
            CinematicVisualSmokeReport.warningIdentifierMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            inconsistentCheck.detail.count,
            CinematicVisualSmokeReport.detailMaxCharacters
        )

        var missingTreatmentReports = completeReports
        let treatmentIndex = try XCTUnwrap(
            missingTreatmentReports.firstIndex { $0.nativeFeedback.lifecycleStateIdentifier == "active" }
        )
        missingTreatmentReports[treatmentIndex].narrativeCue.questPlaque.plaqueTreatmentAccentIdentifier = "none"
        let missingTreatmentSmoke = CinematicVisualSmokeReport(reports: missingTreatmentReports)
        let missingTreatmentCheck = try XCTUnwrap(
            missingTreatmentSmoke.checks.first { $0.id == "native-feedback-treatment-coverage" }
        )
        XCTAssertEqual(missingTreatmentCheck.status, .warning)
        XCTAssertEqual(
            missingTreatmentCheck.warningIdentifier,
            "visual-smoke.native-feedback-treatment-coverage"
        )
        XCTAssertTrue(
            missingTreatmentSmoke.warningIdentifiers.contains("visual-smoke.native-feedback-treatment-coverage")
        )
        XCTAssertTrue(missingTreatmentCheck.detail.contains("accents 3/4"))
        XCTAssertTrue(missingTreatmentCheck.detail.contains("surfaces 3/4"))
        XCTAssertTrue(missingTreatmentCheck.detail.contains("params 3/4"))

        var malformedParameterReports = completeReports
        let parameterIndex = try XCTUnwrap(
            malformedParameterReports.firstIndex { $0.nativeFeedback.sourceIdentifier == "native:verifyStarted" }
        )
        let originalTreatmentIdentifier = malformedParameterReports[parameterIndex]
            .narrativeCue.questPlaque.plaqueTreatmentIdentifier
        let malformedTreatmentIdentifier = originalTreatmentIdentifier.replacingOccurrences(
            of: "emit0.0800",
            with: "emit0.0000"
        )
        malformedParameterReports[parameterIndex].narrativeCue.questPlaque.plaqueTreatmentIdentifier =
            malformedTreatmentIdentifier
        malformedParameterReports[parameterIndex].narrativeCue.questPlaque.identifier =
            malformedParameterReports[parameterIndex].narrativeCue.questPlaque.identifier
                .replacingOccurrences(of: originalTreatmentIdentifier, with: malformedTreatmentIdentifier)
        malformedParameterReports[parameterIndex].narrativeCue.arenaInscription.plaqueTreatmentIdentifier =
            malformedTreatmentIdentifier
        malformedParameterReports[parameterIndex].narrativeCue.arenaInscription.identifier =
            malformedParameterReports[parameterIndex].narrativeCue.arenaInscription.identifier
                .replacingOccurrences(of: originalTreatmentIdentifier, with: malformedTreatmentIdentifier)
        malformedParameterReports[parameterIndex].narrativeCue.activityBanner.plaqueTreatmentIdentifier =
            malformedTreatmentIdentifier
        malformedParameterReports[parameterIndex].narrativeCue.activityBanner.identifier =
            malformedParameterReports[parameterIndex].narrativeCue.activityBanner.identifier
                .replacingOccurrences(of: originalTreatmentIdentifier, with: malformedTreatmentIdentifier)

        let malformedParameterSmoke = CinematicVisualSmokeReport(reports: malformedParameterReports)
        let malformedParameterCheck = try XCTUnwrap(
            malformedParameterSmoke.checks.first { $0.id == "native-feedback-treatment-coverage" }
        )
        XCTAssertEqual(malformedParameterCheck.status, .warning)
        XCTAssertTrue(malformedParameterCheck.detail.contains("surfaces 4/4"))
        XCTAssertTrue(malformedParameterCheck.detail.contains("params 3/4"))

        var divergentPrimitiveReports = completeReports
        let primitiveIndex = try XCTUnwrap(
            divergentPrimitiveReports.firstIndex { $0.nativeFeedback.sourceIdentifier == "native:verifyStarted" }
        )
        divergentPrimitiveReports[primitiveIndex].narrativeCue.questPlaque
            .plaqueTreatmentRenderPrimitiveIdentifiers = ["rail.top"]
        divergentPrimitiveReports[primitiveIndex].narrativeCue.questPlaque
            .plaqueTreatmentRenderPrimitiveCount = 1
        let divergentPrimitiveSmoke = CinematicVisualSmokeReport(reports: divergentPrimitiveReports)
        let divergentPrimitiveCheck = try XCTUnwrap(
            divergentPrimitiveSmoke.checks.first { $0.id == "native-feedback-treatment-coverage" }
        )
        XCTAssertEqual(divergentPrimitiveCheck.status, .warning)
        XCTAssertTrue(divergentPrimitiveCheck.detail.contains("surfaces 4/4"))
        XCTAssertTrue(divergentPrimitiveCheck.detail.contains("params 4/4"))
        XCTAssertTrue(divergentPrimitiveCheck.detail.contains("prims 3/4"))
    }

    func testRecapArtifactCommandAvailabilityWarnsForMissingCoverageAndCollisions() throws {
        let completeReports = CinematicDiagnostics.representativeRunRecapArtifactCommandSmokeReports()
        let completeSmoke = CinematicVisualSmokeReport(reports: completeReports)
        let completeCheck = try XCTUnwrap(
            completeSmoke.checks.first { $0.id == "run-recap-artifact-command-availability" }
        )
        XCTAssertEqual(completeCheck.status, .pass)
        XCTAssertTrue(completeCheck.detail.contains("available"))
        XCTAssertTrue(completeCheck.detail.contains("collisions clear"))

        let missingNoMatchReports = completeReports.filter {
            $0.runRecapShareArtifactCommands.previewNoMatchAvailabilityReason == nil
        }
        let missingNoMatchSmoke = CinematicVisualSmokeReport(reports: missingNoMatchReports)
        let missingNoMatchCheck = try XCTUnwrap(
            missingNoMatchSmoke.checks.first { $0.id == "run-recap-artifact-command-availability" }
        )
        XCTAssertEqual(missingNoMatchCheck.status, .warning)
        XCTAssertEqual(missingNoMatchCheck.warningIdentifier, "visual-smoke.recap-artifact-commands")
        XCTAssertTrue(missingNoMatchSmoke.warningIdentifiers.contains("visual-smoke.recap-artifact-commands"))
        XCTAssertTrue(missingNoMatchCheck.detail.contains("no-match-missing"))

        var collisionReports = completeReports
        collisionReports[0].runRecapShareArtifactCommands.appLevelShortcutCollisionStateIdentifier = "collision"
        collisionReports[0].runRecapShareArtifactCommands.appLevelShortcutCollisionIdentifiers = ["command:o"]
        let collisionSmoke = CinematicVisualSmokeReport(reports: collisionReports)
        let collisionCheck = try XCTUnwrap(
            collisionSmoke.checks.first { $0.id == "run-recap-artifact-command-availability" }
        )
        XCTAssertEqual(collisionCheck.status, .warning)
        XCTAssertEqual(collisionCheck.warningIdentifier, "visual-smoke.recap-artifact-commands")
        XCTAssertTrue(collisionCheck.detail.contains("collisions 1"))
        XCTAssertLessThanOrEqual(
            collisionCheck.warningIdentifier?.count ?? 0,
            CinematicVisualSmokeReport.warningIdentifierMaxCharacters
        )
        XCTAssertLessThanOrEqual(collisionCheck.detail.count, CinematicVisualSmokeReport.detailMaxCharacters)
    }

    func testIdleStoryCycleCoverageWarnsForMissingDescriptorRoutes() throws {
        let completeReports = CinematicDiagnostics.representativeIdleStoryCycleSmokeReports()
        let completeSmoke = CinematicVisualSmokeReport(reports: completeReports)
        let completeCheck = try XCTUnwrap(
            completeSmoke.checks.first { $0.id == "idle-story-cycle-coverage" }
        )
        XCTAssertEqual(completeCheck.status, .pass)

        var missingRouteReports = completeReports
        let activeIndex = try XCTUnwrap(
            missingRouteReports.firstIndex { $0.idleStoryCycle.isActive }
        )
        missingRouteReports[activeIndex].idleStoryCycle.sourceDescriptorIdentifier = "none"
        let missingRouteSmoke = CinematicVisualSmokeReport(reports: missingRouteReports)
        let missingRouteCheck = try XCTUnwrap(
            missingRouteSmoke.checks.first { $0.id == "idle-story-cycle-coverage" }
        )

        XCTAssertEqual(missingRouteCheck.status, .warning)
        XCTAssertEqual(missingRouteCheck.warningIdentifier, "visual-smoke.idle-story-cycle")
        XCTAssertTrue(missingRouteSmoke.warningIdentifiers.contains("visual-smoke.idle-story-cycle"))
        XCTAssertTrue(missingRouteCheck.detail.contains("routes"))
        XCTAssertTrue(missingRouteCheck.detail.contains("choreo"))
        XCTAssertTrue(missingRouteCheck.detail.contains("timing"))
        XCTAssertLessThanOrEqual(
            missingRouteCheck.detail.count,
            CinematicVisualSmokeReport.detailMaxCharacters
        )
    }

    func testIdleStoryCycleCoverageWarnsForNonDistinctChoreographyRoutes() throws {
        var reports = CinematicDiagnostics.representativeIdleStoryCycleSmokeReports()
        for index in reports.indices where reports[index].idleStoryCycle.isActive {
            reports[index].idleStoryCycle.choreographyIdentifier = "collapsed-choreography"
            reports[index].idleStoryCycle.cameraPressureIdentifier = "collapsed-pressure"
            reports[index].idleStoryCycle.transitionDurationScale = 1
            reports[index].idleStoryCycle.targetBias = 0.6
            reports[index].idleStoryCycle.dwellDuration = 4.8
            reports[index].idleStoryCycle.cadence = 7.2
        }

        let smoke = CinematicVisualSmokeReport(reports: reports)
        let check = try XCTUnwrap(
            smoke.checks.first { $0.id == "idle-story-cycle-coverage" }
        )

        XCTAssertEqual(check.status, .warning)
        XCTAssertEqual(check.warningIdentifier, "visual-smoke.idle-story-cycle")
        let expectedDistinctRoutes = CinematicIdleStoryCyclePlan.Descriptor.Phase.allCases.count
        XCTAssertTrue(check.detail.contains("choreo 1/\(expectedDistinctRoutes)"))
        XCTAssertTrue(check.detail.contains("timing 1/\(expectedDistinctRoutes)"))
        XCTAssertTrue(check.detail.contains("pressure 1/\(expectedDistinctRoutes)"))
    }

    func testWarningReportUsesBoundedIdentifiersAndDetails() throws {
        let cleanCompact = try XCTUnwrap(
            CinematicDiagnostics.representativeSmokeMatrix().first {
                $0.activityMotif.eventKindIdentifier == "clean"
                    && $0.overlayDisplay.modeIdentifier == "compact"
            }
        )
        let smoke = CinematicVisualSmokeReport(reports: [cleanCompact])

        XCTAssertEqual(smoke.status, .warning)
        XCTAssertTrue(smoke.warningIdentifiers.contains("visual-smoke.overlay-coverage"))
        XCTAssertTrue(smoke.warningIdentifiers.contains("visual-smoke.chrome-strength"))
        XCTAssertTrue(smoke.warningIdentifiers.contains("visual-smoke.texture-role-coverage"))
        XCTAssertTrue(smoke.warningIdentifiers.contains("visual-smoke.language-layout-coverage"))
        XCTAssertTrue(smoke.warningIdentifiers.contains("visual-smoke.activity-material-treatment"))
        XCTAssertTrue(smoke.warningIdentifiers.contains("visual-smoke.camera-phase-coverage"))
        XCTAssertTrue(smoke.warningIdentifiers.contains("visual-smoke.pressure-influence-spread"))
        XCTAssertTrue(smoke.warningIdentifiers.contains("visual-smoke.recovery-cue-coverage"))
        XCTAssertTrue(smoke.warningIdentifiers.contains("visual-smoke.native-feedback-cue-coverage"))
        XCTAssertTrue(smoke.warningIdentifiers.contains("visual-smoke.native-feedback-treatment-coverage"))
        XCTAssertTrue(smoke.warningIdentifiers.contains("visual-smoke.idle-story-cycle"))
        XCTAssertTrue(smoke.warningIdentifiers.contains("visual-smoke.recap-artifact-commands"))
        XCTAssertTrue(smoke.warningIdentifiers.contains("visual-smoke.saved-artifact-tour"))
        XCTAssertTrue(smoke.warningIdentifiers.contains("visual-smoke.timeline-focus-coverage"))
        XCTAssertTrue(smoke.warningIdentifiers.contains("visual-smoke.run-recap-focus-coverage"))
        XCTAssertTrue(smoke.warningIdentifiers.contains("visual-smoke.run-recap-end-card"))
        XCTAssertEqual(
            smoke.checks.first { $0.id == "narrative-cue-readability" }?.status,
            .pass
        )
        XCTAssertEqual(smoke.checks.first { $0.id == "text-bounds" }?.status, .pass)
        XCTAssertEqual(smoke.checks.first { $0.id == "asset-availability" }?.status, .pass)

        for check in smoke.checks {
            XCTAssertLessThanOrEqual(check.id.count, CinematicVisualSmokeReport.warningIdentifierMaxCharacters)
            XCTAssertLessThanOrEqual(check.label.count, CinematicVisualSmokeReport.labelMaxCharacters)
            XCTAssertLessThanOrEqual(check.detail.count, CinematicVisualSmokeReport.detailMaxCharacters)
            XCTAssertFalse(check.detail.isEmpty)
            if let warningIdentifier = check.warningIdentifier {
                XCTAssertLessThanOrEqual(
                    warningIdentifier.count,
                    CinematicVisualSmokeReport.warningIdentifierMaxCharacters
                )
            }
        }
    }

    func testAssetAvailabilityWarnsForEmptyOrUnrecognizedTextureNames() throws {
        let report = try XCTUnwrap(CinematicDiagnostics.representativeSmokeMatrix().first)

        var emptyTextureReport = report
        emptyTextureReport.setDressing.backdropTextureName = ""
        let emptySmoke = CinematicVisualSmokeReport(reports: [emptyTextureReport])
        XCTAssertEqual(emptySmoke.checks.first { $0.id == "asset-availability" }?.status, .warning)
        XCTAssertTrue(emptySmoke.warningIdentifiers.contains("visual-smoke.asset-availability"))

        var unrecognizedTextureReport = report
        unrecognizedTextureReport.setDressing.arenaTextureName = "missing-arena-runes"
        let unrecognizedSmoke = CinematicVisualSmokeReport(reports: [unrecognizedTextureReport])
        XCTAssertEqual(unrecognizedSmoke.checks.first { $0.id == "asset-availability" }?.status, .warning)
        XCTAssertTrue(unrecognizedSmoke.warningIdentifiers.contains("visual-smoke.asset-availability"))

        var fallbackBackdropReport = report
        fallbackBackdropReport.setDressing.backdropTextureName = "void-arches"
        let fallbackSmoke = CinematicVisualSmokeReport(reports: [fallbackBackdropReport])
        XCTAssertEqual(fallbackSmoke.checks.first { $0.id == "texture-role-coverage" }?.status, .warning)
        XCTAssertTrue(fallbackSmoke.warningIdentifiers.contains("visual-smoke.texture-role-coverage"))

        var fallbackArenaReport = report
        fallbackArenaReport.setDressing.arenaTextureName = "arena-runes"
        let fallbackArenaSmoke = CinematicVisualSmokeReport(reports: [fallbackArenaReport])
        XCTAssertEqual(fallbackArenaSmoke.checks.first { $0.id == "texture-role-coverage" }?.status, .warning)
        XCTAssertTrue(fallbackArenaSmoke.warningIdentifiers.contains("visual-smoke.texture-role-coverage"))
    }

    func testSummaryExportIncludesVisualSmokeWithoutChangingRowsOrSections() {
        let report = CinematicDiagnostics.representativeSmokeMatrix().first!
        let summary = CinematicDiagnosticsSummary(
            report: report,
            visualSmoke: CinematicVisualSmokeReport.representative()
        )

        XCTAssertEqual(summary.visualSmoke.id, "visual-smoke")
        XCTAssertEqual(summary.visualSmoke.label, "Visual smoke")
        XCTAssertEqual(summary.visualSmoke.status, .pass)
        XCTAssertEqual(summary.visualSmoke.statusLabel, "Passing")
        XCTAssertEqual(summary.visualSmoke.warningCount, 0)
        XCTAssertEqual(summary.visualSmoke.warningCountLabel, "No warnings")
        XCTAssertEqual(summary.visualSmoke.warningBadgeLabel, "0")
        XCTAssertEqual(summary.visualSmoke.warningIdentifiers, [])
        XCTAssertEqual(summary.visualSmoke.checkCountLabel, "20 checks")
        XCTAssertEqual(summary.visualSmoke.presentation.headerDetail, "20 checks | No warnings")
        XCTAssertEqual(summary.visualSmoke.presentation.defaultExpanded, false)
        XCTAssertEqual(summary.visualSmoke.presentation.attentionState, .normal)
        XCTAssertEqual(summary.visualSmoke.presentation.warningIdentifiers, [])
        XCTAssertEqual(summary.visualSmoke.presentation.needsAttention, false)
        XCTAssertEqual(summary.attentionSummary.targets, [])
        XCTAssertEqual(summary.attentionSummary.targets.map(\.copyText), [])
        XCTAssertTrue(summary.attentionSummary.isEmpty)
        XCTAssertFalse(summary.nativeFeedbackHistoryExport.isAvailable)
        XCTAssertEqual(summary.nativeFeedbackHistoryExport.copyText, "")
        XCTAssertLessThanOrEqual(
            summary.visualSmoke.warningCountLabel.count,
            CinematicDiagnosticsSummary.visualSmokeCountMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            summary.visualSmoke.presentation.headerDetail.count,
            CinematicDiagnosticsSummary.headerDetailMaxCharacters
        )
        XCTAssertTrue(summary.exportText.contains("Visual smoke (pass, 20 checks)"))
        XCTAssertTrue(summary.exportText.contains("Recap command availability: pass"))
        let commandCheck = summary.visualSmoke.checks.first {
            $0.id == "run-recap-artifact-command-availability"
        }
        XCTAssertNil(commandCheck?.warningTarget)
        XCTAssertFalse(summary.exportText.contains("Recap command availability ->"))
        XCTAssertTrue(summary.exportText.contains("Narrative cue readability: pass"))
        XCTAssertTrue(summary.exportText.contains("Texture role coverage: pass"))
        XCTAssertTrue(summary.exportText.contains("Language layout coverage: pass"))
        XCTAssertTrue(summary.exportText.contains("Activity material treatment: pass"))
        XCTAssertTrue(summary.exportText.contains("Pressure/influence spread: pass"))
        XCTAssertTrue(summary.exportText.contains("Recovery cue coverage: pass"))
        XCTAssertTrue(summary.exportText.contains("Native feedback coverage: pass"))
        XCTAssertTrue(summary.exportText.contains("Native feedback treatment: pass"))
        XCTAssertTrue(summary.exportText.contains("Idle story cycle: pass"))
        XCTAssertTrue(summary.exportText.contains("Saved artifact tour: pass"))
        XCTAssertTrue(summary.exportText.contains("Timeline focus coverage: pass"))
        XCTAssertTrue(summary.exportText.contains("Run recap end card: pass"))
        XCTAssertEqual(summary.plaqueTreatmentLegend.id, "plaque-treatment-legend")
        XCTAssertEqual(summary.plaqueTreatmentLegend.label, "Plaque treatments")
        XCTAssertEqual(summary.plaqueTreatmentLegend.status, .pass)
        XCTAssertEqual(summary.plaqueTreatmentLegend.statusLabel, "Passing")
        XCTAssertEqual(summary.plaqueTreatmentLegend.detail, "smoke pass")
        XCTAssertNil(summary.plaqueTreatmentLegend.warningIdentifier)
        XCTAssertEqual(summary.plaqueTreatmentLegend.rowCountLabel, "4 recipes")
        XCTAssertEqual(summary.plaqueTreatmentLegend.presentation.headerDetail, "4 recipes | Passing | No warnings")
        XCTAssertEqual(summary.plaqueTreatmentLegend.presentation.defaultExpanded, false)
        XCTAssertEqual(summary.plaqueTreatmentLegend.presentation.attentionState, .normal)
        XCTAssertEqual(summary.plaqueTreatmentLegend.presentation.warningIdentifiers, [])
        XCTAssertEqual(summary.plaqueTreatmentLegend.presentation.needsAttention, false)
        XCTAssertLessThanOrEqual(
            summary.plaqueTreatmentLegend.presentation.headerDetail.count,
            CinematicDiagnosticsSummary.headerDetailMaxCharacters
        )
        XCTAssertEqual(
            summary.plaqueTreatmentLegend.rows.map(\.label),
            ["verify-seal", "warning-rails", "failure-fracture", "retry-braces"]
        )
        XCTAssertTrue(summary.exportText.contains("Plaque treatments (pass, 4 recipes): smoke pass"))
        XCTAssertTrue(summary.exportText.contains("verify-seal: accent verify-seal"))
        XCTAssertTrue(summary.exportText.contains("route verifyStarted.verify"))
        XCTAssertTrue(summary.exportText.contains("recipe rail.top,rail.bottom,seal.left,seal.right"))
        XCTAssertTrue(summary.exportText.contains("retry-braces: accent retry-braces"))
        XCTAssertTrue(summary.exportText.contains("primitives 5 rail.top,rail.bottom,retry.brace.left,retry.brace.right,retry.cross"))
        XCTAssertFalse(summary.exportText.contains("Warning summary"))
        XCTAssertFalse(summary.sections.contains { $0.id == "visual-smoke" })
        XCTAssertEqual(summary.rows.count, CinematicDiagnosticsSummary.maxRows)
        XCTAssertEqual(
            summary.rows.map(\.id).prefix(11),
            [
                "repository",
                "immediate",
                "commit-constellation",
                "idle-story-cycle",
                "timeline-focus",
                "run-recap",
                "run-recap-share",
                "run-recap-share-artifact",
                "run-recap-share-artifact-history",
                "run-recap-share-artifact-rollup",
                "run-recap-share-artifact-comparison"
            ]
        )
        XCTAssertEqual(
            summary.sections.map(\.id),
            [
                "repository-context",
                "motifs",
                "stage-motion-effects",
                "narrative-overlay",
                "assets-textures",
                "tuning",
                "camera-shots"
            ]
        )
    }

    func testSummaryVisualSmokeSectionSurfacesInjectedWarningsWithWarningSummary() throws {
        let report = try XCTUnwrap(CinematicDiagnostics.representativeSmokeMatrix().first)

        var missingTextureReport = report
        missingTextureReport.setDressing.backdropTextureName = ""
        let smoke = CinematicVisualSmokeReport(reports: [missingTextureReport])
        let summary = CinematicDiagnosticsSummary(report: report, visualSmoke: smoke)

        XCTAssertEqual(summary.visualSmoke.status, .warning)
        XCTAssertEqual(summary.visualSmoke.statusLabel, "Warning")
        XCTAssertEqual(summary.visualSmoke.warningCount, smoke.warningIdentifiers.count)
        XCTAssertEqual(summary.visualSmoke.warningCountLabel, "\(smoke.warningIdentifiers.count) warnings")
        XCTAssertEqual(summary.visualSmoke.warningBadgeLabel, "\(smoke.warningIdentifiers.count)")
        XCTAssertEqual(summary.visualSmoke.warningIdentifiers, smoke.warningIdentifiers)
        XCTAssertEqual(summary.visualSmoke.checks, smoke.checks)
        XCTAssertEqual(summary.visualSmoke.presentation.defaultExpanded, true)
        XCTAssertEqual(summary.visualSmoke.presentation.attentionState, .warning)
        XCTAssertEqual(summary.visualSmoke.presentation.warningIdentifiers, smoke.warningIdentifiers)
        XCTAssertEqual(summary.visualSmoke.presentation.needsAttention, true)
        XCTAssertTrue(summary.visualSmoke.presentation.headerDetail.contains("20 checks"))
        for warningIdentifier in smoke.warningIdentifiers.prefix(2) {
            XCTAssertTrue(summary.visualSmoke.presentation.headerDetail.contains(warningIdentifier))
        }
        XCTAssertTrue(summary.visualSmoke.help.contains("visual-smoke.asset-availability"))
        XCTAssertTrue(summary.visualSmoke.help.contains("visual-smoke.texture-role-coverage"))
        XCTAssertLessThanOrEqual(
            summary.visualSmoke.warningCountLabel.count,
            CinematicDiagnosticsSummary.visualSmokeCountMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            summary.visualSmoke.presentation.headerDetail.count,
            CinematicDiagnosticsSummary.headerDetailMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            summary.visualSmoke.help.count,
            CinematicDiagnosticsSummary.detailMaxCharacters
        )

        let assetCheck = try XCTUnwrap(summary.visualSmoke.checks.first { $0.id == "asset-availability" })
        let textureCheck = try XCTUnwrap(summary.visualSmoke.checks.first { $0.id == "texture-role-coverage" })
        let commandCheck = try XCTUnwrap(
            summary.visualSmoke.checks.first { $0.id == "run-recap-artifact-command-availability" }
        )
        XCTAssertEqual(assetCheck.status, .warning)
        XCTAssertEqual(assetCheck.warningIdentifier, "visual-smoke.asset-availability")
        XCTAssertEqual(textureCheck.status, .warning)
        XCTAssertEqual(textureCheck.warningIdentifier, "visual-smoke.texture-role-coverage")
        XCTAssertEqual(commandCheck.status, .warning)
        XCTAssertEqual(
            commandCheck.warningTarget?.targetAnchorID,
            "visual-smoke-check-run-recap-artifact-command-availability"
        )

        for check in summary.visualSmoke.checks {
            XCTAssertLessThanOrEqual(check.label.count, CinematicVisualSmokeReport.labelMaxCharacters)
            XCTAssertLessThanOrEqual(check.detail.count, CinematicVisualSmokeReport.detailMaxCharacters)
        }

        XCTAssertEqual(
            summary.attentionSummary.targets.map(\.id),
            [
                "visual-smoke-check-run-recap-artifact-command-availability",
                "visual-smoke",
                "plaque-treatment-legend"
            ]
        )
        XCTAssertFalse(
            summary.attentionSummary.targets.contains {
                $0.id == summary.nativeFeedbackHistoryExport.id
            }
        )
        let commandTarget = try XCTUnwrap(
            summary.attentionSummary.targets.first {
                $0.id == "visual-smoke-check-run-recap-artifact-command-availability"
            }
        )
        XCTAssertEqual(commandTarget.label, "Recap command availability")
        XCTAssertEqual(commandTarget.targetGroupID, "visual-smoke")
        XCTAssertEqual(commandTarget.relatedGroupID, "repository-context")
        XCTAssertEqual(commandTarget.relatedRowID, "run-recap-share-artifact-commands")
        XCTAssertTrue(commandTarget.detail.contains("disabled"))
        XCTAssertTrue(commandTarget.detail.contains("cleanup"))
        XCTAssertTrue(commandTarget.detail.contains("collisions"))
        XCTAssertTrue(commandTarget.detail.contains("correlated"))
        XCTAssertLessThanOrEqual(
            commandTarget.copyText.count,
            CinematicDiagnosticsSummary.attentionTargetCopyMaxCharacters
        )
        XCTAssertTrue(commandTarget.copyText.contains("Cinematic diagnostics warning target"))
        XCTAssertTrue(commandTarget.copyText.contains("Label: Recap command availability"))
        XCTAssertTrue(
            commandTarget.copyText.contains(
                "Target anchor: visual-smoke-check-run-recap-artifact-command-availability"
            )
        )
        XCTAssertTrue(commandTarget.copyText.contains("Target group: visual-smoke"))
        XCTAssertTrue(commandTarget.copyText.contains("Warnings: visual-smoke.recap-artifact-commands"))
        XCTAssertTrue(commandTarget.copyText.contains("Detail:"))
        XCTAssertTrue(commandTarget.copyText.contains("disabled"))
        XCTAssertTrue(commandTarget.copyText.contains("Related row: run-recap-share-artifact-commands"))
        XCTAssertTrue(commandTarget.copyText.contains("Related detail:"))
        XCTAssertTrue(commandTarget.copyText.contains("Recap artifact commands"))
        XCTAssertFalse(commandTarget.copyText.contains("Cinematic Diagnostics\nReport:"))
        XCTAssertFalse(commandTarget.copyText.contains("Visual smoke (warning,"))
        let visualSmokeTarget = try XCTUnwrap(
            summary.attentionSummary.targets.first { $0.id == "visual-smoke" }
        )
        XCTAssertEqual(visualSmokeTarget.id, "visual-smoke")
        XCTAssertEqual(visualSmokeTarget.label, "Visual smoke")
        XCTAssertEqual(visualSmokeTarget.warningCount, smoke.warningIdentifiers.count)
        XCTAssertEqual(
            visualSmokeTarget.visibleWarningIdentifiers,
            Array(smoke.warningIdentifiers.prefix(CinematicDiagnosticsSummary.attentionSummaryMaxVisibleWarnings))
        )
        XCTAssertLessThanOrEqual(
            visualSmokeTarget.visibleWarningIdentifiers.count,
            CinematicDiagnosticsSummary.attentionSummaryMaxVisibleWarnings
        )
        XCTAssertLessThanOrEqual(
            visualSmokeTarget.detail.count,
            CinematicDiagnosticsSummary.attentionSummaryDetailMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            visualSmokeTarget.copyText.count,
            CinematicDiagnosticsSummary.attentionTargetCopyMaxCharacters
        )
        XCTAssertTrue(visualSmokeTarget.copyText.contains("Label: Visual smoke"))
        XCTAssertTrue(visualSmokeTarget.copyText.contains("Target anchor: visual-smoke"))
        XCTAssertTrue(visualSmokeTarget.copyText.contains("Target group: visual-smoke"))
        for warningIdentifier in visualSmokeTarget.visibleWarningIdentifiers {
            XCTAssertTrue(visualSmokeTarget.copyText.contains(warningIdentifier))
        }
        XCTAssertFalse(visualSmokeTarget.copyText.contains("Related row:"))
        let plaqueTarget = try XCTUnwrap(
            summary.attentionSummary.targets.first { $0.targetGroupID == "plaque-treatment-legend" }
        )
        XCTAssertEqual(plaqueTarget.id, "plaque-treatment-legend")
        XCTAssertEqual(plaqueTarget.label, "Plaque treatments")
        XCTAssertEqual(plaqueTarget.warningCount, 1)
        XCTAssertEqual(
            plaqueTarget.visibleWarningIdentifiers,
            ["visual-smoke.native-feedback-treatment-coverage"]
        )
        XCTAssertLessThanOrEqual(
            summary.attentionSummary.targets.count,
            CinematicDiagnosticsSummary.attentionSummaryMaxTargets
        )
        XCTAssertEqual(
            summary.attentionSummary.targets.map { $0.copyText.contains("Cinematic diagnostics warning target") },
            [true, true, true]
        )

        XCTAssertFalse(summary.sections.contains { $0.id == "visual-smoke" })
        XCTAssertEqual(summary.rows.count, CinematicDiagnosticsSummary.maxRows)
        XCTAssertEqual(
            summary.exportText.components(separatedBy: "\n").count,
            summary.rows.count
                + summary.sections.count
                + summary.attentionSummary.targets.count
                + summary.visualSmoke.checks.count
                + summary.plaqueTreatmentLegend.rows.count
                + 5
        )
        XCTAssertTrue(summary.exportText.contains("Warning summary (3 targets)"))
        XCTAssertTrue(
            summary.exportText.contains(
                "Recap command availability -> visual-smoke-check-run-recap-artifact-command-availability"
            )
        )
        XCTAssertTrue(summary.exportText.contains("related run-recap-share-artifact-commands"))
        XCTAssertTrue(
            summary.exportText.contains("Visual smoke -> visual-smoke (\(smoke.warningIdentifiers.count) warnings):")
        )
        XCTAssertTrue(
            summary.exportText.contains("Plaque treatments -> plaque-treatment-legend (1 warning):")
        )
        XCTAssertTrue(summary.exportText.contains("visual-smoke.asset-availability"))
        XCTAssertTrue(summary.exportText.contains("visual-smoke.texture-role-coverage"))
        XCTAssertTrue(summary.exportText.contains("visual-smoke.native-feedback-treatment-coverage"))
        XCTAssertTrue(summary.exportText.contains("Visual smoke (warning, 20 checks)"))
        XCTAssertTrue(summary.exportText.contains("Recap command availability: warning"))
        XCTAssertTrue(summary.exportText.contains("Asset availability: warning"))
        XCTAssertTrue(summary.exportText.contains("warning visual-smoke.asset-availability"))
        XCTAssertTrue(summary.exportText.contains("Texture role coverage: warning"))
        XCTAssertTrue(summary.exportText.contains("warning visual-smoke.texture-role-coverage"))
        XCTAssertEqual(summary.plaqueTreatmentLegend.status, .warning)
        XCTAssertEqual(
            summary.plaqueTreatmentLegend.warningIdentifier,
            "visual-smoke.native-feedback-treatment-coverage"
        )
        XCTAssertEqual(summary.plaqueTreatmentLegend.presentation.defaultExpanded, true)
        XCTAssertEqual(summary.plaqueTreatmentLegend.presentation.attentionState, .warning)
        XCTAssertEqual(
            summary.plaqueTreatmentLegend.presentation.warningIdentifiers,
            ["visual-smoke.native-feedback-treatment-coverage"]
        )
        XCTAssertTrue(
            summary.plaqueTreatmentLegend.presentation.headerDetail.contains(
                "visual-smoke.native-feedback-treatment-coverage"
            )
        )
        XCTAssertLessThanOrEqual(
            summary.plaqueTreatmentLegend.presentation.headerDetail.count,
            CinematicDiagnosticsSummary.headerDetailMaxCharacters
        )
        XCTAssertTrue(
            summary.plaqueTreatmentLegend.detail.contains("visual-smoke.native-feedback-treatment-coverage")
        )
        XCTAssertTrue(
            summary.exportText.contains(
                "Plaque treatments (warning, 4 recipes): smoke warning visual-smoke.native-feedback-treatment-coverage"
            )
        )
    }

    func testSummaryPlaqueTreatmentLegendSurfacesPrimitiveDivergenceWarning() throws {
        let report = try XCTUnwrap(CinematicDiagnostics.representativeSmokeMatrix().first)
        var divergentPrimitiveReports = CinematicDiagnostics.representativeNativeFeedbackSmokeReports()
        let primitiveIndex = try XCTUnwrap(
            divergentPrimitiveReports.firstIndex { $0.nativeFeedback.sourceIdentifier == "native:verifyStarted" }
        )
        divergentPrimitiveReports[primitiveIndex].narrativeCue.questPlaque
            .plaqueTreatmentRenderPrimitiveIdentifiers = ["rail.top"]
        divergentPrimitiveReports[primitiveIndex].narrativeCue.questPlaque
            .plaqueTreatmentRenderPrimitiveCount = 1

        let smoke = CinematicVisualSmokeReport(reports: divergentPrimitiveReports)
        let treatmentCheck = try XCTUnwrap(
            smoke.checks.first { $0.id == "native-feedback-treatment-coverage" }
        )
        XCTAssertEqual(treatmentCheck.status, .warning)
        XCTAssertEqual(
            treatmentCheck.warningIdentifier,
            "visual-smoke.native-feedback-treatment-coverage"
        )
        XCTAssertTrue(smoke.warningIdentifiers.contains("visual-smoke.native-feedback-treatment-coverage"))
        XCTAssertTrue(treatmentCheck.detail.contains("prims 3/4"))

        let summary = CinematicDiagnosticsSummary(report: report, visualSmoke: smoke)
        XCTAssertEqual(summary.plaqueTreatmentLegend.status, .warning)
        XCTAssertEqual(summary.plaqueTreatmentLegend.statusLabel, "Warning")
        XCTAssertEqual(
            summary.plaqueTreatmentLegend.warningIdentifier,
            "visual-smoke.native-feedback-treatment-coverage"
        )
        XCTAssertEqual(summary.plaqueTreatmentLegend.presentation.defaultExpanded, true)
        XCTAssertEqual(summary.plaqueTreatmentLegend.presentation.attentionState, .warning)
        XCTAssertEqual(
            summary.plaqueTreatmentLegend.presentation.warningIdentifiers,
            ["visual-smoke.native-feedback-treatment-coverage"]
        )
        XCTAssertTrue(
            summary.plaqueTreatmentLegend.presentation.headerDetail.contains(
                "visual-smoke.native-feedback-treatment-coverage"
            )
        )
        XCTAssertTrue(
            summary.plaqueTreatmentLegend.detail.contains("visual-smoke.native-feedback-treatment-coverage")
        )
        XCTAssertEqual(
            summary.plaqueTreatmentLegend.rows.map(\.label),
            ["verify-seal", "warning-rails", "failure-fracture", "retry-braces"]
        )
        XCTAssertEqual(
            summary.attentionSummary.targets.map(\.id),
            [
                "visual-smoke-check-run-recap-artifact-command-availability",
                "visual-smoke",
                "plaque-treatment-legend"
            ]
        )
        let visualSmokeTarget = try XCTUnwrap(
            summary.attentionSummary.targets.first { $0.id == "visual-smoke" }
        )
        XCTAssertEqual(visualSmokeTarget.warningCount, smoke.warningIdentifiers.count)
        XCTAssertEqual(
            visualSmokeTarget.visibleWarningIdentifiers,
            Array(smoke.warningIdentifiers.prefix(CinematicDiagnosticsSummary.attentionSummaryMaxVisibleWarnings))
        )
        let plaqueTarget = try XCTUnwrap(
            summary.attentionSummary.targets.first { $0.targetGroupID == "plaque-treatment-legend" }
        )
        XCTAssertEqual(plaqueTarget.warningCount, 1)
        XCTAssertEqual(
            plaqueTarget.visibleWarningIdentifiers,
            ["visual-smoke.native-feedback-treatment-coverage"]
        )
        for row in summary.plaqueTreatmentLegend.rows {
            XCTAssertLessThanOrEqual(row.label.count, CinematicDiagnosticsSummary.labelMaxCharacters)
            XCTAssertLessThanOrEqual(row.detail.count, CinematicDiagnosticsSummary.detailMaxCharacters)
        }
        XCTAssertTrue(summary.exportText.contains("Warning summary (3 targets)"))
        XCTAssertTrue(
            summary.exportText.contains(
                "Recap command availability -> visual-smoke-check-run-recap-artifact-command-availability"
            )
        )
        XCTAssertTrue(
            summary.exportText.contains(
                "Visual smoke -> visual-smoke (\(smoke.warningIdentifiers.count) warnings):"
            )
        )
        XCTAssertTrue(
            summary.exportText.contains(
                "Plaque treatments -> plaque-treatment-legend (1 warning): 4 recipes | Warning"
            )
        )
        XCTAssertTrue(summary.exportText.contains("Plaque treatments (warning, 4 recipes)"))
        XCTAssertTrue(summary.exportText.contains("warning visual-smoke.native-feedback-treatment-coverage"))
    }
}
