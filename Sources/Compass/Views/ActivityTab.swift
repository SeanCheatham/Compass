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
