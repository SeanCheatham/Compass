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
  let project: CompassProject
  let isActive: Bool
  @State private var fileTree: [FileTreeNode] = []
  @State private var codemapEntries: [String: CodemapEntry] = [:]
  @State private var isLoading = true
  @State private var whyGeneratedFile: String? = nil
  @State private var showWhyGenerated = false
  @State private var whyGeneratedExplanation: String? = nil
  @State private var whyGeneratedReason: ExplainUnavailableReason? = nil
  @State private var loadingWhyGenerated = false

  @State private var summaryPopoverFile: String? = nil
  @State private var summaryPopoverText: String? = nil
  @State private var summaryPopoverReason: ExplainUnavailableReason? = nil
  @State private var showSummaryPopover = false

  @State private var loadingSummary = false

  @State private var symbolDetailEntry: CodemapEntry? = nil
  @State private var showSymbolDetailPopover = false

  @State private var sessionScope: SessionScope = .lastSession
  @State private var expandedPaths: Set<String> = []
  @State private var loadedRepoPath: String?

  private var visibleRows: [ExploreVisibleRow] {
    ExploreVisibleRow.visibleRows(in: fileTree, expandedPaths: expandedPaths)
  }

  var body: some View {
    exploreContent
      .popover(isPresented: $showSummaryPopover) {
      if let file = summaryPopoverFile {
        SummaryPopover(
          fileName: (file as NSString).lastPathComponent,
          summary: summaryPopoverText,
          reason: summaryPopoverReason
        )
      }
    }
    .popover(isPresented: $showSymbolDetailPopover) {
      if let entry = symbolDetailEntry {
        SymbolDetailPopover(entry: entry)
      }
    }
    .popover(isPresented: $showWhyGenerated) {
      if let file = whyGeneratedFile {
        WhyGeneratedPopover(
          fileName: (file as NSString).lastPathComponent,
          explanation: $whyGeneratedExplanation,
          reason: $whyGeneratedReason,
          isLoading: $loadingWhyGenerated
        )
      }
    }
    .onAppear {
      guard isActive else { return }
      applyCachedSnapshotIfAvailable()
    }
    .onChange(of: isActive) { _, active in
      guard active else { return }
      applyCachedSnapshotIfAvailable()
      Task { await loadRepositorySnapshotIfNeeded() }
    }
    .task(id: project.repoURL.standardizedFileURL.path) {
      guard isActive else { return }
      await loadRepositorySnapshotIfNeeded()
    }
  }

  @ViewBuilder
  private var exploreContent: some View {
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
        List {
          ForEach(visibleRows) { row in
            FileTreeRowView(
              node: row.node,
              depth: row.depth,
              isExpanded: expandedPaths.contains(row.node.relativePath),
              codemapEntries: codemapEntries,
              onToggleExpansion: toggleExpansion,
              onFileTap: handleFileTap,
              onSummaryTap: handleSummaryTap,
              onSymbolDetailTap: handleSymbolDetailTap,
              onGenerateSummary: handleGenerateSummary
            )
            .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
            .listRowSeparator(.hidden)
          }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
      }
    }
  }

  private func applyCachedSnapshotIfAvailable() {
    guard loadedRepoPath != project.repoURL.standardizedFileURL.path else { return }
    guard let snapshot = ExploreRepositorySnapshotCache.shared.snapshot(for: project.repoURL) else {
      return
    }
    apply(snapshot, repoPath: project.repoURL.standardizedFileURL.path)
  }

  private func apply(_ snapshot: ExploreRepositorySnapshot, repoPath: String) {
    fileTree = snapshot.fileTree
    codemapEntries = snapshot.codemapEntries
    expandedPaths = []
    loadedRepoPath = repoPath
    isLoading = false
  }

  private func toggleExpansion(for path: String) {
    if expandedPaths.contains(path) {
      expandedPaths.remove(path)
    } else {
      expandedPaths.insert(path)
    }
  }

  private func loadRepositorySnapshotIfNeeded() async {
    let repoPath = project.repoURL.standardizedFileURL.path
    guard loadedRepoPath != repoPath else { return }

    if let cached = ExploreRepositorySnapshotCache.shared.snapshot(for: project.repoURL) {
      apply(cached, repoPath: repoPath)
      return
    }

    isLoading = true
    defer { isLoading = false }

    guard let workspace = project.workspace else {
      fileTree = []
      codemapEntries = [:]
      expandedPaths = []
      loadedRepoPath = repoPath
      return
    }

    let repoURL = project.repoURL
    let codemapDir = CodemapStore.defaultDirectory(forWorkspace: workspace)
    let snapshot = await Task.detached(priority: .utility) {
      ExploreRepositorySnapshotLoader.load(repoURL: repoURL, codemapDirectory: codemapDir)
    }.value

    ExploreRepositorySnapshotCache.shared.store(snapshot, for: repoURL)
    apply(snapshot, repoPath: repoPath)
  }

  private func handleFileTap(_ path: String) {
    whyGeneratedFile = path
    whyGeneratedExplanation = nil
    whyGeneratedReason = nil
    loadingWhyGenerated = true
    showWhyGenerated = true
    Task { await loadWhyGenerated() }
  }

  private func handleSummaryTap(_ path: String, summary: String) {
    summaryPopoverFile = path
    summaryPopoverText = summary
    showSummaryPopover = true
  }

  private func handleSymbolDetailTap(_ entry: CodemapEntry) {
    symbolDetailEntry = entry
    showSymbolDetailPopover = true
  }

  private func handleGenerateSummary(_ path: String) {
    Task { await generateSummary(for: path) }
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
    let (result, reason) = await FileExplainer.whyGenerated(
      file: file,
      repoURL: project.repoURL,
      commits: commits
    )
    await MainActor.run {
      self.whyGeneratedExplanation = result
      self.whyGeneratedReason = reason
      self.loadingWhyGenerated = false
    }
  }

  private func generateSummary(for relativePath: String) async {
    self.loadingSummary = true
    let commits: [SessionCommit]
    switch sessionScope {
    case .lastSession:
      commits = project.sessions.last?.commits ?? []
    case .allSessions:
      commits = project.sessions.flatMap(\.commits)
    }
    let (result, reason) = await FileExplainer.explain(
      file: relativePath,
      repoURL: project.repoURL,
      commits: commits
    )
    await MainActor.run {
      if let summary = result {
        self.summaryPopoverFile = relativePath
        self.summaryPopoverText = summary
        self.summaryPopoverReason = nil
        self.showSummaryPopover = true
        self.loadingSummary = false
      } else {
        self.summaryPopoverFile = relativePath
        self.summaryPopoverText = nil
        self.summaryPopoverReason = reason
        self.showSummaryPopover = true
        self.loadingSummary = false
      }
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

  /// Aggregated placeholder for a folder that has children but no stored
  /// folder-level summary.
  var folderSummary: String? {
    guard isDirectory else { return nil }
    let kids = children.filter { !$0.isDirectory }
    if kids.isEmpty { return nil }
    return "\(kids.count) source file\(kids.count == 1 ? "" : "s") in this folder"
  }
}

// MARK: - ExploreVisibleRow

/// A flattened, lazily-rendered row in the Explore file tree.
struct ExploreVisibleRow: Identifiable {
  let node: FileTreeNode
  let depth: Int

  var id: String { node.relativePath }

  static func visibleRows(
    in roots: [FileTreeNode],
    expandedPaths: Set<String>
  ) -> [ExploreVisibleRow] {
    var rows: [ExploreVisibleRow] = []
    append(from: roots, depth: 0, expandedPaths: expandedPaths, into: &rows)
    return rows
  }

  private static func append(
    from nodes: [FileTreeNode],
    depth: Int,
    expandedPaths: Set<String>,
    into rows: inout [ExploreVisibleRow]
  ) {
    for node in nodes {
      rows.append(ExploreVisibleRow(node: node, depth: depth))
      if node.isDirectory,
        !node.children.isEmpty,
        expandedPaths.contains(node.relativePath)
      {
        append(from: node.children, depth: depth + 1, expandedPaths: expandedPaths, into: &rows)
      }
    }
  }
}

// MARK: - FileTreeRowView

struct FileTreeRowView: View {
  let node: FileTreeNode
  let depth: Int
  let isExpanded: Bool
  let codemapEntries: [String: CodemapEntry]
  let onToggleExpansion: (String) -> Void
  let onFileTap: (String) -> Void
  let onSummaryTap: (String, String) -> Void
  let onSymbolDetailTap: (CodemapEntry) -> Void
  let onGenerateSummary: (String) -> Void

  private let rowHeight: CGFloat = 44

  var body: some View {
    HStack(spacing: 8) {
      if node.isDirectory, !node.children.isEmpty {
        Button {
          onToggleExpansion(node.relativePath)
        } label: {
          Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(width: 12)
        }
        .buttonStyle(.plain)
      } else {
        Color.clear.frame(width: 12, height: 1)
      }

      iconView

      if node.isDirectory {
        Text(node.name)
          .font(.system(.body, design: .default))
          .fontWeight(.medium)
          .foregroundStyle(.primary)
          .lineLimit(1)
      } else {
        Button {
          onFileTap(node.relativePath)
        } label: {
          Text(node.name)
            .font(.system(.body, design: .default))
            .fontWeight(.regular)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .buttonStyle(.plain)
      }

      Spacer()

      if !node.isDirectory, let lang = node.language {
        LanguageBadge(language: lang)
      }

      summaryButton
      detailsButton
    }
    .padding(.leading, CGFloat(depth * 16))
    .frame(height: rowHeight)
    .contentShape(Rectangle())
  }

  @ViewBuilder
  private var iconView: some View {
    if node.isDirectory {
      Image(systemName: "folder")
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
  private var detailsButton: some View {
    if let entry = codemapEntries[node.relativePath] {
      Button {
        onSymbolDetailTap(entry)
      } label: {
        Image(systemName: "list.bullet")
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
      .buttonStyle(.plain)
    }
  }

  @ViewBuilder
  var summaryButton: some View {
    if let entry = codemapEntries[node.relativePath],
      let summary = entry.summary,
      !summary.isEmpty
    {
      Button {
        onSummaryTap(node.relativePath, summary)
      } label: {
        HStack(spacing: 4) {
          Text(summary)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
          Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
      }
      .buttonStyle(.plain)
    } else if node.isDirectory, let folderSummary = node.folderSummary {
      Text(folderSummary)
        .font(.caption)
        .foregroundStyle(.tertiary)
        .italic()
        .lineLimit(1)
    } else {
      Button {
        onGenerateSummary(node.relativePath)
      } label: {
        Label("Generate Summary", systemImage: "sparkles")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
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
    case .haskell: return "Hs"
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
    case .haskell: return .purple
    }
  }
}

// MARK: - CodemapFileSystem

/// Reads `repoURL` and produces a tree of `FileTreeNode`s mirroring the
/// source directory layout under `rootURL`.
struct CodemapFileSystem {
  let rootURL: URL
  private let fileManager = FileManager.default

  /// Build the full tree from the repo root.
  func buildTree() -> [FileTreeNode] {
    let keys = topLevelKeys()
    let nodes = keys.map { buildNode(relativePath: $0) }
    return sortNodes(nodes)
  }

  /// Build a tree containing only supported source files and their parent folders.
  func buildSourceTree() -> [FileTreeNode] {
    pruneSourceNodes(buildTree())
  }

  private func pruneSourceNodes(_ nodes: [FileTreeNode]) -> [FileTreeNode] {
    nodes.compactMap { node in
      if node.isDirectory {
        let children = pruneSourceNodes(node.children)
        guard !children.isEmpty else { return nil }
        return FileTreeNode(
          relativePath: node.relativePath,
          isDirectory: true,
          language: nil,
          children: children
        )
      }
      guard CodemapLanguage.forRelativePath(node.relativePath) != nil else { return nil }
      return node
    }
  }

  /// Top-level relative paths immediately under the repo root.
  private func topLevelKeys() -> [String] {
    childRelativePaths(
      under: "",
      url: rootURL,
      isTopLevel: true
    )
  }

  private func buildNode(relativePath: String) -> FileTreeNode {
    let url = rootURL.appendingPathComponent(relativePath)
    guard let entry = directoryEntry(at: url) else {
      return FileTreeNode(
        relativePath: relativePath,
        isDirectory: false,
        language: CodemapLanguage.forRelativePath(relativePath),
        children: []
      )
    }

    if entry.isDirectory {
      let childKeys = childRelativePaths(under: relativePath, url: url)
      let children = childKeys.map { buildNode(relativePath: $0) }
      return FileTreeNode(
        relativePath: relativePath,
        isDirectory: true,
        language: nil,
        children: sortNodes(children)
      )
    }

    return FileTreeNode(
      relativePath: relativePath,
      isDirectory: false,
      language: CodemapLanguage.forRelativePath(relativePath),
      children: []
    )
  }

  private func childRelativePaths(
    under parent: String,
    url: URL,
    isTopLevel: Bool = false
  ) -> [String] {
    guard
      let contents = try? fileManager.contentsOfDirectory(
        at: url,
        includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return []
    }

    return contents.compactMap { childURL in
      guard let entry = directoryEntry(at: childURL) else { return nil }
      let name = childURL.lastPathComponent
      guard
        RepositoryWalkRules.shouldInclude(
          name: name,
          isDirectory: entry.isDirectory,
          isTopLevel: isTopLevel
        )
      else {
        return nil
      }
      return parent.isEmpty ? name : "\(parent)/\(name)"
    }
  }

  private func directoryEntry(at url: URL) -> (isDirectory: Bool, isSymbolicLink: Bool)? {
    guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    else {
      return nil
    }
    if values.isSymbolicLink == true {
      return nil
    }
    return (values.isDirectory == true, false)
  }

  private func sortNodes(_ nodes: [FileTreeNode]) -> [FileTreeNode] {
    let dirs = nodes.filter { $0.isDirectory }.sorted {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
    let files = nodes.filter { !$0.isDirectory }.sorted {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
    return dirs + files
  }
}

// MARK: - SummaryPopover

/// A popover that shows the full codemap summary for a file.
/// Mirrors the layout of ``WhyGeneratedPopover``.
struct SummaryPopover: View {
  let fileName: String
  let summary: String?
  let reason: ExplainUnavailableReason?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label("Summary", systemImage: "text.alignleft")
          .font(.headline)
        Spacer()
        Button("Close") {
          // popover dismiss handled by isPresented
        }
        .buttonStyle(.plain)
        .font(.caption)
      }

      if let summary = summary {
        Text(summary)
          .font(.callout)
          .textSelection(.enabled)
          .frame(maxWidth: 400, alignment: .leading)
      } else if let reason = reason {
        HStack(alignment: .top, spacing: 8) {
          Image(systemName: "exclamationmark.triangle")
            .font(.callout)
            .foregroundStyle(.orange)
          Text(reason.message)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 400, alignment: .leading)
      } else {
        Text("No summary available.")
          .font(.callout)
          .foregroundStyle(.secondary)
          .frame(maxWidth: 400, alignment: .leading)
      }
    }
    .padding(16)
    .frame(width: 440)
  }
}

// MARK: - CodemapSymbolKind + color

extension CodemapSymbolKind {
  /// Color used for symbol kind badges in the symbol detail popover.
  static func color(for kind: CodemapSymbolKind) -> Color {
    switch kind {
    case .function, .method: return .blue
    case .class: return .purple
    case .interface: return .mint
    case .struct: return .orange
    case .enum: return .green
    case .trait: return .pink
    case .module: return .teal
    case .type: return .indigo
    case .property: return .cyan
    case .macro: return .yellow
    case .impl: return .brown
    case .extension: return .gray
    case .constant: return .orange
    }
  }
}

// MARK: - SymbolDetailPopover

/// A popover that shows all symbols and imports for a file.
struct SymbolDetailPopover: View {
  let entry: CodemapEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label("Symbol Details", systemImage: "list.bullet")
          .font(.headline)
        Spacer()
        Button("Close") {
          // popover dismiss handled by isPresented
        }
        .buttonStyle(.plain)
        .font(.caption)
      }

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 8) {
          // Symbols section
          if !entry.symbols.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
              Text("Symbols")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
              ForEach(entry.symbols, id: \.name) { symbol in
                HStack(spacing: 8) {
                  Text(symbolKindLabel(symbol.kind))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Self.color(for: symbol.kind).opacity(0.15))
                    .foregroundStyle(Self.color(for: symbol.kind))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                  Text(symbol.name)
                    .font(.callout)
                    .textSelection(.enabled)
                  Spacer()
                  Text("L\(symbol.line)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
              }
            }
          }

          // Imports section
          if !entry.imports.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
              Text("Imports")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
              ForEach(entry.imports, id: \.raw) { import_ in
                HStack(spacing: 8) {
                  Text(import_.raw)
                    .font(.callout)
                    .textSelection(.enabled)
                  Spacer()
                  Text("L\(import_.line)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
              }
            }
          }

          if entry.symbols.isEmpty && entry.imports.isEmpty {
            Text("No symbols or imports found.")
              .font(.caption)
              .foregroundStyle(.tertiary)
              .italic()
          }
        }
      }
      .frame(maxHeight: 400)
    }
    .padding(16)
    .frame(width: 440)
  }

  private func symbolKindLabel(_ kind: CodemapSymbolKind) -> String {
    switch kind {
    case .function: return "func"
    case .method: return "meth"
    case .class: return "class"
    case .interface: return "iface"
    case .struct: return "struct"
    case .enum: return "enum"
    case .trait: return "trait"
    case .module: return "mod"
    case .type: return "type"
    case .property: return "prop"
    case .macro: return "macro"
    case .impl: return "impl"
    case .extension: return "ext"
    case .constant: return "const"
    }
  }

  private static func color(for kind: CodemapSymbolKind) -> Color {
    CodemapSymbolKind.color(for: kind)
  }
}
