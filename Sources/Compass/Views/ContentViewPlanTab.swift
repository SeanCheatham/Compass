import AppKit
import SwiftUI
import FoundationModels


struct PlanTab: View {
  @ObservedObject var project: CompassProject
  @State private var selectedItemID = PlanTimelineItem.immediateID
  @State private var showAllSessionHistory = false
  @State private var sessionHistoryFilter = PlanSessionHistoryFilter.all

  var body: some View {
    let items = PlanTimelineItem.items(for: project.state)
    let executionEnvironment = project.agentExecutionEnvironment
    let launchPlan = executionEnvironment.launchPlan(repoURL: project.repoURL)
    let overview = PlanWorkflowOverview(
      state: project.state,
      languageProfile: project.languageProfile,
      launchPlan: launchPlan
    )
    let sessionHistory = PlanSessionHistory.displayItems(for: project.sessions)
    let reliabilityFeedback = PlanReliabilityFeedback(
      state: project.state,
      sessions: project.sessions,
      historyItems: sessionHistory
    )
    let sessionHistoryDisplay = PlanSessionHistoryDisplay(
      items: sessionHistory,
      mode: showAllSessionHistory ? .all : .recent,
      filter: sessionHistoryFilter,
      runCues: reliabilityFeedback.recentRunCues
    )

    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        PlanTimelineHeader(
          items: items,
          selectedItemID: $selectedItemID,
          completedCount: project.state.completed.count
        )

        PlanWorkflowOverviewView(
          overview: overview,
          selectedKind: PlanWorkflowOverview.Kind(timelineItemID: selectedItemID)
        ) { kind in
          let destinationID = kind.timelineItemID
          guard items.contains(where: { $0.id == destinationID }) else {
            return
          }

          withAnimation(.easeInOut(duration: 0.2)) {
            selectedItemID = destinationID
          }
        }

        PlanReliabilityFeedbackView(feedback: reliabilityFeedback)

        PlanFocusPanel(item: selectedItem(in: items))

        PlanSessionHistorySection(
          display: sessionHistoryDisplay,
          showAllRuns: $showAllSessionHistory,
          selectedFilter: $sessionHistoryFilter,
          runCues: reliabilityFeedback.recentRunCues,
          repoURL: project.repoURL
        )
      }
      .frame(maxWidth: 1060, alignment: .leading)
    }
    .onAppear {
      normalizeSelection(for: items)
    }
    .onChange(of: project.state) {
      normalizeSelection(for: PlanTimelineItem.items(for: project.state))
    }
  }

  private func selectedItem(in items: [PlanTimelineItem]) -> PlanTimelineItem {
    items.first { $0.id == selectedItemID } ?? items.first { $0.id == PlanTimelineItem.immediateID }
      ?? items[0]
  }

  private func normalizeSelection(for items: [PlanTimelineItem]) {
    if !items.contains(where: { $0.id == selectedItemID }) {
      selectedItemID = items.first { $0.id == PlanTimelineItem.immediateID }?.id ?? items[0].id
    }
  }
}


struct PlanWorkflowOverviewView: View {
  var overview: PlanWorkflowOverview
  var selectedKind: PlanWorkflowOverview.Kind?
  var onSelect: (PlanWorkflowOverview.Kind) -> Void

  private let columns = [
    GridItem(.adaptive(minimum: 280), spacing: 12, alignment: .top)
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 3) {
          SectionHeader("Workflow Overview", systemImage: "rectangle.3.group")
          Text("Current work, queued direction, and the strategic arc stay visible together.")
            .font(.callout)
            .foregroundStyle(.secondary)
        }

        Spacer()

        Label("\(overview.completedCount) completed", systemImage: "checkmark.circle")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 9)
          .padding(.vertical, 5)
          .background(.quaternary.opacity(0.55), in: Capsule())
      }

      LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
        ForEach(overview.sections) { section in
          PlanWorkflowOverviewCard(
            section: section,
            isSelected: section.kind == selectedKind
          ) {
            onSelect(section.kind)
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}


struct PlanWorkflowOverviewCard: View {
  var section: PlanWorkflowOverview.Section
  var isSelected: Bool
  var action: () -> Void

  @FocusState private var isFocused: Bool
  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      cardContent
    }
    .buttonStyle(.plain)
    .focused($isFocused)
    .onHover { isHovered = $0 }
    .help("Show \(section.title.lowercased())")
    .accessibilityLabel("\(section.label): \(section.title)")
    .accessibilityValue(section.excerpt ?? section.emptyMessage)
    .accessibilityHint("Shows this plan section in the focus panel.")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private var cardContent: some View {
    VStack(alignment: .leading, spacing: 10) {
      cardHeader

      Text(section.excerpt ?? section.emptyMessage)
        .font(.callout)
        .foregroundStyle(section.isEmpty ? .secondary : .primary)
        .lineLimit(5)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)

      PlanWorkflowMetadataRow(section: section, color: color)
    }
    .padding(12)
    .frame(maxWidth: .infinity, minHeight: 154, alignment: .topLeading)
    .contentShape(RoundedRectangle(cornerRadius: 8))
    .background(color.opacity(backgroundOpacity), in: RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(color.opacity(borderOpacity), lineWidth: isSelected ? 1.5 : 1)
    }
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(
          Color.primary.opacity(isFocused ? 0.38 : 0),
          style: StrokeStyle(lineWidth: 1, dash: [3, 2])
        )
        .padding(3)
    }
  }

  private var cardHeader: some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: section.systemImage)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(color)
        .frame(width: 24, height: 24)
        .background(color.opacity(isSelected ? 0.2 : 0.12), in: Circle())

      VStack(alignment: .leading, spacing: 2) {
        Text(section.title)
          .font(.headline)
          .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.92))
        Text(section.label)
          .font(.caption.weight(.semibold))
          .foregroundStyle(color)
      }

      Spacer(minLength: 8)

      statusIcon
    }
  }

  @ViewBuilder private var statusIcon: some View {
    ZStack {
      if isSelected {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(color)
      } else if isHovered || isFocused {
        Image(systemName: "chevron.right.circle")
          .foregroundStyle(color.opacity(0.72))
      }
    }
    .font(.system(size: 15, weight: .semibold))
    .frame(width: 18, height: 18)
  }

  private var color: Color {
    switch section.kind {
    case .immediate:
      return .blue
    case .midTerm:
      return .orange
    case .longTerm:
      return .purple
    }
  }

  private var backgroundOpacity: Double {
    if isSelected {
      return 0.15
    }

    return isHovered || isFocused ? 0.1 : 0.07
  }

  private var borderOpacity: Double {
    if isSelected {
      return 0.72
    }

    return isHovered || isFocused ? 0.38 : 0.2
  }
}


struct PlanWorkflowMetadataRow: View {
  var section: PlanWorkflowOverview.Section
  var color: Color

  var body: some View {
    HStack(spacing: 6) {
      if let verifyCommand = section.verifyCommand {
        metadataLabel(verifyCommand, systemImage: "checkmark.seal")
          .textSelection(.enabled)
      } else if section.kind == .immediate {
        metadataLabel("No verify command", systemImage: "checkmark.seal")
      }

      if let timeoutLabel = section.verifyTimeoutLabel {
        metadataLabel(timeoutLabel, systemImage: "timer")
      }

      if let difficulty = section.estimatedDifficultyLabel {
        metadataLabel(difficulty, systemImage: "gauge.with.dots.needle.bottom.50percent")
      } else if section.kind == .immediate {
        metadataLabel("No difficulty", systemImage: "gauge.with.dots.needle.bottom.50percent")
      }

      if section.kind != .immediate {
        metadataLabel("\(section.completedCount) completed", systemImage: "checkmark.circle")
      }
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .lineLimit(1)
  }

  private func metadataLabel(_ text: String, systemImage: String) -> some View {
    Label(text, systemImage: systemImage)
      .padding(.horizontal, 7)
      .padding(.vertical, 3)
      .background(color.opacity(0.1), in: Capsule())
  }
}


struct PlanReliabilityFeedbackView: View {
  var feedback: PlanReliabilityFeedback

  var body: some View {
    if !feedback.isEmpty {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .firstTextBaseline) {
          SectionHeader("Needs Attention", systemImage: "exclamationmark.triangle")

          Spacer()

          Label(
            "\(feedback.notices.count) \(feedback.notices.count == 1 ? "cue" : "cues")",
            systemImage: "waveform.path.ecg"
          )
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 9)
          .padding(.vertical, 5)
          .background(.quaternary.opacity(0.55), in: Capsule())
        }

        VStack(alignment: .leading, spacing: 8) {
          ForEach(feedback.notices) { notice in
            PlanReliabilityNoticeRow(notice: notice)
          }
        }
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(sectionColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .stroke(sectionColor.opacity(0.2))
      }
    }
  }

  private var sectionColor: Color {
    feedback.notices.first.map { reliabilityColor(for: $0.severity) } ?? .red
  }
}


struct PlanReliabilityNoticeRow: View {
  var notice: PlanReliabilityFeedback.Notice

  var body: some View {
    HStack(alignment: .top, spacing: 9) {
      Image(systemName: notice.systemImage)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(color)
        .frame(width: 20, height: 20)

      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text(notice.title)
            .font(.callout.weight(.semibold))

          Text(notice.actionLabel)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())

          if let metadata = notice.metadata {
            Text(metadata)
              .font(.caption.monospacedDigit())
              .foregroundStyle(.secondary)
          }
        }

        Text(notice.detail)
          .font(.callout)
          .foregroundStyle(.secondary)
          .lineLimit(3)
          .fixedSize(horizontal: false, vertical: true)
          .textSelection(.enabled)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var color: Color {
    reliabilityColor(for: notice.severity)
  }
}


struct PlanTimelineHeader: View {
  var items: [PlanTimelineItem]
  @Binding var selectedItemID: String
  var completedCount: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 3) {
          SectionHeader("Plan", systemImage: "map")
          Text("Completed work fades into the rail; upcoming intent stays prominent.")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Label("\(completedCount) completed", systemImage: "checkmark.circle")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 9)
          .padding(.vertical, 5)
          .background(.quaternary.opacity(0.55), in: Capsule())
      }

      ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(alignment: .center, spacing: 0) {
            ForEach(items) { item in
              PlanTimelineTickButton(
                item: item,
                isSelected: item.id == selectedItemID
              ) {
                selectedItemID = item.id
              }
              .id(item.id)
            }
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 8)
          .background(alignment: .top) {
            Capsule()
              .fill(.secondary.opacity(0.16))
              .frame(height: 3)
              .padding(.horizontal, 16)
              .padding(.top, 26)
          }
        }
        .onChange(of: selectedItemID) {
          withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(selectedItemID, anchor: .center)
          }
        }
        .onAppear {
          proxy.scrollTo(selectedItemID, anchor: .center)
        }
      }
    }
    .padding(14)
    .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: 8))
  }
}


struct PlanTimelineTickButton: View {
  var item: PlanTimelineItem
  var isSelected: Bool
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 7) {
        ZStack {
          Circle()
            .fill(item.kind.color.opacity(isSelected ? 0.18 : item.kind.backgroundOpacity))
            .frame(width: item.kind.hitSize, height: item.kind.hitSize)

          Image(systemName: item.kind.systemImage)
            .font(.system(size: item.kind.iconSize, weight: .semibold))
            .foregroundStyle(item.kind.color.opacity(isSelected ? 1 : item.kind.idleOpacity))
            .frame(width: item.kind.hitSize, height: item.kind.hitSize)
        }
        .frame(height: 36)
        .overlay {
          Circle()
            .stroke(item.kind.color.opacity(isSelected ? 0.95 : 0), lineWidth: 2)
        }

        if item.kind.showsLabel {
          Text(item.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(isSelected ? .primary : .secondary)
            .lineLimit(1)
            .frame(width: item.kind.width)
        } else {
          Text(" ")
            .font(.caption)
            .hidden()
        }
      }
      .frame(width: item.kind.width, height: 54, alignment: .top)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(item.helpText)
    .accessibilityLabel(item.helpText)
  }
}


struct PlanFocusPanel: View {
  var item: PlanTimelineItem

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Label(item.title, systemImage: item.kind.systemImage)
          .font(.headline)
          .foregroundStyle(item.kind.color)

        Text(item.kind.label)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 8)
          .padding(.vertical, 3)
          .background(.quaternary.opacity(0.7), in: Capsule())

        Spacer()

        if item.metadata != nil || item.verifyTimeoutLabel != nil {
          HStack(spacing: 6) {
            if let metadata = item.metadata {
              Text(metadata)
            }

            if let timeoutLabel = item.verifyTimeoutLabel {
              Label(timeoutLabel, systemImage: "timer")
            }
          }
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
        }
      }

      MarkdownContent(item.body, empty: item.emptyMessage)

      if let verify = item.verify {
        VerifyCommandView(command: verify)
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(item.kind.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(item.kind.color.opacity(0.22))
    }
  }
}


struct VerifyCommandView: View {
  var command: String

  var body: some View {
    Label(command, systemImage: "checkmark.seal")
      .font(.callout.monospaced())
      .foregroundStyle(.secondary)
      .textSelection(.enabled)
      .padding(.top, 2)
  }
}


struct PlanSessionHistorySection: View {
  var display: PlanSessionHistoryDisplay
  @Binding var showAllRuns: Bool
  @Binding var selectedFilter: PlanSessionHistoryFilter
  var runCues: [Int: PlanReliabilityFeedback.RunCue] = [:]
  var repoURL: URL

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 3) {
          SectionHeader("Run History", systemImage: "clock.arrow.circlepath")
          Text("Recent plan runs, checks, notes, and commits.")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        Spacer()
        HStack(spacing: 8) {
          if display.unfilteredTotalCount > 0 {
            Picker("Status filter", selection: $selectedFilter) {
              ForEach(display.filterOptions) { option in
                Label(
                  "\(option.filter.title) (\(option.count))",
                  systemImage: option.filter.systemImage
                )
                .tag(option.filter)
              }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
          }

          Label(display.countSummary, systemImage: "number")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.55), in: Capsule())

          if display.shouldOfferModeToggle {
            Button {
              showAllRuns.toggle()
            } label: {
              Label(
                display.mode == .all ? "Show Recent" : "Show All",
                systemImage: display.mode == .all ? "clock.arrow.circlepath" : "list.bullet"
              )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
          }
        }
      }

      if let hiddenStatusSummary = display.hiddenStatusSummary {
        Label(
          hiddenSummaryText(hiddenStatusSummary),
          systemImage: "archivebox"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      if display.unfilteredTotalCount == 0 {
        EmptyState("No run history recorded.")
      } else if display.totalCount == 0 {
        EmptyState("No \(display.filter.emptyStateName) match this filter.")
      } else {
        VStack(alignment: .leading, spacing: 10) {
          ForEach(display.visibleItems) { item in
            PlanSessionHistoryCard(
              item: item,
              reliabilityCue: runCues[item.sessionNumber],
              repoURL: repoURL
            )
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func hiddenSummaryText(_ statusSummary: String) -> String {
    let matchingText = display.filter == .all ? "" : " matching"
    return
      "\(display.hiddenCount) older\(matchingText) \(PlanSessionHistoryDisplay.runWord(for: display.hiddenCount)) hidden: \(statusSummary)"
  }
}


struct PlanSessionHistoryCard: View {
  var item: PlanSessionHistoryItem
  var reliabilityCue: PlanReliabilityFeedback.RunCue?
  var repoURL: URL

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text("#\(item.sessionNumber)")
          .font(.headline.monospacedDigit())

        Text(item.statusText)
          .font(.caption.weight(.semibold))
          .foregroundStyle(statusColor)
          .padding(.horizontal, 8)
          .padding(.vertical, 3)
          .background(statusColor.opacity(0.12), in: Capsule())

        if let reliabilityCue {
          Label(reliabilityCue.label, systemImage: reliabilityCue.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(reliabilityColor(for: reliabilityCue.severity))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(reliabilityColor(for: reliabilityCue.severity).opacity(0.12), in: Capsule())
            .help(reliabilityCue.detail)
        }

        Spacer()

        Text(dateString(item.startedAt))
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Text(item.planExcerpt ?? "No plan recorded.")
        .font(.callout)
        .foregroundStyle(item.planExcerpt == nil ? .secondary : .primary)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)

      if let verifyCommand = item.verifyCommand {
        Label(verifyCommand, systemImage: "checkmark.seal")
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
      } else {
        Label("No verify command recorded.", systemImage: "checkmark.seal")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if item.runtimeRouteDescriptor.isSnapshotAvailable {
        RuntimeRouteBadge(descriptor: item.runtimeRouteDescriptor)
      }


      if let feedback = item.feedback {
        LabeledHistoryBlock(title: "Feedback", systemImage: "text.bubble") {
          MarkdownContent(feedback, compact: true)
            .foregroundStyle(.secondary)
        }
      }

      if !item.notes.isEmpty {
        LabeledHistoryBlock(title: "Notes", systemImage: "note.text") {
          VStack(alignment: .leading, spacing: 6) {
            ForEach(item.notes, id: \.self) { note in
              MarkdownContent(note, compact: true)
                .foregroundStyle(.secondary)
            }
          }
        }
      }

      if !item.commits.isEmpty {
        LabeledHistoryBlock(title: "Commits", systemImage: "arrow.triangle.branch") {
          VStack(alignment: .leading, spacing: 5) {
            ForEach(item.commits) { commit in
              Label("\(commit.short) \(commit.subject)", systemImage: "arrow.triangle.branch")
                .font(.caption)
                .textSelection(.enabled)
            }
          }
        }
      }

      if item.status == .succeeded && !item.commits.isEmpty {
        CommitTourRow(item: item, repoURL: repoURL)
      }

      if item.status == .succeeded && !item.commits.isEmpty {
        HStack(spacing: 8) {
          ExplainChangesButton(item: item, repoURL: repoURL)
          ExploreFilesButton(item: item, repoURL: repoURL)
          QnAButton(item: item, repoURL: repoURL)
        }
      }

      if let failedVerify = item.failedVerify {
        DisclosureGroup("Verify failed (\(failedVerify.exitCodeText))") {
          VStack(alignment: .leading, spacing: 6) {
            Text(failedVerify.command)
              .font(.caption.monospaced())
              .foregroundStyle(.secondary)
              .textSelection(.enabled)

            Text(failedVerify.tail)
              .font(.caption.monospaced())
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(8)
              .background(.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 6))
          }
          .padding(.top, 4)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.red)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.38), in: RoundedRectangle(cornerRadius: 8))
  }

  private var statusColor: Color {
    switch item.status {
    case .planning:
      return .blue
    case .awaitingApproval:
      return .purple
    case .developing:
      return .orange
    case .succeeded:
      return .green
    case .failed, .rejectedByPlan:
      return .red
    case .cancelled, .skipped:
      return .secondary
    }
  }

  private func dateString(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .shortened)
  }
}

struct ExplainChangesButton: View {
  let item: PlanSessionHistoryItem
  let repoURL: URL

  @State private var showingPopover = false
  @State private var summary: String?
  @State private var isLoading = false

  private var canExplain: Bool {
    item.status == .succeeded && !item.commits.isEmpty
  }

  var body: some View {
    if canExplain {
      Button {
        showingPopover = true
      } label: {
        Label("Explain Changes", systemImage: "book.pages")
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
      .popover(isPresented: $showingPopover) {
        CommitExplanationPopover(
          item: item,
          repoURL: repoURL,
          summary: $summary,
          isLoading: $isLoading
        )
      }
    }
  }
}

// MARK: - Shared Git Diff Helpers

private func gitDiffForSha(_ sha: String, repoURL: URL) async -> String {
  await withCheckedContinuation { continuation in
    Task {
      let result = try? await ProcessRunner.runEnv(
        "git", ["diff", "--no-color", sha], workingDirectory: repoURL
      )
      continuation.resume(returning: result?.stdout ?? "")
    }
  }
}

private func gitDiffRange(from: String, to: String, repoURL: URL) async -> String {
  await withCheckedContinuation { continuation in
    Task {
      let result = try? await ProcessRunner.runEnv(
        "git", ["diff", "--no-color", "\(from)..\(to)"], workingDirectory: repoURL
      )
      continuation.resume(returning: result?.stdout ?? "")
    }
  }
}

struct CommitExplanationPopover: View {
  let item: PlanSessionHistoryItem
  let repoURL: URL
  @Binding var summary: String?
  @Binding var isLoading: Bool

  @State private var fetchedSummary: String?
  @State private var fetchedDiff: String?

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

      if isLoading {
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text("Generating summary...")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } else if let text = summary ?? fetchedSummary {
        Text(text)
          .font(.callout)
          .textSelection(.enabled)
          .frame(maxWidth: 400, alignment: .leading)
      } else {
        Text("Summary unavailable.")
          .font(.caption)
          .foregroundStyle(.secondary)
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

    isLoading = true
    defer { isLoading = false }

    guard let firstCommit = item.commits.first else { return }

    // Fetch the diff for the commit range
    let diff: String
    if item.commits.count == 1 {
      diff = await gitDiffForSha(firstCommit.sha, repoURL: repoURL)
    } else {
      let lastCommit = item.commits.last!
      diff = await gitDiffRange(from: firstCommit.sha, to: lastCommit.sha, repoURL: repoURL)
    }

    guard !diff.isEmpty else { return }
    fetchedDiff = diff

    if #available(macOS 26.0, *) {
      fetchedSummary = await CommitExplainer.summarize(diff: diff)
    } else {
      fetchedSummary = nil
    }
  }

}

struct CommitTourRow: View {
  let item: PlanSessionHistoryItem
  let repoURL: URL

  @State private var tourText: String?
  @State private var isLoading = false
  @State private var tourAvailabilityError = false

  private var canTour: Bool {
    item.status == .succeeded && !item.commits.isEmpty
  }

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
          Label("Foundation Models is unavailable on this device.", systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
        }
      } else if let tourText {
        LabeledHistoryBlock(title: "What We Built", systemImage: "lightbulb") {
          Text(tourText)
            .font(.callout)
            .foregroundStyle(.primary)
            .textSelection(.enabled)
        }
      } else if canTour {
        EmptyView()
      }
    }
    .task { startTour() }
  }

  func startTour() {
    guard canTour, tourText == nil else { return }
    isLoading = true
    Task {
      await loadTour()
      isLoading = false
    }
  }

  private func loadTour() async {
    tourAvailabilityError = false
    guard let firstCommit = item.commits.first else { return }
    let diff: String
    if item.commits.count == 1 {
      diff = await gitDiffForSha(firstCommit.sha, repoURL: repoURL)
    } else {
      let lastCommit = item.commits.last!
      diff = await gitDiffRange(from: firstCommit.sha, to: lastCommit.sha, repoURL: repoURL)
    }
    guard !diff.isEmpty else { return }
    if #available(macOS 26.0, *) {
      let result = await CommitTourGenerator.generate(diff: diff)
      tourText = result
      if result == nil { tourAvailabilityError = true }
    }
  }
}

struct ExploreFilesButton: View {
  let item: PlanSessionHistoryItem
  let repoURL: URL

  @State private var showingPopover = false

  private var canExplore: Bool {
    item.status == .succeeded && !item.commits.isEmpty
  }

  var body: some View {
    if canExplore {
      Button {
        showingPopover = true
      } label: {
        Label("Explore Files", systemImage: "doc.text.magnifyingglass")
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
      .popover(isPresented: $showingPopover) {
        ExploreFilesPopover(item: item, repoURL: repoURL)
      }
    }
  }
}

struct QnAButton: View {
  let item: PlanSessionHistoryItem
  let repoURL: URL

  @State private var showingPopover = false

  private var canQnA: Bool {
    item.status == .succeeded && !item.commits.isEmpty
  }

  var body: some View {
    if canQnA {
      Button {
        showingPopover = true
      } label: {
        Label("Ask", systemImage: "questionmark.circle")
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
      .popover(isPresented: $showingPopover) {
        QnAPopover(item: item, repoURL: repoURL)
      }
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
        Label("Foundation Models is unavailable on this device.", systemImage: "exclamationmark.triangle")
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

  private var groupedChanges: [(category: FileChangeCategory, changes: [FileChange])] {
    let grouped = Dictionary(grouping: changes, by: { $0.category })
    return FileChangeCategory.allCases
      .compactMap { category -> (FileChangeCategory, [FileChange])? in
        guard let cats = grouped[category], !cats.isEmpty else { return nil }
        return (category, cats)
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
          Text("Loading file changes...")
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
                  ExploreFileRow(change: change)
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

    var loaded = await FileExplainer.changes(for: repoURL, commits: item.commits.reversed())

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
          explanation: loaded[i].explanation
        )
      }
    }

    // Fetch per-file AI explanations concurrently
    await withTaskGroup(of: (Int, String?).self) { group in
      for i in loaded.indices {
        group.addTask {
          let explanation = await FileExplainer.explain(
            file: loaded[i].relativePath,
            repoURL: repoURL,
            commits: item.commits
          )
          return (i, explanation)
        }
      }
      for await (index, explanation) in group {
        if let explanation = explanation {
          loaded[index] = FileChange(
            relativePath: loaded[index].relativePath,
            additions: loaded[index].additions,
            deletions: loaded[index].deletions,
            language: loaded[index].language,
            summary: loaded[index].summary,
            explanation: explanation
          )
        }
      }
    }

    changes = loaded
  }
}

struct ExploreFileRow: View {
  let change: FileChange

  @State private var showExplanation = false

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

        if change.explanation != nil {
          Button {
            showExplanation = true
          } label: {
            Image(systemName: "info.circle")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
        }
      }

      if let summary = change.summary {
        Text(summary)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(.vertical, 4)
    .padding(.horizontal, 6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 4))
    .sheet(isPresented: $showExplanation) {
      if let explanation = change.explanation {
        NavigationStack {
          ScrollView {
            Text(explanation)
              .font(.body)
              .padding()
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .navigationTitle(change.fileName)
          .toolbar {
            ToolbarItem(placement: .confirmationAction) {
              Button("Done") { showExplanation = false }
            }
          }
        }
        .frame(minWidth: 400, minHeight: 200)
      }
    }
  }
}

func reliabilityColor(for severity: PlanReliabilityFeedback.Severity) -> Color {
  switch severity {
  case .warning:
    return .orange
  case .failure:
    return .red
  case .paused:
    return .blue
  }
}

func storageAssessmentColor(for severity: CompassWorkspaceStorageAssessment.Severity)
  -> Color
{
  switch severity {
  case .healthy:
    return .green
  case .info:
    return .blue
  case .warning:
    return .orange
  case .failure:
    return .red
  }
}


struct RuntimeRouteBadge: View {
  var descriptor: PlanSessionHistoryItem.RuntimeRouteDescriptor

  var body: some View {
    Label(descriptor.badgeText, systemImage: descriptor.systemImage)
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)
      .lineLimit(2)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(.quaternary.opacity(0.5), in: Capsule())
      .help(descriptor.helpText)
  }
}


struct LabeledHistoryBlock<Content: View>: View {
  var title: String
  var systemImage: String
  var content: Content

  init(
    title: String,
    systemImage: String,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.systemImage = systemImage
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Label(title, systemImage: systemImage)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)

      content
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}


struct PlanTimelineItem: Identifiable, Equatable {
  static let immediateID = PlanWorkflowOverview.TimelineDestination.immediate.itemID
  private static let midTermID = PlanWorkflowOverview.TimelineDestination.midTerm.itemID
  private static let longTermID = PlanWorkflowOverview.TimelineDestination.longTerm.itemID

  var id: String
  var kind: Kind
  var title: String
  var body: String
  var verify: String?
  var verifyTimeoutLabel: String?
  var metadata: String?
  var emptyMessage: String

  var helpText: String {
    switch kind {
    case .history:
      return "\(title): \(body)"
    default:
      return title
    }
  }

  static func items(for state: PlanState) -> [PlanTimelineItem] {
    let history = state.completed.enumerated().map { index, item in
      PlanTimelineItem(
        id: "plan-history-\(index)",
        kind: .history,
        title: "Iteration \(index + 1)",
        body: item,
        metadata: "#\(index + 1)",
        emptyMessage: "No detail recorded for this iteration."
      )
    }

    let immediate = PlanTimelineItem(
      id: immediateID,
      kind: .immediate,
      title: "Immediate",
      body: state.immediate?.plan ?? "",
      verify: state.immediate?.verify,
      verifyTimeoutLabel: state.immediate.map {
        PlanVerifyMetadata(timeoutMs: $0.verifyTimeoutMs).label
      },
      metadata: state.immediate?.estimatedDifficulty?.rawValue.capitalized,
      emptyMessage: "No immediate plan."
    )

    let midTerm = PlanTimelineItem(
      id: midTermID,
      kind: .midTerm,
      title: "Mid-Term",
      body: state.midTerm,
      emptyMessage: "No mid-term queue."
    )

    let longTerm = PlanTimelineItem(
      id: longTermID,
      kind: .longTerm,
      title: "Long-Term",
      body: state.longTerm,
      emptyMessage: "No long-term arc."
    )

    return history + [immediate, midTerm, longTerm]
  }

  enum Kind: Equatable {
    case history
    case immediate
    case midTerm
    case longTerm

    var label: String {
      switch self {
      case .history: return "History"
      case .immediate: return "Next"
      case .midTerm: return "Queue"
      case .longTerm: return "Arc"
      }
    }

    var systemImage: String {
      switch self {
      case .history: return "circle.fill"
      case .immediate: return "target"
      case .midTerm: return "point.3.connected.trianglepath.dotted"
      case .longTerm: return "mountain.2.fill"
      }
    }

    var color: Color {
      switch self {
      case .history: return .secondary
      case .immediate: return .blue
      case .midTerm: return .orange
      case .longTerm: return .purple
      }
    }

    var width: CGFloat {
      switch self {
      case .history: return 18
      case .immediate, .midTerm, .longTerm: return 112
      }
    }

    var hitSize: CGFloat {
      switch self {
      case .history: return 14
      case .immediate, .midTerm, .longTerm: return 34
      }
    }

    var iconSize: CGFloat {
      switch self {
      case .history: return 5
      case .immediate, .midTerm, .longTerm: return 16
      }
    }

    var backgroundOpacity: Double {
      switch self {
      case .history: return 0.05
      case .immediate, .midTerm, .longTerm: return 0.13
      }
    }

    var idleOpacity: Double {
      switch self {
      case .history: return 0.36
      case .immediate, .midTerm, .longTerm: return 0.85
      }
    }

    var showsLabel: Bool {
      self != .history
    }
  }
}
