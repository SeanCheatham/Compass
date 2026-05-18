import Foundation
@testable import Compass
import XCTest

final class CinematicPlanCompassActionSurfaceTests: XCTestCase {
    func testDescriptorIsDeterministicBoundedAndCorrelatedWithCommandPlan() throws {
        let plan = CinematicPlanCompassPlan(state: populatedState)
        let commandPlan = CinematicPlanCompassCommandPlanner.plan(
            planCompassPlan: plan,
            selectedKind: .midTerm
        )
        let surface = CinematicPlanCompassActionSurfacePlanner.descriptor(commandPlan: commandPlan)
        let repeated = CinematicPlanCompassActionSurfacePlanner.descriptor(commandPlan: commandPlan)

        XCTAssertEqual(surface, repeated)
        XCTAssertEqual(surface.sourceCommandPlanIdentifier, commandPlan.identifier)
        XCTAssertEqual(surface.sourcePlanIdentifier, commandPlan.sourcePlanIdentifier)
        XCTAssertEqual(surface.selectedRouteIdentifier, "mid-term")
        XCTAssertEqual(surface.actionCount, commandPlan.commandCount)
        XCTAssertEqual(surface.enabledActionCount, commandPlan.enabledCommandCount)
        XCTAssertEqual(surface.disabledActionCount, commandPlan.disabledCommandCount)
        XCTAssertLessThanOrEqual(
            surface.identifier.count,
            CinematicPlanCompassActionSurfaceDescriptor.identifierMaxCharacters
        )
        XCTAssertEqual(surface.actions.map(\.sourceActionKind), commandPlan.commands.map(\.actionKind))
        XCTAssertEqual(surface.actions.map(\.sourceCommandIdentifier), commandPlan.commands.map(\.identifier))
        XCTAssertEqual(
            surface.actions.filter(\.isSelectedRoute).map(\.sourceActionKind),
            [.focusMidTermRoute]
        )

        for (action, command) in zip(surface.actions, commandPlan.commands) {
            XCTAssertEqual(action.section, command.section)
            XCTAssertEqual(action.label, command.label)
            XCTAssertEqual(action.help, command.help)
            XCTAssertEqual(action.isEnabled, command.isEnabled)
            XCTAssertEqual(action.shortcutHint, command.shortcut.displayText)
            XCTAssertEqual(
                action.shortcutHint,
                CinematicPlanCompassCommandPlanner.shortcutHint(for: action.sourceActionKind)
            )
            XCTAssertFalse(action.systemImage.isEmpty)
            XCTAssertLessThanOrEqual(
                action.identifier.count,
                CinematicPlanCompassActionSurfaceDescriptor.identifierMaxCharacters
            )
            XCTAssertLessThanOrEqual(
                action.label.count,
                CinematicPlanCompassActionSurfaceDescriptor.labelMaxCharacters
            )
            XCTAssertLessThanOrEqual(
                action.help.count,
                CinematicPlanCompassActionSurfaceDescriptor.helpMaxCharacters
            )
            XCTAssertLessThanOrEqual(
                action.systemImage.count,
                CinematicPlanCompassActionSurfaceDescriptor.systemImageMaxCharacters
            )
            XCTAssertLessThanOrEqual(
                action.shortcutHint.count,
                CinematicPlanCompassActionSurfaceDescriptor.shortcutHintMaxCharacters
            )
        }
    }

    func testDisabledCopyAndSelectedRouteStatesMirrorCommands() throws {
        let plan = CinematicPlanCompassPlan(state: populatedState)
        var commandPlan = CinematicPlanCompassCommandPlanner.plan(
            planCompassPlan: plan,
            selectedKind: .longTerm
        )
        for index in commandPlan.commands.indices where commandPlan.commands[index].section == .copy {
            commandPlan.commands[index].isEnabled = false
        }

        let surface = CinematicPlanCompassActionSurfacePlanner.descriptor(commandPlan: commandPlan)
        let copyActions = surface.actions(in: .copy)

        XCTAssertEqual(surface.disabledActionCount, 2)
        XCTAssertEqual(copyActions.count, 2)
        XCTAssertTrue(copyActions.allSatisfy { !$0.isEnabled })
        XCTAssertEqual(copyActions.map(\.systemImage), ["doc.on.doc", "clipboard"])
        XCTAssertEqual(
            surface.actions.filter(\.isSelectedRoute).map(\.sourceActionKind),
            [.focusLongTermRoute]
        )
        XCTAssertEqual(
            surface.action(for: .copySelectedRoute)?.selectedRouteStateIdentifier,
            "selected-long-term"
        )
        XCTAssertEqual(
            surface.action(for: .copyFullPlanCompass)?.selectedRouteStateIdentifier,
            "available"
        )
    }

    private var populatedState: PlanState {
        PlanState(
            completed: ["Mapped diagnostics", "Rendered plan overlay"],
            immediate: PlanNext(
                plan: "Wire Plan Compass compact action controls",
                verify: "swift test --filter CinematicPlanCompassActionSurfaceTests",
                verifyTimeoutMs: 90_000,
                estimatedDifficulty: .medium
            ),
            midTerm: "Queue action-surface diagnostics",
            longTerm: "Keep project direction visible while agents work"
        )
    }
}
