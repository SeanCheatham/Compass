import AppKit
import CompassCore
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

  /// Gives the embedded macOS VM a chance to shut the guest down
  /// gracefully (flush APFS, stop services) before the process exits
  /// and VZ pulls the power cord. Hard-capped at 6s so a wedged guest
  /// can never block app termination.
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    let vm = SharedCompassVM.shared
    guard vm.virtualMachine != nil else { return .terminateNow }
    vm.beginShutdown()
    Task { @MainActor in
      await withTaskGroup(of: Void.self) { group in
        group.addTask { @MainActor in
          await vm.stop()
        }
        group.addTask {
          try? await Task.sleep(nanoseconds: 6_000_000_000)
        }
        _ = await group.next()
        group.cancelAll()
      }
      NSApp.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }
}

@main
struct CompassApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var model = AppModel()
  @ObservedObject private var localModelManager: LocalModelManager = .shared

  init() {
    CompassWindowStateRepair.repairNavigationSplitViewFrames()
  }

  /// Mirrors `ContentView.isOnboardingComplete` so menu shortcuts
  /// (⌘O / ⌘R / ⌘Return) can't bypass the onboarding gate.
  private var isOnboardingComplete: Bool {
    localModelManager.snapshot.isRunnable
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
      CommandGroup(replacing: .newItem) {
        Button("New Factory Project") {
          Task { await model.createRustProject() }
        }
        .keyboardShortcut("n", modifiers: [.command])
        .disabled(!isOnboardingComplete)
      }
      CommandMenu("Compass") {
        Button("New Factory Project") {
          Task { await model.createRustProject() }
        }
        .disabled(!isOnboardingComplete)

        Button("Add Factory Project") {
          Task { await model.chooseRepository() }
        }
        .keyboardShortcut("o", modifiers: [.command])
        .disabled(!isOnboardingComplete)

        Button("Open Chamber…") {
          Task { await model.chooseChamberRepository() }
        }
        .keyboardShortcut("o", modifiers: [.command, .shift])
        .disabled(!isOnboardingComplete)

        Button("Copy Project Intake") {
          copyTextToPasteboard(projectIntakePayload.text)
        }
        .help(ClipboardHelpText.projectIntake)
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

        Button("Toggle Projects Sidebar") {
          let key = "compass.sidebarCollapsed"
          UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: key), forKey: key)
        }
        .keyboardShortcut("s", modifiers: [.command, .control])
        .disabled(!isOnboardingComplete)

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

        Button("Copy Project Snapshot") {
          if let payload = selectedProjectSnapshotPayload {
            copyTextToPasteboard(payload.text)
          }
        }
        .help(ClipboardHelpText.projectSnapshot)
        .disabled(selectedProjectSnapshotPayload == nil)

        Button("Copy Project Recovery") {
          if let payload = selectedProjectRecoveryPayload {
            copyTextToPasteboard(payload.text)
          }
        }
        .help(ClipboardHelpText.recovery)
        .disabled(selectedProjectRecoveryPayload == nil)

        Button("Copy Project Brief") {
          if let payload = selectedProjectVisionPayload {
            copyTextToPasteboard(payload.text)
          }
        }
        .help(ClipboardHelpText.projectVision)
        .disabled(selectedProjectVisionPayload == nil)

        Button("Copy Latest Run History") {
          if let payload = selectedLatestRunHistoryPayload {
            copyTextToPasteboard(payload.text)
          }
        }
        .help(ClipboardHelpText.runHistory)
        .disabled(selectedLatestRunHistoryPayload == nil)

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
        Button("Copy Runtime Settings") {
          copyTextToPasteboard(runtimeSettingsPayload.text)
        }
        .help(ClipboardHelpText.runtimeSettings)
        .disabled(runtimeSettingsPayload.isEmpty)

        Divider()

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

  private var selectedProjectSnapshotPayload: ProjectSnapshotClipboardPayload? {
    guard isOnboardingComplete, let project = model.selectedProject else { return nil }
    let payload = ProjectSnapshotBuilder.payload(
      for: project,
      agentSettings: model.agentSettings,
      modelSnapshot: localModelManager.snapshot
    )
    return payload.isEmpty ? nil : payload
  }

  private var projectIntakePayload: ProjectIntakeClipboardPayload {
    ProjectIntakeClipboardPayload(
      guide: ProjectIntakeGuide(projectCount: model.projects.count)
    )
  }

  private var runtimeSettingsPayload: AgentSettingsClipboardPayload {
    let guide = AgentSettingsGuide(
      settings: model.agentSettings,
      modelSnapshot: localModelManager.snapshot
    )
    return AgentSettingsClipboardPayload(
      settings: model.agentSettings,
      guide: guide,
      modelSnapshot: localModelManager.snapshot
    )
  }

  private var selectedProjectRecoveryPayload: ProjectRecoveryClipboardPayload? {
    guard isOnboardingComplete, let project = model.selectedProject else { return nil }
    let status = project.reliabilityStatus
    let guide = ProjectRecoveryGuide(status: status)
    let payload = ProjectRecoveryClipboardPayload(status: status, guide: guide)
    return payload.isEmpty ? nil : payload
  }

  private var selectedProjectVisionPayload: ProjectVisionClipboardPayload? {
    guard isOnboardingComplete, let project = model.selectedProject else { return nil }
    let guide = ProjectVisionGuide(brief: project.brief)
    let payload = ProjectVisionClipboardPayload(guide: guide)
    return payload.isEmpty ? nil : payload
  }

  private var selectedLatestRunHistoryPayload: PlanSessionHistoryClipboardPayload? {
    guard isOnboardingComplete, let project = model.selectedProject else { return nil }
    return ProjectSnapshotBuilder.latestRunHistoryClipboardPayload(for: project)
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
