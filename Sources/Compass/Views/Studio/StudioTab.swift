import CompassCore
import SwiftUI

/// Agent-perspective screensaver: file tree on the left, read-only highlighted
/// editor in the center (with typewriter playback of edits), optional thinking
/// transcript, and bash log at the bottom.
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
          let heights = paneHeights(
            for: state.paneFocus,
            showsThinking: !state.thinkingEntries.isEmpty,
            in: geo.size.height
          )
          VStack(spacing: 0) {
            StudioEditorView(state: state)
              .frame(width: geo.size.width, height: heights.editor)
              .clipped()
            if heights.thinking > 0 {
              Divider()
              StudioThinkingView(state: state)
                .frame(width: geo.size.width, height: heights.thinking)
                .clipped()
            }
            StudioTerminalView(state: state)
              .frame(width: geo.size.width, height: heights.terminal)
              .clipped()
          }
          // Animate only after the split has a real size — first bash often
          // opens Studio from the empty state, and animating 0→height + scroll
          // together produces a blank terminal.
          .animation(
            geo.size.height > 1 ? .easeInOut(duration: 0.35) : nil,
            value: state.paneFocus
          )
          .animation(
            geo.size.height > 1 ? .easeInOut(duration: 0.25) : nil,
            value: state.thinkingEntries.isEmpty
          )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
          "Run the factory and watch the agent work here — files it reads open in the editor, edits land inline, thinking streams into a transcript, and bash commands appear in the terminal."
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
    showsThinking: Bool,
    in total: CGFloat
  ) -> (editor: CGFloat, thinking: CGFloat, terminal: CGFloat) {
    let minEditor: CGFloat = 80
    let minTerminal: CGFloat = 64
    let minThinking: CGFloat = showsThinking ? 72 : 0
    let thinkingBudget: CGFloat = showsThinking ? min(max(total * 0.22, minThinking), 180) : 0

    guard total > minEditor + minTerminal + thinkingBudget else {
      if showsThinking, total > minEditor + minTerminal {
        let thinking = min(thinkingBudget, total - minEditor - minTerminal)
        let remaining = total - thinking
        let half = max(remaining / 2, 0)
        return (half, thinking, max(remaining - half, 0))
      }
      let half = max(total / 2, 0)
      return (half, 0, max(total - half, 0))
    }

    let usable = total - thinkingBudget
    let idealEditor = usable * editorHeightFraction(for: focus)
    let editor = min(max(idealEditor, minEditor), usable - minTerminal)
    return (editor, thinkingBudget, usable - editor)
  }
}
