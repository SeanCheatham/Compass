import AppKit
import SwiftUI
import CompassCore

struct ContentView: View {
  @EnvironmentObject private var model: AppModel
  @ObservedObject private var localModelManager: LocalModelManager = .shared

  var body: some View {
    Group {
      if isOnboardingComplete {
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
  }

  /// Mandatory onboarding gate. Compass routes every agent run through
  /// the containerized Linux runtime and needs the local MLX model before
  /// agent runs can start.
  private var isOnboardingComplete: Bool {
    localModelManager.snapshot.isRunnable
  }

  @ViewBuilder
  private var workspaceDetail: some View {
    switch model.workspaceSelection {
    case .runtime:
      ContainerRuntimeView()
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
