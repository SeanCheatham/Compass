import Foundation
@testable import Compass
import XCTest

final class CinematicRunRecapShareArtifactSourceBadgeTests: XCTestCase {
    func testRepoLocalActiveOnlyBaselineIsHidden() {
        let activeHistory = history(seed: "repo-local-active", sessions: [4])
        let reconciliation = CinematicRunRecapShareArtifactSourceReconciliationPlanner.plan(
            activeHistoryPlan: activeHistory,
            activitySourceSnapshot: .notScanned(activeStorage: .repoLocal)
        )

        let badge = CinematicRunRecapShareArtifactSourceBadgePlanner.plan(
            reconciliationPlan: reconciliation
        )

        XCTAssertEqual(reconciliation.stateIdentifier, "active-only")
        XCTAssertFalse(reconciliation.isApplicationSupportComparison)
        XCTAssertFalse(badge.isVisible)
        XCTAssertEqual(badge.sourceReconciliationIdentifier, reconciliation.identifier)
        XCTAssertEqual(badge.stateIdentifier, "active-only")
        XCTAssertEqual(badge.label, "")
        XCTAssertEqual(badge.detail, "")
        XCTAssertEqual(badge.help, "")
        XCTAssertEqual(badge.copyText, "")
        XCTAssertEqual(badge.copyLabel, "")
        XCTAssertEqual(badge.severity, .healthy)
        XCTAssertEqual(badge.tintIdentifier, "hidden")
    }

    func testApplicationSupportSourceStatesAreVisibleAndBounded() throws {
        let sharedHistory = history(seed: "compatible", sessions: [11])
        let compatible = reconciliation(active: sharedHistory, repoLocal: sharedHistory)

        let activeHistory = history(seed: "active", sessions: [20])
        let repoLocalExtra = history(seed: "active", sessions: [21, 20])
        let extra = reconciliation(active: activeHistory, repoLocal: repoLocalExtra)

        let missing = reconciliation(
            active: history(seed: "missing-repo-local", sessions: [12]),
            repoLocal: nil
        )

        let activeMissing = reconciliation(
            active: .unavailable(
                reason: "storage-root-missing",
                storageRootURL: URL(fileURLWithPath: "/tmp/support-missing/.compass"),
                sessionsURL: URL(fileURLWithPath: "/tmp/support-missing/.compass/sessions")
            ),
            repoLocal: history(seed: "repo-local-available", sessions: [33])
        )

        let scanWarnings = reconciliation(
            active: history(seed: "scan-active", sessions: [41]),
            repoLocal: history(
                seed: "scan-warning",
                sessions: [],
                availabilityReason: "no-recap-share-artifacts",
                warnings: ["recap-share-artifact-history.warning.corrupt"]
            )
        )

        let cases: [(String, CinematicRunRecapShareArtifactSourceReconciliationPlan, String, CompassWorkspaceStorageAssessment.Severity, String)] = [
            ("compatible", compatible, "Application Support source", .info, "teal"),
            ("repo-local-missing", missing, "Repo-local source missing", .info, "blue"),
            ("repo-local-extra", extra, "Repo-local has extras", .warning, "orange"),
            ("active-missing-repo-local-available", activeMissing, "Active source missing", .failure, "red"),
            ("scan-warnings", scanWarnings, "Artifact scan warning", .warning, "yellow")
        ]

        for (stateIdentifier, reconciliation, label, severity, tintIdentifier) in cases {
            let badge = CinematicRunRecapShareArtifactSourceBadgePlanner.plan(
                reconciliationPlan: reconciliation
            )

            XCTAssertEqual(reconciliation.stateIdentifier, stateIdentifier)
            XCTAssertTrue(badge.isVisible, stateIdentifier)
            XCTAssertEqual(badge.label, label, stateIdentifier)
            XCTAssertEqual(badge.severity, severity, stateIdentifier)
            XCTAssertEqual(badge.tintIdentifier, tintIdentifier, stateIdentifier)
            XCTAssertEqual(badge.sourceReconciliationIdentifier, reconciliation.identifier, stateIdentifier)
            XCTAssertTrue(badge.identifier.hasPrefix("run-recap-share-artifact-source-badge"), stateIdentifier)
            XCTAssertTrue(
                badge.accessibilityIdentifier.hasPrefix("cinematic-run-recap-artifact-source-badge-"),
                stateIdentifier
            )
            XCTAssertTrue(
                badge.copyAccessibilityIdentifier.hasPrefix("cinematic-run-recap-artifact-source-badge-copy-"),
                stateIdentifier
            )
            XCTAssertTrue(badge.copyText.contains("Reconciliation: \(reconciliation.identifier)"), stateIdentifier)
            XCTAssertTrue(badge.copyText.contains("State: \(stateIdentifier)"), stateIdentifier)
            XCTAssertTrue(badge.copyText.contains("Read-only: copy only"), stateIdentifier)
            XCTAssertEqual(badge.copyLabel, "Copy source details", stateIdentifier)
            assertBadgeIsBounded(badge, file: #filePath, line: #line)
        }

        let compatibleBadge = CinematicRunRecapShareArtifactSourceBadgePlanner.plan(
            reconciliationPlan: compatible
        )
        let extraBadge = CinematicRunRecapShareArtifactSourceBadgePlanner.plan(
            reconciliationPlan: extra
        )
        XCTAssertNotEqual(compatible.identifier, extra.identifier)
        XCTAssertNotEqual(compatibleBadge.identifier, extraBadge.identifier)
        XCTAssertNotEqual(compatibleBadge.copyText, extraBadge.copyText)
        XCTAssertTrue(extraBadge.copyText.contains("Repo-local extra ids:"))
    }

    func testBadgePlannerDoesNotMutateReconciliationInputs() {
        let activeHistory = history(seed: "read-only", sessions: [55])
        let repoLocalHistory = history(seed: "read-only", sessions: [56, 55])
        let activeBefore = activeHistory
        let repoLocalBefore = repoLocalHistory
        let reconciliation = reconciliation(active: activeHistory, repoLocal: repoLocalHistory)
        let reconciliationBefore = reconciliation

        let badge = CinematicRunRecapShareArtifactSourceBadgePlanner.plan(
            reconciliationPlan: reconciliation
        )

        XCTAssertTrue(badge.isVisible)
        XCTAssertEqual(activeHistory, activeBefore)
        XCTAssertEqual(repoLocalHistory, repoLocalBefore)
        XCTAssertEqual(reconciliation, reconciliationBefore)
        XCTAssertTrue(badge.copyText.contains("no repair, migration, deletion"))
        XCTAssertTrue(badge.copyText.contains("artifact-history mutation"))
    }

    func testOverlayWiresSourceReconciliationAndAccessibilityIdentifiers() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/Compass/CinematicTab.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains(
                "artifactSourceReconciliationPlan:\n                                project.cinematicRunRecapShareArtifactSourceReconciliation"
            )
        )
        XCTAssertTrue(source.contains("CinematicRunRecapShareArtifactSourceBadgePlanner.plan"))
        XCTAssertTrue(source.contains("sourceBadgeStrip(sourceBadgePlan)"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(sourceBadgePlan.accessibilityIdentifier)"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(sourceBadgePlan.copyAccessibilityIdentifier)"))
        XCTAssertTrue(source.contains("NSPasteboard.general.setString(sourceBadgePlan.copyText, forType: .string)"))
    }

    private func reconciliation(
        active activeHistory: CinematicRunRecapShareArtifactHistoryPlan,
        repoLocal repoLocalHistory: CinematicRunRecapShareArtifactHistoryPlan?
    ) -> CinematicRunRecapShareArtifactSourceReconciliationPlan {
        CinematicRunRecapShareArtifactSourceReconciliationPlanner.plan(
            activeHistoryPlan: activeHistory,
            repoLocalHistoryPlan: repoLocalHistory,
            activitySourceSnapshot: .notScanned(activeStorage: .applicationSupport)
        )
    }

    private func history(
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

    private func assertBadgeIsBounded(
        _ badge: CinematicRunRecapShareArtifactSourceBadgePlan,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertLessThanOrEqual(
            badge.identifier.count,
            CinematicRunRecapShareArtifactSourceBadgePlan.identifierMaxCharacters,
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            badge.label.count,
            CinematicRunRecapShareArtifactSourceBadgePlan.labelMaxCharacters,
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            badge.detail.count,
            CinematicRunRecapShareArtifactSourceBadgePlan.detailMaxCharacters,
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            badge.help.count,
            CinematicRunRecapShareArtifactSourceBadgePlan.helpMaxCharacters,
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            badge.copyText.count,
            CinematicRunRecapShareArtifactSourceBadgePlan.copyTextMaxCharacters,
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            badge.copyLabel.count,
            CinematicRunRecapShareArtifactSourceBadgePlan.copyLabelMaxCharacters,
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            badge.systemImage.count,
            CinematicRunRecapShareArtifactSourceBadgePlan.systemImageMaxCharacters,
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            badge.tintIdentifier.count,
            CinematicRunRecapShareArtifactSourceBadgePlan.tintIdentifierMaxCharacters,
            file: file,
            line: line
        )
    }
}
