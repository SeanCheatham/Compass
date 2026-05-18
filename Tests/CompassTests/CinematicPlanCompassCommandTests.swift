import Foundation
@testable import Compass
import XCTest

final class CinematicPlanCompassCommandTests: XCTestCase {
    func testCommandOrderingDescriptorsAndShortcutCollisionAvoidance() throws {
        let plan = CinematicPlanCompassPlan(state: populatedState)
        let commandPlan = CinematicPlanCompassCommandPlanner.plan(
            planCompassPlan: plan,
            selectedKind: .midTerm
        )

        XCTAssertEqual(commandPlan.commandCount, CinematicPlanCompassCommandPlan.commandLimit)
        XCTAssertEqual(commandPlan.enabledCommandCount, commandPlan.commandCount)
        XCTAssertEqual(commandPlan.disabledCommandCount, 0)
        XCTAssertEqual(commandPlan.selectedRouteIdentifier, "mid-term")
        XCTAssertEqual(commandPlan.selectedSectionID, plan.midTerm.id)
        XCTAssertEqual(commandPlan.selectedSectionRowIdentifier, plan.midTerm.rowIdentifier)
        XCTAssertEqual(commandPlan.selectedSectionCopyIdentifier, plan.midTerm.copyIdentifier)
        XCTAssertEqual(commandPlan.selectedSectionExportIdentifier, plan.midTerm.exportIdentifier)
        XCTAssertEqual(commandPlan.selectedSectionStateIdentifier, "active")
        XCTAssertFalse(commandPlan.selectedSectionIsEmpty)
        XCTAssertEqual(commandPlan.sourcePlanIdentifier, plan.identifier)
        XCTAssertEqual(commandPlan.sourcePlanCopyIdentifier, plan.copyIdentifier)
        XCTAssertEqual(commandPlan.sourcePlanExportIdentifier, plan.exportIdentifier)
        XCTAssertTrue(commandPlan.identifier.hasPrefix("plan-compass-commands"))

        XCTAssertEqual(
            commandPlan.commands.map(\.actionKind),
            [
                .showPlanOverlay,
                .focusImmediateRoute,
                .focusMidTermRoute,
                .focusLongTermRoute,
                .copyFullPlanCompass,
                .copySelectedRoute
            ]
        )
        XCTAssertEqual(commandPlan.commands.prefix(1).map(\.section), [.overlay])
        XCTAssertEqual(commandPlan.commands.dropFirst(1).prefix(3).map(\.section), [.focus, .focus, .focus])
        XCTAssertEqual(commandPlan.commands.suffix(2).map(\.section), [.copy, .copy])
        XCTAssertEqual(
            commandPlan.commands.map(\.label),
            [
                "Show Plan Compass",
                "Focus Immediate",
                "Focus Mid-Term",
                "Focus Long-Term",
                "Copy Plan Compass",
                "Copy Selected Route"
            ]
        )
        XCTAssertEqual(
            commandPlan.commands.map(\.shortcut.identifier),
            [
                "command+control:p",
                "command+control:1",
                "command+control:2",
                "command+control:3",
                "command+control:c",
                "command+control+shift:c"
            ]
        )
        XCTAssertEqual(Set(commandPlan.commands.map(\.identifier)).count, commandPlan.commandCount)
        XCTAssertEqual(Set(commandPlan.commands.map(\.shortcut)).count, commandPlan.commandCount)
        XCTAssertEqual(commandPlan.appLevelShortcutCollisionStateIdentifier, "clear")
        XCTAssertEqual(commandPlan.appLevelShortcutCollisionIdentifiers, [])
        XCTAssertEqual(commandPlan.appLevelShortcutIdentifiers, ["command:o", "command:r", "command:return"])
        XCTAssertEqual(commandPlan.recapCommandShortcutCollisionStateIdentifier, "clear")
        XCTAssertEqual(commandPlan.recapCommandShortcutCollisionIdentifiers, [])
        XCTAssertEqual(commandPlan.recapCommandShortcutIdentifiers.count, CinematicRunRecapShareArtifactCommandPlan.commandLimit)

        for command in commandPlan.commands {
            XCTAssertFalse(command.identifier.isEmpty)
            XCTAssertFalse(command.label.isEmpty)
            XCTAssertFalse(command.help.isEmpty)
            XCTAssertLessThanOrEqual(command.identifier.count, CinematicPlanCompassCommandPlan.identifierMaxCharacters)
            XCTAssertLessThanOrEqual(command.label.count, CinematicPlanCompassCommandPlan.labelMaxCharacters)
            XCTAssertLessThanOrEqual(command.help.count, CinematicPlanCompassCommandPlan.helpMaxCharacters)
            XCTAssertLessThanOrEqual(
                command.shortcut.displayText.count,
                CinematicPlanCompassCommandPlan.shortcutHintMaxCharacters
            )
            XCTAssertEqual(
                CinematicPlanCompassCommandPlanner.shortcutHint(for: command.actionKind),
                command.shortcut.displayText
            )
        }
    }

    func testFocusedCommandDispatchCarriesPlanAndPerformsAvailableActions() throws {
        let plan = CinematicPlanCompassPlan(state: populatedState)
        let commandPlan = CinematicPlanCompassCommandPlanner.plan(
            planCompassPlan: plan,
            selectedKind: .immediate
        )
        let actionSurface = CinematicPlanCompassActionSurfacePlanner.descriptor(commandPlan: commandPlan)
        var performed: [CinematicPlanCompassCommandPlan.ActionKind] = []
        let dispatch = CinematicPlanCompassCommandDispatch(
            plan: commandPlan,
            perform: { performed.append($0) }
        )

        XCTAssertNotNil(dispatch.plan.command(for: .showPlanOverlay))
        XCTAssertTrue(dispatch.plan.command(for: .focusLongTermRoute)?.isEnabled == true)

        for action in actionSurface.actions where action.isEnabled {
            dispatch.perform(action.sourceActionKind)
        }

        XCTAssertEqual(performed, commandPlan.commands.map(\.actionKind))
    }

    func testCommandPlannerDoesNotMutatePlanCompassDescriptors() {
        let plan = CinematicPlanCompassPlan(state: populatedState)
        let before = plan

        _ = CinematicPlanCompassCommandPlanner.plan(
            planCompassPlan: plan,
            selectedKind: .longTerm
        )

        XCTAssertEqual(plan, before)
    }

    private var populatedState: PlanState {
        PlanState(
            completed: ["Mapped diagnostics", "Rendered plan overlay"],
            immediate: PlanNext(
                plan: "Wire Plan Compass keyboard commands",
                verify: "swift test --filter CinematicPlanCompassCommandTests",
                verifyTimeoutMs: 90_000,
                estimatedDifficulty: .medium
            ),
            midTerm: "Queue diagnostics and command smoke coverage",
            longTerm: "Keep project direction visible while agents work"
        )
    }
}
