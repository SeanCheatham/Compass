import SwiftUI

// MARK: - SessionScope

/// Controls which sessions' commits are used for "why generated" queries.
enum SessionScope: String, CaseIterable {
  case lastSession = "Last Session"
  case allSessions = "All Sessions"
}

// MARK: - ExploreTab

/// A navigable tree view of the repository rooted at `repoURL`,
/// showing each file and folder with its language badge and pre-generated
/// codemap summary. Sub-folder nodes display an aggregated placeholder
/// until richer folder-level summaries are available.
struct ExploreTab: View {
  @ObservedObject var project: CompassProject
  @State private var fileTree: [FileTreeNode] = []
  @State private var codemapEntries: [String: CodemapEntry] = [:]
  @State private var isLoading = true
  @State private var whyGeneratedFile: String? = nil
  @State private var showWhyGenerated = false
  @State private var whyGeneratedExplanation: String? = nil
  @State private var loadingWhyGenerated = false

  @State private var sessionScope: SessionScope = .lastSession

  var body: some View {
    Group {
      if isLoading {
        ProgressView("Loading repository…")
      } else if fileTree.isEmpty {
        ContentUnavailableView(
          "No Source Files",
          systemImage: "folder",
          description: Text("Open a repository to explore its source files.")
        )
      } else {
        VStack(alignment: .leading, spacing: 0) {
          sessionScopePicker
          ScrollView {
          LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(fileTree, id: \.relativePath) { root in
              FileTreeRowView(
                node: root,
                codemapEntries: codemapEntries,
                indentLevel: 0,
                onFileTap: { path in
                  whyGeneratedFile = path
                  whyGeneratedExplanation = nil
                  loadingWhyGenerated = true
                  showWhyGenerated = true
                  Task { await loadWhyGenerated() }
                }
              )
            }
          }
          .padding(.horizontal, 8)
          .padding(.vertical, 6)
        }
        }
      }
    }
    .popover(isPresented: $showWhyGenerated) {
      if let file = whyGeneratedFile {
        WhyGeneratedPopover(
          fileName: (file as NSString).lastPathComponent,
          explanation: $whyGeneratedExplanation,
          isLoading: $loadingWhyGenerated
        )
      }
    }
    .task {
      await loadData()
    }
  }

  private func loadData() async {
    guard let workspace = project.workspace else {
      isLoading = false
      return
    }
    let codemapDir = CodemapStore.defaultDirectory(forWorkspace: workspace)
    let fs = CodemapFileSystem(rootURL: project.repoURL)
    let nodes = fs.buildTree()
    let entries = CodemapStore(directory: codemapDir).loadAllEntries()
    let entryMap = Dictionary(uniqueKeysWithValues: entries.map {
      ($0.relativePath, $0)
    })
    await MainActor.run {
      self.fileTree = nodes
      self.codemapEntries = entryMap
      self.isLoading = false
    }
  }

  private var sessionScopePicker: some View {
    HStack {
      Picker("Session Scope", selection: $sessionScope) {
        Text("Last Session").tag(SessionScope.lastSession)
        Text("All Sessions").tag(SessionScope.allSessions)
      }
      .pickerStyle(.menu)
      Spacer()
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .background(Color(nsColor: .controlBackgroundColor))
  }

  private func loadWhyGenerated() async {
    guard let file = whyGeneratedFile else { return }
    let commits: [SessionCommit]
    switch sessionScope {
    case .lastSession:
      commits = project.sessions.last?.commits ?? []
    case .allSessions:
      commits = project.sessions.flatMap(\.commits)
    }
    let result = await FileExplainer.whyGenerated(
      file: file,
      repoURL: project.repoURL,
      commits: commits
    )
    await MainActor.run {
      self.whyGeneratedExplanation = result
      self.loadingWhyGenerated = false
    }
  }
}

// MARK: - FileTreeNode

/// A node in the repo's directory tree produced by `CodemapFileSystem`.
struct FileTreeNode: Identifiable, Equatable {
  let relativePath: String
  let isDirectory: Bool
  let language: CodemapLanguage?
  var children: [FileTreeNode]

  var id: String { relativePath }

  /// The display name: last path component.
  var name: String {
    (relativePath as NSString).lastPathComponent
  }

  /// Number of source files under this node (direct children only).
  var fileCount: Int {
    isDirectory
      ? children.filter { !$0.isDirectory }.count
      : 0
  }

  /// Aggregated placeholder for a folder that has children but no stored
  /// folder-level summary.
  var folderSummary: String? {
    guard isDirectory else { return nil }
    let kids = children.filter { !$0.isDirectory }
    if kids.isEmpty { return nil }
    return "\(kids.count) source file\(kids.count == 1 ? "" : "s") in this folder"
  }
}

// MARK: - FileTreeRowView

struct FileTreeRowView: View {
  let node: FileTreeNode
  let codemapEntries: [String: CodemapEntry]
  let indentLevel: Int
  let onFileTap: (String) -> Void
  @State private var isExpanded = true

  private let rowHeight: CGFloat = 44

  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      if node.isDirectory {
        ForEach(node.children, id: \.relativePath) { child in
          FileTreeRowView(
            node: child,
            codemapEntries: codemapEntries,
            indentLevel: indentLevel + 1,
            onFileTap: onFileTap
          )
        }
      }
    } label: {
      HStack(spacing: 8) {
        // Indent
        HStack(spacing: 0) {
          ForEach(0..<indentLevel, id: \.self) { _ in
            Rectangle()
              .fill(.clear)
              .frame(width: 20)
          }
        }

        // Icon
        iconView

        // Name
        if node.isDirectory {
          Text(node.name)
            .font(.system(.body, design: .default))
            .fontWeight(node.isDirectory ? .medium : .regular)
            .foregroundStyle(node.isDirectory ? .primary : .secondary)
            .lineLimit(1)
        } else {
          Button {
            onFileTap(node.relativePath)
          } label: {
            Text(node.name)
              .font(.system(.body, design: .default))
              .fontWeight(node.isDirectory ? .medium : .regular)
              .foregroundStyle(node.isDirectory ? .primary : .secondary)
              .lineLimit(1)
          }
          .buttonStyle(.plain)
        }

        Spacer()

        // Language badge (files only)
        if !node.isDirectory, let lang = node.language {
          LanguageBadge(language: lang)
        }

        // Summary
        summaryLabel
      }
      .frame(height: rowHeight)
      .contentShape(Rectangle())
    }
  }

  @ViewBuilder
  private var iconView: some View {
    if node.isDirectory {
      Image(systemName: isExpanded ? "folder.fill" : "folder")
        .foregroundStyle(.yellow)
        .imageScale(.small)
    } else if let lang = node.language {
      Image(systemName: "doc.text")
        .foregroundStyle(LanguageBadge.color(for: lang))
        .imageScale(.small)
    } else {
      Image(systemName: "doc")
        .foregroundStyle(.secondary)
        .imageScale(.small)
    }
  }

  @ViewBuilder
  private var summaryLabel: some View {
    if let entry = codemapEntries[node.relativePath],
       let summary = entry.summary,
       !summary.isEmpty {
      Text(summary)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    } else if node.isDirectory, let folderSummary = node.folderSummary {
      Text(folderSummary)
        .font(.caption)
        .foregroundStyle(.tertiary)
        .italic()
        .lineLimit(1)
    } else {
      Text("No summary yet")
        .font(.caption)
        .foregroundStyle(.tertiary)
        .italic()
    }
  }
}

// MARK: - LanguageBadge

struct LanguageBadge: View {
  let language: CodemapLanguage

  var body: some View {
    Text(shortName)
      .font(.caption2)
      .fontWeight(.medium)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(Self.color(for: language).opacity(0.15))
      .foregroundStyle(Self.color(for: language))
      .clipShape(RoundedRectangle(cornerRadius: 4))
  }

  private var shortName: String {
    switch language {
    case .swift: return "Swift"
    case .typescript: return "TS"
    case .tsx: return "TSX"
    case .javascript: return "JS"
    case .python: return "Py"
    case .go: return "Go"
    case .rust: return "Rs"
    }
  }

  /// Color for language badges, e.g. Swift → orange.
  static func color(for language: CodemapLanguage) -> Color {
    switch language {
    case .swift: return .orange
    case .typescript, .tsx: return .blue
    case .javascript: return .yellow
    case .python: return .green
    case .go: return .cyan
    case .rust: return .orange
    }
  }
}

// MARK: - CodemapFileSystem

/// Reads `repoURL` and produces a tree of `FileTreeNode`s mirroring the
/// source directory layout under `rootURL`.
struct CodemapFileSystem {
  let rootURL: URL

  /// Build the full tree from the repo root.
  func buildTree() -> [FileTreeNode] {
    let keys = topLevelKeys()
    let nodes = keys.map { buildNode(relativePath: $0) }
    return sortNodes(nodes)
  }

  /// Top-level relative paths immediately under the repo root.
  private func topLevelKeys() -> [String] {
    let fm = FileManager.default
    guard let contents = try? fm.contentsOfDirectory(
      atPath: rootURL.path
    ) else { return [] }
    return contents.filter { name in
      // Hide hidden files/dirs and .compass internals
      !name.hasPrefix(".") && name != "Compass"
    }
  }

  private func buildNode(relativePath: String, atLevel level: Int = 0) -> FileTreeNode {
    let url = rootURL.appendingPathComponent(relativePath)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
      return FileTreeNode(
        relativePath: relativePath,
        isDirectory: false,
        language: CodemapLanguage.forRelativePath(relativePath),
        children: []
      )
    }

    if isDirectory.boolValue {
      let childKeys = childKeys(under: relativePath, url: url)
      let children = childKeys.map { buildNode(relativePath: $0, atLevel: level + 1) }
      return FileTreeNode(
        relativePath: relativePath,
        isDirectory: true,
        language: nil,
        children: sortNodes(children)
      )
    } else {
      return FileTreeNode(
        relativePath: relativePath,
        isDirectory: false,
        language: CodemapLanguage.forRelativePath(relativePath),
        children: []
      )
    }
  }

  private func childKeys(under parent: String, url: URL) -> [String] {
    let fm = FileManager.default
    guard let contents = try? fm.contentsOfDirectory(atPath: url.path) else {
      return []
    }
    return contents.filter { name in
      !name.hasPrefix(".")
    }
  }

  private func sortNodes(_ nodes: [FileTreeNode]) -> [FileTreeNode] {
    let dirs = nodes.filter { $0.isDirectory }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    let files = nodes.filter { !$0.isDirectory }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    return dirs + files
  }
}
