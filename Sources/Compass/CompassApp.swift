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
        Button("New Tessera App") {
          Task { await model.createTesseraProject() }
        }
        .keyboardShortcut("n", modifiers: [.command])
        .disabled(!isOnboardingComplete)
      }
      CommandMenu("Compass") {
        Button("New Tessera App") {
          Task { await model.createTesseraProject() }
        }
        .disabled(!isOnboardingComplete)

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

        Button("Copy Project Snapshot") {
          if let payload = selectedProjectSnapshotPayload {
            copyTextToPasteboard(payload.text)
          }
        }
        .disabled(selectedProjectSnapshotPayload == nil)

        Button("Copy Project Recovery") {
          if let payload = selectedProjectRecoveryPayload {
            copyTextToPasteboard(payload.text)
          }
        }
        .disabled(selectedProjectRecoveryPayload == nil)

        Button("Copy Project Vision") {
          if let payload = selectedProjectVisionPayload {
            copyTextToPasteboard(payload.text)
          }
        }
        .disabled(selectedProjectVisionPayload == nil)

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

  private var selectedRunGuide: ProjectRunControlGuide? {
    guard isOnboardingComplete, let project = model.selectedProject else { return nil }
    return ProjectSnapshotBuilder.runGuide(for: project)
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
    let guide = ProjectVisionGuide(vision: project.vision)
    let payload = ProjectVisionClipboardPayload(guide: guide)
    return payload.isEmpty ? nil : payload
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
