import Foundation
@testable import Compass
import XCTest

final class CinematicPlanCompassCommandDiagnosticsTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
    }

    func testSnapshotConstructionCorrelatesCommandPlanAndSelectedRoute() throws {
        let plan = CinematicPlanCompassPlan(state: populatedState)
        let commandPlan = CinematicPlanCompassCommandPlanner.plan(
            planCompassPlan: plan,
            selectedKind: .longTerm
        )
        let actionSurface = CinematicPlanCompassActionSurfacePlanner.descriptor(commandPlan: commandPlan)
        let focusPlan = CinematicPlanCompassSceneFocusPlanner.plan(
            isPlanOverlaySelected: true,
            planCompassPlan: plan,
            selectedKind: .longTerm
        )
        let report = makeReport(
            plan: plan,
            selectedKind: .longTerm,
            focusPlan: focusPlan
        )
        let snapshot = report.planCompassCommands

        XCTAssertEqual(snapshot.commandPlanIdentifier, commandPlan.identifier)
        XCTAssertEqual(snapshot.sourcePlanIdentifier, plan.identifier)
        XCTAssertEqual(snapshot.sourcePlanCopyIdentifier, plan.copyIdentifier)
        XCTAssertEqual(snapshot.sourcePlanExportIdentifier, plan.exportIdentifier)
        XCTAssertEqual(snapshot.selectedRouteIdentifier, "long-term")
        XCTAssertEqual(snapshot.selectedSectionID, plan.longTerm.id)
        XCTAssertEqual(snapshot.selectedSectionRowIdentifier, plan.longTerm.rowIdentifier)
        XCTAssertEqual(snapshot.selectedSectionContentIdentifier, plan.longTerm.contentIdentifier)
        XCTAssertEqual(snapshot.selectedSectionCopyIdentifier, plan.longTerm.copyIdentifier)
        XCTAssertEqual(snapshot.selectedSectionExportIdentifier, plan.longTerm.exportIdentifier)
        XCTAssertEqual(snapshot.selectedSectionStateIdentifier, "active")
        XCTAssertFalse(snapshot.selectedSectionIsEmpty)
        XCTAssertEqual(snapshot.commandCount, commandPlan.commandCount)
        XCTAssertEqual(snapshot.enabledCommandCount, commandPlan.enabledCommandCount)
        XCTAssertEqual(snapshot.disabledCommandCount, commandPlan.disabledCommandCount)
        XCTAssertEqual(snapshot.shortcutIdentifiers, commandPlan.commands.map(\.shortcut.identifier))
        XCTAssertEqual(snapshot.commandActionKindIdentifiers, commandPlan.commands.map(\.actionKind.rawValue))
        XCTAssertEqual(snapshot.copyCommandIdentifiers.count, 2)
        XCTAssertEqual(snapshot.actionSurfaceIdentifier, actionSurface.identifier)
        XCTAssertEqual(snapshot.actionSurfaceSourceCommandPlanIdentifier, commandPlan.identifier)
        XCTAssertEqual(snapshot.visibleActionCount, actionSurface.actionCount)
        XCTAssertEqual(snapshot.visibleEnabledActionCount, actionSurface.enabledActionCount)
        XCTAssertEqual(snapshot.visibleDisabledActionCount, actionSurface.disabledActionCount)
        XCTAssertEqual(snapshot.visibleActionIdentifiers, actionSurface.actions.map(\.identifier))
        XCTAssertEqual(snapshot.visibleActionKindIdentifiers, actionSurface.actions.map(\.sourceActionKind.rawValue))
        XCTAssertEqual(snapshot.visibleActionSourceCommandIdentifiers, actionSurface.actions.map(\.sourceCommandIdentifier))
        XCTAssertEqual(
            snapshot.visibleActionSelectedRouteStateIdentifiers,
            actionSurface.actions.map(\.selectedRouteStateIdentifier)
        )
        XCTAssertEqual(snapshot.selectedVisibleActionKindIdentifiers, ["focusLongTermRoute"])
        XCTAssertEqual(snapshot.appLevelShortcutCollisionStateIdentifier, "clear")
        XCTAssertEqual(snapshot.appLevelShortcutCollisionIdentifiers, [])
        XCTAssertEqual(snapshot.recapCommandShortcutCollisionStateIdentifier, "clear")
        XCTAssertEqual(snapshot.recapCommandShortcutCollisionIdentifiers, [])
        XCTAssertTrue(report.identifier.contains("plan-compass-commands:\(snapshot.identifier)"))
        XCTAssertTrue(report.identifier.contains("plan-compass-action-surface:\(snapshot.actionSurfaceIdentifier)"))
        XCTAssertTrue(report.identifier.contains("plan-compass-command-selected:long-term"))
        XCTAssertEqual(report.planCompassSceneFocus.selectedSectionRouteIdentifier, snapshot.selectedRouteIdentifier)
    }

    func testReportRowAndExportExposeCommandSummaryBoundsAndCorrelation() throws {
        let plan = CinematicPlanCompassPlan(state: populatedState)
        let report = makeReport(plan: plan, selectedKind: .midTerm)
        let summary = CinematicDiagnosticsSummary(
            report: report,
            visualSmoke: CinematicVisualSmokeReport(reports: [report])
        )
        let row = try XCTUnwrap(summary.rows.first { $0.id == "plan-compass-commands" })

        XCTAssertEqual(row.label, "Plan compass commands")
        XCTAssertLessThanOrEqual(row.detail.count, CinematicDiagnosticsSummary.detailMaxCharacters)
        XCTAssertTrue(row.detail.contains("selected mid-term"))
        XCTAssertTrue(row.detail.contains("plan-copy"))
        XCTAssertTrue(row.detail.contains("section-export"))
        XCTAssertTrue(row.detail.contains("app-collisions clear"))
        XCTAssertTrue(row.detail.contains("recap-collisions clear"))
        XCTAssertTrue(row.detail.contains("copy-cmds 2"))
        XCTAssertTrue(row.detail.contains("actions 6 e6 d0"))
        XCTAssertTrue(row.detail.contains("action-surface"))
        XCTAssertTrue(row.detail.contains("action-correlated yes"))
        XCTAssertTrue(summary.exportText.contains("Plan compass commands"))
        XCTAssertTrue(summary.exportText.contains("plan-compass-commands"))
        XCTAssertTrue(summary.exportText.contains("action-correlated yes"))
        XCTAssertTrue(summary.exportText.contains("recap-collisions clear"))
        XCTAssertTrue(summary.exportText.contains("section-copy"))
    }

    func testReportRowAndExportExposeReadinessSummaryBoundsAndCorrelation() throws {
        let plan = CinematicPlanCompassPlan(state: populatedState)
        let readiness = CinematicPlanCompassReadinessPlan(
            state: populatedState,
            planCompassPlan: plan,
            reliabilityFeedback: PlanReliabilityFeedback(state: populatedState, sessions: [])
        )
        let focusPlan = CinematicPlanCompassSceneFocusPlanner.plan(
            isPlanOverlaySelected: true,
            planCompassPlan: plan,
            readinessPlan: readiness,
            selectedKind: .immediate
        )
        let report = makeReport(plan: plan, selectedKind: .immediate, focusPlan: focusPlan)
        let summary = CinematicDiagnosticsSummary(
            report: report,
            visualSmoke: CinematicVisualSmokeReport(reports: [report])
        )
        let row = try XCTUnwrap(summary.rows.first { $0.id == "plan-compass-readiness" })

        XCTAssertEqual(report.planCompassReadiness.identifier, readiness.identifier)
        XCTAssertEqual(report.planCompassReadiness.sourceImmediateContentIdentifier, plan.immediate.contentIdentifier)
        XCTAssertEqual(report.planCompassReadiness.immediateContentIdentifier, plan.immediate.contentIdentifier)
        XCTAssertEqual(report.planCompassReadiness.statusIdentifier, "ready")
        XCTAssertEqual(report.planCompassReadiness.metadataDriftStateIdentifier, "clear")
        XCTAssertEqual(report.planCompassSceneFocus.readinessIdentifier, readiness.identifier)
        XCTAssertEqual(report.planCompassSceneFocus.readinessStatusIdentifier, "ready")
        XCTAssertEqual(report.planCompassSceneFocus.readinessVerifyCommand, readiness.verifyCommand)
        XCTAssertTrue(report.planCompassVerifySeal.isVisible)
        XCTAssertEqual(report.planCompassVerifySeal.rowIdentifier, "plan-compass-verify-seal")
        XCTAssertEqual(report.planCompassVerifySeal.readinessIdentifier, readiness.identifier)
        XCTAssertEqual(report.planCompassVerifySeal.focusDescriptorIdentifier, focusPlan.descriptor?.identifier)
        XCTAssertEqual(report.planCompassVerifySeal.statusIdentifier, "ready")
        XCTAssertEqual(row.label, "Plan readiness")
        XCTAssertLessThanOrEqual(row.detail.count, CinematicDiagnosticsSummary.detailMaxCharacters)
        XCTAssertTrue(row.detail.contains("status ready"))
        XCTAssertTrue(row.detail.contains("drift clear"))
        XCTAssertTrue(row.detail.contains("command swift test"))
        XCTAssertTrue(summary.exportText.contains("Plan readiness"))
        XCTAssertTrue(summary.exportText.contains("plan-compass-readiness"))
        XCTAssertTrue(summary.exportText.contains("status ready"))
        XCTAssertTrue(summary.exportText.contains("drift clear"))
    }

    func testRepresentativeCommandSmokeReportsKeepDiagnosticsCorrelated() throws {
        let reports = CinematicDiagnostics.representativePlanCompassCommandSmokeReports()

        XCTAssertEqual(reports.count, 4)
        XCTAssertEqual(Set(reports.map(\.planCompassCommands.selectedRouteIdentifier)), Set([
            "immediate",
            "mid-term",
            "long-term"
        ]))
        XCTAssertTrue(reports.contains { $0.planCompassCommands.selectedSectionStateIdentifier == "empty" })

        for report in reports {
            let snapshot = report.planCompassCommands
            let sectionCommandCount = snapshot.sections.reduce(0) { $0 + $1.commandCount }

            XCTAssertEqual(snapshot.commandCount, CinematicPlanCompassCommandPlan.commandLimit)
            XCTAssertEqual(sectionCommandCount, snapshot.commandCount)
            XCTAssertEqual(snapshot.sourcePlanIdentifier, report.planCompass?.identifier)
            XCTAssertEqual(snapshot.sourcePlanCopyIdentifier, report.planCompass?.copyIdentifier)
            XCTAssertEqual(snapshot.sourcePlanExportIdentifier, report.planCompass?.exportIdentifier)
            XCTAssertEqual(snapshot.actionSurfaceSourceCommandPlanIdentifier, snapshot.commandPlanIdentifier)
            XCTAssertEqual(snapshot.visibleActionCount, snapshot.commandCount)
            XCTAssertEqual(snapshot.visibleEnabledActionCount, snapshot.enabledCommandCount)
            XCTAssertEqual(snapshot.visibleDisabledActionCount, snapshot.disabledCommandCount)
            XCTAssertEqual(snapshot.visibleActionKindIdentifiers, snapshot.commandActionKindIdentifiers)
            XCTAssertEqual(snapshot.visibleActionSourceCommandIdentifiers.count, snapshot.commandCount)
            XCTAssertEqual(snapshot.selectedVisibleActionKindIdentifiers.count, 1)
            XCTAssertEqual(snapshot.appLevelShortcutCollisionStateIdentifier, "clear")
            XCTAssertEqual(snapshot.recapCommandShortcutCollisionStateIdentifier, "clear")
            XCTAssertTrue(report.identifier.contains("plan-compass-command-plan:"))
            XCTAssertTrue(report.identifier.contains("plan-compass-action-surface:"))
            XCTAssertTrue(report.identifier.contains("plan-compass-command-recap-collisions:clear"))
        }
    }

    func testVisualSmokeWarnsForPlanCompassCommandCollisionDetails() throws {
        var reports = CinematicDiagnostics.representativePlanCompassCommandSmokeReports()
        reports[0].planCompassCommands.recapCommandShortcutCollisionStateIdentifier = "collision"
        reports[0].planCompassCommands.recapCommandShortcutCollisionIdentifiers = [
            reports[0].planCompassCommands.shortcutIdentifiers[0]
        ]

        let smoke = CinematicVisualSmokeReport(reports: reports)
        let check = try XCTUnwrap(smoke.checks.first { $0.id == "plan-compass-command-availability" })

        XCTAssertEqual(check.status, .warning)
        XCTAssertEqual(check.warningIdentifier, "visual-smoke.plan-compass-commands")
        XCTAssertEqual(
            check.warningTarget?.targetAnchorID,
            "visual-smoke-check-plan-compass-command-availability"
        )
        XCTAssertEqual(check.warningTarget?.relatedRowID, "plan-compass-commands")
        XCTAssertTrue(check.detail.contains("recap-collisions"))
        XCTAssertTrue(smoke.warningIdentifiers.contains("visual-smoke.plan-compass-commands"))
    }

    func testVisualSmokeWarnsForPlanCompassActionSurfaceDriftDetails() throws {
        var reports = CinematicDiagnostics.representativePlanCompassCommandSmokeReports()
        reports[0].planCompassCommands.visibleActionKindIdentifiers.removeLast()
        reports[0].planCompassCommands.visibleActionCount -= 1

        let smoke = CinematicVisualSmokeReport(reports: reports)
        let check = try XCTUnwrap(smoke.checks.first { $0.id == "plan-compass-command-availability" })

        XCTAssertEqual(check.status, .warning)
        XCTAssertEqual(check.warningIdentifier, "visual-smoke.plan-compass-commands")
        XCTAssertTrue(check.detail.contains("action-surface"))
        XCTAssertTrue(check.detail.contains("drift"))
        XCTAssertEqual(
            check.warningTarget?.targetAnchorID,
            "visual-smoke-check-plan-compass-command-availability"
        )
        XCTAssertEqual(check.warningTarget?.relatedRowID, "plan-compass-commands")
    }

    func testVisualSmokeWarnsForPlanCompassReadinessDriftDetails() throws {
        var reports = CinematicDiagnostics.representativePlanCompassReadinessSmokeReports()
        reports[0].planCompassReadiness.verifyCommand = "swift test --filter DriftedReadiness"

        let smoke = CinematicVisualSmokeReport(reports: reports)
        let check = try XCTUnwrap(smoke.checks.first { $0.id == "plan-compass-readiness" })

        XCTAssertEqual(check.status, .warning)
        XCTAssertEqual(check.warningIdentifier, "visual-smoke.plan-compass-readiness")
        XCTAssertEqual(
            check.warningTarget?.targetAnchorID,
            "visual-smoke-check-plan-compass-readiness"
        )
        XCTAssertEqual(check.warningTarget?.relatedRowID, "plan-compass-readiness")
        XCTAssertTrue(check.detail.contains("drift"))
        XCTAssertTrue(smoke.warningIdentifiers.contains("visual-smoke.plan-compass-readiness"))
    }

    func testWarningTargetUsesPlanCompassReadinessAttentionDetailAndCopyText() throws {
        var reports = CinematicDiagnostics.representativePlanCompassReadinessSmokeReports()
        reports[0].planCompassReadiness.verifyTimeoutLabel = "Timeout 99m"
        reports[0].planCompassReadiness.metadataDriftStateIdentifier = "drift"

        let report = reports[0]
        let smoke = CinematicVisualSmokeReport(reports: reports)
        let summary = CinematicDiagnosticsSummary(report: report, visualSmoke: smoke)
        let check = try XCTUnwrap(summary.visualSmoke.checks.first { $0.id == "plan-compass-readiness" })
        let warningTarget = try XCTUnwrap(check.warningTarget)
        let target = try XCTUnwrap(
            summary.attentionSummary.targets.first { $0.id == warningTarget.id }
        )

        XCTAssertEqual(warningTarget.id, "visual-smoke-check-plan-compass-readiness")
        XCTAssertEqual(warningTarget.targetGroupID, "visual-smoke")
        XCTAssertEqual(warningTarget.relatedGroupID, "repository-context")
        XCTAssertEqual(warningTarget.relatedRowID, "plan-compass-readiness")
        XCTAssertEqual(target.label, "Plan readiness")
        XCTAssertEqual(target.targetAnchorID, "visual-smoke-check-plan-compass-readiness")
        XCTAssertEqual(target.relatedRowID, "plan-compass-readiness")
        XCTAssertEqual(target.visibleWarningIdentifiers, ["visual-smoke.plan-compass-readiness"])
        XCTAssertTrue(target.detail.contains("status ready"))
        XCTAssertTrue(target.detail.contains("drift drift"))
        XCTAssertTrue(target.detail.contains("timeout available drift"))
        XCTAssertLessThanOrEqual(
            target.detail.count,
            CinematicDiagnosticsSummary.attentionSummaryDetailMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            target.copyText.count,
            CinematicDiagnosticsSummary.attentionTargetCopyMaxCharacters
        )
        XCTAssertTrue(target.copyText.contains("Label: Plan readiness"))
        XCTAssertTrue(target.copyText.contains("Target anchor: visual-smoke-check-plan-compass-readiness"))
        XCTAssertTrue(target.copyText.contains("Warnings: visual-smoke.plan-compass-readiness"))
        XCTAssertTrue(target.copyText.contains("Related row: plan-compass-readiness"))
        XCTAssertTrue(target.copyText.contains("Plan readiness"))
        XCTAssertTrue(summary.exportText.contains("Plan readiness -> visual-smoke-check-plan-compass-readiness"))
        XCTAssertTrue(summary.exportText.contains("related plan-compass-readiness"))
        XCTAssertTrue(summary.exportText.contains("timeout available drift"))
    }

    func testWarningTargetUsesPlanCompassCommandAttentionDetailAndCopyText() throws {
        var reports = CinematicDiagnostics.representativePlanCompassCommandSmokeReports()
        reports[0].planCompassCommands.appLevelShortcutCollisionStateIdentifier = "collision"
        reports[0].planCompassCommands.appLevelShortcutCollisionIdentifiers = [
            reports[0].planCompassCommands.shortcutIdentifiers[0]
        ]

        let report = reports[0]
        let snapshot = report.planCompassCommands
        let smoke = CinematicVisualSmokeReport(reports: reports)
        let summary = CinematicDiagnosticsSummary(report: report, visualSmoke: smoke)
        let check = try XCTUnwrap(
            summary.visualSmoke.checks.first { $0.id == "plan-compass-command-availability" }
        )
        let warningTarget = try XCTUnwrap(check.warningTarget)
        let target = try XCTUnwrap(
            summary.attentionSummary.targets.first { $0.id == warningTarget.id }
        )

        XCTAssertEqual(warningTarget.id, "visual-smoke-check-plan-compass-command-availability")
        XCTAssertEqual(warningTarget.targetGroupID, "visual-smoke")
        XCTAssertEqual(warningTarget.targetAnchorID, "visual-smoke-check-plan-compass-command-availability")
        XCTAssertEqual(warningTarget.relatedGroupID, "repository-context")
        XCTAssertEqual(warningTarget.relatedRowID, "plan-compass-commands")
        XCTAssertEqual(target.label, "Plan command availability")
        XCTAssertEqual(target.targetGroupID, "visual-smoke")
        XCTAssertEqual(target.targetAnchorID, warningTarget.targetAnchorID)
        XCTAssertEqual(target.relatedGroupID, "repository-context")
        XCTAssertEqual(target.relatedRowID, "plan-compass-commands")
        XCTAssertEqual(target.visibleWarningIdentifiers, ["visual-smoke.plan-compass-commands"])
        XCTAssertTrue(
            target.detail.contains(
                "selected \(snapshot.selectedRouteIdentifier) \(snapshot.selectedSectionStateIdentifier)"
            )
        )
        XCTAssertTrue(target.detail.contains("sections"))
        XCTAssertTrue(target.detail.contains("shortcuts"))
        XCTAssertTrue(target.detail.contains("app-collisions collision"))
        XCTAssertTrue(target.detail.contains("recap-collisions clear"))
        XCTAssertTrue(target.detail.contains("copy-cmds 2"))
        XCTAssertTrue(target.detail.contains("actions"))
        XCTAssertTrue(target.detail.contains("action-surface correlated"))
        XCTAssertTrue(target.detail.contains("correlated yes"))
        XCTAssertTrue(target.detail.contains("selected-row \(snapshot.selectedSectionRowIdentifier)"))
        XCTAssertLessThanOrEqual(
            target.detail.count,
            CinematicDiagnosticsSummary.attentionSummaryDetailMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            target.copyText.count,
            CinematicDiagnosticsSummary.attentionTargetCopyMaxCharacters
        )
        XCTAssertTrue(target.copyText.contains("Cinematic diagnostics warning target"))
        XCTAssertTrue(target.copyText.contains("Label: Plan command availability"))
        XCTAssertTrue(
            target.copyText.contains(
                "Target anchor: visual-smoke-check-plan-compass-command-availability"
            )
        )
        XCTAssertTrue(target.copyText.contains("Target group: visual-smoke"))
        XCTAssertTrue(target.copyText.contains("Warnings: visual-smoke.plan-compass-commands"))
        XCTAssertTrue(target.copyText.contains("Detail:"))
        XCTAssertTrue(target.copyText.contains("selected \(snapshot.selectedRouteIdentifier)"))
        XCTAssertTrue(target.copyText.contains("app-collisions collision"))
        XCTAssertTrue(target.copyText.contains("copy-cmds 2"))
        XCTAssertTrue(target.copyText.contains("action-surface correlated"))
        XCTAssertTrue(target.copyText.contains("correlated yes"))
        XCTAssertTrue(target.copyText.contains("Related row: plan-compass-commands"))
        XCTAssertTrue(target.copyText.contains("Related detail:"))
        XCTAssertTrue(target.copyText.contains("Plan compass commands"))
        XCTAssertFalse(target.copyText.contains("Cinematic Diagnostics\nReport:"))
        XCTAssertFalse(target.copyText.contains("Repository/context ("))
        XCTAssertEqual(summary.relatedRow(for: warningTarget)?.id, "plan-compass-commands")
        XCTAssertTrue(
            summary.exportText.contains(
                "Plan command availability -> visual-smoke-check-plan-compass-command-availability"
            )
        )
        XCTAssertTrue(summary.exportText.contains("related plan-compass-commands"))
        XCTAssertTrue(summary.exportText.contains("app-collisions collision"))
        XCTAssertTrue(summary.exportText.contains("copy-cmds 2"))
        XCTAssertTrue(summary.exportText.contains("action-surface correlated"))
        XCTAssertTrue(summary.exportText.contains("correlated yes"))

        var warningHistory = CinematicDiagnosticsWarningBundleHistory()
        warningHistory.record(summary.attentionSummary)
        let warningRollup = warningHistory.rollup
        XCTAssertTrue(warningRollup.copyText.contains(target.targetAnchorID))
        XCTAssertTrue(warningRollup.copyText.contains("diagnostics-row-plan-compass-commands"))
        XCTAssertFalse(warningRollup.copyText.contains(target.detail))
        XCTAssertTrue(warningRollup.rows.allSatisfy { row in
            row.copyText.contains("Warning bundle history row")
        })
    }

    func testCurrentReportPlanCompassCommandsDoNotMutateProjectStateOrStorage() async throws {
        let repoURL = try makeTemporaryDirectory(prefix: "PlanCompassCommandDiagnosticsProject")

        await MainActor.run {
            let project = CompassProject(repoURL: repoURL)
            project.state = populatedState
            project.sessions = [SessionRecord.started(1)]
            project.cinematicRunRecapShareArtifactLibraryContext = CinematicRunRecapShareArtifactLibraryContext(
                selectedEntryIdentifier: "recap-selection",
                searchText: "recap search",
                pinnedEntryIdentifiers: ["pinned-recap"],
                comparisonTargetMode: .pinnedReference,
                savedTourHoldEntryIdentifier: "held-recap"
            )
            project.cinematicRunRecapShareArtifactHistory = .unavailable(reason: "diagnostic-read-only")

            let stateBefore = project.state
            let sessionsBefore = project.sessions
            let activeStorageBefore = project.activeStorage
            let contextBefore = project.cinematicRunRecapShareArtifactLibraryContext
            let historyBefore = project.cinematicRunRecapShareArtifactHistory
            let warningHistoryBefore = project.cinematicDiagnosticsWarningBundleHistory
            let focusPlan = CinematicPlanCompassSceneFocusPlanner.plan(
                isPlanOverlaySelected: true,
                planCompassPlan: CinematicPlanCompassPlan(state: project.state),
                selectedKind: .midTerm
            )

            let report = CinematicDiagnostics.currentReport(
                for: project,
                planCompassCommandSelectedKind: .midTerm,
                planCompassSceneFocusPlan: focusPlan
            )

            XCTAssertEqual(report.planCompassCommands.selectedRouteIdentifier, "mid-term")
            XCTAssertEqual(report.planCompassReadiness.rowIdentifier, "plan-compass-readiness")
            XCTAssertEqual(report.planCompassReadiness.statusIdentifier, "ready")
            XCTAssertFalse(report.planCompassVerifySeal.isVisible)
            XCTAssertEqual(project.state, stateBefore)
            XCTAssertEqual(project.sessions, sessionsBefore)
            XCTAssertEqual(project.activeStorage, activeStorageBefore)
            XCTAssertEqual(project.cinematicRunRecapShareArtifactLibraryContext, contextBefore)
            XCTAssertEqual(project.cinematicRunRecapShareArtifactHistory, historyBefore)
            XCTAssertEqual(project.cinematicDiagnosticsWarningBundleHistory, warningHistoryBefore)
        }
    }

    private var populatedState: PlanState {
        PlanState(
            completed: ["Mapped diagnostics", "Rendered plan overlay"],
            immediate: PlanNext(
                plan: "Expose Plan Compass command diagnostics",
                verify: "swift test --filter CinematicPlanCompassCommandDiagnosticsTests",
                verifyTimeoutMs: 90_000,
                estimatedDifficulty: .high
            ),
            midTerm: "Queue selected route diagnostics",
            longTerm: "Make keyboard command coverage visible in smoke reports"
        )
    }

    private func makeReport(
        plan: CinematicPlanCompassPlan,
        selectedKind: PlanWorkflowOverview.Kind,
        focusPlan: CinematicPlanCompassSceneFocusPlan = .none
    ) -> CinematicDiagnosticsReport {
        CinematicDiagnostics.report(
            repoName: "Compass",
            phase: LoopPhase.planning.rawValue,
            immediateTitle: "Expose Plan Compass command diagnostics",
            completedCount: 2,
            planCompassPlan: plan,
            latestEvent: nil,
            languageProfile: .empty,
            activityProfile: .empty,
            influenceSettings: CinematicInfluenceSettings(),
            hasExplicitUserFocus: focusPlan.isActive,
            planCompassCommandSelectedKind: selectedKind,
            planCompassSceneFocusPlan: focusPlan
        )
    }

    private func makeTemporaryDirectory(prefix: String) throws -> URL {
        let url = URL(
            fileURLWithPath: "/tmp/\(prefix)-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryDirectories.append(url)
        return url
    }
}
