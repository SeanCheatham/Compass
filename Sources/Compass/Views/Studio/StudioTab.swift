import CompassCore
import SwiftUI

/// Agent-perspective screensaver: file tree on the left, read-only highlighted
/// editor in the center (with typewriter playback of edits), bash log at the bottom.
struct StudioTab: View {
  @ObservedObject var project: CompassProject
  /// Observed directly — `CompassProject.studioState` is not `@Published`, so
  /// pane-focus / activity changes would not otherwise rebuild this split.
  @ObservedObject private var state: StudioState

  init(project: CompassProject) {
    self.project = project
    self.state = project.studioState
  }

  var body: some View {
    if state.hasActivity {
      HSplitView {
        StudioFileTreeView(project: project)
          .frame(minWidth: 180, idealWidth: 230, maxWidth: 320)
        GeometryReader { geo in
          let heights = paneHeights(for: state.paneFocus, in: geo.size.height)
          VStack(spacing: 0) {
            StudioEditorView(state: state)
              .frame(width: geo.size.width, height: heights.editor)
            StudioTerminalView(state: state)
              .frame(width: geo.size.width, height: heights.terminal)
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

  /// Split height that always sums to `total` so min-height floors cannot
  /// overflow the pane (and steal the majority from the focused side).
  private func paneHeights(
    for focus: StudioState.StudioPaneFocus,
    in total: CGFloat
  ) -> (editor: CGFloat, terminal: CGFloat) {
    let minEditor: CGFloat = 80
    let minTerminal: CGFloat = 64
    guard total > minEditor + minTerminal else {
      let half = max(total / 2, 0)
      return (half, max(total - half, 0))
    }
    let idealEditor = total * editorHeightFraction(for: focus)
    let editor = min(max(idealEditor, minEditor), total - minTerminal)
    return (editor, total - editor)
  }
}
