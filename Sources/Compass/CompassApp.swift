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
    // If there's no VM to stop, quit instantly — no need to flash a
    // shutdown overlay in front of the user.
    let host = SharedCompassVM.shared
    guard host.virtualMachine != nil else {
      return .terminateNow
    }
    // Flip the shutdown flag *synchronously* before yielding to the
    // Task so SwiftUI gets a chance to render the shutdown view in the
    // same run-loop turn we return `.terminateLater`.
    host.beginShutdown()
    Task { @MainActor in
      await Self.stopSharedVMWithBudget(host: host)
      NSApp.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }

  @MainActor
  private static func stopSharedVMWithBudget(host: SharedCompassVM) async {
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
  @ObservedObject private var sharedVMHost: SharedCompassVM = .shared

  init() {
    CompassWindowStateRepair.repairNavigationSplitViewFrames()
  }

  /// Mirrors `ContentView.isOnboardingComplete` so menu shortcuts
  /// (⌘O / ⌘R / ⌘Return) can't bypass the onboarding gate.
  private var isOnboardingComplete: Bool {
    sharedVMHost.readiness.isReady && model.agentSettings.isTextCapabilityReady
  }

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
        .disabled(!isOnboardingComplete)

        Button("Copy Project Intake") {
          copyTextToPasteboard(projectIntakePayload.text)
        }
        .keyboardShortcut("i", modifiers: [.command, .option])
        .disabled(!isOnboardingComplete)

        Button("Refresh Project") {
          Task { await model.refreshSelectedProject() }
        }
        .keyboardShortcut("r", modifiers: [.command])
        .disabled(!isOnboardingComplete || model.selectedProject == nil)

        Button("Reveal Project in Finder") {
          if let repoURL = model.selectedProject?.repoURL {
            NSWorkspace.shared.activateFileViewerSelecting([repoURL])
          }
        }
        .keyboardShortcut("f", modifiers: [.command, .option])
        .disabled(!isOnboardingComplete || model.selectedProject == nil)

        Button("Copy Project Path") {
          if let repoPath = model.selectedProject?.repoURL.path {
            copyTextToPasteboard(repoPath)
          }
        }
        .disabled(!isOnboardingComplete || model.selectedProject == nil)

        Button("Play") {
          Task { await model.playSelectedProject() }
        }
        .keyboardShortcut(.return, modifiers: [.command])
        .disabled(
          !isOnboardingComplete || (model.selectedProject?.isRunning ?? true)
            || (model.selectedProject?.isAutoPlaying ?? true))

        Divider()

        Button("Copy Factory Brief") {
          if let guide = selectedFactoryGuide {
            copyTextToPasteboard(guide.handoffText)
          }
        }
        .keyboardShortcut("c", modifiers: [.command, .option])
        .disabled(selectedFactoryGuide == nil)

        Button(PauseMode.afterIteration.label) {
          model.selectedProject?.requestPause(.afterIteration)
        }
        .keyboardShortcut("p", modifiers: [.command, .shift])
        .disabled(!canPauseSelectedProject)

        Button("Stop Run") {
          model.selectedProject?.stopRun()
        }
        .keyboardShortcut(".", modifiers: [.command])
        .disabled(!canStopSelectedProject)
      }
      CommandMenu("Runtime") {
        if let runtimeMenu = model.selectedProject?.runtimeDiagnosticsMenu {
          let diagnosticsAction = runtimeMenu.copyDiagnosticsAction
          Button(diagnosticsAction.title) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(diagnosticsAction.copyText, forType: .string)
          }
          .help(diagnosticsAction.helpText)
        } else {
          Button("Copy Runtime Diagnostics") {}
            .disabled(true)
        }
      }
    }

    Settings {
      CompassSettingsView()
        .environmentObject(model)
    }
  }

  private var selectedFactoryGuide: FactoryCompassGuide? {
    guard isOnboardingComplete, let project = model.selectedProject else { return nil }
    let runGuide = ProjectRunControlGuide(
      state: project.state,
      reliabilityStatus: project.reliabilityStatus,
      hasRepository: project.hasRepository,
      isRunning: project.isRunning,
      isAutoPlaying: project.isAutoPlaying,
      isPaused: project.isPaused,
      languageProfile: project.languageProfile,
      forgeProfile: project.forgeProfile,
      drafts: project.drafts
    )
    return FactoryCompassGuide(runGuide: runGuide)
  }

  private var projectIntakePayload: ProjectIntakeClipboardPayload {
    ProjectIntakeClipboardPayload(
      guide: ProjectIntakeGuide(projectCount: model.projects.count)
    )
  }

  private var canPauseSelectedProject: Bool {
    guard isOnboardingComplete, let project = model.selectedProject else { return false }
    return (project.isRunning || project.isAutoPlaying) && !project.isPaused
  }

  private var canStopSelectedProject: Bool {
    guard isOnboardingComplete, let project = model.selectedProject else { return false }
    return project.canStop
  }
}
