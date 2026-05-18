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
                "timeline-focus-coverage"
            ]
        )
        XCTAssertTrue(first.checks.allSatisfy { $0.status == .pass })
    }

    func testRepresentativeReportCoversExpectedVisualPaths() throws {
        let smoke = CinematicVisualSmokeReport.representative()
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
        let timelineFocus = try XCTUnwrap(smoke.checks.first { $0.id == "timeline-focus-coverage" })

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
        XCTAssertTrue(timelineFocus.detail.contains("commit"))
        XCTAssertTrue(timelineFocus.detail.contains("recovery"))
        XCTAssertTrue(timelineFocus.detail.contains("failed-verify"))
        XCTAssertTrue(timelineFocus.detail.contains("commit-constellation"))
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
        XCTAssertTrue(smoke.warningIdentifiers.contains("visual-smoke.timeline-focus-coverage"))
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
        XCTAssertEqual(summary.visualSmoke.checkCountLabel, "14 checks")
        XCTAssertEqual(summary.visualSmoke.presentation.headerDetail, "14 checks | No warnings")
        XCTAssertEqual(summary.visualSmoke.presentation.defaultExpanded, false)
        XCTAssertEqual(summary.visualSmoke.presentation.attentionState, .normal)
        XCTAssertEqual(summary.visualSmoke.presentation.warningIdentifiers, [])
        XCTAssertEqual(summary.visualSmoke.presentation.needsAttention, false)
        XCTAssertEqual(summary.attentionSummary.targets, [])
        XCTAssertTrue(summary.attentionSummary.isEmpty)
        XCTAssertLessThanOrEqual(
            summary.visualSmoke.warningCountLabel.count,
            CinematicDiagnosticsSummary.visualSmokeCountMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            summary.visualSmoke.presentation.headerDetail.count,
            CinematicDiagnosticsSummary.headerDetailMaxCharacters
        )
        XCTAssertTrue(summary.exportText.contains("Visual smoke (pass, 14 checks)"))
        XCTAssertTrue(summary.exportText.contains("Narrative cue readability: pass"))
        XCTAssertTrue(summary.exportText.contains("Texture role coverage: pass"))
        XCTAssertTrue(summary.exportText.contains("Language layout coverage: pass"))
        XCTAssertTrue(summary.exportText.contains("Activity material treatment: pass"))
        XCTAssertTrue(summary.exportText.contains("Pressure/influence spread: pass"))
        XCTAssertTrue(summary.exportText.contains("Recovery cue coverage: pass"))
        XCTAssertTrue(summary.exportText.contains("Native feedback coverage: pass"))
        XCTAssertTrue(summary.exportText.contains("Native feedback treatment: pass"))
        XCTAssertTrue(summary.exportText.contains("Timeline focus coverage: pass"))
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
            summary.rows.map(\.id).prefix(7),
            [
                "repository",
                "immediate",
                "commit-constellation",
                "timeline-focus",
                "run-recap",
                "language-motif",
                "activity-motif"
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
        XCTAssertTrue(summary.visualSmoke.presentation.headerDetail.contains("14 checks"))
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
        XCTAssertEqual(assetCheck.status, .warning)
        XCTAssertEqual(assetCheck.warningIdentifier, "visual-smoke.asset-availability")
        XCTAssertEqual(textureCheck.status, .warning)
        XCTAssertEqual(textureCheck.warningIdentifier, "visual-smoke.texture-role-coverage")

        for check in summary.visualSmoke.checks {
            XCTAssertLessThanOrEqual(check.label.count, CinematicVisualSmokeReport.labelMaxCharacters)
            XCTAssertLessThanOrEqual(check.detail.count, CinematicVisualSmokeReport.detailMaxCharacters)
        }

        XCTAssertEqual(
            summary.attentionSummary.targets.map(\.targetGroupID),
            ["visual-smoke", "plaque-treatment-legend"]
        )
        let visualSmokeTarget = try XCTUnwrap(
            summary.attentionSummary.targets.first { $0.targetGroupID == "visual-smoke" }
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
        XCTAssertTrue(summary.exportText.contains("Warning summary (2 targets)"))
        XCTAssertTrue(
            summary.exportText.contains("Visual smoke -> visual-smoke (\(smoke.warningIdentifiers.count) warnings):")
        )
        XCTAssertTrue(
            summary.exportText.contains("Plaque treatments -> plaque-treatment-legend (1 warning):")
        )
        XCTAssertTrue(summary.exportText.contains("visual-smoke.asset-availability"))
        XCTAssertTrue(summary.exportText.contains("visual-smoke.texture-role-coverage"))
        XCTAssertTrue(summary.exportText.contains("visual-smoke.native-feedback-treatment-coverage"))
        XCTAssertTrue(summary.exportText.contains("Visual smoke (warning, 14 checks)"))
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
            summary.attentionSummary.targets.map(\.targetGroupID),
            ["visual-smoke", "plaque-treatment-legend"]
        )
        let visualSmokeTarget = try XCTUnwrap(
            summary.attentionSummary.targets.first { $0.targetGroupID == "visual-smoke" }
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
        XCTAssertTrue(summary.exportText.contains("Warning summary (2 targets)"))
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
