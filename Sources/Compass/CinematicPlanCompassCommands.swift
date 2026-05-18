import SwiftUI

struct CinematicPlanCompassCommandDispatch {
    var plan: CinematicPlanCompassCommandPlan
    var perform: (CinematicPlanCompassCommandPlan.ActionKind) -> Void
}

private struct CinematicPlanCompassCommandDispatchKey: FocusedValueKey {
    typealias Value = CinematicPlanCompassCommandDispatch
}

extension FocusedValues {
    var cinematicPlanCompassCommandDispatch: CinematicPlanCompassCommandDispatch? {
        get { self[CinematicPlanCompassCommandDispatchKey.self] }
        set { self[CinematicPlanCompassCommandDispatchKey.self] = newValue }
    }
}

struct CinematicPlanCompassFocusedCommands: Commands {
    @FocusedValue(\.cinematicPlanCompassCommandDispatch)
    private var commandDispatch

    var body: some Commands {
        CommandMenu("Plan Compass") {
            if let commandDispatch {
                ForEach(CinematicPlanCompassCommandPlan.Section.allCases) { section in
                    let commands = commandDispatch.plan.commands(in: section)
                    if !commands.isEmpty {
                        Section {
                            ForEach(commands) { command in
                                Button(command.label) {
                                    commandDispatch.perform(command.actionKind)
                                }
                                .keyboardShortcut(
                                    command.shortcut.keyEquivalent,
                                    modifiers: command.shortcut.eventModifiers
                                )
                                .disabled(!command.isEnabled)
                                .help(command.help)
                            }
                        } header: {
                            Text(section.title)
                        }
                    }
                }
            } else {
                Button("No Plan Compass Commands") {}
                    .disabled(true)
            }
        }
    }
}

private extension CinematicPlanCompassCommandPlan.Shortcut {
    var keyEquivalent: KeyEquivalent {
        key.keyEquivalent
    }

    var eventModifiers: EventModifiers {
        var eventModifiers: EventModifiers = []
        for modifier in modifiers {
            eventModifiers.insert(modifier.eventModifier)
        }
        return eventModifiers
    }
}

private extension CinematicPlanCompassCommandPlan.Shortcut.Key {
    var keyEquivalent: KeyEquivalent {
        switch self {
        case .returnKey:
            return .return
        default:
            return KeyEquivalent(character)
        }
    }

    var character: Character {
        rawValue.first ?? " "
    }
}

private extension CinematicPlanCompassCommandPlan.Shortcut.Modifier {
    var eventModifier: EventModifiers {
        switch self {
        case .command:
            return .command
        case .control:
            return .control
        case .option:
            return .option
        case .shift:
            return .shift
        }
    }
}
