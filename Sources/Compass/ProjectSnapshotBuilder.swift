import CompassCore
import Foundation

enum ProjectSnapshotBuilder {
  @MainActor
  static func payload(
    for project: CompassProject,
    agentSettings: AgentRuntimeSettings,
    modelSnapshot: LocalModelSnapshot,
    runGuide providedRunGuide: ProjectRunControlGuide? = nil
  ) -> ProjectSnapshotClipboardPayload {
    let runGuide = providedRunGuide ?? self.runGuide(for: project)
    let draftGuide = DraftIntakeGuide(drafts: project.drafts)
    let visionGuide = ProjectVisionGuide(vision: project.vision)
    let settingsGuide = AgentSettingsGuide(
      settings: agentSettings,
      modelSnapshot: modelSnapshot
    )
    let recoveryGuide = ProjectRecoveryGuide(status: project.reliabilityStatus)

    return ProjectSnapshotClipboardPayload(
      projectName: project.displayName,
      runGuide: runGuide,
      draftGuide: draftGuide,
      settingsGuide: settingsGuide,
      visionGuide: visionGuide,
      recoveryGuide: recoveryGuide,
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
      drafts: project.drafts,
      vision: project.vision
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

  @MainActor
  static func latestRunHistoryClipboardPayload(
    for project: CompassProject
  ) -> PlanSessionHistoryClipboardPayload? {
    let historyItems = PlanSessionHistory.displayItems(
      for: project.sessions,
      auditManifests: auditManifests(for: project.sessions, workspace: project.workspace)
    )
    guard let latest = historyItems.first else { return nil }
    let feedback = PlanReliabilityFeedback(
      state: project.state,
      sessions: project.sessions,
      historyItems: historyItems
    )
    let payload = PlanSessionHistoryClipboardPayload(
      item: latest,
      reliabilityCue: feedback.recentRunCues[latest.sessionNumber]
    )
    return payload.isEmpty ? nil : payload
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
