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
      if !nodes.contains(where: { $0.path == path }) {
        nodes.append(StudioFileNode(path: path, name: head, children: nil))
        nodes.sort { sortOrder($0, $1) }
      }
      return
    }
    if let index = nodes.firstIndex(where: { $0.path == path && $0.isDirectory }) {
      insert(components: Array(components.dropFirst()), into: &nodes[index].children!, prefix: path)
    } else {
      var directory = StudioFileNode(path: path, name: head, children: [])
      insert(components: Array(components.dropFirst()), into: &directory.children!, prefix: path)
      nodes.append(directory)
    }
    nodes.sort { sortOrder($0, $1) }
  }

  private static func sortOrder(_ lhs: StudioFileNode, _ rhs: StudioFileNode) -> Bool {
    if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
  }
}

@MainActor
final class StudioFileTreeModel: ObservableObject {
  @Published private(set) var roots: [StudioFileNode] = []

  private var reloadTask: Task<Void, Never>?
  private var pendingReloadURL: URL?

  /// Reload the tracked/untracked file list. Coalesces rapid bursts (one
  /// in-flight reload at a time; latest repoURL wins for the next pass).
  func reload(repoURL: URL) {
    if reloadTask != nil {
      pendingReloadURL = repoURL
      return
    }
    reloadTask = Task {
      let paths = await Self.listFiles(repoURL: repoURL)
      if !Task.isCancelled {
        roots = StudioFileNode.build(from: paths)
      }
      reloadTask = nil
      if let pending = pendingReloadURL {
        pendingReloadURL = nil
        reload(repoURL: pending)
      }
    }
  }

  private static func listFiles(repoURL: URL) async -> [String] {
    guard
      let result = try? await ProcessRunner.runEnv(
        "git",
        ["ls-files", "-co", "--exclude-standard"],
        workingDirectory: repoURL
      ), result.exitCode == 0
    else { return [] }
    return
      result.stdout
      .components(separatedBy: "\n")
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty && !$0.hasPrefix(".compass/") && $0 != ".compass" }
  }
}

struct StudioFileTreeView: View {
  @ObservedObject var project: CompassProject
  @StateObject private var model = StudioFileTreeModel()
  @State private var expandedPaths: Set<String> = []

  private var state: StudioState { project.studioState }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text(project.repoURL.lastPathComponent)
          .font(.callout.weight(.semibold))
          .lineLimit(1)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      Divider()
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(model.roots) { node in
            StudioFileTreeNodeView(
              node: node,
              depth: 0,
              expandedPaths: $expandedPaths,
              openPath: state.openFile,
              touchedPath: state.lastTouchedPath,
              onOpenFile: { path in
                state.peek(path)
              }
            )
          }
        }
        .padding(.vertical, 6)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    .task {
      model.reload(repoURL: project.repoURL)
    }
    .onChange(of: state.treeRefreshToken) {
      model.reload(repoURL: project.repoURL)
    }
    .onChange(of: state.lastTouchedPath) {
      reveal(state.lastTouchedPath)
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
  let onOpenFile: (String) -> Void

  private var isExpanded: Bool { expandedPaths.contains(node.path) }

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
