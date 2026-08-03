import CompassCore
import SwiftUI

/// IDE-style read-only mirror of the agent session: file tree on the left,
/// simulated editor in the center, continuous terminal at the bottom.
struct StudioTab: View {
  @ObservedObject var project: CompassProject

  var body: some View {
    if project.studioState.hasActivity {
      HSplitView {
        StudioFileTreeView(project: project)
          .frame(minWidth: 180, idealWidth: 230, maxWidth: 320)
        VSplitView {
          StudioEditorView(state: project.studioState)
            .frame(minWidth: 320, minHeight: 220)
          StudioTerminalView(state: project.studioState)
            .frame(minWidth: 320, minHeight: 120, idealHeight: 200)
        }
        .layoutPriority(1)
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
}
