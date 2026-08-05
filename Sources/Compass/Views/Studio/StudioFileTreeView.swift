import CompassCore
import SwiftUI

struct StudioFileNode: Identifiable, Hashable {
  let path: String
  let name: String
  var children: [StudioFileNode]?

  var id: String { path }
  var isDirectory: Bool { children != nil }

  static func build(from paths: [String]) -> [StudioFileNode] {
    var roots: [StudioFileNode] = []
    for path in paths where !path.isEmpty {
      insert(components: path.split(separator: "/").map(String.init), into: &roots, prefix: "")
    }
    return roots
  }

  private static func insert(
    components: [String],
    into nodes: inout [StudioFileNode],
    prefix: String
  ) {
    guard let head = components.first else { return }
    let path = prefix.isEmpty ? head : "\(prefix)/\(head)"
    if components.count == 1 {
      // Prefer an existing directory at this path over a duplicate file leaf —
      // nested paths win when the agent has also touched a same-named file.
      if nodes.contains(where: { $0.path == path }) { return }
      nodes.append(StudioFileNode(path: path, name: head, children: nil))
      nodes.sort { sortOrder($0, $1) }
      return
    }
    if let index = nodes.firstIndex(where: { $0.path == path }) {
      // Promote a prior file leaf into a directory so nested paths can attach
      // without creating a duplicate Identifiable id.
      var children = nodes[index].children ?? []
      insert(
        components: Array(components.dropFirst()),
        into: &children,
        prefix: path
      )
      nodes[index].children = children
    } else {
      var children: [StudioFileNode] = []
      insert(
        components: Array(components.dropFirst()),
        into: &children,
        prefix: path
      )
      nodes.append(StudioFileNode(path: path, name: head, children: children))
    }
    nodes.sort { sortOrder($0, $1) }
  }

  private static func sortOrder(_ lhs: StudioFileNode, _ rhs: StudioFileNode) -> Bool {
    if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
  }
}

struct StudioFileTreeView: View {
  @ObservedObject var project: CompassProject
  @ObservedObject private var state: StudioState
  @State private var expandedPaths: Set<String> = []
  @State private var revealedKnownPaths: Set<String> = []

  init(project: CompassProject) {
    self.project = project
    self.state = project.studioState
  }

  private var knownPaths: [String] {
    state.knownFiles.keys.sorted()
  }

  private var heatByPath: [String: Double] {
    StudioState.heatByPath(state.knownFiles)
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text(project.repoURL.lastPathComponent)
          .font(.callout.weight(.semibold))
          .lineLimit(1)
        Spacer(minLength: 0)
        Text("\(state.knownFiles.count)")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.tertiary)
          .help("Files the agent has seen this session")
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      Divider()
      if state.knownFiles.isEmpty {
        Text("Files the agent reads, edits, or lists will appear here.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .padding(16)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(StudioFileNode.build(from: knownPaths)) { node in
              StudioFileTreeNodeView(
                node: node,
                depth: 0,
                expandedPaths: $expandedPaths,
                openPath: state.openFile,
                touchedPath: state.lastTouchedPath,
                heatByPath: heatByPath,
                onOpenFile: { path in
                  state.peek(path)
                }
              )
            }
          }
          .padding(.vertical, 6)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    .onChange(of: state.lastTouchedPath) {
      reveal(state.lastTouchedPath)
    }
    .onChange(of: knownPaths) { _, newPaths in
      for path in newPaths where !revealedKnownPaths.contains(path) {
        reveal(path)
        revealedKnownPaths.insert(path)
      }
    }
  }

  private func reveal(_ path: String?) {
    guard let path else { return }
    var components = path.split(separator: "/").map(String.init)
    guard components.count > 1 else { return }
    components.removeLast()
    var prefix = ""
    for component in components {
      prefix = prefix.isEmpty ? component : "\(prefix)/\(component)"
      expandedPaths.insert(prefix)
    }
  }
}

private struct StudioFileTreeNodeView: View {
  let node: StudioFileNode
  let depth: Int
  @Binding var expandedPaths: Set<String>
  let openPath: String?
  let touchedPath: String?
  /// Recency heat per path (0–1), most recently seen file = 1.
  let heatByPath: [String: Double]
  let onOpenFile: (String) -> Void

  private var isExpanded: Bool { expandedPaths.contains(node.path) }
  private var heat: Double { heatByPath[node.path] ?? 0 }

  var body: some View {
    if node.isDirectory {
      Button {
        if isExpanded {
          expandedPaths.remove(node.path)
        } else {
          expandedPaths.insert(node.path)
        }
      } label: {
        rowLabel(
          systemImage: isExpanded ? "chevron.down" : "chevron.right",
          name: node.name,
          isDirectory: true
        )
      }
      .buttonStyle(.plain)
      if isExpanded, let children = node.children {
        ForEach(children) { child in
          StudioFileTreeNodeView(
            node: child,
            depth: depth + 1,
            expandedPaths: $expandedPaths,
            openPath: openPath,
            touchedPath: touchedPath,
            heatByPath: heatByPath,
            onOpenFile: onOpenFile
          )
        }
      }
    } else {
      Button {
        onOpenFile(node.path)
      } label: {
        rowLabel(systemImage: fileIcon, name: node.name, isDirectory: false)
          .background(
            RoundedRectangle(cornerRadius: 5)
              .fill(backgroundColor)
          )
      }
      .buttonStyle(.plain)
    }
  }

  private var fileIcon: String {
    switch (node.name as NSString).pathExtension.lowercased() {
    case "swift", "rs", "py", "js", "ts", "tsx", "jsx", "go", "c", "cc", "cpp", "h", "hpp":
      return "chevron.left.forwardslash.chevron.right"
    case "md", "txt", "rst":
      return "doc.text"
    case "json", "yaml", "yml", "toml", "xml":
      return "curlybraces"
    default:
      return "doc"
    }
  }

  private var backgroundColor: Color {
    if node.path == openPath {
      return Color.accentColor.opacity(0.22)
    }
    if node.path == touchedPath {
      return Color.accentColor.opacity(0.10)
    }
    if heat > 0 {
      return Color.orange.opacity(0.16 * heat)
    }
    return .clear
  }

  private func rowLabel(systemImage: String, name: String, isDirectory: Bool) -> some View {
    HStack(spacing: 5) {
      Image(systemName: systemImage)
        .font(.system(size: isDirectory ? 9 : 10, weight: .medium))
        .foregroundStyle(isDirectory ? Color.secondary : Color.accentColor)
        .frame(width: 12)
      Text(name)
        .font(.callout)
        .lineLimit(1)
        .foregroundStyle(node.path == openPath ? Color.primary : Color.secondary)
      Spacer(minLength: 0)
    }
    .padding(.leading, CGFloat(depth) * 14 + 8)
    .padding(.trailing, 8)
    .padding(.vertical, 3)
    .contentShape(Rectangle())
  }
}
