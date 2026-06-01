import SwiftUI

struct PlanTab: View {
  @ObservedObject var project: CompassProject
  @State private var selectedItemID = PlanTimelineItem.immediateID
  @State private var showAllSessionHistory = false
  @State private var sessionHistoryFilter = PlanSessionHistoryFilter.all
  @State private var factoryBriefNarration: PlanFactoryBriefNarration?

  var body: some View {
    let items = PlanTimelineItem.items(for: project.state)
    let executionEnvironment = project.agentExecutionEnvironment
    let launchPlan = executionEnvironment.launchPlan(repoURL: project.repoURL)
    let overview = PlanWorkflowOverview(
      state: project.state,
      languageProfile: project.languageProfile,
      launchPlan: launchPlan
    )
    let historySessions = showAllSessionHistory ? project.allSessions : project.sessions
    let sessionHistory = PlanSessionHistory.displayItems(for: historySessions)
    let reliabilityFeedback = PlanReliabilityFeedback(
      state: project.state,
      sessions: historySessions,
      historyItems: sessionHistory
    )
    let factoryBrief = PlanFactoryBrief(
      state: project.state,
      reliabilityFeedback: reliabilityFeedback,
      launchPlan: launchPlan,
      languageProfile: project.languageProfile,
      forgeProfile: project.forgeProfile
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

        PlanFactoryBriefView(
          brief: factoryBrief,
          narration: matchingNarration(for: factoryBrief)
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

        PlanFocusPanel(
          item: selectedItem(in: items),
          languageProfile: project.languageProfile,
          forgeProfile: project.forgeProfile
        )

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
    .onAppear {
      normalizeSelection(for: items)
    }
    .onChange(of: showAllSessionHistory) { _, showAll in
      guard showAll else { return }
      Task {
        await project.loadArchivedSessionsIfNeeded()
      }
    }
    .onChange(of: project.state) {
      normalizeSelection(for: PlanTimelineItem.items(for: project.state))
    }
    .task(id: "\(factoryBrief.narrationIdentifier)|running-\(project.isRunning)") {
      factoryBriefNarration = nil
      guard !project.isRunning else { return }
      factoryBriefNarration = await PlanFactoryBriefNarrator.narrate(brief: factoryBrief)
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

  private func matchingNarration(for brief: PlanFactoryBrief) -> PlanFactoryBriefNarration? {
    guard factoryBriefNarration?.briefIdentifier == brief.narrationIdentifier else {
      return nil
    }
    return factoryBriefNarration
  }
}
