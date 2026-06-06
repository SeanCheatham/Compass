import AppKit
import Foundation

@MainActor
final class CompassProject: ObservableObject, Identifiable {
  let id: UUID
  @Published var repoURL: URL
  @Published var activeStorage: KnownProjectActiveStorage
  @Published var state = PlanState.empty
  @Published var drafts = ""
  @Published var draftEntry = ""
  @Published var lessons = ""
  @Published var assumptions: [AssumptionRecord] = []
  @Published var vision = ""
  @Published var productizationConfig = ProductizationConfig.empty
  @Published var productTournamentEvidenceIndex = ProductTournamentEvidenceIndex.empty
  @Published var sessions: [SessionRecord] = []
  @Published var archivedSessions: [SessionRecord] = []
  @Published var hasOlderArchivedSessions = false
  @Published var isLoadingArchivedSessions = false
  @Published var languageProfile = RepositoryLanguageProfile.empty
  @Published var forgeProfile: ForgeProfile?
  @Published var activitySourceSnapshot = RepositoryActivitySourceSnapshot.notScanned()
  @Published var nativeFeedbackMode: NativeFeedbackMode
  @Published var hostXcodeBuildTestEnabled: Bool
  @Published var liveLog: [LiveLine] = []
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
  let reflectSessionWindow = 10
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
    activeStorage: KnownProjectActiveStorage = .repoLocal,
    addedAt: Date = Date(),
    lastOpenedAt: Date = Date(),
    nativeFeedbackMode: NativeFeedbackMode = .notifications,
    hostXcodeBuildTestEnabled: Bool = false,
    storageApplicationSupportRoots: KnownProjectStore.ApplicationSupportRoots =
      KnownProjectStore.productionApplicationSupportRoots(),
    storageMigrationAction: @escaping CompassWorkspaceStorageMigrationAction = { plan in
      try CompassWorkspaceStorageMigrator().migrate(plan: plan)
    }
  ) {
    self.id = id
    self.repoURL = repoURL.standardizedFileURL
    self.activeStorage = activeStorage
    activitySourceSnapshot = RepositoryActivitySourceSnapshot.notScanned(
      activeStorage: activeStorage)
    self.addedAt = addedAt
    self.lastOpenedAt = lastOpenedAt
    self.nativeFeedbackMode = nativeFeedbackMode
    self.hostXcodeBuildTestEnabled = hostXcodeBuildTestEnabled
    self.storageApplicationSupportRoots = storageApplicationSupportRoots
    self.storageMigrationAction = storageMigrationAction
  }
}

/// Result of a post-Develop verify pass — distinguishes retry-worthy
/// noise from issues the UI should display, and carries the raw verify
/// command output for the session record.
struct PostCheckResult {
  var ok: Bool
  /// True when Develop found that the planned verify command itself
  /// needs a new Plan pass.
  var requiresPlanRepair: Bool
  /// Issues from the verify step (non-zero exit, blocked without bypass, etc.).
  var verifyIssues: [String]
  /// Issues from the git-status check (unexpected failure, dirty tree).
  var gitStatusIssues: [String]
  var verifyOutput: VerifyOutput?
}
