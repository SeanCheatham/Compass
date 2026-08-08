import CompassCore
import SwiftUI

/// Agent-perspective screensaver: file tree on the left, tabbed editor/terminal
/// in the upper pane, and optional thinking transcript pinned below.
struct StudioTab: View {
  @ObservedObject var project: CompassProject
  /// Observed directly — `CompassProject.studioState` is not `@Published`, so
  /// surface / activity changes would not otherwise rebuild this split.
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
            showsThinking: !state.thinkingEntries.isEmpty,
            in: geo.size.height
          )
          VStack(spacing: 0) {
            VStack(spacing: 0) {
              studioTabStrip
              if state.selectedSurface == .terminal {
                StudioTerminalView(state: state)
              } else {
                StudioEditorView(state: state)
              }
            }
            .frame(width: geo.size.width, height: heights.upper)
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
          // Animate only after the split has a real size — first content often
          // opens Studio from the empty state.
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
          "When the agent runs, files it touches open here, edits type in place, bash lands in the Terminal tab, and thinking streams below. Factory and health runs both feed this view."
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

  @ViewBuilder
  private var studioTabStrip: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 6) {
        tabChip(
          title: "Terminal",
          systemImage: "terminal",
          selected: state.selectedSurface == .terminal
        ) {
          state.selectTerminal()
        }
        ForEach(state.recentPaths.reversed(), id: \.self) { path in
          tabChip(
            title: (path as NSString).lastPathComponent,
            systemImage: nil,
            selected: state.selectedSurface == .file && path == state.openFile
          ) {
            state.peek(path)
          }
        }
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
    }
    Divider()
  }

  private func tabChip(
    title: String,
    systemImage: String?,
    selected: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 4) {
        if let systemImage {
          Image(systemName: systemImage)
            .font(.system(size: 10))
        }
        Text(title)
          .font(.caption)
          .lineLimit(1)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(
        RoundedRectangle(cornerRadius: 4)
          .fill(
            selected
              ? Color.accentColor.opacity(0.22)
              : Color.secondary.opacity(0.12)
          )
      )
    }
    .buttonStyle(.plain)
  }

  /// Upper pane vs pinned thinking. Terminal shares the upper pane as a tab,
  /// so it no longer competes for a separate vertical slice.
  private func paneHeights(
    showsThinking: Bool,
    in total: CGFloat
  ) -> (upper: CGFloat, thinking: CGFloat) {
    let minUpper: CGFloat = 120
    let minThinking: CGFloat = 72
    let maxThinking: CGFloat = 180
    let divider: CGFloat = 1

    guard showsThinking else {
      return (max(total, 0), 0)
    }

    let minTotalForThinking = minUpper + minThinking + divider
    guard total >= minTotalForThinking else {
      return (max(total, 0), 0)
    }

    let thinking = min(max(total * 0.22, minThinking), maxThinking)
    return (total - thinking - divider, thinking)
  }
}
