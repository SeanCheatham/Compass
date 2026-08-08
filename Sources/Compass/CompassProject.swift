import AppKit
import CompassCore
import Foundation

@MainActor
final class CompassProject: ObservableObject, Identifiable {
  let id: UUID
  @Published var repoURL: URL
  @Published var projectKind: ProjectKind
  @Published var activeStorage: KnownProjectActiveStorage
  @Published var state = PlanState.empty
  @Published var drafts = ""
  @Published var draftEntry = ""
  @Published var lessons = ""
  @Published var assumptions: [AssumptionRecord] = []
  @Published var brief = ProjectBrief.empty
  @Published var requirementLedger = RequirementLedger.empty
  @Published var sessions: [SessionRecord] = []
  @Published var archivedSessions: [SessionRecord] = []
  @Published var hasOlderArchivedSessions = false
  @Published var isLoadingArchivedSessions = false
  @Published var languageProfile = RepositoryLanguageProfile.empty
  @Published var activitySourceSnapshot = RepositoryActivitySourceSnapshot.notScanned()
  @Published var nativeFeedbackMode: NativeFeedbackMode
  @Published var liveLog: [LiveLine] = []
  let studioState: StudioState
  /// Speaks Studio thinking entries aloud when enabled.
  let studioThinkingSpeech: StudioThinkingSpeechService
  @Published var studioThinkingNarrationEnabled: Bool {
    didSet {
      studioThinkingSpeech.isEnabled = studioThinkingNarrationEnabled
    }
  }
  @Published var phase: LoopPhase = .idle
  @Published var isRunning = false
  @Published var isAutoPlaying = false
  @Published var isPaused = false
  @Published var pauseMode: PauseMode = .immediate
  @Published var errorMessage: String?
  @Published var activeStorageActivationState = CompassProjectActiveStorageState.idle
  @Published var activeStorageActivationConfirmation: CompassWorkspaceStorageActivationConfirmation?
  @Published var storageMigrationState = CompassProjectStorageMigrationState.idle
  @Published var storageMigrationConfirmation: CompassWorkspaceStorageMigrationConfirmation?
  @Published var chamberSnapshot: ChamberSnapshot?

  var addedAt: Date
  var lastOpenedAt: Date
  var storageApplicationSupportRoots: KnownProjectStore.ApplicationSupportRoots

  // Members below are conceptually private to the class but are accessed
  // across the per-topic extension files (Editing, Storage, Run, Git,
  // etc.) that flesh out CompassProject. Swift's `private` scopes to the
  // declaring source file, which would break the topical split without
  // moving everything back into one file — so they live at internal
  // visibility and are documented as for-extension-use-only here.
  var workspace: CompassWorkspace? {
    guard FileManager.default.fileExists(atPath: repoURL.path),
      let repoURL = CompassWorkspace.discover(from: repoURL)
    else { return nil }
    return makeWorkspace(repoURL: repoURL)
  }

  var executor: AgentExecutor?
  var stopRequested = false
  /// When Plan returns no immediate work and a full requirements audit finds
  /// unsatisfied items, auto-play injects findings and continues once.
  var pendingRequirementsReplan = false
  /// True after we already continued auto-play once for unsatisfied findings
  /// without shipping new work — prevents infinite Plan/audit loops.
  var alreadyReplannedAfterUnsatisfiedAudit = false
  var activeAuditSessionNumber: Int?
  var activeAuditEventSequence = 0
  /// Session number the codemap was last refreshed for. When Plan and
  /// Develop fire back-to-back inside the same session the second call
  /// no-ops; a fresh Plan run (different session number) triggers a
  /// new refresh. Set in `refreshCodemapIfNeeded(...)`.
  var codemapRefreshedForSession: Int?
  let storageMigrationAction: CompassWorkspaceStorageMigrationAction
  let maxDevelopAttempts = 3
  /// Soft cap surfaced to the Critic prompt so it knows how many
  /// review rounds to expect. Critic-driven retries re-run the full
  /// Develop + post-checks inner loop with critic feedback added.
  let maxCriticAttempts = 3
  var allSessions: [SessionRecord] {
    let merged = archivedSessions + sessions
    var bySession: [Int: SessionRecord] = [:]
    for record in merged {
      bySession[record.session] = record
    }
    return bySession.values.sorted { lhs, rhs in
      if lhs.session == rhs.session {
        return lhs.startedAt < rhs.startedAt
      }
      return lhs.session < rhs.session
    }
  }

  func loadArchivedSessionsIfNeeded() async {
    guard hasOlderArchivedSessions, archivedSessions.isEmpty, !isLoadingArchivedSessions else {
      return
    }
    guard let workspace else { return }
    isLoadingArchivedSessions = true
    defer { isLoadingArchivedSessions = false }
    archivedSessions = workspace.readArchivedSessions()
  }

  init(
    id: UUID = UUID(),
    repoURL: URL,
    projectKind: ProjectKind = .factory,
    activeStorage: KnownProjectActiveStorage = .repoLocal,
    addedAt: Date = Date(),
    lastOpenedAt: Date = Date(),
    nativeFeedbackMode: NativeFeedbackMode = .notifications,
    studioThinkingNarrationEnabled: Bool = false,
    storageApplicationSupportRoots: KnownProjectStore.ApplicationSupportRoots =
      KnownProjectStore.productionApplicationSupportRoots(),
    storageMigrationAction: @escaping CompassWorkspaceStorageMigrationAction = { plan in
      try CompassWorkspaceStorageMigrator().migrate(plan: plan)
    }
  ) {
    self.id = id
    self.repoURL = repoURL.standardizedFileURL
    self.projectKind = projectKind
    self.activeStorage = activeStorage
    activitySourceSnapshot = RepositoryActivitySourceSnapshot.notScanned(
      activeStorage: activeStorage)
    self.addedAt = addedAt
    self.lastOpenedAt = lastOpenedAt
    self.nativeFeedbackMode = nativeFeedbackMode
    self.storageApplicationSupportRoots = storageApplicationSupportRoots
    self.storageMigrationAction = storageMigrationAction
    self.studioState = StudioState(
      repoURL: repoURL.standardizedFileURL,
      workspacePrefix: "/workspace"
    )
    studioThinkingSpeech = StudioThinkingSpeechService()
    self.studioThinkingNarrationEnabled = studioThinkingNarrationEnabled
    studioThinkingSpeech.isEnabled = studioThinkingNarrationEnabled
    studioThinkingSpeech.attach(to: studioState)
  }
}

/// Result of a post-Develop verify pass — distinguishes retry-worthy
/// noise from issues the UI should display, and carries the raw verify
/// command output for the session record.
typealias PostCheckResult = FactoryPostCheckResult
