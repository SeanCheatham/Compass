import Foundation
@testable import Compass
import XCTest

final class CinematicRunRecapShareArtifactCommandDiagnosticsTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
    }

    func testSnapshotConstructionCorrelatesActionMenuAndCommandPlan() throws {
        let workspace = try makeInitializedWorkspace()
        for session in 1...4 {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-command-diagnostics-\(session).md",
                contents: artifactMarkdown(
                    session: session,
                    title: "Command Diagnostics \(session)",
                    status: "succeeded",
                    commit: "Command diagnostics commit \(session)",
                    body: "command diagnostics body \(session)"
                )
            )
        }
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let selected = try XCTUnwrap(history.entries.first { $0.sessionNumber == 3 })
        let pinned = try XCTUnwrap(history.entries.first { $0.sessionNumber == 1 })
        let held = try XCTUnwrap(history.entries.first { $0.sessionNumber == 2 })
        let context = CinematicRunRecapShareArtifactLibraryContext(
            selectedEntryIdentifier: selected.identifier,
            pinnedEntryIdentifiers: [pinned.identifier],
            comparisonTargetMode: .pinnedReference,
            savedTourHoldEntryIdentifier: held.identifier
        )
        let fixture = makeFixture(history: history, context: context)
        let commandPlan = CinematicRunRecapShareArtifactCommandPlanner.plan(actionMenuPlan: fixture.menu)
        let report = makeReport(history: history, context: context)
        let snapshot = report.runRecapShareArtifactCommands

        XCTAssertEqual(snapshot.sourceActionMenuIdentifier, fixture.menu.identifier)
        XCTAssertEqual(snapshot.commandPlanIdentifier, commandPlan.identifier)
        XCTAssertEqual(snapshot.sourceHistoryIdentifier, history.identifier)
        XCTAssertEqual(snapshot.sourcePreviewIdentifier, fixture.preview.identifier)
        XCTAssertEqual(snapshot.sourceRollupIdentifier, fixture.rollup.identifier)
        XCTAssertEqual(snapshot.sourceComparisonIdentifier, fixture.comparison.identifier)
        XCTAssertEqual(snapshot.sourcePinsIdentifier, fixture.pins.identifier)
        XCTAssertEqual(snapshot.sourceTourIdentifier, fixture.tour.identifier)
        XCTAssertEqual(snapshot.sourceSelectedExportIdentifier, fixture.selectedExport.identifier)
        XCTAssertEqual(snapshot.sourceFilteredExportIdentifier, fixture.filteredExport.identifier)
        XCTAssertEqual(snapshot.actionCount, fixture.menu.actionCount)
        XCTAssertEqual(snapshot.commandCount, commandPlan.commandCount)
        XCTAssertEqual(snapshot.enabledCommandCount, commandPlan.commands.filter(\.isEnabled).count)
        XCTAssertEqual(snapshot.disabledCommandCount, commandPlan.commands.filter { !$0.isEnabled }.count)
        XCTAssertEqual(snapshot.sectionCount, CinematicRunRecapShareArtifactActionMenuPlan.Section.allCases.count)
        XCTAssertEqual(snapshot.shortcutIdentifiers, commandPlan.commands.map(\.shortcut.identifier))
        XCTAssertEqual(snapshot.omittedActionKindIdentifiers, ["cleanupOldArtifacts"])
        XCTAssertEqual(snapshot.appLevelShortcutCollisionStateIdentifier, "clear")
        XCTAssertEqual(snapshot.appLevelShortcutIdentifiers, ["command:o", "command:r", "command:return"])
        XCTAssertEqual(snapshot.appLevelShortcutCollisionIdentifiers, [])
        XCTAssertTrue(snapshot.identifier.hasPrefix("run-recap-share-artifact-command-diagnostics"))
        XCTAssertTrue(report.identifier.contains("run-recap-share-artifact-commands:\(snapshot.identifier)"))
        XCTAssertTrue(report.identifier.contains("run-recap-share-artifact-command-plan:\(commandPlan.identifier)"))
        XCTAssertTrue(report.identifier.contains("run-recap-share-artifact-command-source-menu:\(fixture.menu.identifier)"))

        let sectionCounts = Dictionary(uniqueKeysWithValues: snapshot.sections.map {
            ($0.sectionIdentifier, $0.commandCount)
        })
        XCTAssertEqual(sectionCounts["navigate"], 3)
        XCTAssertEqual(sectionCounts["exports"], 7)
        XCTAssertEqual(sectionCounts["organize"], 2)
        XCTAssertEqual(sectionCounts["tour"], 3)
        XCTAssertEqual(sectionCounts["maintain"], 0)
    }

    func testReportRowAndExportExposeCommandSummaryBoundsAndCorrelation() throws {
        let workspace = try makeInitializedWorkspace()
        for session in 1...3 {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-command-export-\(session).md",
                contents: artifactMarkdown(
                    session: session,
                    title: "Command Export \(session)",
                    status: "succeeded",
                    commit: "Command export commit \(session)",
                    body: "command export body \(session)"
                )
            )
        }
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let selected = try XCTUnwrap(history.entries.first { $0.sessionNumber == 2 })
        let context = CinematicRunRecapShareArtifactLibraryContext(selectedEntryIdentifier: selected.identifier)
        let report = makeReport(history: history, context: context)
        let summary = CinematicDiagnosticsSummary(
            report: report,
            visualSmoke: CinematicVisualSmokeReport(reports: [report])
        )
        let row = try XCTUnwrap(summary.rows.first { $0.id == "run-recap-share-artifact-commands" })

        XCTAssertEqual(row.label, "Recap artifact commands")
        XCTAssertLessThanOrEqual(row.detail.count, CinematicDiagnosticsSummary.detailMaxCharacters)
        XCTAssertTrue(row.detail.contains("cmd 15/16"))
        XCTAssertTrue(row.detail.contains("source-menu"))
        XCTAssertTrue(row.detail.contains(String(report.runRecapShareArtifactCommands.sourceActionMenuIdentifier.prefix(18))))
        XCTAssertTrue(row.detail.contains("command-plan"))
        XCTAssertTrue(row.detail.contains("omitted cleanupOldArtifacts"))
        XCTAssertTrue(row.detail.contains("shortcuts command:["))
        XCTAssertTrue(row.detail.contains("app-collisions clear command:o,command:r,command:return"))
        XCTAssertTrue(summary.exportText.contains("Recap artifact commands:"))
        XCTAssertTrue(summary.exportText.contains(row.detail))
        XCTAssertTrue(summary.exportText.contains("Repository/context (17 rows)"))
    }

    func testUnavailableAndNoMatchDisabledStatesAreInspectable() throws {
        let unavailableReport = makeReport(
            history: .unavailable(reason: "diagnostic-unavailable"),
            context: .empty
        )
        let unavailableSummary = CinematicDiagnosticsSummary(
            report: unavailableReport,
            visualSmoke: CinematicVisualSmokeReport(reports: [unavailableReport])
        )
        let unavailableRow = try XCTUnwrap(
            unavailableSummary.rows.first { $0.id == "run-recap-share-artifact-commands" }
        )

        XCTAssertEqual(unavailableReport.runRecapShareArtifactCommands.historyAvailabilityReason, "diagnostic-unavailable")
        XCTAssertTrue(unavailableReport.runRecapShareArtifactCommands.disabledActionKindIdentifiers.contains("copyLibraryExport"))
        XCTAssertTrue(unavailableReport.runRecapShareArtifactCommands.disabledActionKindIdentifiers.contains("copySelectedExport"))
        XCTAssertTrue(unavailableRow.detail.contains("history diagnostic-unavailable"))
        XCTAssertTrue(unavailableSummary.exportText.contains("history diagnostic-unavailable"))

        let workspace = try makeInitializedWorkspace()
        for session in 1...2 {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-command-no-match-\(session).md",
                contents: artifactMarkdown(
                    session: session,
                    title: "No Match Diagnostics \(session)",
                    status: "succeeded",
                    commit: "No match diagnostics commit \(session)",
                    body: "ordinary command diagnostics body"
                )
            )
        }
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let context = CinematicRunRecapShareArtifactLibraryContext(
            searchText: "missing command diagnostics beacon"
        )
        let report = makeReport(history: history, context: context)
        let summary = CinematicDiagnosticsSummary(
            report: report,
            visualSmoke: CinematicVisualSmokeReport(reports: [report])
        )
        let row = try XCTUnwrap(summary.rows.first { $0.id == "run-recap-share-artifact-commands" })
        let snapshot = report.runRecapShareArtifactCommands

        XCTAssertEqual(snapshot.previewNoMatchAvailabilityReason, "no-matching-recap-share-artifacts")
        XCTAssertTrue(snapshot.disabledActionKindIdentifiers.contains("navigatePrevious"))
        XCTAssertTrue(snapshot.disabledActionKindIdentifiers.contains("revealSelected"))
        XCTAssertTrue(snapshot.disabledActionKindIdentifiers.contains("copySelectedExport"))
        XCTAssertTrue(snapshot.disabledActionKindIdentifiers.contains("copyFilteredExport"))
        XCTAssertTrue(snapshot.disabledActionKindIdentifiers.contains("copyRollupExport"))
        XCTAssertTrue(snapshot.disabledActionKindIdentifiers.contains("copyComparisonExport"))
        XCTAssertEqual(snapshot.selectedExportAvailabilityReason, "no-matching-recap-share-artifacts")
        XCTAssertEqual(snapshot.filteredExportAvailabilityReason, "no-matching-recap-share-artifacts")
        XCTAssertTrue(row.detail.contains("no-match no-matching-recap-share-artifacts"))
        XCTAssertTrue(row.detail.contains("disabled navigatePrevious"))
        XCTAssertTrue(summary.exportText.contains("no-match no-matching-recap-share-artifacts"))
    }

    func testStalePinFilteredHoldAndPromotedHoldDiagnosticsAreInspectable() throws {
        let workspace = try makeInitializedWorkspace()
        let artifactCount = CinematicRunRecapShareArtifactHistoryPlan.retentionLimit + 2
        for session in 1...artifactCount {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-command-state-\(session).md",
                contents: artifactMarkdown(
                    session: session,
                    title: "Command State \(session)",
                    status: "succeeded",
                    commit: "Command state commit \(session)",
                    body: session == artifactCount ? "active command diagnostics beacon" : "retained body"
                )
            )
        }
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let selected = try XCTUnwrap(history.entries.first { $0.sessionNumber == artifactCount })
        let held = try XCTUnwrap(history.entries.first { $0.sessionNumber == artifactCount - 2 })
        let context = CinematicRunRecapShareArtifactLibraryContext(
            selectedEntryIdentifier: selected.identifier,
            searchText: "ACTIVE COMMAND DIAGNOSTICS",
            pinnedEntryIdentifiers: [held.identifier, selected.identifier, "stale-command-diagnostic-pin"],
            comparisonTargetMode: .pinnedReference,
            savedTourHoldEntryIdentifier: held.identifier
        )
        let report = makeReport(history: history, context: context)
        let summary = CinematicDiagnosticsSummary(
            report: report,
            visualSmoke: CinematicVisualSmokeReport(reports: [report])
        )
        let row = try XCTUnwrap(summary.rows.first { $0.id == "run-recap-share-artifact-commands" })
        let snapshot = report.runRecapShareArtifactCommands

        XCTAssertEqual(snapshot.missingPinnedEntryCount, 1)
        XCTAssertEqual(snapshot.filteredPinnedEntryCount, 1)
        XCTAssertEqual(snapshot.tourSavedHoldStateIdentifier, "filtered-hold")
        XCTAssertEqual(snapshot.tourFilteredSavedHoldEntryIdentifier, held.identifier)
        XCTAssertEqual(snapshot.comparisonPromotedHoldStateIdentifier, "filtered-promoted-hold-target")
        XCTAssertTrue(snapshot.omittedActionKindIdentifiers.contains("cleanupOldArtifacts"))
        XCTAssertTrue(row.detail.contains("pins stale 1 filtered 1"))
        XCTAssertTrue(row.detail.contains("hold filtered-hold"))
        XCTAssertTrue(row.detail.contains("promoted filtered-promoted-hold-target"))
        XCTAssertTrue(summary.exportText.contains("pins stale 1 filtered 1"))
        XCTAssertTrue(summary.exportText.contains("promoted filtered-promoted-hold-target"))
    }

    func testRepresentativeCommandSmokeReportsKeepDiagnosticsCorrelated() throws {
        let reports = CinematicDiagnostics.representativeRunRecapArtifactCommandSmokeReports()

        XCTAssertEqual(reports.count, 8)
        for report in reports {
            let snapshot = report.runRecapShareArtifactCommands
            let sectionCommandCount = snapshot.sections.reduce(0) { $0 + $1.commandCount }

            XCTAssertEqual(snapshot.sourceHistoryIdentifier, report.runRecapShareArtifactHistory.identifier)
            XCTAssertEqual(snapshot.sourcePreviewIdentifier, report.runRecapShareArtifactPreview.identifier)
            XCTAssertEqual(snapshot.sourceRollupIdentifier, report.runRecapShareArtifactRollup.identifier)
            XCTAssertEqual(snapshot.sourceComparisonIdentifier, report.runRecapShareArtifactComparison.identifier)
            XCTAssertEqual(snapshot.sourcePinsIdentifier, report.runRecapShareArtifactPins.identifier)
            XCTAssertEqual(snapshot.sourceTourIdentifier, report.runRecapShareArtifactTour.identifier)
            XCTAssertEqual(
                snapshot.sourceSelectedExportIdentifier,
                report.runRecapShareArtifactPreview.selectedExport.identifier
            )
            XCTAssertEqual(
                snapshot.sourceFilteredExportIdentifier,
                report.runRecapShareArtifactPreview.filteredExport.identifier
            )
            XCTAssertEqual(snapshot.commandCount + snapshot.omittedActionKindIdentifiers.count, snapshot.actionCount)
            XCTAssertEqual(sectionCommandCount, snapshot.commandCount)
            XCTAssertEqual(snapshot.omittedActionKindIdentifiers, ["cleanupOldArtifacts"])
            XCTAssertEqual(snapshot.appLevelShortcutCollisionStateIdentifier, "clear")
            XCTAssertTrue(report.identifier.contains("run-recap-share-artifact-commands:\(snapshot.identifier)"))
            XCTAssertTrue(report.identifier.contains("run-recap-share-artifact-command-plan:"))
            XCTAssertTrue(report.identifier.contains("run-recap-share-artifact-command-source-menu:"))
        }
    }

    func testDiagnosticsPathKeepsActionMenuAndCommandPlannerCompatibleWithoutMutatingContext() throws {
        let workspace = try makeInitializedWorkspace()
        for session in 1...3 {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-command-immutable-\(session).md",
                contents: artifactMarkdown(
                    session: session,
                    title: "Immutable Diagnostics \(session)",
                    status: session == 2 ? "failed verify" : "succeeded",
                    commit: "Immutable diagnostics commit \(session)",
                    body: session == 3 ? "immutable diagnostics beacon" : "ordinary immutable body"
                )
            )
        }
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let selected = try XCTUnwrap(history.entries.first { $0.sessionNumber == 3 })
        let held = try XCTUnwrap(history.entries.first { $0.sessionNumber == 2 })
        let context = CinematicRunRecapShareArtifactLibraryContext(
            selectedEntryIdentifier: selected.identifier,
            searchText: "IMMUTABLE DIAGNOSTICS",
            pinnedEntryIdentifiers: [held.identifier, held.identifier, "missing-command-diagnostic-pin"],
            comparisonTargetMode: .pinnedReference,
            savedTourHoldEntryIdentifier: held.identifier
        )
        let contextBefore = context
        let fixture = makeFixture(history: history, context: context)
        let commandPlan = CinematicRunRecapShareArtifactCommandPlanner.plan(actionMenuPlan: fixture.menu)
        let report = makeReport(history: history, context: context)

        XCTAssertEqual(context, contextBefore)
        XCTAssertEqual(report.runRecapShareArtifactPreview.identifier, fixture.preview.identifier)
        XCTAssertEqual(report.runRecapShareArtifactRollup.identifier, fixture.rollup.identifier)
        XCTAssertEqual(report.runRecapShareArtifactComparison.identifier, fixture.comparison.identifier)
        XCTAssertEqual(report.runRecapShareArtifactPins.identifier, fixture.pins.identifier)
        XCTAssertEqual(report.runRecapShareArtifactTour.identifier, fixture.tour.identifier)
        XCTAssertEqual(report.runRecapShareArtifactCommands.sourceActionMenuIdentifier, fixture.menu.identifier)
        XCTAssertEqual(report.runRecapShareArtifactCommands.commandPlanIdentifier, commandPlan.identifier)
    }

    private struct Fixture {
        var preview: CinematicRunRecapShareArtifactPreviewBrowserPlan
        var rollup: CinematicRunRecapShareArtifactRollupPlan
        var comparison: CinematicRunRecapShareArtifactComparisonPlan
        var pins: CinematicRunRecapShareArtifactPinnedReferencePlan
        var tour: CinematicRunRecapShareArtifactTourPlan
        var selectedExport: CinematicRunRecapShareArtifactSubsetExportPlan
        var filteredExport: CinematicRunRecapShareArtifactSubsetExportPlan
        var menu: CinematicRunRecapShareArtifactActionMenuPlan
    }

    private func makeReport(
        history: CinematicRunRecapShareArtifactHistoryPlan,
        context: CinematicRunRecapShareArtifactLibraryContext
    ) -> CinematicDiagnosticsReport {
        CinematicDiagnostics.report(
            repoName: "Compass",
            phase: LoopPhase.succeeded.rawValue,
            immediateTitle: "Expose recap artifact command diagnostics",
            completedCount: 3,
            latestEvent: nil,
            languageProfile: languageProfile(primaryLanguage: .swift),
            activityProfile: activityProfile(recentCommitCount: 1, lastTerminalStatus: .succeeded),
            influenceSettings: CinematicInfluenceSettings(),
            runRecapShareArtifactHistoryPlan: history,
            runRecapShareArtifactPreviewSelectedEntryIdentifier: context.selectedEntryIdentifier,
            runRecapShareArtifactPreviewSearchQuery: context.searchText,
            runRecapShareArtifactComparisonTargetMode: context.comparisonTargetMode,
            runRecapShareArtifactPinnedEntryIdentifiers: context.pinnedEntryIdentifiers,
            runRecapShareArtifactSavedTourHoldEntryIdentifier: context.savedTourHoldEntryIdentifier
        )
    }

    private func makeFixture(
        history: CinematicRunRecapShareArtifactHistoryPlan,
        context: CinematicRunRecapShareArtifactLibraryContext
    ) -> Fixture {
        let preview = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: context.selectedEntryIdentifier,
            searchQuery: context.searchText
        )
        let rollup = CinematicRunRecapShareArtifactRollupPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: context.selectedEntryIdentifier,
            searchQuery: context.searchText
        )
        let comparison = CinematicRunRecapShareArtifactComparisonPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: context.selectedEntryIdentifier,
            searchQuery: context.searchText,
            targetMode: context.comparisonTargetMode,
            pinnedEntryIdentifiers: context.pinnedEntryIdentifiers,
            savedTourHoldEntryIdentifier: context.savedTourHoldEntryIdentifier
        )
        let pins = CinematicRunRecapShareArtifactPinnedReferencePlanner.plan(
            historyPlan: history,
            pinnedEntryIdentifiers: context.pinnedEntryIdentifiers,
            selectedEntryIdentifier: context.selectedEntryIdentifier,
            searchQuery: context.searchText
        )
        let tour = CinematicRunRecapShareArtifactTourPlanner.plan(
            historyPlan: history,
            libraryContext: context
        )
        let selectedExport = CinematicRunRecapShareArtifactSubsetExportPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: context.selectedEntryIdentifier,
            searchQuery: context.searchText,
            scope: .selected
        )
        let filteredExport = CinematicRunRecapShareArtifactSubsetExportPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: context.selectedEntryIdentifier,
            searchQuery: context.searchText,
            scope: .filtered
        )
        let menu = CinematicRunRecapShareArtifactActionMenuPlanner.plan(
            previewPlan: preview,
            rollupPlan: rollup,
            comparisonPlan: comparison,
            pinnedReferencePlan: pins,
            tourPlan: tour,
            selectedExportPlan: selectedExport,
            filteredExportPlan: filteredExport,
            historyPlan: history
        )

        return Fixture(
            preview: preview,
            rollup: rollup,
            comparison: comparison,
            pins: pins,
            tour: tour,
            selectedExport: selectedExport,
            filteredExport: filteredExport,
            menu: menu
        )
    }

    private func artifactMarkdown(
        session: Int,
        title: String,
        status: String,
        commit: String,
        body: String
    ) -> String {
        """
        # Compass Run Recap Share

        - Artifact: artifact-\(session)
        - Availability: available
        - Session: \(session)
        - Filename: recap-share-command-diagnostics-\(session).md
        - Share: share-id
        - Recap: recap-id
        - Focus: focus-id
        - End card: end-card-id
        - Title: \(title)
        - Status: \(status)
        - Detail: Command diagnostics detail
        - Commit: \(commit)

        ## Events
        - event

        ## Share Text

        ```text
        \(body)
        ```
        """
    }

    private func makeInitializedWorkspace() throws -> CompassWorkspace {
        let repoURL = try makeTemporaryGitRepository()
        let workspace = CompassWorkspace(repoURL: repoURL)
        try workspace.initialize()
        return workspace
    }

    private func makeTemporaryGitRepository() throws -> URL {
        let directory = try makeTemporaryDirectory()
        try FileManager.default.createDirectory(
            at: directory.appending(path: ".git", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        return directory
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "CinematicRunRecapShareArtifactCommandDiagnosticsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        temporaryDirectories.append(directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
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
