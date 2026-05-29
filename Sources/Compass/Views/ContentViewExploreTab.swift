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

  @State private var summaryPopoverFile: String? = nil
  @State private var summaryPopoverText: String? = nil
  @State private var showSummaryPopover = false

  @State private var loadingSummary = false

  @State private var symbolDetailEntry: CodemapEntry? = nil
  @State private var showSymbolDetailPopover = false

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
                },
                onSummaryTap: { path, summary in
                  summaryPopoverFile = path
                  summaryPopoverText = summary
                  showSummaryPopover = true
                },
                onSymbolDetailTap: { entry in
                  symbolDetailEntry = entry
                  showSymbolDetailPopover = true
                },
                onGenerateSummary: { path in
                  Task { await generateSummary(for: path) }
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
    .popover(isPresented: $showSummaryPopover) {
      if let file = summaryPopoverFile, let text = summaryPopoverText {
        SummaryPopover(
          fileName: (file as NSString).lastPathComponent,
          summary: text
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

  private func generateSummary(for relativePath: String) async {
    let commits: [SessionCommit]
    switch sessionScope {
    case .lastSession:
      commits = project.sessions.last?.commits ?? []
    case .allSessions:
      commits = project.sessions.flatMap(\.commits)
    }
    let result = await FileExplainer.explain(
      file: relativePath,
      repoURL: project.repoURL,
      commits: commits
    )
    await MainActor.run {
      if let summary = result {
        self.summaryPopoverFile = relativePath
        self.summaryPopoverText = summary
        self.showSummaryPopover = true
      }
      self.loadingSummary = false
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

// MARK: - FileTreeRowView

struct FileTreeRowView: View {
  let node: FileTreeNode
  let codemapEntries: [String: CodemapEntry]
  let indentLevel: Int
  let onFileTap: (String) -> Void
  let onSummaryTap: (String, String) -> Void
  let onSymbolDetailTap: (CodemapEntry) -> Void
  let onGenerateSummary: (String) -> Void
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
            onFileTap: onFileTap,
            onSummaryTap: onSummaryTap,
            onSymbolDetailTap: onSymbolDetailTap,
            onGenerateSummary: onGenerateSummary
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

        // Summary — tap to open full-text popover
        summaryButton

        // Symbol details — tap to open symbol/import popover
        detailsButton
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
       !summary.isEmpty {
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
      Button { onGenerateSummary(node.relativePath) } label: {
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

// MARK: - SummaryPopover

/// A popover that shows the full codemap summary for a file.
/// Mirrors the layout of ``WhyGeneratedPopover``.
struct SummaryPopover: View {
  let fileName: String
  let summary: String

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

      Text(summary)
        .font(.callout)
        .textSelection(.enabled)
        .frame(maxWidth: 400, alignment: .leading)
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
