import Foundation
@testable import Compass
import XCTest

final class CinematicDiagnosticsTests: XCTestCase {
    func testReportIsStableAndUsesDeterministicCopyAndMotifs() {
        let latestEvent = CinematicBriefingEvent(
            line: LiveLine(
                level: .success,
                text: "Develop diagnostics stabilized",
                detail: "Develop diagnostics stabilized",
                kind: .agentMessage,
                status: .completed
            )
        )
        let settings = CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 0.75)
        let input = CinematicDiagnosticsInput(
            repoName: "Compass",
            phase: "Developing",
            immediateTitle: "Add deterministic cinematic diagnostics smoke path",
            completedCount: 4,
            latestEvent: latestEvent,
            languageProfile: languageProfile(primaryLanguage: .swift),
            activityProfile: activityProfile(worktreeChanges: worktreeChanges(modified: 3)),
            influenceSettings: settings
        )

        let report = makeReport(input)
        let repeated = makeReport(input)

        XCTAssertEqual(report, repeated)
        XCTAssertEqual(report.influenceIdentifier, "dramatic|0.7500|standard")
        XCTAssertEqual(report.languageMotif.sigilIdentifier, "language.swift")
        XCTAssertEqual(report.languageMotif.styleIdentifier, "swift-comet")
        XCTAssertEqual(report.languageMotif.ambientSpellIdentifier, "edit")
        XCTAssertEqual(report.activityMotif.eventKindIdentifier, "dirty")
        XCTAssertEqual(report.activityMotif.sigilIdentifier, "activity.dirty")
        XCTAssertEqual(report.activityMotif.styleIdentifier, "pressure-shard")
        XCTAssertEqual(report.activityMotif.tintSourceIdentifier, "pressure")
        XCTAssertEqual(report.activityMotif.transitionSpellIdentifier, "pressure")
        XCTAssertEqual(report.recoveryCue.kindIdentifier, "none")
        XCTAssertEqual(report.recoveryCue.treatmentIdentifier, "none")
        XCTAssertEqual(report.recoveryCue.visualIdentifier, "none")
        XCTAssertEqual(report.recoveryCue.lightFamilyIdentifier, "none")
        XCTAssertFalse(report.timelineFocus.isActive)
        XCTAssertEqual(report.timelineFocus.kindIdentifier, "none")
        XCTAssertEqual(report.timelineFocus.identifier, "timeline-focus.none")
        XCTAssertEqual(report.stageBeat.kindIdentifier, "developing")
        XCTAssertEqual(report.stageBeat.cameraShotIdentifier, "cast-prep")
        XCTAssertEqual(report.stageBeat.lightFamilyIdentifier, "shell")
        XCTAssertEqual(report.stageBeat.activityEventKindIdentifier, "dirty")
        XCTAssertEqual(report.stageBeat.activityLightFamilyIdentifier, "pressure")
        XCTAssertEqual(report.stageBeat.activityArenaEffectIdentifier, "activity-pulse")
        XCTAssertEqual(report.stageEffect.phaseArenaEffectIdentifier, "charge")
        XCTAssertEqual(report.stageEffect.activityArenaEffectIdentifier, "activity-pulse")
        XCTAssertNil(report.stageEffect.recoveryEffectIdentifier)
        XCTAssertEqual(report.stageEffect.recoveryCueKindIdentifier, "none")
        XCTAssertEqual(report.stageEffect.arenaRingCount, 3)
        XCTAssertEqual(report.stageEffect.phaseLightPulseCount, 1)
        XCTAssertEqual(report.stageEffect.pressureLevelIdentifier, "light")
        XCTAssertEqual(report.stageEffect.influenceStyleIdentifier, "dramatic")
        XCTAssertGreaterThan(report.stageEffect.energy, 0)
        XCTAssertTrue(report.identifier.contains("stage-atmosphere:"))
        XCTAssertEqual(report.stageAtmosphere.pressureLevelIdentifier, "light")
        XCTAssertEqual(report.stageAtmosphere.influenceStyleIdentifier, "dramatic")
        XCTAssertEqual(report.stageAtmosphere.activityIdentifier, "dirty")
        XCTAssertGreaterThan(report.stageAtmosphere.pressureHaloOpacity, 0)
        XCTAssertGreaterThan(report.stageAtmosphere.phaseLightPressureBoost, 0)
        XCTAssertGreaterThan(report.stageAtmosphere.floorTintOpacity, 0)
        XCTAssertTrue(report.identifier.contains("phase-polish:"))
        XCTAssertEqual(report.stagePhasePolish.postureIdentifier, "editing")
        XCTAssertEqual(report.stagePhasePolish.phaseIdentifier, "developing")
        XCTAssertEqual(report.stagePhasePolish.activityIdentifier, "dirty")
        XCTAssertEqual(report.stagePhasePolish.recoveryCueKindIdentifier, "none")
        XCTAssertEqual(report.stagePhasePolish.staffOrbLightFamilyIdentifier, "edit")
        XCTAssertGreaterThan(report.stagePhasePolish.poseIntensity, 0)
        XCTAssertGreaterThan(report.stagePhasePolish.staffOrbEmission, 0)
        XCTAssertGreaterThan(report.stagePhasePolish.sigilOrbitRadius, 0)
        XCTAssertGreaterThan(report.stagePhasePolish.portalAperture, 0)
        XCTAssertTrue(report.identifier.contains("narrative-cues:"))
        XCTAssertEqual(report.narrativeCue.questPlaque.text, report.worldText.questLabel)
        XCTAssertEqual(report.narrativeCue.questPlaque.secondaryText, report.briefing.title)
        XCTAssertEqual(report.narrativeCue.arenaInscription.text, report.worldText.arenaCallout)
        XCTAssertEqual(report.narrativeCue.activityBanner.text, report.worldText.activityCallout)
        XCTAssertEqual(report.narrativeCue.questPlaque.anchorIdentifier, "left-forge-pylon")
        XCTAssertEqual(report.narrativeCue.activityBanner.anchorIdentifier, "right-warning-pylon")
        XCTAssertEqual(report.narrativeCue.activityBanner.lightFamilyIdentifier, "pressure")
        XCTAssertEqual(report.narrativeCue.questPlaque.layout.facingModeIdentifier, "arena-camera")
        XCTAssertEqual(report.narrativeCue.arenaInscription.layout.facingModeIdentifier, "floor-inscription")
        XCTAssertEqual(report.narrativeCue.activityBanner.layout.glyphSideIdentifier, "trailing")
        XCTAssertTrue(report.narrativeCue.questPlaque.identifier.contains(report.narrativeCue.questPlaque.layout.identifier))
        XCTAssertFalse(report.narrativeCue.identifier.isEmpty)
        XCTAssertTrue(report.identifier.contains("overlay:"))
        XCTAssertEqual(report.overlayDisplay.modeIdentifier, "compact")
        XCTAssertEqual(report.overlayDisplay.visiblePillIdentifiers, ["activity"])
        XCTAssertEqual(report.overlayDisplay.hudProminenceIdentifier, "minimal")
        XCTAssertTrue(report.overlayDisplay.chromeStyleIdentifier.hasPrefix("compact-active|"))
        XCTAssertEqual(report.overlayDisplay.reasonIdentifier, "in-world-readable-cues")
        XCTAssertTrue(report.overlayDisplay.narrativeCueReadabilityIdentifier.contains("count:3"))
        XCTAssertTrue(report.overlayDisplay.identifier.contains("chrome:\(report.overlayDisplay.chromeStyleIdentifier)"))
        XCTAssertEqual(report.overlayDisplay.activitySourceCuePolicyIdentifier, "hidden")
        XCTAssertEqual(report.overlayDisplay.activitySourceCueKindIdentifier, "hidden")
        XCTAssertEqual(report.overlayDisplay.activitySourceCueSeverityIdentifier, "info")
        XCTAssertFalse(report.overlayDisplay.showsActivitySourceCue)
        XCTAssertTrue(report.overlayDisplay.identifier.contains("activity-source-policy:hidden"))
        XCTAssertFalse(report.activitySourceBeacon.isVisible)
        XCTAssertEqual(report.activitySourceBeacon.visibilityIdentifier, "hidden")
        XCTAssertEqual(report.activitySourceBeacon.kindIdentifier, "hidden")
        XCTAssertTrue(report.worldText.identifier.contains(report.worldText.questLabel))
        XCTAssertTrue(report.briefing.identifier.contains(report.briefing.title))

        let expectedBriefing = CinematicBriefingService.deterministicBriefing(
            for: CinematicBriefingInput(
                repoName: input.repoName,
                currentPhase: input.phase,
                immediatePlanTitle: input.immediateTitle,
                completedCount: input.completedCount,
                latestEvent: input.latestEvent
            )
        )
        let expectedWorldText = CinematicWorldTextService.deterministicWorldText(
            for: CinematicWorldTextInput(
                repoName: input.repoName,
                currentPhase: input.phase,
                immediatePlanTitle: input.immediateTitle,
                completedCount: input.completedCount,
                latestEvent: input.latestEvent,
                languageProfile: input.languageProfile,
                activityProfile: input.activityProfile
            )
        )

        XCTAssertEqual(report.briefing.title, expectedBriefing.title)
        XCTAssertEqual(report.briefing.detail, expectedBriefing.detail)
        XCTAssertEqual(report.worldText.questLabel, expectedWorldText.questLabel)
        XCTAssertEqual(report.worldText.arenaCallout, expectedWorldText.arenaCallout)
        XCTAssertEqual(report.worldText.activityCallout, expectedWorldText.activityCallout)
    }

    func testRepresentativeSmokeMatrixCoversLanguagesAndActivityStates() {
        let reports = CinematicDiagnostics.representativeSmokeMatrix()
        let expectedActivityCaseCount = CinematicDiagnostics.representativeActivityCases().count
        let expectedRecoveryCueCaseCount = CinematicRecoveryCuePlanner.representativePlans().count

        XCTAssertEqual(
            reports.count,
            RepositoryLanguage.allCases.count * expectedActivityCaseCount * expectedRecoveryCueCaseCount
        )
        XCTAssertEqual(Set(reports.map(\.languageMotif.language)), Set(RepositoryLanguage.allCases))
        XCTAssertEqual(
            Set(reports.map(\.activityMotif.eventKindIdentifier)),
            Set(CinematicActivityEventKind.allCases.map(\.rawValue))
        )
        XCTAssertEqual(
            Set(reports.map(\.languageMotif.sigilIdentifier)).count,
            RepositoryLanguage.allCases.count
        )
        XCTAssertEqual(
            Set(reports.map(\.activityMotif.sigilIdentifier)),
            Set(CinematicActivityEventKind.allCases.map { "activity.\($0.rawValue)" })
        )
        XCTAssertEqual(
            Set(reports.map(\.setDressing.backdropTextureRouteIdentifier)),
            CinematicTextureAssetCatalog.expectedRouteIdentifiers(for: .backdrop)
        )
        XCTAssertEqual(
            Set(reports.map(\.setDressing.backdropTextureName)),
            CinematicTextureAssetCatalog.generatedBackdropNames
        )
        XCTAssertEqual(
            Set(reports.map(\.setDressing.arenaTextureRouteIdentifier)),
            CinematicTextureAssetCatalog.expectedRouteIdentifiers(for: .arena)
        )
        XCTAssertEqual(
            Set(reports.map(\.setDressing.arenaTextureName)),
            CinematicTextureAssetCatalog.generatedArenaNames
        )
        XCTAssertEqual(
            Set(reports.map(\.setDressing.pedestalLayoutIdentifier)),
            CinematicSetDressingGeometryCatalog.expectedPedestalLayoutIdentifiers
        )
        XCTAssertEqual(
            Set(reports.map(\.setDressing.shardFormationIdentifier)),
            CinematicSetDressingGeometryCatalog.expectedShardFormationIdentifiers
        )
        XCTAssertTrue(
            reports.allSatisfy {
                $0.setDressing.pedestalSlotCount == CinematicSetDressingPlan.pedestalCountRange.upperBound
                    && $0.setDressing.shardSlotCount == CinematicSetDressingPlan.shardCountRange.upperBound
                    && $0.setDressing.layoutGeometryIsBounded
            }
        )
        XCTAssertEqual(
            Set(reports.map(\.setDressing.runeMaterialIdentifier)),
            CinematicRuneMaterialTreatmentCatalog.expectedRuneMaterialIdentifiers
        )
        XCTAssertEqual(
            Set(reports.map(\.setDressing.runeMaterialTreatmentIdentifier)),
            CinematicRuneMaterialTreatmentCatalog.expectedTreatmentIdentifiers
        )
        XCTAssertTrue(
            reports.allSatisfy {
                CinematicTextureAssetCatalog.recognizes($0.setDressing.backdropTextureName, role: .backdrop)
                    && CinematicTextureAssetCatalog.recognizes($0.setDressing.arenaTextureName, role: .arena)
                    && CinematicTextureAssetCatalog.isGeneratedBackdropTextureName($0.setDressing.backdropTextureName)
                    && CinematicTextureAssetCatalog.isGeneratedArenaTextureName($0.setDressing.arenaTextureName)
                    && CinematicTextureAssetCatalog.isPackagedResourceAvailable(
                        $0.setDressing.backdropTextureName,
                        role: .backdrop
                    )
                    && CinematicTextureAssetCatalog.isPackagedResourceAvailable(
                        $0.setDressing.arenaTextureName,
                        role: .arena
                    )
                    && !$0.setDressing.usesFallbackTextureAsset
            }
        )
        XCTAssertTrue(
            Set(reports.map(\.activityTuning.pressureLevelIdentifier))
                .isSuperset(of: ["clean", "light", "moderate", "heavy"])
        )
        XCTAssertTrue(
            Set(reports.map(\.stageEffect.pressureLevelIdentifier))
                .isSuperset(of: ["clean", "light", "moderate", "heavy"])
        )
        XCTAssertTrue(
            Set(reports.map(\.stageAtmosphere.pressureLevelIdentifier))
                .isSuperset(of: ["clean", "light", "moderate", "heavy"])
        )
        XCTAssertTrue(
            Set(reports.map(\.stagePhasePolish.postureIdentifier))
                .isSuperset(of: ["neutral", "editing", "sealing", "archival", "fracture", "healing"])
        )
        XCTAssertEqual(
            Set(reports.map(\.recoveryCue.kindIdentifier)),
            Set(["none", "failedVerify", "dirtyWorktree", "mutationTestingRecovery", "promotionFailed"])
        )
        XCTAssertEqual(
            Set(reports.map(\.recoveryCue.treatmentIdentifier)),
            Set(["none", "verify-failure", "dirty-cleanup", "mutation-recovery", "promotion-branch"])
        )
        XCTAssertTrue(
            Set(reports.map(\.timelineFocus.kindIdentifier))
                .isSuperset(of: ["none", "plan", "develop", "verify", "outcome", "commit", "recovery", "failed-verify"])
        )
        XCTAssertTrue(reports.contains { $0.timelineFocus.commitNodeIdentifier != nil })
        XCTAssertTrue(reports.contains { $0.timelineFocus.recoveryTreatmentIdentifier == "promotion-branch" })
        XCTAssertTrue(
            Set(reports.map(\.overlayDisplay.modeIdentifier))
                .isSuperset(of: ["full", "compact"])
        )
        XCTAssertTrue(reports.allSatisfy { !$0.overlayDisplay.chromeStyleIdentifier.isEmpty })
        XCTAssertTrue(
            Set(reports.map(\.overlayDisplay.chromeStyleIdentifier))
                .contains { $0.hasPrefix("compact-active|") || $0.hasPrefix("compact-readable|") }
        )
    }

    func testRepresentativeNativeFeedbackSmokeFixturesCoverRoutesAndLifecycle() throws {
        let reports = CinematicDiagnostics.representativeNativeFeedbackSmokeReports()
        let activeReports = reports.filter { $0.nativeFeedback.lifecycleStateIdentifier == "active" }
        let expiredReport = try XCTUnwrap(
            reports.first { $0.nativeFeedback.lifecycleStateIdentifier == "expired" }
        )

        XCTAssertEqual(reports.count, 7)
        XCTAssertEqual(activeReports.count, 6)
        XCTAssertEqual(
            Set(activeReports.map(\.nativeFeedback.styleIdentifier)),
            Set(["verify", "warning", "failure"])
        )
        XCTAssertTrue(activeReports.contains { $0.nativeFeedback.sourceIdentifier == "native:verifyStarted" })
        XCTAssertTrue(activeReports.contains { $0.nativeFeedback.sourceIdentifier == "native:postChecksFailed" })
        XCTAssertTrue(activeReports.contains { $0.nativeFeedback.sourceIdentifier == "plan-readiness:ready" })
        XCTAssertTrue(activeReports.contains { $0.nativeFeedback.sourceIdentifier == "plan-readiness:missing-metadata" })
        XCTAssertTrue(activeReports.contains { $0.nativeFeedback.sourceIdentifier == "run-cue:11:dirtyWorktree" })
        XCTAssertTrue(activeReports.contains { $0.nativeFeedback.sourceIdentifier == "run-cue:7:failedVerify" })
        XCTAssertEqual(
            Set(activeReports.flatMap(\.nativeFeedback.affectedNarrativeDescriptorIdentifiers)),
            Set([
                "narrative.quest.plaque",
                "narrative.arena.inscription",
                "narrative.activity.banner"
            ])
        )
        XCTAssertTrue(activeReports.contains { $0.narrativeCue.questPlaque.anchorIdentifier == "left-seal-pylon" })
        XCTAssertTrue(activeReports.contains { $0.narrativeCue.questPlaque.anchorIdentifier == "right-warning-pylon" })
        XCTAssertTrue(activeReports.contains { $0.narrativeCue.questPlaque.anchorIdentifier == "fracture-gate" })
        let verifyReport = try XCTUnwrap(
            activeReports.first { $0.nativeFeedback.sourceIdentifier == "native:verifyStarted" }
        )
        let failedReport = try XCTUnwrap(
            activeReports.first { $0.nativeFeedback.sourceIdentifier == "native:postChecksFailed" }
        )
        let warningReport = try XCTUnwrap(
            activeReports.first { $0.nativeFeedback.sourceIdentifier == "run-cue:11:dirtyWorktree" }
        )
        let retryReport = try XCTUnwrap(
            activeReports.first { $0.nativeFeedback.sourceIdentifier == "run-cue:7:failedVerify" }
        )
        let readinessReport = try XCTUnwrap(
            activeReports.first { $0.nativeFeedback.sourceIdentifier == "plan-readiness:ready" }
        )
        let readinessWarningReport = try XCTUnwrap(
            activeReports.first { $0.nativeFeedback.sourceIdentifier == "plan-readiness:missing-metadata" }
        )
        XCTAssertEqual(verifyReport.narrativeCue.questPlaque.plaqueTreatmentAccentIdentifier, "verify-seal")
        XCTAssertEqual(verifyReport.narrativeCue.questPlaque.plaqueTreatmentRouteIdentifier, "verifyStarted.verify")
        XCTAssertEqual(
            verifyReport.narrativeCue.questPlaque.plaqueTreatmentRenderPrimitiveIdentifiers,
            ["rail.top", "rail.bottom", "seal.left", "seal.right"]
        )
        XCTAssertEqual(readinessReport.narrativeCue.questPlaque.plaqueTreatmentAccentIdentifier, "verify-seal")
        XCTAssertEqual(readinessReport.narrativeCue.questPlaque.plaqueTreatmentRouteIdentifier, "developReady.verify")
        XCTAssertEqual(
            readinessReport.narrativeCue.questPlaque.plaqueTreatmentRenderPrimitiveIdentifiers,
            ["rail.top", "rail.bottom", "seal.left", "seal.right"]
        )
        XCTAssertEqual(
            readinessWarningReport.narrativeCue.questPlaque.plaqueTreatmentAccentIdentifier,
            "warning-rails"
        )
        XCTAssertEqual(
            readinessWarningReport.narrativeCue.questPlaque.plaqueTreatmentRouteIdentifier,
            "developReady.warning"
        )
        XCTAssertEqual(
            readinessWarningReport.narrativeCue.questPlaque.plaqueTreatmentRenderPrimitiveIdentifiers,
            ["rail.top", "rail.bottom", "warning.left", "warning.right"]
        )
        XCTAssertEqual(failedReport.narrativeCue.questPlaque.plaqueTreatmentAccentIdentifier, "failure-fracture")
        XCTAssertEqual(failedReport.narrativeCue.questPlaque.plaqueTreatmentRouteIdentifier, "postChecksFailed.failure")
        XCTAssertEqual(
            failedReport.narrativeCue.questPlaque.plaqueTreatmentRenderPrimitiveIdentifiers,
            ["rail.top", "rail.bottom", "fracture.diagonal.a", "fracture.diagonal.b"]
        )
        XCTAssertEqual(warningReport.narrativeCue.questPlaque.plaqueTreatmentAccentIdentifier, "warning-rails")
        XCTAssertEqual(warningReport.narrativeCue.questPlaque.plaqueTreatmentRouteIdentifier, "developRetrying.warning.dirtyWorktree")
        XCTAssertEqual(
            warningReport.narrativeCue.questPlaque.plaqueTreatmentRenderPrimitiveIdentifiers,
            ["rail.top", "rail.bottom", "warning.left", "warning.right"]
        )
        XCTAssertEqual(retryReport.narrativeCue.questPlaque.plaqueTreatmentAccentIdentifier, "retry-braces")
        XCTAssertEqual(retryReport.narrativeCue.questPlaque.plaqueTreatmentRouteIdentifier, "developRetrying.failure.failedVerify")
        XCTAssertEqual(
            retryReport.narrativeCue.questPlaque.plaqueTreatmentRenderPrimitiveIdentifiers,
            ["rail.top", "rail.bottom", "retry.brace.left", "retry.brace.right", "retry.cross"]
        )
        XCTAssertTrue(activeReports.allSatisfy {
            $0.narrativeCue.questPlaque.plaqueTreatmentAccentIdentifier
                == $0.narrativeCue.arenaInscription.plaqueTreatmentAccentIdentifier
                && $0.narrativeCue.questPlaque.plaqueTreatmentAccentIdentifier
                    == $0.narrativeCue.activityBanner.plaqueTreatmentAccentIdentifier
                && $0.narrativeCue.questPlaque.plaqueTreatmentRenderRecipeIdentifier
                    == $0.narrativeCue.arenaInscription.plaqueTreatmentRenderRecipeIdentifier
                && $0.narrativeCue.questPlaque.plaqueTreatmentRenderRecipeIdentifier
                    == $0.narrativeCue.activityBanner.plaqueTreatmentRenderRecipeIdentifier
                && $0.narrativeCue.questPlaque.plaqueTreatmentRenderPrimitiveCount
                    == $0.narrativeCue.questPlaque.plaqueTreatmentRenderPrimitiveIdentifiers.count
                && $0.narrativeCue.questPlaque.identifier.contains($0.narrativeCue.questPlaque.plaqueTreatmentIdentifier)
        })
        XCTAssertTrue(
            activeReports.allSatisfy {
                $0.nativeFeedback.cueIdentifier == $0.overlayDisplay.nativeFeedbackCueIdentifier
                    && $0.nativeFeedback.cueIdentifier == $0.narrativeCue.nativeFeedbackCueIdentifier
                    && $0.nativeFeedback.lifecycleActiveCueIdentifier == $0.nativeFeedback.cueIdentifier
                    && $0.overlayDisplay.showsNativeFeedbackBanner
                    && $0.overlayDisplay.nativeFeedbackBannerPolicyIdentifier == "visible"
            }
        )
        XCTAssertEqual(expiredReport.nativeFeedback.cueIdentifier, "none")
        XCTAssertEqual(expiredReport.nativeFeedback.lifecycleActiveCueIdentifier, "none")
        XCTAssertEqual(expiredReport.nativeFeedback.lifecycleRecentArchiveCount, 1)
        XCTAssertTrue(expiredReport.nativeFeedback.lifecycleRecentArchiveIdentifiers.first?.contains("reason:expired") == true)
        XCTAssertEqual(expiredReport.overlayDisplay.nativeFeedbackCueIdentifier, "none")
        XCTAssertFalse(expiredReport.overlayDisplay.showsNativeFeedbackBanner)
        XCTAssertEqual(expiredReport.overlayDisplay.nativeFeedbackBannerPolicyIdentifier, "none")

        let smoke = CinematicVisualSmokeReport(reports: reports)
        let nativeFeedbackCheck = try XCTUnwrap(
            smoke.checks.first { $0.id == "native-feedback-cue-coverage" }
        )
        let nativeFeedbackTreatmentCheck = try XCTUnwrap(
            smoke.checks.first { $0.id == "native-feedback-treatment-coverage" }
        )
        XCTAssertEqual(nativeFeedbackCheck.status, .pass)
        XCTAssertTrue(nativeFeedbackCheck.detail.contains("active 6"))
        XCTAssertTrue(nativeFeedbackCheck.detail.contains("routes fracture,seal,warning"))
        XCTAssertTrue(nativeFeedbackCheck.detail.contains("expired 1"))
        XCTAssertEqual(nativeFeedbackTreatmentCheck.status, .pass)
        XCTAssertTrue(nativeFeedbackTreatmentCheck.detail.contains("accents 4/4"))
        XCTAssertTrue(nativeFeedbackTreatmentCheck.detail.contains("prims 6/6"))
        XCTAssertTrue(nativeFeedbackTreatmentCheck.detail.contains("routes 6/6"))
        XCTAssertTrue(nativeFeedbackTreatmentCheck.detail.contains("pairs 6/6"))
        XCTAssertTrue(nativeFeedbackTreatmentCheck.detail.contains("surfaces 6/6"))
        XCTAssertTrue(nativeFeedbackTreatmentCheck.detail.contains("params 6/6"))
    }

    func testReportAndSummaryExportSelectedRecoveryCue() throws {
        let recoveryCuePlan = try XCTUnwrap(
            CinematicRecoveryCuePlanner.representativePlans().first {
                $0.selectedKindIdentifier == "promotionFailed"
            }
        )
        let report = CinematicDiagnostics.report(
            repoName: "Compass",
            phase: LoopPhase.failed.rawValue,
            immediateTitle: "Resolve promotion failure",
            completedCount: 4,
            latestEvent: nil,
            languageProfile: languageProfile(primaryLanguage: .swift),
            activityProfile: activityProfile(recentCommitCount: 2),
            influenceSettings: CinematicInfluenceSettings(),
            recoveryCuePlan: recoveryCuePlan
        )

        XCTAssertEqual(report.recoveryCue.kindIdentifier, "promotionFailed")
        XCTAssertEqual(report.recoveryCue.treatmentIdentifier, "promotion-branch")
        XCTAssertEqual(report.recoveryCue.lightFamilyIdentifier, "git")
        XCTAssertEqual(report.recoveryCue.symbolIdentifier, "git-failure-branch")
        XCTAssertEqual(report.stageEffect.recoveryArenaEffectIdentifier, "history-chains")
        XCTAssertEqual(report.stagePhasePolish.recoveryCueKindIdentifier, "promotionFailed")
        XCTAssertEqual(report.stagePhasePolish.staffOrbLightFamilyIdentifier, "git")
        XCTAssertEqual(report.stagePhasePolish.fractureLightFamilyIdentifier, "git")

        let summary = CinematicDiagnosticsSummary(
            report: report,
            visualSmoke: CinematicVisualSmokeReport(reports: [report])
        )
        XCTAssertTrue(summary.rows.contains { $0.id == "recovery-cue" })
        XCTAssertTrue(summary.exportText.contains("Recovery cue: promotionFailed"))
        XCTAssertTrue(summary.exportText.contains("git-failure-branch"))
    }

    func testMutationRecoveryCueFeedsDiagnosticsAttentionAndWarningBundleCopy() throws {
        let recoveryCuePlan = CinematicRecoveryCuePlanner.plan(
            recentRunCues: [
                22: diagnosticsRunCue(
                    kind: .mutationTestingRecovery,
                    severity: .failure,
                    label: "Review Mutation",
                    detail: "mutation failure tail",
                    systemImage: "testtube.2"
                )
            ]
        )
        let report = CinematicDiagnostics.report(
            repoName: "Compass",
            phase: LoopPhase.failed.rawValue,
            immediateTitle: "Review mutation recovery",
            completedCount: 4,
            latestEvent: nil,
            languageProfile: languageProfile(primaryLanguage: .swift),
            activityProfile: activityProfile(recentCommitCount: 2),
            influenceSettings: CinematicInfluenceSettings(comfortMode: .quiet),
            recoveryCuePlan: recoveryCuePlan
        )

        XCTAssertEqual(report.recoveryCue.kindIdentifier, "mutationTestingRecovery")
        XCTAssertEqual(report.recoveryCue.treatmentIdentifier, "mutation-recovery")
        XCTAssertEqual(report.idleStoryCycle.targetKindIdentifier, "recovery-mutation")

        let summary = CinematicDiagnosticsSummary(
            report: report,
            visualSmoke: CinematicVisualSmokeReport(reports: [report])
        )
        let target = try XCTUnwrap(
            summary.attentionSummary.targets.first {
                $0.targetAnchorID == "diagnostics-row-recovery-cue"
            }
        )

        XCTAssertEqual(target.label, "Mutation recovery")
        XCTAssertEqual(target.relatedRowID, "recovery-cue")
        XCTAssertTrue(target.visibleWarningIdentifiers.contains("recovery-cue.mutation-testing-recovery"))
        XCTAssertTrue(target.copyText.contains("Read-only"))
        XCTAssertTrue(summary.exportText.contains("Mutation recovery -> recovery-cue-mutation-testing"))
    }

    func testReportAndSummaryExportSelectedTimelineFocus() throws {
        let commitConstellationPlan = CinematicTimelineSceneFocusPlanner.representativeCommitConstellationPlan()
        let focusPlan = CinematicTimelineSceneFocusPlanner.representativePlan(
            activityCaseIdentifier: "commit",
            recoveryCuePlan: .none,
            commitConstellationPlan: commitConstellationPlan
        )
        let descriptor = try XCTUnwrap(focusPlan.descriptor)
        let report = CinematicDiagnostics.report(
            repoName: "Compass",
            phase: LoopPhase.verifying.rawValue,
            immediateTitle: "Preview selected timeline beat",
            completedCount: 5,
            latestEvent: nil,
            languageProfile: languageProfile(primaryLanguage: .swift),
            activityProfile: activityProfile(recentCommitCount: 2),
            influenceSettings: CinematicInfluenceSettings(),
            commitConstellationPlan: commitConstellationPlan,
            timelineFocusPlan: focusPlan
        )

        XCTAssertTrue(report.timelineFocus.isActive)
        XCTAssertEqual(report.timelineFocus.kindIdentifier, "commit")
        XCTAssertEqual(report.timelineFocus.selectedBeatID, focusPlan.selectedBeatID)
        XCTAssertEqual(report.timelineFocus.descriptorIdentifier, descriptor.identifier)
        XCTAssertEqual(report.timelineFocus.commitNodeIdentifier, descriptor.commitNodeIdentifier)
        XCTAssertEqual(report.timelineFocus.cameraShotIdentifier, CinematicCameraShot.commitConstellation.identifier)
        XCTAssertEqual(report.timelineFocus.lightFamilyIdentifier, "git")
        XCTAssertTrue(report.identifier.contains(focusPlan.identifier))

        let summary = CinematicDiagnosticsSummary(
            report: report,
            visualSmoke: CinematicVisualSmokeReport(reports: [report])
        )
        let row = try XCTUnwrap(summary.rows.first { $0.id == "timeline-focus" })
        XCTAssertEqual(row.label, "Timeline focus")
        XCTAssertTrue(row.detail.contains("kind commit"))
        XCTAssertTrue(row.detail.contains("shot commit-constellation"))
        XCTAssertTrue(row.detail.contains(descriptor.commitNodeIdentifier ?? "missing-node"))
        XCTAssertTrue(summary.exportText.contains("Timeline focus:"))
        XCTAssertTrue(summary.exportText.contains(focusPlan.selectedBeatID ?? "missing-beat"))
    }

    func testReportAndSummaryExportIdleStoryCycleState() throws {
        let report = try XCTUnwrap(
            CinematicDiagnostics.representativeIdleStoryCycleSmokeReports().first {
                $0.idleStoryCycle.phaseIdentifier == "native-feedback-plaque"
            }
        )
        let summary = CinematicDiagnosticsSummary(
            report: report,
            visualSmoke: CinematicVisualSmokeReport(reports: [report])
        )
        let row = try XCTUnwrap(summary.rows.first { $0.id == "idle-story-cycle" })

        XCTAssertTrue(report.idleStoryCycle.isActive)
        XCTAssertEqual(report.idleStoryCycle.phaseIdentifier, "native-feedback-plaque")
        XCTAssertEqual(report.idleStoryCycle.suppressionReason, "none")
        XCTAssertNotEqual(report.idleStoryCycle.sourceDescriptorIdentifier, "none")
        XCTAssertTrue(report.idleStoryCycle.targetKindIdentifier.hasPrefix("native-feedback"))
        XCTAssertInRange(report.idleStoryCycle.cadence, CinematicIdleStoryCyclePlan.cadenceRange)
        XCTAssertInRange(report.idleStoryCycle.dwellDuration, CinematicIdleStoryCyclePlan.dwellDurationRange)
        XCTAssertInRange(
            report.idleStoryCycle.transitionDurationScale,
            CinematicIdleStoryCyclePlan.transitionDurationScaleRange
        )
        XCTAssertInRange(report.idleStoryCycle.targetBias, CinematicIdleStoryCyclePlan.targetBiasRange)
        XCTAssertInRange(report.idleStoryCycle.comfortDamping, CinematicIdleStoryCyclePlan.comfortDampingRange)
        XCTAssertNotEqual(report.idleStoryCycle.choreographyIdentifier, "none")
        XCTAssertNotEqual(report.idleStoryCycle.cameraPressureIdentifier, "none")
        XCTAssertTrue(report.idleStoryCycle.cameraTreatmentIdentifier.contains("pressure:"))
        XCTAssertNotEqual(report.idleStoryCycle.pulseHintIdentifier, "none")
        XCTAssertLessThanOrEqual(
            report.idleStoryCycle.phaseCopy.count,
            CinematicIdleStoryCyclePlan.phaseCopyMaxCharacters
        )
        XCTAssertTrue(report.identifier.contains("idle-story-cycle:"))
        XCTAssertTrue(row.detail.contains("active"))
        XCTAssertTrue(row.detail.contains("phase native-feedback-plaque"))
        XCTAssertTrue(row.detail.contains("camera shot:"))
        XCTAssertTrue(row.detail.contains("dwell"))
        XCTAssertTrue(row.detail.contains("transition"))
        XCTAssertTrue(row.detail.contains("pressure"))
        XCTAssertTrue(row.detail.contains("bias"))
        XCTAssertTrue(row.detail.contains("damping"))
        XCTAssertTrue(row.detail.contains("anchor anchor:"))
        XCTAssertTrue(summary.exportText.contains("Idle story cycle: active"))
        XCTAssertTrue(summary.exportText.contains("native-feedback-plaque"))
        XCTAssertTrue(summary.exportText.contains("pressure"))
        XCTAssertTrue(summary.exportText.contains("choreo"))

        let suppressed = try XCTUnwrap(
            CinematicDiagnostics.representativeIdleStoryCycleSmokeReports().first {
                !$0.idleStoryCycle.isActive
            }
        )
        let suppressedSummary = CinematicDiagnosticsSummary(
            report: suppressed,
            visualSmoke: CinematicVisualSmokeReport(reports: [suppressed])
        )
        XCTAssertEqual(suppressed.idleStoryCycle.suppressionReason, "live-follow")
        XCTAssertTrue(suppressedSummary.exportText.contains("Idle story cycle: empty live-follow"))
    }

    func testReportAndSummaryExportDiagnosticsWarningPulseMetadata() throws {
        var history = CinematicDiagnosticsWarningBundleHistory()
        history.record(
            CinematicDiagnosticsSummary.AttentionSummary(
                targets: [
                    warningAttentionTarget(
                        "idle-pulse-a",
                        warnings: ["visual-smoke.shared-warning", "visual-smoke.shared-warning"],
                        relatedRowID: "idle-story-cycle"
                    ),
                    warningAttentionTarget(
                        "idle-pulse-b",
                        warnings: ["visual-smoke.recap-artifact-commands"],
                        relatedRowID: "run-recap-share-artifact-commands"
                    )
                ]
            )
        )
        let report = CinematicDiagnostics.report(
            repoName: "Diagnostics Warning Pulse",
            phase: LoopPhase.succeeded.rawValue,
            immediateTitle: "Surface active diagnostics warning",
            completedCount: 1,
            latestEvent: nil,
            languageProfile: languageProfile(primaryLanguage: .swift),
            activityProfile: activityProfile(lastTerminalStatus: .succeeded),
            influenceSettings: CinematicInfluenceSettings(),
            diagnosticsWarningBundleHistory: history
        )
        let summary = CinematicDiagnosticsSummary(
            report: report,
            visualSmoke: CinematicVisualSmokeReport(reports: [report])
        )
        let row = try XCTUnwrap(summary.rows.first { $0.id == "idle-story-cycle" })

        XCTAssertEqual(report.idleStoryCycle.phaseIdentifier, "diagnostics-warning-pulse")
        XCTAssertEqual(report.idleStoryCycle.diagnosticsWarningWarningCount, 3)
        XCTAssertEqual(report.idleStoryCycle.diagnosticsWarningTargetCount, 2)
        XCTAssertEqual(report.idleStoryCycle.diagnosticsWarningIdentifiers, [
            "visual-smoke.shared-warning",
            "visual-smoke.recap-artifact-commands"
        ])
        XCTAssertEqual(report.idleStoryCycle.diagnosticsWarningRepeatedIdentifiers, [
            "visual-smoke.shared-warning"
        ])
        XCTAssertTrue(
            report.idleStoryCycle.diagnosticsWarningRelatedRowAnchors.contains(
                "diagnostics-row-run-recap-share-artifact-commands"
            )
        )
        XCTAssertTrue(row.detail.contains("diagnostics-warning-pulse"))
        XCTAssertTrue(row.detail.contains("warning-bundle"))
        XCTAssertTrue(row.detail.contains("visual-smoke.shared-warning"))
        XCTAssertTrue(summary.exportText.contains("Idle story cycle: active"))
        XCTAssertTrue(summary.exportText.contains("warning ids visual-smoke.shared-warning"))
        XCTAssertFalse(summary.exportText.contains("copy idle-pulse"))
    }

    func testReportAndSummaryExportSavedRecapArtifactTourState() throws {
        let report = try XCTUnwrap(
            CinematicDiagnostics.representativeSavedRecapArtifactTourSmokeReports().first {
                $0.runRecapShareArtifactTour.stateIdentifier == "pinned"
            }
        )
        let summary = CinematicDiagnosticsSummary(
            report: report,
            visualSmoke: CinematicVisualSmokeReport(reports: [report])
        )
        let row = try XCTUnwrap(summary.rows.first { $0.id == "run-recap-share-artifact-tour" })

        XCTAssertTrue(report.runRecapShareArtifactTour.isAvailable)
        XCTAssertEqual(report.runRecapShareArtifactTour.selectionSourceIdentifier, "pinned")
        XCTAssertEqual(report.runRecapShareArtifactTour.runtimeRouteCueStateIdentifier, "apple-container")
        XCTAssertEqual(report.runRecapShareArtifactTour.runtimeRouteCueCompactCopy, "Container")
        XCTAssertEqual(report.runRecapShareArtifactTour.runtimeRouteTreatmentAccentIdentifier, "container-blue")
        XCTAssertEqual(report.runRecapShareArtifactTour.mutationTestingCueAvailabilityIdentifier, "available")
        XCTAssertEqual(report.runRecapShareArtifactTour.mutationTestingTreatmentStateIdentifier, "succeeded")
        XCTAssertEqual(report.runRecapShareArtifactTour.mutationTestingTreatmentAccentIdentifier, "mutation-green")
        XCTAssertEqual(report.idleStoryCycle.phaseIdentifier, "saved-recap-artifact-tour")
        XCTAssertEqual(report.idleStoryCycle.cameraPressureIdentifier, "archive-tour")
        XCTAssertTrue(report.identifier.contains("run-recap-share-artifact-tour-state:pinned"))
        XCTAssertTrue(report.identifier.contains("run-recap-share-artifact-tour-runtime-route:apple-container"))
        XCTAssertTrue(report.identifier.contains("run-recap-share-artifact-tour-mutation:succeeded"))
        XCTAssertTrue(row.detail.contains("state pinned"))
        XCTAssertTrue(row.detail.contains("source pinned"))
        XCTAssertTrue(row.detail.contains("runtime route apple-container"))
        XCTAssertTrue(row.detail.contains("mutation succeeded"))
        XCTAssertTrue(summary.exportText.contains("Recap artifact tour: available"))
        XCTAssertTrue(summary.exportText.contains("state pinned"))
        XCTAssertTrue(summary.exportText.contains("route copy Container"))
        XCTAssertTrue(summary.exportText.contains("mutation succeeded"))
    }

    func testReportAndSummaryExportHeldSavedRecapArtifactTourState() throws {
        let report = try XCTUnwrap(
            CinematicDiagnostics.representativeSavedRecapArtifactTourSmokeReports().first {
                $0.runRecapShareArtifactTour.stateIdentifier == "held"
            }
        )
        let filteredHoldReport = try XCTUnwrap(
            CinematicDiagnostics.representativeSavedRecapArtifactTourSmokeReports().first {
                $0.runRecapShareArtifactTour.stateIdentifier == "filtered-hold"
            }
        )
        let summary = CinematicDiagnosticsSummary(
            report: report,
            visualSmoke: CinematicVisualSmokeReport(reports: [report, filteredHoldReport])
        )
        let row = try XCTUnwrap(summary.rows.first { $0.id == "run-recap-share-artifact-tour" })

        XCTAssertEqual(report.runRecapShareArtifactTour.savedTourHoldStateIdentifier, "held")
        XCTAssertEqual(report.runRecapShareArtifactTour.selectionSourceIdentifier, "held")
        XCTAssertEqual(report.runRecapShareArtifactTour.runtimeRouteCueStateIdentifier, "native")
        XCTAssertEqual(report.runRecapShareArtifactTour.runtimeRouteTreatmentAccentIdentifier, "native-green")
        XCTAssertEqual(report.runRecapShareArtifactTour.mutationTestingTreatmentStateIdentifier, "failed")
        XCTAssertEqual(report.runRecapShareArtifactTour.mutationTestingTreatmentAccentIdentifier, "mutation-red")
        XCTAssertEqual(filteredHoldReport.runRecapShareArtifactTour.savedTourHoldStateIdentifier, "filtered-hold")
        XCTAssertEqual(filteredHoldReport.runRecapShareArtifactTour.runtimeRouteCueStateIdentifier, "native-fallback")
        XCTAssertEqual(filteredHoldReport.runRecapShareArtifactTour.runtimeRouteTreatmentAccentIdentifier, "fallback-amber")
        XCTAssertTrue(report.identifier.contains("run-recap-share-artifact-tour-hold:held"))
        XCTAssertTrue(row.detail.contains("hold held"))
        XCTAssertTrue(row.detail.contains("runtime route native"))
        XCTAssertTrue(row.detail.contains("mutation failed"))
        XCTAssertTrue(summary.exportText.contains("hold held"))
        XCTAssertTrue(summary.exportText.contains("filtered-hold"))
        XCTAssertTrue(summary.exportText.contains("native-fallback"))
    }

    func testRunRecapSavedArtifactTourRuntimeRouteFallbackAttentionTargetIsBoundedAndSanitized() throws {
        let secret = "secret-runtime-route-value"
        let repoPath = "/Users/example/project/.devcontainer/devcontainer.json"
        let history = diagnosticsRuntimeRouteHistory(
            seed: "fallback-attention",
            runtimeRouteSection: diagnosticsRuntimeRouteSection(
                effectiveRoute: "native-macos",
                effectiveRouteTitle: "Native macOS",
                fallbackState: "fallback",
                supportClassification: "feature-based",
                phase: "Develop (\(repoPath))",
                extraLines: [
                    "- Runtime audit: \(repoPath)-\(secret)",
                    "- Visible support tokens: arg:TOKEN, feature:node",
                    "- Image label: \(secret)",
                    "- Workspace label: \(repoPath)"
                ]
            )
        )
        let selected = try XCTUnwrap(history.entries.first)
        let report = makeReport(
            CinematicDiagnosticsInput(
                repoName: "Compass",
                phase: "Developing",
                immediateTitle: "Inspect fallback tour route",
                completedCount: 2,
                latestEvent: nil,
                languageProfile: languageProfile(primaryLanguage: .swift),
                activityProfile: activityProfile(recentCommitCount: 1),
                influenceSettings: CinematicInfluenceSettings(),
                runRecapShareArtifactHistoryPlan: history,
                runRecapShareArtifactSavedTourHoldEntryIdentifier: selected.identifier
            )
        )
        let summary = CinematicDiagnosticsSummary(report: report)
        let target = try XCTUnwrap(
            summary.attentionSummary.targets.first {
                $0.targetAnchorID == "diagnostics-row-run-recap-share-artifact-tour"
            }
        )

        XCTAssertEqual(report.runRecapShareArtifactTour.runtimeRouteCueStateIdentifier, "native-fallback")
        XCTAssertEqual(target.relatedGroupID, "repository-context")
        XCTAssertEqual(target.relatedRowID, "run-recap-share-artifact-tour")
        XCTAssertEqual(target.label, "Tour route fallback")
        XCTAssertTrue(target.id.hasPrefix("run-recap-share-artifact-tour-route-native-fallback"))
        XCTAssertEqual(target.visibleWarningIdentifiers.first, "run-recap-share-artifact-tour-runtime-route.native-fallback")
        XCTAssertTrue(target.visibleWarningIdentifiers.contains { $0.contains(".cue-") })
        XCTAssertTrue(target.visibleWarningIdentifiers.contains { $0.contains(".selected-") })
        XCTAssertTrue(target.detail.contains("route Native fallback"))
        XCTAssertTrue(target.detail.contains("support feature-based"))
        XCTAssertTrue(target.detail.contains("selection held"))
        XCTAssertTrue(target.detail.contains("hold held"))
        XCTAssertTrue(target.detail.contains("selected \(selected.identifier)"))
        XCTAssertLessThanOrEqual(
            target.detail.count,
            CinematicDiagnosticsSummary.attentionSummaryDetailMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            target.copyText.count,
            CinematicDiagnosticsSummary.attentionTargetCopyMaxCharacters
        )
        XCTAssertTrue(target.copyText.contains("Route compact: Native fallback"))
        XCTAssertTrue(target.copyText.contains("Route detail: route native fallback"))
        XCTAssertTrue(target.copyText.contains("Selection source: held"))
        XCTAssertTrue(target.copyText.contains("Hold state: held"))
        XCTAssertTrue(target.copyText.contains("Selected artifact: \(selected.identifier)"))
        XCTAssertTrue(target.copyText.contains("Related row: run-recap-share-artifact-tour"))
        XCTAssertTrue(target.copyText.contains("Read-only: route cue snapshot only"))
        XCTAssertTrue(summary.exportText.contains("Tour route fallback -> \(target.id)"))
        XCTAssertTrue(summary.exportText.contains("anchor diagnostics-row-run-recap-share-artifact-tour"))
        XCTAssertTrue(summary.exportText.contains("related run-recap-share-artifact-tour"))
        XCTAssertTrue(summary.exportText.contains("run-recap-share-artifact-tour-runtime-route.native-fallback"))

        var warningHistory = CinematicDiagnosticsWarningBundleHistory()
        warningHistory.record(summary.attentionSummary)
        let entry = try XCTUnwrap(warningHistory.entries.first)
        XCTAssertTrue(entry.targetAnchors.contains("diagnostics-row-run-recap-share-artifact-tour"))
        XCTAssertTrue(entry.relatedRowAnchors.contains("diagnostics-row-run-recap-share-artifact-tour"))
        XCTAssertTrue(entry.warningIdentifiers.contains("run-recap-share-artifact-tour-runtime-route.native-fallback"))
        XCTAssertTrue(warningHistory.rollup.copyText.contains("diagnostics-row-run-recap-share-artifact-tour"))
        XCTAssertTrue(warningHistory.rollup.copyText.contains("run-recap-share-artifact-tour-runtime-route.native-fallback"))

        for leaked in [secret, repoPath, "arg:TOKEN", "feature:node"] {
            XCTAssertFalse(target.id.contains(leaked))
            XCTAssertFalse(target.detail.contains(leaked))
            XCTAssertFalse(target.copyText.contains(leaked))
            XCTAssertFalse(summary.exportText.contains(leaked))
            XCTAssertFalse(warningHistory.copyText.contains(leaked))
            XCTAssertFalse(warningHistory.rollup.copyText.contains(leaked))
        }
    }

    func testRunRecapSavedArtifactTourRuntimeRouteMissingCueAttentionTarget() throws {
        let history = diagnosticsRuntimeRouteHistory(seed: "missing-cue-attention")
        let selected = try XCTUnwrap(history.entries.first)
        let report = makeReport(
            CinematicDiagnosticsInput(
                repoName: "Compass",
                phase: "Developing",
                immediateTitle: "Inspect missing tour route cue",
                completedCount: 1,
                latestEvent: nil,
                languageProfile: languageProfile(primaryLanguage: .swift),
                activityProfile: activityProfile(recentCommitCount: 1),
                influenceSettings: CinematicInfluenceSettings(),
                runRecapShareArtifactHistoryPlan: history,
                runRecapShareArtifactSavedTourHoldEntryIdentifier: selected.identifier
            )
        )
        let summary = CinematicDiagnosticsSummary(report: report)
        let target = try XCTUnwrap(
            summary.attentionSummary.targets.first {
                $0.targetAnchorID == "diagnostics-row-run-recap-share-artifact-tour"
            }
        )

        XCTAssertEqual(report.runRecapShareArtifactTour.runtimeRouteCueStateIdentifier, "missing-cue")
        XCTAssertEqual(target.relatedRowID, "run-recap-share-artifact-tour")
        XCTAssertEqual(target.label, "Tour route cue missing")
        XCTAssertTrue(target.id.hasPrefix("run-recap-share-artifact-tour-route-missing-cue"))
        XCTAssertEqual(target.visibleWarningIdentifiers.first, "run-recap-share-artifact-tour-runtime-route.missing-cue")
        XCTAssertTrue(target.visibleWarningIdentifiers.contains("run-recap-share-artifact-tour-runtime-route.cue-missing"))
        XCTAssertTrue(target.detail.contains("state missing-cue"))
        XCTAssertTrue(target.detail.contains("route Missing cue"))
        XCTAssertTrue(target.detail.contains("selected \(selected.identifier)"))
        XCTAssertTrue(target.copyText.contains("Route compact: Missing cue"))
        XCTAssertTrue(target.copyText.contains("Route help: No runtime route cue was found"))
        XCTAssertLessThanOrEqual(
            target.copyText.count,
            CinematicDiagnosticsSummary.attentionTargetCopyMaxCharacters
        )
        XCTAssertTrue(summary.exportText.contains("Tour route cue missing -> \(target.id)"))
        XCTAssertTrue(summary.exportText.contains("run-recap-share-artifact-tour-runtime-route.missing-cue"))
    }

    func testRunRecapSavedArtifactTourRuntimeRouteAttentionIgnoresContainerNativeAndUnavailable() throws {
        let cases: [(String, String?, String)] = [
            (
                "apple",
                diagnosticsRuntimeRouteSection(
                    effectiveRoute: "apple-container",
                    effectiveRouteTitle: "Apple container",
                    fallbackState: "direct",
                    supportClassification: "image-routeable"
                ),
                "apple-container"
            ),
            (
                "native",
                diagnosticsRuntimeRouteSection(
                    effectiveRoute: "native-macos",
                    effectiveRouteTitle: "Native macOS",
                    fallbackState: "direct",
                    supportClassification: "not-inspected"
                ),
                "native"
            ),
            ("unavailable", nil, "missing-cue")
        ]

        for (seed, runtimeRouteSection, expectedRouteState) in cases {
            let history = seed == "unavailable"
                ? diagnosticsRuntimeRouteHistory(seed: seed, entries: [])
                : diagnosticsRuntimeRouteHistory(seed: seed, runtimeRouteSection: runtimeRouteSection)
            let report = makeReport(
                CinematicDiagnosticsInput(
                    repoName: "Compass",
                    phase: "Developing",
                    immediateTitle: "Ignore quiet tour route state",
                    completedCount: 1,
                    latestEvent: nil,
                    languageProfile: languageProfile(primaryLanguage: .swift),
                    activityProfile: activityProfile(recentCommitCount: 1),
                    influenceSettings: CinematicInfluenceSettings(),
                    runRecapShareArtifactHistoryPlan: history,
                    runRecapShareArtifactSavedTourHoldEntryIdentifier: history.entries.first?.identifier
                )
            )
            let summary = CinematicDiagnosticsSummary(report: report)

            XCTAssertEqual(report.runRecapShareArtifactTour.runtimeRouteCueStateIdentifier, expectedRouteState, seed)
            XCTAssertFalse(
                summary.attentionSummary.targets.contains {
                    $0.targetAnchorID == "diagnostics-row-run-recap-share-artifact-tour"
                },
                seed
            )
            XCTAssertFalse(
                summary.exportText.contains("run-recap-share-artifact-tour-runtime-route.\(expectedRouteState)"),
                seed
            )
        }
    }

    func testRunRecapSavedArtifactTourMutationCueDiagnosticsAreBoundedAndSanitized() throws {
        let secret = "secret-mutation-diagnostics-value"
        let repoPath = "/Users/example/project/.devcontainer/devcontainer.json"
        let containerToolPath = "/usr/local/bin/container"
        let composePath = "/Users/example/project/compose.override.yml"
        let history = diagnosticsRuntimeRouteHistory(
            seed: "mutation-cue-diagnostics",
            runtimeRouteSection: diagnosticsRuntimeRouteSection(
                effectiveRoute: "native-macos",
                effectiveRouteTitle: "Native macOS",
                fallbackState: "direct",
                supportClassification: "not-inspected"
            ),
            mutationTestingSection: """
            ## Mutation Tests

            - Mutation audit: mutation-audit \(repoPath) \(secret)
            - Status: failed (Failed)
            - Route: apple-container-route (Apple container)
            - Language: swift (Swift)
            - Seed command: swift test \(repoPath) \(containerToolPath) containerEnv=TOKEN=\(secret) build-arg=API_KEY=\(secret)
            - Exit code: exit 65
            - Duration: 2.5 s
            - Runtime route audit: runtime \(containerToolPath) \(composePath)
            - Runtime route correlation: route-diverged|fallback-not-required|mutation:apple-container-route|runtime:native-macos|\(secret)
            - Output tail: raw failure \(repoPath) \(containerToolPath) \(composePath) .devcontainer/devcontainer.json \(secret)
            """
        )
        let selected = try XCTUnwrap(history.entries.first)
        let report = makeReport(
            CinematicDiagnosticsInput(
                repoName: "Compass",
                phase: "Developing",
                immediateTitle: "Inspect mutation cue diagnostics",
                completedCount: 1,
                latestEvent: nil,
                languageProfile: languageProfile(primaryLanguage: .swift),
                activityProfile: activityProfile(recentCommitCount: 1),
                influenceSettings: CinematicInfluenceSettings(),
                runRecapShareArtifactHistoryPlan: history,
                runRecapShareArtifactSavedTourHoldEntryIdentifier: selected.identifier
            )
        )
        let summary = CinematicDiagnosticsSummary(report: report)
        let row = try XCTUnwrap(summary.rows.first { $0.id == "run-recap-share-artifact-tour" })
        let target = try XCTUnwrap(
            summary.attentionSummary.targets.first {
                $0.id.hasPrefix("run-recap-share-artifact-tour-mutation-runtime-route-diverged")
            }
        )
        let selectedFingerprint = MutationTestingPresentationSanitizer.fingerprint(selected.identifier)
        let correlationFingerprint = MutationTestingPresentationSanitizer.fingerprint(
            report.runRecapShareArtifactTour.mutationTestingCueRuntimeRouteCorrelationIdentifier
        )
        let exposedText = [
            report.identifier,
            row.detail,
            summary.exportText,
            target.id,
            target.detail,
            target.copyText,
            target.visibleWarningIdentifiers.joined(separator: "\n"),
            report.runRecapShareArtifactTour.mutationTestingCueIdentifier ?? "",
            report.runRecapShareArtifactTour.mutationTestingCueDetailCopy ?? "",
            report.runRecapShareArtifactTour.mutationTestingTreatmentIdentifier,
            report.runRecapShareArtifactTour.mutationTestingTreatmentHelpCopy
        ].joined(separator: "\n")

        XCTAssertEqual(report.runRecapShareArtifactTour.mutationTestingCueAvailabilityIdentifier, "available")
        XCTAssertEqual(report.runRecapShareArtifactTour.mutationTestingCueStatusIdentifier, "failed")
        XCTAssertEqual(report.runRecapShareArtifactTour.mutationTestingTreatmentStateIdentifier, "runtime-route-diverged")
        XCTAssertEqual(report.runRecapShareArtifactTour.mutationTestingTreatmentAccentIdentifier, "mutation-amber")
        XCTAssertTrue(row.detail.contains("mutation runtime-route-diverged"))
        XCTAssertTrue(summary.exportText.contains("mutation runtime-route-diverged"))
        XCTAssertEqual(target.relatedGroupID, "repository-context")
        XCTAssertEqual(target.relatedRowID, "run-recap-share-artifact-tour")
        XCTAssertEqual(target.targetAnchorID, "diagnostics-row-run-recap-share-artifact-tour")
        XCTAssertEqual(target.label, "Tour mutation route diverged")
        XCTAssertEqual(
            target.visibleWarningIdentifiers.first,
            "run-recap-share-artifact-tour-mutation-testing.runtime-route-diverged"
        )
        XCTAssertTrue(
            target.visibleWarningIdentifiers.contains(
                "run-recap-share-artifact-tour-mutation-testing.selected-\(selectedFingerprint)"
            )
        )
        XCTAssertTrue(
            target.visibleWarningIdentifiers.contains(
                "run-recap-share-artifact-tour-mutation-testing.corr-\(correlationFingerprint)"
            )
        )
        XCTAssertTrue(target.detail.contains("mutation runtime-route-diverged"))
        XCTAssertTrue(target.detail.contains("status failed"))
        XCTAssertTrue(target.detail.contains("selected fingerprint \(selectedFingerprint)"))
        XCTAssertTrue(target.copyText.contains("Mutation cue status: failed"))
        XCTAssertTrue(target.copyText.contains("Mutation treatment state: runtime-route-diverged"))
        XCTAssertTrue(target.copyText.contains("Route correlation: route-diverged"))
        XCTAssertTrue(target.copyText.contains("Selected artifact fingerprint: \(selectedFingerprint)"))
        XCTAssertTrue(target.copyText.contains("Related row: run-recap-share-artifact-tour"))
        XCTAssertTrue(target.copyText.contains("Read-only: mutation cue snapshot only"))
        XCTAssertTrue(summary.exportText.contains("Tour mutation route diverged -> \(target.id)"))
        XCTAssertTrue(summary.exportText.contains("anchor diagnostics-row-run-recap-share-artifact-tour"))
        XCTAssertTrue(summary.exportText.contains("related run-recap-share-artifact-tour"))
        XCTAssertTrue(
            summary.exportText.contains(
                "run-recap-share-artifact-tour-mutation-testing.runtime-route-diverged"
            )
        )
        XCTAssertLessThanOrEqual(
            row.detail.count,
            CinematicDiagnosticsSummary.detailMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            target.detail.count,
            CinematicDiagnosticsSummary.attentionSummaryDetailMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            target.copyText.count,
            CinematicDiagnosticsSummary.attentionTargetCopyMaxCharacters
        )

        var warningHistory = CinematicDiagnosticsWarningBundleHistory()
        warningHistory.record(summary.attentionSummary)
        let entry = try XCTUnwrap(warningHistory.entries.first)
        XCTAssertTrue(entry.targetAnchors.contains("diagnostics-row-run-recap-share-artifact-tour"))
        XCTAssertTrue(entry.relatedRowAnchors.contains("diagnostics-row-run-recap-share-artifact-tour"))
        XCTAssertTrue(
            entry.warningIdentifiers.contains(
                "run-recap-share-artifact-tour-mutation-testing.runtime-route-diverged"
            )
        )
        XCTAssertTrue(
            warningHistory.rollup.copyText.contains(
                "run-recap-share-artifact-tour-mutation-testing.runtime-route-diverged"
            )
        )
        for leaked in [
            secret,
            repoPath,
            containerToolPath,
            composePath,
            ".devcontainer/devcontainer.json",
            "containerEnv=TOKEN",
            "build-arg=API_KEY",
            "raw failure"
        ] {
            XCTAssertFalse(exposedText.contains(leaked), "Leaked mutation diagnostics text: \(leaked)")
            XCTAssertFalse(warningHistory.copyText.contains(leaked), "Leaked warning history text: \(leaked)")
            XCTAssertFalse(warningHistory.rollup.copyText.contains(leaked), "Leaked warning rollup text: \(leaked)")
        }
    }

    func testRunRecapSavedArtifactTourMutationTestingAttentionIgnoresQuietStates() throws {
        let cases: [(seed: String, mutationSection: String?, expectedState: String, entries: [CinematicRunRecapShareArtifactHistoryPlan.Entry]?)] = [
            (
                "succeeded",
                """
                ## Mutation Tests

                - Mutation audit: quiet-succeeded
                - Status: succeeded (Succeeded)
                - Route: apple-container-route (Apple container)
                - Language: swift (Swift)
                - Seed command: swift test
                - Exit code: exit 0
                - Duration: 1.1 s
                - Runtime route audit: quiet-runtime
                - Runtime route correlation: route-aligned|fallback-not-required|mutation:apple-container-route|runtime:apple-container
                - Output tail: mutation ok
                """,
                "succeeded",
                nil
            ),
            (
                "unknown",
                """
                ## Mutation Tests

                - Mutation audit: quiet-unknown
                - Status: cancelled (Cancelled)
                - Route: unknown (Unknown)
                - Language: swift (Swift)
                - Seed command: swift test
                - Exit code: exit unknown
                - Duration: unknown
                - Runtime route audit: quiet-runtime
                - Runtime route correlation: route-aligned|fallback-not-required|mutation:unknown|runtime:native-macos
                - Output tail: mutation inconclusive
                """,
                "unknown",
                nil
            ),
            ("missing", nil, "missing", nil),
            ("unavailable", nil, "missing", [])
        ]

        for testCase in cases {
            let history = diagnosticsRuntimeRouteHistory(
                seed: testCase.seed,
                mutationTestingSection: testCase.mutationSection,
                entries: testCase.entries
            )
            let report = makeReport(
                CinematicDiagnosticsInput(
                    repoName: "Compass",
                    phase: "Developing",
                    immediateTitle: "Ignore quiet tour mutation state",
                    completedCount: 1,
                    latestEvent: nil,
                    languageProfile: languageProfile(primaryLanguage: .swift),
                    activityProfile: activityProfile(recentCommitCount: 1),
                    influenceSettings: CinematicInfluenceSettings(),
                    runRecapShareArtifactHistoryPlan: history,
                    runRecapShareArtifactSavedTourHoldEntryIdentifier: history.entries.first?.identifier
                )
            )
            let summary = CinematicDiagnosticsSummary(report: report)

            XCTAssertEqual(
                report.runRecapShareArtifactTour.mutationTestingTreatmentStateIdentifier,
                testCase.expectedState,
                testCase.seed
            )
            XCTAssertTrue(summary.exportText.contains("mutation \(testCase.expectedState)"), testCase.seed)
            XCTAssertFalse(
                summary.attentionSummary.targets.contains {
                    $0.id.hasPrefix("run-recap-share-artifact-tour-mutation")
                },
                testCase.seed
            )
            XCTAssertFalse(
                summary.exportText.contains("run-recap-share-artifact-tour-mutation-testing.\(testCase.expectedState)"),
                testCase.seed
            )
        }
    }

    func testRepresentativeRunRecapArtifactCommandSmokeReportsCoverAvailabilityStates() throws {
        let reports = CinematicDiagnostics.representativeRunRecapArtifactCommandSmokeReports()
        let snapshots = reports.map(\.runRecapShareArtifactCommands)

        XCTAssertEqual(reports.count, 8)
        XCTAssertTrue(snapshots.contains { $0.historyAvailabilityReason == "available" })
        XCTAssertTrue(snapshots.contains { $0.historyAvailabilityReason == "command-smoke-unavailable" })
        XCTAssertTrue(snapshots.contains {
            $0.previewNoMatchAvailabilityReason == "no-matching-recap-share-artifacts"
        })
        XCTAssertTrue(snapshots.contains { $0.missingPinnedEntryCount > 0 })
        XCTAssertTrue(snapshots.contains { $0.filteredPinnedEntryCount > 0 })
        XCTAssertTrue(snapshots.contains { $0.tourSavedHoldStateIdentifier == "filtered-hold" })
        XCTAssertTrue(snapshots.contains {
            $0.comparisonPromotedHoldStateIdentifier == "retained-promoted-hold-target"
        })
        XCTAssertTrue(snapshots.contains {
            $0.comparisonPromotedHoldStateIdentifier == "filtered-promoted-hold-target"
        })
        XCTAssertTrue(reports.contains {
            $0.runRecapShareArtifactHistory.cleanupCandidateCount > 0
                && $0.runRecapShareArtifactCommands.omittedActionKindIdentifiers == ["cleanupOldArtifacts"]
        })
        XCTAssertTrue(snapshots.allSatisfy {
            $0.commandCount == CinematicRunRecapShareArtifactCommandPlan.commandLimit
                && $0.actionCount == CinematicRunRecapShareArtifactActionMenuPlan.actionLimit
                && $0.appLevelShortcutCollisionStateIdentifier == "clear"
                && $0.appLevelShortcutCollisionIdentifiers.isEmpty
                && $0.commandCount + $0.omittedActionKindIdentifiers.count == $0.actionCount
        })

        let smoke = CinematicVisualSmokeReport(reports: reports)
        let check = try XCTUnwrap(
            smoke.checks.first { $0.id == "run-recap-artifact-command-availability" }
        )
        XCTAssertEqual(check.status, .pass)
        XCTAssertTrue(check.detail.contains("available"))
        XCTAssertTrue(check.detail.contains("unavailable"))
        XCTAssertTrue(check.detail.contains("no-match"))
        XCTAssertTrue(check.detail.contains("stale-pin"))
        XCTAssertTrue(check.detail.contains("filtered-hold"))
        XCTAssertTrue(check.detail.contains("promoted-hold"))
        XCTAssertTrue(check.detail.contains("cleanup-omitted"))
        XCTAssertTrue(check.detail.contains("collisions clear"))
        XCTAssertTrue(check.detail.contains("bounded"))
    }

    func testReportContainsEveryCameraShotAndCameraTuningValue() throws {
        let settings = CinematicInfluenceSettings(cameraStyle: .steady, intensity: 0.25)
        let report = CinematicDiagnostics.representativeSmokeMatrix(influenceSettings: settings).first!

        XCTAssertEqual(
            report.cameraSnapshots.map(\.shotIdentifier),
            CinematicCameraShot.allCases.map(\.identifier)
        )
        let commitConstellationShot = try XCTUnwrap(
            report.cameraSnapshots.first { $0.shotIdentifier == CinematicCameraShot.commitConstellation.identifier }
        )
        XCTAssertEqual(
            commitConstellationShot.position,
            CinematicTuning.cameraPosition(for: .commitConstellation, settings: settings)
        )
        XCTAssertEqual(Set(report.cameraSnapshots.map(\.identifier)).count, CinematicCameraShot.allCases.count)
        XCTAssertEqual(report.cameraTuning.orbitScale, CinematicTuning.cameraOrbitScale(settings: settings))
        XCTAssertEqual(report.cameraTuning.pullbackScale, CinematicTuning.cameraPullbackScale(settings: settings))
        XCTAssertEqual(report.cameraTuning.heightOffset, CinematicTuning.cameraHeightOffset(settings: settings))
        XCTAssertEqual(
            report.cameraTuning.followResponsiveness,
            CinematicTuning.cameraFollowResponsiveness(settings: settings)
        )
        XCTAssertEqual(
            report.cameraTuning.followFieldOfView,
            CinematicTuning.cameraFollowFieldOfView(settings: settings)
        )
        XCTAssertEqual(report.cameraTuning.driftScale, CinematicTuning.cameraDriftScale(settings: settings))
        XCTAssertEqual(report.cameraTuning.shakeScale, CinematicTuning.cameraShakeScale(settings: settings))

        for (shot, snapshot) in zip(CinematicCameraShot.allCases, report.cameraSnapshots) {
            XCTAssertEqual(snapshot.shotIdentifier, shot.identifier)
            XCTAssertEqual(snapshot.position, CinematicTuning.cameraPosition(for: shot, settings: settings))
            XCTAssertEqual(
                snapshot.fieldOfView,
                CinematicTuning.cameraFieldOfView(for: shot, settings: settings),
                accuracy: 0.0001
            )
            XCTAssertEqual(
                snapshot.transitionDuration,
                CinematicTuning.cameraTransitionDuration(for: shot, settings: settings),
                accuracy: 0.0001
            )
            XCTAssertTrue(snapshot.identifier.hasPrefix("\(shot.identifier)|steady|0.2500|standard"))
        }
    }

    func testWorldTextAndBriefingStayWithinOverlayBounds() {
        let reports = CinematicDiagnostics.representativeSmokeMatrix(
            influenceSettings: CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 1)
        )

        for report in reports {
            assertWorldTextBounds(report.worldText, file: #filePath, line: #line)
            assertNarrativeCueBounds(report.narrativeCue, file: #filePath, line: #line)
            XCTAssertFalse(report.briefing.title.isEmpty)
            XCTAssertFalse(report.briefing.detail.isEmpty)
            XCTAssertLessThanOrEqual(report.briefing.title.count, CinematicBriefingService.titleMaxCharacters)
            XCTAssertLessThanOrEqual(report.briefing.detail.count, CinematicBriefingService.detailMaxCharacters)
        }
    }

    func testCameraAndActivityTuningStayInsideClampRanges() {
        let settingsSamples = [
            CinematicInfluenceSettings(cameraStyle: .steady, intensity: 0),
            CinematicInfluenceSettings(cameraStyle: .follow, intensity: CinematicInfluenceSettings.defaultIntensity),
            CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 1)
        ]

        for settings in settingsSamples {
            let reports = CinematicDiagnostics.representativeSmokeMatrix(influenceSettings: settings)
            for report in reports {
                XCTAssertInRange(report.cameraTuning.followFieldOfView, CinematicTuning.cameraFollowFieldOfViewRange)
                XCTAssertInRange(report.cameraTuning.shakeScale, CinematicTuning.cameraShakeScaleRange)
                XCTAssertFinite(report.cameraTuning.orbitScale)
                XCTAssertFinite(report.cameraTuning.pullbackScale)
                XCTAssertFinite(report.cameraTuning.heightOffset)
                XCTAssertFinite(report.cameraTuning.followResponsiveness)
                XCTAssertFinite(report.cameraTuning.driftScale)
                XCTAssertGreaterThan(report.cameraTuning.orbitScale, 0)
                XCTAssertGreaterThan(report.cameraTuning.pullbackScale, 0)
                XCTAssertGreaterThan(report.cameraTuning.followResponsiveness, 0)
                XCTAssertGreaterThan(report.cameraTuning.driftScale, 0)

                XCTAssertInRange(report.activityTuning.ambientSpawnCadence, CinematicTuning.ambientSpawnCadenceRange)
                XCTAssertInRange(report.activityTuning.ambientEnemyLimit, CinematicTuning.ambientEnemyLimitRange)
                XCTAssertInRange(report.activityTuning.activityLightBoost, CinematicTuning.activityLightBoostRange)
                XCTAssertFinite(report.activityTuning.activityPressureScale)
                XCTAssertGreaterThan(report.activityTuning.activityPressureScale, 0)

                assertStageEffectTuningBounds(report.stageEffect, file: #filePath, line: #line)
                assertStageAtmosphereBounds(report.stageAtmosphere, file: #filePath, line: #line)
                assertStagePhasePolishBounds(report.stagePhasePolish, file: #filePath, line: #line)

                for snapshot in report.cameraSnapshots {
                    XCTAssertFinite(snapshot.position)
                    XCTAssertInRange(snapshot.fieldOfView, CinematicTuning.cameraFieldOfViewRange)
                    XCTAssertGreaterThanOrEqual(snapshot.transitionDuration, 0.16)
                }
            }
        }
    }

    func testSummaryRowsAreDeterministicallyOrderedAndBounded() {
        let report = makeReport(
            CinematicDiagnosticsInput(
                repoName: "Compass Diagnostics Surface With A Deliberately Long Repository Name",
                phase: "Developing",
                immediateTitle: "Add current cinematic diagnostics export rows with a deliberately long title",
                completedCount: 7,
                latestEvent: nil,
                languageProfile: languageProfile(primaryLanguage: .swift),
                activityProfile: activityProfile(worktreeChanges: worktreeChanges(modified: 12)),
                influenceSettings: CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 0.9)
            )
        )

        let summary = CinematicDiagnosticsSummary(report: report)

        XCTAssertEqual(
            summary.rows.map(\.id),
            [
                "repository",
                "activity-source",
                "cinematic-scene-lifecycle",
                "immediate",
                "plan-compass-readiness",
                "plan-compass-verify-seal",
                "commit-constellation",
                "idle-story-cycle",
                "plan-compass-focus",
                "plan-compass-commands",
                "timeline-focus",
                "run-recap",
                "run-recap-share",
                "run-recap-share-artifact",
                "run-recap-share-artifact-history",
                "run-recap-share-artifact-sources",
                "run-recap-share-artifact-rollup",
                "run-recap-share-artifact-comparison",
                "run-recap-share-artifact-pins",
                "run-recap-share-artifact-tour",
                "run-recap-share-artifact-preview",
                "run-recap-share-artifact-commands",
                "run-recap-focus",
                "run-recap-end-card",
                "language-motif",
                "activity-motif",
                "recovery-cue",
                "stage-beat",
                "stage-effect",
                "effect-tuning",
                "effect-rings",
                "effect-pulses",
                "effect-history",
                "stage-atmosphere",
                "atmosphere-tints",
                "phase-polish",
                "narrative-cues",
                "narrative-layout",
                "overlay-display",
                "native-feedback-history",
                "native-feedback-delivery",
                "world-quest",
                "world-arena",
                "world-activity",
                "set-dressing",
                "textures",
                "activity-tuning",
                "camera-tuning",
                "camera-follow",
                "camera-shot-home",
                "camera-shot-wide",
                "camera-shot-cast-prep",
                "camera-shot-over-shoulder",
                "camera-shot-impact",
                "camera-shot-overhead",
                "camera-shot-commit-constellation"
            ]
        )
        XCTAssertEqual(summary.rows.count, CinematicDiagnosticsSummary.maxRows)
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
        XCTAssertEqual(
            summary.sections.map { $0.rows.map(\.id) },
            [
                [
                    "repository",
                    "activity-source",
                    "cinematic-scene-lifecycle",
                    "immediate",
                    "plan-compass-readiness",
                    "plan-compass-verify-seal",
                    "commit-constellation",
                    "idle-story-cycle",
                    "plan-compass-focus",
                    "plan-compass-commands",
                    "timeline-focus",
                    "run-recap",
                    "run-recap-share",
                    "run-recap-share-artifact",
                    "run-recap-share-artifact-history",
                    "run-recap-share-artifact-sources",
                    "run-recap-share-artifact-rollup",
                    "run-recap-share-artifact-comparison",
                    "run-recap-share-artifact-pins",
                    "run-recap-share-artifact-tour",
                    "run-recap-share-artifact-preview",
                    "run-recap-share-artifact-commands",
                    "run-recap-focus",
                    "run-recap-end-card"
                ],
                [
                    "language-motif",
                    "activity-motif"
                ],
                [
                    "recovery-cue",
                    "stage-beat",
                    "stage-effect",
                    "effect-rings",
                    "effect-pulses",
                    "effect-history",
                    "stage-atmosphere",
                    "atmosphere-tints",
                    "phase-polish"
                ],
                [
                    "narrative-cues",
                    "narrative-layout",
                    "overlay-display",
                    "native-feedback-history",
                    "native-feedback-delivery",
                    "world-quest",
                    "world-arena",
                    "world-activity"
                ],
                [
                    "set-dressing",
                    "textures"
                ],
                [
                    "effect-tuning",
                    "activity-tuning",
                    "camera-tuning",
                    "camera-follow"
                ],
                [
                    "camera-shot-home",
                    "camera-shot-wide",
                    "camera-shot-cast-prep",
                    "camera-shot-over-shoulder",
                    "camera-shot-impact",
                    "camera-shot-overhead",
                    "camera-shot-commit-constellation"
                ]
            ]
        )

        let sectionRowIDs = summary.sections.flatMap { $0.rows.map(\.id) }
        XCTAssertEqual(sectionRowIDs.count, summary.rows.count)
        XCTAssertEqual(Set(sectionRowIDs), Set(summary.rows.map(\.id)))
        XCTAssertEqual(Set(sectionRowIDs).count, sectionRowIDs.count)

        for row in summary.rows {
            XCTAssertLessThanOrEqual(row.label.count, CinematicDiagnosticsSummary.labelMaxCharacters)
            XCTAssertLessThanOrEqual(row.detail.count, CinematicDiagnosticsSummary.detailMaxCharacters)
            XCTAssertFalse(row.label.isEmpty)
            XCTAssertFalse(row.detail.isEmpty)
        }

        for section in summary.sections {
            XCTAssertLessThanOrEqual(section.label.count, CinematicDiagnosticsSummary.labelMaxCharacters)
            XCTAssertFalse(section.label.isEmpty)
            XCTAssertFalse(section.rows.isEmpty)
            XCTAssertEqual(section.rowCountLabel, "\(section.rows.count) rows")
        }
    }

    func testSummaryPresentationMetadataKeepsContextVisibleAndCollapsesDensePassingGroups() throws {
        let report = try XCTUnwrap(CinematicDiagnostics.representativeSmokeMatrix().first)
        let summary = CinematicDiagnosticsSummary(report: report)

        XCTAssertEqual(summary.defaultExpandedGroupStates["repository-context"], true)
        XCTAssertEqual(summary.defaultExpandedGroupStates["motifs"], true)
        XCTAssertEqual(summary.defaultExpandedGroupStates["narrative-overlay"], true)
        XCTAssertEqual(summary.defaultExpandedGroupStates["assets-textures"], true)
        XCTAssertEqual(summary.defaultExpandedGroupStates["tuning"], true)
        XCTAssertEqual(summary.defaultExpandedGroupStates["stage-motion-effects"], false)
        XCTAssertEqual(summary.defaultExpandedGroupStates["camera-shots"], false)
        XCTAssertEqual(summary.defaultExpandedGroupStates["visual-smoke"], false)
        XCTAssertEqual(summary.defaultExpandedGroupStates["plaque-treatment-legend"], false)

        for section in summary.sections {
            XCTAssertEqual(section.presentation.headerDetail, section.rowCountLabel)
            XCTAssertEqual(section.presentation.attentionState, .normal)
            XCTAssertEqual(section.presentation.warningIdentifiers, [])
            XCTAssertEqual(section.presentation.needsAttention, false)
            XCTAssertLessThanOrEqual(
                section.presentation.headerDetail.count,
                CinematicDiagnosticsSummary.headerDetailMaxCharacters
            )
        }
    }

    func testSummaryExportIncludesMotifSetDressingAndCameraIdentifiers() {
        let report = makeReport(
            CinematicDiagnosticsInput(
                repoName: "Compass",
                phase: "Verifying",
                immediateTitle: "Expose current diagnostics",
                completedCount: 3,
                latestEvent: CinematicBriefingEvent(
                    line: LiveLine(
                        level: .success,
                        text: "Verify passed",
                        detail: "swift test passed",
                        kind: .command,
                        status: .completed
                    )
                ),
                languageProfile: languageProfile(primaryLanguage: .swift),
                activityProfile: activityProfile(recentCommitCount: 2),
                influenceSettings: CinematicInfluenceSettings(cameraStyle: .steady, intensity: 0.2)
            )
        )

        let summary = CinematicDiagnosticsSummary(report: report)

        XCTAssertTrue(summary.exportText.hasPrefix("Cinematic Diagnostics\n"))
        XCTAssertTrue(summary.attentionSummary.isEmpty)
        XCTAssertEqual(summary.attentionSummary.targets, [])
        XCTAssertFalse(summary.exportText.contains("Warning summary"))
        XCTAssertEqual(
            summary.exportText.components(separatedBy: "\n").count,
            summary.rows.count
                + summary.sections.count
                + summary.visualSmoke.checks.count
                + summary.plaqueTreatmentLegend.rows.count
                + 4
        )
        let expectedSectionHeadings = summary.sections.map { "\($0.label) (\($0.rowCountLabel))" }
        let actualSectionHeadings = summary.exportText
            .components(separatedBy: "\n")
            .filter { expectedSectionHeadings.contains($0) }
        XCTAssertEqual(actualSectionHeadings, expectedSectionHeadings)
        XCTAssertTrue(summary.exportText.contains("Repository/context (24 rows)"))
        XCTAssertTrue(summary.exportText.contains("Motifs (2 rows)"))
        XCTAssertTrue(summary.exportText.contains("Stage motion/effects (9 rows)"))
        XCTAssertTrue(summary.exportText.contains("Narrative/overlay (8 rows)"))
        XCTAssertTrue(summary.exportText.contains("Assets/textures (2 rows)"))
        XCTAssertTrue(summary.exportText.contains("Tuning (4 rows)"))
        XCTAssertTrue(summary.exportText.contains("Camera shots (7 rows)"))
        XCTAssertTrue(summary.exportText.contains("Visual smoke (pass, 26 checks)"))
        XCTAssertTrue(summary.exportText.contains("Plaque treatments (pass, 4 recipes): smoke pass"))
        XCTAssertTrue(summary.exportText.contains("failure-fracture: accent failure-fracture"))
        XCTAssertTrue(summary.exportText.contains("Overlay fallback: pass"))
        XCTAssertTrue(summary.exportText.contains("Native feedback coverage: pass"))
        XCTAssertTrue(summary.exportText.contains("Native feedback treatment: pass"))
        XCTAssertTrue(summary.exportText.contains("Idle story cycle: pass"))
        XCTAssertTrue(summary.exportText.contains("Saved artifact tour: pass"))
        XCTAssertTrue(summary.exportText.contains(report.languageMotif.sigilIdentifier))
        XCTAssertTrue(summary.exportText.contains(report.languageMotif.styleIdentifier))
        XCTAssertTrue(summary.exportText.contains("Activity source:"))
        XCTAssertTrue(summary.exportText.contains("availability \(report.activitySource.sourceAvailabilityIdentifier)"))
        XCTAssertTrue(summary.exportText.contains("repo-local \(report.activitySource.repoLocalSessionsStateIdentifier)"))
        XCTAssertTrue(summary.exportText.contains("Scene lifecycle:"))
        XCTAssertTrue(summary.exportText.contains(report.cinematicSceneLifecycle.stateIdentifier))
        XCTAssertTrue(summary.exportText.contains(report.activityMotif.sigilIdentifier))
        XCTAssertTrue(summary.exportText.contains(report.activityMotif.styleIdentifier))
        XCTAssertTrue(summary.exportText.contains(report.stageBeat.kindIdentifier))
        XCTAssertTrue(summary.exportText.contains(report.stageBeat.cameraShotIdentifier))
        XCTAssertTrue(summary.exportText.contains(report.stageEffect.phaseArenaEffectIdentifier))
        XCTAssertTrue(summary.exportText.contains("Effect tuning:"))
        XCTAssertTrue(summary.exportText.contains(report.stageEffect.pressureLevelIdentifier))
        XCTAssertTrue(summary.exportText.contains(report.stageEffect.influenceStyleIdentifier))
        XCTAssertTrue(summary.exportText.contains(report.stageEffect.arenaRingIdentifiers[0]))
        XCTAssertTrue(summary.exportText.contains(report.stageEffect.phaseLightPulseIdentifiers[0]))
        XCTAssertTrue(summary.exportText.contains("Atmosphere:"))
        XCTAssertTrue(summary.exportText.contains("Atmosphere tints:"))
        XCTAssertTrue(summary.exportText.contains(report.stageAtmosphere.pressureHaloIdentifier))
        XCTAssertTrue(summary.exportText.contains(report.stageAtmosphere.floorTintIdentifier))
        XCTAssertTrue(summary.exportText.contains("Phase polish:"))
        XCTAssertTrue(summary.exportText.contains(report.stagePhasePolish.postureIdentifier))
        XCTAssertTrue(summary.exportText.contains(report.stagePhasePolish.staffOrbLightFamilyIdentifier))
        XCTAssertTrue(summary.exportText.contains(report.stagePhasePolish.cadenceIdentifier))
        XCTAssertTrue(summary.exportText.contains("Narrative cues:"))
        XCTAssertTrue(summary.exportText.contains("Narrative layout:"))
        XCTAssertTrue(summary.exportText.contains("Overlay display:"))
        XCTAssertTrue(summary.exportText.contains("mode \(report.overlayDisplay.modeIdentifier)"))
        XCTAssertTrue(summary.exportText.contains("chrome \(report.overlayDisplay.chromeStyleIdentifier)"))
        XCTAssertTrue(summary.exportText.contains("Native feedback delivery:"))
        XCTAssertTrue(summary.exportText.contains("notification-status not-requested"))
        XCTAssertTrue(summary.exportText.contains(report.narrativeCue.questPlaque.anchorIdentifier))
        XCTAssertTrue(summary.exportText.contains(report.narrativeCue.activityBanner.text))
        XCTAssertTrue(summary.exportText.contains(report.narrativeCue.arenaInscription.layout.facingModeIdentifier))
        XCTAssertTrue(summary.exportText.contains(report.narrativeCue.activityBanner.layout.glyphSideIdentifier))
        XCTAssertTrue(summary.exportText.contains(report.setDressing.languageArchitectureIdentifier))
        XCTAssertTrue(summary.exportText.contains(report.setDressing.activityMarkerIdentifier))
        XCTAssertTrue(summary.exportText.contains(report.setDressing.layoutGeometryCoverageIdentifier))
        XCTAssertTrue(summary.exportText.contains(report.setDressing.materialTextureVariantIdentifier))
        XCTAssertTrue(summary.exportText.contains(report.setDressing.backdropTextureAssetIdentifier))
        XCTAssertTrue(summary.exportText.contains(report.setDressing.arenaTextureAssetIdentifier))
        XCTAssertTrue(summary.exportText.contains(report.setDressing.textureRoleCoverageIdentifier))
        XCTAssertTrue(summary.exportText.contains(report.setDressing.runeMaterialIdentifier))
        XCTAssertTrue(summary.exportText.contains(report.setDressing.runeMaterialTreatmentIdentifier))
        XCTAssertTrue(summary.exportText.contains(report.setDressing.backdropTextureName))
        XCTAssertTrue(summary.exportText.contains(report.setDressing.arenaTextureName))
        XCTAssertTrue(summary.exportText.contains("backdrop generated"))
        XCTAssertTrue(summary.exportText.contains("arena generated"))
        XCTAssertTrue(summary.exportText.contains("backdrop packaged"))
        XCTAssertTrue(summary.exportText.contains("arena packaged"))
        XCTAssertTrue(summary.exportText.contains(report.cameraTuning.identifier))
        XCTAssertTrue(summary.exportText.contains(report.cameraSnapshots[0].identifier))
        XCTAssertTrue(summary.exportText.contains(report.cameraSnapshots[3].shotIdentifier))
    }

    func testActivitySourceDiagnosticsRowAndIdentifierTrackActiveStorageSource() throws {
        let repoURL = URL(fileURLWithPath: "/tmp/CompassActivitySourceDiagnostics")
        let supportRoot = repoURL
            .appending(path: "Application Support", directoryHint: .isDirectory)
            .appending(path: "Compass", directoryHint: .isDirectory)
        let supportSnapshot = RepositoryActivitySourceSnapshot(
            activeStorage: .applicationSupport,
            storageRootURL: supportRoot,
            sessionsRecordURL: supportRoot.appending(path: "sessions.json"),
            sourceAvailability: .available,
            repoLocalSessionsRecordURL: repoURL
                .appending(path: ".compass", directoryHint: .isDirectory)
                .appending(path: "sessions.json"),
            repoLocalSessionsState: .ignoredMissing
        )
        let staleRepoLocalSnapshot = RepositoryActivitySourceSnapshot(
            activeStorage: .applicationSupport,
            storageRootURL: supportRoot,
            sessionsRecordURL: supportRoot.appending(path: "sessions.json"),
            sourceAvailability: .available,
            repoLocalSessionsRecordURL: repoURL
                .appending(path: ".compass", directoryHint: .isDirectory)
                .appending(path: "sessions.json"),
            repoLocalSessionsState: .ignoredCompatible
        )
        let movedRootSnapshot = RepositoryActivitySourceSnapshot(
            activeStorage: .applicationSupport,
            storageRootURL: supportRoot.appending(path: "Moved", directoryHint: .isDirectory),
            sessionsRecordURL: supportRoot
                .appending(path: "Moved", directoryHint: .isDirectory)
                .appending(path: "sessions.json"),
            sourceAvailability: .available,
            repoLocalSessionsRecordURL: repoURL
                .appending(path: ".compass", directoryHint: .isDirectory)
                .appending(path: "sessions.json"),
            repoLocalSessionsState: .ignoredMissing
        )
        let report = makeReport(
            CinematicDiagnosticsInput(
                repoName: "Compass",
                phase: "Developing",
                immediateTitle: "Expose active storage activity diagnostics",
                completedCount: 2,
                latestEvent: nil,
                languageProfile: languageProfile(primaryLanguage: .swift),
                activityProfile: activityProfile(recentCommitCount: 1),
                activitySourceSnapshot: supportSnapshot,
                influenceSettings: CinematicInfluenceSettings()
            )
        )
        let staleReport = makeReport(
            CinematicDiagnosticsInput(
                repoName: "Compass",
                phase: "Developing",
                immediateTitle: "Expose active storage activity diagnostics",
                completedCount: 2,
                latestEvent: nil,
                languageProfile: languageProfile(primaryLanguage: .swift),
                activityProfile: activityProfile(recentCommitCount: 1),
                activitySourceSnapshot: staleRepoLocalSnapshot,
                influenceSettings: CinematicInfluenceSettings()
            )
        )
        let movedReport = makeReport(
            CinematicDiagnosticsInput(
                repoName: "Compass",
                phase: "Developing",
                immediateTitle: "Expose active storage activity diagnostics",
                completedCount: 2,
                latestEvent: nil,
                languageProfile: languageProfile(primaryLanguage: .swift),
                activityProfile: activityProfile(recentCommitCount: 1),
                activitySourceSnapshot: movedRootSnapshot,
                influenceSettings: CinematicInfluenceSettings()
            )
        )
        let summary = CinematicDiagnosticsSummary(report: report)
        let row = try XCTUnwrap(summary.row(id: "activity-source"))

        XCTAssertEqual(report.activitySource, supportSnapshot)
        XCTAssertTrue(report.identifier.contains("activity-source:\(supportSnapshot.identifier)"))
        XCTAssertEqual(report.overlayDisplay.activitySourceCueKindIdentifier, "application-support-active")
        XCTAssertEqual(report.overlayDisplay.activitySourceCuePolicyIdentifier, "visible")
        XCTAssertEqual(report.overlayDisplay.activitySourceCueSeverityIdentifier, "info")
        XCTAssertEqual(report.overlayDisplay.activitySourceCueTintIdentifier, "blue")
        XCTAssertTrue(report.overlayDisplay.showsActivitySourceCue)
        XCTAssertTrue(report.activitySourceBeacon.isVisible)
        XCTAssertEqual(report.activitySourceBeacon.visibilityIdentifier, "visible")
        XCTAssertEqual(report.activitySourceBeacon.kindIdentifier, "application-support-active")
        XCTAssertEqual(report.activitySourceBeacon.lightFamilyIdentifier, "scan")
        XCTAssertEqual(report.activitySourceBeacon.arenaEffectIdentifier, "seal")
        XCTAssertEqual(report.activitySourceBeacon.cameraShotIdentifier, "cast-prep")
        XCTAssertLessThanOrEqual(
            report.activitySourceBeacon.identifier.count,
            CinematicActivitySourceBeaconPlan.identifierLimit
        )
        XCTAssertTrue(report.identifier.contains("activity-source-beacon-visibility:visible"))
        XCTAssertTrue(report.identifier.contains("overlay-activity-source-policy:visible"))
        XCTAssertTrue(report.overlayDisplay.identifier.contains("activity-source-policy:visible"))
        XCTAssertNotEqual(report.identifier, staleReport.identifier)
        XCTAssertNotEqual(report.identifier, movedReport.identifier)
        XCTAssertTrue(row.detail.contains("storage application_support"))
        XCTAssertTrue(row.detail.contains("availability available"))
        XCTAssertTrue(row.detail.contains("repo-local ignored-missing"))
        XCTAssertTrue(row.detail.contains("repo-local-mode ignored"))
        XCTAssertTrue(row.detail.contains("sessions.json"))
        XCTAssertFalse(row.detail.contains("source-beacon"))
        XCTAssertLessThanOrEqual(row.detail.count, CinematicDiagnosticsSummary.detailMaxCharacters)
        XCTAssertTrue(summary.exportText.contains("Activity source:"))
        XCTAssertTrue(summary.exportText.contains("storage application_support"))
        XCTAssertTrue(summary.exportText.contains("repo-local ignored-missing"))
        XCTAssertTrue(summary.exportText.contains("source-cue visible"))
        XCTAssertTrue(summary.exportText.contains("source-kind application-support-active"))
        XCTAssertTrue(summary.exportText.contains("source-severity info"))
    }

    func testQuietModeSuppressesAvailableActivitySourceCueButKeepsWarningsVisibleInDiagnostics() {
        let repoURL = URL(fileURLWithPath: "/tmp/CompassActivitySourceCueDiagnostics")
        let supportRoot = repoURL
            .appending(path: "Application Support", directoryHint: .isDirectory)
            .appending(path: "Compass", directoryHint: .isDirectory)
        let supportAvailable = RepositoryActivitySourceSnapshot(
            activeStorage: .applicationSupport,
            storageRootURL: supportRoot,
            sessionsRecordURL: supportRoot.appending(path: "sessions.json"),
            sourceAvailability: .available,
            repoLocalSessionsRecordURL: repoURL
                .appending(path: ".compass", directoryHint: .isDirectory)
                .appending(path: "sessions.json"),
            repoLocalSessionsState: .ignoredCompatible
        )
        let missingActiveRecord = RepositoryActivitySourceSnapshot(
            activeStorage: .applicationSupport,
            storageRootURL: supportRoot,
            sessionsRecordURL: supportRoot.appending(path: "sessions.json"),
            sourceAvailability: .sessionsRecordMissing,
            repoLocalSessionsRecordURL: repoURL
                .appending(path: ".compass", directoryHint: .isDirectory)
                .appending(path: "sessions.json"),
            repoLocalSessionsState: .ignoredMissing
        )
        let quietSettings = CinematicInfluenceSettings(
            cameraStyle: .follow,
            comfortMode: .quiet,
            intensity: 0.4
        )

        let quietSupportReport = makeReport(
            CinematicDiagnosticsInput(
                repoName: "Compass",
                phase: "Developing",
                immediateTitle: "Dampen noncritical source cues",
                completedCount: 1,
                latestEvent: nil,
                languageProfile: languageProfile(primaryLanguage: .swift),
                activityProfile: activityProfile(recentCommitCount: 1),
                activitySourceSnapshot: supportAvailable,
                influenceSettings: quietSettings
            )
        )
        let quietMissingReport = makeReport(
            CinematicDiagnosticsInput(
                repoName: "Compass",
                phase: "Developing",
                immediateTitle: "Keep source warnings visible",
                completedCount: 1,
                latestEvent: nil,
                languageProfile: languageProfile(primaryLanguage: .swift),
                activityProfile: activityProfile(recentCommitCount: 1),
                activitySourceSnapshot: missingActiveRecord,
                influenceSettings: quietSettings
            )
        )
        let supportSummary = CinematicDiagnosticsSummary(report: quietSupportReport)
        let missingSummary = CinematicDiagnosticsSummary(report: quietMissingReport)

        XCTAssertFalse(quietSupportReport.overlayDisplay.showsActivitySourceCue)
        XCTAssertEqual(
            quietSupportReport.overlayDisplay.activitySourceCuePolicyIdentifier,
            "suppressed-quiet-noncritical"
        )
        XCTAssertEqual(quietSupportReport.overlayDisplay.activitySourceCueSeverityIdentifier, "info")
        XCTAssertFalse(quietSupportReport.activitySourceBeacon.isVisible)
        XCTAssertEqual(
            quietSupportReport.activitySourceBeacon.visibilityIdentifier,
            "suppressed-quiet-noncritical"
        )
        XCTAssertEqual(quietSupportReport.activitySourceBeacon.suppressionReason, "quiet-noncritical")
        XCTAssertTrue(supportSummary.exportText.contains("source-cue suppressed-quiet-noncritical"))
        XCTAssertTrue(supportSummary.exportText.contains("source-visible no"))
        XCTAssertFalse(
            supportSummary.attentionSummary.targets.contains {
                $0.targetAnchorID == "diagnostics-row-activity-source"
            }
        )

        XCTAssertTrue(quietMissingReport.overlayDisplay.showsActivitySourceCue)
        XCTAssertEqual(quietMissingReport.overlayDisplay.activitySourceCuePolicyIdentifier, "visible-warning")
        XCTAssertEqual(quietMissingReport.overlayDisplay.activitySourceCueSeverityIdentifier, "warning")
        XCTAssertEqual(quietMissingReport.overlayDisplay.activitySourceCueTintIdentifier, "orange")
        XCTAssertTrue(quietMissingReport.activitySourceBeacon.isVisible)
        XCTAssertTrue(quietMissingReport.activitySourceBeacon.isCritical)
        XCTAssertEqual(quietMissingReport.activitySourceBeacon.visibilityIdentifier, "visible-warning")
        XCTAssertEqual(quietMissingReport.activitySourceBeacon.lightFamilyIdentifier, "pressure")
        XCTAssertEqual(quietMissingReport.idleStoryCycle.phaseIdentifier, "activity-source-beacon")
        XCTAssertTrue(missingSummary.exportText.contains("source-cue visible-warning"))
        XCTAssertTrue(missingSummary.exportText.contains("source-visible yes"))
        XCTAssertTrue(missingSummary.exportText.contains("availability sessions-record-missing"))
        XCTAssertTrue(missingSummary.exportText.contains("source-beacon visible-warning/application-support-unavailable"))
        let sourceTarget = missingSummary.attentionSummary.targets.first {
            $0.targetAnchorID == "diagnostics-row-activity-source"
        }
        XCTAssertEqual(sourceTarget?.id, "activity-source-application-support-unavailable-sessions-record-missing")
        XCTAssertEqual(sourceTarget?.targetGroupID, "repository-context")
        XCTAssertEqual(sourceTarget?.relatedGroupID, "repository-context")
        XCTAssertEqual(sourceTarget?.relatedRowID, "activity-source")
        XCTAssertEqual(sourceTarget?.visibleWarningIdentifiers, ["activity-source.source.sessions-record-missing"])
        XCTAssertTrue(sourceTarget?.detail.contains("cue policy visible-warning") ?? false)
        XCTAssertTrue(sourceTarget?.detail.contains("beacon visible-warning/application-support-unavailable") ?? false)
    }

    func testActivitySourceWarningAttentionTargetExportsBoundedCopyAndRollupAnchors() throws {
        let repoURL = URL(fileURLWithPath: "/tmp/CompassActivitySourceAttention")
        let supportRoot = repoURL
            .appending(path: "Application Support", directoryHint: .isDirectory)
            .appending(path: "Compass", directoryHint: .isDirectory)
        let missingSnapshot = RepositoryActivitySourceSnapshot(
            activeStorage: .applicationSupport,
            storageRootURL: supportRoot,
            sessionsRecordURL: supportRoot.appending(path: "sessions.json"),
            sourceAvailability: .sessionsRecordMissing,
            repoLocalSessionsRecordURL: repoURL
                .appending(path: ".compass", directoryHint: .isDirectory)
                .appending(path: "sessions.json"),
            repoLocalSessionsState: .ignoredMissing
        )
        let report = makeReport(
            CinematicDiagnosticsInput(
                repoName: "Compass",
                phase: "Developing",
                immediateTitle: "Drill into missing activity source diagnostics",
                completedCount: 1,
                latestEvent: nil,
                languageProfile: languageProfile(primaryLanguage: .swift),
                activityProfile: activityProfile(recentCommitCount: 1),
                activitySourceSnapshot: missingSnapshot,
                influenceSettings: CinematicInfluenceSettings()
            )
        )
        let summary = CinematicDiagnosticsSummary(report: report)
        let target = try XCTUnwrap(
            summary.attentionSummary.targets.first {
                $0.targetAnchorID == "diagnostics-row-activity-source"
            }
        )

        XCTAssertEqual(target.id, "activity-source-application-support-unavailable-sessions-record-missing")
        XCTAssertEqual(target.targetGroupID, "repository-context")
        XCTAssertEqual(target.targetAnchorID, "diagnostics-row-activity-source")
        XCTAssertEqual(target.relatedGroupID, "repository-context")
        XCTAssertEqual(target.relatedRowID, "activity-source")
        XCTAssertEqual(target.label, "Activity record missing")
        XCTAssertEqual(target.warningCount, 1)
        XCTAssertEqual(target.visibleWarningIdentifiers, ["activity-source.source.sessions-record-missing"])
        XCTAssertLessThanOrEqual(target.detail.count, CinematicDiagnosticsSummary.attentionSummaryDetailMaxCharacters)
        XCTAssertTrue(target.detail.contains("storage application_support"))
        XCTAssertTrue(target.detail.contains("availability sessions-record-missing"))
        XCTAssertTrue(target.detail.contains("repo-local ignored-missing"))
        XCTAssertTrue(target.detail.contains("cue policy visible-warning"))
        XCTAssertTrue(target.detail.contains("beacon visible-warning/application-support-unavailable"))

        XCTAssertLessThanOrEqual(target.copyText.count, CinematicDiagnosticsSummary.attentionTargetCopyMaxCharacters)
        XCTAssertTrue(target.copyText.contains("Cinematic diagnostics warning target"))
        XCTAssertTrue(target.copyText.contains("Target anchor: diagnostics-row-activity-source"))
        XCTAssertTrue(target.copyText.contains("Target group: repository-context"))
        XCTAssertTrue(target.copyText.contains("Warnings: activity-source.source.sessions-record-missing"))
        XCTAssertTrue(target.copyText.contains("Storage kind: application_support"))
        XCTAssertTrue(target.copyText.contains("Availability: sessions-record-missing"))
        XCTAssertTrue(target.copyText.contains("Repo-local state: ignored-missing"))
        XCTAssertTrue(target.copyText.contains("Sessions path:"))
        XCTAssertTrue(target.copyText.contains("Repo-local sessions path:"))
        XCTAssertTrue(target.copyText.contains("Cue policy: visible-warning"))
        XCTAssertTrue(target.copyText.contains("Beacon visibility: visible-warning"))
        XCTAssertTrue(target.copyText.contains("Related row: activity-source"))
        XCTAssertFalse(target.copyText.contains("Cinematic Diagnostics\nReport:"))
        XCTAssertFalse(target.copyText.contains("Visual smoke (warning,"))

        XCTAssertTrue(summary.exportText.contains("Warning summary (1 target)"))
        XCTAssertTrue(summary.exportText.contains("Activity record missing -> \(target.id)"))
        XCTAssertTrue(summary.exportText.contains("anchor diagnostics-row-activity-source"))
        XCTAssertTrue(summary.exportText.contains("related activity-source"))
        XCTAssertTrue(summary.exportText.contains("activity-source.source.sessions-record-missing"))

        var history = CinematicDiagnosticsWarningBundleHistory()
        history.record(summary.attentionSummary)
        let entry = try XCTUnwrap(history.entries.first)
        XCTAssertEqual(entry.targetIdentifiers, [target.id])
        XCTAssertEqual(entry.warningIdentifiers, ["activity-source.source.sessions-record-missing"])
        XCTAssertEqual(entry.targetAnchors, ["diagnostics-row-activity-source"])
        XCTAssertEqual(entry.relatedRowAnchors, ["diagnostics-row-activity-source"])
        XCTAssertTrue(history.rollup.copyText.contains("diagnostics-row-activity-source"))
    }

    func testActivitySourceAttentionIgnoresOrdinaryAndNoncriticalSupportStates() {
        let repoURL = URL(fileURLWithPath: "/tmp/CompassActivitySourceAttentionOrdinary")
        let supportRoot = repoURL
            .appending(path: "Application Support", directoryHint: .isDirectory)
            .appending(path: "Compass", directoryHint: .isDirectory)
        let ordinaryRepoLocal = RepositoryActivitySourceSnapshot(
            activeStorage: .repoLocal,
            storageRootURL: repoURL.appending(path: ".compass", directoryHint: .isDirectory),
            sessionsRecordURL: repoURL
                .appending(path: ".compass", directoryHint: .isDirectory)
                .appending(path: "sessions.json"),
            sourceAvailability: .available,
            repoLocalSessionsRecordURL: repoURL
                .appending(path: ".compass", directoryHint: .isDirectory)
                .appending(path: "sessions.json"),
            repoLocalSessionsState: .activeSource
        )
        let supportAvailable = RepositoryActivitySourceSnapshot(
            activeStorage: .applicationSupport,
            storageRootURL: supportRoot,
            sessionsRecordURL: supportRoot.appending(path: "sessions.json"),
            sourceAvailability: .available,
            repoLocalSessionsRecordURL: repoURL
                .appending(path: ".compass", directoryHint: .isDirectory)
                .appending(path: "sessions.json"),
            repoLocalSessionsState: .ignoredCompatible
        )

        for snapshot in [ordinaryRepoLocal, supportAvailable] {
            let report = makeReport(
                CinematicDiagnosticsInput(
                    repoName: "Compass",
                    phase: "Developing",
                    immediateTitle: "Keep ordinary source state out of warning summary",
                    completedCount: 1,
                    latestEvent: nil,
                    languageProfile: languageProfile(primaryLanguage: .swift),
                    activityProfile: activityProfile(recentCommitCount: 1),
                    activitySourceSnapshot: snapshot,
                    influenceSettings: CinematicInfluenceSettings()
                )
            )
            let summary = CinematicDiagnosticsSummary(report: report)

            XCTAssertFalse(
                summary.attentionSummary.targets.contains {
                    $0.targetAnchorID == "diagnostics-row-activity-source"
                }
            )
            XCTAssertFalse(summary.exportText.contains("activity-source.source."))
            XCTAssertFalse(summary.exportText.contains("activity-source.repo-local.ignored-compatible"))
        }
    }

    func testActivitySourceAttentionIncludesActionableIgnoredRepoLocalState() throws {
        let repoURL = URL(fileURLWithPath: "/tmp/CompassActivitySourceAttentionIgnored")
        let supportRoot = repoURL
            .appending(path: "Application Support", directoryHint: .isDirectory)
            .appending(path: "Compass", directoryHint: .isDirectory)
        let ignoredUnreadable = RepositoryActivitySourceSnapshot(
            activeStorage: .applicationSupport,
            storageRootURL: supportRoot,
            sessionsRecordURL: supportRoot.appending(path: "sessions.json"),
            sourceAvailability: .available,
            repoLocalSessionsRecordURL: repoURL
                .appending(path: ".compass", directoryHint: .isDirectory)
                .appending(path: "sessions.json"),
            repoLocalSessionsState: .ignoredUnreadable
        )
        let quietSettings = CinematicInfluenceSettings(
            cameraStyle: .follow,
            comfortMode: .quiet,
            intensity: 0.4
        )
        let report = makeReport(
            CinematicDiagnosticsInput(
                repoName: "Compass",
                phase: "Developing",
                immediateTitle: "Surface ignored repo-local source diagnostics",
                completedCount: 1,
                latestEvent: nil,
                languageProfile: languageProfile(primaryLanguage: .swift),
                activityProfile: activityProfile(recentCommitCount: 1),
                activitySourceSnapshot: ignoredUnreadable,
                influenceSettings: quietSettings
            )
        )
        let summary = CinematicDiagnosticsSummary(report: report)
        let target = try XCTUnwrap(
            summary.attentionSummary.targets.first {
                $0.targetAnchorID == "diagnostics-row-activity-source"
            }
        )

        XCTAssertFalse(report.overlayDisplay.showsActivitySourceCue)
        XCTAssertEqual(report.overlayDisplay.activitySourceCuePolicyIdentifier, "suppressed-quiet-noncritical")
        XCTAssertFalse(report.activitySourceBeacon.isVisible)
        XCTAssertEqual(report.activitySourceBeacon.visibilityIdentifier, "suppressed-quiet-noncritical")
        XCTAssertEqual(target.id, "activity-source-application-support-active-ignored-unreadable")
        XCTAssertEqual(target.label, "Repo sessions ignored")
        XCTAssertEqual(target.visibleWarningIdentifiers, ["activity-source.repo-local.ignored-unreadable"])
        XCTAssertTrue(target.detail.contains("availability available"))
        XCTAssertTrue(target.detail.contains("repo-local ignored-unreadable"))
        XCTAssertTrue(target.detail.contains("cue policy suppressed-quiet-noncritical"))
        XCTAssertTrue(target.detail.contains("beacon suppressed-quiet-noncritical/application-support-active"))
        XCTAssertTrue(target.copyText.contains("Repo-local state: ignored-unreadable"))
        XCTAssertTrue(target.copyText.contains("Cue policy: suppressed-quiet-noncritical"))
        XCTAssertTrue(target.copyText.contains("Beacon visibility: suppressed-quiet-noncritical"))
        XCTAssertTrue(summary.exportText.contains("activity-source.repo-local.ignored-unreadable"))
    }

    func testRunRecapSourceReconciliationAttentionTargetsActionableStatesAndExport() throws {
        let activeHistory = diagnosticsSourceHistory(seed: "active", sessions: [20])
        let actionableCases: [(CinematicRunRecapShareArtifactHistoryPlan, CinematicRunRecapShareArtifactSourceReconciliationPlan, String, String)] = [
            (
                activeHistory,
                diagnosticsSourceReconciliation(
                    active: activeHistory,
                    repoLocal: diagnosticsSourceHistory(seed: "active", sessions: [21, 20])
                ),
                "repo-local-extra",
                "Repo-local has extras"
            ),
            (
                CinematicRunRecapShareArtifactHistoryPlan.unavailable(
                    reason: "storage-root-missing",
                    storageRootURL: URL(fileURLWithPath: "/tmp/source-attention/support/.compass"),
                    sessionsURL: URL(fileURLWithPath: "/tmp/source-attention/support/.compass/sessions")
                ),
                diagnosticsSourceReconciliation(
                    active: CinematicRunRecapShareArtifactHistoryPlan.unavailable(
                        reason: "storage-root-missing",
                        storageRootURL: URL(fileURLWithPath: "/tmp/source-attention/support/.compass"),
                        sessionsURL: URL(fileURLWithPath: "/tmp/source-attention/support/.compass/sessions")
                    ),
                    repoLocal: diagnosticsSourceHistory(seed: "repo-local-available", sessions: [33])
                ),
                "active-missing-repo-local-available",
                "Active source missing"
            ),
            (
                diagnosticsSourceHistory(seed: "scan-active", sessions: [41]),
                diagnosticsSourceReconciliation(
                    active: diagnosticsSourceHistory(seed: "scan-active", sessions: [41]),
                    repoLocal: diagnosticsSourceHistory(
                        seed: "scan-warning",
                        sessions: [],
                        availabilityReason: "no-recap-share-artifacts",
                        warnings: ["recap-share-artifact-history.warning.corrupt"]
                    )
                ),
                "scan-warnings",
                "Artifact scan warning"
            )
        ]

        for (activeHistory, reconciliation, state, label) in actionableCases {
            let report = makeReport(
                CinematicDiagnosticsInput(
                    repoName: "Compass",
                    phase: "Developing",
                    immediateTitle: "Surface recap source reconciliation warning",
                    completedCount: 1,
                    latestEvent: nil,
                    languageProfile: languageProfile(primaryLanguage: .swift),
                    activityProfile: activityProfile(recentCommitCount: 1),
                    activitySourceSnapshot: diagnosticsSourceActivitySnapshot(),
                    influenceSettings: CinematicInfluenceSettings(),
                    runRecapShareArtifactHistoryPlan: activeHistory,
                    runRecapShareArtifactSourceReconciliationPlan: reconciliation
                )
            )
            let summary = CinematicDiagnosticsSummary(report: report)
            let target = try XCTUnwrap(
                summary.attentionSummary.targets.first {
                    $0.targetAnchorID == "diagnostics-row-run-recap-share-artifact-sources"
                },
                state
            )

            XCTAssertEqual(target.targetGroupID, "repository-context", state)
            XCTAssertEqual(target.relatedGroupID, "repository-context", state)
            XCTAssertEqual(target.relatedRowID, "run-recap-share-artifact-sources", state)
            XCTAssertEqual(target.label, label, state)
            XCTAssertLessThanOrEqual(
                target.detail.count,
                CinematicDiagnosticsSummary.attentionSummaryDetailMaxCharacters,
                state
            )
            XCTAssertLessThanOrEqual(
                target.copyText.count,
                CinematicDiagnosticsSummary.attentionTargetCopyMaxCharacters,
                state
            )
            XCTAssertTrue(target.visibleWarningIdentifiers.first?.hasPrefix("run-recap-share-artifact-sources.\(state)") ?? false, state)
            XCTAssertTrue(target.detail.contains("state \(state)"), state)
            XCTAssertTrue(target.detail.contains("active total \(reconciliation.activeTotalCount)"), state)
            XCTAssertTrue(target.detail.contains("repo-local total \(reconciliation.repoLocalTotalCount)"), state)
            XCTAssertTrue(target.detail.contains("warnings active \(reconciliation.activeWarningCount) repo-local \(reconciliation.repoLocalWarningCount)"), state)
            XCTAssertTrue(target.detail.contains("activity-source"), state)
            XCTAssertTrue(target.copyText.contains("Cinematic diagnostics warning target"), state)
            XCTAssertTrue(target.copyText.contains("Target anchor: diagnostics-row-run-recap-share-artifact-sources"), state)
            XCTAssertTrue(target.copyText.contains("Reconciliation state: \(state)"), state)
            XCTAssertTrue(target.copyText.contains("Active total: \(reconciliation.activeTotalCount)"), state)
            XCTAssertTrue(target.copyText.contains("Repo-local total: \(reconciliation.repoLocalTotalCount)"), state)
            XCTAssertTrue(target.copyText.contains("Warning counts: active \(reconciliation.activeWarningCount), repo-local \(reconciliation.repoLocalWarningCount)"), state)
            XCTAssertTrue(target.copyText.contains("Active sessions path:"), state)
            XCTAssertTrue(target.copyText.contains("Repo-local sessions path:"), state)
            XCTAssertTrue(target.copyText.contains("Activity source:"), state)
            XCTAssertTrue(target.copyText.contains("Related row: run-recap-share-artifact-sources"), state)
            XCTAssertTrue(target.copyText.contains("Related detail:"), state)
            XCTAssertTrue(target.copyText.contains("Read-only: diagnostics capture only"), state)
            XCTAssertFalse(target.copyText.contains("Cinematic Diagnostics\nReport:"), state)

            if state == "repo-local-extra" {
                XCTAssertTrue(target.detail.contains("repo-local extra ids"), state)
                XCTAssertTrue(target.copyText.contains("Representative repo-local extra ids: artifact-active-session:21"), state)
            }

            XCTAssertTrue(summary.exportText.contains("Warning summary"), state)
            XCTAssertTrue(summary.exportText.contains("\(label) -> \(target.id)"), state)
            XCTAssertTrue(summary.exportText.contains("anchor diagnostics-row-run-recap-share-artifact-sources"), state)
            XCTAssertTrue(summary.exportText.contains("related run-recap-share-artifact-sources"), state)
            XCTAssertTrue(summary.exportText.contains(target.visibleWarningIdentifiers[0]), state)
            XCTAssertEqual(summary.relatedRow(for: CinematicVisualSmokeReport.Check.WarningTarget(
                id: target.id,
                targetGroupID: target.targetGroupID,
                targetAnchorID: target.targetAnchorID,
                relatedGroupID: target.relatedGroupID,
                relatedRowID: target.relatedRowID,
                label: target.label,
                detail: target.detail
            ))?.id, "run-recap-share-artifact-sources", state)
        }
    }

    func testRunRecapSourceReconciliationAttentionOrdersAfterActivitySourceAndFeedsWarningHistory() throws {
        let activitySource = diagnosticsSourceActivitySnapshot(
            availability: .sessionsRecordMissing,
            repoLocalState: .ignoredMissing
        )
        let activeHistory = diagnosticsSourceHistory(seed: "ordered-active", sessions: [20])
        let reconciliation = diagnosticsSourceReconciliation(
            active: activeHistory,
            repoLocal: diagnosticsSourceHistory(seed: "ordered-active", sessions: [21, 20]),
            activitySource: activitySource
        )
        let report = makeReport(
            CinematicDiagnosticsInput(
                repoName: "Compass",
                phase: "Developing",
                immediateTitle: "Order recap source reconciliation warnings",
                completedCount: 1,
                latestEvent: nil,
                languageProfile: languageProfile(primaryLanguage: .swift),
                activityProfile: activityProfile(recentCommitCount: 1),
                activitySourceSnapshot: activitySource,
                influenceSettings: CinematicInfluenceSettings(),
                runRecapShareArtifactHistoryPlan: activeHistory,
                runRecapShareArtifactSourceReconciliationPlan: reconciliation
            )
        )
        let summary = CinematicDiagnosticsSummary(report: report)

        XCTAssertEqual(
            Array(summary.attentionSummary.targets.prefix(2).map(\.targetAnchorID)),
            [
                "diagnostics-row-activity-source",
                "diagnostics-row-run-recap-share-artifact-sources"
            ]
        )
        let sourceTarget = try XCTUnwrap(
            summary.attentionSummary.targets.first {
                $0.targetAnchorID == "diagnostics-row-run-recap-share-artifact-sources"
            }
        )
        XCTAssertEqual(sourceTarget.visibleWarningIdentifiers.first, "run-recap-share-artifact-sources.repo-local-extra")

        var history = CinematicDiagnosticsWarningBundleHistory()
        history.record(summary.attentionSummary)
        let entry = try XCTUnwrap(history.entries.first)

        XCTAssertEqual(
            Array(entry.targetAnchors.prefix(2)),
            [
                "diagnostics-row-activity-source",
                "diagnostics-row-run-recap-share-artifact-sources"
            ]
        )
        XCTAssertTrue(entry.warningIdentifiers.contains("activity-source.source.sessions-record-missing"))
        XCTAssertTrue(entry.warningIdentifiers.contains("run-recap-share-artifact-sources.repo-local-extra"))
        XCTAssertTrue(entry.relatedRowAnchors.contains("diagnostics-row-run-recap-share-artifact-sources"))
        XCTAssertTrue(history.rollup.copyText.contains("diagnostics-row-run-recap-share-artifact-sources"))
        XCTAssertTrue(history.rollup.copyText.contains("run-recap-share-artifact-sources.repo-local-extra"))
        XCTAssertLessThanOrEqual(
            history.rollup.copyText.count,
            CinematicDiagnosticsWarningBundleHistory.copyTextMaxCharacters
        )
    }

    func testRunRecapSourceReconciliationAttentionIgnoresQuietStates() {
        let activeOnly = CinematicRunRecapShareArtifactSourceReconciliationPlanner.plan(
            activeHistoryPlan: diagnosticsSourceHistory(seed: "repo-local-active", sessions: [4]),
            activitySourceSnapshot: .notScanned(activeStorage: .repoLocal)
        )
        let sharedHistory = diagnosticsSourceHistory(seed: "compatible", sessions: [11])
        let compatible = diagnosticsSourceReconciliation(
            active: sharedHistory,
            repoLocal: sharedHistory
        )
        let repoLocalMissing = diagnosticsSourceReconciliation(
            active: diagnosticsSourceHistory(seed: "missing-repo-local", sessions: [12]),
            repoLocal: nil
        )
        let cases: [(CinematicRunRecapShareArtifactHistoryPlan, CinematicRunRecapShareArtifactSourceReconciliationPlan, RepositoryActivitySourceSnapshot)] = [
            (
                diagnosticsSourceHistory(seed: "repo-local-active", sessions: [4]),
                activeOnly,
                .notScanned(activeStorage: .repoLocal)
            ),
            (
                sharedHistory,
                compatible,
                diagnosticsSourceActivitySnapshot()
            ),
            (
                diagnosticsSourceHistory(seed: "missing-repo-local", sessions: [12]),
                repoLocalMissing,
                diagnosticsSourceActivitySnapshot(repoLocalState: .ignoredMissing)
            )
        ]

        for (activeHistory, reconciliation, activitySource) in cases {
            let report = makeReport(
                CinematicDiagnosticsInput(
                    repoName: "Compass",
                    phase: "Developing",
                    immediateTitle: "Keep quiet recap source states out of warnings",
                    completedCount: 1,
                    latestEvent: nil,
                    languageProfile: languageProfile(primaryLanguage: .swift),
                    activityProfile: activityProfile(recentCommitCount: 1),
                    activitySourceSnapshot: activitySource,
                    influenceSettings: CinematicInfluenceSettings(),
                    runRecapShareArtifactHistoryPlan: activeHistory,
                    runRecapShareArtifactSourceReconciliationPlan: reconciliation
                )
            )
            let summary = CinematicDiagnosticsSummary(report: report)

            XCTAssertFalse(
                summary.attentionSummary.targets.contains {
                    $0.targetAnchorID == "diagnostics-row-run-recap-share-artifact-sources"
                },
                reconciliation.stateIdentifier
            )
            XCTAssertFalse(
                summary.exportText.contains("-> run-recap-share-artifact-sources"),
                reconciliation.stateIdentifier
            )
            XCTAssertFalse(
                summary.exportText.contains("run-recap-share-artifact-sources.\(reconciliation.stateIdentifier)"),
                reconciliation.stateIdentifier
            )
        }
    }

    func testPlanCompassRowsCorrelateWithDiagnosticsExport() throws {
        let state = PlanState(
            completed: [
                "Added plan overview",
                "Bound diagnostics copy",
                "Rendered completed strip",
                "Fed scene focus waypoints",
                "Covered export correlation"
            ],
            immediate: PlanNext(
                plan: "Render the plan compass overlay",
                verify: "swift test --filter CinematicPlanCompassPlanTests",
                verifyTimeoutMs: 120_000,
                estimatedDifficulty: .medium
            ),
            midTerm: "Queue cinematic plan polish",
            longTerm: "Make waiting time legible."
        )
        let planCompass = CinematicPlanCompassPlan(state: state)
        let planFocus = CinematicPlanCompassSceneFocusPlanner.plan(
            isPlanOverlaySelected: true,
            planCompassPlan: planCompass
        )
        let planFocusDescriptor = try XCTUnwrap(planFocus.descriptor)
        let report = CinematicDiagnostics.report(
            repoName: "Compass",
            phase: "Developing",
            immediateTitle: "Render the plan compass overlay",
            completedCount: state.completed.count,
            planCompassPlan: planCompass,
            latestEvent: nil,
            languageProfile: languageProfile(primaryLanguage: .swift),
            activityProfile: activityProfile(recentCommitCount: 1),
            influenceSettings: CinematicInfluenceSettings(cameraStyle: .steady, intensity: 0.35),
            hasExplicitUserFocus: true,
            planCompassSceneFocusPlan: planFocus
        )
        let summary = CinematicDiagnosticsSummary(
            report: report,
            visualSmoke: CinematicVisualSmokeReport(reports: [report])
        )

        XCTAssertEqual(report.planCompass, planCompass)
        XCTAssertEqual(report.planCompassHistory.identifier, planCompass.completedWaypointStripIdentifier)
        XCTAssertEqual(report.planCompassHistory.completedCount, state.completed.count)
        XCTAssertEqual(report.planCompassHistory.waypointCount, planCompass.completedWaypointCount)
        XCTAssertEqual(report.planCompassHistory.hiddenCount, planCompass.hiddenCompletedWaypointCount)
        XCTAssertEqual(report.planCompassHistory.latestWaypointIdentifier, planCompass.latestCompletedWaypoint?.contentIdentifier)
        XCTAssertEqual(report.planCompassHistory.latestWaypointCopyIdentifier, planCompass.latestCompletedWaypoint?.copyIdentifier)
        XCTAssertEqual(report.planCompassHistory.latestWaypointExportIdentifier, planCompass.latestCompletedWaypoint?.exportIdentifier)
        XCTAssertEqual(report.planCompassHistory.historyStateIdentifier, "truncated")
        XCTAssertEqual(report.planCompassSceneFocus.descriptorIdentifier, planFocusDescriptor.identifier)
        XCTAssertEqual(report.planCompassSceneFocus.selectedSectionRouteIdentifier, "immediate")
        XCTAssertTrue(report.identifier.contains("plan-compass:\(planCompass.identifier)"))
        XCTAssertTrue(report.identifier.contains("plan-compass-copy:\(planCompass.copyIdentifier)"))
        XCTAssertTrue(report.identifier.contains("plan-compass-export:\(planCompass.exportIdentifier)"))
        XCTAssertTrue(report.identifier.contains("plan-compass-history:\(planCompass.completedWaypointStripIdentifier)"))
        XCTAssertTrue(report.identifier.contains("plan-compass-history-hidden:1"))
        XCTAssertTrue(report.identifier.contains("plan-compass-focus:\(planFocus.identifier)"))
        XCTAssertTrue(report.identifier.contains("plan-compass-action-surface:"))

        let historyRow = try XCTUnwrap(summary.row(id: "plan-compass-history"))
        let readinessRow = try XCTUnwrap(summary.row(id: "plan-compass-readiness"))
        let immediateRow = try XCTUnwrap(summary.row(id: "plan-compass-immediate"))
        let midTermRow = try XCTUnwrap(summary.row(id: "plan-compass-mid-term"))
        let longTermRow = try XCTUnwrap(summary.row(id: "plan-compass-long-term"))
        let focusRow = try XCTUnwrap(summary.row(id: "plan-compass-focus"))
        let commandsRow = try XCTUnwrap(summary.row(id: "plan-compass-commands"))

        XCTAssertTrue(historyRow.detail.contains("waypoints \(planCompass.completedWaypointCount)"))
        XCTAssertTrue(historyRow.detail.contains("hidden 1"))
        XCTAssertTrue(historyRow.detail.contains("latest-label #5"))
        XCTAssertTrue(historyRow.detail.contains(planCompass.latestCompletedWaypoint?.copyIdentifier ?? "missing"))
        XCTAssertTrue(historyRow.detail.contains("correlated yes"))
        XCTAssertTrue(readinessRow.detail.contains("status ready"))
        XCTAssertTrue(readinessRow.detail.contains("drift clear"))
        XCTAssertTrue(readinessRow.detail.contains("command swift test --filter CinematicPlanCompassPlanTests"))
        XCTAssertTrue(immediateRow.detail.contains(planCompass.immediate.copyIdentifier))
        XCTAssertTrue(immediateRow.detail.contains(planCompass.immediate.exportIdentifier))
        XCTAssertTrue(immediateRow.detail.contains("verify Timeout 2m"))
        XCTAssertTrue(immediateRow.detail.contains("difficulty medium"))
        XCTAssertTrue(midTermRow.detail.contains(planCompass.midTerm.displayText))
        XCTAssertTrue(longTermRow.detail.contains(planCompass.longTerm.displayText))
        XCTAssertTrue(focusRow.detail.contains(planFocusDescriptor.planCopyIdentifier))
        XCTAssertTrue(focusRow.detail.contains(planFocusDescriptor.selectedSectionExportIdentifier))
        XCTAssertTrue(focusRow.detail.contains("route immediate"))
        XCTAssertTrue(focusRow.detail.contains("diagnostics plan-compass-focus.diagnostics"))
        XCTAssertTrue(focusRow.detail.contains("waypoints \(planCompass.completedWaypointCount)"))
        XCTAssertTrue(focusRow.detail.contains("waypoint-rail plan-compass-focus"))
        XCTAssertTrue(commandsRow.detail.contains("actions 6 e6 d0"))
        XCTAssertTrue(commandsRow.detail.contains("selected-actions focusImmediateRoute"))
        XCTAssertTrue(commandsRow.detail.contains("action-correlated yes"))
        XCTAssertTrue(summary.exportText.contains("Immediate direction:"))
        XCTAssertTrue(summary.exportText.contains("Plan readiness:"))
        XCTAssertTrue(summary.exportText.contains("Plan history:"))
        XCTAssertTrue(summary.exportText.contains(planCompass.immediate.exportIdentifier))
        XCTAssertTrue(summary.exportText.contains(planCompass.latestCompletedWaypoint?.exportIdentifier ?? "missing"))
        XCTAssertTrue(summary.exportText.contains(planCompass.midTerm.copyIdentifier))
        XCTAssertTrue(summary.exportText.contains(planCompass.longTerm.exportIdentifier))
        XCTAssertTrue(summary.exportText.contains("Plan compass focus:"))
        XCTAssertTrue(summary.exportText.contains(planFocusDescriptor.selectedSectionCopyIdentifier))
        XCTAssertTrue(summary.exportText.contains("Plan compass commands:"))
        XCTAssertTrue(summary.exportText.contains("action-correlated yes"))
    }

    func testSummaryKeepsNarrativeAndOverlayRowsInOneTuningGroup() throws {
        let report = makeReport(
            CinematicDiagnosticsInput(
                repoName: "Compass",
                phase: "Developing",
                immediateTitle: "Tune narrative overlay diagnostics",
                completedCount: 5,
                latestEvent: nil,
                languageProfile: languageProfile(primaryLanguage: .swift),
                activityProfile: activityProfile(worktreeChanges: worktreeChanges(modified: 5)),
                influenceSettings: CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 0.65)
            )
        )

        let summary = CinematicDiagnosticsSummary(report: report)
        let narrativeSection = try XCTUnwrap(summary.sections.first { $0.id == "narrative-overlay" })
        let narrativeRowIDs = narrativeSection.rows.map(\.id)

        XCTAssertEqual(narrativeSection.label, "Narrative/overlay")
        XCTAssertEqual(
            narrativeRowIDs,
            [
                "narrative-cues",
                "narrative-layout",
                "overlay-display",
                "native-feedback-history",
                "native-feedback-delivery",
                "world-quest",
                "world-arena",
                "world-activity"
            ]
        )

        for rowID in [
            "narrative-cues",
            "narrative-layout",
            "overlay-display",
            "native-feedback-history",
            "native-feedback-delivery"
        ] {
            XCTAssertEqual(
                summary.sections.filter { section in
                    section.rows.contains { $0.id == rowID }
                }.map(\.id),
                ["narrative-overlay"]
            )
        }
    }

    func testNativeFeedbackHistoryQuickExportIsUnavailableWhenHistoryIsEmpty() throws {
        let report = makeReport(
            CinematicDiagnosticsInput(
                repoName: "Empty Native History",
                phase: "Developing",
                immediateTitle: "Leave native history empty",
                completedCount: 0,
                latestEvent: nil,
                languageProfile: languageProfile(primaryLanguage: .swift),
                activityProfile: activityProfile(),
                influenceSettings: CinematicInfluenceSettings()
            )
        )
        let summary = CinematicDiagnosticsSummary(report: report)
        let historyRow = try XCTUnwrap(summary.rows.first { $0.id == "native-feedback-history" })

        XCTAssertEqual(historyRow.detail, "none")
        assertNativeFeedbackHistoryExport(
            summary.nativeFeedbackHistoryExport,
            row: historyRow,
            activeCount: 0,
            archivedCount: 0,
            omittedCount: 0,
            requiredTokens: []
        )
    }

    func testNativeFeedbackDeliveryDiagnosticsRowsCoverAuthorizationStates() throws {
        let cases: [(String, NativeFeedbackDeliverySnapshot, [String])] = [
            (
                "not-requested",
                NativeFeedbackDeliverySnapshot(
                    mode: .notifications,
                    notificationSupportIdentifier: "available",
                    authorizationRequestStateIdentifier: "not-requested",
                    notificationAuthorizationStatusIdentifier: "not-requested",
                    notificationsAllowed: false,
                    recentDedupeCount: 1,
                    lastAttemptedMilestoneIdentifier: "verifyStarted",
                    lastAttemptResultIdentifier: "queued-notification",
                    speechStateIdentifier: "suppressed-mode"
                ),
                [
                    "mode notifications",
                    "notifications",
                    "speech-off",
                    "support available",
                    "authorization not-requested",
                    "notification-status not-requested",
                    "notification-allowed false",
                    "dedupe 1",
                    "last verifyStarted/queued-notification",
                    "speech suppressed-mode"
                ]
            ),
            (
                "allowed",
                NativeFeedbackDeliverySnapshot(
                    mode: .speechAndNotifications,
                    notificationSupportIdentifier: "available",
                    authorizationRequestStateIdentifier: "requested",
                    notificationAuthorizationStatusIdentifier: "allowed",
                    notificationsAllowed: true,
                    recentDedupeCount: 2,
                    lastAttemptedMilestoneIdentifier: "verifyPassed",
                    lastAttemptResultIdentifier: "notification-delivered",
                    speechStateIdentifier: "speaking"
                ),
                [
                    "mode speech_and_notifications",
                    "notifications",
                    "speech",
                    "notification-status allowed",
                    "notification-allowed true",
                    "last verifyPassed/notification-delivered",
                    "speech speaking"
                ]
            ),
            (
                "denied",
                NativeFeedbackDeliverySnapshot(
                    mode: .notifications,
                    notificationSupportIdentifier: "available",
                    authorizationRequestStateIdentifier: "requested",
                    notificationAuthorizationStatusIdentifier: "denied",
                    notificationsAllowed: false,
                    recentDedupeCount: 3,
                    lastAttemptedMilestoneIdentifier: "postChecksFailed",
                    lastAttemptResultIdentifier: "notification-suppressed-denied",
                    speechStateIdentifier: "suppressed-mode"
                ),
                [
                    "mode notifications",
                    "authorization requested",
                    "notification-status denied",
                    "last postChecksFailed/notification-suppressed-denied"
                ]
            ),
            (
                "unavailable",
                NativeFeedbackDeliverySnapshot(
                    mode: .notifications,
                    notificationSupportIdentifier: "unavailable-app-bundle",
                    authorizationRequestStateIdentifier: "not-requested",
                    notificationAuthorizationStatusIdentifier: "unavailable-app-bundle",
                    notificationsAllowed: false,
                    recentDedupeCount: 4,
                    lastAttemptedMilestoneIdentifier: "developStarted",
                    lastAttemptResultIdentifier: "notification-suppressed-unavailable",
                    speechStateIdentifier: "suppressed-mode"
                ),
                [
                    "support unavailable-app-bundle",
                    "notification-status unavailable-app-bundle",
                    "last developStarted/notification-suppressed-unavailable"
                ]
            ),
            (
                "off",
                NativeFeedbackDeliverySnapshot(
                    mode: .off,
                    notificationSupportIdentifier: "available",
                    authorizationRequestStateIdentifier: "not-requested",
                    notificationAuthorizationStatusIdentifier: "not-requested",
                    notificationsAllowed: false,
                    recentDedupeCount: 0,
                    lastAttemptedMilestoneIdentifier: "paused",
                    lastAttemptResultIdentifier: "suppressed-off",
                    speechStateIdentifier: "suppressed-mode"
                ),
                [
                    "mode off",
                    "notifications-off",
                    "speech-off",
                    "last paused/suppressed-off",
                    "speech suppressed-mode"
                ]
            )
        ]

        for (name, snapshot, expectedTokens) in cases {
            let report = makeReport(
                CinematicDiagnosticsInput(
                    repoName: "Native Delivery \(name)",
                    phase: "Verifying",
                    immediateTitle: "Expose native delivery diagnostics",
                    completedCount: 1,
                    latestEvent: nil,
                    languageProfile: languageProfile(primaryLanguage: .swift),
                    activityProfile: activityProfile(recentCommitCount: 1),
                    influenceSettings: CinematicInfluenceSettings(),
                    nativeFeedbackDeliverySnapshot: snapshot
                )
            )
            let summary = CinematicDiagnosticsSummary(report: report)
            let row = try XCTUnwrap(summary.rows.first { $0.id == "native-feedback-delivery" })

            XCTAssertTrue(report.identifier.contains("native-feedback-delivery:\(snapshot.identifier)"))
            XCTAssertEqual(row.label, "Native feedback delivery")
            for token in expectedTokens {
                XCTAssertTrue(row.detail.contains(token), "\(name) missing row token \(token)")
                XCTAssertTrue(summary.exportText.contains(token), "\(name) missing export token \(token)")
            }
            XCTAssertTrue(summary.exportText.contains("Native feedback delivery:"))
        }
    }

    @MainActor
    func testCurrentReportDeliveryDiagnosticsAreReadOnlyAndLeaveCueLifecycleUnchanged() throws {
        let project = CompassProject(
            repoURL: URL(fileURLWithPath: "/tmp/NativeDeliveryReadOnly", isDirectory: true),
            nativeFeedbackMode: .notifications
        )
        project.phase = .verifying
        project.languageProfile = languageProfile(primaryLanguage: .swift)
        project.activityProfile = activityProfile(recentCommitCount: 1)
        project.recordCinematicNativeFeedback(.verifyStarted)
        let cueBefore = try XCTUnwrap(project.cinematicNativeFeedbackCue)
        let lifecycleBefore = project.cinematicNativeFeedbackCueLifecycle
        let sessionsBefore = project.sessions
        let recapArtifactContextBefore = project.cinematicRunRecapShareArtifactLibraryContext
        let warningHistoryBefore = project.cinematicDiagnosticsWarningBundleHistory
        let activeStorageBefore = project.activeStorage
        let deliveryBefore = NativeFeedbackService.shared.deliverySnapshot(mode: project.nativeFeedbackMode)
        let planCompassFocus = CinematicPlanCompassSceneFocusPlanner.plan(
            isPlanOverlaySelected: true,
            planCompassPlan: CinematicPlanCompassPlan(state: project.state)
        )

        let report = CinematicDiagnostics.currentReport(
            for: project,
            planCompassSceneFocusPlan: planCompassFocus
        )
        let deliveryAfter = NativeFeedbackService.shared.deliverySnapshot(mode: project.nativeFeedbackMode)
        let summary = CinematicDiagnosticsSummary(
            report: report,
            visualSmoke: CinematicVisualSmokeReport(reports: [report])
        )

        XCTAssertEqual(project.cinematicNativeFeedbackCue, cueBefore)
        XCTAssertEqual(project.cinematicNativeFeedbackCueLifecycle, lifecycleBefore)
        XCTAssertEqual(project.sessions, sessionsBefore)
        XCTAssertEqual(project.cinematicRunRecapShareArtifactLibraryContext, recapArtifactContextBefore)
        XCTAssertEqual(project.cinematicDiagnosticsWarningBundleHistory, warningHistoryBefore)
        XCTAssertEqual(project.activeStorage, activeStorageBefore)
        XCTAssertEqual(report.planCompass, CinematicPlanCompassPlan(state: project.state))
        XCTAssertEqual(report.planCompassSceneFocus.identifier, planCompassFocus.identifier)
        XCTAssertEqual(report.nativeFeedback.cueIdentifier, cueBefore.identifier)
        XCTAssertEqual(
            deliveryAfter.authorizationRequestStateIdentifier,
            deliveryBefore.authorizationRequestStateIdentifier
        )
        XCTAssertEqual(
            deliveryAfter.notificationAuthorizationStatusIdentifier,
            deliveryBefore.notificationAuthorizationStatusIdentifier
        )
        XCTAssertNotNil(summary.rows.first { $0.id == "native-feedback-delivery" })
    }

    @MainActor
    func testSceneLifecycleDiagnosticsDistinguishCacheStatesAndStayBounded() throws {
        let cache = CinematicSceneCache(releaseDelay: 600)
        let projectID = UUID()
        let coordinator = cache.coordinator(for: projectID)
        coordinator.primeLifecycleForTesting(
            elapsedTime: 18,
            phase: .developing,
            isThinking: true
        )
        let activeCacheSnapshot = try XCTUnwrap(cache.lifecycleSnapshot(for: projectID))
        defer {
            cache.release(projectID)
            cache.expireReleasedCoordinator(for: projectID)
        }

        let activeReport = makeReport(
            CinematicDiagnosticsInput(
                repoName: "Lifecycle Diagnostics",
                phase: "Developing",
                immediateTitle: "Inspect mounted lifecycle diagnostics",
                completedCount: 1,
                latestEvent: nil,
                languageProfile: languageProfile(primaryLanguage: .swift),
                activityProfile: activityProfile(recentCommitCount: 1),
                sceneCacheLifecycleSnapshot: activeCacheSnapshot,
                influenceSettings: CinematicInfluenceSettings()
            )
        )
        let passingVisualSmoke = CinematicVisualSmokeReport.representative()
        let activeSummary = CinematicDiagnosticsSummary(report: activeReport, visualSmoke: passingVisualSmoke)
        let activeRow = try XCTUnwrap(activeSummary.row(id: "cinematic-scene-lifecycle"))

        XCTAssertEqual(activeReport.cinematicSceneLifecycle.stateIdentifier, "active")
        XCTAssertEqual(activeReport.cinematicSceneLifecycle.retainCount, 1)
        XCTAssertFalse(activeReport.cinematicSceneLifecycle.hasScheduledExpiry)
        XCTAssertEqual(activeReport.cinematicSceneLifecycle.timerSuspensionIdentifier, "running")
        XCTAssertEqual(activeReport.cinematicSceneLifecycle.installedStateIdentifier, "installed")
        XCTAssertEqual(activeReport.cinematicSceneLifecycle.phaseIdentifier, LoopPhase.developing.rawValue)
        XCTAssertTrue(activeRow.detail.contains("active"))
        XCTAssertTrue(activeRow.detail.contains("retain 1"))
        XCTAssertTrue(activeRow.detail.contains("expiry none"))
        XCTAssertTrue(activeRow.detail.contains("timers running"))
        XCTAssertTrue(activeRow.detail.contains("installed installed"))
        XCTAssertTrue(activeRow.detail.contains("phase Developing"))
        XCTAssertTrue(activeRow.detail.contains("focus commit:"))
        XCTAssertLessThanOrEqual(activeRow.detail.count, CinematicDiagnosticsSummary.detailMaxCharacters)
        XCTAssertTrue(activeSummary.exportText.contains("Scene lifecycle: active"))
        XCTAssertTrue(activeSummary.attentionSummary.isEmpty)

        let invariantSnapshot = CinematicSceneCacheLifecycleSnapshot(
            retainCount: 0,
            hasScheduledExpiry: false,
            coordinator: activeCacheSnapshot.coordinator
        )
        let invariantReport = makeReport(
            CinematicDiagnosticsInput(
                repoName: "Lifecycle Diagnostics",
                phase: "Developing",
                immediateTitle: "Inspect invariant lifecycle diagnostics",
                completedCount: 1,
                latestEvent: nil,
                languageProfile: languageProfile(primaryLanguage: .swift),
                activityProfile: activityProfile(recentCommitCount: 1),
                sceneCacheLifecycleSnapshot: invariantSnapshot,
                influenceSettings: CinematicInfluenceSettings()
            )
        )
        let invariantSummary = CinematicDiagnosticsSummary(report: invariantReport, visualSmoke: passingVisualSmoke)
        let invariantTarget = try XCTUnwrap(
            invariantSummary.attentionSummary.targets.first {
                $0.id == "cinematic-scene-lifecycle-lifecycle-invariant"
            }
        )

        XCTAssertEqual(invariantReport.cinematicSceneLifecycle.stateIdentifier, "lifecycle-invariant")
        XCTAssertEqual(invariantTarget.targetGroupID, "repository-context")
        XCTAssertEqual(invariantTarget.targetAnchorID, "diagnostics-row-cinematic-scene-lifecycle")
        XCTAssertEqual(invariantTarget.relatedGroupID, "repository-context")
        XCTAssertEqual(invariantTarget.relatedRowID, "cinematic-scene-lifecycle")
        XCTAssertEqual(invariantTarget.visibleWarningIdentifiers.first, "cinematic-scene-lifecycle.lifecycle-invariant")
        XCTAssertTrue(invariantTarget.detail.contains("retain 0"))
        XCTAssertTrue(invariantTarget.detail.contains("onscreen"))
        XCTAssertTrue(invariantTarget.copyText.contains("Related row: cinematic-scene-lifecycle"))
        XCTAssertTrue(invariantTarget.copyText.contains("Related detail: lifecycle-invariant"))
        XCTAssertTrue(
            invariantTarget.copyText.contains(
                "no RealityKit scene coordinator is mounted, retained, reacquired, expired, or resurrected"
            )
        )
        XCTAssertLessThanOrEqual(
            invariantTarget.detail.count,
            CinematicDiagnosticsSummary.attentionSummaryDetailMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            invariantTarget.copyText.count,
            CinematicDiagnosticsSummary.attentionTargetCopyMaxCharacters
        )
        XCTAssertTrue(
            invariantSummary.exportText.contains(
                "Scene lifecycle invariant -> cinematic-scene-lifecycle-lifecycle-invariant"
            )
        )

        var warningHistory = CinematicDiagnosticsWarningBundleHistory()
        warningHistory.record(invariantSummary.attentionSummary)
        let warningEntry = try XCTUnwrap(warningHistory.entries.first)
        XCTAssertEqual(warningEntry.targetIdentifiers, ["cinematic-scene-lifecycle-lifecycle-invariant"])
        XCTAssertEqual(warningEntry.targetAnchors, ["diagnostics-row-cinematic-scene-lifecycle"])
        XCTAssertEqual(warningEntry.relatedRowAnchors, ["diagnostics-row-cinematic-scene-lifecycle"])
        XCTAssertEqual(warningEntry.warningIdentifiers, [
            "cinematic-scene-lifecycle.lifecycle-invariant",
            "cinematic-scene-lifecycle.retain-0",
            "cinematic-scene-lifecycle.onscreen"
        ])

        let idlePulseReport = CinematicDiagnostics.report(
            repoName: "Lifecycle Diagnostics",
            phase: LoopPhase.succeeded.rawValue,
            immediateTitle: "Pulse lifecycle diagnostics warning",
            completedCount: 1,
            latestEvent: nil,
            languageProfile: languageProfile(primaryLanguage: .swift),
            activityProfile: activityProfile(lastTerminalStatus: .succeeded),
            influenceSettings: CinematicInfluenceSettings(),
            diagnosticsWarningBundleHistory: warningHistory
        )
        XCTAssertEqual(idlePulseReport.idleStoryCycle.phaseIdentifier, "diagnostics-warning-pulse")
        XCTAssertEqual(idlePulseReport.idleStoryCycle.diagnosticsWarningTargetCount, 1)
        XCTAssertEqual(idlePulseReport.idleStoryCycle.diagnosticsWarningWarningCount, 4)
        XCTAssertEqual(
            idlePulseReport.idleStoryCycle.diagnosticsWarningTargetAnchors,
            ["diagnostics-row-cinematic-scene-lifecycle"]
        )
        XCTAssertEqual(
            idlePulseReport.idleStoryCycle.diagnosticsWarningRelatedRowAnchors,
            ["diagnostics-row-cinematic-scene-lifecycle"]
        )
        XCTAssertTrue(
            idlePulseReport.idleStoryCycle.diagnosticsWarningIdentifiers.contains(
                "cinematic-scene-lifecycle.lifecycle-invariant"
            )
        )

        cache.release(projectID)
        let suspendedSnapshot = try XCTUnwrap(cache.lifecycleSnapshot(for: projectID))
        let suspendedReport = makeReport(
            CinematicDiagnosticsInput(
                repoName: "Lifecycle Diagnostics",
                phase: "Developing",
                immediateTitle: "Inspect suspended lifecycle diagnostics",
                completedCount: 1,
                latestEvent: nil,
                languageProfile: languageProfile(primaryLanguage: .swift),
                activityProfile: activityProfile(recentCommitCount: 1),
                sceneCacheLifecycleSnapshot: suspendedSnapshot,
                influenceSettings: CinematicInfluenceSettings()
            )
        )
        let suspendedSummary = CinematicDiagnosticsSummary(report: suspendedReport, visualSmoke: passingVisualSmoke)
        let suspendedRow = try XCTUnwrap(suspendedSummary.row(id: "cinematic-scene-lifecycle"))

        XCTAssertEqual(suspendedReport.cinematicSceneLifecycle.stateIdentifier, "cached-offscreen")
        XCTAssertEqual(suspendedReport.cinematicSceneLifecycle.retainCount, 0)
        XCTAssertTrue(suspendedReport.cinematicSceneLifecycle.hasScheduledExpiry)
        XCTAssertEqual(suspendedReport.cinematicSceneLifecycle.timerSuspensionIdentifier, "suspended")
        XCTAssertTrue(suspendedRow.detail.contains("cached-offscreen"))
        XCTAssertTrue(suspendedRow.detail.contains("retain 0"))
        XCTAssertTrue(suspendedRow.detail.contains("expiry scheduled"))
        XCTAssertTrue(suspendedRow.detail.contains("timers suspended"))
        XCTAssertTrue(suspendedRow.detail.contains("offscreen"))
        XCTAssertTrue(suspendedSummary.attentionSummary.isEmpty)

        let expiredStyleSnapshot = CinematicSceneCacheLifecycleSnapshot(
            retainCount: 0,
            hasScheduledExpiry: false,
            coordinator: suspendedSnapshot.coordinator
        )
        let expiredStyleReport = makeReport(
            CinematicDiagnosticsInput(
                repoName: "Lifecycle Diagnostics",
                phase: "Developing",
                immediateTitle: "Inspect expired-style lifecycle diagnostics",
                completedCount: 1,
                latestEvent: nil,
                languageProfile: languageProfile(primaryLanguage: .swift),
                activityProfile: activityProfile(recentCommitCount: 1),
                sceneCacheLifecycleSnapshot: expiredStyleSnapshot,
                influenceSettings: CinematicInfluenceSettings()
            )
        )
        XCTAssertEqual(expiredStyleReport.cinematicSceneLifecycle.stateIdentifier, "expired-style")
        XCTAssertTrue(
            CinematicDiagnosticsSummary(
                report: expiredStyleReport,
                visualSmoke: passingVisualSmoke
            ).attentionSummary.isEmpty
        )

        let reacquired = cache.coordinator(for: projectID)
        XCTAssertTrue(reacquired === coordinator)
        let reacquiredReport = makeReport(
            CinematicDiagnosticsInput(
                repoName: "Lifecycle Diagnostics",
                phase: "Developing",
                immediateTitle: "Inspect reacquired lifecycle diagnostics",
                completedCount: 1,
                latestEvent: nil,
                languageProfile: languageProfile(primaryLanguage: .swift),
                activityProfile: activityProfile(recentCommitCount: 1),
                sceneCacheLifecycleSnapshot: cache.lifecycleSnapshot(for: projectID),
                influenceSettings: CinematicInfluenceSettings()
            )
        )
        XCTAssertEqual(reacquiredReport.cinematicSceneLifecycle.stateIdentifier, "active")
        XCTAssertEqual(reacquiredReport.cinematicSceneLifecycle.retainCount, 1)
        XCTAssertFalse(reacquiredReport.cinematicSceneLifecycle.hasScheduledExpiry)

        cache.release(projectID)
        cache.expireReleasedCoordinator(for: projectID)
        let expiredReport = makeReport(
            CinematicDiagnosticsInput(
                repoName: "Lifecycle Diagnostics",
                phase: "Developing",
                immediateTitle: "Inspect expired lifecycle diagnostics",
                completedCount: 1,
                latestEvent: nil,
                languageProfile: languageProfile(primaryLanguage: .swift),
                activityProfile: activityProfile(recentCommitCount: 1),
                sceneCacheLifecycleSnapshot: cache.lifecycleSnapshot(for: projectID),
                influenceSettings: CinematicInfluenceSettings()
            )
        )
        let expiredSummary = CinematicDiagnosticsSummary(report: expiredReport, visualSmoke: passingVisualSmoke)
        let expiredRow = try XCTUnwrap(expiredSummary.row(id: "cinematic-scene-lifecycle"))

        XCTAssertEqual(expiredReport.cinematicSceneLifecycle.stateIdentifier, "not-mounted-or-expired")
        XCTAssertEqual(expiredReport.cinematicSceneLifecycle.retainCount, 0)
        XCTAssertFalse(expiredReport.cinematicSceneLifecycle.hasScheduledExpiry)
        XCTAssertTrue(expiredRow.detail.contains("not-mounted-or-expired"))
        XCTAssertTrue(expiredSummary.exportText.contains("Scene lifecycle: not-mounted-or-expired"))
        XCTAssertTrue(expiredSummary.attentionSummary.isEmpty)
    }

    @MainActor
    func testCurrentReportSceneLifecycleInspectionDoesNotCreateRetainOrResurrectCacheEntry() throws {
        let project = CompassProject(
            repoURL: URL(fileURLWithPath: "/tmp/SceneLifecycleReadOnly", isDirectory: true)
        )
        defer {
            CinematicSceneCache.shared.release(project.id)
            CinematicSceneCache.shared.expireReleasedCoordinator(for: project.id)
        }

        XCTAssertNil(CinematicSceneCache.shared.lifecycleSnapshot(for: project.id))
        let notMountedReport = CinematicDiagnostics.currentReport(for: project)
        XCTAssertEqual(notMountedReport.cinematicSceneLifecycle.stateIdentifier, "not-mounted-or-expired")
        XCTAssertNil(CinematicSceneCache.shared.lifecycleSnapshot(for: project.id))
        let notMountedSummary = CinematicDiagnosticsSummary(
            report: notMountedReport,
            visualSmoke: CinematicVisualSmokeReport(reports: [notMountedReport])
        )
        XCTAssertEqual(notMountedSummary.row(id: "cinematic-scene-lifecycle")?.id, "cinematic-scene-lifecycle")
        XCTAssertFalse(
            notMountedSummary.visualSmoke.warningIdentifiers.contains("visual-smoke.cinematic-scene-lifecycle")
        )
        XCTAssertNil(CinematicSceneCache.shared.lifecycleSnapshot(for: project.id))

        let coordinator = CinematicSceneCache.shared.coordinator(for: project.id)
        coordinator.primeLifecycleForTesting(
            elapsedTime: 34,
            phase: .verifying,
            isThinking: true
        )
        let mountedBefore = try XCTUnwrap(CinematicSceneCache.shared.lifecycleSnapshot(for: project.id))
        let mountedReport = CinematicDiagnostics.currentReport(for: project)
        XCTAssertEqual(mountedReport.cinematicSceneLifecycle.stateIdentifier, "active")
        XCTAssertEqual(mountedReport.cinematicSceneLifecycle.retainCount, mountedBefore.retainCount)
        XCTAssertEqual(CinematicSceneCache.shared.lifecycleSnapshot(for: project.id), mountedBefore)

        CinematicSceneCache.shared.release(project.id)
        let suspendedBefore = try XCTUnwrap(CinematicSceneCache.shared.lifecycleSnapshot(for: project.id))
        let suspendedReport = CinematicDiagnostics.currentReport(for: project)
        XCTAssertEqual(suspendedReport.cinematicSceneLifecycle.stateIdentifier, "cached-offscreen")
        XCTAssertEqual(suspendedReport.cinematicSceneLifecycle.retainCount, 0)
        XCTAssertEqual(CinematicSceneCache.shared.lifecycleSnapshot(for: project.id), suspendedBefore)

        let reacquired = CinematicSceneCache.shared.coordinator(for: project.id)
        XCTAssertTrue(reacquired === coordinator)
        CinematicSceneCache.shared.release(project.id)
        CinematicSceneCache.shared.expireReleasedCoordinator(for: project.id)

        XCTAssertNil(CinematicSceneCache.shared.lifecycleSnapshot(for: project.id))
        let expiredReport = CinematicDiagnostics.currentReport(for: project)
        XCTAssertEqual(expiredReport.cinematicSceneLifecycle.stateIdentifier, "not-mounted-or-expired")
        _ = CinematicDiagnosticsSummary(
            report: expiredReport,
            visualSmoke: CinematicVisualSmokeReport(reports: [expiredReport])
        )
        XCTAssertNil(CinematicSceneCache.shared.lifecycleSnapshot(for: project.id))
    }

    @MainActor
    func testCurrentReportPlanCompassHistoryIsReadOnlyAcrossProjectStateAndStorageContext() throws {
        let project = CompassProject(
            repoURL: URL(fileURLWithPath: "/tmp/PlanCompassHistoryReadOnly", isDirectory: true)
        )
        project.state = PlanState(
            completed: (1...6).map { "Completed read-only waypoint \($0)" },
            immediate: PlanNext(plan: "Expose read-only plan history", verify: "swift test"),
            midTerm: "Queue read-only diagnostics",
            longTerm: "Preserve cinematic context"
        )
        project.sessions = [SessionRecord.started(1)]
        project.cinematicRunRecapShareArtifactLibraryContext = CinematicRunRecapShareArtifactLibraryContext(
            selectedEntryIdentifier: "selected-history-entry",
            searchText: "history",
            pinnedEntryIdentifiers: ["selected-history-entry", "pinned-history-entry"],
            comparisonTargetMode: .pinnedReference,
            savedTourHoldEntryIdentifier: "held-history-entry"
        )

        let stateBefore = project.state
        let sessionsBefore = project.sessions
        let recapArtifactContextBefore = project.cinematicRunRecapShareArtifactLibraryContext
        let warningHistoryBefore = project.cinematicDiagnosticsWarningBundleHistory
        let activeStorageBefore = project.activeStorage
        let planCompass = CinematicPlanCompassPlan(state: project.state)
        let readiness = CinematicPlanCompassReadinessPlan(
            state: project.state,
            planCompassPlan: planCompass,
            reliabilityFeedback: PlanReliabilityFeedback(state: project.state, sessions: project.sessions)
        )
        let planCompassFocus = CinematicPlanCompassSceneFocusPlanner.plan(
            isPlanOverlaySelected: true,
            planCompassPlan: planCompass,
            readinessPlan: readiness,
            selectedKind: .immediate
        )

        let report = CinematicDiagnostics.currentReport(
            for: project,
            planCompassSceneFocusPlan: planCompassFocus
        )

        XCTAssertEqual(project.state, stateBefore)
        XCTAssertEqual(project.sessions, sessionsBefore)
        XCTAssertEqual(project.cinematicRunRecapShareArtifactLibraryContext, recapArtifactContextBefore)
        XCTAssertEqual(project.cinematicDiagnosticsWarningBundleHistory, warningHistoryBefore)
        XCTAssertEqual(project.activeStorage, activeStorageBefore)
        XCTAssertEqual(report.planCompass, planCompass)
        XCTAssertEqual(report.planCompassHistory.identifier, planCompass.completedWaypointStripIdentifier)
        XCTAssertEqual(report.planCompassHistory.hiddenCount, 2)
        XCTAssertEqual(report.planCompassReadiness.rowIdentifier, "plan-compass-readiness")
        XCTAssertEqual(report.planCompassReadiness.sourceImmediateContentIdentifier, planCompass.immediate.contentIdentifier)
        XCTAssertEqual(report.planCompassSceneFocus.identifier, planCompassFocus.identifier)
        XCTAssertEqual(report.planCompassSceneFocus.completedWaypointIdentifiers, planCompass.completedWaypoints.map(\.contentIdentifier))
        XCTAssertTrue(report.planCompassVerifySeal.isVisible)
        XCTAssertEqual(report.planCompassVerifySeal.rowIdentifier, "plan-compass-verify-seal")
        XCTAssertEqual(report.planCompassVerifySeal.focusDescriptorIdentifier, planCompassFocus.descriptor?.identifier)
        XCTAssertEqual(report.planCompassVerifySeal.readinessIdentifier, report.planCompassReadiness.identifier)
    }

    func testCurrentReportUsesCompassProjectInputs() async {
        await MainActor.run {
            let repoURL = URL(fileURLWithPath: "/tmp/CurrentDiagnosticsRepo", isDirectory: true)
            let project = CompassProject(
                repoURL: repoURL,
                cinematicInfluenceSettings: CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 0.75)
            )
            project.state = PlanState(
                completed: ["Stage diagnostics", "Wire copy action"],
                immediate: PlanNext(
                    plan: "Expose current cinematic diagnostics\nKeep behavior unchanged",
                    verify: "swift test"
                ),
                midTerm: "",
                longTerm: ""
            )
            project.phase = .developing
            project.languageProfile = languageProfile(primaryLanguage: .python)
            project.activityProfile = activityProfile(recentCommitCount: 1)
            project.liveLog = [
                LiveLine(
                    level: .success,
                    text: "Generated diagnostics report",
                    detail: "Current motif state is ready",
                    kind: .agentMessage,
                    status: .completed
                )
            ]

            let deliverySnapshot = NativeFeedbackService.shared.deliverySnapshot(mode: project.nativeFeedbackMode)
            let report = CinematicDiagnostics.currentReport(for: project)
            let expected = CinematicDiagnostics.report(
                repoName: "CurrentDiagnosticsRepo",
                phase: "Developing",
                immediateTitle: "Expose current cinematic diagnostics",
                completedCount: 2,
                planCompassPlan: CinematicPlanCompassPlan(state: project.state),
                latestEvent: project.liveLog.last.map(CinematicBriefingEvent.init(line:)),
                languageProfile: project.languageProfile,
                activityProfile: project.activityProfile,
                influenceSettings: project.cinematicInfluenceSettings,
                isRunning: project.isRunning,
                isAutoPlaying: project.isAutoPlaying,
                isPaused: project.isPaused,
                hasRepository: project.hasRepository,
                nativeFeedbackDeliverySnapshot: deliverySnapshot
            )

            XCTAssertEqual(report, expected)
            XCTAssertEqual(report.repoName, "CurrentDiagnosticsRepo")
            XCTAssertEqual(report.phase, "Developing")
            XCTAssertEqual(report.immediateTitle, "Expose current cinematic diagnostics")
            XCTAssertEqual(report.completedCount, 2)
            XCTAssertEqual(report.planCompass, CinematicPlanCompassPlan(state: project.state))
            XCTAssertEqual(report.languageMotif.sigilIdentifier, "language.python")
            XCTAssertEqual(report.activityMotif.eventKindIdentifier, "commit")
            XCTAssertEqual(report.stageBeat.phaseIdentifier, "Developing")
            XCTAssertEqual(report.stageBeat.kindIdentifier, "developing")
            XCTAssertEqual(report.stageBeat.cameraShotIdentifier, "cast-prep")
            XCTAssertEqual(report.stageBeat.activityEventKindIdentifier, "commit")
            XCTAssertTrue(report.stageBeat.shouldRunHistoryChains)
            XCTAssertEqual(report.influenceIdentifier, "dramatic|0.7500|standard")
        }
    }

    func testCurrentReportPropagatesNativeFeedbackCueToNarrativeAndExport() async throws {
        try await MainActor.run {
            let repoURL = URL(fileURLWithPath: "/tmp/NativeDiagnosticsRepo", isDirectory: true)
            let project = CompassProject(
                repoURL: repoURL,
                cinematicInfluenceSettings: CinematicInfluenceSettings(cameraStyle: .follow, intensity: 0.65),
                nativeFeedbackMode: .notifications
            )
            project.state = PlanState(
                completed: ["Implemented native cue"],
                immediate: PlanNext(
                    plan: "Thread native feedback into cinematic diagnostics",
                    verify: "swift test"
                ),
                midTerm: "",
                longTerm: ""
            )
            project.phase = .verifying
            project.languageProfile = languageProfile(primaryLanguage: .swift)
            project.activityProfile = activityProfile(recentCommitCount: 1)
            project.recordCinematicNativeFeedback(.verifyStarted)
            let cue = try XCTUnwrap(project.cinematicNativeFeedbackCue)

            let deliverySnapshot = NativeFeedbackService.shared.deliverySnapshot(mode: project.nativeFeedbackMode)
            let report = CinematicDiagnostics.currentReport(for: project)
            let expected = CinematicDiagnostics.report(
                repoName: "NativeDiagnosticsRepo",
                phase: "Verifying",
                immediateTitle: "Thread native feedback into cinematic diagnostics",
                completedCount: 1,
                planCompassPlan: CinematicPlanCompassPlan(state: project.state),
                latestEvent: nil,
                languageProfile: project.languageProfile,
                activityProfile: project.activityProfile,
                influenceSettings: project.cinematicInfluenceSettings,
                isRunning: project.isRunning,
                isAutoPlaying: project.isAutoPlaying,
                isPaused: project.isPaused,
                hasRepository: project.hasRepository,
                nativeFeedbackCue: cue,
                nativeFeedbackLifecycle: project.cinematicNativeFeedbackCueLifecycle,
                nativeFeedbackDeliverySnapshot: deliverySnapshot
            )

            XCTAssertEqual(report, expected)
            XCTAssertEqual(report.nativeFeedback.cueIdentifier, cue.identifier)
            XCTAssertEqual(report.nativeFeedback.lifecycleIdentifier, project.cinematicNativeFeedbackCueLifecycle.identifier)
            XCTAssertEqual(report.nativeFeedback.lifecycleStateIdentifier, "active")
            XCTAssertEqual(report.nativeFeedback.lifecycleActiveCueIdentifier, cue.identifier)
            XCTAssertEqual(report.nativeFeedback.lifecycleRecentArchiveCount, 0)
            let activeHistory = try XCTUnwrap(report.nativeFeedback.lifecycleActiveHistoryEntry)
            XCTAssertEqual(activeHistory.sequence, 1)
            XCTAssertEqual(activeHistory.stateIdentifier, "active")
            XCTAssertNil(activeHistory.reasonIdentifier)
            XCTAssertEqual(activeHistory.milestoneIdentifier, "verifyStarted")
            XCTAssertEqual(activeHistory.sourceIdentifier, "native:verifyStarted")
            XCTAssertEqual(activeHistory.styleIdentifier, "verify")
            XCTAssertEqual(activeHistory.displayDuration, CinematicNativeFeedbackCueLifecycle.standardDisplayDuration)
            XCTAssertEqual(activeHistory.lifecycleIdentifier, cue.lifecycleIdentifier)
            XCTAssertEqual(activeHistory.cueIdentifier, cue.identifier)
            XCTAssertEqual(report.nativeFeedback.lifecycleArchiveHistoryEntries, [])
            XCTAssertEqual(report.nativeFeedback.lifecycleHistoryEntryCount, 1)
            XCTAssertEqual(report.nativeFeedback.sourceIdentifier, "native:verifyStarted")
            XCTAssertEqual(report.nativeFeedback.styleIdentifier, "verify")
            XCTAssertEqual(report.nativeFeedback.milestoneIdentifier, "verifyStarted")
            XCTAssertEqual(
                report.nativeFeedback.affectedNarrativeDescriptorIdentifiers,
                ["narrative.quest.plaque", "narrative.arena.inscription", "narrative.activity.banner"]
            )
            XCTAssertEqual(report.narrativeCue.nativeFeedbackCueIdentifier, cue.identifier)
            XCTAssertEqual(report.narrativeCue.nativeFeedbackLifecycleIdentifier, cue.lifecycleIdentifier)
            XCTAssertEqual(report.narrativeCue.nativeFeedbackSourceIdentifier, "native:verifyStarted")
            XCTAssertEqual(report.overlayDisplay.nativeFeedbackCueIdentifier, cue.identifier)
            XCTAssertEqual(
                report.overlayDisplay.nativeFeedbackLifecycleIdentifier,
                project.cinematicNativeFeedbackCueLifecycle.identifier
            )
            XCTAssertEqual(report.narrativeCue.questPlaque.anchorIdentifier, "left-seal-pylon")
            XCTAssertEqual(report.narrativeCue.arenaInscription.anchorIdentifier, "arena-rear")
            XCTAssertEqual(report.narrativeCue.questPlaque.plaqueTreatmentAccentIdentifier, "verify-seal")
            XCTAssertEqual(report.narrativeCue.questPlaque.plaqueTreatmentRouteIdentifier, "verifyStarted.verify")
            XCTAssertEqual(
                report.narrativeCue.questPlaque.plaqueTreatmentRenderRecipeIdentifier,
                "rail.top,rail.bottom,seal.left,seal.right"
            )
            XCTAssertEqual(
                report.narrativeCue.questPlaque.plaqueTreatmentRenderPrimitiveIdentifiers,
                ["rail.top", "rail.bottom", "seal.left", "seal.right"]
            )
            XCTAssertEqual(report.narrativeCue.questPlaque.plaqueTreatmentRenderPrimitiveCount, 4)
            XCTAssertTrue(report.narrativeCue.questPlaque.text.lowercased().contains("verify"))
            XCTAssertTrue(report.narrativeCue.arenaInscription.text.lowercased().contains("seal"))

            let summary = CinematicDiagnosticsSummary(
                report: report,
                visualSmoke: CinematicVisualSmokeReport(reports: [report])
            )
            XCTAssertTrue(summary.exportText.contains("source native:verifyStarted"))
            XCTAssertTrue(summary.exportText.contains("style verify"))
            XCTAssertTrue(summary.exportText.contains("milestone verifyStarted"))
            XCTAssertTrue(summary.exportText.contains("lifecycle \(cue.lifecycleIdentifier)"))
            XCTAssertTrue(summary.exportText.contains("native-lifecycle native-feedback-cue-lifecycle"))
            XCTAssertTrue(summary.exportText.contains("state:active"))
            XCTAssertTrue(summary.exportText.contains("treatments verify-seal"))
            XCTAssertTrue(summary.exportText.contains("treatment verify-seal/verifyStarted.verify"))
            XCTAssertTrue(summary.exportText.contains("primitives rail.top,rail.bottom,seal.left,seal.right"))
            XCTAssertTrue(summary.exportText.contains("count 4"))
            XCTAssertTrue(summary.exportText.contains("affects narrative.quest.plaque"))
            XCTAssertTrue(summary.exportText.contains("native \(cue.identifier)"))
            let historyRow = try XCTUnwrap(summary.rows.first { $0.id == "native-feedback-history" })
            XCTAssertTrue(historyRow.detail.contains("#1 active"))
            XCTAssertTrue(historyRow.detail.contains("source native:verifyStarted"))
            XCTAssertTrue(historyRow.detail.contains("style verify"))
            XCTAssertTrue(historyRow.detail.contains("duration 8.0000s"))
            XCTAssertTrue(summary.exportText.contains("Native feedback history:"))
            assertNativeFeedbackHistoryExport(
                summary.nativeFeedbackHistoryExport,
                row: historyRow,
                activeCount: 1,
                archivedCount: 0,
                omittedCount: 0,
                requiredTokens: [
                    "#1 active",
                    "milestone verifyStarted",
                    "source native:verifyStarted",
                    "style verify",
                    "duration 8.0000s",
                    "lifecycle \(cue.lifecycleIdentifier)"
                ],
                forbiddenTokens: [
                    cue.title,
                    cue.detail,
                    NativeFeedbackContent(milestone: .verifyStarted, projectName: "NativeDiagnosticsRepo").body
                ]
            )
        }
    }

    func testCurrentReportPropagatesPlanReadinessNativeFeedbackCueToDiagnosticsAndExport() async throws {
        try await MainActor.run {
            let now = Date(timeIntervalSinceReferenceDate: 8_500)
            let repoURL = URL(fileURLWithPath: "/tmp/ReadinessNativeDiagnosticsRepo", isDirectory: true)
            let project = CompassProject(
                repoURL: repoURL,
                cinematicInfluenceSettings: CinematicInfluenceSettings(cameraStyle: .follow, intensity: 0.65),
                nativeFeedbackMode: .notifications
            )
            project.state = PlanState(
                completed: ["Accepted readiness cue"],
                immediate: PlanNext(
                    plan: "Wait at the Develop gate",
                    verify: "swift test",
                    verifyTimeoutMs: 120_000,
                    estimatedDifficulty: .medium
                ),
                midTerm: "",
                longTerm: ""
            )
            project.phase = .paused
            project.isPaused = true
            project.languageProfile = languageProfile(primaryLanguage: .swift)
            project.activityProfile = activityProfile(worktreeChanges: worktreeChanges(modified: 1))
            let cue = try XCTUnwrap(
                project.recordPlanReadinessNativeFeedback(
                    state: project.state,
                    gate: .pausedBeforeDevelop,
                    now: now
                )
            )

            let report = CinematicDiagnostics.currentReport(for: project)

            XCTAssertEqual(cue.milestone, .developReady)
            XCTAssertEqual(cue.sourceIdentifier, "plan-readiness:ready")
            XCTAssertEqual(cue.styleIdentifier, "verify")
            XCTAssertEqual(report.nativeFeedback.cueIdentifier, cue.identifier)
            XCTAssertEqual(report.nativeFeedback.sourceIdentifier, "plan-readiness:ready")
            XCTAssertEqual(report.nativeFeedback.milestoneIdentifier, "developReady")
            XCTAssertEqual(report.nativeFeedback.styleIdentifier, "verify")
            XCTAssertEqual(report.narrativeCue.nativeFeedbackSourceIdentifier, "plan-readiness:ready")
            XCTAssertEqual(report.narrativeCue.nativeFeedbackMilestoneIdentifier, "developReady")
            XCTAssertEqual(report.narrativeCue.questPlaque.plaqueTreatmentAccentIdentifier, "verify-seal")
            XCTAssertEqual(report.narrativeCue.questPlaque.plaqueTreatmentRouteIdentifier, "developReady.verify")
            XCTAssertEqual(
                report.narrativeCue.questPlaque.plaqueTreatmentRenderPrimitiveIdentifiers,
                ["rail.top", "rail.bottom", "seal.left", "seal.right"]
            )
            XCTAssertEqual(report.overlayDisplay.nativeFeedbackCueIdentifier, cue.identifier)
            XCTAssertEqual(
                report.overlayDisplay.nativeFeedbackLifecycleIdentifier,
                project.cinematicNativeFeedbackCueLifecycle.identifier
            )
            let activeHistory = try XCTUnwrap(report.nativeFeedback.lifecycleActiveHistoryEntry)
            XCTAssertEqual(activeHistory.milestoneIdentifier, "developReady")
            XCTAssertEqual(activeHistory.sourceIdentifier, "plan-readiness:ready")
            XCTAssertEqual(activeHistory.styleIdentifier, "verify")

            let summary = CinematicDiagnosticsSummary(
                report: report,
                visualSmoke: CinematicVisualSmokeReport(reports: [report])
            )
            XCTAssertTrue(summary.exportText.contains("source plan-readiness:ready"))
            XCTAssertTrue(summary.exportText.contains("milestone developReady"))
            XCTAssertTrue(summary.exportText.contains("treatment verify-seal/developReady.verify"))
            XCTAssertTrue(summary.exportText.contains("primitives rail.top,rail.bottom,seal.left,seal.right"))
            let historyRow = try XCTUnwrap(summary.rows.first { $0.id == "native-feedback-history" })
            assertNativeFeedbackHistoryExport(
                summary.nativeFeedbackHistoryExport,
                row: historyRow,
                activeCount: 1,
                archivedCount: 0,
                omittedCount: 0,
                requiredTokens: [
                    "#1 active",
                    "milestone developReady",
                    "source plan-readiness:ready",
                    "style verify",
                    "duration 8.0000s",
                    "lifecycle \(cue.lifecycleIdentifier)"
                ],
                forbiddenTokens: [
                    cue.title,
                    cue.detail,
                    NativeFeedbackContent(
                        readinessPlan: CinematicPlanCompassReadinessPlan(
                            state: project.state,
                            planCompassPlan: CinematicPlanCompassPlan(state: project.state),
                            reliabilityFeedback: PlanReliabilityFeedback(state: project.state, sessions: project.sessions)
                        ),
                        projectName: "ReadinessNativeDiagnosticsRepo"
                    ).body
                ]
            )
        }
    }

    func testCurrentReportExportsReplacedNativeFeedbackHistory() async throws {
        try await MainActor.run {
            let now = Date(timeIntervalSinceReferenceDate: 5_500)
            let repoURL = URL(fileURLWithPath: "/tmp/ReplacedNativeDiagnosticsRepo", isDirectory: true)
            let project = CompassProject(
                repoURL: repoURL,
                nativeFeedbackMode: .notifications
            )
            project.state = PlanState(
                completed: ["Recorded first cue"],
                immediate: PlanNext(
                    plan: "Replace native feedback cue",
                    verify: "swift test"
                ),
                midTerm: "",
                longTerm: ""
            )
            project.phase = .verifying
            project.languageProfile = languageProfile(primaryLanguage: .swift)
            project.activityProfile = activityProfile(recentCommitCount: 1)
            project.recordCinematicNativeFeedback(.verifyStarted, now: now)
            let firstCue = try XCTUnwrap(project.cinematicNativeFeedbackCue)
            project.phase = .developing
            project.recordCinematicNativeFeedback(.developStarted, now: now.addingTimeInterval(1))
            let secondCue = try XCTUnwrap(project.cinematicNativeFeedbackCue)

            let report = CinematicDiagnostics.currentReport(for: project)
            let activeHistory = try XCTUnwrap(report.nativeFeedback.lifecycleActiveHistoryEntry)
            let archivedHistory = try XCTUnwrap(report.nativeFeedback.lifecycleArchiveHistoryEntries.first)

            XCTAssertEqual(activeHistory.sequence, 2)
            XCTAssertEqual(activeHistory.stateIdentifier, "active")
            XCTAssertNil(activeHistory.reasonIdentifier)
            XCTAssertEqual(activeHistory.milestoneIdentifier, "developStarted")
            XCTAssertEqual(activeHistory.sourceIdentifier, "native:developStarted")
            XCTAssertEqual(activeHistory.styleIdentifier, "develop")
            XCTAssertEqual(activeHistory.cueIdentifier, secondCue.identifier)
            XCTAssertEqual(archivedHistory.sequence, 1)
            XCTAssertEqual(archivedHistory.stateIdentifier, "archived")
            XCTAssertEqual(archivedHistory.reasonIdentifier, "replaced")
            XCTAssertEqual(archivedHistory.milestoneIdentifier, "verifyStarted")
            XCTAssertEqual(archivedHistory.sourceIdentifier, "native:verifyStarted")
            XCTAssertEqual(archivedHistory.styleIdentifier, "verify")
            XCTAssertEqual(archivedHistory.cueIdentifier, firstCue.identifier)
            XCTAssertEqual(report.nativeFeedback.lifecycleHistoryEntryCount, 2)

            let summary = CinematicDiagnosticsSummary(
                report: report,
                visualSmoke: CinematicVisualSmokeReport(reports: [report])
            )
            let historyRow = try XCTUnwrap(summary.rows.first { $0.id == "native-feedback-history" })
            XCTAssertTrue(historyRow.detail.contains("#2 active"))
            XCTAssertTrue(historyRow.detail.contains("#1 archived/replaced"))
            XCTAssertTrue(historyRow.detail.contains("milestone developStarted"))
            XCTAssertTrue(historyRow.detail.contains("milestone verifyStarted"))
            XCTAssertTrue(summary.exportText.contains("Native feedback history:"))
            XCTAssertTrue(summary.exportText.contains("archived/replaced"))
            assertNativeFeedbackHistoryExport(
                summary.nativeFeedbackHistoryExport,
                row: historyRow,
                activeCount: 1,
                archivedCount: 1,
                omittedCount: 0,
                requiredTokens: [
                    "#2 active",
                    "#1 archived/replaced",
                    "milestone developStarted",
                    "milestone verifyStarted",
                    "source native:developStarted",
                    "source native:verifyStarted",
                    "lifecycle \(secondCue.lifecycleIdentifier)",
                    "lifecycle \(archivedHistory.lifecycleIdentifier)"
                ]
            )
        }
    }

    func testCurrentReportExportsExpiredNativeFeedbackLifecycleArchive() async throws {
        try await MainActor.run {
            let now = Date(timeIntervalSinceReferenceDate: 5_000)
            let repoURL = URL(fileURLWithPath: "/tmp/ExpiredNativeDiagnosticsRepo", isDirectory: true)
            let project = CompassProject(
                repoURL: repoURL,
                cinematicInfluenceSettings: CinematicInfluenceSettings(
                    cameraStyle: .follow,
                    comfortMode: .quiet,
                    intensity: 0.65
                ),
                nativeFeedbackMode: .notifications
            )
            project.state = PlanState(
                completed: ["Implemented native cue lifecycle"],
                immediate: PlanNext(
                    plan: "Expire native feedback cue",
                    verify: "swift test"
                ),
                midTerm: "",
                longTerm: ""
            )
            project.phase = .verifying
            project.languageProfile = languageProfile(primaryLanguage: .swift)
            project.activityProfile = activityProfile(recentCommitCount: 1)
            project.recordCinematicNativeFeedback(.verifyStarted, now: now)
            let activeCue = try XCTUnwrap(project.cinematicNativeFeedbackCue)

            XCTAssertTrue(
                project.expireCinematicNativeFeedbackCue(
                    now: now.addingTimeInterval(CinematicNativeFeedbackCueLifecycle.standardDisplayDuration)
                )
            )

            let report = CinematicDiagnostics.currentReport(for: project)
            let archive = try XCTUnwrap(project.cinematicNativeFeedbackCueLifecycle.recentArchive.first)
            XCTAssertNil(project.cinematicNativeFeedbackCue)
            XCTAssertEqual(archive.cueIdentifier, activeCue.identifier)
            XCTAssertEqual(archive.archiveReason, .expired)
            XCTAssertEqual(report.nativeFeedback.cueIdentifier, "none")
            XCTAssertEqual(report.nativeFeedback.lifecycleStateIdentifier, "expired")
            XCTAssertEqual(report.nativeFeedback.lifecycleRecentArchiveCount, 1)
            XCTAssertEqual(report.nativeFeedback.lifecycleRecentArchiveIdentifiers, [archive.lifecycleIdentifier])
            XCTAssertNil(report.nativeFeedback.lifecycleActiveHistoryEntry)
            let archivedHistory = try XCTUnwrap(report.nativeFeedback.lifecycleArchiveHistoryEntries.first)
            XCTAssertEqual(archivedHistory.sequence, 1)
            XCTAssertEqual(archivedHistory.stateIdentifier, "archived")
            XCTAssertEqual(archivedHistory.reasonIdentifier, "expired")
            XCTAssertEqual(archivedHistory.milestoneIdentifier, "verifyStarted")
            XCTAssertEqual(archivedHistory.sourceIdentifier, "native:verifyStarted")
            XCTAssertEqual(archivedHistory.styleIdentifier, "verify")
            XCTAssertEqual(archivedHistory.displayDuration, CinematicNativeFeedbackCueLifecycle.standardDisplayDuration)
            XCTAssertEqual(archivedHistory.lifecycleIdentifier, archive.lifecycleIdentifier)
            XCTAssertEqual(archivedHistory.cueIdentifier, activeCue.identifier)
            XCTAssertEqual(report.nativeFeedback.lifecycleHistoryEntryCount, 1)
            XCTAssertEqual(report.overlayDisplay.nativeFeedbackCueIdentifier, "none")
            XCTAssertEqual(report.overlayDisplay.nativeFeedbackLifecycleIdentifier, project.cinematicNativeFeedbackCueLifecycle.identifier)
            XCTAssertFalse(report.overlayDisplay.showsNativeFeedbackBanner)
            XCTAssertEqual(report.overlayDisplay.nativeFeedbackBannerPolicyIdentifier, "none")
            XCTAssertEqual(report.narrativeCue.nativeFeedbackCueIdentifier, "none")

            let summary = CinematicDiagnosticsSummary(
                report: report,
                visualSmoke: CinematicVisualSmokeReport(reports: [report])
            )
            XCTAssertTrue(summary.exportText.contains("native-lifecycle \(project.cinematicNativeFeedbackCueLifecycle.identifier)"))
            XCTAssertTrue(summary.exportText.contains("state:expired"))
            XCTAssertTrue(summary.exportText.contains("reason:expired"))
            XCTAssertTrue(summary.exportText.contains("Native feedback history:"))
            XCTAssertTrue(summary.exportText.contains("#1 archived/expired"))
            let historyRow = try XCTUnwrap(summary.rows.first { $0.id == "native-feedback-history" })
            assertNativeFeedbackHistoryExport(
                summary.nativeFeedbackHistoryExport,
                row: historyRow,
                activeCount: 0,
                archivedCount: 1,
                omittedCount: 0,
                requiredTokens: [
                    "#1 archived/expired",
                    "milestone verifyStarted",
                    "source native:verifyStarted",
                    "style verify",
                    "duration 8.0000s",
                    "lifecycle \(archive.lifecycleIdentifier)"
                ],
                forbiddenTokens: [
                    activeCue.title,
                    activeCue.detail,
                    NativeFeedbackContent(milestone: .verifyStarted, projectName: "ExpiredNativeDiagnosticsRepo").body
                ]
            )
        }
    }

    func testCurrentReportExportsModeOffNativeFeedbackHistory() async throws {
        try await MainActor.run {
            let now = Date(timeIntervalSinceReferenceDate: 6_000)
            let repoURL = URL(fileURLWithPath: "/tmp/ModeOffNativeDiagnosticsRepo", isDirectory: true)
            let project = CompassProject(
                repoURL: repoURL,
                nativeFeedbackMode: .notifications
            )
            project.phase = .verifying
            project.languageProfile = languageProfile(primaryLanguage: .swift)
            project.activityProfile = activityProfile(recentCommitCount: 1)
            project.recordCinematicNativeFeedback(.verifyStarted, now: now)
            project.nativeFeedbackMode = .off

            let report = CinematicDiagnostics.currentReport(for: project)
            XCTAssertEqual(report.nativeFeedback.lifecycleStateIdentifier, "archived")
            XCTAssertEqual(report.nativeFeedback.lifecycleRecentArchiveCount, 1)
            let archivedHistory = try XCTUnwrap(report.nativeFeedback.lifecycleArchiveHistoryEntries.first)
            XCTAssertEqual(archivedHistory.stateIdentifier, "archived")
            XCTAssertEqual(archivedHistory.reasonIdentifier, "mode-off")
            XCTAssertEqual(archivedHistory.milestoneIdentifier, "verifyStarted")
            XCTAssertEqual(archivedHistory.sourceIdentifier, "native:verifyStarted")
            XCTAssertEqual(archivedHistory.styleIdentifier, "verify")

            let summary = CinematicDiagnosticsSummary(
                report: report,
                visualSmoke: CinematicVisualSmokeReport(reports: [report])
            )
            let historyRow = try XCTUnwrap(summary.rows.first { $0.id == "native-feedback-history" })
            XCTAssertTrue(historyRow.detail.contains("archived/mode-off"))
            XCTAssertTrue(summary.exportText.contains("archived/mode-off"))
            assertNativeFeedbackHistoryExport(
                summary.nativeFeedbackHistoryExport,
                row: historyRow,
                activeCount: 0,
                archivedCount: 1,
                omittedCount: 0,
                requiredTokens: [
                    "#1 archived/mode-off",
                    "milestone verifyStarted",
                    "source native:verifyStarted",
                    "style verify",
                    "duration 8.0000s"
                ],
                forbiddenTokens: [
                    NativeFeedbackContent(milestone: .verifyStarted, projectName: "ModeOffNativeDiagnosticsRepo").body
                ]
            )
        }
    }

    func testNativeFeedbackHistoryBoundsArchiveEntriesAndSummaryDetail() throws {
        let now = Date(timeIntervalSinceReferenceDate: 6_500)
        let cue = try XCTUnwrap(
            CinematicNativeFeedbackCuePlanner.plan(
                milestone: .verifyStarted,
                content: NativeFeedbackContent(milestone: .verifyStarted, projectName: "Bounded History"),
                phase: .verifying,
                feedbackMode: .notifications,
                recentRunCues: [:]
            )
        )
        let recordCount = CinematicNativeFeedbackCueLifecycle.recentArchiveLimit + 4
        var lifecycle = CinematicNativeFeedbackCueLifecycle()
        var activeCue: CinematicNativeFeedbackCuePlan?

        for offset in 0..<recordCount {
            activeCue = lifecycle.record(cue, now: now.addingTimeInterval(Double(offset)))
        }

        let report = CinematicDiagnostics.report(
            repoName: "Bounded History",
            phase: LoopPhase.verifying.rawValue,
            immediateTitle: "Bound native feedback archive diagnostics",
            completedCount: 2,
            latestEvent: nil,
            languageProfile: languageProfile(primaryLanguage: .swift),
            activityProfile: activityProfile(recentCommitCount: 1),
            influenceSettings: CinematicInfluenceSettings(),
            nativeFeedbackCue: try XCTUnwrap(activeCue),
            nativeFeedbackLifecycle: lifecycle
        )

        XCTAssertEqual(
            report.nativeFeedback.lifecycleArchiveHistoryEntries.count,
            CinematicNativeFeedbackCueLifecycle.recentArchiveLimit
        )
        XCTAssertEqual(
            report.nativeFeedback.lifecycleHistoryEntryCount,
            CinematicNativeFeedbackCueLifecycle.recentArchiveLimit + 1
        )
        XCTAssertEqual(report.nativeFeedback.lifecycleActiveHistoryEntry?.sequence, recordCount)
        XCTAssertEqual(
            report.nativeFeedback.lifecycleArchiveHistoryEntries.map(\.sequence),
            Array(
                Array((recordCount - CinematicNativeFeedbackCueLifecycle.recentArchiveLimit)..<recordCount)
                    .reversed()
            )
        )

        let summary = CinematicDiagnosticsSummary(
            report: report,
            visualSmoke: CinematicVisualSmokeReport(reports: [report])
        )
        let historyRow = try XCTUnwrap(summary.rows.first { $0.id == "native-feedback-history" })
        XCTAssertLessThanOrEqual(historyRow.detail.count, CinematicDiagnosticsSummary.detailMaxCharacters)
        XCTAssertTrue(historyRow.detail.contains("#\(recordCount) active"))
        XCTAssertTrue(historyRow.detail.contains("#\(recordCount - 1) archived/replaced"))
        XCTAssertTrue(summary.exportText.contains("Native feedback history:"))
        assertNativeFeedbackHistoryExport(
            summary.nativeFeedbackHistoryExport,
            row: historyRow,
            activeCount: 1,
            archivedCount: CinematicNativeFeedbackCueLifecycle.recentArchiveLimit,
            omittedCount: recordCount - (CinematicNativeFeedbackCueLifecycle.recentArchiveLimit + 1),
            requiredTokens: [
                "#\(recordCount) active",
                "#\(recordCount - 1) archived/replaced",
                "#\(recordCount - CinematicNativeFeedbackCueLifecycle.recentArchiveLimit) archived/replaced",
                "milestone verifyStarted",
                "source native:verifyStarted",
                "style verify",
                "duration 8.0000s"
            ],
            forbiddenTokens: [
                "#1 archived/replaced",
                "#2 archived/replaced",
                "#3 archived/replaced",
                cue.title,
                cue.detail
            ]
        )
    }

    func testRunRecapDiagnosticsExposeAvailabilityAndExportRows() throws {
        let session = diagnosticsSession(
            12,
            status: .succeeded,
            commits: [
                SessionCommit(
                    sha: "abcdef1234567890",
                    short: "abcdef1",
                    subject: "Add cinematic recap diagnostics"
                )
            ],
            endedAt: 12_500
        )
        let state = PlanState(
            completed: ["Completed recap diagnostics"],
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
                12: diagnosticsRunCue(
                    kind: .failedVerify,
                    severity: .failure,
                    label: "Retry Develop",
                    detail: "verify failed before recap",
                    systemImage: "checkmark.seal.fill"
                )
            ],
            commitConstellationPlan: commitPlan,
            nativeFeedbackLifecycle: CinematicNativeFeedbackCueLifecycle()
        )
        let recapFocusPlan = CinematicRunRecapSceneFocusPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: recapPlan,
            commitConstellationPlan: commitPlan,
            timelinePlan: CinematicSessionTimelinePlan(sessions: [session])
        )
        let recapEndCardPlan = CinematicRunRecapEndCardPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: recapPlan
        )
        let recapSharePlan = CinematicRunRecapSharePlanner.plan(
            recapPlan: recapPlan,
            recapFocusDescriptor: recapFocusPlan.descriptor,
            endCardDescriptor: recapEndCardPlan.descriptor
        )
        let recapShareArtifactPlan = CinematicRunRecapShareArtifactPlanner.plan(
            sharePlan: recapSharePlan,
            sessions: [session]
        )
        let report = makeReport(
            CinematicDiagnosticsInput(
                repoName: "Compass",
                phase: "Succeeded",
                immediateTitle: "Expose recap diagnostics",
                completedCount: state.completed.count,
                latestEvent: nil,
                languageProfile: languageProfile(primaryLanguage: .swift),
                activityProfile: activityProfile(recentCommitCount: 1, lastTerminalStatus: .succeeded),
                influenceSettings: CinematicInfluenceSettings(),
                commitConstellationPlan: commitPlan,
                runRecapPlan: recapPlan,
                runRecapSceneFocusPlan: recapFocusPlan,
                runRecapEndCardPlan: recapEndCardPlan
            )
        )
        let focusDescriptor = try XCTUnwrap(recapFocusPlan.descriptor)
        let cardDescriptor = try XCTUnwrap(recapEndCardPlan.descriptor)

        XCTAssertTrue(report.runRecap.isAvailable)
        XCTAssertEqual(report.runRecap.identifier, recapPlan.identifier)
        XCTAssertEqual(report.runRecap.availabilityIdentifier, "available")
        XCTAssertEqual(report.runRecap.title, "Run #12 succeeded")
        XCTAssertEqual(report.runRecap.detail, "Completed recap diagnostics")
        XCTAssertEqual(report.runRecap.statusIdentifier, "succeeded")
        XCTAssertEqual(report.runRecap.styleIdentifier, "success")
        XCTAssertEqual(report.runRecap.colorIdentifier, "green")
        XCTAssertEqual(report.runRecap.completedCount, 1)
        XCTAssertEqual(report.runRecap.commitHighlightCount, 1)
        XCTAssertEqual(report.runRecap.eventChipCount, 1)
        XCTAssertEqual(report.runRecap.eventChipIdentifiers, recapPlan.eventChips.map(\.identifier))
        XCTAssertTrue(report.identifier.contains("run-recap:\(recapPlan.identifier)"))
        XCTAssertTrue(report.runRecapShare.isAvailable)
        XCTAssertEqual(report.runRecapShare.identifier, recapSharePlan.identifier)
        XCTAssertEqual(report.runRecapShare.recapIdentifier, recapPlan.identifier)
        XCTAssertEqual(report.runRecapShare.recapFocusIdentifier, focusDescriptor.identifier)
        XCTAssertEqual(report.runRecapShare.endCardIdentifier, cardDescriptor.identifier)
        XCTAssertEqual(report.runRecapShare.title, recapPlan.title)
        XCTAssertEqual(report.runRecapShare.detail, recapPlan.detail)
        XCTAssertEqual(report.runRecapShare.status, recapPlan.status)
        XCTAssertEqual(report.runRecapShare.commitHighlight, recapPlan.newestCommitHighlight)
        XCTAssertEqual(report.runRecapShare.eventSummaryCount, recapPlan.eventChipCount)
        XCTAssertEqual(report.runRecapShare.text, recapSharePlan.text)
        XCTAssertTrue(report.runRecapShare.visualDescriptorTokens.contains("focus-shot:victory"))
        XCTAssertTrue(report.runRecapShare.visualDescriptorTokens.contains("end-card-treatment:verify-seal"))
        XCTAssertTrue(report.identifier.contains("run-recap-share:\(recapSharePlan.identifier)"))
        XCTAssertTrue(report.runRecapShareArtifact.isAvailable)
        XCTAssertEqual(report.runRecapShareArtifact.identifier, recapShareArtifactPlan.identifier)
        XCTAssertEqual(report.runRecapShareArtifact.availabilityReason, "available")
        XCTAssertEqual(report.runRecapShareArtifact.sessionNumber, session.session)
        XCTAssertEqual(report.runRecapShareArtifact.filename, recapShareArtifactPlan.filename)
        XCTAssertEqual(report.runRecapShareArtifact.shareIdentifier, recapSharePlan.identifier)
        XCTAssertEqual(report.runRecapShareArtifact.recapIdentifier, recapPlan.identifier)
        XCTAssertEqual(report.runRecapShareArtifact.recapFocusIdentifier, focusDescriptor.identifier)
        XCTAssertEqual(report.runRecapShareArtifact.endCardIdentifier, cardDescriptor.identifier)
        XCTAssertEqual(report.runRecapShareArtifact.eventSummaryCount, recapSharePlan.eventSummaryCount)
        XCTAssertEqual(
            report.runRecapShareArtifact.visualDescriptorTokenCount,
            recapSharePlan.visualDescriptorTokenCount
        )
        XCTAssertEqual(report.runRecapShareArtifact.markdownLength, recapShareArtifactPlan.markdownLength)
        XCTAssertTrue(report.identifier.contains("run-recap-share-artifact:\(recapShareArtifactPlan.identifier)"))
        XCTAssertTrue(report.runRecapSceneFocus.isActive)
        XCTAssertEqual(report.runRecapSceneFocus.identifier, recapFocusPlan.identifier)
        XCTAssertEqual(report.runRecapSceneFocus.descriptorIdentifier, focusDescriptor.identifier)
        XCTAssertEqual(report.runRecapSceneFocus.terminalStatusIdentifier, "succeeded")
        XCTAssertEqual(report.runRecapSceneFocus.terminalStyleIdentifier, "success")
        XCTAssertEqual(report.runRecapSceneFocus.cameraShotIdentifier, "victory")
        XCTAssertEqual(report.runRecapSceneFocus.lightFamilyIdentifier, "verify")
        XCTAssertEqual(report.runRecapSceneFocus.arenaEffectIdentifier, "victory")
        XCTAssertEqual(report.runRecapSceneFocus.commitNodeIdentifier, commitPlan.nodes.first?.stableID)
        XCTAssertTrue(report.identifier.contains("run-recap-focus:\(recapFocusPlan.identifier)"))
        XCTAssertTrue(report.runRecapEndCard.isActive)
        XCTAssertEqual(report.runRecapEndCard.identifier, recapEndCardPlan.identifier)
        XCTAssertEqual(report.runRecapEndCard.descriptorIdentifier, cardDescriptor.identifier)
        XCTAssertEqual(report.runRecapEndCard.recapIdentifier, recapPlan.identifier)
        XCTAssertEqual(report.runRecapEndCard.title, recapPlan.title)
        XCTAssertEqual(report.runRecapEndCard.detail, recapPlan.detail)
        XCTAssertEqual(report.runRecapEndCard.status, recapPlan.status)
        XCTAssertEqual(report.runRecapEndCard.titleSourceIdentifier, "deterministic")
        XCTAssertEqual(report.runRecapEndCard.flavorStateIdentifier, "deterministic")
        XCTAssertEqual(report.runRecapEndCard.styleIdentifier, "success")
        XCTAssertEqual(report.runRecapEndCard.anchorIdentifier, "victory-arch")
        XCTAssertEqual(report.runRecapEndCard.glyphIdentifier, "recap.success.seal")
        XCTAssertEqual(report.runRecapEndCard.plaqueTreatmentAccentIdentifier, "verify-seal")
        XCTAssertLessThanOrEqual(report.runRecapEndCard.titleLength, CinematicRunRecapEndCardPlan.titleMaxCharacters)
        XCTAssertLessThanOrEqual(report.runRecapEndCard.detailLength, CinematicRunRecapEndCardPlan.detailMaxCharacters)
        XCTAssertLessThanOrEqual(report.runRecapEndCard.statusLength, CinematicRunRecapEndCardPlan.statusMaxCharacters)
        XCTAssertTrue(report.identifier.contains("run-recap-end-card:\(recapEndCardPlan.identifier)"))

        let summary = CinematicDiagnosticsSummary(
            report: report,
            visualSmoke: CinematicVisualSmokeReport(reports: [report])
        )
        let row = try XCTUnwrap(summary.rows.first { $0.id == "run-recap" })
        let shareRow = try XCTUnwrap(summary.rows.first { $0.id == "run-recap-share" })
        let artifactRow = try XCTUnwrap(summary.rows.first { $0.id == "run-recap-share-artifact" })
        let focusRow = try XCTUnwrap(summary.rows.first { $0.id == "run-recap-focus" })
        let cardRow = try XCTUnwrap(summary.rows.first { $0.id == "run-recap-end-card" })
        XCTAssertTrue(row.detail.contains("available"))
        XCTAssertTrue(row.detail.contains("title Run #12 succeeded"))
        XCTAssertTrue(row.detail.contains("completed 1"))
        XCTAssertTrue(row.detail.contains("commits 1"))
        XCTAssertTrue(row.detail.contains("events 1"))
        XCTAssertTrue(shareRow.detail.contains("available"))
        XCTAssertTrue(shareRow.detail.contains("share"))
        XCTAssertTrue(shareRow.detail.contains("recap"))
        XCTAssertTrue(shareRow.detail.contains("focus"))
        XCTAssertTrue(shareRow.detail.contains("end-card"))
        XCTAssertTrue(shareRow.detail.contains("copy"))
        XCTAssertTrue(shareRow.detail.contains("visual"))
        XCTAssertTrue(shareRow.detail.contains("focus-shot:victory"))
        XCTAssertTrue(shareRow.detail.contains("end-card-treatment:verify-seal"))
        XCTAssertTrue(artifactRow.detail.contains("available"))
        XCTAssertTrue(artifactRow.detail.contains("session 12"))
        XCTAssertTrue(artifactRow.detail.contains("file \(recapShareArtifactPlan.filename)"))
        XCTAssertTrue(artifactRow.detail.contains("artifact"))
        XCTAssertTrue(artifactRow.detail.contains("share"))
        XCTAssertTrue(artifactRow.detail.contains("recap"))
        XCTAssertTrue(artifactRow.detail.contains("focus"))
        XCTAssertTrue(artifactRow.detail.contains("end-card"))
        XCTAssertTrue(focusRow.detail.contains("active"))
        XCTAssertTrue(focusRow.detail.contains("descriptor \(focusDescriptor.identifier)"))
        XCTAssertTrue(focusRow.detail.contains("style success"))
        XCTAssertTrue(focusRow.detail.contains("shot victory"))
        XCTAssertTrue(focusRow.detail.contains("node \(commitPlan.nodes.first?.stableID ?? "")"))
        XCTAssertTrue(cardRow.detail.contains("active"))
        XCTAssertTrue(cardRow.detail.contains("title Run #12 succeeded"))
        XCTAssertTrue(cardRow.detail.contains("title-source deterministic"))
        XCTAssertTrue(cardRow.detail.contains("flavor deterministic"))
        XCTAssertTrue(cardRow.detail.contains("style success/green"))
        XCTAssertTrue(cardRow.detail.contains("anchor victory-arch"))
        XCTAssertTrue(cardRow.detail.contains("treatment verify-seal/recap.success"))
        XCTAssertTrue(cardRow.detail.contains("lengths"))
        XCTAssertTrue(summary.exportText.contains("Run recap: available"))
        XCTAssertTrue(summary.exportText.contains("Run recap share: available"))
        XCTAssertTrue(summary.exportText.contains("Recap share artifact: available"))
        XCTAssertTrue(summary.exportText.contains("file \(recapShareArtifactPlan.filename)"))
        XCTAssertTrue(summary.exportText.contains("focus-shot:victory"))
        XCTAssertTrue(summary.exportText.contains("end-card-treatment:verify-seal"))
        XCTAssertTrue(summary.exportText.contains("Run recap focus: active"))
        XCTAssertTrue(summary.exportText.contains("Run recap end card: active"))
        XCTAssertTrue(summary.exportText.contains("status 1 commit highlight"))
    }

    func testRunRecapEndCardDiagnosticsExposePinnedComparisonCueStateAndExport() throws {
        let reports = CinematicDiagnostics.representativePinnedComparisonCueSmokeReports()
        let activeReport = try XCTUnwrap(
            reports.first { $0.runRecapEndCard.pinnedComparisonCueStateIdentifier == "visible-pinned-target" }
        )
        let filteredReport = try XCTUnwrap(
            reports.first { $0.runRecapEndCard.pinnedComparisonCueStateIdentifier == "filtered-pinned-target" }
        )
        let promotedHoldReport = try XCTUnwrap(
            reports.first {
                $0.runRecapEndCard.pinnedComparisonCuePromotedHoldStateIdentifier
                    == "retained-promoted-hold-target"
            }
        )
        let filteredPromotedHoldReport = try XCTUnwrap(
            reports.first {
                $0.runRecapEndCard.pinnedComparisonCuePromotedHoldStateIdentifier
                    == "filtered-promoted-hold-target"
            }
        )
        let noMatchReport = try XCTUnwrap(
            reports.first {
                $0.runRecapEndCard.pinnedComparisonCueNoMatchStateIdentifier
                    == "no-matching-recap-share-artifacts"
            }
        )
        let activeCueIdentifier = try XCTUnwrap(activeReport.runRecapEndCard.pinnedComparisonCueIdentifier)
        let activeSummary = CinematicDiagnosticsSummary(
            report: activeReport,
            visualSmoke: CinematicVisualSmokeReport(reports: reports)
        )
        let activeRow = try XCTUnwrap(activeSummary.rows.first { $0.id == "run-recap-end-card" })

        XCTAssertTrue(activeReport.runRecapEndCard.hasPinnedComparisonCue)
        XCTAssertEqual(activeReport.runRecapEndCard.pinnedComparisonCueModeIdentifier, "pinned_reference")
        XCTAssertEqual(activeReport.runRecapEndCard.pinnedComparisonCueStateIdentifier, "visible-pinned-target")
        XCTAssertEqual(activeReport.runRecapEndCard.pinnedComparisonCueSelectedSessionNumber, 12)
        XCTAssertEqual(activeReport.runRecapEndCard.pinnedComparisonCueTargetSessionNumber, 10)
        XCTAssertEqual(activeReport.runRecapEndCard.pinnedComparisonCueDeltaLabel, "delta 2 sessions")
        XCTAssertEqual(activeReport.runRecapEndCard.pinnedComparisonCuePinnedEntryCount, 1)
        XCTAssertEqual(activeReport.runRecapEndCard.pinnedComparisonCueRetainedPinnedEntryCount, 1)
        XCTAssertEqual(activeReport.runRecapEndCard.pinnedComparisonCueMissingPinnedEntryCount, 0)
        XCTAssertEqual(activeReport.runRecapEndCard.pinnedComparisonCueFilteredPinnedEntryCount, 0)
        XCTAssertEqual(activeReport.runRecapEndCard.pinnedComparisonCueGlyphIdentifier, "pin.bridge.active")
        XCTAssertEqual(activeReport.runRecapEndCard.pinnedComparisonCueRailTreatmentIdentifier, "pin-bridge-rail")
        XCTAssertLessThanOrEqual(
            activeReport.runRecapEndCard.pinnedComparisonCueLabelLength,
            CinematicRunRecapEndCardPlan.pinnedComparisonLabelMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            activeReport.runRecapEndCard.pinnedComparisonCueDetailLength,
            CinematicRunRecapEndCardPlan.pinnedComparisonDetailMaxCharacters
        )
        XCTAssertTrue(activeReport.identifier.contains("run-recap-end-card-pinned-cue:\(activeCueIdentifier)"))
        XCTAssertTrue(activeReport.identifier.contains("run-recap-end-card-pinned-cue-mode:pinned_reference"))
        XCTAssertTrue(activeReport.identifier.contains("run-recap-end-card-pinned-cue-state:visible-pinned-target"))
        XCTAssertTrue(activeRow.detail.contains("pin cue visible-pinned-target"))
        XCTAssertTrue(activeRow.detail.contains("pin mode pinned_reference"))
        XCTAssertTrue(activeRow.detail.contains("pin sessions S12->S10"))
        XCTAssertTrue(activeRow.detail.contains("pin delta 2 sessions pin-bridge-rail"))
        XCTAssertTrue(activeSummary.exportText.contains("Run recap end card: active"))
        XCTAssertTrue(activeSummary.exportText.contains("pin cue visible-pinned-target"))
        XCTAssertTrue(activeSummary.exportText.contains("pin counts 1/1 stale 0 filtered 0"))

        XCTAssertTrue(filteredReport.runRecapEndCard.hasPinnedComparisonCue)
        XCTAssertEqual(filteredReport.runRecapEndCard.pinnedComparisonCueFilteredPinnedEntryCount, 1)
        XCTAssertEqual(filteredReport.runRecapEndCard.pinnedComparisonCueGlyphIdentifier, "pin.bridge.filtered")
        XCTAssertEqual(filteredReport.runRecapEndCard.pinnedComparisonCueRailTreatmentIdentifier, "filtered-pin-rail")

        XCTAssertTrue(promotedHoldReport.runRecapEndCard.hasPinnedComparisonCue)
        XCTAssertEqual(
            promotedHoldReport.runRecapEndCard.pinnedComparisonCueGlyphIdentifier,
            "hold.pin.bridge.active"
        )
        XCTAssertEqual(
            promotedHoldReport.runRecapEndCard.pinnedComparisonCueRailTreatmentIdentifier,
            "promoted-hold-rail"
        )
        XCTAssertTrue(promotedHoldReport.runRecapEndCard.pinnedComparisonCueLabel.contains("Promoted hold"))
        XCTAssertTrue(promotedHoldReport.runRecapEndCard.pinnedComparisonCueDetail.contains("held artifact"))
        XCTAssertTrue(
            promotedHoldReport.identifier.contains(
                "run-recap-end-card-pinned-cue-promoted-hold:retained-promoted-hold-target"
            )
        )

        XCTAssertTrue(filteredPromotedHoldReport.runRecapEndCard.hasPinnedComparisonCue)
        XCTAssertEqual(
            filteredPromotedHoldReport.runRecapEndCard.pinnedComparisonCueGlyphIdentifier,
            "hold.pin.bridge.filtered"
        )
        XCTAssertEqual(
            filteredPromotedHoldReport.runRecapEndCard.pinnedComparisonCueRailTreatmentIdentifier,
            "filtered-promoted-hold-rail"
        )

        XCTAssertFalse(noMatchReport.runRecapEndCard.hasPinnedComparisonCue)
        XCTAssertEqual(noMatchReport.runRecapEndCard.pinnedComparisonCueStateIdentifier, "no-selected-recap-share-artifact")
        XCTAssertEqual(
            noMatchReport.runRecapEndCard.pinnedComparisonCueNoMatchStateIdentifier,
            "no-matching-recap-share-artifacts"
        )
    }

    func testRunRecapDiagnosticsExposeAppliedAndStaleFlavorState() throws {
        let session = diagnosticsSession(
            13,
            status: .succeeded,
            commits: [
                SessionCommit(
                    sha: "abcdef1234567890",
                    short: "abcdef1",
                    subject: "Add recap flavor diagnostics"
                )
            ],
            endedAt: 13_500
        )
        let state = PlanState(
            completed: ["Completed recap flavor diagnostics"],
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
        let flavor = try XCTUnwrap(
            CinematicRunRecapFlavorService.parseGeneratedFlavor(
                """
                Title: Flavor Diagnostics Sealed
                Detail: Compass completed recap flavor diagnostics with the newest commit signal.
                """,
                sourceIdentifier: flavorInput.sourceIdentifier
            )
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
        let endCardPlan = CinematicRunRecapEndCardPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: recapPlan
        )
        let report = makeReport(
            CinematicDiagnosticsInput(
                repoName: "Compass",
                phase: "Succeeded",
                immediateTitle: "Expose recap flavor diagnostics",
                completedCount: state.completed.count,
                latestEvent: nil,
                languageProfile: languageProfile(primaryLanguage: .swift),
                activityProfile: activityProfile(recentCommitCount: 1, lastTerminalStatus: .succeeded),
                influenceSettings: CinematicInfluenceSettings(),
                commitConstellationPlan: commitPlan,
                runRecapPlan: recapPlan,
                runRecapEndCardPlan: endCardPlan
            )
        )
        let summary = CinematicDiagnosticsSummary(report: report)
        let row = try XCTUnwrap(summary.rows.first { $0.id == "run-recap" })
        let shareRow = try XCTUnwrap(summary.rows.first { $0.id == "run-recap-share" })
        let cardRow = try XCTUnwrap(summary.rows.first { $0.id == "run-recap-end-card" })

        XCTAssertEqual(report.runRecap.title, "Flavor Diagnostics Sealed")
        XCTAssertEqual(report.runRecap.flavorStateIdentifier, "applied")
        XCTAssertEqual(report.runRecap.flavorIdentifier, flavor.identifier)
        XCTAssertEqual(report.runRecap.flavorSourceIdentifier, flavorInput.sourceIdentifier)
        XCTAssertEqual(report.runRecap.titleSourceIdentifier, "generated")
        XCTAssertEqual(report.runRecapEndCard.title, "Flavor Diagnostics Sealed")
        XCTAssertEqual(report.runRecapEndCard.titleSourceIdentifier, "generated")
        XCTAssertEqual(report.runRecapEndCard.flavorStateIdentifier, "applied")
        XCTAssertEqual(report.runRecapEndCard.flavorIdentifier, flavor.identifier)
        XCTAssertTrue(row.detail.contains("flavor applied"))
        XCTAssertTrue(row.detail.contains("title-source generated"))
        XCTAssertEqual(report.runRecapShare.title, "Flavor Diagnostics Sealed")
        XCTAssertTrue(report.runRecapShare.visualDescriptorTokens.contains("title-source:generated"))
        XCTAssertTrue(report.runRecapShare.visualDescriptorTokens.contains("flavor-state:applied"))
        XCTAssertTrue(shareRow.detail.contains("title-source:generated"))
        XCTAssertTrue(shareRow.detail.contains("flavor-state:applied"))
        XCTAssertTrue(cardRow.detail.contains("flavor applied"))
        XCTAssertTrue(cardRow.detail.contains("title-source generated"))
        XCTAssertTrue(summary.exportText.contains("Run recap: available"))
        XCTAssertTrue(summary.exportText.contains("Run recap share: available"))
        XCTAssertTrue(summary.exportText.contains("Run recap end card: active"))
        XCTAssertTrue(summary.exportText.contains("flavor applied"))

        let staleFlavor = CinematicRunRecapFlavor(
            sourceIdentifier: "\(flavorInput.sourceIdentifier)|old",
            title: "Older Flavor Diagnostics",
            detail: "Older flavor should stay diagnostic only.",
            titleSource: .generated
        )
        let stalePlan = CinematicRunRecapPlanner.plan(
            state: state,
            sessions: [session],
            isRunning: false,
            isAutoPlaying: false,
            recentRunCues: [:],
            commitConstellationPlan: commitPlan,
            nativeFeedbackLifecycle: CinematicNativeFeedbackCueLifecycle(),
            flavor: staleFlavor
        )
        let staleEndCardPlan = CinematicRunRecapEndCardPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: stalePlan
        )
        let staleReport = makeReport(
            CinematicDiagnosticsInput(
                repoName: "Compass",
                phase: "Succeeded",
                immediateTitle: "Expose stale recap flavor diagnostics",
                completedCount: state.completed.count,
                latestEvent: nil,
                languageProfile: languageProfile(primaryLanguage: .swift),
                activityProfile: activityProfile(recentCommitCount: 1, lastTerminalStatus: .succeeded),
                influenceSettings: CinematicInfluenceSettings(),
                commitConstellationPlan: commitPlan,
                runRecapPlan: stalePlan,
                runRecapEndCardPlan: staleEndCardPlan
            )
        )
        let staleSummary = CinematicDiagnosticsSummary(report: staleReport)

        XCTAssertEqual(staleReport.runRecap.title, "Run #13 succeeded")
        XCTAssertEqual(staleReport.runRecap.flavorStateIdentifier, "stale")
        XCTAssertEqual(staleReport.runRecap.flavorIdentifier, staleFlavor.identifier)
        XCTAssertEqual(staleReport.runRecap.titleSourceIdentifier, "deterministic")
        XCTAssertEqual(staleReport.runRecapEndCard.title, "Run #13 succeeded")
        XCTAssertEqual(staleReport.runRecapEndCard.flavorStateIdentifier, "stale")
        XCTAssertEqual(staleReport.runRecapEndCard.flavorIdentifier, staleFlavor.identifier)
        XCTAssertEqual(staleReport.runRecapEndCard.titleSourceIdentifier, "deterministic")
        XCTAssertTrue(staleSummary.exportText.contains("flavor stale"))
        XCTAssertTrue(staleSummary.exportText.contains("title-source deterministic"))
    }

    func testEmptyRunRecapDiagnosticsExplainWhyRecapIsUnavailable() {
        let report = makeReport(
            CinematicDiagnosticsInput(
                repoName: "Compass",
                phase: "Developing",
                immediateTitle: "Keep empty recap explainable",
                completedCount: 0,
                latestEvent: nil,
                languageProfile: languageProfile(primaryLanguage: .swift),
                activityProfile: activityProfile(),
                influenceSettings: CinematicInfluenceSettings(),
                runRecapPlan: .empty(reason: "active-run")
            )
        )
        let summary = CinematicDiagnosticsSummary(
            report: report,
            visualSmoke: CinematicVisualSmokeReport(reports: [report])
        )
        let row = summary.rows.first { $0.id == "run-recap" }
        let shareRow = summary.rows.first { $0.id == "run-recap-share" }
        let artifactRow = summary.rows.first { $0.id == "run-recap-share-artifact" }
        let focusRow = summary.rows.first { $0.id == "run-recap-focus" }
        let cardRow = summary.rows.first { $0.id == "run-recap-end-card" }

        XCTAssertFalse(report.runRecap.isAvailable)
        XCTAssertEqual(report.runRecap.availabilityIdentifier, "active-run")
        XCTAssertEqual(report.runRecap.identifier, "run-recap.empty|reason:active-run")
        XCTAssertFalse(report.runRecapShare.isAvailable)
        XCTAssertEqual(report.runRecapShare.availabilityReason, "active-run")
        XCTAssertEqual(report.runRecapShare.recapIdentifier, report.runRecap.identifier)
        XCTAssertTrue(report.runRecapShare.text.contains("Availability: unavailable (active-run)"))
        XCTAssertFalse(report.runRecapShareArtifact.isAvailable)
        XCTAssertEqual(report.runRecapShareArtifact.availabilityReason, "active-run")
        XCTAssertNil(report.runRecapShareArtifact.sessionNumber)
        XCTAssertEqual(report.runRecapShareArtifact.shareIdentifier, report.runRecapShare.identifier)
        XCTAssertEqual(report.runRecapShareArtifact.recapIdentifier, report.runRecap.identifier)
        XCTAssertFalse(report.runRecapSceneFocus.isActive)
        XCTAssertEqual(report.runRecapSceneFocus.identifier, "run-recap-scene-focus.none")
        XCTAssertFalse(report.runRecapEndCard.isActive)
        XCTAssertEqual(report.runRecapEndCard.identifier, "run-recap-end-card.none")
        XCTAssertTrue(row?.detail.contains("empty active-run") == true)
        XCTAssertTrue(shareRow?.detail.contains("empty active-run") == true)
        XCTAssertTrue(artifactRow?.detail.contains("empty active-run") == true)
        XCTAssertEqual(focusRow?.detail, "empty")
        XCTAssertEqual(cardRow?.detail, "empty")
        XCTAssertTrue(summary.exportText.contains("Run recap: empty active-run"))
        XCTAssertTrue(summary.exportText.contains("Run recap share: empty active-run"))
        XCTAssertTrue(summary.exportText.contains("Recap share artifact: empty active-run"))
        XCTAssertTrue(summary.exportText.contains("Run recap focus: empty"))
        XCTAssertTrue(summary.exportText.contains("Run recap end card: empty"))
    }

    func testRunRecapArtifactHistoryDiagnosticsExposeLibraryExportAndWarnings() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "CinematicDiagnosticsArtifactHistory-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let workspace = CompassWorkspace(repoURL: temporaryDirectory, storageRootURL: temporaryDirectory.appending(path: ".compass"))
        try FileManager.default.createDirectory(at: temporaryDirectory.appending(path: ".git"), withIntermediateDirectories: true)
        try workspace.initialize()
        _ = try workspace.writeSessionArtifact(
            session: 17,
            name: "recap-share-diagnostics.md",
            contents: """
            # Compass Run Recap Share

            - Artifact: diagnostics-artifact
            - Availability: available
            - Session: 17
            - Filename: recap-share-diagnostics.md
            - Share: share-id
            - Recap: recap-id
            - Focus: focus-id
            - End card: end-card-id
            - Title: Diagnostics Recap
            - Status: succeeded
            - Detail: Diagnostics detail
            - Commit: Diagnostics commit
            """
        )
        _ = try workspace.writeSessionArtifact(
            session: 18,
            name: "recap-share-corrupt.md",
            contents: "corrupt diagnostics artifact"
        )
        let historyPlan = workspace.refreshRunRecapShareArtifactHistory()
        let previewPlan = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: historyPlan
        )
        let rollupPlan = CinematicRunRecapShareArtifactRollupPlanner.plan(
            historyPlan: historyPlan
        )

        let report = makeReport(
            CinematicDiagnosticsInput(
                repoName: "Compass",
                phase: "Succeeded",
                immediateTitle: "Expose recap artifact history",
                completedCount: 3,
                latestEvent: nil,
                languageProfile: languageProfile(primaryLanguage: .swift),
                activityProfile: activityProfile(recentCommitCount: 1, lastTerminalStatus: .succeeded),
                influenceSettings: CinematicInfluenceSettings(),
                runRecapShareArtifactHistoryPlan: historyPlan
            )
        )
        let summary = CinematicDiagnosticsSummary(
            report: report,
            visualSmoke: CinematicVisualSmokeReport(reports: [report])
        )
        let row = try XCTUnwrap(summary.rows.first { $0.id == "run-recap-share-artifact-history" })
        let rollupRow = try XCTUnwrap(summary.rows.first { $0.id == "run-recap-share-artifact-rollup" })
        let previewRow = try XCTUnwrap(summary.rows.first { $0.id == "run-recap-share-artifact-preview" })

        XCTAssertTrue(report.runRecapShareArtifactHistory.isAvailable)
        XCTAssertEqual(report.runRecapShareArtifactHistory.totalCount, 1)
        XCTAssertEqual(report.runRecapShareArtifactHistory.hiddenCount, 0)
        XCTAssertEqual(report.runRecapShareArtifactHistory.retentionLimit, historyPlan.retentionLimit)
        XCTAssertEqual(report.runRecapShareArtifactHistory.cleanupCandidateCount, 0)
        XCTAssertEqual(report.runRecapShareArtifactHistory.hiddenCleanupCandidateCount, 0)
        XCTAssertEqual(report.runRecapShareArtifactHistory.cleanupCandidateIdentifiers, [])
        XCTAssertEqual(report.runRecapShareArtifactHistory.latestSessionNumber, 17)
        XCTAssertEqual(report.runRecapShareArtifactHistory.latestFilename, "17-recap-share-diagnostics.md")
        XCTAssertEqual(report.runRecapShareArtifactHistory.warningCount, 1)
        XCTAssertEqual(report.runRecapShareArtifactHistory.warningIdentifiers.count, 1)
        XCTAssertEqual(report.runRecapShareArtifactHistory.warningStateIdentifier, "warnings")
        XCTAssertEqual(report.runRecapShareArtifactHistory.lastCleanupResultIdentifier, "none")
        XCTAssertEqual(report.runRecapShareArtifactHistory.lastCleanupResultStatus, "none")
        XCTAssertEqual(report.runRecapShareArtifactHistory.exportIdentifier, historyPlan.exportIdentifier)
        XCTAssertEqual(report.runRecapShareArtifactHistory.exportMarkdownLength, historyPlan.combinedMarkdownLength)
        XCTAssertTrue(report.runRecapShareArtifactPreview.isAvailable)
        XCTAssertTrue(report.runRecapShareArtifactRollup.isAvailable)
        XCTAssertEqual(report.runRecapShareArtifactRollup.identifier, rollupPlan.identifier)
        XCTAssertEqual(report.runRecapShareArtifactRollup.exportIdentifier, rollupPlan.exportIdentifier)
        XCTAssertEqual(report.runRecapShareArtifactRollup.retainedEntryCount, 1)
        XCTAssertEqual(report.runRecapShareArtifactRollup.matchingEntryCount, 1)
        XCTAssertEqual(report.runRecapShareArtifactRollup.unfilteredVisibleCount, 1)
        XCTAssertEqual(report.runRecapShareArtifactRollup.sessionRangeLabel, "S17")
        XCTAssertEqual(report.runRecapShareArtifactRollup.newestSessionNumber, 17)
        XCTAssertEqual(report.runRecapShareArtifactRollup.oldestSessionNumber, 17)
        XCTAssertEqual(report.runRecapShareArtifactRollup.statusBuckets.first { $0.identifier == "succeeded" }?.count, 1)
        XCTAssertEqual(report.runRecapShareArtifactRollup.warningStateIdentifier, "warnings")
        XCTAssertEqual(report.runRecapShareArtifactRollup.warningCount, 1)
        XCTAssertEqual(report.runRecapShareArtifactRollup.warningIdentifiers.count, 1)
        XCTAssertLessThanOrEqual(
            report.runRecapShareArtifactRollup.exportTextLength,
            CinematicRunRecapShareArtifactRollupPlan.exportTextMaxCharacters
        )
        XCTAssertEqual(report.runRecapShareArtifactPreview.identifier, previewPlan.identifier)
        XCTAssertEqual(report.runRecapShareArtifactPreview.selectedEntryIdentifier, historyPlan.latestEntry?.identifier)
        XCTAssertNil(report.runRecapShareArtifactPreview.previousEntryIdentifier)
        XCTAssertNil(report.runRecapShareArtifactPreview.nextEntryIdentifier)
        XCTAssertEqual(report.runRecapShareArtifactPreview.selectedIndex, 0)
        XCTAssertEqual(report.runRecapShareArtifactPreview.selectedOrdinal, 1)
        XCTAssertEqual(report.runRecapShareArtifactPreview.entryCount, 1)
        XCTAssertEqual(report.runRecapShareArtifactPreview.sessionNumber, 17)
        XCTAssertEqual(report.runRecapShareArtifactPreview.filename, "17-recap-share-diagnostics.md")
        XCTAssertEqual(report.runRecapShareArtifactPreview.titleSnippet, "Diagnostics Recap")
        XCTAssertEqual(report.runRecapShareArtifactPreview.statusSnippet, "succeeded")
        XCTAssertEqual(report.runRecapShareArtifactPreview.commitSnippet, "Diagnostics commit")
        XCTAssertEqual(report.runRecapShareArtifactPreview.warningStateIdentifier, "warnings")
        XCTAssertEqual(report.runRecapShareArtifactPreview.warningCount, 1)
        XCTAssertEqual(
            report.runRecapShareArtifactPreview.markdownLength,
            try XCTUnwrap(historyPlan.latestEntry?.markdownLength)
        )
        XCTAssertTrue(report.runRecapShareArtifactPreview.selectedExport.isAvailable)
        XCTAssertEqual(report.runRecapShareArtifactPreview.selectedExport.scopeIdentifier, "selected")
        XCTAssertEqual(report.runRecapShareArtifactPreview.selectedExport.exportEntryCount, 1)
        XCTAssertEqual(report.runRecapShareArtifactPreview.selectedExport.warningStateIdentifier, "warnings")
        XCTAssertEqual(report.runRecapShareArtifactPreview.selectedExport.warningCount, 1)
        XCTAssertTrue(report.runRecapShareArtifactPreview.filteredExport.isAvailable)
        XCTAssertEqual(report.runRecapShareArtifactPreview.filteredExport.scopeIdentifier, "filtered")
        XCTAssertEqual(report.runRecapShareArtifactPreview.filteredExport.exportEntryCount, 1)
        XCTAssertEqual(report.runRecapShareArtifactPreview.filteredExport.warningStateIdentifier, "warnings")
        XCTAssertEqual(report.runRecapShareArtifactPreview.filteredExport.warningCount, 1)
        XCTAssertTrue(report.identifier.contains("run-recap-share-artifact-preview:\(previewPlan.identifier)"))
        XCTAssertTrue(report.identifier.contains("run-recap-share-artifact-rollup:\(rollupPlan.identifier)"))
        XCTAssertTrue(report.identifier.contains("run-recap-share-artifact-selected-export:"))
        XCTAssertTrue(report.identifier.contains("run-recap-share-artifact-filtered-export:"))
        XCTAssertTrue(row.detail.contains("available"))
        XCTAssertTrue(row.detail.contains("total 1"))
        XCTAssertTrue(row.detail.contains("retention \(historyPlan.retentionLimit)"))
        XCTAssertTrue(row.detail.contains("cleanup candidates 0"))
        XCTAssertTrue(row.detail.contains("warning state warnings"))
        XCTAssertTrue(row.detail.contains("last cleanup none"))
        XCTAssertTrue(row.detail.contains("latest session 17"))
        XCTAssertTrue(row.detail.contains("17-recap-share-diagnostics.md"))
        XCTAssertTrue(row.detail.contains("warnings 1"))
        XCTAssertTrue(rollupRow.detail.contains("available"))
        XCTAssertTrue(rollupRow.detail.contains("matches 1/1"))
        XCTAssertTrue(rollupRow.detail.contains("range S17"))
        XCTAssertTrue(rollupRow.detail.contains("buckets succeeded 1"))
        XCTAssertTrue(rollupRow.detail.contains("warning state warnings"))
        XCTAssertTrue(rollupRow.detail.contains("copy \(rollupPlan.exportTextLength) chars"))
        XCTAssertTrue(previewRow.detail.contains("available"))
        XCTAssertTrue(previewRow.detail.contains("selection 1/1"))
        XCTAssertTrue(previewRow.detail.contains("session 17"))
        XCTAssertTrue(previewRow.detail.contains("17-recap-share-diagnostics.md"))
        XCTAssertTrue(previewRow.detail.contains("selected export available"))
        XCTAssertTrue(previewRow.detail.contains("filtered export available"))
        XCTAssertTrue(previewRow.detail.contains("warning state warnings"))
        XCTAssertTrue(previewRow.detail.contains("warnings 1"))
        XCTAssertTrue(summary.exportText.contains("Recap artifact library: available"))
        XCTAssertTrue(summary.exportText.contains("Recap artifact rollup: available"))
        XCTAssertTrue(summary.exportText.contains("Recap artifact preview: available"))
        XCTAssertTrue(summary.exportText.contains("matches 1/1"))
        XCTAssertTrue(summary.exportText.contains("buckets succeeded 1"))
        XCTAssertTrue(summary.exportText.contains("selection 1/1"))
        XCTAssertTrue(summary.exportText.contains("selected export available"))
        XCTAssertTrue(summary.exportText.contains("filtered export available"))
        XCTAssertTrue(summary.exportText.contains("retention \(historyPlan.retentionLimit)"))
        XCTAssertTrue(summary.exportText.contains("cleanup candidates 0"))
        XCTAssertTrue(summary.exportText.contains("warning state warnings"))
        XCTAssertTrue(summary.exportText.contains("last cleanup none"))
        XCTAssertTrue(summary.exportText.contains(String(historyPlan.exportIdentifier.prefix(32))))
        XCTAssertTrue(summary.exportText.contains(report.runRecapShareArtifactHistory.warningIdentifiers[0]))
    }

    func testRunRecapArtifactCleanupDiagnosticsExposeRetentionCandidatesAndLastResult() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "CinematicDiagnosticsArtifactCleanup-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let workspace = CompassWorkspace(repoURL: temporaryDirectory, storageRootURL: temporaryDirectory.appending(path: ".compass"))
        try FileManager.default.createDirectory(at: temporaryDirectory.appending(path: ".git"), withIntermediateDirectories: true)
        try workspace.initialize()
        let artifactCount = CinematicRunRecapShareArtifactHistoryPlan.retentionLimit + 1
        for session in 1...artifactCount {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-cleanup-\(session).md",
                contents: """
                # Compass Run Recap Share

                - Artifact: cleanup-artifact-\(session)
                - Availability: available
                - Session: \(session)
                - Filename: recap-share-cleanup-\(session).md
                - Share: share-id
                - Recap: recap-id
                - Focus: focus-id
                - End card: end-card-id
                - Title: Cleanup Recap \(session)
                - Status: succeeded
                - Detail: Cleanup detail
                - Commit: Cleanup commit \(session)
                """
            )
        }
        let before = workspace.refreshRunRecapShareArtifactHistory()
        let candidateReport = makeReport(
            CinematicDiagnosticsInput(
                repoName: "Compass",
                phase: "Succeeded",
                immediateTitle: "Expose recap artifact cleanup candidates",
                completedCount: 3,
                latestEvent: nil,
                languageProfile: languageProfile(primaryLanguage: .swift),
                activityProfile: activityProfile(recentCommitCount: 1, lastTerminalStatus: .succeeded),
                influenceSettings: CinematicInfluenceSettings(),
                runRecapShareArtifactHistoryPlan: before
            )
        )
        let candidateSummary = CinematicDiagnosticsSummary(
            report: candidateReport,
            visualSmoke: CinematicVisualSmokeReport(reports: [candidateReport])
        )

        let cleanup = workspace.cleanupRunRecapShareArtifacts()
        let report = makeReport(
            CinematicDiagnosticsInput(
                repoName: "Compass",
                phase: "Succeeded",
                immediateTitle: "Expose recap artifact cleanup result",
                completedCount: 3,
                latestEvent: nil,
                languageProfile: languageProfile(primaryLanguage: .swift),
                activityProfile: activityProfile(recentCommitCount: 1, lastTerminalStatus: .succeeded),
                influenceSettings: CinematicInfluenceSettings(),
                runRecapShareArtifactHistoryPlan: cleanup.refreshedHistory,
                runRecapShareArtifactCleanupResult: cleanup
            )
        )
        let summary = CinematicDiagnosticsSummary(
            report: report,
            visualSmoke: CinematicVisualSmokeReport(reports: [report])
        )
        let row = try XCTUnwrap(summary.rows.first { $0.id == "run-recap-share-artifact-history" })

        XCTAssertEqual(before.cleanupCandidateCount, 1)
        XCTAssertEqual(candidateReport.runRecapShareArtifactHistory.cleanupCandidateCount, 1)
        XCTAssertEqual(candidateReport.runRecapShareArtifactHistory.cleanupCandidateIdentifiers.count, 1)
        XCTAssertTrue(candidateSummary.exportText.contains("cleanup candidates 1"))
        XCTAssertTrue(candidateSummary.exportText.contains("cleanup ids"))
        XCTAssertEqual(cleanup.status, .deleted)
        XCTAssertEqual(report.runRecapShareArtifactHistory.retentionLimit, before.retentionLimit)
        XCTAssertEqual(report.runRecapShareArtifactHistory.cleanupCandidateCount, 0)
        XCTAssertEqual(report.runRecapShareArtifactHistory.warningStateIdentifier, "clear")
        XCTAssertEqual(report.runRecapShareArtifactHistory.lastCleanupResultIdentifier, cleanup.identifier)
        XCTAssertEqual(report.runRecapShareArtifactHistory.lastCleanupResultStatus, "deleted")
        XCTAssertTrue(report.identifier.contains("run-recap-share-artifact-cleanup:\(cleanup.identifier)"))
        XCTAssertTrue(row.detail.contains("cleanup candidates 0"))
        XCTAssertTrue(row.detail.contains("warning state clear"))
        XCTAssertTrue(row.detail.contains("last cleanup deleted"))
        XCTAssertTrue(summary.exportText.contains("last cleanup deleted"))
        XCTAssertTrue(summary.exportText.contains(String(cleanup.identifier.prefix(32))))
    }

    func testComfortModePropagatesToDiagnosticsIdentifiersAndExport() {
        let settings = CinematicInfluenceSettings(
            cameraStyle: .follow,
            comfortMode: .quiet,
            intensity: 0.4
        )
        let report = makeReport(
            CinematicDiagnosticsInput(
                repoName: "Compass",
                phase: "Developing",
                immediateTitle: "Expose quiet cinematic diagnostics",
                completedCount: 2,
                latestEvent: nil,
                languageProfile: languageProfile(primaryLanguage: .swift),
                activityProfile: activityProfile(worktreeChanges: worktreeChanges(modified: 4)),
                influenceSettings: settings
            )
        )
        let summary = CinematicDiagnosticsSummary(
            report: report,
            visualSmoke: CinematicVisualSmokeReport(reports: [report])
        )

        XCTAssertEqual(report.influenceIdentifier, "follow|0.4000|quiet")
        XCTAssertTrue(report.identifier.contains("influence:follow|0.4000|quiet"))
        XCTAssertTrue(report.overlayDisplay.identifier.contains("comfort:quiet"))
        XCTAssertTrue(report.overlayDisplay.identifier.contains("influence:follow|0.4000|quiet"))
        XCTAssertTrue(report.overlayDisplay.chromeStyleIdentifier.hasPrefix("compact-active-quiet|"))
        XCTAssertTrue(report.cameraTuning.identifier.hasPrefix("follow|0.4000|quiet"))
        XCTAssertTrue(report.activityTuning.identifier.hasPrefix("follow|0.4000|quiet"))
        XCTAssertTrue(report.cameraSnapshots.allSatisfy { $0.identifier.contains("|quiet|") })
        XCTAssertTrue(summary.exportText.contains("quiet"))
        XCTAssertTrue(summary.exportText.contains("compact-active-quiet"))
    }

    func testSummaryOutputIsStableAcrossRepeatedCalls() {
        let report = makeReport(
            CinematicDiagnosticsInput(
                repoName: "Compass",
                phase: "Recovering",
                immediateTitle: "Stabilize diagnostics export",
                completedCount: 4,
                latestEvent: nil,
                languageProfile: languageProfile(primaryLanguage: .rust),
                activityProfile: activityProfile(worktreeChanges: worktreeChanges(conflicted: 1)),
                influenceSettings: CinematicInfluenceSettings(cameraStyle: .follow, intensity: 0.5)
            )
        )

        let first = CinematicDiagnosticsSummary(report: report)
        let second = CinematicDiagnosticsSummary(report: report)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.exportText, second.exportText)
    }

    func testRepresentativeDiagnosticsExposeStageEffectTuningDifferences() throws {
        let dramaticReports = CinematicDiagnostics.representativeSmokeMatrix(
            influenceSettings: CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 1)
        )
        let clean = try XCTUnwrap(dramaticReports.first {
            $0.activityMotif.eventKindIdentifier == "clean" && $0.stageEffect.pressureLevelIdentifier == "clean"
        })
        let heavy = try XCTUnwrap(dramaticReports.first {
            $0.activityMotif.eventKindIdentifier == "dirty" && $0.stageEffect.pressureLevelIdentifier == "heavy"
        })

        XCTAssertGreaterThan(heavy.stageEffect.pressureFraction, clean.stageEffect.pressureFraction)
        XCTAssertGreaterThan(heavy.stageEffect.energy, clean.stageEffect.energy)
        XCTAssertGreaterThan(heavy.stageEffect.ringScaleMultiplier, clean.stageEffect.ringScaleMultiplier)
        XCTAssertLessThan(heavy.stageEffect.ringDurationScale, clean.stageEffect.ringDurationScale)
        XCTAssertGreaterThan(heavy.stageAtmosphere.pressureHaloOpacity, clean.stageAtmosphere.pressureHaloOpacity)
        XCTAssertGreaterThan(heavy.stageAtmosphere.phaseLightPressureBoost, clean.stageAtmosphere.phaseLightPressureBoost)
        XCTAssertGreaterThan(heavy.stageAtmosphere.rimLightPressureBoost, clean.stageAtmosphere.rimLightPressureBoost)
        XCTAssertGreaterThan(heavy.stageAtmosphere.floorTintOpacity, clean.stageAtmosphere.floorTintOpacity)
        XCTAssertLessThan(heavy.stageAtmosphere.atmosphericPulseCadence, clean.stageAtmosphere.atmosphericPulseCadence)
        XCTAssertGreaterThan(heavy.stagePhasePolish.poseIntensity, clean.stagePhasePolish.poseIntensity)
        XCTAssertGreaterThan(heavy.stagePhasePolish.staffOrbEmission, clean.stagePhasePolish.staffOrbEmission)

        let steady = CinematicDiagnostics.report(
            repoName: "Compass",
            phase: "Verifying",
            immediateTitle: "Bound stage effect tuning",
            completedCount: 2,
            latestEvent: nil,
            languageProfile: languageProfile(primaryLanguage: .swift),
            activityProfile: activityProfile(worktreeChanges: worktreeChanges(modified: 8)),
            influenceSettings: CinematicInfluenceSettings(cameraStyle: .steady, intensity: 0)
        )
        let follow = CinematicDiagnostics.report(
            repoName: "Compass",
            phase: "Verifying",
            immediateTitle: "Bound stage effect tuning",
            completedCount: 2,
            latestEvent: nil,
            languageProfile: languageProfile(primaryLanguage: .swift),
            activityProfile: activityProfile(worktreeChanges: worktreeChanges(modified: 8)),
            influenceSettings: CinematicInfluenceSettings(cameraStyle: .follow, intensity: CinematicInfluenceSettings.defaultIntensity)
        )
        let dramatic = CinematicDiagnostics.report(
            repoName: "Compass",
            phase: "Verifying",
            immediateTitle: "Bound stage effect tuning",
            completedCount: 2,
            latestEvent: nil,
            languageProfile: languageProfile(primaryLanguage: .swift),
            activityProfile: activityProfile(worktreeChanges: worktreeChanges(modified: 8)),
            influenceSettings: CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 1)
        )

        XCTAssertLessThan(steady.stageEffect.influenceFraction, follow.stageEffect.influenceFraction)
        XCTAssertLessThan(follow.stageEffect.influenceFraction, dramatic.stageEffect.influenceFraction)
        XCTAssertGreaterThan(dramatic.stageEffect.sparkBirthRateMultiplier, steady.stageEffect.sparkBirthRateMultiplier)
        XCTAssertInRange(dramatic.stageEffect.sparkBirthRateMultiplier, CinematicStageEffectPlan.sparkBirthRateMultiplierRange)
        XCTAssertGreaterThan(dramatic.stageAtmosphere.influenceFraction, steady.stageAtmosphere.influenceFraction)
        XCTAssertGreaterThan(dramatic.stageAtmosphere.rimLightPressureBoost, steady.stageAtmosphere.rimLightPressureBoost)
        XCTAssertInRange(dramatic.stageAtmosphere.rimLightPressureBoost, CinematicStageAtmospherePlan.rimLightPressureBoostRange)
        XCTAssertGreaterThan(dramatic.stagePhasePolish.sigilOrbitRadius, steady.stagePhasePolish.sigilOrbitRadius)
        XCTAssertGreaterThan(dramatic.stagePhasePolish.portalAperture, steady.stagePhasePolish.portalAperture)
        XCTAssertInRange(dramatic.stagePhasePolish.portalAperture, CinematicStagePhasePolishPlan.portalApertureRange)

        let summary = CinematicDiagnosticsSummary(report: heavy)
        XCTAssertTrue(summary.rows.contains { $0.id == "effect-tuning" })
        XCTAssertTrue(summary.rows.contains { $0.id == "stage-atmosphere" })
        XCTAssertTrue(summary.rows.contains { $0.id == "phase-polish" })
        XCTAssertTrue(summary.rows.contains { $0.id == "narrative-cues" })
        XCTAssertTrue(summary.rows.contains { $0.id == "narrative-layout" })
        XCTAssertTrue(summary.rows.contains { $0.id == "overlay-display" })
        XCTAssertTrue(summary.exportText.contains("Effect tuning:"))
        XCTAssertTrue(summary.exportText.contains("Atmosphere:"))
        XCTAssertTrue(summary.exportText.contains("Phase polish:"))
        XCTAssertTrue(summary.exportText.contains("Narrative cues:"))
        XCTAssertTrue(summary.exportText.contains("Narrative layout:"))
        XCTAssertTrue(summary.exportText.contains("Overlay display:"))
        XCTAssertTrue(summary.exportText.contains("pressure heavy"))
        XCTAssertTrue(summary.exportText.contains("influence dramatic"))
    }

    func testWarningBundleHistorySkipsPassingDiagnostics() throws {
        let report = try XCTUnwrap(CinematicDiagnostics.representativeSmokeMatrix().first)
        let summary = CinematicDiagnosticsSummary(report: report)
        var history = CinematicDiagnosticsWarningBundleHistory()

        history.record(summary.attentionSummary)

        XCTAssertTrue(summary.attentionSummary.isEmpty)
        XCTAssertFalse(history.isAvailable)
        XCTAssertEqual(history.entries, [])
        XCTAssertEqual(history.omittedCount, 0)
        XCTAssertNil(history.currentUnresolvedBundle)
        XCTAssertFalse(history.hasCurrentUnresolvedBundle)
        XCTAssertEqual(history.copyText, "")
        XCTAssertEqual(history.copyLabel, "No warning bundles")
        XCTAssertTrue(history.copyHelp.contains("No warning bundle history"))
        XCTAssertFalse(history.rollup.isAvailable)
        XCTAssertEqual(history.rollup.stateIdentifier, "empty")
        XCTAssertEqual(history.rollup.stateLabel, "No warning history")
        XCTAssertEqual(history.rollup.rows, [])
        XCTAssertEqual(history.rollup.countsLabel, "entries 0 | captures 0 | omitted 0")
    }

    func testWarningBundleHistoryCapturesFirstBundleWithRelatedAnchors() throws {
        let attention = warningAttentionSummary(
            "command",
            warnings: ["visual-smoke.recap-artifact-commands"],
            relatedRowID: "run-recap-share-artifact-commands"
        )
        var history = CinematicDiagnosticsWarningBundleHistory()

        history.record(attention)

        let entry = try XCTUnwrap(history.entries.first)
        XCTAssertTrue(history.isAvailable)
        XCTAssertEqual(history.entries.count, 1)
        XCTAssertEqual(history.capturedCount, 1)
        XCTAssertEqual(entry.sequence, 1)
        XCTAssertEqual(entry.captureCount, 1)
        XCTAssertEqual(entry.targetCount, 1)
        XCTAssertEqual(entry.warningCount, 1)
        XCTAssertEqual(entry.targetIdentifiers, ["target-command"])
        XCTAssertEqual(entry.warningIdentifiers, ["visual-smoke.recap-artifact-commands"])
        XCTAssertEqual(entry.targetAnchors, ["visual-smoke-check-command"])
        XCTAssertEqual(entry.relatedRowAnchors, ["diagnostics-row-run-recap-share-artifact-commands"])
        XCTAssertTrue(entry.bundleIdentifier.hasPrefix("warning-bundle-"))
        XCTAssertEqual(history.currentUnresolvedBundle, entry)
        XCTAssertTrue(history.hasCurrentUnresolvedBundle)
        XCTAssertTrue(history.copyText.contains("Cinematic diagnostics warning bundles"))
        XCTAssertTrue(history.copyText.contains("Export correlation: warning summary targets"))
        XCTAssertTrue(history.copyText.contains("related diagnostics row anchors"))
        XCTAssertTrue(history.copyText.contains("visual-smoke.recap-artifact-commands"))
        XCTAssertTrue(history.copyText.contains("diagnostics-row-run-recap-share-artifact-commands"))
        XCTAssertFalse(history.copyText.contains("Cinematic Diagnostics\nReport:"))
        XCTAssertEqual(history.copyText, history.rollup.copyText)

        let rollup = history.rollup
        XCTAssertTrue(rollup.isAvailable)
        XCTAssertEqual(rollup.stateIdentifier, "current-unresolved")
        XCTAssertEqual(rollup.stateLabel, "Current unresolved")
        XCTAssertEqual(rollup.currentBundleIdentifier, entry.bundleIdentifier)
        XCTAssertTrue(rollup.stateDetail.contains(entry.bundleIdentifier))
        XCTAssertEqual(rollup.entryCount, 1)
        XCTAssertEqual(rollup.capturedCount, 1)
        XCTAssertEqual(rollup.omittedCount, 0)
        XCTAssertEqual(rollup.recentBundleRows.map(\.label), ["#1 current"])
        XCTAssertEqual(rollup.groupedWarningIdentifierRows.map(\.countLabel), ["x1"])
        XCTAssertEqual(rollup.repeatedIdentifierRows, [])
        XCTAssertEqual(rollup.anchorSummaryRows.map(\.kind), [.targetAnchors, .relatedRowAnchors])
        XCTAssertTrue(rollup.targetAnchorSummary.contains("visual-smoke-check-command"))
        XCTAssertTrue(
            rollup.relatedRowAnchorSummary.contains(
                "diagnostics-row-run-recap-share-artifact-commands"
            )
        )
    }

    func testWarningBundleHistoryCoalescesConsecutiveDuplicateBundles() throws {
        let attention = warningAttentionSummary(
            "duplicate",
            warnings: ["visual-smoke.asset-availability"]
        )
        var history = CinematicDiagnosticsWarningBundleHistory()

        history.record(attention)
        history.record(attention)

        let entry = try XCTUnwrap(history.entries.first)
        XCTAssertEqual(history.entries.count, 1)
        XCTAssertEqual(history.capturedCount, 2)
        XCTAssertEqual(history.nextSequence, 2)
        XCTAssertEqual(entry.sequence, 1)
        XCTAssertEqual(entry.captureCount, 2)
        XCTAssertEqual(history.currentUnresolvedBundle?.captureCount, 2)
        XCTAssertTrue(entry.copyLine.contains("x2"))
        XCTAssertTrue(history.copyText.contains("captures 2"))
    }

    func testWarningBundleHistoryClearsCurrentWithoutDroppingHistory() throws {
        let attention = warningAttentionSummary(
            "cleared",
            warnings: ["visual-smoke.idle-story-cycle"]
        )
        var history = CinematicDiagnosticsWarningBundleHistory()

        history.record(attention)
        let firstEntry = try XCTUnwrap(history.currentUnresolvedBundle)
        history.record(CinematicDiagnosticsSummary.AttentionSummary(targets: []))

        XCTAssertEqual(history.entries.count, 1)
        XCTAssertEqual(history.entries.first, firstEntry)
        XCTAssertNil(history.currentUnresolvedBundle)
        XCTAssertFalse(history.hasCurrentUnresolvedBundle)
        XCTAssertTrue(history.isAvailable)
        XCTAssertEqual(history.rollup.stateIdentifier, "cleared-retained")
        XCTAssertEqual(history.rollup.stateLabel, "Cleared, retained")
        XCTAssertNil(history.rollup.currentBundleIdentifier)
        XCTAssertEqual(history.rollup.recentBundleRows.map(\.label), ["#1 retained"])
        XCTAssertTrue(history.rollup.copyText.contains("State: cleared-retained"))

        history.record(attention)

        XCTAssertEqual(history.entries.count, 2)
        XCTAssertEqual(history.entries.map(\.sequence), [1, 2])
        XCTAssertEqual(history.entries.map(\.captureCount), [1, 1])
        XCTAssertEqual(history.entries[0].bundleIdentifier, history.entries[1].bundleIdentifier)
        XCTAssertEqual(history.currentUnresolvedBundle?.sequence, 2)
        XCTAssertEqual(history.rollup.stateIdentifier, "current-unresolved")
        XCTAssertEqual(history.rollup.recentBundleRows.map(\.label), ["#2 current", "#1 retained"])
    }

    func testWarningBundleHistoryKeepsMultipleDistinctBundles() {
        let first = warningAttentionSummary("first", warnings: ["visual-smoke.asset-availability"])
        let second = warningAttentionSummary("second", warnings: ["visual-smoke.texture-role-coverage"])
        var history = CinematicDiagnosticsWarningBundleHistory()

        history.record(first)
        history.record(second)
        history.record(first)

        XCTAssertEqual(history.entries.count, 3)
        XCTAssertEqual(history.capturedCount, 3)
        XCTAssertEqual(history.entries.map(\.sequence), [1, 2, 3])
        XCTAssertEqual(history.entries.map(\.captureCount), [1, 1, 1])
        XCTAssertEqual(history.entries[0].bundleIdentifier, history.entries[2].bundleIdentifier)
        XCTAssertNotEqual(history.entries[0].id, history.entries[2].id)
        XCTAssertEqual(history.entries[1].warningIdentifiers, ["visual-smoke.texture-role-coverage"])
    }

    func testWarningBundleHistoryRetainsBoundedRecentEntriesAndOmittedCounts() {
        var history = CinematicDiagnosticsWarningBundleHistory()

        for index in 0..<(CinematicDiagnosticsWarningBundleHistory.maxEntries + 2) {
            history.record(
                warningAttentionSummary(
                    "bundle-\(index)",
                    warnings: ["visual-smoke.warning-\(index)"]
                )
            )
        }

        XCTAssertEqual(history.entries.count, CinematicDiagnosticsWarningBundleHistory.maxEntries)
        XCTAssertEqual(history.omittedCount, 2)
        XCTAssertEqual(
            history.capturedCount,
            CinematicDiagnosticsWarningBundleHistory.maxEntries + 2
        )
        XCTAssertEqual(history.entries.map(\.sequence), Array(3...8))
        XCTAssertEqual(history.entries.first?.warningIdentifiers, ["visual-smoke.warning-2"])
        XCTAssertTrue(history.copyText.contains("omitted 2"))
        XCTAssertEqual(history.rollup.omittedCount, 2)
        XCTAssertEqual(history.rollup.capturedCount, CinematicDiagnosticsWarningBundleHistory.maxEntries + 2)
        XCTAssertEqual(
            history.rollup.recentBundleRows.map(\.label),
            ["#8 current", "#7 retained", "#6 retained"]
        )
        XCTAssertLessThanOrEqual(
            history.rollup.recentBundleRows.count,
            CinematicDiagnosticsWarningBundleHistory.recentEntryRollupLimit
        )
    }

    func testWarningBundleHistorySurfacesRepeatedWarningIdentifiers() throws {
        let attention = CinematicDiagnosticsSummary.AttentionSummary(
            targets: [
                warningAttentionTarget(
                    "shared-a",
                    warnings: ["visual-smoke.shared-warning", "visual-smoke.asset-availability"]
                ),
                warningAttentionTarget(
                    "shared-b",
                    warnings: ["visual-smoke.shared-warning"],
                    relatedRowID: "textures"
                )
            ]
        )
        var history = CinematicDiagnosticsWarningBundleHistory()

        history.record(attention)

        let entry = try XCTUnwrap(history.entries.first)
        XCTAssertEqual(
            entry.warningIdentifiers,
            ["visual-smoke.shared-warning", "visual-smoke.asset-availability"]
        )
        XCTAssertEqual(entry.repeatedWarningIdentifiers, ["visual-smoke.shared-warning"])
        XCTAssertEqual(history.repeatedWarningIdentifiers, ["visual-smoke.shared-warning"])
        XCTAssertTrue(history.copyText.contains("Repeated warnings: visual-smoke.shared-warning"))
        XCTAssertTrue(entry.copyLine.contains("repeated visual-smoke.shared-warning"))
        XCTAssertEqual(
            history.rollup.groupedWarningIdentifierRows.map {
                $0.detail.components(separatedBy: " | ").first ?? ""
            },
            ["visual-smoke.shared-warning", "visual-smoke.asset-availability"]
        )
        XCTAssertEqual(history.rollup.repeatedWarningIdentifiers, ["visual-smoke.shared-warning"])
        XCTAssertEqual(history.rollup.repeatedIdentifierRows.map(\.countLabel), ["1"])
        XCTAssertTrue(
            history.rollup.repeatedIdentifierRows.first?.copyText.contains(
                "visual-smoke.shared-warning"
            ) ?? false
        )
    }

    func testWarningBundleHistoryRollupOrdersGroupedAndRepeatedWarningRows() {
        var history = CinematicDiagnosticsWarningBundleHistory()

        history.record(
            CinematicDiagnosticsSummary.AttentionSummary(
                targets: [
                    warningAttentionTarget(
                        "ordered-a",
                        warnings: ["visual-smoke.shared-warning", "visual-smoke.unique-a"]
                    ),
                    warningAttentionTarget(
                        "ordered-b",
                        warnings: ["visual-smoke.shared-warning"]
                    )
                ]
            )
        )
        history.record(
            warningAttentionSummary(
                "ordered-c",
                warnings: ["visual-smoke.unique-a", "visual-smoke.unique-b"]
            )
        )

        let rollup = history.rollup
        XCTAssertEqual(
            rollup.groupedWarningIdentifierRows.map {
                $0.detail.components(separatedBy: " | ").first ?? ""
            },
            [
                "visual-smoke.shared-warning",
                "visual-smoke.unique-a",
                "visual-smoke.unique-b"
            ]
        )
        XCTAssertEqual(
            rollup.repeatedWarningIdentifiers,
            ["visual-smoke.shared-warning", "visual-smoke.unique-a"]
        )
        XCTAssertTrue(
            rollup.repeatedIdentifierRows.first?.detail.hasPrefix(
                "visual-smoke.shared-warning x2, visual-smoke.unique-a x2"
            ) ?? false
        )
    }

    func testWarningBundleHistoryCopyIsBounded() {
        var history = CinematicDiagnosticsWarningBundleHistory()
        let longToken = String(repeating: "warning-segment-", count: 16)

        for index in 0..<(CinematicDiagnosticsWarningBundleHistory.maxEntries + 3) {
            let warnings = (0..<12).map { "visual-smoke.\(longToken)\(index)-\($0)" }
            history.record(
                warningAttentionSummary(
                    "\(longToken)\(index)",
                    warnings: warnings,
                    relatedRowID: "row-\(longToken)\(index)"
                )
            )
        }

        XCTAssertLessThanOrEqual(
            history.copyText.count,
            CinematicDiagnosticsWarningBundleHistory.copyTextMaxCharacters
        )
        for entry in history.entries {
            XCTAssertLessThanOrEqual(
                entry.copyLine.count,
                CinematicDiagnosticsWarningBundleHistory.entryCopyLineMaxCharacters
            )
            XCTAssertTrue(
                entry.warningIdentifiers.allSatisfy {
                    $0.count <= CinematicDiagnosticsWarningBundleHistory.identifierMaxCharacters
                }
            )
            XCTAssertTrue(
                entry.relatedRowAnchors.allSatisfy {
                    $0.count <= CinematicDiagnosticsWarningBundleHistory.identifierMaxCharacters
                }
            )
        }
        for row in history.rollup.rows {
            XCTAssertLessThanOrEqual(
                row.detail.count,
                CinematicDiagnosticsWarningBundleHistory.rollupRowDetailMaxCharacters
            )
            XCTAssertLessThanOrEqual(
                row.copyLine.count,
                CinematicDiagnosticsWarningBundleHistory.entryCopyLineMaxCharacters
            )
            XCTAssertLessThanOrEqual(
                row.copyText.count,
                CinematicDiagnosticsWarningBundleHistory.rollupRowCopyTextMaxCharacters
            )
        }
    }

    func testWarningBundleHistoryCopyDoesNotLeakNativeNotificationBodyText() throws {
        let notificationBody = "SECRET_NATIVE_NOTIFICATION_BODY_SHOULD_NOT_LEAK"
        let attention = CinematicDiagnosticsSummary.AttentionSummary(
            targets: [
                CinematicDiagnosticsSummary.AttentionTarget(
                    id: "native-feedback-warning",
                    targetGroupID: "visual-smoke",
                    targetAnchorID: "visual-smoke-check-native-feedback",
                    relatedGroupID: "narrative-overlay",
                    relatedRowID: "native-feedback-delivery",
                    label: "Native feedback warning",
                    detail: "notification body \(notificationBody)",
                    warningCount: 1,
                    visibleWarningIdentifiers: ["visual-smoke.native-feedback-cue-coverage"],
                    copyText: "Native notification body \(notificationBody)"
                )
            ]
        )
        var history = CinematicDiagnosticsWarningBundleHistory()

        history.record(attention)

        let entry = try XCTUnwrap(history.entries.first)
        XCTAssertFalse(entry.copyLine.contains(notificationBody))
        XCTAssertFalse(history.copyText.contains(notificationBody))
        XCTAssertFalse(history.rollup.copyText.contains(notificationBody))
        XCTAssertFalse(history.rollup.rows.contains { row in
            row.detail.contains(notificationBody)
                || row.copyLine.contains(notificationBody)
                || row.copyText.contains(notificationBody)
        })
        XCTAssertTrue(history.copyText.contains("visual-smoke.native-feedback-cue-coverage"))
        XCTAssertTrue(history.copyText.contains("diagnostics-row-native-feedback-delivery"))
    }

    @MainActor
    func testCompassProjectStoresWarningBundleHistoryInMemory() {
        let project = CompassProject(
            repoURL: URL(fileURLWithPath: "/tmp/DiagnosticsWarningBundleHistory", isDirectory: true)
        )

        project.recordCinematicDiagnosticsWarningBundle(
            warningAttentionSummary(
                "project",
                warnings: ["visual-smoke.asset-availability"]
            )
        )

        XCTAssertEqual(project.cinematicDiagnosticsWarningBundleHistory.entries.count, 1)
        XCTAssertNotNil(project.cinematicDiagnosticsWarningBundleHistory.currentUnresolvedBundle)
        project.recordCinematicDiagnosticsWarningBundle(
            CinematicDiagnosticsSummary.AttentionSummary(targets: [])
        )
        XCTAssertEqual(project.cinematicDiagnosticsWarningBundleHistory.entries.count, 1)
        XCTAssertNil(project.cinematicDiagnosticsWarningBundleHistory.currentUnresolvedBundle)
        let record = KnownProjectRecord(
            id: project.id,
            path: project.repoURL.path,
            addedAt: project.addedAt.timeIntervalSince1970,
            lastOpenedAt: project.lastOpenedAt.timeIntervalSince1970
        )
        let data = try? JSONEncoder().encode(record)
        let json = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        XCTAssertFalse(json.contains("cinematicDiagnosticsWarningBundleHistory"))
    }

    @MainActor
    func testCompassProjectSnoozesWarningPulseInMemoryWithoutClearingDiagnosticsState() throws {
        let project = CompassProject(
            repoURL: URL(fileURLWithPath: "/tmp/DiagnosticsWarningPulseSnooze", isDirectory: true)
        )
        let attention = warningAttentionSummary(
            "project-snooze",
            warnings: ["visual-smoke.asset-availability"],
            relatedRowID: "assets"
        )

        project.recordCinematicDiagnosticsWarningBundle(attention)
        let historyBefore = project.cinematicDiagnosticsWarningBundleHistory
        let copyBefore = historyBefore.copyText
        let sessionsBefore = project.sessions
        let currentBundle = try XCTUnwrap(historyBefore.currentUnresolvedBundle)

        project.snoozeCinematicDiagnosticsWarningPulse()

        let quieting = try XCTUnwrap(project.cinematicDiagnosticsWarningPulseQuietingDescriptor)
        XCTAssertTrue(quieting.matches(currentBundle))
        XCTAssertEqual(project.cinematicDiagnosticsWarningBundleHistory, historyBefore)
        XCTAssertEqual(project.cinematicDiagnosticsWarningBundleHistory.copyText, copyBefore)
        XCTAssertEqual(project.sessions, sessionsBefore)

        let status = CinematicDiagnosticsWarningPulseQuietingStatusDescriptor(
            currentBundle: currentBundle,
            quietingDescriptor: quieting
        )
        XCTAssertEqual(status.stateIdentifier, "snoozed")
        XCTAssertTrue(status.canResume)
        XCTAssertFalse(status.canSnooze)
        XCTAssertTrue(status.copyText.contains(currentBundle.bundleIdentifier))

        project.resumeCinematicDiagnosticsWarningPulse()
        XCTAssertNil(project.cinematicDiagnosticsWarningPulseQuietingDescriptor)
        XCTAssertEqual(project.cinematicDiagnosticsWarningBundleHistory, historyBefore)
        XCTAssertEqual(project.sessions, sessionsBefore)

        let record = KnownProjectRecord(
            id: project.id,
            path: project.repoURL.path,
            addedAt: project.addedAt.timeIntervalSince1970,
            lastOpenedAt: project.lastOpenedAt.timeIntervalSince1970
        )
        let data = try JSONEncoder().encode(record)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("cinematicDiagnosticsWarningPulseQuietingDescriptor"))
    }

    @MainActor
    func testCompassProjectClearsStaleWarningPulseSnoozeOnDuplicateCaptureAndNewBundle() throws {
        let project = CompassProject(
            repoURL: URL(fileURLWithPath: "/tmp/DiagnosticsWarningPulseDuplicate", isDirectory: true)
        )
        let first = warningAttentionSummary(
            "duplicate-snooze",
            warnings: ["visual-smoke.asset-availability"]
        )

        project.recordCinematicDiagnosticsWarningBundle(first)
        project.snoozeCinematicDiagnosticsWarningPulse()
        XCTAssertNotNil(project.cinematicDiagnosticsWarningPulseQuietingDescriptor)

        project.recordCinematicDiagnosticsWarningBundle(first)

        XCTAssertNil(project.cinematicDiagnosticsWarningPulseQuietingDescriptor)
        XCTAssertEqual(project.cinematicDiagnosticsWarningBundleHistory.entries.count, 1)
        XCTAssertEqual(project.cinematicDiagnosticsWarningBundleHistory.currentUnresolvedBundle?.captureCount, 2)

        project.snoozeCinematicDiagnosticsWarningPulse()
        XCTAssertNotNil(project.cinematicDiagnosticsWarningPulseQuietingDescriptor)

        project.recordCinematicDiagnosticsWarningBundle(
            warningAttentionSummary(
                "new-snooze",
                warnings: ["visual-smoke.texture-role-coverage"]
            )
        )

        XCTAssertNil(project.cinematicDiagnosticsWarningPulseQuietingDescriptor)
        XCTAssertEqual(project.cinematicDiagnosticsWarningBundleHistory.entries.count, 2)
        XCTAssertEqual(project.cinematicDiagnosticsWarningBundleHistory.currentUnresolvedBundle?.sequence, 2)
        XCTAssertEqual(
            project.cinematicDiagnosticsWarningBundleHistory.currentUnresolvedBundle?.warningIdentifiers,
            ["visual-smoke.texture-role-coverage"]
        )
    }

    func testWarningPulseQuietingDescriptorsAreBoundedAndBodyFree() throws {
        let secret = "SECRET_NATIVE_NOTIFICATION_BODY_SHOULD_NOT_LEAK"
        let longToken = String(repeating: "warning-pulse-token-", count: 20)
        let entry = CinematicDiagnosticsWarningBundleHistory.Entry(
            sequence: 12_345,
            bundleIdentifier: "warning-bundle-\(longToken)",
            captureCount: 99_999,
            targetCount: 42,
            warningCount: 77,
            targetIdentifiers: ["target-\(longToken)-\(secret)"],
            warningIdentifiers: ["visual-smoke.\(longToken)-\(secret)"],
            repeatedWarningIdentifiers: ["visual-smoke.repeated-\(longToken)-\(secret)"],
            targetAnchors: ["visual-smoke-check-\(longToken)-\(secret)"],
            relatedRowAnchors: ["diagnostics-row-\(longToken)-\(secret)"]
        )

        let quieting = CinematicDiagnosticsWarningPulseQuietingDescriptor(entry: entry)
        let activeStatus = CinematicDiagnosticsWarningPulseQuietingStatusDescriptor(
            currentBundle: entry,
            quietingDescriptor: nil
        )
        let snoozedStatus = CinematicDiagnosticsWarningPulseQuietingStatusDescriptor(
            currentBundle: entry,
            quietingDescriptor: quieting
        )

        XCTAssertLessThanOrEqual(
            quieting.identifier.count,
            CinematicDiagnosticsWarningPulseQuietingDescriptor.identifierMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            quieting.statusLabel.count,
            CinematicDiagnosticsWarningPulseQuietingDescriptor.labelMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            quieting.statusDetail.count,
            CinematicDiagnosticsWarningPulseQuietingDescriptor.detailMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            quieting.resumeHelp.count,
            CinematicDiagnosticsWarningPulseQuietingDescriptor.helpMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            quieting.copyText.count,
            CinematicDiagnosticsWarningPulseQuietingDescriptor.copyTextMaxCharacters
        )
        XCTAssertFalse(quieting.copyText.contains(secret))
        XCTAssertTrue(quieting.matches(entry))
        XCTAssertEqual(quieting.sequence, 12_345)
        XCTAssertEqual(quieting.captureCount, 99_999)

        for status in [activeStatus, snoozedStatus] {
            XCTAssertLessThanOrEqual(
                status.id.count,
                CinematicDiagnosticsWarningPulseQuietingStatusDescriptor.identifierMaxCharacters
            )
            XCTAssertLessThanOrEqual(
                status.label.count,
                CinematicDiagnosticsWarningPulseQuietingStatusDescriptor.labelMaxCharacters
            )
            XCTAssertLessThanOrEqual(
                status.detail.count,
                CinematicDiagnosticsWarningPulseQuietingStatusDescriptor.detailMaxCharacters
            )
            XCTAssertLessThanOrEqual(
                status.actionHelp.count,
                CinematicDiagnosticsWarningPulseQuietingStatusDescriptor.helpMaxCharacters
            )
            XCTAssertLessThanOrEqual(
                status.copyText.count,
                CinematicDiagnosticsWarningPulseQuietingStatusDescriptor.copyTextMaxCharacters
            )
            XCTAssertFalse(status.copyText.contains(secret))
        }
        XCTAssertEqual(activeStatus.stateIdentifier, "active")
        XCTAssertTrue(activeStatus.canSnooze)
        XCTAssertEqual(snoozedStatus.stateIdentifier, "snoozed")
        XCTAssertTrue(snoozedStatus.canResume)
    }

    func testDiagnosticsReportCorrelatesSavedWarningPulseAuditWithCurrentBundle() throws {
        var warningHistory = CinematicDiagnosticsWarningBundleHistory()
        warningHistory.record(
            warningAttentionSummary(
                "recap-warning-pulse-audit",
                warnings: [
                    "visual-smoke.warning-pulse-a",
                    "visual-smoke.warning-pulse-b"
                ],
                relatedRowID: "run-recap-share-artifact-tour"
            )
        )
        let currentBundle = try XCTUnwrap(warningHistory.currentUnresolvedBundle)
        let status = CinematicDiagnosticsWarningPulseQuietingStatusDescriptor(
            currentBundle: currentBundle,
            quietingDescriptor: nil
        )
        let audit = CinematicRunRecapShareArtifactWarningPulseAudit(
            entry: currentBundle,
            status: status
        )
        let session = diagnosticsSession(72, status: .succeeded, endedAt: 72_500)
        let runRecapPlan = diagnosticsRunRecapPlan(session: session)
        let commitPlan = CinematicCommitConstellationPlan(sessions: [session])
        let timelinePlan = CinematicSessionTimelinePlan(sessions: [session])
        let focusPlan = CinematicRunRecapSceneFocusPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: runRecapPlan,
            commitConstellationPlan: commitPlan,
            timelinePlan: timelinePlan
        )
        let endCardPlan = CinematicRunRecapEndCardPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: runRecapPlan
        )
        let sharePlan = CinematicRunRecapSharePlanner.plan(
            recapPlan: runRecapPlan,
            recapFocusDescriptor: focusPlan.descriptor,
            endCardDescriptor: endCardPlan.descriptor
        )
        let artifactPlan = CinematicRunRecapShareArtifactPlanner.plan(
            sharePlan: sharePlan,
            sessions: [session],
            warningPulseAudit: audit
        )
        let artifactEntry = CinematicRunRecapShareArtifactHistoryPlan.Entry(
            identifier: "diagnostics-warning-pulse-artifact-entry",
            sessionNumber: 72,
            filename: "72-\(artifactPlan.filename)",
            url: URL(fileURLWithPath: "/tmp/diagnostics-warning-pulse/72-\(artifactPlan.filename)"),
            pathDisplayText: "sessions/72-\(artifactPlan.filename)",
            titleSnippet: artifactPlan.title,
            statusSnippet: artifactPlan.status,
            commitSnippet: artifactPlan.commitHighlight,
            markdownContents: artifactPlan.markdownContents,
            markdownLength: artifactPlan.markdownLength
        )
        let historyPlan = CinematicRunRecapShareArtifactHistoryPlan(
            identifier: "diagnostics-warning-pulse-history",
            isAvailable: true,
            availabilityReason: "available",
            storageRootDisplayText: ".compass",
            sessionsDisplayText: ".compass/sessions",
            retentionLimit: CinematicRunRecapShareArtifactHistoryPlan.retentionLimit,
            entries: [artifactEntry],
            totalCount: 1,
            hiddenCount: 0,
            cleanupCandidateCount: 0,
            hiddenCleanupCandidateCount: 0,
            cleanupCandidateIdentifiers: [],
            warnings: [],
            warningCount: 0,
            hiddenWarningCount: 0,
            exportIdentifier: "diagnostics-warning-pulse-history-export",
            combinedMarkdownExport: artifactPlan.markdownContents
        )
        let report = CinematicDiagnostics.report(
            repoName: "Diagnostics Warning Pulse",
            phase: "Develop",
            immediateTitle: "Correlate warning pulse audit",
            completedCount: 1,
            latestEvent: nil,
            languageProfile: languageProfile(primaryLanguage: .swift),
            activityProfile: activityProfile(),
            influenceSettings: CinematicInfluenceSettings(),
            commitConstellationPlan: commitPlan,
            runRecapPlan: runRecapPlan,
            runRecapSceneFocusPlan: focusPlan,
            runRecapEndCardPlan: endCardPlan,
            runRecapShareArtifactPlan: artifactPlan,
            runRecapShareArtifactHistoryPlan: historyPlan,
            diagnosticsWarningBundleHistory: warningHistory
        )
        let summary = CinematicDiagnosticsSummary(report: report)
        let artifactRow = try XCTUnwrap(summary.rows.first { $0.id == "run-recap-share-artifact" })
        let historyRow = try XCTUnwrap(summary.rows.first { $0.id == "run-recap-share-artifact-history" })
        let rollupRow = try XCTUnwrap(summary.rows.first { $0.id == "run-recap-share-artifact-rollup" })

        XCTAssertEqual(report.runRecapShareArtifact.warningPulseAuditIdentifier, audit.identifier)
        XCTAssertEqual(report.runRecapShareArtifact.warningPulseAuditBundleIdentifier, currentBundle.bundleIdentifier)
        XCTAssertEqual(report.runRecapShareArtifact.warningPulseAuditCaptureCount, currentBundle.captureCount)
        XCTAssertEqual(report.runRecapShareArtifactHistory.warningPulseAuditCount, 1)
        XCTAssertEqual(report.runRecapShareArtifactHistory.latestWarningPulseAuditIdentifier, audit.identifier)
        XCTAssertEqual(report.runRecapShareArtifactRollup.warningPulseAuditCount, 1)
        XCTAssertEqual(report.runRecapShareArtifactRollup.warningPulseStateSummary, "active 1")
        XCTAssertEqual(report.runRecapShareArtifactRollup.warningPulseAuditIdentifiers, [audit.identifier])
        XCTAssertTrue(report.identifier.contains("run-recap-share-artifact-warning-pulse:\(audit.identifier)"))
        XCTAssertTrue(report.identifier.contains("run-recap-share-artifact-history-warning-pulses:1"))
        XCTAssertTrue(report.identifier.contains("run-recap-share-artifact-rollup-warning-pulses:1"))
        XCTAssertTrue(artifactRow.detail.contains("warning pulse active"))
        XCTAssertTrue(historyRow.detail.contains("warning pulse audits 1"))
        XCTAssertTrue(rollupRow.detail.contains("warning pulse audits 1 active 1"))
        XCTAssertTrue(summary.exportText.contains("Recap share artifact:"))
        XCTAssertTrue(summary.exportText.contains("warning pulse active"))
        XCTAssertEqual(warningHistory.currentUnresolvedBundle, currentBundle)
    }

    private func warningAttentionSummary(
        _ suffix: String,
        warnings: [String],
        relatedRowID: String? = nil
    ) -> CinematicDiagnosticsSummary.AttentionSummary {
        CinematicDiagnosticsSummary.AttentionSummary(
            targets: [
                warningAttentionTarget(
                    suffix,
                    warnings: warnings,
                    relatedRowID: relatedRowID
                )
            ]
        )
    }

    private func warningAttentionTarget(
        _ suffix: String,
        warnings: [String],
        relatedRowID: String? = nil
    ) -> CinematicDiagnosticsSummary.AttentionTarget {
        CinematicDiagnosticsSummary.AttentionTarget(
            id: "target-\(suffix)",
            targetGroupID: "visual-smoke",
            targetAnchorID: "visual-smoke-check-\(suffix)",
            relatedGroupID: relatedRowID == nil ? nil : "repository-context",
            relatedRowID: relatedRowID,
            label: "Warning \(suffix)",
            detail: "detail \(suffix)",
            warningCount: warnings.count,
            visibleWarningIdentifiers: warnings,
            copyText: "copy \(suffix)"
        )
    }

    private func diagnosticsSourceReconciliation(
        active activeHistory: CinematicRunRecapShareArtifactHistoryPlan,
        repoLocal repoLocalHistory: CinematicRunRecapShareArtifactHistoryPlan?,
        activitySource: RepositoryActivitySourceSnapshot? = nil
    ) -> CinematicRunRecapShareArtifactSourceReconciliationPlan {
        CinematicRunRecapShareArtifactSourceReconciliationPlanner.plan(
            activeHistoryPlan: activeHistory,
            repoLocalHistoryPlan: repoLocalHistory,
            activitySourceSnapshot: activitySource ?? diagnosticsSourceActivitySnapshot()
        )
    }

    private func diagnosticsSourceActivitySnapshot(
        availability: RepositoryActivitySourceSnapshot.SourceAvailability = .available,
        repoLocalState: RepositoryActivitySourceSnapshot.RepoLocalSessionsState = .ignoredCompatible
    ) -> RepositoryActivitySourceSnapshot {
        let repoURL = URL(fileURLWithPath: "/tmp/CompassRecapSourceAttention", isDirectory: true)
        let supportRoot = repoURL
            .appending(path: "Application Support", directoryHint: .isDirectory)
            .appending(path: "Compass", directoryHint: .isDirectory)
        return RepositoryActivitySourceSnapshot(
            activeStorage: .applicationSupport,
            storageRootURL: supportRoot,
            sessionsRecordURL: supportRoot.appending(path: "sessions.json"),
            sourceAvailability: availability,
            repoLocalSessionsRecordURL: repoURL
                .appending(path: ".compass", directoryHint: .isDirectory)
                .appending(path: "sessions.json"),
            repoLocalSessionsState: repoLocalState
        )
    }

    private func diagnosticsRuntimeRouteHistory(
        seed: String,
        runtimeRouteSection: String? = nil,
        mutationTestingSection: String? = nil,
        entries: [CinematicRunRecapShareArtifactHistoryPlan.Entry]? = nil
    ) -> CinematicRunRecapShareArtifactHistoryPlan {
        let resolvedEntries = entries ?? [
            diagnosticsRuntimeRouteEntry(
                seed: seed,
                session: 42,
                runtimeRouteSection: runtimeRouteSection,
                mutationTestingSection: mutationTestingSection
            )
        ]
        return CinematicRunRecapShareArtifactHistoryPlan(
            identifier: "runtime-route-history-\(seed)-entries:\(resolvedEntries.count)",
            isAvailable: !resolvedEntries.isEmpty,
            availabilityReason: resolvedEntries.isEmpty ? "runtime-route-empty" : "available",
            storageRootDisplayText: "/tmp/\(seed)/.compass",
            sessionsDisplayText: "/tmp/\(seed)/.compass/sessions",
            retentionLimit: CinematicRunRecapShareArtifactHistoryPlan.retentionLimit,
            entries: resolvedEntries,
            totalCount: resolvedEntries.count,
            hiddenCount: 0,
            cleanupCandidateCount: 0,
            hiddenCleanupCandidateCount: 0,
            cleanupCandidateIdentifiers: [],
            warnings: [],
            warningCount: 0,
            hiddenWarningCount: 0,
            exportIdentifier: "runtime-route-export-\(seed)",
            combinedMarkdownExport: "runtime route export \(seed)"
        )
    }

    private func diagnosticsRuntimeRouteEntry(
        seed: String,
        session: Int,
        runtimeRouteSection: String?,
        mutationTestingSection: String? = nil
    ) -> CinematicRunRecapShareArtifactHistoryPlan.Entry {
        let filename = "\(session)-runtime-route-\(seed).md"
        let markdown = [
            """
            # Compass Run Recap Share

            - Artifact: runtime-route-\(seed)-\(session)
            - Availability: available
            - Session: \(session)
            - Filename: \(filename)
            - Share: share-id
            - Recap: recap-id
            - Focus: focus-id
            - End card: end-card-id
            - Title: Runtime route \(seed)
            - Status: succeeded
            - Detail: Runtime route detail
            - Commit: Runtime route commit
            """,
            runtimeRouteSection ?? "",
            mutationTestingSection ?? "",
            """
            ## Events
            - event

            ## Share Text

            ```text
            runtime route body
            ```
            """
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
        return CinematicRunRecapShareArtifactHistoryPlan.Entry(
            identifier: "runtime-route-entry-\(seed)-session:\(session)",
            sessionNumber: session,
            filename: filename,
            url: URL(fileURLWithPath: "/tmp/\(seed)/.compass/sessions/\(filename)"),
            pathDisplayText: "/tmp/\(seed)/.compass/sessions/\(filename)",
            titleSnippet: "Runtime route \(seed)",
            statusSnippet: "succeeded",
            commitSnippet: "Runtime route commit",
            markdownContents: markdown,
            markdownLength: markdown.count
        )
    }

    private func diagnosticsRuntimeRouteSection(
        effectiveRoute: String,
        effectiveRouteTitle: String,
        fallbackState: String,
        supportClassification: String,
        phase: String = "Develop (develop)",
        attempt: String = "1",
        selectedPreference: CodexExecutionEnvironmentPreference = .devcontainerPreferred,
        fallbackReason: String = "none",
        extraLines: [String] = []
    ) -> String {
        let baseLines = [
            "## Runtime Route",
            "",
            "- Runtime audit: runtime-route-audit",
            "- Phase: \(phase)",
            "- Attempt: \(attempt)",
            "- Selected preference: \(selectedPreference.rawValue) (\(selectedPreference.title))",
            "- Effective route: \(effectiveRoute) (\(effectiveRouteTitle))",
            "- Support classification: \(supportClassification)",
            "- Visible support tokens: none",
            "- Omitted support tokens: 0",
            "- Image label: none",
            "- Workspace label: none",
            "- Fallback state: \(fallbackState)",
            "- Fallback reason: \(fallbackReason)",
            "- Provisioning availability: none",
            "- Provisioning status: none",
            "- Provisioning action: none"
        ]
        return (baseLines + extraLines).joined(separator: "\n")
    }

    private func diagnosticsSourceHistory(
        seed: String,
        sessions: [Int],
        availabilityReason: String = "available",
        warnings: [String] = []
    ) -> CinematicRunRecapShareArtifactHistoryPlan {
        let entries = sessions.map { session in
            CinematicRunRecapShareArtifactHistoryPlan.Entry(
                identifier: "artifact-\(seed)-session:\(session)",
                sessionNumber: session,
                filename: "\(session)-recap-share-\(seed).md",
                url: URL(fileURLWithPath: "/tmp/\(seed)/.compass/sessions/\(session)-recap-share-\(seed).md"),
                pathDisplayText: "/tmp/\(seed)/.compass/sessions/\(session)-recap-share-\(seed).md",
                titleSnippet: "Recap \(session)",
                statusSnippet: "succeeded",
                commitSnippet: "Commit \(session)",
                markdownContents: "# Compass Run Recap Share\n\n- Session: \(session)\n",
                markdownLength: 45
            )
        }
        let warningPlans = warnings.enumerated().map { index, identifier in
            CinematicRunRecapShareArtifactHistoryPlan.Warning(
                identifier: identifier,
                fileDisplayText: "/tmp/\(seed)/warning-\(index).md",
                message: "Warning \(index)"
            )
        }

        return CinematicRunRecapShareArtifactHistoryPlan(
            identifier: "history-\(seed)-sessions:\(sessions.map(String.init).joined(separator: ","))-warnings:\(warnings.count)",
            isAvailable: !entries.isEmpty && availabilityReason == "available",
            availabilityReason: entries.isEmpty ? availabilityReason : availabilityReason,
            storageRootDisplayText: "/tmp/\(seed)/.compass",
            sessionsDisplayText: "/tmp/\(seed)/.compass/sessions",
            retentionLimit: CinematicRunRecapShareArtifactHistoryPlan.retentionLimit,
            entries: entries,
            totalCount: entries.count,
            hiddenCount: 0,
            cleanupCandidateCount: 0,
            hiddenCleanupCandidateCount: 0,
            cleanupCandidateIdentifiers: [],
            warnings: warningPlans,
            warningCount: warningPlans.count,
            hiddenWarningCount: 0,
            exportIdentifier: "export-\(seed)",
            combinedMarkdownExport: "export \(seed)"
        )
    }
}

private struct CinematicDiagnosticsInput {
    var repoName: String
    var phase: String
    var immediateTitle: String
    var completedCount: Int
    var latestEvent: CinematicBriefingEvent?
    var languageProfile: RepositoryLanguageProfile
    var activityProfile: RepositoryActivityProfile
    var activitySourceSnapshot: RepositoryActivitySourceSnapshot = .notScanned()
    var sceneCacheLifecycleSnapshot: CinematicSceneCacheLifecycleSnapshot? = nil
    var influenceSettings: CinematicInfluenceSettings
    var commitConstellationPlan: CinematicCommitConstellationPlan = .empty
    var runRecapPlan: CinematicRunRecapPlan = .empty(reason: "no-finished-session")
    var runRecapSceneFocusPlan: CinematicRunRecapSceneFocusPlan = .none
    var runRecapEndCardPlan: CinematicRunRecapEndCardPlan = .none
    var runRecapShareArtifactHistoryPlan: CinematicRunRecapShareArtifactHistoryPlan?
    var runRecapShareArtifactSourceReconciliationPlan:
        CinematicRunRecapShareArtifactSourceReconciliationPlan?
    var runRecapShareArtifactCleanupResult: CinematicRunRecapShareArtifactCleanupResult?
    var runRecapShareArtifactPreviewSelectedEntryIdentifier: String?
    var runRecapShareArtifactPreviewSearchQuery: String?
    var runRecapShareArtifactComparisonTargetMode: CinematicRunRecapShareArtifactComparisonTargetMode = .adjacent
    var runRecapShareArtifactPinnedEntryIdentifiers: [String] = []
    var runRecapShareArtifactSavedTourHoldEntryIdentifier: String?
    var nativeFeedbackDeliverySnapshot: NativeFeedbackDeliverySnapshot = NativeFeedbackDeliverySnapshot(
        mode: .notifications
    )
}

private func makeReport(_ input: CinematicDiagnosticsInput) -> CinematicDiagnosticsReport {
    CinematicDiagnostics.report(
        repoName: input.repoName,
        phase: input.phase,
        immediateTitle: input.immediateTitle,
        completedCount: input.completedCount,
        latestEvent: input.latestEvent,
        languageProfile: input.languageProfile,
        activityProfile: input.activityProfile,
        activitySourceSnapshot: input.activitySourceSnapshot,
        sceneCacheLifecycleSnapshot: input.sceneCacheLifecycleSnapshot,
        influenceSettings: input.influenceSettings,
        commitConstellationPlan: input.commitConstellationPlan,
        runRecapPlan: input.runRecapPlan,
        runRecapSceneFocusPlan: input.runRecapSceneFocusPlan,
        runRecapEndCardPlan: input.runRecapEndCardPlan,
        runRecapShareArtifactHistoryPlan: input.runRecapShareArtifactHistoryPlan,
        runRecapShareArtifactSourceReconciliationPlan: input.runRecapShareArtifactSourceReconciliationPlan,
        runRecapShareArtifactCleanupResult: input.runRecapShareArtifactCleanupResult,
        runRecapShareArtifactPreviewSelectedEntryIdentifier: input.runRecapShareArtifactPreviewSelectedEntryIdentifier,
        runRecapShareArtifactPreviewSearchQuery: input.runRecapShareArtifactPreviewSearchQuery,
        runRecapShareArtifactComparisonTargetMode: input.runRecapShareArtifactComparisonTargetMode,
        runRecapShareArtifactPinnedEntryIdentifiers: input.runRecapShareArtifactPinnedEntryIdentifiers,
        runRecapShareArtifactSavedTourHoldEntryIdentifier: input.runRecapShareArtifactSavedTourHoldEntryIdentifier,
        nativeFeedbackDeliverySnapshot: input.nativeFeedbackDeliverySnapshot
    )
}

private func assertNativeFeedbackHistoryExport(
    _ export: CinematicDiagnosticsSummary.NativeFeedbackHistoryExport,
    row: CinematicDiagnosticsSummary.Row,
    activeCount: Int,
    archivedCount: Int,
    omittedCount: Int,
    requiredTokens: [String],
    forbiddenTokens: [String] = [],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(export.id, "native-feedback-history-export", file: file, line: line)
    XCTAssertEqual(export.rowID, row.id, file: file, line: line)
    XCTAssertEqual(export.activeCount, activeCount, file: file, line: line)
    XCTAssertEqual(export.archivedCount, archivedCount, file: file, line: line)
    XCTAssertEqual(export.omittedCount, omittedCount, file: file, line: line)
    XCTAssertEqual(export.entries.filter { $0.stateIdentifier == "active" }.count, activeCount, file: file, line: line)
    XCTAssertEqual(export.entries.filter { $0.stateIdentifier == "archived" }.count, archivedCount, file: file, line: line)

    guard !requiredTokens.isEmpty else {
        XCTAssertFalse(export.isAvailable, file: file, line: line)
        XCTAssertEqual(export.entries, [], file: file, line: line)
        XCTAssertEqual(export.copyText, "", file: file, line: line)
        XCTAssertEqual(export.copyLabel, "No native history", file: file, line: line)
        XCTAssertTrue(export.copyHelp.contains("No native feedback cue history"), file: file, line: line)
        return
    }

    XCTAssertTrue(export.isAvailable, file: file, line: line)
    XCTAssertEqual(export.copyLabel, "Copy native history", file: file, line: line)
    XCTAssertTrue(export.copyHelp.contains("active \(activeCount)"), file: file, line: line)
    XCTAssertTrue(export.copyHelp.contains("archived \(archivedCount)"), file: file, line: line)
    XCTAssertTrue(export.copyHelp.contains("omitted \(omittedCount)"), file: file, line: line)
    XCTAssertLessThanOrEqual(
        export.copyText.count,
        CinematicDiagnosticsSummary.nativeFeedbackHistoryExportCopyMaxCharacters,
        file: file,
        line: line
    )
    XCTAssertTrue(export.copyText.hasPrefix("Native feedback history\n"), file: file, line: line)
    XCTAssertTrue(export.copyText.contains("Row: \(row.id)"), file: file, line: line)
    XCTAssertTrue(
        export.copyText.contains("Counts: active \(activeCount) | archived \(archivedCount) | omitted \(omittedCount)"),
        file: file,
        line: line
    )
    XCTAssertFalse(export.copyText.contains("Cinematic Diagnostics\nReport:"), file: file, line: line)

    for entry in export.entries {
        XCTAssertLessThanOrEqual(
            entry.copyLine.count,
            CinematicDiagnosticsSummary.nativeFeedbackHistoryExportEntryMaxCharacters,
            file: file,
            line: line
        )
        XCTAssertTrue(export.copyText.contains(entry.copyLine), file: file, line: line)
        XCTAssertTrue(entry.copyLine.contains("#\(entry.sequence)"), file: file, line: line)
        XCTAssertTrue(entry.copyLine.contains(entry.stateIdentifier), file: file, line: line)
        if let reason = entry.reasonIdentifier {
            XCTAssertTrue(entry.copyLine.contains(reason), file: file, line: line)
        }
        XCTAssertTrue(entry.copyLine.contains("milestone \(entry.milestoneIdentifier)"), file: file, line: line)
        XCTAssertTrue(entry.copyLine.contains("source \(entry.sourceIdentifier ?? "none")"), file: file, line: line)
        XCTAssertTrue(entry.copyLine.contains("style \(entry.styleIdentifier ?? "none")"), file: file, line: line)
        XCTAssertTrue(entry.copyLine.contains("duration"), file: file, line: line)
        XCTAssertTrue(entry.copyLine.contains("lifecycle \(entry.lifecycleIdentifier)"), file: file, line: line)
    }

    for segment in row.detail.components(separatedBy: " | ") where segment != "none" && !segment.contains("...") {
        XCTAssertTrue(export.copyText.contains(segment), "missing row segment \(segment)", file: file, line: line)
    }

    for token in requiredTokens {
        XCTAssertTrue(export.copyText.contains(token), "missing token \(token)", file: file, line: line)
    }

    for token in forbiddenTokens {
        XCTAssertFalse(export.copyText.contains(token), "forbidden token \(token)", file: file, line: line)
    }
}

private func diagnosticsSession(
    _ number: Int,
    status: SessionStatus,
    commits: [SessionCommit] = [],
    endedAt: Double?
) -> SessionRecord {
    SessionRecord(
        session: number,
        startedAt: Double(number * 1_000),
        endedAt: endedAt,
        plan: "Expose diagnostics",
        verify: "swift test",
        beforeSha: nil,
        afterSha: nil,
        commits: commits,
        status: status,
        notes: [],
        verifyOutput: nil,
        feedback: nil
    )
}

private func diagnosticsRunCue(
    kind: PlanReliabilityFeedback.Kind,
    severity: PlanReliabilityFeedback.Severity,
    label: String,
    detail: String,
    systemImage: String
) -> PlanReliabilityFeedback.RunCue {
    PlanReliabilityFeedback.RunCue(
        notice: PlanReliabilityFeedback.Notice(
            id: "\(kind.rawValue)-diagnostics-test",
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

private func diagnosticsRunRecapPlan(session: SessionRecord) -> CinematicRunRecapPlan {
    CinematicRunRecapPlanner.plan(
        state: PlanState(
            completed: ["Complete diagnostics warning pulse audit"],
            immediate: nil,
            midTerm: "",
            longTerm: ""
        ),
        sessions: [session],
        isRunning: false,
        isAutoPlaying: false,
        recentRunCues: [:],
        commitConstellationPlan: CinematicCommitConstellationPlan(sessions: [session]),
        nativeFeedbackLifecycle: CinematicNativeFeedbackCueLifecycle()
    )
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
    worktreeChanges: RepositoryWorktreeChangeCounts = RepositoryWorktreeChangeCounts(),
    recentSessionCount: Int = 1,
    recentSucceededCount: Int = 0,
    recentFailedCount: Int = 0,
    recentCommitCount: Int = 0,
    lastTerminalStatus: SessionStatus? = nil,
    successStreak: Int = 0,
    failureStreak: Int = 0,
    recoveredFromFailure: Bool = false
) -> RepositoryActivityProfile {
    RepositoryActivityProfile(
        isAvailable: true,
        worktreeChanges: worktreeChanges,
        recentSessionCount: recentSessionCount,
        recentSucceededCount: recentSucceededCount,
        recentFailedCount: recentFailedCount,
        recentCommitCount: recentCommitCount,
        lastTerminalStatus: lastTerminalStatus,
        lastSuccessfulSession: successStreak > 0 ? 1 : nil,
        lastFailedSession: failureStreak > 0 || recoveredFromFailure ? 0 : nil,
        successStreak: successStreak,
        failureStreak: failureStreak,
        recoveredFromFailure: recoveredFromFailure
    )
}

private func worktreeChanges(
    added: Int = 0,
    modified: Int = 0,
    deleted: Int = 0,
    renamed: Int = 0,
    untracked: Int = 0,
    conflicted: Int = 0,
    other: Int = 0
) -> RepositoryWorktreeChangeCounts {
    var changes = RepositoryWorktreeChangeCounts()
    changes.added = added
    changes.modified = modified
    changes.deleted = deleted
    changes.renamed = renamed
    changes.untracked = untracked
    changes.conflicted = conflicted
    changes.other = other
    return changes
}

private func assertWorldTextBounds(
    _ text: CinematicDiagnosticsReport.WorldTextSnapshot,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertLessThanOrEqual(
        text.questLabel.count,
        CinematicWorldTextService.questLabelMaxCharacters,
        file: file,
        line: line
    )
    XCTAssertLessThanOrEqual(
        text.arenaCallout.count,
        CinematicWorldTextService.arenaCalloutMaxCharacters,
        file: file,
        line: line
    )
    XCTAssertLessThanOrEqual(
        text.activityCallout.count,
        CinematicWorldTextService.activityCalloutMaxCharacters,
        file: file,
        line: line
    )
    XCTAssertLessThanOrEqual(
        wordCount(text.questLabel),
        CinematicWorldTextService.questLabelMaxWords,
        file: file,
        line: line
    )
    XCTAssertLessThanOrEqual(
        wordCount(text.arenaCallout),
        CinematicWorldTextService.arenaCalloutMaxWords,
        file: file,
        line: line
    )
    XCTAssertLessThanOrEqual(
        wordCount(text.activityCallout),
        CinematicWorldTextService.activityCalloutMaxWords,
        file: file,
        line: line
    )
}

private func wordCount(_ text: String) -> Int {
    text.split(whereSeparator: \.isWhitespace).count
}

private func assertStageEffectTuningBounds(
    _ snapshot: CinematicDiagnosticsReport.StageEffectSnapshot,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertInRange(snapshot.pressureFraction, CinematicStageEffectPlan.stageEffectPressureRange, file: file, line: line)
    XCTAssertInRange(snapshot.energy, CinematicStageEffectPlan.stageEffectEnergyRange, file: file, line: line)
    XCTAssertInRange(snapshot.influenceIntensity, CinematicStageEffectPlan.stageEffectInfluenceRange, file: file, line: line)
    XCTAssertInRange(snapshot.influenceFraction, CinematicStageEffectPlan.stageEffectInfluenceRange, file: file, line: line)
    XCTAssertInRange(snapshot.activityLightBoost, CinematicStageEffectPlan.stageEffectActivityLightBoostRange, file: file, line: line)
    XCTAssertInRange(snapshot.activityLightBoostFraction, CinematicStageEffectPlan.stageEffectEnergyRange, file: file, line: line)
    XCTAssertInRange(snapshot.runePulseScale, CinematicStageEffectPlan.stageEffectRunePulseScaleRange, file: file, line: line)
    XCTAssertInRange(snapshot.activityPulseDuration, CinematicStageEffectPlan.stageEffectActivityPulseDurationRange, file: file, line: line)
    XCTAssertInRange(snapshot.ringDurationScale, CinematicStageEffectPlan.ringDurationScaleRange, file: file, line: line)
    XCTAssertInRange(snapshot.ringScaleMultiplier, CinematicStageEffectPlan.ringScaleMultiplierRange, file: file, line: line)
    XCTAssertInRange(snapshot.ringOpacityMultiplier, CinematicStageEffectPlan.ringOpacityMultiplierRange, file: file, line: line)
    XCTAssertInRange(snapshot.colorAlphaMultiplier, CinematicStageEffectPlan.colorAlphaMultiplierRange, file: file, line: line)
    XCTAssertInRange(snapshot.pulseIntensityMultiplier, CinematicStageEffectPlan.pulseIntensityMultiplierRange, file: file, line: line)
    XCTAssertInRange(snapshot.pulseDurationMultiplier, CinematicStageEffectPlan.pulseDurationMultiplierRange, file: file, line: line)
    XCTAssertInRange(snapshot.sparkBirthRateMultiplier, CinematicStageEffectPlan.sparkBirthRateMultiplierRange, file: file, line: line)
    XCTAssertInRange(snapshot.historyTrailTargetCount, CinematicStageEffectPlan.historyTrailTuningCountRange, file: file, line: line)
    XCTAssertInRange(snapshot.cameraShakeMultiplier, CinematicStageEffectPlan.cameraShakeMultiplierRange, file: file, line: line)
    XCTAssertInRange(snapshot.cameraShakeDurationMultiplier, CinematicStageEffectPlan.cameraShakeDurationMultiplierRange, file: file, line: line)
    XCTAssertInRange(snapshot.victoryCadenceMultiplier, CinematicStageEffectPlan.victoryCadenceMultiplierRange, file: file, line: line)
    XCTAssertFalse(snapshot.tuningIdentifier.isEmpty, file: file, line: line)
}

private func assertStageAtmosphereBounds(
    _ snapshot: CinematicDiagnosticsReport.StageAtmosphereSnapshot,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertInRange(snapshot.pressureFraction, CinematicStageAtmospherePlan.atmospherePressureRange, file: file, line: line)
    XCTAssertInRange(snapshot.influenceIntensity, CinematicStageAtmospherePlan.atmosphereInfluenceRange, file: file, line: line)
    XCTAssertInRange(snapshot.influenceFraction, CinematicStageAtmospherePlan.atmosphereInfluenceRange, file: file, line: line)
    XCTAssertInRange(snapshot.energy, CinematicStageAtmospherePlan.atmosphereEnergyRange, file: file, line: line)
    XCTAssertInRange(snapshot.pressureHaloRadius, CinematicStageAtmospherePlan.pressureHaloRadiusRange, file: file, line: line)
    XCTAssertInRange(snapshot.pressureHaloOpacity, CinematicStageAtmospherePlan.pressureHaloOpacityRange, file: file, line: line)
    XCTAssertInRange(snapshot.pressureHaloScale, CinematicStageAtmospherePlan.pressureHaloScaleRange, file: file, line: line)
    XCTAssertInRange(snapshot.pressureHaloColorAlpha, CinematicStageAtmospherePlan.colorAlphaRange, file: file, line: line)
    XCTAssertInRange(snapshot.atmosphericPulseCadence, CinematicStageAtmospherePlan.atmosphericPulseCadenceRange, file: file, line: line)
    XCTAssertInRange(snapshot.atmosphericPulseAmplitude, CinematicStageAtmospherePlan.atmosphericPulseAmplitudeRange, file: file, line: line)
    XCTAssertInRange(snapshot.atmosphericPulseOpacity, CinematicStageAtmospherePlan.atmosphericPulseOpacityRange, file: file, line: line)
    XCTAssertInRange(snapshot.phaseLightPressureBoost, CinematicStageAtmospherePlan.phaseLightPressureBoostRange, file: file, line: line)
    XCTAssertInRange(snapshot.rimLightPressureBoost, CinematicStageAtmospherePlan.rimLightPressureBoostRange, file: file, line: line)
    XCTAssertInRange(snapshot.pressureLightColorAlpha, CinematicStageAtmospherePlan.colorAlphaRange, file: file, line: line)
    XCTAssertTintInRange(
        red: snapshot.backdropTintRed,
        green: snapshot.backdropTintGreen,
        blue: snapshot.backdropTintBlue,
        opacity: snapshot.backdropTintOpacity,
        blendFraction: snapshot.backdropTintBlendFraction,
        opacityRange: CinematicStageAtmospherePlan.backdropTintOpacityRange,
        file: file,
        line: line
    )
    XCTAssertTintInRange(
        red: snapshot.floorTintRed,
        green: snapshot.floorTintGreen,
        blue: snapshot.floorTintBlue,
        opacity: snapshot.floorTintOpacity,
        blendFraction: snapshot.floorTintBlendFraction,
        opacityRange: CinematicStageAtmospherePlan.floorTintOpacityRange,
        file: file,
        line: line
    )
    XCTAssertFalse(snapshot.identifier.isEmpty, file: file, line: line)
    XCTAssertFalse(snapshot.pressureHaloIdentifier.isEmpty, file: file, line: line)
    XCTAssertFalse(snapshot.atmosphericPulseIdentifier.isEmpty, file: file, line: line)
    XCTAssertFalse(snapshot.pressureLightingIdentifier.isEmpty, file: file, line: line)
    XCTAssertFalse(snapshot.backdropTintIdentifier.isEmpty, file: file, line: line)
    XCTAssertFalse(snapshot.floorTintIdentifier.isEmpty, file: file, line: line)
}

private func assertStagePhasePolishBounds(
    _ snapshot: CinematicDiagnosticsReport.StagePhasePolishSnapshot,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertInRange(snapshot.poseIntensity, CinematicStagePhasePolishPlan.poseIntensityRange, file: file, line: line)
    XCTAssertInRange(snapshot.staffOrbScale, CinematicStagePhasePolishPlan.staffOrbScaleRange, file: file, line: line)
    XCTAssertInRange(snapshot.staffOrbEmission, CinematicStagePhasePolishPlan.staffOrbEmissionRange, file: file, line: line)
    XCTAssertInRange(snapshot.staffOrbPulseAmplitude, CinematicStagePhasePolishPlan.staffOrbPulseAmplitudeRange, file: file, line: line)
    XCTAssertInRange(snapshot.sigilOrbitRadius, CinematicStagePhasePolishPlan.sigilOrbitRadiusRange, file: file, line: line)
    XCTAssertInRange(snapshot.sigilSealEmphasis, CinematicStagePhasePolishPlan.sigilSealEmphasisRange, file: file, line: line)
    XCTAssertInRange(snapshot.sigilVictoryEmphasis, CinematicStagePhasePolishPlan.sigilVictoryEmphasisRange, file: file, line: line)
    XCTAssertInRange(snapshot.sigilPulseAmplitude, CinematicStagePhasePolishPlan.sigilPulseAmplitudeRange, file: file, line: line)
    XCTAssertInRange(snapshot.portalAperture, CinematicStagePhasePolishPlan.portalApertureRange, file: file, line: line)
    XCTAssertInRange(snapshot.portalScale, CinematicStagePhasePolishPlan.portalScaleRange, file: file, line: line)
    XCTAssertInRange(snapshot.portalOpacity, CinematicStagePhasePolishPlan.portalOpacityRange, file: file, line: line)
    XCTAssertInRange(snapshot.backdropAperture, CinematicStagePhasePolishPlan.backdropApertureRange, file: file, line: line)
    XCTAssertInRange(snapshot.backdropOpacityBoost, CinematicStagePhasePolishPlan.backdropOpacityBoostRange, file: file, line: line)
    XCTAssertInRange(snapshot.fractureOpacity, CinematicStagePhasePolishPlan.fractureOpacityRange, file: file, line: line)
    XCTAssertInRange(snapshot.fractureSpread, CinematicStagePhasePolishPlan.fractureSpreadRange, file: file, line: line)
    XCTAssertInRange(snapshot.healingOpacity, CinematicStagePhasePolishPlan.healingOpacityRange, file: file, line: line)
    XCTAssertInRange(snapshot.poseCadence, CinematicStagePhasePolishPlan.poseCadenceRange, file: file, line: line)
    XCTAssertInRange(snapshot.orbPulseCadence, CinematicStagePhasePolishPlan.orbPulseCadenceRange, file: file, line: line)
    XCTAssertInRange(snapshot.sigilOrbitCadence, CinematicStagePhasePolishPlan.sigilOrbitCadenceRange, file: file, line: line)
    XCTAssertInRange(snapshot.fractureCadence, CinematicStagePhasePolishPlan.fractureCadenceRange, file: file, line: line)
    XCTAssertFalse(snapshot.identifier.isEmpty, file: file, line: line)
    XCTAssertFalse(snapshot.wizardPoseIdentifier.isEmpty, file: file, line: line)
    XCTAssertFalse(snapshot.staffOrbIdentifier.isEmpty, file: file, line: line)
    XCTAssertFalse(snapshot.sigilEmphasisIdentifier.isEmpty, file: file, line: line)
    XCTAssertFalse(snapshot.portalBackdropIdentifier.isEmpty, file: file, line: line)
    XCTAssertFalse(snapshot.fractureRecoveryIdentifier.isEmpty, file: file, line: line)
    XCTAssertFalse(snapshot.cadenceIdentifier.isEmpty, file: file, line: line)
}

private func assertNarrativeCueBounds(
    _ snapshot: CinematicDiagnosticsReport.NarrativeCueSnapshot,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertFalse(snapshot.identifier.isEmpty, file: file, line: line)
    XCTAssertFalse(snapshot.stageBeatIdentifier.isEmpty, file: file, line: line)
    XCTAssertFalse(snapshot.stagePhasePolishIdentifier.isEmpty, file: file, line: line)
    XCTAssertFalse(snapshot.languageIdentifier.isEmpty, file: file, line: line)
    XCTAssertFalse(snapshot.activityIdentifier.isEmpty, file: file, line: line)
    XCTAssertFalse(snapshot.influenceIdentifier.isEmpty, file: file, line: line)

    assertNarrativeCueDescriptorBounds(
        snapshot.questPlaque,
        maxCharacters: CinematicWorldTextService.questLabelMaxCharacters,
        maxWords: CinematicWorldTextService.questLabelMaxWords,
        file: file,
        line: line
    )
    assertNarrativeCueDescriptorBounds(
        snapshot.arenaInscription,
        maxCharacters: CinematicWorldTextService.arenaCalloutMaxCharacters,
        maxWords: CinematicWorldTextService.arenaCalloutMaxWords,
        file: file,
        line: line
    )
    assertNarrativeCueDescriptorBounds(
        snapshot.activityBanner,
        maxCharacters: CinematicWorldTextService.activityCalloutMaxCharacters,
        maxWords: CinematicWorldTextService.activityCalloutMaxWords,
        file: file,
        line: line
    )
    XCTAssertLessThanOrEqual(
        snapshot.questPlaque.secondaryText?.count ?? 0,
        CinematicBriefingService.titleMaxCharacters,
        file: file,
        line: line
    )
}

private func assertNarrativeCueDescriptorBounds(
    _ descriptor: CinematicDiagnosticsReport.NarrativeCueDescriptorSnapshot,
    maxCharacters: Int,
    maxWords: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    typealias RenderRecipe = CinematicSceneNarrativeCuePlan.CueDescriptor.PlaqueTreatmentDescriptor.RenderRecipe

    XCTAssertFalse(descriptor.identifier.isEmpty, file: file, line: line)
    XCTAssertFalse(descriptor.stableID.isEmpty, file: file, line: line)
    XCTAssertFalse(descriptor.text.isEmpty, file: file, line: line)
    XCTAssertLessThanOrEqual(descriptor.text.count, maxCharacters, file: file, line: line)
    XCTAssertLessThanOrEqual(wordCount(descriptor.text), maxWords, file: file, line: line)
    XCTAssertInRange(descriptor.scale, CinematicSceneNarrativeCuePlan.cueScaleRange, file: file, line: line)
    XCTAssertInRange(descriptor.opacity, CinematicSceneNarrativeCuePlan.cueOpacityRange, file: file, line: line)
    XCTAssertInRange(descriptor.cadence, CinematicSceneNarrativeCuePlan.cueCadenceRange, file: file, line: line)
    XCTAssertFalse(descriptor.anchorIdentifier.isEmpty, file: file, line: line)
    XCTAssertFalse(descriptor.visibilityIdentifier.isEmpty, file: file, line: line)
    XCTAssertFalse(descriptor.lightFamilyIdentifier.isEmpty, file: file, line: line)
    XCTAssertFalse(descriptor.tintFamilyIdentifier.isEmpty, file: file, line: line)
    XCTAssertFalse(descriptor.plaqueTreatmentIdentifier.isEmpty, file: file, line: line)
    XCTAssertFalse(descriptor.plaqueTreatmentAccentIdentifier.isEmpty, file: file, line: line)
    XCTAssertFalse(descriptor.plaqueTreatmentRouteIdentifier.isEmpty, file: file, line: line)
    XCTAssertTrue(descriptor.identifier.contains(descriptor.plaqueTreatmentIdentifier), file: file, line: line)
    XCTAssertFalse(descriptor.plaqueTreatmentRenderRecipeIdentifier.isEmpty, file: file, line: line)
    XCTAssertEqual(
        descriptor.plaqueTreatmentRenderPrimitiveCount,
        descriptor.plaqueTreatmentRenderPrimitiveIdentifiers.count,
        file: file,
        line: line
    )
    XCTAssertInRange(
        descriptor.plaqueTreatmentRenderPrimitiveCount,
        RenderRecipe.primitiveCountRange,
        file: file,
        line: line
    )
    XCTAssertTrue(
        descriptor.plaqueTreatmentRenderPrimitiveIdentifiers.allSatisfy {
            $0.count <= RenderRecipe.primitiveIdentifierMaxCharacters
        },
        file: file,
        line: line
    )
    assertNarrativeCueLayoutBounds(descriptor.layout, file: file, line: line)
}

private func assertNarrativeCueLayoutBounds(
    _ layout: CinematicDiagnosticsReport.NarrativeCueLayoutSnapshot,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertFalse(layout.identifier.isEmpty, file: file, line: line)
    XCTAssertInRange(layout.anchorPosition.x, CinematicSceneNarrativeCuePlan.cueAnchorXRange, file: file, line: line)
    XCTAssertInRange(layout.anchorPosition.y, CinematicSceneNarrativeCuePlan.cueAnchorYRange, file: file, line: line)
    XCTAssertInRange(layout.anchorPosition.z, CinematicSceneNarrativeCuePlan.cueAnchorZRange, file: file, line: line)
    XCTAssertFalse(layout.facingModeIdentifier.isEmpty, file: file, line: line)
    XCTAssertInRange(layout.plateWidth, CinematicSceneNarrativeCuePlan.cuePlateWidthRange, file: file, line: line)
    XCTAssertInRange(layout.plateHeight, CinematicSceneNarrativeCuePlan.cuePlateHeightRange, file: file, line: line)
    XCTAssertInRange(layout.primaryTextWidth, CinematicSceneNarrativeCuePlan.cueTextWidthRange, file: file, line: line)
    XCTAssertInRange(layout.secondaryTextWidth, CinematicSceneNarrativeCuePlan.cueTextWidthRange, file: file, line: line)
    XCTAssertInRange(layout.primaryFontSize, CinematicSceneNarrativeCuePlan.cueFontSizeRange, file: file, line: line)
    XCTAssertInRange(layout.secondaryFontSize, CinematicSceneNarrativeCuePlan.cueFontSizeRange, file: file, line: line)
    XCTAssertInRange(layout.backingOpacity, CinematicSceneNarrativeCuePlan.cueBackingOpacityRange, file: file, line: line)
    XCTAssertFalse(layout.glyphSideIdentifier.isEmpty, file: file, line: line)
    XCTAssertInRange(layout.glyphOffset.x, CinematicSceneNarrativeCuePlan.cueOffsetXRange, file: file, line: line)
    XCTAssertInRange(layout.glyphOffset.y, CinematicSceneNarrativeCuePlan.cueOffsetYRange, file: file, line: line)
    XCTAssertInRange(layout.glyphOffset.z, CinematicSceneNarrativeCuePlan.cueLayerZRange, file: file, line: line)
    XCTAssertInRange(layout.plateDepth, CinematicSceneNarrativeCuePlan.cuePlateDepthRange, file: file, line: line)
    XCTAssertInRange(layout.plateZOffset, CinematicSceneNarrativeCuePlan.cueLayerZRange, file: file, line: line)
    XCTAssertInRange(layout.primaryTextOffset.x, CinematicSceneNarrativeCuePlan.cueOffsetXRange, file: file, line: line)
    XCTAssertInRange(layout.primaryTextOffset.y, CinematicSceneNarrativeCuePlan.cueOffsetYRange, file: file, line: line)
    XCTAssertInRange(layout.primaryTextOffset.z, CinematicSceneNarrativeCuePlan.cueLayerZRange, file: file, line: line)
    XCTAssertInRange(layout.secondaryTextOffset.x, CinematicSceneNarrativeCuePlan.cueOffsetXRange, file: file, line: line)
    XCTAssertInRange(layout.secondaryTextOffset.y, CinematicSceneNarrativeCuePlan.cueOffsetYRange, file: file, line: line)
    XCTAssertInRange(layout.secondaryTextOffset.z, CinematicSceneNarrativeCuePlan.cueLayerZRange, file: file, line: line)
}

private func XCTAssertTintInRange(
    red: Float,
    green: Float,
    blue: Float,
    opacity: Float,
    blendFraction: Float,
    opacityRange: ClosedRange<Float>,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertInRange(red, CinematicStageAtmospherePlan.colorComponentRange, file: file, line: line)
    XCTAssertInRange(green, CinematicStageAtmospherePlan.colorComponentRange, file: file, line: line)
    XCTAssertInRange(blue, CinematicStageAtmospherePlan.colorComponentRange, file: file, line: line)
    XCTAssertInRange(opacity, opacityRange, file: file, line: line)
    XCTAssertInRange(blendFraction, CinematicStageAtmospherePlan.surfaceTintBlendRange, file: file, line: line)
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

private func XCTAssertFinite(
    _ value: Float,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertTrue(value.isFinite, file: file, line: line)
}

private func XCTAssertFinite(
    _ value: SIMD3<Float>,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertTrue(value.x.isFinite, file: file, line: line)
    XCTAssertTrue(value.y.isFinite, file: file, line: line)
    XCTAssertTrue(value.z.isFinite, file: file, line: line)
}
