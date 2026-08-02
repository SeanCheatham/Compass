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

  /// Mandatory onboarding gate: agent runs cannot start until the local
  /// MLX model is downloaded and runnable.
  private var isOnboardingComplete: Bool {
    localModelManager.snapshot.isRunnable
  }

  @ViewBuilder
  private var workspaceDetail: some View {
    switch model.workspaceSelection {
    case .runtime:
      TabView {
        ContainerRuntimeView()
          .tabItem { Label("Container Runtime", systemImage: "shippingbox") }
        MacOSVMRuntimeView()
          .tabItem { Label("macOS VM", systemImage: "desktopcomputer") }
      }
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
