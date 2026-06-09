import SwiftUI

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

    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        LiveTab(
          project: project,
          layout: .embedded(feedHeight: liveFeedHeight)
        )

        ActivityReliabilitySummary(feedback: reliabilityFeedback)

        ActivityTokenCostSummary(items: sessionHistory)

        ActivityRunHistorySection(
          display: sessionHistoryDisplay,
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

private struct ActivityTokenCostSummary: View {
  var items: [PlanSessionHistoryItem]

  private var tokenItems: [PlanSessionHistoryItem] {
    items.filter { !$0.tokenSummary.isEmpty }
  }

  private var latest: PlanSessionHistoryItem? {
    tokenItems.sorted { $0.startedAt > $1.startedAt }.first
  }

  private var totalTokens: Int {
    tokenItems.reduce(0) { $0 + $1.tokenSummary.totalTokens }
  }

  private var compactionCount: Int {
    tokenItems.reduce(0) { $0 + $1.tokenSummary.compactionCount }
  }

  private var retryCount: Int {
    tokenItems.reduce(0) { $0 + $1.tokenSummary.retryCount }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      SectionHeader("Token Cost", systemImage: "gauge.with.dots.needle.67percent")

      if let latest {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(latest.tokenSummary.compactLabel ?? "0 tokens")
            .font(.callout.monospacedDigit().weight(.semibold))
          Text("latest run #\(latest.sessionNumber)")
            .font(.caption)
            .foregroundStyle(.secondary)
          Spacer()
          Text("\(SessionPhaseTokenUsage.formatTokens(totalTokens)) total")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }

        HStack(spacing: 8) {
          if let proofAction = latest.tokenSummary.latestProofActionKind {
            ActivityPill(text: proofAction)
          }
          ActivityPill(text: "\(compactionCount) compaction(s)")
          ActivityPill(text: "\(retryCount) retry(s)")
        }
      } else {
        Text("No token usage recorded yet.")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    }
  }
}

private struct ActivityReliabilitySummary: View {
  var feedback: PlanReliabilityFeedback

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      SectionHeader("Run Attention", systemImage: "exclamationmark.triangle")

      if feedback.notices.isEmpty {
        Text("No recent run attention items.")
          .font(.callout)
          .foregroundStyle(.secondary)
      } else {
        ForEach(feedback.notices) { notice in
          HStack(alignment: .top, spacing: 10) {
            Image(systemName: notice.systemImage)
              .foregroundStyle(reliabilityColor(for: notice.severity))
              .frame(width: 18, height: 18)
              .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
              HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(notice.title)
                  .font(.callout.weight(.semibold))
                Text("#\(notice.sessionNumber)")
                  .font(.caption.monospacedDigit())
                  .foregroundStyle(.secondary)
              }
              Text(notice.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
              Text(notice.actionLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(reliabilityColor(for: notice.severity))
            }
          }
          .padding(10)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(
            reliabilityColor(for: notice.severity).opacity(0.08),
            in: RoundedRectangle(cornerRadius: 8)
          )
        }
      }
    }
  }
}

private struct ActivityRunHistorySection: View {
  var display: PlanSessionHistoryDisplay
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

      Text(display.countSummary)
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

      HStack(spacing: 8) {
        if let verifyCommand = item.verifyCommand, !verifyCommand.isEmpty {
          ActivityPill(text: "verify")
            .help(verifyCommand)
        }
        if let runtimeRouteSummary = item.runtimeRouteSummary, !runtimeRouteSummary.isEmpty {
          ActivityPill(text: runtimeRouteSummary)
        }
        if !item.commits.isEmpty {
          ActivityPill(text: "\(item.commits.count) commit(s)")
        }
        if !item.auditArtifacts.isEmpty {
          ActivityPill(text: "\(item.auditArtifacts.count) artifact(s)")
        }
        if let tokenLabel = item.tokenSummary.compactLabel {
          ActivityPill(text: tokenLabel)
        }
        if item.tokenSummary.compactionCount > 0 {
          ActivityPill(text: "\(item.tokenSummary.compactionCount) compact")
        }
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
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
