import AppKit
import SwiftUI

extension PlanSessionHistoryItem {
  var canExplore: Bool {
    status == .succeeded && !commits.isEmpty
  }

  var canTour: Bool { canExplore }
  var canQnA: Bool { canExplore }
}

struct ExploreButton<PopoverContent: View>: View {
  let condition: Bool
  let label: String
  let systemImage: String
  let repoURL: URL
  let content: () -> PopoverContent

  @State private var showingPopover = false

  var body: some View {
    if condition {
      Button {
        showingPopover = true
      } label: {
        Label(label, systemImage: systemImage)
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
      .popover(isPresented: $showingPopover) {
        content()
      }
    }
  }
}

struct ExplainChangesButton: View {
  let item: PlanSessionHistoryItem
  let repoURL: URL

  var body: some View {
    ExploreButton(
      condition: item.canExplore,
      label: "Explain Changes",
      systemImage: "book.pages",
      repoURL: repoURL
    ) {
      CommitExplanationPopover(
        item: item,
        repoURL: repoURL
      )
    }
  }
}

struct CommitExplanationPopover: View {
  let item: PlanSessionHistoryItem
  let repoURL: URL

  @State private var fetchedSummary: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label("Changes Summary", systemImage: "book.pages")
          .font(.headline)
        Spacer()
        Button("Close") {
          // popover dismiss handled by isPresented
        }
        .buttonStyle(.plain)
        .font(.caption)
      }

      if let text = fetchedSummary {
        Text(text)
          .font(.callout)
          .textSelection(.enabled)
          .frame(maxWidth: 400, alignment: .leading)
      } else {
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text("Generating summary...")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding(16)
    .frame(width: 440)
    .task {
      await loadExplanation()
    }
  }

  private func loadExplanation() async {
    guard fetchedSummary == nil else { return }

    guard !item.commits.isEmpty else { return }

    // Delegate diff fetching and summary generation to CommitTourGenerator,
    // which handles the same first/last commit logic internally.
    fetchedSummary = await CommitTourGenerator.generateTour(
      commits: item.commits,
      repoURL: repoURL
    )
  }
}

struct PerCommitNarrativesButton: View {
  let item: PlanSessionHistoryItem
  let repoURL: URL

  var body: some View {
    ExploreButton(
      condition: item.canExplore,
      label: "Per-Commit",
      systemImage: "list.bullet.rectangle",
      repoURL: repoURL
    ) {
      PerCommitNarrativesPopover(item: item, repoURL: repoURL)
    }
  }
}

struct PerCommitNarrativesPopover: View {
  let item: PlanSessionHistoryItem
  let repoURL: URL

  @State private var narratives: [CommitNarrative] = []
  @State private var isLoading = false

  /// Tracks which commits have finished loading (true = done, false = still loading).
  @State private var loadedFlags: [Bool] = []

  struct CommitNarrative: Identifiable {
    let id = UUID()
    let sha: String
    let subject: String
    var text: String?
    var availabilityError = false
    var narrator: String?
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label("Per-Commit Narratives", systemImage: "list.bullet.rectangle")
          .font(.headline)
        Spacer()
        Button("Close") {
          // popover dismiss handled by isPresented
        }
        .buttonStyle(.plain)
        .font(.caption)
      }

      if isLoading {
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text("Generating narratives...")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } else if narratives.isEmpty {
        Text("No narratives available.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(narratives.enumerated()), id: \.element.id) { index, narrative in
              VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                  Text(narrative.sha)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                  Text(narrative.subject)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                  Spacer()
                  let loaded = index < loadedFlags.count && loadedFlags[index]
                  if !loaded {
                    ProgressView()
                      .controlSize(.mini)
                  }
                }

                if let narrator = narrative.narrator {
                  Text(narrator)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .italic()
                    .lineLimit(1)
                }

                if narrative.availabilityError {
                  Label(
                    "Foundation Models is unavailable on this device.",
                    systemImage: "exclamationmark.triangle"
                  )
                  .font(.caption)
                  .foregroundStyle(.orange)
                } else if let text = narrative.text {
                  Text(text)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                } else {
                  Text("Summary unavailable.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
              }
              .padding(8)
              .background(.black.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
            }
          }
        }
        .frame(maxHeight: 400)
      }
    }
    .padding(16)
    .frame(width: 440)
    .task {
      await loadNarratives()
    }
  }

  private func loadNarratives() async {
    guard !item.commits.isEmpty else {
      isLoading = false
      return
    }

    isLoading = true

    let initialNarratives: [CommitNarrative] = item.commits.map { commit in
      CommitNarrative(sha: String(commit.sha.prefix(7)), subject: commit.subject)
    }
    narratives = initialNarratives
    loadedFlags = Array(repeating: false, count: item.commits.count)

    await withTaskGroup(of: (Int, CommitNarrative?).self) { group in
      for (index, commit) in item.commits.enumerated() {
        group.addTask {
          if #available(macOS 26.0, *) {
            // Fetch the diff for both narrator and explainer (runs in parallel with FM call).
            let diff = await CommitExplainer.gitDiff(sha: commit.sha, repoURL: repoURL)
            let trimmedDiff = diff.trimmingCharacters(in: .whitespacesAndNewlines)

            var narrative = initialNarratives[index]
            if !trimmedDiff.isEmpty {
              narrative.narrator = await CommitNarrator.narrate(commit: commit, diff: trimmedDiff)
            }

            // Explainer task.
            let (text, _) = await CommitExplainer.explain(commit: commit, repoURL: repoURL)
            narrative.text = text
            narrative.availabilityError = (text == nil)
            return (index, narrative)
          } else {
            var narrative = initialNarratives[index]
            narrative.availabilityError = true
            return (index, narrative)
          }
        }
      }
      for await (index, narrative) in group {
        if let narrative {
          narratives[index] = narrative
          loadedFlags[index] = true
        }
      }
    }

    isLoading = false
  }
}

struct CommitTourRow: View {
  let item: PlanSessionHistoryItem
  let repoURL: URL

  @State private var tourText: String?
  @State private var isLoading = false
  @State private var tourAvailabilityError = false
  @State private var isMonospaced = false

  var body: some View {
    Group {
      if isLoading {
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text("Generating tour...")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        if tourAvailabilityError {
          Label(
            "Foundation Models is unavailable on this device.",
            systemImage: "exclamationmark.triangle"
          )
          .font(.caption)
          .foregroundStyle(.orange)
        }
      } else if let tourText {
        LabeledHistoryBlock(title: "What We Built", systemImage: "lightbulb") {
          HStack(alignment: .top) {
            Text(tourText)
              .font(isMonospaced ? .callout.monospaced() : .callout)
              .foregroundStyle(.primary)
              .textSelection(.enabled)
            VStack(alignment: .trailing, spacing: 4) {
              Button {
                isMonospaced.toggle()
              } label: {
                Image(systemName: isMonospaced ? "textformat" : "textformat.abc")
                  .font(.caption)
              }
              .buttonStyle(.plain)
              .help("Toggle monospaced font")
              Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(tourText, forType: .string)
              } label: {
                Image(systemName: "doc.on.clipboard")
                  .font(.caption)
              }
              .buttonStyle(.plain)
              .help("Copy to clipboard")
            }
          }
        }
      } else if item.canTour {
        EmptyView()
      }
    }
    .task { startTour() }
  }

  func startTour() {
    guard item.canTour, tourText == nil else { return }
    isLoading = true
    Task {
      await loadTour()
      isLoading = false
    }
  }

  private func loadTour() async {
    tourAvailabilityError = false
    if #available(macOS 26.0, *) {
      let result = await CommitTourGenerator.generateTour(commits: item.commits, repoURL: repoURL)
      tourText = result
      if result == nil { tourAvailabilityError = true }
    }
  }
}

struct ExploreFilesButton: View {
  let item: PlanSessionHistoryItem
  let repoURL: URL

  var body: some View {
    ExploreButton(
      condition: item.canExplore,
      label: "Explore Files",
      systemImage: "doc.text.magnifyingglass",
      repoURL: repoURL
    ) {
      ExploreFilesPopover(item: item, repoURL: repoURL)
    }
  }
}

struct ArchitectureGraphButton: View {
  let item: PlanSessionHistoryItem
  let repoURL: URL

  var body: some View {
    ExploreButton(
      condition: item.canExplore,
      label: "Architecture",
      systemImage: "arrow.triangle.branch",
      repoURL: repoURL
    ) {
      ArchitectureGraphPopover(item: item, repoURL: repoURL)
    }
  }
}

struct ArchitectureGraphPopover: View {
  let item: PlanSessionHistoryItem
  let repoURL: URL

  @State private var graphText: String?
  @State private var explanation: String?
  @State private var isLoading = false
  @State private var availabilityError = false
  @State private var svgExportPath: String?
  @State private var svgExportError: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label("Architecture Graph", systemImage: "arrow.triangle.branch")
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

      if isLoading {
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text("Analyzing architecture...")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } else {
        if let graphText {
          VStack(alignment: .leading, spacing: 8) {
            Text("Structure")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
            ScrollView {
              Text(graphText)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 180)
            .padding(8)
            .background(.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 6))
          }
        }

        if let explanation {
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Text("Explanation")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
              Spacer()
              Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(explanation, forType: .string)
              } label: {
                Image(systemName: "doc.on.clipboard")
                  .font(.caption)
              }
              .buttonStyle(.plain)
              .help("Copy explanation to clipboard")
            }
            ScrollView {
              Text(explanation)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 160)
          }
        }

        exportSVGButton
      }
    }
    .padding(16)
    .frame(width: 440)
    .task { await loadGraph() }
  }

  @ViewBuilder
  private var exportSVGButton: some View {
    VStack(alignment: .leading, spacing: 6) {
      Button {
        exportSVG()
      } label: {
        Label("Export SVG", systemImage: "square.and.arrow.up")
          .font(.caption)
      }
      .buttonStyle(.bordered)
      .controlSize(.small)

      if let path = svgExportPath {
        Text("Saved: \(path)")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      if let error = svgExportError {
        Text(error)
          .font(.caption2)
          .foregroundStyle(.orange)
      }
    }
  }

  private func exportSVG() {
    let result = ArchitectureGraphPopoverLogic.exportSVGState(repoURL: repoURL)
    svgExportPath = result.path
    svgExportError = result.error
  }

  private func loadGraph() async {
    isLoading = true
    availabilityError = false
    let result = await ArchitectureGraphPopoverLogic.loadGraphState(repoURL: repoURL)
    graphText = result.graphText
    explanation = result.explanation
    availabilityError = result.availabilityError
    isLoading = false
  }
}

enum ArchitectureGraphPopoverLogic {
  static func exportSVGState(repoURL: URL) -> ArchitectureGraphPopoverExportState {
    let codemapDir =
      repoURL
      .appendingPathComponent(".compass/codemap")
      .standardizedFileURL
    let viz = CodemapGraphViz(repoURL: repoURL, codemapDirectory: codemapDir)
    do {
      if let url = try viz.writeOverviewSVG() {
        return ArchitectureGraphPopoverExportState(path: url.lastPathComponent, error: nil)
      } else {
        return ArchitectureGraphPopoverExportState(
          path: nil,
          error: "Codemap is empty — no files to render."
        )
      }
    } catch {
      return ArchitectureGraphPopoverExportState(
        path: nil,
        error: "Failed: \(error.localizedDescription)"
      )
    }
  }

  static func loadGraphState(repoURL: URL) async -> ArchitectureGraphPopoverLoadState {
    let codemapDir =
      repoURL
      .appendingPathComponent(".compass/codemap")
      .standardizedFileURL
    let graph = buildGraph(codemapDirectory: codemapDir)
    let graphText = graph.textGraph()
    var explanation: String?
    var availabilityError = false

    if #available(macOS 26.0, *) {
      let result = await ArchitectureGraph.explain(graph: graph, repoURL: repoURL)
      explanation = result
      if result == nil { availabilityError = true }
    }

    return ArchitectureGraphPopoverLoadState(
      graphText: graphText,
      explanation: explanation,
      availabilityError: availabilityError
    )
  }
}

struct ArchitectureGraphPopoverExportState: Equatable {
  var path: String?
  var error: String?
}

struct ArchitectureGraphPopoverLoadState: Equatable {
  var graphText: String
  var explanation: String?
  var availabilityError: Bool
}

struct QnAButton: View {
  let item: PlanSessionHistoryItem
  let repoURL: URL

  var body: some View {
    ExploreButton(
      condition: item.canQnA,
      label: "Ask",
      systemImage: "questionmark.circle",
      repoURL: repoURL
    ) {
      QnAPopover(item: item, repoURL: repoURL)
    }
  }
}

struct QnAPopover: View {
  let item: PlanSessionHistoryItem
  let repoURL: URL

  @State private var question = ""
  @State private var answer: RepoQnA.Answer?
  @State private var isLoading = false
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
        TextField("What would you like to know?", text: $question)
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
      let result = await RepoQnA.answer(question: trimmed, repoURL: repoURL, commits: item.commits)
      answer = result
      if result == nil { availabilityError = true }
    }
    isLoading = false
  }
}

struct ExploreFilesPopover: View {
  let item: PlanSessionHistoryItem
  let repoURL: URL

  @State private var changes: [FileChange] = []
  @State private var isLoading = false
  @State private var fileCount: Int = 0

  private var groupedChanges: [(category: FileChangeCategory, changes: [FileChange])] {
    let grouped = Dictionary(grouping: changes, by: { $0.category })
    return FileChangeCategory.allCases
      .compactMap { category -> (FileChangeCategory, [FileChange])? in
        guard let cats = grouped[category], !cats.isEmpty else { return nil }
        return (
          category, cats.sorted { ($0.additions + $0.deletions) > ($1.additions + $1.deletions) }
        )
      }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label("Changed Files", systemImage: "doc.text.magnifyingglass")
          .font(.headline)
        Spacer()
        Button("Close") {
          // popover dismiss handled by isPresented
        }
        .buttonStyle(.plain)
        .font(.caption)
      }

      if isLoading {
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text("Analyzing \(fileCount) files...")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } else if changes.isEmpty {
        Text("No file changes found in these commits.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 14) {
            ForEach(groupedChanges, id: \.category) { entry in
              VStack(alignment: .leading, spacing: 5) {
                Text(entry.category.rawValue)
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.secondary)

                ForEach(entry.changes) { change in
                  ExploreFileRow(change: change, repoURL: repoURL, commits: item.commits)
                }
              }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 400)
      }
    }
    .padding(16)
    .frame(width: 480)
    .task {
      await loadChanges()
    }
  }

  private func loadChanges() async {
    guard changes.isEmpty else { return }
    isLoading = true
    defer { isLoading = false }

    // item.commits is already in newest-first order, which is what
    // changes(for:) expects — it passes newest..oldest to git internally.
    var loaded = await FileExplainer.changes(for: repoURL, commits: item.commits)

    // Enrich with codemap summaries
    let codemapDir = CodemapStore.defaultDirectory(
      forWorkspace: CompassWorkspace(repoURL: repoURL)
    )
    let store = CodemapStore(directory: codemapDir)
    for i in loaded.indices {
      if let entry = store.loadEntry(forRelativePath: loaded[i].relativePath) {
        loaded[i] = FileChange(
          relativePath: loaded[i].relativePath,
          additions: loaded[i].additions,
          deletions: loaded[i].deletions,
          language: loaded[i].language,
          summary: entry.summary,
          explanation: loaded[i].explanation,
          explanationReason: loaded[i].explanationReason
        )
      }
    }

    // Fetch per-file AI explanations concurrently
    await withTaskGroup(of: (Int, String?, ExplainUnavailableReason?).self) { group in
      for i in loaded.indices {
        group.addTask {
          let (explanation, reason) = await FileExplainer.explain(
            file: loaded[i].relativePath,
            repoURL: repoURL,
            commits: item.commits
          )
          return (i, explanation, reason)
        }
      }
      for await (index, explanation, reason) in group {
        loaded[index] = FileChange(
          relativePath: loaded[index].relativePath,
          additions: loaded[index].additions,
          deletions: loaded[index].deletions,
          language: loaded[index].language,
          summary: loaded[index].summary,
          explanation: explanation,
          explanationReason: reason
        )
      }
    }

    fileCount = loaded.count
    changes = loaded
  }
}

struct ExploreFileRow: View {
  let change: FileChange
  let repoURL: URL
  let commits: [SessionCommit]

  @State private var showExplanation = false
  @State private var whyGeneratedExplanation: String?
  @State private var whyGeneratedReason: ExplainUnavailableReason?
  @State private var showWhyGenerated = false
  @State private var loadingWhyGenerated = false

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 6) {
        Text(change.fileName)
          .font(.callout.monospaced())
          .lineLimit(1)
          .truncationMode(.middle)
          .frame(maxWidth: .infinity, alignment: .leading)

        if let lang = change.language {
          Text(lang.displayName)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
        }

        Text(change.lineCountLabel)
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)

        if change.explanation != nil || change.explanationReason != nil {
          Button {
            showExplanation = true
          } label: {
            Image(systemName: "info.circle")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
        }

        Button {
          loadingWhyGenerated = true
          showWhyGenerated = true
          Task { await loadWhyGenerated() }
        } label: {
          if loadingWhyGenerated {
            ProgressView()
              .controlSize(.mini)
              .frame(width: 16, height: 16)
          } else {
            Image(systemName: "questionmark.circle")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .buttonStyle(.plain)
      }

      if let summary = change.summary {
        Text(summary)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
    }
    .padding(.vertical, 4)
    .padding(.horizontal, 6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 4))
    .sheet(isPresented: $showExplanation) {
      ExplanationSheet(
        fileName: change.fileName,
        explanation: change.explanation,
        reason: change.explanationReason
      )
    }
    .popover(isPresented: $showWhyGenerated) {
      WhyGeneratedPopover(
        fileName: change.fileName,
        explanation: $whyGeneratedExplanation,
        reason: $whyGeneratedReason,
        isLoading: $loadingWhyGenerated
      )
    }
  }

  private func loadWhyGenerated() async {
    guard whyGeneratedExplanation == nil && whyGeneratedReason == nil else { return }
    let (result, reason) = await FileExplainer.whyGenerated(
      file: change.relativePath,
      repoURL: repoURL,
      commits: commits
    )
    await MainActor.run {
      whyGeneratedExplanation = result
      whyGeneratedReason = reason
    }
  }
}

struct ExplanationSheet: View {
  let fileName: String
  let explanation: String?
  let reason: ExplainUnavailableReason?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        if let explanation = explanation {
          Text(explanation)
            .font(.body)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let reason = reason {
          VStack(alignment: .leading, spacing: 12) {
            Label("Explanation Unavailable", systemImage: "exclamationmark.triangle")
              .font(.headline)
            Text(reason.message)
              .font(.body)
              .foregroundStyle(.secondary)
          }
          .padding()
          .frame(maxWidth: .infinity, alignment: .leading)
        } else {
          Text("Explanation unavailable.")
            .font(.body)
            .foregroundStyle(.secondary)
            .padding()
        }
      }
      .navigationTitle(fileName)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
    .frame(minWidth: 400, minHeight: 200)
  }
}

struct WhyGeneratedPopover: View {
  let fileName: String
  let fileURL: URL?
  @Binding var explanation: String?
  @Binding var reason: ExplainUnavailableReason?
  @Binding var isLoading: Bool
  @State private var copiedReason = false

  init(
    fileName: String, fileURL: URL? = nil, explanation: Binding<String?>,
    reason: Binding<ExplainUnavailableReason?>, isLoading: Binding<Bool>
  ) {
    self.fileName = fileName
    self.fileURL = fileURL
    self._explanation = explanation
    self._reason = reason
    self._isLoading = isLoading
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label("Why Generated?", systemImage: "questionmark.circle")
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
        if let explanation = explanation, !explanation.isEmpty {
          Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(explanation, forType: .string)
            copiedReason = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
              copiedReason = false
            }
          } label: {
            Label(
              copiedReason ? "Copied!" : "Copy reason",
              systemImage: copiedReason ? "checkmark" : "doc.on.doc"
            )
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

      if isLoading {
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text("Generating explanation...")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } else if let text = explanation {
        Text(text)
          .font(.callout)
          .textSelection(.enabled)
          .frame(maxWidth: 400, alignment: .leading)
      } else if let reason = reason {
        HStack(alignment: .top, spacing: 8) {
          Image(systemName: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
          Text(reason.message)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 400, alignment: .leading)
      } else {
        Text("Explanation unavailable.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(16)
    .frame(width: 440)
  }
}
