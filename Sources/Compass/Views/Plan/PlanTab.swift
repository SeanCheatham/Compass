import SwiftUI

struct PlanRunContextSection: View {
  @ObservedObject var project: CompassProject
  @State private var selectedItemID = PlanTimelineItem.immediateID
  @State private var tournamentBriefNarration: PlanTournamentBriefNarration?

  var body: some View {
    let items = PlanTimelineItem.items(for: project.state)
    let executionEnvironment = project.agentExecutionEnvironment
    let launchPlan = executionEnvironment.launchPlan(repoURL: project.repoURL)
    let historySessions = project.sessions
    let sessionHistory = PlanSessionHistory.displayItems(
      for: historySessions,
      auditManifests: auditManifests(for: historySessions)
    )
    let reliabilityFeedback = PlanReliabilityFeedback(
      state: project.state,
      sessions: historySessions,
      historyItems: sessionHistory
    )
    let tournamentBrief = PlanTournamentBrief(
      state: project.state,
      reliabilityFeedback: reliabilityFeedback,
      launchPlan: launchPlan,
      languageProfile: project.languageProfile,
      forgeProfile: project.forgeProfile
    )

    VStack(alignment: .leading, spacing: 18) {
      PlanTournamentBriefView(
        brief: tournamentBrief,
        narration: matchingNarration(for: tournamentBrief)
      )

      PlanTimelineHeader(
        items: items,
        selectedItemID: $selectedItemID,
        completedCount: project.state.completed.count
      )

      PlanFocusPanel(
        item: selectedItem(in: items),
        languageProfile: project.languageProfile,
        forgeProfile: project.forgeProfile
      )
    }
    .onAppear {
      normalizeSelection(for: items)
    }
    .onChange(of: project.state) {
      normalizeSelection(for: PlanTimelineItem.items(for: project.state))
    }
    .task(id: "\(tournamentBrief.narrationIdentifier)|running-\(project.isRunning)") {
      tournamentBriefNarration = nil
      guard !project.isRunning else { return }
      tournamentBriefNarration = await PlanTournamentBriefNarrator.narrate(brief: tournamentBrief)
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

  private func auditManifests(for sessions: [SessionRecord]) -> [Int: SessionAuditManifest] {
    guard let workspace = project.workspace else { return [:] }
    return sessions.reduce(into: [Int: SessionAuditManifest]()) { result, session in
      result[session.session] = workspace.readSessionAuditManifest(session: session.session)
    }
  }

  private func matchingNarration(for brief: PlanTournamentBrief) -> PlanTournamentBriefNarration? {
    guard tournamentBriefNarration?.briefIdentifier == brief.narrationIdentifier else {
      return nil
    }
    return tournamentBriefNarration
  }
}

struct PlanTab: View {
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
        PlanRunContextSection(project: project)

        PlanWorkflowOverviewView(
          overview: PlanWorkflowOverview(
            state: project.state,
            languageProfile: project.languageProfile,
            launchPlan: project.agentExecutionEnvironment.launchPlan(repoURL: project.repoURL)
          ),
          selectedKind: .immediate
        ) { _ in }

        PlanReliabilityFeedbackView(feedback: reliabilityFeedback)

        PlanSessionHistorySection(
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
    }
    .onChange(of: showAllSessionHistory) { _, showAll in
      guard showAll else { return }
      Task {
        await project.loadArchivedSessionsIfNeeded()
      }
    }
  }

  private func auditManifests(for sessions: [SessionRecord]) -> [Int: SessionAuditManifest] {
    guard let workspace = project.workspace else { return [:] }
    return sessions.reduce(into: [Int: SessionAuditManifest]()) { result, session in
      result[session.session] = workspace.readSessionAuditManifest(session: session.session)
    }
  }
}
