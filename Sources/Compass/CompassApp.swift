import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Bounded delay we accept to gracefully stop the shared VM before the
    /// host terminates. macOS will SIGKILL the process at ~10s if we miss
    /// the reply window, so we pick a value comfortably under that.
    private static let vmStopBudget: TimeInterval = 6

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

    /// Defers termination until the shared VM has had a chance to stop
    /// cleanly. Without this, the VZ guest just gets its references
    /// dropped — VZ does not guarantee a clean halt in that case, and
    /// subsequent boots can land in NVRAM-corruption territory.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor in
            await Self.stopSharedVMWithBudget()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    @MainActor
    private static func stopSharedVMWithBudget() async {
        let host = SharedCompassVM.shared
        // Nothing to stop if the VM never got off the ground.
        guard host.virtualMachine != nil else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                await host.stop()
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(vmStopBudget * 1_000_000_000))
            }
            // First task wins; whichever returns first cancels the rest so
            // we don't hold the app open past the budget.
            await group.next()
            group.cancelAll()
        }
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
