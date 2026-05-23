import AppKit
import Foundation
import Virtualization

typealias CompassWorkspaceStorageMigrationAction = (CompassWorkspaceStorageMigrationPlan) throws ->
  CompassWorkspaceStorageMigrationResult

struct CompassWorkspaceStorageActivationConfirmation: Identifiable, Equatable {
  static let titleLimit = 58
  static let messageLimit = 900
  static let actionLabelLimit = 32

  var plan: CompassWorkspaceStorageActivationPlan

  var id: String {
    [
      plan.repoURL.path,
      plan.candidateURL.path,
      plan.projectStorageIdentifier,
    ]
    .joined(separator: "|")
  }

  var title: String {
    Self.boundedText("Activate Application Support storage?", limit: Self.titleLimit)
  }

  var message: String {
    Self.boundedText(
      [
        "Active state root: \(boundedPath(plan.candidateURL.path, limit: 220))",
        "Git/agent repo: \(boundedPath(plan.repoURL.path, limit: 180))",
        "Repo-local fallback: \(boundedPath(plan.repoLocalURL.path, limit: 180))",
        "This switches Compass state to the prepared Application Support candidate without changing the Git working directory.",
      ]
      .joined(separator: "\n"),
      limit: Self.messageLimit
    )
  }

  var confirmLabel: String {
    Self.boundedText("Activate Candidate", limit: Self.actionLabelLimit)
  }

  var cancelLabel: String {
    Self.boundedText("Cancel", limit: Self.actionLabelLimit)
  }

  private func boundedPath(_ value: String, limit: Int) -> String {
    Self.boundedPath(value, limit: limit)
  }

  private static func boundedPath(_ value: String, limit: Int) -> String {
    guard value.count > limit else { return value }
    guard limit > 3 else { return String(value.prefix(max(0, limit))) }
    return "..." + value.suffix(max(0, limit - 3))
  }

  private static func boundedText(_ value: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard value.count > limit else { return value }
    guard limit > 3 else { return String(value.prefix(limit)) }
    return value.prefix(limit - 3)
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}

struct CompassProjectActiveStorageState: Equatable {
  static let labelLimit = 38
  static let detailLimit = 280
  static let helpLimit = 560

  enum Phase: Equatable {
    case idle
    case awaitingConfirmation
    case running
    case succeeded
    case failed
    case blocked
  }

  var phase: Phase
  var label: String
  var detail: String
  var systemImage: String

  var isRunning: Bool {
    phase == .running
  }

  var shouldShowFeedback: Bool {
    phase != .idle
  }

  var helpText: String {
    Self.boundedText(
      [label, detail]
        .filter { !$0.isEmpty }
        .joined(separator: " - "),
      limit: Self.helpLimit
    )
  }

  static let idle = CompassProjectActiveStorageState(
    phase: .idle,
    label: "Activate storage",
    detail:
      "Switch a prepared Application Support candidate into active Compass state while keeping repoURL as the Git/agent workspace.",
    systemImage: "externaldrive.badge.checkmark"
  )

  static func awaitingConfirmation(_ confirmation: CompassWorkspaceStorageActivationConfirmation)
    -> Self
  {
    Self(
      phase: .awaitingConfirmation,
      label: "Confirm activation",
      detail:
        "Review the active-storage switch before Compass starts reading Application Support state.",
      systemImage: confirmation.plan.systemImage
    )
  }

  static func running(plan: CompassWorkspaceStorageActivationPlan) -> Self {
    Self(
      phase: .running,
      label: "Activating storage",
      detail:
        "Switching active Compass state to \(boundedPath(plan.candidateURL.path, limit: 144)).",
      systemImage: "externaldrive.badge.checkmark"
    )
  }

  static func succeeded(plan: CompassWorkspaceStorageActivationPlan) -> Self {
    Self(
      phase: .succeeded,
      label: "Support storage active",
      detail:
        "Compass now reads and writes state at \(boundedPath(plan.candidateURL.path, limit: 144)); repoURL remains \(boundedPath(plan.repoURL.path, limit: 96)).",
      systemImage: "checkmark.circle.fill"
    )
  }

  static func failed(_ error: Error) -> Self {
    Self(
      phase: .failed,
      label: "Activation failed",
      detail: error.localizedDescription,
      systemImage: "exclamationmark.triangle.fill"
    )
  }

  static func blocked(plan: CompassWorkspaceStorageActivationPlan) -> Self {
    Self(
      phase: .blocked,
      label: plan.label,
      detail: plan.detail,
      systemImage: plan.systemImage
    )
  }

  static func blockedWhileBusy() -> Self {
    Self(
      phase: .blocked,
      label: "Activation blocked",
      detail: "Stop or finish the active Compass run before switching active storage.",
      systemImage: "pause.circle.fill"
    )
  }

  init(phase: Phase, label: String, detail: String, systemImage: String) {
    self.phase = phase
    self.label = Self.boundedText(label, limit: Self.labelLimit)
    self.detail = Self.boundedText(detail, limit: Self.detailLimit)
    self.systemImage = systemImage
  }

  private static func boundedPath(_ value: String, limit: Int) -> String {
    guard value.count > limit else { return value }
    guard limit > 3 else { return String(value.prefix(max(0, limit))) }
    return "..." + value.suffix(max(0, limit - 3))
  }

  private static func boundedText(_ value: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard value.count > limit else { return value }
    guard limit > 3 else { return String(value.prefix(limit)) }
    return value.prefix(limit - 3)
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}

enum CompassProjectActiveStorageActivationError: LocalizedError, Equatable {
  case unavailable(CompassWorkspaceStorageActivationPlan.Kind, String)
  case rolledBack(primary: String, rollbackFailure: String?)

  var errorDescription: String? {
    switch self {
    case .unavailable(_, let detail):
      return "Active-storage activation is unavailable: \(detail)"
    case .rolledBack(let primary, let rollbackFailure):
      if let rollbackFailure {
        return
          "Activation failed and Compass rolled back to repo-local storage. Primary failure: \(primary) Rollback persistence also failed: \(rollbackFailure)"
      }
      return
        "Activation failed and Compass rolled back to repo-local storage. Primary failure: \(primary)"
    }
  }
}

struct CompassWorkspaceStorageMigrationConfirmation: Identifiable, Equatable {
  static let titleLimit = 58
  static let messageLimit = 900
  static let actionLabelLimit = 32

  var plan: CompassWorkspaceStorageMigrationPlan

  var id: String {
    [
      plan.repoURL.path,
      plan.destinationURL.path,
      plan.manifestURL.path,
    ]
    .joined(separator: "|")
  }

  var title: String {
    Self.boundedText("Prepare Application Support storage?", limit: Self.titleLimit)
  }

  var message: String {
    Self.boundedText(
      [
        "Source: \(boundedPath(plan.sourceCompassURL.path, limit: 160))",
        "Destination: \(boundedPath(plan.destinationURL.path, limit: 220))",
        "Manifest: \(boundedPath(plan.manifestURL.path, limit: 220))",
        "No active-storage switch: repo-local .compass/ remains the source of truth after this copy.",
      ]
      .joined(separator: "\n"),
      limit: Self.messageLimit
    )
  }

  var confirmLabel: String {
    Self.boundedText("Prepare Candidate", limit: Self.actionLabelLimit)
  }

  var cancelLabel: String {
    Self.boundedText("Cancel", limit: Self.actionLabelLimit)
  }

  private func boundedPath(_ value: String, limit: Int) -> String {
    Self.boundedPath(value, limit: limit)
  }

  private static func boundedPath(_ value: String, limit: Int) -> String {
    guard value.count > limit else { return value }
    guard limit > 3 else { return String(value.prefix(max(0, limit))) }
    return "..." + value.suffix(max(0, limit - 3))
  }

  private static func boundedText(_ value: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard value.count > limit else { return value }
    guard limit > 3 else { return String(value.prefix(limit)) }
    return value.prefix(limit - 3)
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}

struct CompassProjectStorageMigrationState: Equatable {
  static let labelLimit = 38
  static let detailLimit = 260
  static let helpLimit = 520

  enum Phase: Equatable {
    case idle
    case awaitingConfirmation
    case running
    case succeeded
    case failed
    case blocked
  }

  var phase: Phase
  var label: String
  var detail: String
  var systemImage: String

  var isRunning: Bool {
    phase == .running
  }

  var shouldShowFeedback: Bool {
    phase != .idle
  }

  var helpText: String {
    Self.boundedText(
      [label, detail]
        .filter { !$0.isEmpty }
        .joined(separator: " - "),
      limit: Self.helpLimit
    )
  }

  static let idle = CompassProjectStorageMigrationState(
    phase: .idle,
    label: "Prepare storage",
    detail:
      "Copy repo-local .compass/ to Application Support as an opt-in candidate. Repo-local remains active.",
    systemImage: "arrow.triangle.2.circlepath"
  )

  static func awaitingConfirmation(_ confirmation: CompassWorkspaceStorageMigrationConfirmation)
    -> Self
  {
    Self(
      phase: .awaitingConfirmation,
      label: "Confirm storage copy",
      detail: "Review the Application Support candidate transaction before it runs.",
      systemImage: confirmation.plan.systemImage
    )
  }

  static func running(plan: CompassWorkspaceStorageMigrationPlan) -> Self {
    Self(
      phase: .running,
      label: "Preparing storage",
      detail:
        "Copying repo-local .compass/ to \(boundedPath(plan.destinationURL.path, limit: 128)); repo-local remains active.",
      systemImage: "arrow.triangle.2.circlepath"
    )
  }

  static func succeeded(_ result: CompassWorkspaceStorageMigrationResult) -> Self {
    Self(
      phase: .succeeded,
      label: "Storage candidate ready",
      detail: result.detail,
      systemImage: "checkmark.circle.fill"
    )
  }

  static func failed(_ error: Error) -> Self {
    Self(
      phase: .failed,
      label: "Storage copy failed",
      detail: error.localizedDescription,
      systemImage: "exclamationmark.triangle.fill"
    )
  }

  static func blocked(plan: CompassWorkspaceStorageMigrationPlan) -> Self {
    Self(
      phase: .blocked,
      label: plan.label,
      detail: plan.detail,
      systemImage: plan.systemImage
    )
  }

  static func blockedWhileRunning() -> Self {
    Self(
      phase: .blocked,
      label: "Migration blocked",
      detail: "Stop the active agent run before preparing Application Support candidate storage.",
      systemImage: "pause.circle.fill"
    )
  }

  init(phase: Phase, label: String, detail: String, systemImage: String) {
    self.phase = phase
    self.label = Self.boundedText(label, limit: Self.labelLimit)
    self.detail = Self.boundedText(detail, limit: Self.detailLimit)
    self.systemImage = systemImage
  }

  private static func boundedPath(_ value: String, limit: Int) -> String {
    guard value.count > limit else { return value }
    guard limit > 3 else { return String(value.prefix(max(0, limit))) }
    return "..." + value.suffix(max(0, limit - 3))
  }

  private static func boundedText(_ value: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard value.count > limit else { return value }
    guard limit > 3 else { return String(value.prefix(limit)) }
    return value.prefix(limit - 3)
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}

enum CompassProjectStorageMigrationActionError: LocalizedError, Equatable {
  case activeStorageChanged
  case repoLocalSourceMissing(String)

  var errorDescription: String? {
    switch self {
    case .activeStorageChanged:
      return
        "Storage migration unexpectedly reported an active-storage switch; repo-local .compass/ must remain active."
    case .repoLocalSourceMissing(let path):
      return "Repo-local .compass/ was not preserved at \(path)."
    }
  }
}

enum PlanReadinessNativeFeedbackGate: String, Equatable {
  case planOnly = "plan-only"
  case pausedBeforeDevelop = "paused-before-develop"
}

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

  private var workspace: CompassWorkspace? {
    guard FileManager.default.fileExists(atPath: repoURL.path),
      let repoURL = CompassWorkspace.discover(from: repoURL)
    else { return nil }
    return makeWorkspace(repoURL: repoURL)
  }

  private var executor: AgentExecutor?
  private var stopRequested = false
  /// Session number the codemap was last refreshed for. When Plan and
  /// Develop fire back-to-back inside the same session the second call
  /// no-ops; a fresh Plan run (different session number) triggers a
  /// new refresh. Set in `refreshCodemapIfNeeded(...)`.
  private var codemapRefreshedForSession: Int?
  private let storageMigrationAction: CompassWorkspaceStorageMigrationAction
  private let mutationTestingRunner: ProcessRunner.InvocationRunner?
  private let maxDevelopAttempts = 3
  /// Maximum number of adversarial Critic reviews per Develop iteration.
  /// After this many critic-rejected passes, Compass accepts the latest
  /// Develop output and proceeds — the loop has to terminate even when
  /// the critic and dev agents disagree forever. Each critic-driven
  /// retry re-runs the full Develop + post-checks inner loop with
  /// critic feedback added; worst case is `maxCriticAttempts *
  /// maxDevelopAttempts` Develop runs.
  private let maxCriticAttempts = 3
  private let reflectSessionWindow = 10

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
    },
    mutationTestingRunner: ProcessRunner.InvocationRunner? = nil
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
    self.mutationTestingRunner = mutationTestingRunner
  }
}

@MainActor
extension CompassProject {
  var displayName: String {
    repoURL.lastPathComponent
  }

  var repoPath: String {
    repoURL.path
  }

  var compassPath: String {
    makeStorageResolver(repoURL: repoURL).storageRootURL.path
  }

  var agentExecutionEnvironment: AgentExecutionEnvironment {
    AgentExecutionEnvironment.discover(
      vmReadiness: SharedCompassVM.shared.readiness
    )
  }

  var runtimeDiagnosticsMenu: AgentExecutionEnvironmentMenu {
    let environment = agentExecutionEnvironment
    // Both Develop and mutation testing route off the main repo
    // URL now (the per-iteration host worktree concept is gone),
    // so the env-presentation plan and the mutation-testing plan
    // share the same launch plan.
    let envLaunchPlan = agentLaunchPlan(for: repoURL)
    let mutationLaunchPlan = envLaunchPlan
    let mutationTestingPlan = AgentMutationTestingPlan(
      state: state,
      languageProfile: languageProfile,
      launchPlan: mutationLaunchPlan
    )
    let mutationRecoveryDescriptor = MutationTestingRecoveryDescriptor.runtimeDescriptor(
      sessions: sessions,
      readiness: mutationTestingPlan
    )
    return AgentExecutionEnvironmentMenu(
      environment: environment,
      launchPlan: envLaunchPlan,
      mutationTestingPlan: mutationTestingPlan,
      mutationRecoveryDescriptor: mutationRecoveryDescriptor,
      mutationExecutionState: mutationTestingExecutionState
    )
  }

  var hasRepository: Bool {
    workspace != nil
  }

  var canStop: Bool {
    isRunning || isAutoPlaying || isPaused
  }

  var immediateTitle: String {
    guard let immediate = state.immediate else { return "No immediate plan" }
    return immediate.plan
      .split(whereSeparator: \.isNewline)
      .first
      .map(String.init) ?? "Immediate plan"
  }

  func initializeWorkspace() async {
    do {
      guard let workspace else {
        fail(AppModelError.noRepositorySelected)
        return
      }
      try workspace.initialize()
      log("Initialized \(workspace.compassURL.path)", level: .success)
      await refresh()
    } catch {
      fail(error)
    }
  }

  func refresh() async {
    do {
      try await refreshFromWorkspace(requireStorageRoot: false)
    } catch {
      fail(error)
    }
  }

  private func refreshFromWorkspace(requireStorageRoot: Bool) async throws {
    guard let workspace else {
      state = .empty
      drafts = ""
      lessons = ""
      vision = ""
      sessions = []
      activitySourceSnapshot = RepositoryActivitySourceSnapshot.noRepository(
        activeStorage: activeStorage
      )
      languageProfile = .empty
      if requireStorageRoot {
        throw AppModelError.noRepositorySelected
      }
      return
    }

    languageProfile = RepositoryLanguageProfileService.scan(repoURL: workspace.repoURL)
    activitySourceSnapshot = RepositoryActivitySourceSnapshot.snapshot(
      activeStorage: activeStorage,
      workspace: workspace
    )

    if !FileManager.default.fileExists(atPath: workspace.compassURL.path) {
      state = .empty
      drafts = ""
      lessons = ""
      vision = ""
      sessions = []
      if requireStorageRoot {
        throw AppModelError.internalInvariant(
          "Active Compass storage root is missing at \(workspace.compassURL.path)."
        )
      }
      return
    }

    state = try workspace.readState()
    drafts = workspace.readDrafts()
    lessons = workspace.readLessons()
    vision = workspace.readVision()
    sessions = workspace.readSessions()
  }

  func saveVision() async {
    do {
      guard let workspace else {
        fail(AppModelError.noRepositorySelected)
        return
      }
      try await initializeIfNeeded(workspace)
      try workspace.writeVision(vision)
      log("Saved vision.", level: .success)
    } catch {
      fail(error)
    }
  }

  func saveLessons() async {
    do {
      guard let workspace else {
        fail(AppModelError.noRepositorySelected)
        return
      }
      try await initializeIfNeeded(workspace)
      try workspace.writeLessons(lessons)
      log("Saved lessons.", level: .success)
    } catch {
      fail(error)
    }
  }

  func saveDrafts() async {
    do {
      guard let workspace else {
        fail(AppModelError.noRepositorySelected)
        return
      }
      try await initializeIfNeeded(workspace)
      try workspace.writeDrafts(drafts)
      log("Saved drafts.", level: .success)
    } catch {
      fail(error)
    }
  }

  func addDraft() async {
    await queueDraft(
      draftEntry,
      clearsDraftEntry: true,
      feedback: "Draft queued."
    )
  }

  func acceptDraftRefinement(_ refinement: DraftRefinement) async {
    await queueDraft(
      refinement.refinedText,
      clearsDraftEntry: true,
      feedback: "Refined draft queued."
    )
  }

  func modifyDraft(with refinement: DraftRefinement) {
    draftEntry = refinement.refinedText
  }

  private func queueDraft(
    _ text: String,
    clearsDraftEntry: Bool,
    feedback: String
  ) async {
    do {
      guard let workspace else {
        fail(AppModelError.noRepositorySelected)
        return
      }
      try await initializeIfNeeded(workspace)
      try workspace.appendDraft(text)
      if clearsDraftEntry {
        draftEntry = ""
      }
      drafts = workspace.readDrafts()
      log(feedback, level: .success)
    } catch {
      fail(error)
    }
  }

  func activeStorageActivationPlan() -> CompassWorkspaceStorageActivationPlan {
    CompassWorkspaceStorageActivationPlan(
      repoURL: repoURL,
      activeStorage: activeStorage,
      applicationSupportRoots: storageApplicationSupportRoots
    )
  }

  func prepareActiveStorageActivationConfirmation() {
    guard isIdleForActiveStorageActivation else {
      activeStorageActivationConfirmation = nil
      activeStorageActivationState = .blockedWhileBusy()
      errorMessage = activeStorageActivationState.detail
      log(activeStorageActivationState.detail, level: .warning)
      return
    }

    let plan = activeStorageActivationPlan()
    guard plan.isAvailable else {
      activeStorageActivationConfirmation = nil
      activeStorageActivationState = .blocked(plan: plan)
      errorMessage = activeStorageActivationState.detail
      log(
        "Active storage activation blocked: \(activeStorageActivationState.detail)", level: .warning
      )
      return
    }

    let confirmation = CompassWorkspaceStorageActivationConfirmation(plan: plan)
    activeStorageActivationConfirmation = confirmation
    activeStorageActivationState = .awaitingConfirmation(confirmation)
    errorMessage = nil
  }

  func cancelActiveStorageActivationConfirmation() {
    activeStorageActivationConfirmation = nil
    if activeStorageActivationState.phase == .awaitingConfirmation {
      activeStorageActivationState = .idle
    }
  }

  func confirmActiveStorageActivation(
    _ confirmation: CompassWorkspaceStorageActivationConfirmation,
    persistProjectRegistry: () throws -> Void
  ) async {
    activeStorageActivationConfirmation = nil

    guard isIdleForActiveStorageActivation else {
      activeStorageActivationState = .blockedWhileBusy()
      errorMessage = activeStorageActivationState.detail
      log(activeStorageActivationState.detail, level: .warning)
      return
    }

    let plan = activeStorageActivationPlan()
    guard plan.isAvailable else {
      let error = CompassProjectActiveStorageActivationError.unavailable(plan.kind, plan.detail)
      activeStorageActivationState = .failed(error)
      errorMessage = activeStorageActivationState.detail
      log(activeStorageActivationState.detail, level: .error)
      return
    }

    activeStorageActivationState = .running(plan: plan)
    errorMessage = nil
    log(
      "Active storage activation: switching Compass state to \(plan.candidateURL.path).",
      level: .info)
    await Task.yield()

    let previousStorage = activeStorage
    do {
      activeStorage = .applicationSupport
      try persistProjectRegistry()
      try await refreshFromWorkspace(requireStorageRoot: true)

      activeStorageActivationState = .succeeded(plan: plan)
      errorMessage = nil
      log(activeStorageActivationState.detail, level: .success)
    } catch {
      let rollbackFailure = await rollbackActiveStorage(
        to: previousStorage,
        persistProjectRegistry: persistProjectRegistry
      )
      let rollbackError = CompassProjectActiveStorageActivationError.rolledBack(
        primary: error.localizedDescription,
        rollbackFailure: rollbackFailure
      )
      activeStorageActivationState = .failed(rollbackError)
      errorMessage = activeStorageActivationState.detail
      log(activeStorageActivationState.detail, level: .error)
    }
  }

  func storageMigrationPlan() -> CompassWorkspaceStorageMigrationPlan {
    CompassWorkspaceStorageMigrationPlan(
      repoURL: repoURL,
      applicationSupportRoots: storageApplicationSupportRoots
    )
  }

  func prepareStorageMigrationConfirmation() {
    guard !isRunning, !isAutoPlaying else {
      storageMigrationConfirmation = nil
      storageMigrationState = .blockedWhileRunning()
      errorMessage = storageMigrationState.detail
      log(storageMigrationState.detail, level: .warning)
      return
    }

    let plan = storageMigrationPlan()
    guard plan.isAvailable else {
      storageMigrationConfirmation = nil
      storageMigrationState = .blocked(plan: plan)
      errorMessage = storageMigrationState.detail
      log("Storage migration blocked: \(storageMigrationState.detail)", level: .warning)
      return
    }

    let confirmation = CompassWorkspaceStorageMigrationConfirmation(plan: plan)
    storageMigrationConfirmation = confirmation
    storageMigrationState = .awaitingConfirmation(confirmation)
    errorMessage = nil
  }

  func cancelStorageMigrationConfirmation() {
    storageMigrationConfirmation = nil
    if storageMigrationState.phase == .awaitingConfirmation {
      storageMigrationState = .idle
    }
  }

  func confirmStorageMigration(_ confirmation: CompassWorkspaceStorageMigrationConfirmation) async {
    storageMigrationConfirmation = nil

    guard !isRunning, !isAutoPlaying else {
      storageMigrationState = .blockedWhileRunning()
      errorMessage = storageMigrationState.detail
      log(storageMigrationState.detail, level: .warning)
      return
    }

    let plan = confirmation.plan
    guard plan.isAvailable else {
      storageMigrationState = .blocked(plan: plan)
      errorMessage = storageMigrationState.detail
      log("Storage migration blocked: \(storageMigrationState.detail)", level: .warning)
      return
    }

    storageMigrationState = .running(plan: plan)
    errorMessage = nil
    log(
      "Storage migration: preparing Application Support candidate at \(plan.destinationURL.path).",
      level: .info)
    await Task.yield()

    do {
      let result = try storageMigrationAction(plan)
      guard result.activeStorageDidChange == false else {
        throw CompassProjectStorageMigrationActionError.activeStorageChanged
      }
      guard FileManager.default.fileExists(atPath: plan.sourceCompassURL.path) else {
        throw CompassProjectStorageMigrationActionError.repoLocalSourceMissing(
          plan.sourceCompassURL.path)
      }

      storageMigrationState = .succeeded(result)
      log(storageMigrationState.detail, level: .success)
      await refresh()
    } catch {
      storageMigrationState = .failed(error)
      errorMessage = storageMigrationState.detail
      log(storageMigrationState.detail, level: .error)
    }
  }

  func play(agentSettings: AgentRuntimeSettings, modelOverride: String) async {
    guard !isRunning, !isAutoPlaying else { return }
    stopRequested = false
    let resumedFromPause = isPaused
    isAutoPlaying = true
    isPaused = false
    pauseMode = .immediate

    if resumedFromPause,
      let sessionIndex = latestAwaitingDevelopSessionIndex(),
      state.immediate != nil
    {
      log("Auto-play resumed.", level: .success)
      await runDevelopPass(
        existingSessionIndex: sessionIndex,
        agentSettings: agentSettings,
        modelOverride: modelOverride
      )
    } else {
      log("Auto-play started.", level: .success)
    }

    while isAutoPlaying, !isPaused, !stopRequested {
      guard phase != .failed, phase != .cancelled else {
        isAutoPlaying = false
        return
      }

      await runPlanPass(
        continueToDevelop: true,
        agentSettings: agentSettings,
        modelOverride: modelOverride
      )

      if state.immediate == nil, phase == .idle {
        isAutoPlaying = false
        log("Auto-play stopped: no immediate work.", level: .info)
        return
      }

      if phase == .failed || phase == .cancelled {
        isAutoPlaying = false
        return
      }

      await Task.yield()
    }
  }

  func runPlanOnly(agentSettings: AgentRuntimeSettings, modelOverride: String) async {
    guard !isRunning else { return }
    isAutoPlaying = false
    await runPlanPass(
      continueToDevelop: false,
      agentSettings: agentSettings,
      modelOverride: modelOverride
    )
  }

  func runDevelopOnly(agentSettings: AgentRuntimeSettings, modelOverride: String) async {
    guard !isRunning else { return }
    isAutoPlaying = false
    isPaused = false
    await runDevelopPass(
      existingSessionIndex: nil,
      agentSettings: agentSettings,
      modelOverride: modelOverride
    )
  }

  func runMutationTesting() async {
    let initialLaunchPlan = agentLaunchPlan(for: repoURL)
    let initialReadiness = AgentMutationTestingPlan(
      state: state,
      languageProfile: languageProfile,
      launchPlan: initialLaunchPlan
    )
    let initialAction = AgentMutationTestingMenuAction(
      readiness: initialReadiness,
      executionState: mutationTestingExecutionState
    )

    guard isIdleForMutationTesting else {
      errorMessage = initialAction.helpText
      log(initialAction.helpText, level: .warning)
      return
    }

    let workspace: CompassWorkspace
    do {
      workspace = try await resolveWorkspaceForRun()
      try await initializeIfNeeded(workspace)
      state = try workspace.readState()
    } catch {
      fail(error)
      return
    }

    let launchPlan = agentLaunchPlan(for: workspace.repoURL)
    let readiness = AgentMutationTestingPlan(
      state: state,
      languageProfile: languageProfile,
      launchPlan: launchPlan
    )
    let action = AgentMutationTestingMenuAction(
      readiness: readiness,
      executionState: .idle
    )

    guard readiness.isReady,
      let next = state.immediate
    else {
      errorMessage = action.helpText
      log(action.helpText, level: .warning)
      return
    }

    let command = next.verify.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !command.isEmpty else {
      errorMessage = action.helpText
      log(action.helpText, level: .warning)
      return
    }

    isRunning = true
    isAutoPlaying = false
    isPaused = false
    phase = .verifying
    errorMessage = nil
    let sessionIndex = startSession()
    guard sessions.indices.contains(sessionIndex) else {
      fail(AppModelError.internalInvariant("Could not start a mutation testing session."))
      isRunning = false
      phase = .failed
      return
    }

    sessions[sessionIndex].status = .developing
    sessions[sessionIndex].endedAt = nil
    try? persistSessions()

    logExecutionEnvironmentPreflight(
      phase: "Mutation",
      nativeExecutionURL: workspace.repoURL,
      launchPlan: launchPlan,
      sessionIndex: sessionIndex
    )
    log(
      "Mutation testing: running `\(readiness.seedCommandLabel)` through \(readiness.routeLabel).",
      level: .info
    )

    let startedAt = Date().timeIntervalSince1970 * 1000
    let timeoutMs = verifyTimeoutMs(for: next)
    do {
      let result = try await ProcessRunner.runShell(
        command,
        workingDirectory: workspace.repoURL,
        timeout: TimeInterval(timeoutMs) / 1000,
        launchPlan: launchPlan,
        runner: mutationTestingRunner
      )
      let endedAt = Date().timeIntervalSince1970 * 1000
      let execution = SessionMutationTestingExecution(
        readiness: readiness,
        exitCode: Int(result.exitCode),
        startedAt: startedAt,
        endedAt: endedAt,
        outputTail: result.stdout + result.stderr,
        launchPlan: launchPlan
      )
      if sessions.indices.contains(sessionIndex) {
        sessions[sessionIndex].recordMutationTestingExecution(execution)
      }

      if result.exitCode == 0 {
        endSession(sessionIndex, status: .succeeded)
        phase = .succeeded
        log("Mutation testing completed.", level: .success)
      } else {
        endSession(sessionIndex, status: .failed)
        phase = .failed
        log("Mutation testing failed (exit \(result.exitCode)).", level: .error)
      }
    } catch {
      let endedAt = Date().timeIntervalSince1970 * 1000
      let safeError = AgentMutationTestingMetadataSanitizer.sanitizedOutputTail(
        error.localizedDescription,
        launchPlan: launchPlan,
        limit: 360
      )
      let execution = SessionMutationTestingExecution(
        readiness: readiness,
        exitCode: nil,
        startedAt: startedAt,
        endedAt: endedAt,
        outputTail: safeError,
        launchPlan: launchPlan
      )
      if sessions.indices.contains(sessionIndex) {
        sessions[sessionIndex].recordMutationTestingExecution(execution)
      }
      endSession(sessionIndex, status: .failed)
      phase = .failed
      errorMessage = safeError
      log("Mutation testing failed: \(safeError)", level: .error)
    }

    isRunning = false
    executor = nil
    await refresh()
  }

  func requestPause(_ mode: PauseMode) {
    if isPaused && (mode == .afterIteration || mode == pauseMode) {
      return
    }

    isPaused = true
    isAutoPlaying = false
    pauseMode = mode
    let pausedImmediately = !isRunning
    if !isRunning {
      phase = .paused
    }
    switch mode {
    case .immediate:
      log("Pause requested: stopping at the next gate.", level: .warning)
    case .afterIteration:
      log("Pause requested: after this iteration.", level: .warning)
    }
    if pausedImmediately {
      feedback(.paused)
    }
  }

  func stopRun() {
    let wasRunning = isRunning
    stopRequested = wasRunning
    executor?.cancel()
    isAutoPlaying = false
    isPaused = false
    pauseMode = .immediate
    phase = .cancelled
    isRunning = wasRunning
    if let sessionIndex = latestAwaitingDevelopSessionIndex() {
      endSession(sessionIndex, status: .cancelled)
    }
    if !wasRunning {
      stopRequested = false
    }
    log("Stop requested.", level: .warning)
    if !wasRunning {
      feedback(.stopped)
    }
  }

  private func runPlanPass(
    continueToDevelop: Bool,
    agentSettings: AgentRuntimeSettings,
    modelOverride: String
  ) async {
    let workspace: CompassWorkspace
    do {
      workspace = try await resolveWorkspaceForRun()
    } catch {
      fail(error)
      return
    }

    do {
      try await initializeIfNeeded(workspace)
    } catch {
      fail(error)
      return
    }

    isRunning = true
    phase = .planning
    errorMessage = nil
    let sessionIndex = startSession()
    guard sessions.indices.contains(sessionIndex) else {
      fail(AppModelError.internalInvariant("Could not start a Compass session."))
      isRunning = false
      phase = .failed
      return
    }
    let sessionNumber = sessions[sessionIndex].session
    var consumedDrafts = ""

    do {
      try workspace.backupStateFile()
      await refreshCodemapIfNeeded(
        workspace: workspace,
        sessionNumber: sessionNumber,
        agentSettings: agentSettings
      )
      try await runReflectIfNeeded(
        workspace,
        sessionIndex: sessionIndex,
        agentSettings: agentSettings,
        modelOverride: modelOverride
      )

      let priorFeedback = previousFeedback(excluding: sessionNumber)
      consumedDrafts = try workspace.snapshotAndClearDrafts()
      drafts = ""

      let currentState = try workspace.readState()
      log(
        "Plan input: \(workspace.stateURL.path) (\(currentState.completed.count) completed, immediate: \(firstLine(currentState.immediate?.plan) ?? "none")).",
        level: .info
      )

      let prompt = try Prompts.planPrompt(
        state: currentState,
        drafts: consumedDrafts,
        feedback: priorFeedback,
        lessons: workspace.readLessons(),
        vision: workspace.readVision()
      )
      let promptURL = try workspace.writeSessionArtifact(
        session: sessionNumber,
        name: "plan-prompt.md",
        contents: prompt
      )
      log("Saved Plan prompt: \(promptURL.path)", level: .info)

      let launchPlan = agentLaunchPlan(for: workspace.repoURL)
      logExecutionEnvironmentPreflight(
        phase: "Plan",
        nativeExecutionURL: workspace.repoURL,
        launchPlan: launchPlan,
        sessionIndex: sessionIndex
      )
      log("Plan: launching agent.", level: .info)
      let planResult = try await runAgent(
        phase: .plan,
        agentSettings: agentSettings,
        modelOverride: modelOverride,
        workingDirectory: workspace.repoURL,
        userPrompt: prompt,
        submitResultSchema: Prompts.planSchema,
        decode: PlanRunResult.self
      )
      let nextState = planResult.state

      try validatePlanTransition(from: currentState, to: nextState)
      let lessonEditCount = try workspace.applyLessonEdits(planResult.lessonEdits)
      try workspace.writeState(nextState)
      logLessonEdits(lessonEditCount)
      state = nextState
      log(
        "Plan accepted: \(nextState.completed.count) completed, immediate: \(firstLine(nextState.immediate?.plan) ?? "none").",
        level: .success
      )
      feedback(.planAccepted)
      guard sessions.indices.contains(sessionIndex) else {
        throw AppModelError.internalInvariant("Session #\(sessionNumber) disappeared during Plan.")
      }
      sessions[sessionIndex].plan = nextState.immediate?.plan
      sessions[sessionIndex].verify = nextState.immediate?.verify
      try persistSessions()

      if nextState.immediate == nil {
        endSession(sessionIndex, status: .skipped)
        phase = .idle
        log("Plan returned no immediate work.", level: .info)
        feedback(.noImmediateWork)
        isRunning = false
        executor = nil
        await refresh()
        return
      }

      log("Plan selected: \(immediateTitle)", level: .success)

      if continueToDevelop {
        if isPaused && pauseMode == .immediate {
          guard sessions.indices.contains(sessionIndex) else {
            throw AppModelError.internalInvariant(
              "Session #\(sessionNumber) disappeared while pausing.")
          }
          sessions[sessionIndex].status = .awaitingApproval
          sessions[sessionIndex].endedAt = nil
          try persistSessions()
          phase = .paused
          log("Paused before Develop.", level: .warning)
          feedbackPlanReadinessGate(for: nextState, gate: .pausedBeforeDevelop)
          isRunning = false
          executor = nil
          await refresh()
          return
        }

        isRunning = false
        executor = nil
        await runDevelopPass(
          existingSessionIndex: sessionIndex,
          agentSettings: agentSettings,
          modelOverride: modelOverride
        )
      } else {
        appendSessionNote("Plan-only run; Develop was not started.", to: sessionIndex)
        endSession(sessionIndex, status: .awaitingApproval)
        phase = .idle
        feedbackPlanReadinessGate(for: nextState, gate: .planOnly)
        isRunning = false
        executor = nil
      }
    } catch {
      if stopRequested {
        stopRequested = false
        if !consumedDrafts.isEmpty {
          let current = workspace.readDrafts()
          try? workspace.writeDrafts(
            [consumedDrafts, current].filter { !$0.isEmpty }.joined(separator: "\n"))
        }
        appendSessionNote("Stopped by user.", to: sessionIndex)
        endSession(sessionIndex, status: .cancelled)
        phase = .cancelled
        isRunning = false
        executor = nil
        log("Run stopped.", level: .warning)
        feedback(.stopped)
        await refresh()
        return
      }

      if !consumedDrafts.isEmpty {
        let current = workspace.readDrafts()
        try? workspace.writeDrafts(
          [consumedDrafts, current].filter { !$0.isEmpty }.joined(separator: "\n"))
      }
      appendSessionNote(error.localizedDescription, to: sessionIndex)
      endSession(sessionIndex, status: .failed)
      phase = .failed
      isRunning = false
      executor = nil
      fail(error)
    }

    await refresh()
  }

  private func runDevelopPass(
    existingSessionIndex: Int?,
    agentSettings: AgentRuntimeSettings,
    modelOverride: String
  ) async {
    let workspace: CompassWorkspace
    do {
      workspace = try await resolveWorkspaceForRun()
    } catch {
      fail(error)
      return
    }

    do {
      try await initializeIfNeeded(workspace)
      state = try workspace.readState()
    } catch {
      fail(error)
      return
    }

    guard let next = state.immediate else {
      log("No immediate plan to develop.", level: .warning)
      feedback(.noImmediateWork)
      return
    }

    isRunning = true
    phase = .developing
    errorMessage = nil
    let sessionIndex = existingSessionIndex ?? startSession()
    guard sessions.indices.contains(sessionIndex) else {
      fail(AppModelError.internalInvariant("Could not start a Develop session."))
      isRunning = false
      phase = .failed
      return
    }
    sessions[sessionIndex].status = .developing
    sessions[sessionIndex].endedAt = nil
    sessions[sessionIndex].plan = next.plan
    sessions[sessionIndex].verify = next.verify
    let beforeSha = await gitCurrentSha(at: workspace.repoURL)
    sessions[sessionIndex].beforeSha = beforeSha
    try? persistSessions()
    feedback(.developStarted)

    await refreshCodemapIfNeeded(
      workspace: workspace,
      sessionNumber: sessions[sessionIndex].session,
      agentSettings: agentSettings
    )

    do {
      // The Develop iteration operates directly on `workspace.repoURL`.
      // Under the `.sharedVM` route the route layer remaps that URL
      // through `SharedCompassVMGuestWorkspaceCatalog` to a persistent
      // per-repo guest workspace under `/Users/compass/Compass/Repos/
      // <UUID>/worktree` and the agent runs there; under the host
      // route the agent runs in the user's working tree directly.
      // Either way, only one workspace handle is in play per
      // iteration, so Develop and Verify can't desynchronize onto
      // different catalog entries.

      var finalIssues: [String] = []
      var finalVerifyOutput: VerifyOutput?
      var succeeded = false
      var criticFeedbacks: [String] = []
      var criticAttempt = 0

      // Outer loop: adversarial Critic review gates each successful
      // Develop+post-check pass. On critic-reject Develop re-runs with
      // the critic's feedback added; capped at `maxCriticAttempts` so
      // the iteration always terminates.
      criticLoop: while true {
        var priorIssues: [String] = []
        var postChecksPassed = false
        var postCheckSummary: DevelopSummary?
        var postCheckLaunchPlan: AgentExecutionLaunchPlan?

        for attempt in 1...maxDevelopAttempts {
          phase = .developing
          let prompt = Prompts.developPrompt(
            next: next,
            lessons: workspace.readLessons(),
            vision: workspace.readVision(),
            attempt: attempt,
            priorIssues: priorIssues,
            criticFeedback: criticFeedbacks
          )

          let launchPlan = agentLaunchPlan(for: workspace.repoURL)
          logExecutionEnvironmentPreflight(
            phase: "Develop",
            nativeExecutionURL: workspace.repoURL,
            launchPlan: launchPlan,
            sessionIndex: sessionIndex,
            attempt: attempt
          )
          log(
            "Develop: launching agent (attempt \(attempt)/\(maxDevelopAttempts), critic cycle \(criticAttempt + 1)/\(maxCriticAttempts)).",
            level: .info
          )
          let summary: DevelopSummary
          do {
            summary = try await runAgent(
              phase: .develop,
              agentSettings: agentSettings,
              modelOverride: modelOverride,
              workingDirectory: workspace.repoURL,
              userPrompt: prompt,
              submitResultSchema: Prompts.developSchema,
              decode: DevelopSummary.self
            )
          } catch let error as AgentExecutionError where error.isAgentBudgetExhaustion {
            // The agent ran out of wall-clock budget or iterations
            // mid-attempt. Treat that as a failed attempt with
            // budget-exhaustion context so the next attempt starts
            // fresh, rather than aborting the whole Develop pass.
            let note =
              "Develop attempt \(attempt) ended without submit_result: \(error.localizedDescription)."
            log(note, level: .warning)
            appendSessionNote(note, to: sessionIndex)
            priorIssues = [note]
            finalIssues = [note]
            finalVerifyOutput = nil
            if attempt < maxDevelopAttempts {
              feedback(.developRetrying)
            }
            continue
          }

          // Under the `.sharedVM` route the agent worked in the
          // guest workspace and Verify ran there too. We defer the
          // host-side pull and commit until Verify passes (and the
          // Critic approves) so failed attempts don't leave the main
          // repo dirty. Under the host route the agent already
          // committed in place using its own `git` tool.

          guard sessions.indices.contains(sessionIndex) else {
            throw AppModelError.internalInvariant("Develop session disappeared during agent run.")
          }
          sessions[sessionIndex].feedback = summary.feedback
          appendSessionNote(summary.summary, to: sessionIndex)

          let post = try await runPostChecks(
            next: next,
            summary: summary,
            workingDirectory: workspace.repoURL,
            launchPlan: launchPlan,
            sessionIndex: sessionIndex,
            attempt: attempt
          )
          finalIssues = post.displayIssues
          finalVerifyOutput = post.verifyOutput
          if sessions.indices.contains(sessionIndex) {
            sessions[sessionIndex].verifyOutput = post.verifyOutput
          }
          try? persistSessions()

          if post.ok {
            postChecksPassed = true
            postCheckSummary = summary
            postCheckLaunchPlan = launchPlan
            break
          }

          priorIssues = post.retryIssues
          if attempt < maxDevelopAttempts {
            feedback(.developRetrying)
            log("Develop post-checks failed; retrying with failure context.", level: .warning)
          }
        }

        guard postChecksPassed,
          let summary = postCheckSummary,
          let launchPlan = postCheckLaunchPlan
        else {
          // Post-checks fundamentally failed after every attempt — do
          // not run the critic. The iteration ends as a failure with
          // the existing post-check issues already in `finalIssues`.
          succeeded = false
          break criticLoop
        }

        // Pull guest workspace onto the host so the Critic can diff
        // against the pre-Develop SHA. We do this regardless of the
        // critic's verdict because the inner loop already passed —
        // even on critic-reject the next Develop attempt sees the
        // cumulative guest state (persistent), and the next pull
        // overwrites the dirty host state with whatever the new
        // Verify-passing iteration produced.
        if case .sharedVM = launchPlan.effectiveRoute {
          await pullDevelopChangesIfNeeded(
            mainRepoURL: workspace.repoURL,
            plan: launchPlan
          )
        }

        criticAttempt += 1
        let verdict = await runCriticPass(
          next: next,
          developSummary: summary,
          verifyOutput: finalVerifyOutput,
          beforeSha: beforeSha,
          priorCritiques: criticFeedbacks,
          workspace: workspace,
          agentSettings: agentSettings,
          modelOverride: modelOverride,
          iteration: criticAttempt,
          sessionIndex: sessionIndex
        )

        if verdict.verdict == .approve {
          if let commitIssue = await landDevelopChanges(
            workspace: workspace,
            summary: summary,
            launchPlan: launchPlan,
            sessionIndex: sessionIndex
          ) {
            finalIssues = [commitIssue]
            succeeded = false
          } else {
            succeeded = true
            feedback(.commitsPromoted)
          }
          break criticLoop
        }

        if criticAttempt >= maxCriticAttempts {
          let warning =
            "Critic still requested changes after \(maxCriticAttempts) reviews; accepting and proceeding."
          log(warning, level: .warning)
          appendSessionNote(warning, to: sessionIndex)
          if let commitIssue = await landDevelopChanges(
            workspace: workspace,
            summary: summary,
            launchPlan: launchPlan,
            sessionIndex: sessionIndex
          ) {
            finalIssues = [commitIssue]
            succeeded = false
          } else {
            succeeded = true
            feedback(.commitsPromoted)
          }
          break criticLoop
        }

        // Reject + budget remains: queue another Develop pass.
        criticFeedbacks.append(
          "Critic review \(criticAttempt) requested changes:\n\(verdict.feedback)")
        feedback(.developRetrying)
      }

      for issue in finalIssues {
        appendSessionNote(issue, to: sessionIndex)
      }
      guard sessions.indices.contains(sessionIndex) else {
        throw AppModelError.internalInvariant("Develop session disappeared before completion.")
      }
      sessions[sessionIndex].verifyOutput = finalVerifyOutput
      let afterSha = await gitCurrentSha(at: workspace.repoURL)
      sessions[sessionIndex].afterSha = afterSha
      sessions[sessionIndex].commits = await gitCommits(
        in: workspace.repoURL,
        from: beforeSha,
        to: afterSha
      )

      endSession(sessionIndex, status: succeeded ? .succeeded : .failed)
      phase = succeeded ? .succeeded : .failed
      log(
        succeeded ? "Develop completed." : "Develop finished with failed post-checks.",
        level: succeeded ? .success : .error)
      if !succeeded {
        feedback(.postChecksFailed)
      }

      if isPaused {
        phase = .paused
        log("Paused after iteration.", level: .warning)
        feedback(.paused)
      }
    } catch {
      if stopRequested {
        stopRequested = false
        appendSessionNote("Stopped by user.", to: sessionIndex)
        endSession(sessionIndex, status: .cancelled)
        phase = .cancelled
        log("Run stopped.", level: .warning)
        feedback(.stopped)
      } else {
        appendSessionNote(error.localizedDescription, to: sessionIndex)
        endSession(sessionIndex, status: .failed)
        phase = .failed
        fail(error)
      }
    }

    isRunning = false
    executor = nil
    await refresh()
  }

  private func initializeIfNeeded(_ workspace: CompassWorkspace) async throws {
    guard !FileManager.default.fileExists(atPath: workspace.compassURL.path) else { return }
    try workspace.initialize()
    await refresh()
  }

  private var isIdleForActiveStorageActivation: Bool {
    !isRunning && !isAutoPlaying && !isPaused
  }

  private var isIdleForMutationTesting: Bool {
    !isRunning
      && !isAutoPlaying
      && !isPaused
      && !storageMigrationState.isRunning
      && !activeStorageActivationState.isRunning
  }

  private var mutationTestingExecutionState: AgentMutationTestingMenuAction.ExecutionState {
    if isPaused { return .paused }
    if !isIdleForMutationTesting { return .running }
    return .idle
  }

  private func rollbackActiveStorage(
    to previousStorage: KnownProjectActiveStorage,
    persistProjectRegistry: () throws -> Void
  ) async -> String? {
    activeStorage = previousStorage
    var rollbackFailure: String?
    do {
      try persistProjectRegistry()
    } catch {
      rollbackFailure = error.localizedDescription
    }
    await refresh()
    return rollbackFailure
  }

  private func resolveWorkspaceForRun() async throws -> CompassWorkspace {
    let resolvedURL = try await resolveGitRoot(from: repoURL)
    if repoURL.path != resolvedURL.path {
      repoURL = resolvedURL
      log("Resolved repo root: \(repoURL.path)", level: .info)
    }

    let workspace = makeWorkspace(repoURL: repoURL)
    log("Using Compass workspace: \(workspace.compassURL.path)", level: .info)
    return workspace
  }

  private func makeWorkspace(repoURL: URL) -> CompassWorkspace {
    makeStorageResolver(repoURL: repoURL).workspace
  }

  private func makeStorageResolver(repoURL: URL) -> CompassProjectStorageResolver {
    CompassProjectStorageResolver(
      repoURL: repoURL,
      activeStorage: activeStorage,
      applicationSupportRoots: storageApplicationSupportRoots
    )
  }

  private func agentLaunchPlan(for nativeExecutionURL: URL) -> AgentExecutionLaunchPlan {
    // Compass always routes the agent through the Shared VM; the
    // onboarding gate prevents launches until the VM is ready. The
    // planner still falls back to host when the VirtioFS catalog
    // can't map this repo (Plan/Reflect on the main repo lives
    // outside the workspaces share), which is an internal-only
    // concern with no user-facing toggle.
    let host = SharedCompassVM.shared
    let readiness = host.readiness
    return AgentExecutionLaunchPlan.plan(
      repoURL: nativeExecutionURL,
      vmReadiness: readiness,
      sharedVMRouteFactory: { hostURL in
        Self.makeSharedVMRoute(
          hostRepoURL: hostURL,
          readiness: readiness,
          bundle: host.bundle
        )
      }
    )
  }

  /// Builds a `SharedVMRoute` for a host repo URL by mapping it to
  /// the guest-local path where Compass keeps its synced copy
  /// (`/Users/compass/Compass/Repos/<UUID>/worktree`). Returns nil if
  /// the VM is not ready, or if the catalog lookup fails (planner
  /// falls back to host).
  ///
  /// The mapping no longer references VirtioFS: macOS guests TCC-block
  /// `AppleVirtIOFS` reads from every process (even LaunchAgents inside
  /// the GUI session, even root via LaunchDaemon), so Compass copies
  /// repo contents into the guest via vsock-streamed tar instead. See
  /// `SharedCompassVMWorktreeSync` for the push/pull machinery.
  ///
  /// Callers must pass the user's main repo URL — never a derived
  /// per-iteration path — so every Compass phase (Plan / Reflect /
  /// Develop / Verify) keys off the same catalog entry and sees the
  /// same guest workspace.
  private static func makeSharedVMRoute(
    hostRepoURL: URL,
    readiness: SharedCompassVMReadiness,
    bundle: SharedCompassVMBundle
  ) -> SharedVMRoute? {
    guard case .ready(let sshDestination) = readiness else { return nil }

    let catalogEntry: SharedCompassVMGuestWorkspaceCatalog.CatalogEntry
    do {
      catalogEntry = try SharedCompassVMGuestWorkspaceCatalog.ensureEntry(
        forRepoURL: hostRepoURL
      )
    } catch {
      // Bookkeeping failure shouldn't strand the agent — fall back
      // to host execution rather than throwing inside the launch
      // planner.
      return nil
    }
    let guestWorkspacePath = SharedCompassVMGuestWorkspaceCatalog.guestWorktreePath(
      forEntry: catalogEntry
    )

    return SharedVMRoute(
      sshDestination: sshDestination,
      hostWorktreeURL: hostRepoURL,
      guestWorkspacePath: guestWorkspacePath,
      environmentVariables: [:],
      identityFile: bundle.privateKeyURL.path,
      knownHostsFile: bundle.knownHostsURL.path
    )
  }

  private func logExecutionEnvironmentPreflight(
    phase: String,
    nativeExecutionURL: URL,
    launchPlan: AgentExecutionLaunchPlan? = nil,
    sessionIndex: Int? = nil,
    attempt: Int? = nil
  ) {
    let environment = AgentExecutionEnvironment.discover(
      vmReadiness: SharedCompassVM.shared.readiness
    )
    let effectiveLaunchPlan = launchPlan ?? environment.launchPlan(repoURL: nativeExecutionURL)
    log(
      effectiveLaunchPlan.preflightSummary(phase: phase),
      level: .info
    )
    if let sessionIndex {
      recordSessionExecutionEnvironmentSnapshot(
        phase: phase,
        attempt: attempt,
        launchPlan: effectiveLaunchPlan,
        sessionIndex: sessionIndex
      )
    }
    let presentation = environment.presentation(launchPlan: effectiveLaunchPlan)
    let detail = [presentation.status, presentation.detail, effectiveLaunchPlan.routeDetail()]
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    log(detail, level: presentation.isWarning ? .warning : .info)
  }

  private func recordSessionExecutionEnvironmentSnapshot(
    phase: String,
    attempt: Int?,
    launchPlan: AgentExecutionLaunchPlan,
    sessionIndex: Int
  ) {
    guard sessions.indices.contains(sessionIndex) else { return }
    let snapshot = SessionExecutionEnvironmentSnapshot(
      phase: phase,
      attempt: attempt,
      launchPlan: launchPlan
    )
    sessions[sessionIndex].recordExecutionEnvironmentSnapshot(snapshot)
    try? persistSessions()
  }

  private func resolveGitRoot(from url: URL) async throws -> URL {
    let result: ProcessResult
    do {
      result = try await ProcessRunner.runEnv(
        "git",
        ["rev-parse", "--show-toplevel"],
        workingDirectory: url
      )
    } catch {
      throw AppModelError.notGitRepository(url.path)
    }

    guard result.exitCode == 0 else {
      throw AppModelError.notGitRepository(url.path)
    }

    let root = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !root.isEmpty else {
      throw AppModelError.notGitRepository(url.path)
    }
    return URL(fileURLWithPath: root).standardizedFileURL
  }

  private func startSession() -> Int {
    let nextNumber = (sessions.map(\.session).max() ?? 0) + 1
    sessions.append(.started(nextNumber))
    try? persistSessions()
    return sessions.count - 1
  }

  private func endSession(_ index: Int, status: SessionStatus) {
    guard sessions.indices.contains(index) else { return }
    sessions[index].status = status
    sessions[index].endedAt = Date().timeIntervalSince1970 * 1000
    try? persistSessions()
  }

  private func appendSessionNote(_ note: String, to index: Int) {
    let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, sessions.indices.contains(index) else { return }
    if sessions[index].notes.last != trimmed {
      sessions[index].notes.append(trimmed)
    }
    try? persistSessions()
  }

  private func logLessonEdits(_ count: Int) {
    guard count > 0 else { return }
    let noun = count == 1 ? "edit" : "edits"
    log("Applied \(count) lesson \(noun).", level: .success)
  }

  private func previousFeedback(excluding session: Int) -> String {
    sessions
      .filter { $0.session != session && $0.endedAt != nil }
      .sorted { $0.startedAt > $1.startedAt }
      .compactMap { $0.feedback?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty } ?? ""
  }

  private func runReflectIfNeeded(
    _ workspace: CompassWorkspace,
    sessionIndex: Int,
    agentSettings: AgentRuntimeSettings,
    modelOverride: String
  ) async throws {
    guard sessions.indices.contains(sessionIndex) else { return }
    let cadence = reflectEvery()
    guard cadence > 0, sessions[sessionIndex].session % cadence == 0 else { return }

    let iteration = sessions[sessionIndex].session
    let recentSessions =
      sessions
      .filter { $0.session != iteration && $0.endedAt != nil }
      .sorted { $0.startedAt > $1.startedAt }
      .prefix(reflectSessionWindow)

    let prompt = try Prompts.reflectPrompt(
      state: workspace.readState(),
      lessons: workspace.readLessons(),
      vision: workspace.readVision(),
      recentSessions: Array(recentSessions),
      iteration: iteration
    )

    let launchPlan = agentLaunchPlan(for: workspace.repoURL)
    logExecutionEnvironmentPreflight(
      phase: "Reflect",
      nativeExecutionURL: workspace.repoURL,
      launchPlan: launchPlan,
      sessionIndex: sessionIndex
    )
    log("Reflect: launching agent.", level: .info)
    let result = try await runAgent(
      phase: .reflect,
      agentSettings: agentSettings,
      modelOverride: modelOverride,
      workingDirectory: workspace.repoURL,
      userPrompt: prompt,
      submitResultSchema: Prompts.reflectSchema,
      decode: ReflectSummary.self
    )

    let lessonEditCount = try workspace.applyLessonEdits(result.lessonEdits)
    if let reflectedState = result.state {
      try workspace.writeState(reflectedState)
      state = reflectedState
      log("Reflect updated state.json: \(result.summary)", level: .success)
    } else {
      log("Reflect: \(result.summary)", level: .info)
    }
    logLessonEdits(lessonEditCount)
  }

  private func reflectEvery() -> Int {
    let raw = ProcessInfo.processInfo.environment["COMPASS_REFLECT_EVERY"]
    guard let raw, !raw.isEmpty, let parsed = Int(raw), parsed >= 0 else {
      return 5
    }
    return parsed
  }

  private func persistSessions() throws {
    try workspace?.writeSessions(sessions)
  }

  /// Build an AgentExecutionConfiguration, run it, and decode the
  /// `submit_result` arguments into the phase result model. Assigns the
  /// executor to `self.executor` so `stopRun()` can cancel mid-stream.
  private func runAgent<T: Decodable>(
    phase: AgentPhase,
    agentSettings: AgentRuntimeSettings,
    modelOverride: String,
    workingDirectory: URL,
    userPrompt: String,
    submitResultSchema: String,
    decode: T.Type
  ) async throws -> T {
    let schema = AgentToolParametersSchema(json: Data(submitResultSchema.utf8))
    let environment = resolveAgentEnvironment(forHostURL: workingDirectory)
    if environment.kind == .sharedVM {
      // Ensure the persistent guest workspace has contents before
      // the agent's first read_file. ensurePopulated is idempotent
      // — pays the push cost only when the guest workspace is
      // missing, so subsequent phases / iterations / sessions
      // skip straight to running the agent.
      try await ensurePersistentGuestWorkspace(forHostRepo: workingDirectory)
    }
    let configuration = AgentExecutionConfiguration(
      settings: agentSettings,
      phase: phase,
      modelOverride: modelOverride,
      systemPrompt: Prompts.agentSystemPrompt(
        phase: phase,
        workingDirectoryPath: environment.workingDirectory.path,
        executionEnvironment: environment.kind == .sharedVM ? .sharedVM : .host
      ),
      userPrompt: userPrompt,
      tools: AgentExecutor.toolsForPhase(phase),
      submitResultSchema: schema,
      workingDirectory: environment.workingDirectory,
      filesystem: environment.filesystem,
      bashRunner: environment.bashRunner
    )
    let agent = AgentExecutor { [weak self] event in
      Task { @MainActor in self?.log(event) }
    }
    executor = agent
    let result = try await agent.run(configuration)
    do {
      return try JSONDecoder().decode(T.self, from: result.submitResultArguments)
    } catch {
      let body = String(decoding: result.submitResultArguments, as: UTF8.self)
      throw AppModelError.internalInvariant(
        "Could not decode \(T.self) from submit_result: \(error.localizedDescription)\n\(body)"
      )
    }
  }

  /// Resolved working directory + tool backends for an agent run.
  /// When the project's execution preference is `.sharedVM` and the
  /// VM resolves to a ready route for `hostURL`, the agent operates
  /// entirely inside the persistent per-repo guest workspace via the
  /// vsock-served Compass guest agent. `SharedCompassVMRepoWorkspaceSync`
  /// populates that workspace lazily on first use; under the host
  /// route the agent stays native and works against `hostURL`
  /// directly.
  struct AgentEnvironment {
    /// Coarse descriptor for the agent's runtime environment. Used by
    /// the system-prompt builder to teach the model what tooling it
    /// can expect — e.g. the Shared VM has Command Line Tools only,
    /// not full Xcode, so reaching for `xcodebuild` is wasted work.
    enum Kind {
      case host
      case sharedVM
    }
    var kind: Kind
    var workingDirectory: URL
    var filesystem: AgentFilesystem
    var bashRunner: AgentBashRunner
  }

  private func resolveAgentEnvironment(forHostURL hostURL: URL) -> AgentEnvironment {
    let launchPlan = agentLaunchPlan(for: hostURL)
    switch launchPlan.effectiveRoute {
    case .host:
      if let reason = launchPlan.fallbackReason {
        log("Agent route falling back to host: \(reason)", level: .info)
      }
      return AgentEnvironment(
        kind: .host,
        workingDirectory: hostURL,
        filesystem: AgentHostFilesystem(),
        bashRunner: AgentHostBashRunner()
      )
    case .sharedVM(let route):
      guard let machine = SharedCompassVM.shared.virtualMachine else {
        log(
          "Agent route via Shared VM requested but no live VZVirtualMachine; falling back to host.",
          level: .warning)
        return AgentEnvironment(
          kind: .host,
          workingDirectory: hostURL,
          filesystem: AgentHostFilesystem(),
          bashRunner: AgentHostBashRunner()
        )
      }
      // `route.guestWorkspacePath` is the persistent per-repo
      // guest workspace (from `SharedCompassVMGuestWorkspaceCatalog`)
      // — the same directory for every Plan / Reflect / Develop /
      // Verify run against this repo.
      let guestWorkingDirectory = URL(fileURLWithPath: route.guestWorkspacePath)
      log(
        "Agent route via Shared VM (vsock) at workspace \(guestWorkingDirectory.path)", level: .info
      )
      let client = Self.makeVsockClient(on: machine)
      return AgentEnvironment(
        kind: .sharedVM,
        workingDirectory: guestWorkingDirectory,
        filesystem: client,
        bashRunner: client
      )
    }
  }

  /// Runs the Verify shell command in the same place the agent just
  /// operated. For `.sharedVM` routes this goes through the guest's
  /// bash RPC against the persistent guest workspace; everything else
  /// falls through to the existing host-side `ProcessRunner.runShell`
  /// path.
  ///
  /// The host workingDirectory parameter is only used by the host
  /// fallback. Under .sharedVM the guest path is resolved via the
  /// catalog so the command runs against the same `<UUID>/worktree`
  /// the agent's `bash` tool calls land in.
  private func runVerifyCommand(
    command: String,
    hostWorkingDirectory: URL,
    timeoutSeconds: TimeInterval,
    launchPlan: AgentExecutionLaunchPlan
  ) async throws -> ProcessResult {
    if case .sharedVM(let route) = launchPlan.effectiveRoute,
      let machine = SharedCompassVM.shared.virtualMachine
    {
      let client = Self.makeVsockClient(on: machine)
      let guestWorkingDirectory = URL(fileURLWithPath: route.guestWorkspacePath)
      log(
        "Verify: running inside Shared VM at \(route.guestWorkspacePath) (timeout \(Int(timeoutSeconds * 1000))ms).",
        level: .info
      )
      return try await client.run(
        command: command,
        workingDirectory: guestWorkingDirectory,
        timeout: timeoutSeconds
      )
    }
    return try await ProcessRunner.runShell(
      command,
      workingDirectory: hostWorkingDirectory,
      timeout: timeoutSeconds,
      launchPlan: launchPlan
    )
  }

  /// Ensures the persistent guest workspace for `hostRepoURL` exists and
  /// has the host repo's contents. No-op if the guest workspace already
  /// exists (the agent's prior state is preserved). Callers can force
  /// a re-sync by passing `forceRefresh: true`.
  ///
  /// Called from `runAgent` for `.sharedVM` routes so the agent's first
  /// `read_file` always finds something. For session-level operations
  /// (e.g. an explicit user-driven refresh in the future) this can be
  /// invoked directly without going through runAgent.
  @discardableResult
  private func ensurePersistentGuestWorkspace(
    forHostRepo hostRepoURL: URL,
    forceRefresh: Bool = false
  ) async throws -> SharedCompassVMRepoWorkspaceSync.Outcome? {
    guard let machine = SharedCompassVM.shared.virtualMachine else {
      return nil
    }
    let client = Self.makeVsockClient(on: machine)
    let result: (guestPath: String, outcome: SharedCompassVMRepoWorkspaceSync.Outcome)
    do {
      result = try await SharedCompassVMRepoWorkspaceSync.ensurePopulated(
        hostRepoURL: hostRepoURL,
        client: client,
        forceRefresh: forceRefresh
      )
    } catch let error as SharedCompassVMRepoWorkspaceSync.SyncError {
      // Log the *readable* description before rethrowing — without
      // this the activity batch only shows
      // "The operation couldn't be completed.
      //  (Compass.SharedCompassVMRepoWorkspaceSync.SyncError error N.)"
      // because the failure ascends through callers that surface
      // `localizedDescription` from the raw error chain.
      log("Guest workspace sync failed: \(error.description)", level: .error)
      throw error
    }
    switch result.outcome {
    case .reused:
      log(
        "Guest workspace at \(result.guestPath) already populated — preserving prior agent state.",
        level: .info)
    case .freshlyPopulated:
      log(
        "Guest workspace at \(result.guestPath) populated for the first time from \(hostRepoURL.path).",
        level: .info)
    case .refreshed:
      log(
        "Guest workspace at \(result.guestPath) force-refreshed from \(hostRepoURL.path).",
        level: .info)
    }
    return result.outcome
  }

  /// Builds a vsock-backed agent client that opens a fresh
  /// `VZVirtioSocketConnection` per RPC. Shared between the agent loop
  /// (`resolveAgentEnvironment`) and the worktree sync helpers below
  /// so the connect-and-write path stays in one place.
  private static func makeVsockClient(on machine: VZVirtualMachine) -> AgentVsockClient {
    AgentVsockClient(
      transportFactory: {
        let connection = try await SharedCompassVMVsock.connect(on: machine)
        return VZVirtioSocketTransport(connection: connection)
      }
    )
  }

  /// Pulls the guest workspace's current state (filtered against the
  /// well-known build-output dirs) back onto the host's main repo.
  /// Called after Verify passes under the `.sharedVM` route so the
  /// follow-up host-side commit captures whatever the in-guest agent
  /// produced.
  ///
  /// Pull failures are logged but not thrown: the subsequent
  /// `git status` will surface "nothing to commit" or partial state
  /// instead of dropping the entire iteration on a transient
  /// transport hiccup.
  private func pullDevelopChangesIfNeeded(
    mainRepoURL: URL,
    plan: AgentExecutionLaunchPlan
  ) async {
    guard case .sharedVM(let route) = plan.effectiveRoute,
      let machine = SharedCompassVM.shared.virtualMachine
    else {
      return
    }
    let client = Self.makeVsockClient(on: machine)
    do {
      try await SharedCompassVMWorktreeSync.pull(
        hostWorktreeURL: mainRepoURL,
        guestWorktreePath: route.guestWorkspacePath,
        client: client
      )
    } catch {
      log(
        "Develop: vsock pull from guest failed — host commit may see stale state: \(error.localizedDescription)",
        level: .warning
      )
    }
  }

  /// Run one Critic review pass against the Develop output that just
  /// passed post-checks. Always returns a verdict — Critic infrastructure
  /// failures (network, schema decode) log a warning and fall through to
  /// an `.approve` verdict so a flaky review path can't strand an
  /// otherwise-good Develop iteration.
  private func runCriticPass(
    next: PlanNext,
    developSummary: DevelopSummary,
    verifyOutput: VerifyOutput?,
    beforeSha: String?,
    priorCritiques: [String],
    workspace: CompassWorkspace,
    agentSettings: AgentRuntimeSettings,
    modelOverride: String,
    iteration: Int,
    sessionIndex: Int
  ) async -> CriticVerdict {
    phase = .reviewing
    let launchPlan = agentLaunchPlan(for: workspace.repoURL)
    logExecutionEnvironmentPreflight(
      phase: "Critic",
      nativeExecutionURL: workspace.repoURL,
      launchPlan: launchPlan,
      sessionIndex: sessionIndex,
      attempt: iteration
    )
    log("Critic: launching review \(iteration)/\(maxCriticAttempts).", level: .info)

    let diff = await gitDiffSinceSha(beforeSha, in: workspace.repoURL)
    let verifyOutputText = verifyOutput?.tail ?? ""
    let verifyExitCode = verifyOutput?.exitCode
    let prompt = Prompts.criticPrompt(
      next: next,
      developSummary: developSummary,
      verifyCommand: next.verify,
      verifyExitCode: verifyExitCode,
      verifyOutput: verifyOutputText,
      gitDiff: diff,
      priorCritiques: priorCritiques,
      lessons: workspace.readLessons(),
      vision: workspace.readVision(),
      iteration: iteration,
      maxIterations: maxCriticAttempts
    )

    let verdict: CriticVerdict
    do {
      verdict = try await runAgent(
        phase: .critic,
        agentSettings: agentSettings,
        modelOverride: modelOverride,
        workingDirectory: workspace.repoURL,
        userPrompt: prompt,
        submitResultSchema: Prompts.criticSchema,
        decode: CriticVerdict.self
      )
    } catch {
      let note =
        "Critic pass failed: \(error.localizedDescription); accepting Develop output."
      log(note, level: .warning)
      appendSessionNote(note, to: sessionIndex)
      return CriticVerdict(verdict: .approve, summary: "critic pass failed", feedback: "")
    }

    let level: LiveLine.Level = verdict.verdict == .approve ? .success : .warning
    let note =
      "Critic \(iteration)/\(maxCriticAttempts): \(verdict.verdict.rawValue) — \(verdict.summary)"
    log(note, level: level)
    appendSessionNote(note, to: sessionIndex)
    return verdict
  }

  /// Commit the Develop iteration's changes onto the host's current
  /// branch (under `.sharedVM`) and apply any lesson edits. Returns nil
  /// on success or a single human-readable issue string when the host
  /// commit fails. Lesson-edit failures are logged but not treated as
  /// blockers — they're durable guidance, not the iteration's product.
  private func landDevelopChanges(
    workspace: CompassWorkspace,
    summary: DevelopSummary,
    launchPlan: AgentExecutionLaunchPlan,
    sessionIndex: Int
  ) async -> String? {
    if case .sharedVM = launchPlan.effectiveRoute {
      if let commitIssue = await commitAgentChangesOnHost(
        mainRepoURL: workspace.repoURL,
        summary: summary
      ) {
        return commitIssue
      }
    }
    do {
      logLessonEdits(try workspace.applyLessonEdits(summary.lessonEdits))
    } catch {
      let note = "Lesson edits were not applied: \(error.localizedDescription)"
      appendSessionNote(note, to: sessionIndex)
      log(note, level: .error)
    }
    return nil
  }

  private func validatePlanTransition(from current: PlanState, to next: PlanState) throws {
    do {
      try PlanTransitionValidator.validate(from: current, to: next)
    } catch let error as PlanTransitionValidationError {
      throw AppModelError.rejectedPlan(error.message)
    }
  }

  private func runPostChecks(
    next: PlanNext,
    summary: DevelopSummary,
    workingDirectory: URL,
    launchPlan: AgentExecutionLaunchPlan,
    sessionIndex: Int,
    attempt: Int
  ) async throws -> PostCheckResult {
    var retryIssues: [String] = []
    var displayIssues: [String] = []
    var verifyOutput: VerifyOutput?

    switch summary.status {
    case .succeeded:
      break
    case .blocked:
      if summary.bypassVerify != true {
        let issue = "Develop reported it was blocked but did not request verify bypass."
        retryIssues.append(issue)
        displayIssues.append(issue)
      }
    case .failed:
      let issue = "Develop reported failure: \(summary.feedback)"
      retryIssues.append(issue)
      displayIssues.append(issue)
    }

    if summary.bypassVerify == true {
      log("Post-check: skipping verify per Develop bypassVerify=true.", level: .warning)
    } else {
      phase = .verifying
      let timeoutMs = verifyTimeoutMs(for: next)
      logExecutionEnvironmentPreflight(
        phase: "Verify",
        nativeExecutionURL: workingDirectory,
        launchPlan: launchPlan,
        sessionIndex: sessionIndex,
        attempt: attempt
      )
      log(
        "Post-check: running verify command `\(next.verify)` (timeout \(timeoutMs)ms).",
        level: .info)
      feedback(.verifyStarted)
      // Verify runs in the same workspace the agent just operated
      // on. For .sharedVM that means inside the guest via the
      // vsock bash RPC against the persistent guest workspace; for
      // host runs the existing ProcessRunner.runShell path applies.
      // Sending Verify through the host while the agent worked in
      // the guest would race against any file the pull step
      // hadn't observed yet — and now that the guest is the source
      // of truth, it's also the only place the agent's tooling is
      // guaranteed to be the same as what we tested against.
      let verify = try await runVerifyCommand(
        command: next.verify,
        hostWorkingDirectory: workingDirectory,
        timeoutSeconds: TimeInterval(timeoutMs) / 1000,
        launchPlan: launchPlan
      )
      if verify.exitCode == 0 {
        log("Verify passed.", level: .success)
        feedback(.verifyPassed)
      } else {
        let verifyTail = tail(verify.stdout + verify.stderr, max: 4000)
        let issue = """
          Verify command `\(next.verify)` exited with code \(verify.exitCode). Output (tail):
          ```
          \(verifyTail)
          ```
          """
        retryIssues.append(issue)
        verifyOutput = VerifyOutput(
          command: next.verify,
          exitCode: Int(verify.exitCode),
          tail: verifyTail
        )
        log("Verify failed (exit \(verify.exitCode)).", level: .error)
      }
    }

    // Under `.sharedVM` the agent runs in the guest workspace,
    // which has no `.git`, so a host-side `git status` here would
    // either look stale (the post-Verify pull hasn't happened yet)
    // or always-dirty (after an early pull). The Develop loop's
    // `commitAgentChangesOnHost` does the host-side commit
    // explicitly once Verify passes.
    if case .sharedVM = launchPlan.effectiveRoute {
      log(
        "Post-check: skipping host git-status check under .sharedVM (commits are managed post-Verify by the Develop loop).",
        level: .info)
    } else {
      let gitStatus = try await ProcessRunner.runEnv(
        "git",
        ["status", "--porcelain"],
        workingDirectory: workingDirectory,
        timeout: 30
      )
      if gitStatus.exitCode != 0 {
        let issue = """
          `git status --porcelain` failed unexpectedly:
          ```
          \(tail(gitStatus.stdout + gitStatus.stderr, max: 2000))
          ```
          """
        retryIssues.append(issue)
        displayIssues.append(issue)
        log("Working-tree status check failed.", level: .error)
      } else {
        let status = gitStatus.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if status.isEmpty {
          log("Working tree clean.", level: .success)
        } else {
          let issue = """
            Uncommitted or untracked changes remain after Develop ran. Commit them or add them to .gitignore.
            `git status --porcelain` output:
            ```
            \(status)
            ```
            """
          retryIssues.append(issue)
          displayIssues.append(issue)
          log("Working tree is not clean after Develop.", level: .error)
        }
      }
    }

    return PostCheckResult(
      ok: retryIssues.isEmpty,
      retryIssues: retryIssues,
      displayIssues: displayIssues,
      verifyOutput: verifyOutput
    )
  }

  private func verifyTimeoutMs(for next: PlanNext) -> Int {
    if let timeout = next.verifyTimeoutMs, timeout > 0 {
      return timeout
    }
    let raw = ProcessInfo.processInfo.environment["COMPASS_VERIFY_TIMEOUT_MS"]
    guard let raw, let parsed = Int(raw), parsed > 0 else {
      return 10 * 60 * 1000
    }
    return parsed
  }

  /// Stages whatever the post-Verify pull left in the main repo and
  /// lands it as a single commit on the user's current branch. Only
  /// relevant for the `.sharedVM` route — under the host route the
  /// agent already committed in-place using its `bash` tool.
  ///
  /// The guest workspace has no `.git`, so the agent cannot perform
  /// the commit itself. Compass takes responsibility for it
  /// host-side once Verify confirms the agent's work is good. The
  /// commit message uses the agent's own `summary` so future
  /// `git log` reads remain agent-authored.
  ///
  /// Returns nil on success, or a human-readable issue string on
  /// failure.
  private func commitAgentChangesOnHost(
    mainRepoURL: URL,
    summary: DevelopSummary
  ) async -> String? {
    // Skip the commit entirely when there is nothing to commit. The
    // agent may have done a no-op iteration (or pulled an exact
    // duplicate of what's already on the branch); committing an
    // empty change would either fail or produce noise.
    let status: ProcessResult
    do {
      status = try await ProcessRunner.runEnv(
        "git",
        ["status", "--porcelain"],
        workingDirectory: mainRepoURL,
        timeout: 30
      )
    } catch {
      return "Host-side commit failed at git status: \(error.localizedDescription)"
    }
    if status.exitCode != 0 {
      return
        "Host-side commit failed at git status (exit \(status.exitCode)): \(tail(status.stderr + status.stdout, max: 2000))"
    }
    if status.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      log(
        "Host-side commit: pulled guest workspace is identical to the host branch — nothing to commit.",
        level: .info)
      return nil
    }

    do {
      try await runGitOrThrow(
        ["add", "-A"],
        in: mainRepoURL,
        failurePrefix: "Failed to stage agent changes on host"
      )
    } catch {
      return error.localizedDescription
    }

    let message = commitMessage(for: summary)
    do {
      try await runGitOrThrow(
        ["commit", "-m", message],
        in: mainRepoURL,
        failurePrefix: "Failed to create host-side commit for agent changes"
      )
    } catch {
      return error.localizedDescription
    }
    log("Host-side commit landed: \(boundedFirstLine(message, limit: 72))", level: .success)
    return nil
  }

  /// Renders the host-side commit message Compass writes after pulling
  /// from the guest workspace. Format mirrors the agent's submit_result:
  /// the summary becomes the subject (truncated), feedback the body.
  private func commitMessage(for summary: DevelopSummary) -> String {
    let subject = boundedFirstLine(summary.summary, limit: 72)
    let feedback = summary.feedback.trimmingCharacters(in: .whitespacesAndNewlines)
    if feedback.isEmpty {
      return subject
    }
    return "\(subject)\n\n\(feedback)"
  }

  /// Helper: pick the first non-empty line of `text`, trimmed and
  /// truncated to `limit` chars. Used to keep commit-subject lines
  /// inside conventional 72-column limits regardless of what the agent
  /// returned.
  private func boundedFirstLine(_ text: String, limit: Int) -> String {
    let firstLine =
      text
      .split(whereSeparator: \.isNewline)
      .first
      .map(String.init)?
      .trimmingCharacters(in: .whitespaces) ?? ""
    if firstLine.isEmpty { return "Develop iteration (no summary)" }
    if firstLine.count <= limit { return firstLine }
    return String(firstLine.prefix(limit)).trimmingCharacters(in: .whitespaces)
  }

  private func runGitOrThrow(_ arguments: [String], in directory: URL, failurePrefix: String)
    async throws
  {
    let result = try await ProcessRunner.runEnv("git", arguments, workingDirectory: directory)
    guard result.exitCode == 0 else {
      throw AppModelError.gitCommandFailed(
        "\(failurePrefix): \(tail(result.stderr + result.stdout, max: 2000))"
      )
    }
  }

  private func gitCurrentSha(at repoURL: URL) async -> String? {
    guard
      let result = try? await ProcessRunner.runEnv(
        "git",
        ["rev-parse", "HEAD"],
        workingDirectory: repoURL
      ), result.exitCode == 0
    else {
      return nil
    }
    return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Capture the unified diff from `since` (a SHA, may be nil for
  /// "initial commit") to the working tree's current state, including
  /// staged + unstaged + untracked files. Best-effort: returns an empty
  /// string when git fails so the Critic prompt always renders.
  ///
  /// `git diff <sha>` shows tracked changes; untracked files are
  /// appended separately via `git status --porcelain` + `git diff
  /// --no-index /dev/null <path>` so the Critic sees brand-new files
  /// instead of only modifications.
  private func gitDiffSinceSha(_ since: String?, in repoURL: URL) async -> String {
    var sections: [String] = []
    let baseArguments: [String]
    if let since {
      baseArguments = ["diff", "--no-color", "\(since)..HEAD"]
    } else {
      baseArguments = ["diff", "--no-color", "HEAD"]
    }
    if let trackedDiff = try? await ProcessRunner.runEnv(
      "git", baseArguments, workingDirectory: repoURL),
      trackedDiff.exitCode == 0,
      !trackedDiff.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      sections.append(trackedDiff.stdout)
    }
    if let workingDiff = try? await ProcessRunner.runEnv(
      "git", ["diff", "--no-color", "HEAD"], workingDirectory: repoURL),
      workingDiff.exitCode == 0,
      !workingDiff.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      sections.append(workingDiff.stdout)
    }
    if let untrackedList = try? await ProcessRunner.runEnv(
      "git", ["ls-files", "--others", "--exclude-standard"], workingDirectory: repoURL),
      untrackedList.exitCode == 0
    {
      let paths = untrackedList.stdout
        .split(whereSeparator: \.isNewline)
        .map(String.init)
        .filter { !$0.isEmpty }
      for path in paths {
        if let added = try? await ProcessRunner.runEnv(
          "git",
          ["diff", "--no-color", "--no-index", "--", "/dev/null", path],
          workingDirectory: repoURL
        ),
          !added.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
          sections.append(added.stdout)
        }
      }
    }
    let combined = sections.joined(separator: "\n")
    return tail(combined, max: 32_000)
  }

  private func gitCommits(in repoURL: URL, from before: String?, to after: String?) async
    -> [SessionCommit]
  {
    guard let after, before != after else { return [] }
    let range = before.map { "\($0)..\(after)" } ?? after
    guard
      let result = try? await ProcessRunner.runEnv(
        "git",
        ["log", "--reverse", "--format=%H%x09%h%x09%s", range],
        workingDirectory: repoURL
      ), result.exitCode == 0
    else {
      return []
    }

    return result.stdout
      .split(whereSeparator: \.isNewline)
      .compactMap { line in
        let parts = line.split(separator: "\t", maxSplits: 2).map(String.init)
        guard parts.count == 3 else { return nil }
        return SessionCommit(sha: parts[0], short: parts[1], subject: parts[2])
      }
  }

  private func feedback(_ milestone: NativeFeedbackMilestone) {
    NativeFeedbackService.shared.emit(
      milestone,
      projectName: displayName,
      mode: nativeFeedbackMode
    )
  }

  /// Refresh the on-disk codemap (symbols + per-file summaries) once per
  /// session. The agent's read-only `outline` / `find_symbol` / `summary`
  /// tools all read from this cache, so this is what makes a brand-new
  /// session see up-to-date data without paying the cost on every tool
  /// call. Failures are non-fatal — a stale or partial codemap is better
  /// than refusing to launch the agent.
  private func refreshCodemapIfNeeded(
    workspace: CompassWorkspace,
    sessionNumber: Int,
    agentSettings: AgentRuntimeSettings
  ) async {
    if codemapRefreshedForSession == sessionNumber { return }
    let refresher = CodemapRefresher.make(
      workspace: workspace,
      settings: agentSettings
    )
    do {
      let result = try await refresher.refresh()
      codemapRefreshedForSession = sessionNumber
      let parts = [
        "indexed \(result.indexed)",
        "unchanged \(result.unchanged)",
        "pruned \(result.pruned)",
        "summarized \(result.summariesGenerated)",
      ]
      log(
        "Codemap refresh: \(parts.joined(separator: ", ")).",
        level: .info
      )
      if result.indexerFailed > 0 || result.summariesFailed > 0 {
        log(
          "Codemap refresh had \(result.indexerFailed) parse failure(s) and \(result.summariesFailed) summary failure(s).",
          level: .warning
        )
      }
    } catch {
      log(
        "Codemap refresh failed: \(error.localizedDescription)",
        level: .warning
      )
    }
  }

  private func feedbackPlanReadinessGate(
    for _: PlanState,
    gate _: PlanReadinessNativeFeedbackGate
  ) {
    NativeFeedbackService.shared.emit(
      .developReady,
      projectName: displayName,
      mode: nativeFeedbackMode
    )
  }

  private func log(_ text: String, level: LiveLine.Level) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    let line = LiveLine(level: level, text: trimmed)
    liveLog.append(line)
    trimLiveLog()
  }

  private func log(_ event: LiveEvent) {
    let title = event.text.trimmingCharacters(in: .whitespacesAndNewlines)
    let detail = event.detail?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty || !(detail?.isEmpty ?? true) else { return }

    if event.status == .completed || event.status == .failed,
      let correlationID = event.correlationID,
      let index = liveLog.lastIndex(where: {
        $0.correlationID == correlationID && $0.status == .running
      })
    {
      liveLog[index].level = event.level
      liveLog[index].text = title.isEmpty ? liveLog[index].text : title
      liveLog[index].detail = detail?.isEmpty == false ? detail : liveLog[index].detail
      liveLog[index].kind = event.kind
      liveLog[index].status = event.status
      liveLog[index].completedAt = Date()
    } else {
      let line = LiveLine(
        level: event.level,
        text: title,
        detail: detail?.isEmpty == false ? detail : nil,
        kind: event.kind,
        status: event.status,
        correlationID: event.correlationID
      )
      liveLog.append(line)
    }

    trimLiveLog()
  }

  private func trimLiveLog() {
    if liveLog.count > 800 {
      liveLog.removeFirst(liveLog.count - 800)
    }
  }

  private func firstLine(_ text: String?) -> String? {
    text?
      .split(whereSeparator: \.isNewline)
      .first
      .map(String.init)
  }

  private func latestAwaitingDevelopSessionIndex() -> Int? {
    sessions.indices
      .filter { sessions[$0].status == .awaitingApproval && sessions[$0].endedAt == nil }
      .max { sessions[$0].session < sessions[$1].session }
  }

  private func fail(_ error: Error) {
    errorMessage = error.localizedDescription
    log(error.localizedDescription, level: .error)
  }

  private func tail(_ text: String, max: Int) -> String {
    guard text.count > max else { return text }
    return "...(truncated)...\n" + String(text.suffix(max))
  }
}

/// Top-level workspace selection driven by the sidebar.
///
/// The sidebar has two kinds of entries: the singleton Sandbox section (hosting
/// the shared VM view + first-boot checklist + provisioning UI) and the
/// per-project list. `WorkspaceSelection` lets the detail pane swap between
/// them without losing track of which project was last viewed.
enum WorkspaceSelection: Equatable {
  case sandbox
  case project(UUID)

  var projectID: UUID? {
    if case .project(let id) = self { return id }
    return nil
  }

  var isSandbox: Bool {
    if case .sandbox = self { return true }
    return false
  }
}

@MainActor
final class AppModel: ObservableObject {
  @Published var projects: [CompassProject] = []
  @Published var selectedProjectID: UUID?
  @Published var workspaceSelection: WorkspaceSelection = .sandbox
  @Published var modelOverride = ""
  @Published private(set) var agentSettings: AgentRuntimeSettings
  private let agentSettingsStore: AgentSettingsStore
  @Published var errorMessage: String?

  /// Process-wide shared VM host. Bound to the singleton in
  /// `SharedCompassVM.shared` so every call site sees the same readiness
  /// snapshot. UI binds to its `@Published` properties via the singleton's
  /// own `ObservableObject` surface — there is no per-AppModel mirror.
  let sharedVMHost: SharedCompassVM = SharedCompassVM.shared

  init(agentSettingsStore: AgentSettingsStore = AgentSettingsStore()) {
    self.agentSettingsStore = agentSettingsStore
    self.agentSettings = agentSettingsStore.load()
  }

  // MARK: - Agent settings setters

  func setAgentBaseURL(_ raw: String) {
    agentSettingsStore.setBaseURL(raw)
    agentSettings = agentSettingsStore.load()
  }

  func setAgentAPIKey(_ raw: String) {
    do {
      try agentSettingsStore.setAPIKey(raw)
    } catch {
      errorMessage = "Could not save API key: \(error.localizedDescription)"
    }
    agentSettings = agentSettingsStore.load()
  }

  func setAgentDefaultModel(_ raw: String) {
    agentSettingsStore.setDefaultModel(raw)
    agentSettings = agentSettingsStore.load()
  }

  func setAgentPlanModelOverride(_ raw: String) {
    agentSettingsStore.setPlanModelOverride(raw)
    agentSettings = agentSettingsStore.load()
  }

  func setAgentDevelopModelOverride(_ raw: String) {
    agentSettingsStore.setDevelopModelOverride(raw)
    agentSettings = agentSettingsStore.load()
  }

  func setAgentReflectModelOverride(_ raw: String) {
    agentSettingsStore.setReflectModelOverride(raw)
    agentSettings = agentSettingsStore.load()
  }

  func setAgentCriticModelOverride(_ raw: String) {
    agentSettingsStore.setCriticModelOverride(raw)
    agentSettings = agentSettingsStore.load()
  }

  var selectedProject: CompassProject? {
    projects.first { $0.id == selectedProjectID }
  }

  /// Switches the detail pane to the Sandbox section.
  func selectSandbox() {
    workspaceSelection = .sandbox
    errorMessage = nil
  }

  func bootstrap() async {
    Self.cleanLegacyHostWorktreesCacheIfPresent()

    projects = KnownProjectStore.load().map(CompassProject.init(record:))
    selectedProjectID = projects.sorted { $0.lastOpenedAt > $1.lastOpenedAt }.first?.id
    if let id = selectedProjectID {
      workspaceSelection = .project(id)
    } else {
      workspaceSelection = .sandbox
    }

    if projects.isEmpty {
      errorMessage = nil
    } else {
      for project in projects {
        await project.refresh()
      }
    }

    // Always-on lifecycle: warm up the shared VM, and if the bundle is
    // already provisioned, kick off the live VZ instance so agent runs
    // against `.sharedVM` projects don't pay a cold-start tax. Failures
    // are non-fatal — readiness captures any problem and Develop falls
    // back to `.host` automatically.
    Task { [weak self] in
      guard let self else { return }
      do {
        try await self.sharedVMHost.warmup()
      } catch {
        self.log(error.localizedDescription, level: .warning)
        return
      }
      if self.sharedVMHost.bundle.existsOnDisk() {
        do {
          try await self.sharedVMHost.start()
        } catch {
          self.log(
            "Shared VM start failed: \(error.localizedDescription)",
            level: .warning
          )
        }
      }
    }
  }

  /// One-shot GC for `~/Library/Caches/Compass/Worktrees/`, the
  /// legacy per-iteration host worktree cache used by the
  /// pre-removal Develop sandbox. Existing dev-* subdirectories are
  /// orphaned now that Compass no longer creates host worktrees;
  /// remove the whole tree on launch so they don't accumulate.
  ///
  /// Best-effort: silently ignores "directory doesn't exist" and
  /// any permission errors. The user can also rm the tree manually.
  private static func cleanLegacyHostWorktreesCacheIfPresent() {
    guard
      let cachesRoot = try? FileManager.default.url(
        for: .cachesDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: false
      )
    else {
      return
    }
    let legacyRoot =
      cachesRoot
      .appendingPathComponent("Compass", isDirectory: true)
      .appendingPathComponent("Worktrees", isDirectory: true)
    guard FileManager.default.fileExists(atPath: legacyRoot.path) else {
      return
    }
    try? FileManager.default.removeItem(at: legacyRoot)
  }

  /// Surface for AppModel-level log lines (the per-project loggers route
  /// through `CompassProject`). Used by the warmup task.
  private func log(_ message: String, level: LiveLine.Level) {
    // No global log buffer at the AppModel layer today; surface via
    // `errorMessage` for warnings/errors so the UI shows them and discard
    // info lines.
    switch level {
    case .warning, .error:
      errorMessage = message
    default:
      break
    }
  }

  func chooseRepository() async {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.message = "Choose a Git repository for Compass"

    guard panel.runModal() == .OK, let url = panel.url else { return }

    do {
      let repoURL = try await resolveGitRoot(from: url)
      let project = upsertProject(repoURL: repoURL)
      selectProject(project)
      project.logProjectSelected()
      await project.refresh()
    } catch {
      fail(error)
    }
  }

  func selectProject(_ project: CompassProject) {
    selectedProjectID = project.id
    workspaceSelection = .project(project.id)
    project.lastOpenedAt = Date()
    errorMessage = nil
    saveProjects()
    Task { await project.refresh() }
  }

  func removeProject(_ project: CompassProject) {
    if project.canStop {
      project.stopRun()
    }
    projects.removeAll { $0.id == project.id }
    if selectedProjectID == project.id {
      selectedProjectID = projects.sorted { $0.lastOpenedAt > $1.lastOpenedAt }.first?.id
      if let newID = selectedProjectID {
        workspaceSelection = .project(newID)
      } else {
        workspaceSelection = .sandbox
      }
    }
    saveProjects()
  }

  func playSelectedProject() async {
    guard let selectedProject else { return }
    await selectedProject.play(agentSettings: agentSettings, modelOverride: modelOverride)
  }

  func runMutationTestingForSelectedProject() async {
    await selectedProject?.runMutationTesting()
  }

  func refreshSelectedProject() async {
    await selectedProject?.refresh()
  }

  private func upsertProject(repoURL: URL) -> CompassProject {
    let standardized = repoURL.standardizedFileURL
    if let existing = projects.first(where: { $0.repoURL.path == standardized.path }) {
      existing.lastOpenedAt = Date()
      saveProjects()
      return existing
    }

    let project = CompassProject(repoURL: standardized)
    projects.insert(project, at: 0)
    saveProjects()
    return project
  }

  private func resolveGitRoot(from url: URL) async throws -> URL {
    let result: ProcessResult
    do {
      result = try await ProcessRunner.runEnv(
        "git",
        ["rev-parse", "--show-toplevel"],
        workingDirectory: url
      )
    } catch {
      throw AppModelError.notGitRepository(url.path)
    }

    guard result.exitCode == 0 else {
      throw AppModelError.notGitRepository(url.path)
    }

    let root = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !root.isEmpty else {
      throw AppModelError.notGitRepository(url.path)
    }
    return URL(fileURLWithPath: root).standardizedFileURL
  }

  func saveProjects() {
    do {
      try saveProjectsThrowing()
    } catch {
      fail(error)
    }
  }

  func saveProjectsThrowing() throws {
    try KnownProjectStore.save(projects.map(\.record))
  }

  private func fail(_ error: Error) {
    errorMessage = error.localizedDescription
  }
}

enum KnownProjectActiveStorage: String, Codable, CaseIterable, Identifiable {
  case repoLocal = "repo_local"
  case applicationSupport = "application_support"

  var id: Self { self }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let rawValue = try container.decode(String.self)
    self = KnownProjectActiveStorage(rawValue: rawValue) ?? .repoLocal
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

struct CompassProjectStorageResolver: Equatable {
  var repoURL: URL
  var activeStorage: KnownProjectActiveStorage
  var applicationSupportRoots: KnownProjectStore.ApplicationSupportRoots

  init(
    repoURL: URL,
    activeStorage: KnownProjectActiveStorage = .repoLocal,
    applicationSupportRoots: KnownProjectStore.ApplicationSupportRoots =
      KnownProjectStore.productionApplicationSupportRoots()
  ) {
    self.repoURL = repoURL.standardizedFileURL
    self.activeStorage = activeStorage
    self.applicationSupportRoots = applicationSupportRoots
  }

  var storageRootURL: URL {
    Self.storageRootURL(
      for: repoURL,
      activeStorage: activeStorage,
      applicationSupportRoots: applicationSupportRoots
    )
  }

  var workspace: CompassWorkspace {
    CompassWorkspace(repoURL: repoURL, storageRootURL: storageRootURL)
  }

  static func storageRootURL(
    for repoURL: URL,
    activeStorage: KnownProjectActiveStorage,
    applicationSupportRoots roots: KnownProjectStore.ApplicationSupportRoots
  ) -> URL {
    let standardizedRepoURL = repoURL.standardizedFileURL
    switch activeStorage {
    case .repoLocal:
      return CompassWorkspace.repoLocalStorageRootURL(for: standardizedRepoURL)
    case .applicationSupport:
      return CompassWorkspaceStorageAssessment.currentApplicationSupportCandidateURL(
        for: standardizedRepoURL,
        applicationSupportRoots: roots
      )
    }
  }
}

struct KnownProjectRecord: Codable, Identifiable, Equatable {
  var id: UUID
  var path: String
  var activeStorage: KnownProjectActiveStorage
  var addedAt: Double
  var lastOpenedAt: Double
  var nativeFeedbackMode: NativeFeedbackMode

  enum CodingKeys: String, CodingKey {
    case id
    case path
    case activeStorage
    case addedAt
    case lastOpenedAt
    case nativeFeedbackMode
  }

  init(
    id: UUID,
    path: String,
    activeStorage: KnownProjectActiveStorage = .repoLocal,
    addedAt: Double,
    lastOpenedAt: Double,
    nativeFeedbackMode: NativeFeedbackMode = .notifications
  ) {
    self.id = id
    self.path = path
    self.activeStorage = activeStorage
    self.addedAt = addedAt
    self.lastOpenedAt = lastOpenedAt
    self.nativeFeedbackMode = nativeFeedbackMode
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    path = try container.decode(String.self, forKey: .path)
    activeStorage =
      try container.decodeIfPresent(
        KnownProjectActiveStorage.self,
        forKey: .activeStorage
      ) ?? .repoLocal
    addedAt = try container.decode(Double.self, forKey: .addedAt)
    lastOpenedAt = try container.decode(Double.self, forKey: .lastOpenedAt)
    nativeFeedbackMode =
      try container.decodeIfPresent(
        NativeFeedbackMode.self,
        forKey: .nativeFeedbackMode
      ) ?? .notifications
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(path, forKey: .path)
    try container.encode(activeStorage, forKey: .activeStorage)
    try container.encode(addedAt, forKey: .addedAt)
    try container.encode(lastOpenedAt, forKey: .lastOpenedAt)
    try container.encode(nativeFeedbackMode, forKey: .nativeFeedbackMode)
  }
}

extension CompassProject {
  fileprivate convenience init(record: KnownProjectRecord) {
    self.init(
      id: record.id,
      repoURL: URL(fileURLWithPath: record.path).standardizedFileURL,
      activeStorage: record.activeStorage,
      addedAt: Date(timeIntervalSince1970: record.addedAt),
      lastOpenedAt: Date(timeIntervalSince1970: record.lastOpenedAt),
      nativeFeedbackMode: record.nativeFeedbackMode
    )
  }

  fileprivate var record: KnownProjectRecord {
    KnownProjectRecord(
      id: id,
      path: repoURL.path,
      activeStorage: activeStorage,
      addedAt: addedAt.timeIntervalSince1970,
      lastOpenedAt: lastOpenedAt.timeIntervalSince1970,
      nativeFeedbackMode: nativeFeedbackMode
    )
  }

  fileprivate func logProjectSelected() {
    log("Selected repo: \(repoURL.path)", level: .success)
    log("Compass workspace: \(compassPath)", level: .info)
  }
}

enum KnownProjectStore {
  struct ApplicationSupportRoots: Equatable {
    var current: URL
    var legacy: URL
  }

  static func load() -> [KnownProjectRecord] {
    load(applicationSupportRoots: productionApplicationSupportRoots())
  }

  static func load(applicationSupportRoots roots: ApplicationSupportRoots) -> [KnownProjectRecord] {
    let sourceURL =
      FileManager.default.fileExists(atPath: projectsURL(in: roots.current).path)
      ? projectsURL(in: roots.current)
      : legacyProjectsURL(in: roots.legacy)
    guard let data = try? Data(contentsOf: sourceURL), !data.isEmpty else {
      return []
    }
    return (try? JSONDecoder().decode([KnownProjectRecord].self, from: data)) ?? []
  }

  static func save(_ records: [KnownProjectRecord]) throws {
    try save(records, applicationSupportRoots: productionApplicationSupportRoots())
  }

  static func save(
    _ records: [KnownProjectRecord], applicationSupportRoots roots: ApplicationSupportRoots
  ) throws {
    let directoryURL = directoryURL(in: roots.current)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(records)
    try data.write(to: projectsURL(in: roots.current), options: .atomic)
  }

  private static func projectsURL(in currentApplicationSupportRoot: URL) -> URL {
    directoryURL(in: currentApplicationSupportRoot).appending(path: "projects.json")
  }

  private static func legacyProjectsURL(in legacyApplicationSupportRoot: URL) -> URL {
    legacyDirectoryURL(in: legacyApplicationSupportRoot).appending(path: "projects.json")
  }

  static func directoryURL(in currentApplicationSupportRoot: URL) -> URL {
    currentApplicationSupportRoot.appending(path: "Compass", directoryHint: .isDirectory)
  }

  static func legacyDirectoryURL(in legacyApplicationSupportRoot: URL) -> URL {
    legacyApplicationSupportRoot.appending(path: "CompassNative", directoryHint: .isDirectory)
  }

  static func productionApplicationSupportRoots() -> ApplicationSupportRoots {
    let base =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.homeDirectoryForCurrentUser.appending(
        path: "Library/Application Support", directoryHint: .isDirectory)
    return ApplicationSupportRoots(current: base, legacy: base)
  }
}

private enum AppModelError: LocalizedError {
  case noRepositorySelected
  case notGitRepository(String)
  case gitCommandFailed(String)
  case internalInvariant(String)
  case rejectedPlan(String)

  var errorDescription: String? {
    switch self {
    case .noRepositorySelected:
      return "Choose a Git repository before running Compass."
    case .notGitRepository(let path):
      return "\(path) is not inside a Git repository."
    case .gitCommandFailed(let message):
      return message
    case .internalInvariant(let message):
      return message
    case .rejectedPlan(let message):
      return message
    }
  }
}

private struct PostCheckResult {
  var ok: Bool
  var retryIssues: [String]
  var displayIssues: [String]
  var verifyOutput: VerifyOutput?
}
