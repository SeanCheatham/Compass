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
            Set(["none", "failedVerify", "dirtyWorktree", "promotionFailed"])
        )
        XCTAssertEqual(
            Set(reports.map(\.recoveryCue.treatmentIdentifier)),
            Set(["none", "verify-failure", "dirty-cleanup", "promotion-branch"])
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

        XCTAssertEqual(reports.count, 5)
        XCTAssertEqual(activeReports.count, 4)
        XCTAssertEqual(
            Set(activeReports.map(\.nativeFeedback.styleIdentifier)),
            Set(["verify", "warning", "failure"])
        )
        XCTAssertTrue(activeReports.contains { $0.nativeFeedback.sourceIdentifier == "native:verifyStarted" })
        XCTAssertTrue(activeReports.contains { $0.nativeFeedback.sourceIdentifier == "native:postChecksFailed" })
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
        XCTAssertEqual(verifyReport.narrativeCue.questPlaque.plaqueTreatmentAccentIdentifier, "verify-seal")
        XCTAssertEqual(verifyReport.narrativeCue.questPlaque.plaqueTreatmentRouteIdentifier, "verifyStarted.verify")
        XCTAssertEqual(
            verifyReport.narrativeCue.questPlaque.plaqueTreatmentRenderPrimitiveIdentifiers,
            ["rail.top", "rail.bottom", "seal.left", "seal.right"]
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
        XCTAssertTrue(nativeFeedbackCheck.detail.contains("active 4"))
        XCTAssertTrue(nativeFeedbackCheck.detail.contains("routes fracture,seal,warning"))
        XCTAssertTrue(nativeFeedbackCheck.detail.contains("expired 1"))
        XCTAssertEqual(nativeFeedbackTreatmentCheck.status, .pass)
        XCTAssertTrue(nativeFeedbackTreatmentCheck.detail.contains("accents 4/4"))
        XCTAssertTrue(nativeFeedbackTreatmentCheck.detail.contains("prims 4/4"))
        XCTAssertTrue(nativeFeedbackTreatmentCheck.detail.contains("routes 4/4"))
        XCTAssertTrue(nativeFeedbackTreatmentCheck.detail.contains("pairs 4/4"))
        XCTAssertTrue(nativeFeedbackTreatmentCheck.detail.contains("surfaces 4/4"))
        XCTAssertTrue(nativeFeedbackTreatmentCheck.detail.contains("params 4/4"))
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
                "immediate",
                "commit-constellation",
                "idle-story-cycle",
                "timeline-focus",
                "run-recap",
                "run-recap-share",
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
                "camera-shot-commit-constellation",
                "camera-shot-failure"
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
                    "immediate",
                    "commit-constellation",
                    "idle-story-cycle",
                    "timeline-focus",
                    "run-recap",
                    "run-recap-share",
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
                    "camera-shot-commit-constellation",
                    "camera-shot-failure"
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
        XCTAssertTrue(summary.exportText.contains("Repository/context (9 rows)"))
        XCTAssertTrue(summary.exportText.contains("Motifs (2 rows)"))
        XCTAssertTrue(summary.exportText.contains("Stage motion/effects (9 rows)"))
        XCTAssertTrue(summary.exportText.contains("Narrative/overlay (7 rows)"))
        XCTAssertTrue(summary.exportText.contains("Assets/textures (2 rows)"))
        XCTAssertTrue(summary.exportText.contains("Tuning (4 rows)"))
        XCTAssertTrue(summary.exportText.contains("Camera shots (8 rows)"))
        XCTAssertTrue(summary.exportText.contains("Visual smoke (pass, 17 checks)"))
        XCTAssertTrue(summary.exportText.contains("Plaque treatments (pass, 4 recipes): smoke pass"))
        XCTAssertTrue(summary.exportText.contains("failure-fracture: accent failure-fracture"))
        XCTAssertTrue(summary.exportText.contains("Overlay fallback: pass"))
        XCTAssertTrue(summary.exportText.contains("Native feedback coverage: pass"))
        XCTAssertTrue(summary.exportText.contains("Native feedback treatment: pass"))
        XCTAssertTrue(summary.exportText.contains("Idle story cycle: pass"))
        XCTAssertTrue(summary.exportText.contains(report.languageMotif.sigilIdentifier))
        XCTAssertTrue(summary.exportText.contains(report.languageMotif.styleIdentifier))
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
                "world-quest",
                "world-arena",
                "world-activity"
            ]
        )

        for rowID in ["narrative-cues", "narrative-layout", "overlay-display", "native-feedback-history"] {
            XCTAssertEqual(
                summary.sections.filter { section in
                    section.rows.contains { $0.id == rowID }
                }.map(\.id),
                ["narrative-overlay"]
            )
        }
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

            let report = CinematicDiagnostics.currentReport(for: project)
            let expected = CinematicDiagnostics.report(
                repoName: "CurrentDiagnosticsRepo",
                phase: "Developing",
                immediateTitle: "Expose current cinematic diagnostics",
                completedCount: 2,
                latestEvent: project.liveLog.last.map(CinematicBriefingEvent.init(line:)),
                languageProfile: project.languageProfile,
                activityProfile: project.activityProfile,
                influenceSettings: project.cinematicInfluenceSettings,
                isRunning: project.isRunning,
                isAutoPlaying: project.isAutoPlaying,
                isPaused: project.isPaused,
                hasRepository: project.hasRepository
            )

            XCTAssertEqual(report, expected)
            XCTAssertEqual(report.repoName, "CurrentDiagnosticsRepo")
            XCTAssertEqual(report.phase, "Developing")
            XCTAssertEqual(report.immediateTitle, "Expose current cinematic diagnostics")
            XCTAssertEqual(report.completedCount, 2)
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

            let report = CinematicDiagnostics.currentReport(for: project)
            let expected = CinematicDiagnostics.report(
                repoName: "NativeDiagnosticsRepo",
                phase: "Verifying",
                immediateTitle: "Thread native feedback into cinematic diagnostics",
                completedCount: 1,
                latestEvent: nil,
                languageProfile: project.languageProfile,
                activityProfile: project.activityProfile,
                influenceSettings: project.cinematicInfluenceSettings,
                isRunning: project.isRunning,
                isAutoPlaying: project.isAutoPlaying,
                isPaused: project.isPaused,
                hasRepository: project.hasRepository,
                nativeFeedbackCue: cue,
                nativeFeedbackLifecycle: project.cinematicNativeFeedbackCueLifecycle
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
        XCTAssertTrue(summary.exportText.contains("focus-shot:victory"))
        XCTAssertTrue(summary.exportText.contains("end-card-treatment:verify-seal"))
        XCTAssertTrue(summary.exportText.contains("Run recap focus: active"))
        XCTAssertTrue(summary.exportText.contains("Run recap end card: active"))
        XCTAssertTrue(summary.exportText.contains("status 1 commit highlight"))
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
        let focusRow = summary.rows.first { $0.id == "run-recap-focus" }
        let cardRow = summary.rows.first { $0.id == "run-recap-end-card" }

        XCTAssertFalse(report.runRecap.isAvailable)
        XCTAssertEqual(report.runRecap.availabilityIdentifier, "active-run")
        XCTAssertEqual(report.runRecap.identifier, "run-recap.empty|reason:active-run")
        XCTAssertFalse(report.runRecapShare.isAvailable)
        XCTAssertEqual(report.runRecapShare.availabilityReason, "active-run")
        XCTAssertEqual(report.runRecapShare.recapIdentifier, report.runRecap.identifier)
        XCTAssertTrue(report.runRecapShare.text.contains("Availability: unavailable (active-run)"))
        XCTAssertFalse(report.runRecapSceneFocus.isActive)
        XCTAssertEqual(report.runRecapSceneFocus.identifier, "run-recap-scene-focus.none")
        XCTAssertFalse(report.runRecapEndCard.isActive)
        XCTAssertEqual(report.runRecapEndCard.identifier, "run-recap-end-card.none")
        XCTAssertTrue(row?.detail.contains("empty active-run") == true)
        XCTAssertTrue(shareRow?.detail.contains("empty active-run") == true)
        XCTAssertEqual(focusRow?.detail, "empty")
        XCTAssertEqual(cardRow?.detail, "empty")
        XCTAssertTrue(summary.exportText.contains("Run recap: empty active-run"))
        XCTAssertTrue(summary.exportText.contains("Run recap share: empty active-run"))
        XCTAssertTrue(summary.exportText.contains("Run recap focus: empty"))
        XCTAssertTrue(summary.exportText.contains("Run recap end card: empty"))
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
}

private struct CinematicDiagnosticsInput {
    var repoName: String
    var phase: String
    var immediateTitle: String
    var completedCount: Int
    var latestEvent: CinematicBriefingEvent?
    var languageProfile: RepositoryLanguageProfile
    var activityProfile: RepositoryActivityProfile
    var influenceSettings: CinematicInfluenceSettings
    var commitConstellationPlan: CinematicCommitConstellationPlan = .empty
    var runRecapPlan: CinematicRunRecapPlan = .empty(reason: "no-finished-session")
    var runRecapSceneFocusPlan: CinematicRunRecapSceneFocusPlan = .none
    var runRecapEndCardPlan: CinematicRunRecapEndCardPlan = .none
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
        influenceSettings: input.influenceSettings,
        commitConstellationPlan: input.commitConstellationPlan,
        runRecapPlan: input.runRecapPlan,
        runRecapSceneFocusPlan: input.runRecapSceneFocusPlan,
        runRecapEndCardPlan: input.runRecapEndCardPlan
    )
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
