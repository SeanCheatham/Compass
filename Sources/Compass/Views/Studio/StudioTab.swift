import CompassCore
import SwiftUI

/// Agent-perspective screensaver: file tree on the left, read-only highlighted
/// editor in the center (with typewriter playback of edits), bash log below,
/// and optional thinking transcript under the terminal.
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
            StudioTerminalView(state: state)
              .frame(width: geo.size.width, height: heights.terminal)
              .clipped()
            if heights.thinking > 0 {
              Divider()
              StudioThinkingView(
                state: state,
                speech: project.studioThinkingSpeech,
                project: project
              )
              .frame(width: geo.size.width, height: heights.thinking)
              .clipped()
            }
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
          "When the agent runs, files it touches open here, edits type in place, bash lands in the terminal, and thinking streams below."
        )
        .font(.callout)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 420)
        Text("Start a run from Activity to populate this view.")
          .font(.caption)
          .foregroundStyle(.tertiary)
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
    let minThinking: CGFloat = 72
    let maxThinking: CGFloat = 180
    // Divider above thinking (under the terminal) sits outside the thinking frame.
    let divider: CGFloat = 1

    let twoPane: (editor: CGFloat, thinking: CGFloat, terminal: CGFloat) = {
      guard total > minEditor + minTerminal else {
        let half = max(total / 2, 0)
        return (half, 0, max(total - half, 0))
      }
      let idealEditor = total * editorHeightFraction(for: focus)
      let editor = min(max(idealEditor, minEditor), total - minTerminal)
      return (editor, 0, total - editor)
    }()

    guard showsThinking else { return twoPane }

    // Hide thinking rather than render a sub-minimum strip that clips content.
    let minTotalForThinking = minEditor + minTerminal + minThinking + divider
    guard total >= minTotalForThinking else { return twoPane }

    var thinking = min(max(total * 0.22, minThinking), maxThinking)
    // When the terminal is focused, keep enough split budget that the terminal
    // can stay the majority even after minEditor floors the editor pane.
    if focus == .terminal {
      let usableNeededForTerminalMajority = (minEditor * 2) + 1
      let maxThinkingForFocus = total - divider - usableNeededForTerminalMajority
      if maxThinkingForFocus < minThinking {
        return twoPane
      }
      thinking = min(thinking, maxThinkingForFocus)
    }

    let usable = total - thinking - divider
    switch focus {
    case .terminal:
      let idealTerminal = usable * (1 - editorHeightFraction(for: focus))
      let terminal = min(max(idealTerminal, minTerminal), usable - minEditor)
      return (usable - terminal, thinking, terminal)
    case .editor, .balanced:
      let idealEditor = usable * editorHeightFraction(for: focus)
      let editor = min(max(idealEditor, minEditor), usable - minTerminal)
      return (editor, thinking, usable - editor)
    }
  }
}
