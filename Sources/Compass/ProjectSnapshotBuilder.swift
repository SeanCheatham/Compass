import Foundation

enum ProjectSnapshotBuilder {
  @MainActor
  static func payload(
    for project: CompassProject,
    agentSettings: AgentRuntimeSettings,
    foundationModelsAvailable: Bool,
    runGuide providedRunGuide: ProjectRunControlGuide? = nil
  ) -> ProjectSnapshotClipboardPayload {
    let runGuide = providedRunGuide ?? self.runGuide(for: project)
    let draftGuide = DraftIntakeGuide(drafts: project.drafts)
    let assumptionGuide = AssumptionReviewGuide(
      ledger: AssumptionLedger(assumptions: project.assumptions)
    )
    let lessonsGuide = ProjectLessonsGuide(lessons: project.lessons)
    let settingsGuide = AgentSettingsGuide(
      settings: agentSettings,
      foundationModelsAvailable: foundationModelsAvailable
    )

    return ProjectSnapshotClipboardPayload(
      projectName: project.displayName,
      runGuide: runGuide,
      draftGuide: draftGuide,
      assumptionGuide: assumptionGuide,
      settingsGuide: settingsGuide,
      lessonsGuide: lessonsGuide,
      historyGuide: historyGuide(for: project)
    )
  }

  @MainActor
  static func runGuide(for project: CompassProject) -> ProjectRunControlGuide {
    ProjectRunControlGuide(
      state: project.state,
      reliabilityStatus: project.reliabilityStatus,
      hasRepository: project.hasRepository,
      isRunning: project.isRunning,
      isAutoPlaying: project.isAutoPlaying,
      isPaused: project.isPaused,
      languageProfile: project.languageProfile,
      forgeProfile: project.forgeProfile,
      drafts: project.drafts
    )
  }

  @MainActor
  private static func historyGuide(for project: CompassProject) -> PlanSessionHistoryGuide {
    let historyItems = PlanSessionHistory.displayItems(
      for: project.sessions,
      auditManifests: auditManifests(for: project.sessions, workspace: project.workspace)
    )
    let feedback = PlanReliabilityFeedback(
      state: project.state,
      sessions: project.sessions,
      historyItems: historyItems
    )
    let display = PlanSessionHistoryDisplay(
      items: historyItems,
      runCues: feedback.recentRunCues
    )
    return PlanSessionHistoryGuide(display: display, runCues: feedback.recentRunCues)
  }

  private static func auditManifests(
    for sessions: [SessionRecord],
    workspace: CompassWorkspace?
  ) -> [Int: SessionAuditManifest] {
    guard let workspace else { return [:] }
    return sessions.reduce(into: [Int: SessionAuditManifest]()) { result, session in
      result[session.session] = workspace.readSessionAuditManifest(session: session.session)
    }
  }
}
