import SwiftUI

struct CinematicRunRecapShareArtifactCommandDispatch {
    var plan: CinematicRunRecapShareArtifactCommandPlan
    var perform: (CinematicRunRecapShareArtifactActionMenuPlan.ActionKind) -> Void
}

private struct CinematicRunRecapShareArtifactCommandDispatchKey: FocusedValueKey {
    typealias Value = CinematicRunRecapShareArtifactCommandDispatch
}

extension FocusedValues {
    var cinematicRunRecapShareArtifactCommandDispatch: CinematicRunRecapShareArtifactCommandDispatch? {
        get { self[CinematicRunRecapShareArtifactCommandDispatchKey.self] }
        set { self[CinematicRunRecapShareArtifactCommandDispatchKey.self] = newValue }
    }
}

struct CinematicRunRecapShareArtifactFocusedCommands: Commands {
    @FocusedValue(\.cinematicRunRecapShareArtifactCommandDispatch)
    private var commandDispatch

    var body: some Commands {
        CommandMenu("Recap Artifacts") {
            if let commandDispatch {
                ForEach(CinematicRunRecapShareArtifactActionMenuPlan.Section.allCases) { section in
                    let commands = commandDispatch.plan.commands(in: section)
                    if !commands.isEmpty {
                        Section {
                            ForEach(commands) { command in
                                Button(command.label) {
                                    commandDispatch.perform(command.sourceActionKind)
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
                Button("No Recap Artifact Commands") {}
                    .disabled(true)
            }
        }
    }
}

private extension CinematicRunRecapShareArtifactCommandPlan.Shortcut {
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

private extension CinematicRunRecapShareArtifactCommandPlan.Shortcut.Key {
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

private extension CinematicRunRecapShareArtifactCommandPlan.Shortcut.Modifier {
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
