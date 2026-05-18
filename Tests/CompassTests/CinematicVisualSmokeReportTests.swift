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
                "camera-phase-coverage",
                "pressure-influence-spread",
                "recovery-cue-coverage",
                "timeline-focus-coverage"
            ]
        )
        XCTAssertTrue(first.checks.allSatisfy { $0.status == .pass })
    }

    func testRepresentativeReportCoversExpectedVisualPaths() throws {
        let smoke = CinematicVisualSmokeReport.representative()
        let overlay = try XCTUnwrap(smoke.checks.first { $0.id == "overlay-fallback-usage" })
        let chrome = try XCTUnwrap(smoke.checks.first { $0.id == "chrome-strength" })
        let pressure = try XCTUnwrap(smoke.checks.first { $0.id == "pressure-influence-spread" })
        let recoveryCue = try XCTUnwrap(smoke.checks.first { $0.id == "recovery-cue-coverage" })
        let timelineFocus = try XCTUnwrap(smoke.checks.first { $0.id == "timeline-focus-coverage" })

        XCTAssertEqual(overlay.status, .pass)
        XCTAssertTrue(overlay.detail.contains("compact"))
        XCTAssertTrue(overlay.detail.contains("full"))
        XCTAssertTrue(overlay.detail.contains("fallback"))
        XCTAssertTrue(overlay.detail.contains("missing-repository"))
        XCTAssertTrue(chrome.detail.contains("compact-active"))
        XCTAssertTrue(chrome.detail.contains("full-readable"))
        XCTAssertTrue(chrome.detail.contains("fallback-readable"))
        XCTAssertTrue(pressure.detail.contains("clean"))
        XCTAssertTrue(pressure.detail.contains("heavy"))
        XCTAssertTrue(pressure.detail.contains("steady"))
        XCTAssertTrue(pressure.detail.contains("dramatic"))
        XCTAssertTrue(recoveryCue.detail.contains("failedVerify"))
        XCTAssertTrue(recoveryCue.detail.contains("dirtyWorktree"))
        XCTAssertTrue(recoveryCue.detail.contains("promotionFailed"))
        XCTAssertTrue(recoveryCue.detail.contains("history-chains"))
        XCTAssertTrue(timelineFocus.detail.contains("commit"))
        XCTAssertTrue(timelineFocus.detail.contains("recovery"))
        XCTAssertTrue(timelineFocus.detail.contains("failed-verify"))
        XCTAssertTrue(timelineFocus.detail.contains("commit-constellation"))
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
        XCTAssertTrue(smoke.warningIdentifiers.contains("visual-smoke.camera-phase-coverage"))
        XCTAssertTrue(smoke.warningIdentifiers.contains("visual-smoke.pressure-influence-spread"))
        XCTAssertTrue(smoke.warningIdentifiers.contains("visual-smoke.recovery-cue-coverage"))
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

    func testSummaryExportIncludesVisualSmokeWithoutChangingRowsOrSections() {
        let report = CinematicDiagnostics.representativeSmokeMatrix().first!
        let summary = CinematicDiagnosticsSummary(
            report: report,
            visualSmoke: CinematicVisualSmokeReport.representative()
        )

        XCTAssertTrue(summary.exportText.contains("Visual smoke (pass, 9 checks)"))
        XCTAssertTrue(summary.exportText.contains("Narrative cue readability: pass"))
        XCTAssertTrue(summary.exportText.contains("Pressure/influence spread: pass"))
        XCTAssertTrue(summary.exportText.contains("Recovery cue coverage: pass"))
        XCTAssertTrue(summary.exportText.contains("Timeline focus coverage: pass"))
        XCTAssertFalse(summary.sections.contains { $0.id == "visual-smoke" })
        XCTAssertEqual(summary.rows.count, CinematicDiagnosticsSummary.maxRows)
        XCTAssertEqual(
            summary.rows.map(\.id).prefix(6),
            [
                "repository",
                "immediate",
                "commit-constellation",
                "timeline-focus",
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
}
