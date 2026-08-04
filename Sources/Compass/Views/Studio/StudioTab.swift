import CompassCore
import SwiftUI

/// Agent-perspective screensaver: file tree on the left, read-only highlighted
/// editor in the center (with typewriter playback of edits), bash log at the bottom.
struct StudioTab: View {
  @ObservedObject var project: CompassProject

  private var state: StudioState { project.studioState }

  var body: some View {
    if state.hasActivity {
      HSplitView {
        StudioFileTreeView(project: project)
          .frame(minWidth: 180, idealWidth: 230, maxWidth: 320)
        GeometryReader { geo in
          let editorFraction = editorHeightFraction(for: state.paneFocus)
          let editorHeight = max(140, geo.size.height * editorFraction)
          let terminalHeight = max(96, geo.size.height - editorHeight)
          VStack(spacing: 0) {
            StudioEditorView(state: state)
              .frame(width: geo.size.width, height: editorHeight)
            StudioTerminalView(state: state)
              .frame(width: geo.size.width, height: terminalHeight)
          }
          .animation(.easeInOut(duration: 0.35), value: state.paneFocus)
        }
        .layoutPriority(1)
        .frame(minWidth: 320)
      }
    } else {
      VStack(spacing: 10) {
        Image(systemName: "rectangle.split3x1")
          .font(.system(size: 34, weight: .light))
          .foregroundStyle(.tertiary)
        Text("Studio")
          .font(.headline)
        Text(
          "Run the factory and watch the agent work here — files it reads open in the editor, edits land inline, and bash commands stream into the terminal."
        )
        .font(.callout)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 420)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func editorHeightFraction(for focus: StudioState.StudioPaneFocus) -> CGFloat {
    switch focus {
    case .editor: return 0.75
    case .terminal: return 0.25
    case .balanced: return 0.62
    }
  }
}
