import AppKit
import Foundation
import Virtualization


@MainActor
final class CompassProject: ObservableObject, Identifiable {
  let id: UUID
  @Published var repoURL: URL
  @Published var activeStorage: KnownProjectActiveStorage
  @Published var state = PlanState.empty
  @Published var drafts = ""
  @Published var draftEntry = ""
  @Published var lessons = ""
  @Published var vision = ""
  @Published var sessions: [SessionRecord] = []
  @Published var languageProfile = RepositoryLanguageProfile.empty
  @Published var activitySourceSnapshot = RepositoryActivitySourceSnapshot.notScanned()
  @Published var nativeFeedbackMode: NativeFeedbackMode
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
  /// Session number the codemap was last refreshed for. When Plan and
  /// Develop fire back-to-back inside the same session the second call
  /// no-ops; a fresh Plan run (different session number) triggers a
  /// new refresh. Set in `refreshCodemapIfNeeded(...)`.
  var codemapRefreshedForSession: Int?
  let storageMigrationAction: CompassWorkspaceStorageMigrationAction
  let maxDevelopAttempts = 3
  /// Maximum number of adversarial Critic reviews per Develop iteration.
  /// After this many critic-rejected passes, Compass accepts the latest
  /// Develop output and proceeds — the loop has to terminate even when
  /// the critic and dev agents disagree forever. Each critic-driven
  /// retry re-runs the full Develop + post-checks inner loop with
  /// critic feedback added; worst case is `maxCriticAttempts *
  /// maxDevelopAttempts` Develop runs.
  let maxCriticAttempts = 3
  let reflectSessionWindow = 10

  init(
    id: UUID = UUID(),
    repoURL: URL,
    activeStorage: KnownProjectActiveStorage = .repoLocal,
    addedAt: Date = Date(),
    lastOpenedAt: Date = Date(),
    nativeFeedbackMode: NativeFeedbackMode = .notifications,
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
    self.storageApplicationSupportRoots = storageApplicationSupportRoots
    self.storageMigrationAction = storageMigrationAction
  }
}

/// Result of a post-Develop verify pass — distinguishes retry-worthy
/// noise from issues the UI should display, and carries the raw verify
/// command output for the session record.
struct PostCheckResult {
  var ok: Bool
  /// Issues from the verify step (non-zero exit, blocked without bypass, etc.).
  var verifyIssues: [String]
  /// Issues from the git-status check (unexpected failure, dirty tree).
  var gitStatusIssues: [String]
  var verifyOutput: VerifyOutput?
}
