import AppKit
import SwiftUI

struct ContentView: View {
  @EnvironmentObject private var model: AppModel
  @ObservedObject private var sharedVMHost: SharedCompassVM = .shared
  @ObservedObject private var localModelManager: LocalModelManager = .shared

  var body: some View {
    Group {
      if sharedVMHost.isShuttingDown {
        ShutdownView()
      } else if isOnboardingComplete {
        HSplitView {
          SidebarView()
            .frame(minWidth: 260, idealWidth: 310, maxWidth: 380, maxHeight: .infinity)
          workspaceDetail
            .frame(minWidth: 640, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      } else {
        OnboardingView()
      }
    }
    .animation(.easeInOut(duration: 0.2), value: sharedVMHost.isShuttingDown)
  }

  /// Mandatory onboarding gate. Compass routes every agent run through
  /// the Shared VM and needs the local MLX model before agent runs can start.
  private var isOnboardingComplete: Bool {
    sharedVMHost.readiness.isReady && localModelManager.snapshot.isRunnable
  }

  @ViewBuilder
  private var workspaceDetail: some View {
    switch model.workspaceSelection {
    case .sandbox:
      SandboxView()
    case .project:
      if let project = model.selectedProject {
        MainWorkspaceView(project: project)
          .id(project.id)
      } else {
        NoProjectView()
      }
    }
  }
}

/// Replaces the workspace UI while the AppDelegate awaits a clean VM stop
/// during `applicationShouldTerminate`. The host's 6s budget is real wall
/// time — without this view the live workspace just sits frozen on screen,
/// leaving the user wondering whether ⌘Q registered.
