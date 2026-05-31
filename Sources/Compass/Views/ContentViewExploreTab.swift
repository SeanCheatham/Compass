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
struct ExploreTab: View, Equatable {
  let repoURL: URL
  let workspace: CompassWorkspace?
  let isActive: Bool
  let sessionRecords: () -> [SessionRecord]
  let onLoadArchivedSessions: () async -> Void
  @State private var fileTree: [FileTreeNode] = []
  @State private var codemapEntries: [String: CodemapEntry] = [:]
  @State private var visibleRows: [ExploreVisibleRow] = []
  @State private var isLoading = true
  @State private var whyGeneratedFile: String? = nil
  @State private var showWhyGenerated = false
  @State private var whyGeneratedExplanation: String? = nil
  @State private var whyGeneratedReason: ExplainUnavailableReason? = nil
  @State private var loadingWhyGenerated = false
  @State private var recentChangeSummaries: [String] = []

  @State private var summaryPopoverFile: String? = nil
  @State private var summaryPopoverText: String? = nil
  @State private var summaryPopoverReason: ExplainUnavailableReason? = nil
  @State private var showSummaryPopover = false

  @State private var loadingSummary = false

  @State private var symbolDetailEntry: CodemapEntry? = nil
  @State private var showSymbolDetailPopover = false

  @State private var showQAPopover = false
  @State private var qaQuestion = ""
  @State private var qaAnswer: RepoQnA.Answer?
  @State private var qaReason: ExplainUnavailableReason?
  @State private var loadingQA = false

  @State private var sessionScope: SessionScope = .lastSession
  @State private var expandedPaths: Set<String> = []
  @State private var loadedRepoPath: String?
  @State private var loadingRepoPath: String?

  static func == (lhs: ExploreTab, rhs: ExploreTab) -> Bool {
    lhs.isActive == rhs.isActive
      && lhs.repoURL == rhs.repoURL
      && lhs.workspace?.compassURL == rhs.workspace?.compassURL
  }

  var body: some View {
    ZStack(alignment: .topLeading) {
      exploreContent
      Color.clear
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
        .task(id: repoURL.standardizedFileURL.path) {
          guard isActive else { return }
          await loadRepositorySnapshotIfNeeded()
        }
    }
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
        SymbolDetailPopover(
          entry: entry, fileURL: repoURL.appendingPathComponent(entry.relativePath))
      }
    }
    .popover(isPresented: $showWhyGenerated) {
      if let file = whyGeneratedFile {
        WhyGeneratedPopover(
          fileName: (file as NSString).lastPathComponent,
          fileURL: repoURL.appendingPathComponent(file),
          explanation: $whyGeneratedExplanation,
          reason: $whyGeneratedReason,
          isLoading: $loadingWhyGenerated
        )
      }
    }
    .popover(isPresented: $showQAPopover) {
      QnAPopoverExplore(
        question: $qaQuestion,
        answer: $qaAnswer,
        reason: $qaReason,
        isLoading: $loadingQA,
        repoURL: repoURL,
        commits: commitsForSessionScope()
      )
    }
    .onAppear {
      guard isActive else { return }
      applyCachedSnapshotIfAvailable()
      Task { await loadRecentChangeSummaries() }
    }
    .onChange(of: isActive) { _, active in
      guard active else { return }
      applyCachedSnapshotIfAvailable()
      Task { await loadRecentChangeSummaries() }
    }
    .onChange(of: sessionScope) { _, _ in
      Task { await loadRecentChangeSummaries() }
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
        recentChangesHeader
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
              onGenerateSummary: handleGenerateSummary,
              onWhyGeneratedTap: handleFileTap
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
    guard loadedRepoPath != repoURL.standardizedFileURL.path else { return }
    guard let snapshot = ExploreRepositorySnapshotCache.shared.snapshot(for: repoURL) else {
      return
    }
    apply(snapshot, repoPath: repoURL.standardizedFileURL.path)
  }

  private func apply(_ snapshot: ExploreRepositorySnapshot, repoPath: String) {
    fileTree = snapshot.fileTree
    codemapEntries = snapshot.codemapEntries
    expandedPaths = []
    refreshVisibleRows()
    loadedRepoPath = repoPath
    isLoading = false
  }

  private func refreshVisibleRows() {
    visibleRows = ExploreVisibleRow.visibleRows(in: fileTree, expandedPaths: expandedPaths)
  }

  private func toggleExpansion(for path: String) {
    if expandedPaths.contains(path) {
      expandedPaths.remove(path)
    } else {
      expandedPaths.insert(path)
    }
    refreshVisibleRows()
  }

  @MainActor
  private func loadRepositorySnapshotIfNeeded() async {
    let repoPath = repoURL.standardizedFileURL.path
    guard loadedRepoPath != repoPath else {
      isLoading = false
      return
    }
    guard loadingRepoPath != repoPath else { return }

    if let cached = ExploreRepositorySnapshotCache.shared.snapshot(for: repoURL) {
      apply(cached, repoPath: repoPath)
      return
    }

    loadingRepoPath = repoPath
    if fileTree.isEmpty {
      isLoading = true
    }

    guard let workspace else {
      fileTree = []
      codemapEntries = [:]
      expandedPaths = []
      visibleRows = []
      loadedRepoPath = repoPath
      loadingRepoPath = nil
      isLoading = false
      return
    }

    let codemapDir = CodemapStore.defaultDirectory(forWorkspace: workspace)
    let snapshot = await Task.detached(priority: .utility) {
      ExploreRepositorySnapshotLoader.load(repoURL: repoURL, codemapDirectory: codemapDir)
    }.value

    guard !Task.isCancelled else { return }
    guard repoURL.standardizedFileURL.path == repoPath else { return }

    ExploreRepositorySnapshotCache.shared.store(snapshot, for: repoURL)
    apply(snapshot, repoPath: repoPath)
    loadingRepoPath = nil
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
    HStack(spacing: 8) {
      Button {
        qaQuestion = ""
        qaAnswer = nil
        qaReason = nil
        showQAPopover = true
      } label: {
        Label("Ask a Question", systemImage: "questionmark.circle")
          .font(.callout)
      }
      .buttonStyle(.bordered)
      .controlSize(.small)

      Spacer()

      Picker("Session Scope", selection: $sessionScope) {
        Text("Last Session").tag(SessionScope.lastSession)
        Text("All Sessions").tag(SessionScope.allSessions)
      }
      .pickerStyle(.menu)
      .onChange(of: sessionScope) { _, scope in
        guard scope == .allSessions else { return }
        Task {
          await onLoadArchivedSessions()
        }
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .background(Color(nsColor: .controlBackgroundColor))
  }

  private func loadWhyGenerated() async {
    guard let file = whyGeneratedFile else { return }
    let commits = commitsForSessionScope()
    let (result, reason) = await FileExplainer.whyGenerated(
      file: file,
      repoURL: repoURL,
      commits: commits
    )
    await MainActor.run {
      self.whyGeneratedExplanation = result
      self.whyGeneratedReason = reason
      self.loadingWhyGenerated = false
    }
  }

  private func loadRecentChangeSummaries() async {
    if #available(macOS 26.0, *) {
      let commits = commitsForSessionScope()
      guard !commits.isEmpty else {
        await MainActor.run { self.recentChangeSummaries = [] }
        return
      }
      guard FoundationModelsAvailability.isAvailable else {
        await MainActor.run { self.recentChangeSummaries = [] }
        return
      }
      var summaries: [String] = []
      await withTaskGroup(of: String?.self) { group in
        for commit in commits {
          group.addTask {
            let diff = await CommitExplainer.gitDiff(sha: commit.sha, repoURL: self.repoURL)
            let trimmedDiff = diff.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedDiff.isEmpty else { return nil }
            return await CommitNarrator.narrate(commit: commit, diff: trimmedDiff)
          }
        }
        for await result in group {
          if let text = result {
            summaries.append(text)
          }
        }
      }
      await MainActor.run { self.recentChangeSummaries = summaries }
    }
  }

  private var recentChangesHeader: some View {
    Group {
      if recentChangeSummaries.isEmpty {
        EmptyView()
      } else {
        VStack(alignment: .leading, spacing: 4) {
          Text("Recent Changes")
            .font(.headline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
          ForEach(Array(recentChangeSummaries.enumerated()), id: \.offset) { _, summary in
            Text(summary)
              .font(.caption)
              .foregroundStyle(.secondary)
              .padding(.horizontal, 12)
              .lineLimit(1)
          }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
      }
    }
  }

  private func commitsForSessionScope() -> [SessionCommit] {
    let sessions = sessionRecords()
    switch sessionScope {
    case .lastSession:
      return sessions.last?.commits ?? []
    case .allSessions:
      return sessions.flatMap(\.commits)
    }
  }

  private func generateSummary(for relativePath: String) async {
    self.loadingSummary = true
    let commits = commitsForSessionScope()
    let (result, reason) = await FileExplainer.explain(
      file: relativePath,
      repoURL: repoURL,
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
struct FileTreeNode: Identifiable, Equatable, Sendable {
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
  let onWhyGeneratedTap: (String) -> Void

  private let rowHeight: CGFloat = 44
  private let summaryPreviewLimit = 180

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
    .contextMenu {
      if !node.isDirectory {
        Button {
          onWhyGeneratedTap(node.relativePath)
        } label: {
          Label("Why was this generated?", systemImage: "questionmark.circle")
        }
      }
    }
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
          Text(summaryPreview(summary))
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

  private func summaryPreview(_ summary: String) -> String {
    let singleLine =
      summary
      .replacingOccurrences(of: "\n", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard singleLine.count > summaryPreviewLimit else { return singleLine }
    return singleLine.prefix(summaryPreviewLimit - 1)
      .trimmingCharacters(in: .whitespacesAndNewlines) + "…"
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
    case .go: return .cyan
    case .rust: return .orange
    }
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
  let fileURL: URL?

  init(entry: CodemapEntry, fileURL: URL? = nil) {
    self.entry = entry
    self.fileURL = fileURL
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label("Symbol Details", systemImage: "list.bullet")
          .font(.headline)
        Spacer()
        if let url = fileURL {
          Button {
            NSWorkspace.shared.open(url)
          } label: {
            Label("Open in Xcode", systemImage: "chevron.left.forwardslash.chevron.right")
              .font(.caption)
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }
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
              ForEach(entry.imports, id: \.raw) { `import` in
                HStack(spacing: 8) {
                  Text(`import`.raw)
                    .font(.callout)
                    .textSelection(.enabled)
                  Spacer()
                  Text("L\(`import`.line)")
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

// MARK: - QnAPopoverExplore

/// Q&A popover for the Explore tab, backed by `RepoQnA.answer`.
/// Mirrors the layout of ``QnAPopover`` in the Plan tab.
struct QnAPopoverExplore: View {
  @Binding var question: String
  @Binding var answer: RepoQnA.Answer?
  @Binding var reason: ExplainUnavailableReason?
  @Binding var isLoading: Bool

  let repoURL: URL
  let commits: [SessionCommit]

  @State private var availabilityError = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label("Ask About Changes", systemImage: "questionmark.circle")
          .font(.headline)
        Spacer()
      }

      if availabilityError {
        Label(
          "Foundation Models is unavailable on this device.",
          systemImage: "exclamationmark.triangle"
        )
        .font(.caption)
        .foregroundStyle(.orange)
      }

      HStack(spacing: 8) {
        TextField("Ask about this repository…", text: $question)
          .textFieldStyle(.roundedBorder)
          .font(.callout)
          .onChange(of: question) { _, _ in answer = nil }

        Button("Ask") {
          Task { await submitQuestion() }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
      }

      if isLoading {
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text("Generating answer...")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } else if let answer {
        VStack(alignment: .leading, spacing: 8) {
          HStack(alignment: .top) {
            ScrollView {
              Text(answer.text)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)

            Button {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(answer.text, forType: .string)
            } label: {
              Image(systemName: "doc.on.clipboard")
                .font(.caption)
            }
            .buttonStyle(.plain)
            .help("Copy answer to clipboard")
          }

          if !answer.sources.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
              Text("Sources:")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
              ForEach(answer.sources, id: \.self) { source in
                Text(source)
                  .font(.caption.monospaced())
                  .foregroundStyle(.secondary)
              }
            }
          }
        }
      }
    }
    .padding(16)
    .frame(width: 420)
  }

  private func submitQuestion() async {
    let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    isLoading = true
    answer = nil
    availabilityError = false
    if #available(macOS 26.0, *) {
      let result = await RepoQnA.answer(question: trimmed, repoURL: repoURL, commits: commits)
      answer = result
      if result == nil { availabilityError = true }
    }
    isLoading = false
  }
}
