import SwiftUI
import CompassCore

struct ActivityTab: View {
  @ObservedObject var project: CompassProject
  @State private var showAllSessionHistory = false
  @State private var sessionHistoryFilter = PlanSessionHistoryFilter.all

  var body: some View {
    let historySessions = showAllSessionHistory ? project.allSessions : project.sessions
    let sessionHistory = PlanSessionHistory.displayItems(
      for: historySessions,
      auditManifests: auditManifests(for: historySessions)
    )
    let reliabilityFeedback = PlanReliabilityFeedback(
      state: project.state,
      sessions: historySessions,
      historyItems: sessionHistory
    )
    let sessionHistoryDisplay = PlanSessionHistoryDisplay(
      items: sessionHistory,
      mode: showAllSessionHistory ? .all : .recent,
      filter: sessionHistoryFilter,
      runCues: reliabilityFeedback.recentRunCues
    )
    let totalTokens = sessionHistory.reduce(0) { $0 + $1.tokenSummary.totalTokens }

    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        LiveTab(
          project: project,
          layout: .embedded(feedHeight: liveFeedHeight)
        )

        ActivityRunHistorySection(
          display: sessionHistoryDisplay,
          tokenTotalLabel: totalTokens > 0
            ? "\(SessionPhaseTokenUsage.formatTokens(totalTokens)) tokens total" : nil,
          showAllRuns: $showAllSessionHistory,
          selectedFilter: $sessionHistoryFilter,
          runCues: reliabilityFeedback.recentRunCues,
          repoURL: project.repoURL,
          hasOlderArchivedSessions: project.hasOlderArchivedSessions,
          isLoadingArchivedSessions: project.isLoadingArchivedSessions,
          onLoadArchivedSessions: {
            await project.loadArchivedSessionsIfNeeded()
          }
        )
      }
      .frame(maxWidth: 1060, alignment: .leading)
      .padding(.bottom, 8)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .onChange(of: showAllSessionHistory) { _, showAll in
      guard showAll else { return }
      Task {
        await project.loadArchivedSessionsIfNeeded()
      }
    }
  }

  private var liveFeedHeight: CGFloat {
    if project.isRunning || project.isAutoPlaying {
      return 360
    }
    return project.liveLog.isEmpty ? 220 : 300
  }

  private func auditManifests(for sessions: [SessionRecord]) -> [Int: SessionAuditManifest] {
    guard let workspace = project.workspace else { return [:] }
    return sessions.reduce(into: [Int: SessionAuditManifest]()) { result, session in
      result[session.session] = workspace.readSessionAuditManifest(session: session.session)
    }
  }
}

private struct ActivityRunHistorySection: View {
  var display: PlanSessionHistoryDisplay
  var tokenTotalLabel: String?
  @Binding var showAllRuns: Bool
  @Binding var selectedFilter: PlanSessionHistoryFilter
  var runCues: [Int: PlanReliabilityFeedback.RunCue]
  var repoURL: URL
  var hasOlderArchivedSessions: Bool
  var isLoadingArchivedSessions: Bool
  var onLoadArchivedSessions: () async -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        SectionHeader("Run History", systemImage: "clock.arrow.circlepath")
        Spacer()
        Picker("Status filter", selection: $selectedFilter) {
          ForEach(display.filterOptions) { option in
            Text("\(option.filter.title) (\(option.count))").tag(option.filter)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)

        Toggle("All", isOn: $showAllRuns)
          .toggleStyle(.switch)
          .controlSize(.small)
          .disabled(!display.shouldOfferModeToggle && !showAllRuns)
      }

      HStack(spacing: 6) {
        Text(display.countSummary)
        if let tokenTotalLabel {
          Text("·")
          Text(tokenTotalLabel)
            .monospacedDigit()
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)

      if display.visibleItems.isEmpty {
        Text("No \(selectedFilter.emptyStateName).")
          .font(.callout)
          .foregroundStyle(.secondary)
          .padding(12)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
      } else {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(display.visibleItems) { item in
            ActivityRunHistoryRow(item: item, cue: runCues[item.sessionNumber])
          }
        }
      }

      if hasOlderArchivedSessions {
        Button {
          Task { await onLoadArchivedSessions() }
        } label: {
          Label(
            isLoadingArchivedSessions ? "Loading Archived Runs" : "Load Archived Runs",
            systemImage: "archivebox"
          )
        }
        .buttonStyle(.bordered)
        .disabled(isLoadingArchivedSessions)
      }
    }
  }
}

private struct ActivityRunHistoryRow: View {
  var item: PlanSessionHistoryItem
  var cue: PlanReliabilityFeedback.RunCue?

  private var clipboardPayload: PlanSessionHistoryClipboardPayload {
    PlanSessionHistoryClipboardPayload(item: item, reliabilityCue: cue)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text("#\(item.sessionNumber)")
          .font(.callout.monospacedDigit().weight(.semibold))
        Text(item.statusText)
          .font(.caption.weight(.semibold))
          .foregroundStyle(statusColor)
        Spacer()
        Text(item.startedAt, style: .relative)
          .font(.caption)
          .foregroundStyle(.secondary)
        CopyRunHistoryButton(payload: clipboardPayload)
      }

      if let cue {
        Label(cue.label, systemImage: cue.systemImage)
          .font(.caption.weight(.semibold))
          .foregroundStyle(reliabilityColor(for: cue.severity))
      }

      if let planExcerpt = item.planExcerpt, !planExcerpt.isEmpty {
        Text(planExcerpt)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }

      if hasPills {
        HStack(spacing: 8) {
          if let verifyCommand = item.verifyCommand, !verifyCommand.isEmpty {
            ActivityPill(text: "verify")
              .help(verifyCommand)
          }
          if !item.commits.isEmpty {
            ActivityPill(text: "\(item.commits.count) commit(s)")
          }
          if let tokenLabel = item.tokenSummary.compactLabel {
            ActivityPill(text: tokenLabel)
          }
        }
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
  }

  private var hasPills: Bool {
    if let verifyCommand = item.verifyCommand, !verifyCommand.isEmpty { return true }
    return !item.commits.isEmpty || item.tokenSummary.compactLabel != nil
  }

  private var statusColor: Color {
    switch item.status {
    case .succeeded:
      return .green
    case .failed, .rejectedByPlan:
      return .red
    case .cancelled, .skipped:
      return .secondary
    case .planning, .developing, .awaitingApproval:
      return .blue
    }
  }
}

private struct ActivityPill: View {
  var text: String

  var body: some View {
    Text(text)
      .font(.caption2.weight(.semibold))
      .lineLimit(1)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(.quaternary, in: Capsule())
      .foregroundStyle(.secondary)
  }
}

private struct CopyRunHistoryButton: View {
  var payload: PlanSessionHistoryClipboardPayload
  @State private var copied = false

  var body: some View {
    Button {
      copyTextToPasteboard(payload.text)
      copied = true
      Task { @MainActor in
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        copied = false
      }
    } label: {
      Label(
        copied ? "Copied" : "Copy",
        systemImage: copied ? "checkmark" : "doc.on.doc"
      )
      .lineLimit(1)
    }
    .controlSize(.small)
    .disabled(payload.isEmpty)
    .help(ClipboardHelpText.runHistory)
  }
}
