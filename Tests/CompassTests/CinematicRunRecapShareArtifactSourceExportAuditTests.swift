import Foundation
@testable import Compass
import XCTest

final class CinematicRunRecapShareArtifactSourceExportAuditTests: XCTestCase {
    func testRepoLocalActiveBaselineAuditIsHiddenAndDoesNotChangeExports() {
        let activeHistory = history(seed: "repo-local", sessions: [4, 3])
        let reconciliation = CinematicRunRecapShareArtifactSourceReconciliationPlanner.plan(
            activeHistoryPlan: activeHistory,
            activitySourceSnapshot: .notScanned(activeStorage: .repoLocal)
        )

        let audit = CinematicRunRecapShareArtifactSourceExportAuditPlanner.plan(
            reconciliationPlan: reconciliation
        )
        let selectedWithoutAudit = CinematicRunRecapShareArtifactSubsetExportPlanner.plan(
            historyPlan: activeHistory,
            selectedEntryIdentifier: activeHistory.entries.last?.identifier,
            scope: .selected
        )
        let selectedWithAudit = CinematicRunRecapShareArtifactSubsetExportPlanner.plan(
            historyPlan: activeHistory,
            selectedEntryIdentifier: activeHistory.entries.last?.identifier,
            scope: .selected,
            sourceExportAuditPlan: audit
        )
        let rollupWithoutAudit = CinematicRunRecapShareArtifactRollupPlanner.plan(
            historyPlan: activeHistory
        )
        let rollupWithAudit = CinematicRunRecapShareArtifactRollupPlanner.plan(
            historyPlan: activeHistory,
            sourceExportAuditPlan: audit
        )
        let libraryWithAudit = CinematicRunRecapShareArtifactSourceExportAuditPlanner.markdownExport(
            baseMarkdown: activeHistory.combinedMarkdownExport,
            sourceExportAuditPlan: audit,
            limit: CinematicRunRecapShareArtifactHistoryPlan.combinedMarkdownMaxCharacters
        )

        XCTAssertEqual(reconciliation.stateIdentifier, "active-only")
        XCTAssertFalse(audit.isVisible)
        XCTAssertEqual(audit.markdownSection, "")
        XCTAssertFalse(selectedWithAudit.sourceExportAuditIncluded)
        XCTAssertNil(selectedWithAudit.sourceExportAuditIdentifier)
        XCTAssertEqual(selectedWithAudit.sourceExportAuditMarkdownLength, 0)
        XCTAssertEqual(selectedWithAudit, selectedWithoutAudit)
        XCTAssertEqual(rollupWithAudit, rollupWithoutAudit)
        XCTAssertEqual(libraryWithAudit, activeHistory.combinedMarkdownExport)
        XCTAssertFalse(selectedWithAudit.markdownContents.contains("## Storage Source"))
        XCTAssertFalse(rollupWithAudit.exportText.contains("## Storage Source"))
    }

    func testApplicationSupportStatesProduceVisibleBoundedAuditMarkdown() {
        let sharedHistory = history(seed: "compatible", sessions: [11])
        let compatible = reconciliation(active: sharedHistory, repoLocal: sharedHistory)
        let missing = reconciliation(
            active: history(seed: "missing-repo-local", sessions: [12]),
            repoLocal: nil
        )
        let extra = reconciliation(
            active: history(seed: "extra", sessions: [20]),
            repoLocal: history(seed: "extra", sessions: [21, 20])
        )
        let activeMissing = reconciliation(
            active: .unavailable(
                reason: "storage-root-missing",
                storageRootURL: URL(fileURLWithPath: "/tmp/support-missing/.compass"),
                sessionsURL: URL(fileURLWithPath: "/tmp/support-missing/.compass/sessions")
            ),
            repoLocal: history(seed: "repo-local-available", sessions: [33])
        )
        let scanWarning = reconciliation(
            active: history(seed: "scan-active", sessions: [41]),
            repoLocal: history(
                seed: "scan-warning",
                sessions: [],
                availabilityReason: "no-recap-share-artifacts",
                warnings: ["recap-share-artifact-history.warning.corrupt"]
            )
        )
        let cases: [(String, CinematicRunRecapShareArtifactSourceReconciliationPlan)] = [
            ("compatible", compatible),
            ("repo-local-missing", missing),
            ("repo-local-extra", extra),
            ("active-missing-repo-local-available", activeMissing),
            ("scan-warnings", scanWarning)
        ]

        for (stateIdentifier, reconciliation) in cases {
            let audit = CinematicRunRecapShareArtifactSourceExportAuditPlanner.plan(
                reconciliationPlan: reconciliation
            )

            XCTAssertTrue(audit.isVisible, stateIdentifier)
            XCTAssertEqual(audit.sourceReconciliationIdentifier, reconciliation.identifier, stateIdentifier)
            XCTAssertEqual(audit.stateIdentifier, stateIdentifier, stateIdentifier)
            XCTAssertEqual(audit.activeTotalCount, reconciliation.activeTotalCount, stateIdentifier)
            XCTAssertEqual(audit.repoLocalTotalCount, reconciliation.repoLocalTotalCount, stateIdentifier)
            XCTAssertEqual(audit.activeLatestSessionNumber, reconciliation.activeLatestSessionNumber, stateIdentifier)
            XCTAssertEqual(audit.repoLocalLatestSessionNumber, reconciliation.repoLocalLatestSessionNumber, stateIdentifier)
            XCTAssertEqual(audit.activeWarningCount, reconciliation.activeWarningCount, stateIdentifier)
            XCTAssertEqual(audit.repoLocalWarningCount, reconciliation.repoLocalWarningCount, stateIdentifier)
            XCTAssertTrue(audit.markdownSection.contains("## Storage Source"), stateIdentifier)
            XCTAssertTrue(audit.markdownSection.contains("- Reconciliation: \(reconciliation.identifier)"), stateIdentifier)
            XCTAssertTrue(audit.markdownSection.contains("- State: \(stateIdentifier)"), stateIdentifier)
            XCTAssertTrue(audit.markdownSection.contains("Read-only: export audit only"), stateIdentifier)
            XCTAssertLessThanOrEqual(
                audit.identifier.count,
                CinematicRunRecapShareArtifactSourceExportAuditPlan.identifierMaxCharacters,
                stateIdentifier
            )
            XCTAssertLessThanOrEqual(
                audit.markdownLength,
                CinematicRunRecapShareArtifactSourceExportAuditPlan.markdownMaxCharacters,
                stateIdentifier
            )
            XCTAssertLessThanOrEqual(
                audit.readOnlyDisclaimer.count,
                CinematicRunRecapShareArtifactSourceExportAuditPlan.readOnlyDisclaimerMaxCharacters,
                stateIdentifier
            )
            XCTAssertLessThanOrEqual(
                audit.representativeActiveEntryIdentifiers.count,
                CinematicRunRecapShareArtifactSourceExportAuditPlan.representativeEntryLimit,
                stateIdentifier
            )
            XCTAssertLessThanOrEqual(
                audit.representativeRepoLocalEntryIdentifiers.count,
                CinematicRunRecapShareArtifactSourceExportAuditPlan.representativeEntryLimit,
                stateIdentifier
            )
            XCTAssertLessThanOrEqual(
                audit.representativeRepoLocalExtraEntryIdentifiers.count,
                CinematicRunRecapShareArtifactSourceExportAuditPlan.representativeEntryLimit,
                stateIdentifier
            )
        }
    }

    func testVisibleAuditThreadsIntoLibrarySubsetRollupAndDiagnosticsExports() {
        let activeHistory = history(seed: "diagnostics-active", sessions: [7])
        let repoLocalHistory = history(seed: "diagnostics-active", sessions: [8, 7])
        let reconciliation = reconciliation(active: activeHistory, repoLocal: repoLocalHistory)
        let audit = CinematicRunRecapShareArtifactSourceExportAuditPlanner.plan(
            reconciliationPlan: reconciliation
        )

        let selectedWithoutAudit = CinematicRunRecapShareArtifactSubsetExportPlanner.plan(
            historyPlan: activeHistory,
            selectedEntryIdentifier: activeHistory.latestEntry?.identifier,
            scope: .selected
        )
        let selectedWithAudit = CinematicRunRecapShareArtifactSubsetExportPlanner.plan(
            historyPlan: activeHistory,
            selectedEntryIdentifier: activeHistory.latestEntry?.identifier,
            scope: .selected,
            sourceExportAuditPlan: audit
        )
        let filteredWithAudit = CinematicRunRecapShareArtifactSubsetExportPlanner.plan(
            historyPlan: activeHistory,
            scope: .filtered,
            sourceExportAuditPlan: audit
        )
        let rollupWithoutAudit = CinematicRunRecapShareArtifactRollupPlanner.plan(
            historyPlan: activeHistory
        )
        let rollupWithAudit = CinematicRunRecapShareArtifactRollupPlanner.plan(
            historyPlan: activeHistory,
            sourceExportAuditPlan: audit
        )
        let libraryWithAudit = CinematicRunRecapShareArtifactSourceExportAuditPlanner.markdownExport(
            baseMarkdown: activeHistory.combinedMarkdownExport,
            sourceExportAuditPlan: audit,
            limit: CinematicRunRecapShareArtifactHistoryPlan.combinedMarkdownMaxCharacters
        )
        let report = CinematicDiagnostics.report(
            repoName: "Compass",
            phase: "Succeeded",
            immediateTitle: "Audit recap artifact source",
            completedCount: 1,
            latestEvent: nil,
            languageProfile: languageProfile(primaryLanguage: .swift),
            activityProfile: .empty,
            activitySourceSnapshot: .notScanned(activeStorage: .applicationSupport),
            influenceSettings: CinematicInfluenceSettings(),
            runRecapShareArtifactHistoryPlan: activeHistory,
            runRecapShareArtifactSourceReconciliationPlan: reconciliation
        )
        let summary = CinematicDiagnosticsSummary(report: report)
        let rollupRow = summary.row(id: "run-recap-share-artifact-rollup")
        let previewRow = summary.row(id: "run-recap-share-artifact-preview")

        XCTAssertTrue(audit.isVisible)
        XCTAssertTrue(selectedWithAudit.sourceExportAuditIncluded)
        XCTAssertEqual(selectedWithAudit.sourceExportAuditIdentifier, audit.identifier)
        XCTAssertEqual(selectedWithAudit.sourceExportAuditMarkdownLength, audit.markdownLength)
        XCTAssertNotEqual(selectedWithAudit.identifier, selectedWithoutAudit.identifier)
        XCTAssertNotEqual(selectedWithAudit.exportIdentifier, selectedWithoutAudit.exportIdentifier)
        XCTAssertTrue(selectedWithAudit.markdownContents.contains("## Storage Source"))
        XCTAssertTrue(filteredWithAudit.markdownContents.contains("## Storage Source"))
        XCTAssertTrue(rollupWithAudit.sourceExportAuditIncluded)
        XCTAssertEqual(rollupWithAudit.sourceExportAuditIdentifier, audit.identifier)
        XCTAssertNotEqual(rollupWithAudit.identifier, rollupWithoutAudit.identifier)
        XCTAssertNotEqual(rollupWithAudit.exportIdentifier, rollupWithoutAudit.exportIdentifier)
        XCTAssertTrue(rollupWithAudit.exportText.contains("## Storage Source"))
        XCTAssertTrue(libraryWithAudit.contains("## Storage Source"))
        XCTAssertTrue(libraryWithAudit.contains("- State: repo-local-extra"))
        XCTAssertLessThanOrEqual(
            libraryWithAudit.count,
            CinematicRunRecapShareArtifactHistoryPlan.combinedMarkdownMaxCharacters
        )
        XCTAssertTrue(report.runRecapShareArtifactPreview.selectedExport.sourceExportAuditIncluded)
        XCTAssertEqual(report.runRecapShareArtifactPreview.selectedExport.sourceExportAuditIdentifier, audit.identifier)
        XCTAssertEqual(report.runRecapShareArtifactPreview.selectedExport.sourceExportAuditMarkdownLength, audit.markdownLength)
        XCTAssertTrue(report.runRecapShareArtifactPreview.filteredExport.sourceExportAuditIncluded)
        XCTAssertEqual(report.runRecapShareArtifactRollup.sourceExportAuditIdentifier, audit.identifier)
        XCTAssertEqual(report.runRecapShareArtifactRollup.sourceExportAuditMarkdownLength, audit.markdownLength)
        XCTAssertTrue(rollupRow?.detail.contains("source audit \(audit.markdownLength)") ?? false)
        XCTAssertTrue(previewRow?.detail.contains("source-audit \(audit.markdownLength)") ?? false)
        XCTAssertTrue(summary.exportText.contains("source audit \(audit.markdownLength)"))
        XCTAssertTrue(summary.exportText.contains("source-audit \(audit.markdownLength)"))
    }

    func testAuditPlanningIsReadOnlyAndBoundsRepresentativeIdentifiers() {
        let activeHistory = history(seed: String(repeating: "active-long-", count: 12), sessions: [9, 8, 7, 6, 5])
        let repoLocalHistory = history(seed: String(repeating: "repo-local-long-", count: 12), sessions: [10, 9, 8, 7, 6, 5])
        let activeBefore = activeHistory
        let repoLocalBefore = repoLocalHistory
        let reconciliation = reconciliation(active: activeHistory, repoLocal: repoLocalHistory)
        let reconciliationBefore = reconciliation

        let audit = CinematicRunRecapShareArtifactSourceExportAuditPlanner.plan(
            reconciliationPlan: reconciliation
        )

        XCTAssertEqual(activeHistory, activeBefore)
        XCTAssertEqual(repoLocalHistory, repoLocalBefore)
        XCTAssertEqual(reconciliation, reconciliationBefore)
        XCTAssertTrue(audit.isVisible)
        XCTAssertEqual(
            audit.representativeActiveEntryIdentifiers.count,
            CinematicRunRecapShareArtifactSourceExportAuditPlan.representativeEntryLimit
        )
        XCTAssertEqual(
            audit.representativeRepoLocalEntryIdentifiers.count,
            CinematicRunRecapShareArtifactSourceExportAuditPlan.representativeEntryLimit
        )
        XCTAssertEqual(
            audit.representativeRepoLocalExtraEntryIdentifiers.count,
            CinematicRunRecapShareArtifactSourceExportAuditPlan.representativeEntryLimit
        )
        XCTAssertTrue(audit.markdownSection.contains("no repair, migration, deletion"))
        XCTAssertTrue(audit.markdownSection.contains("artifact-history mutation"))
        XCTAssertLessThanOrEqual(
            audit.markdownLength,
            CinematicRunRecapShareArtifactSourceExportAuditPlan.markdownMaxCharacters
        )
    }

    func testOverlayWiresAuditIntoCopyPaths() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/Compass/CinematicTab.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("currentSourceExportAuditPlan"))
        XCTAssertTrue(source.contains("sourceExportAuditPlan: currentSourceExportAuditPlan"))
        XCTAssertTrue(source.contains("CinematicRunRecapShareArtifactSourceExportAuditPlanner.markdownExport"))
        XCTAssertTrue(source.contains("baseMarkdown: plan.combinedMarkdownExport"))
        XCTAssertTrue(source.contains("NSPasteboard.general.setString(export, forType: .string)"))
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
                statusSnippet: session.isMultiple(of: 2) ? "failed verify" : "succeeded",
                commitSnippet: "Commit \(session)",
                markdownContents: """
                # Compass Run Recap Share

                - Session: \(session)
                - Title: Recap \(session)
                - Status: succeeded

                ## Share Text

                ```text
                Body \(seed) \(session)
                ```
                """,
                markdownLength: 120
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
            combinedMarkdownExport: """
            # Compass Recap Share Artifact Library

            - Export: export-\(seed)
            - Total artifacts: \(entries.count)
            """
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
}
