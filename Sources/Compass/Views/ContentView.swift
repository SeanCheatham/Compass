import AppKit
import SwiftUI


import AppKit
import SwiftUI

struct ContentView: View {
  @EnvironmentObject private var model: AppModel
  @ObservedObject private var sharedVMHost: SharedCompassVM = .shared

  var body: some View {
    Group {
      if sharedVMHost.isShuttingDown {
        ShutdownView()
      } else if isOnboardingComplete {
        NavigationSplitView {
          SidebarView()
        } detail: {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      } else {
        OnboardingView()
      }
    }
    .animation(.easeInOut(duration: 0.2), value: sharedVMHost.isShuttingDown)
  }

  /// Mandatory onboarding gate. Compass routes every agent run through
  /// the Shared VM and needs a configured Text provider to call the
  /// LLM, so neither is optional — the rest of the UI is hidden until
  /// both land. On-device Foundation Models is "configured" once
  /// selected (no API key required); HTTP providers also need a key.
  private var isOnboardingComplete: Bool {
    sharedVMHost.readiness.isReady && model.agentSettings.isTextCapabilityReady
  }
}

/// Replaces the workspace UI while the AppDelegate awaits a clean VM stop
/// during `applicationShouldTerminate`. The host's 6s budget is real wall
/// time — without this view the live workspace just sits frozen on screen,
/// leaving the user wondering whether ⌘Q registered.
