import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        for window in NSApp.windows {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct CompassApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1120, minHeight: 760)
                .task {
                    await model.bootstrap()
                }
        }
        .defaultSize(width: 1120, height: 760)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Compass") {
                Button("Add Project") {
                    Task { await model.chooseRepository() }
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Refresh Project") {
                    Task { await model.refreshSelectedProject() }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(model.selectedProject == nil)

                Button("Play") {
                    Task { await model.playSelectedProject() }
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled((model.selectedProject?.isRunning ?? true) || (model.selectedProject?.isAutoPlaying ?? true))
            }
            CommandMenu("Runtime") {
                if let runtimeMenu = model.selectedProject?.runtimeDiagnosticsMenu {
                    let diagnosticsAction = runtimeMenu.copyDiagnosticsAction
                    Button(diagnosticsAction.title) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(diagnosticsAction.copyText, forType: .string)
                    }
                    .help(diagnosticsAction.helpText)
                    if let mutationAction = runtimeMenu.mutationTestingAction {
                        Divider()
                        Button(mutationAction.title) {
                            Task { await model.runMutationTestingForSelectedProject() }
                        }
                        .disabled(!mutationAction.isEnabled)
                        .help(mutationAction.helpText)
                    }
                    if let recovery = runtimeMenu.mutationRecoveryDescriptor {
                        Divider()
                        Button(recovery.copyActionLabel) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(recovery.copyText, forType: .string)
                        }
                        .help(recovery.helpText)
                    }
                } else {
                    Button("Copy Runtime Diagnostics") {}
                        .disabled(true)
                    Button("Run Mutation Test") {}
                        .disabled(true)
                        .help("Select a project before running mutation testing.")
                }
            }
            CinematicPlanCompassFocusedCommands()
            CinematicRunRecapShareArtifactFocusedCommands()
        }
}
}
