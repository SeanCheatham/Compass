import AppKit
import Foundation
import Virtualization

typealias CompassWorkspaceStorageMigrationAction = (CompassWorkspaceStorageMigrationPlan) throws -> CompassWorkspaceStorageMigrationResult

struct CompassWorkspaceStorageActivationConfirmation: Identifiable, Equatable {
    static let titleLimit = 58
    static let messageLimit = 900
    static let actionLabelLimit = 32

    var plan: CompassWorkspaceStorageActivationPlan

    var id: String {
        [
            plan.repoURL.path,
            plan.candidateURL.path,
            plan.projectStorageIdentifier
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
                "This switches Compass state to the prepared Application Support candidate without changing the Git working directory."
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
        detail: "Switch a prepared Application Support candidate into active Compass state while keeping repoURL as the Git/agent workspace.",
        systemImage: "externaldrive.badge.checkmark"
    )

    static func awaitingConfirmation(_ confirmation: CompassWorkspaceStorageActivationConfirmation) -> Self {
        Self(
            phase: .awaitingConfirmation,
            label: "Confirm activation",
            detail: "Review the active-storage switch before Compass starts reading Application Support state.",
            systemImage: confirmation.plan.systemImage
        )
    }

    static func running(plan: CompassWorkspaceStorageActivationPlan) -> Self {
        Self(
            phase: .running,
            label: "Activating storage",
            detail: "Switching active Compass state to \(boundedPath(plan.candidateURL.path, limit: 144)).",
            systemImage: "externaldrive.badge.checkmark"
        )
    }

    static func succeeded(plan: CompassWorkspaceStorageActivationPlan) -> Self {
        Self(
            phase: .succeeded,
            label: "Support storage active",
            detail: "Compass now reads and writes state at \(boundedPath(plan.candidateURL.path, limit: 144)); repoURL remains \(boundedPath(plan.repoURL.path, limit: 96)).",
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
        case let .unavailable(_, detail):
            return "Active-storage activation is unavailable: \(detail)"
        case let .rolledBack(primary, rollbackFailure):
            if let rollbackFailure {
                return "Activation failed and Compass rolled back to repo-local storage. Primary failure: \(primary) Rollback persistence also failed: \(rollbackFailure)"
            }
            return "Activation failed and Compass rolled back to repo-local storage. Primary failure: \(primary)"
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
            plan.manifestURL.path
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
                "No active-storage switch: repo-local .compass/ remains the source of truth after this copy."
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
        detail: "Copy repo-local .compass/ to Application Support as an opt-in candidate. Repo-local remains active.",
        systemImage: "arrow.triangle.2.circlepath"
    )

    static func awaitingConfirmation(_ confirmation: CompassWorkspaceStorageMigrationConfirmation) -> Self {
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
            detail: "Copying repo-local .compass/ to \(boundedPath(plan.destinationURL.path, limit: 128)); repo-local remains active.",
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
            return "Storage migration unexpectedly reported an active-storage switch; repo-local .compass/ must remain active."
        case let .repoLocalSourceMissing(path):
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
    @Published var activityProfile = RepositoryActivityProfile.empty
    @Published var activitySourceSnapshot = RepositoryActivitySourceSnapshot.notScanned()
    @Published var cinematicInfluenceSettings: CinematicInfluenceSettings
    @Published private(set) var cinematicNativeFeedbackCueLifecycle = CinematicNativeFeedbackCueLifecycle()
    @Published var cinematicNativeFeedbackCue: CinematicNativeFeedbackCuePlan?
    @Published var nativeFeedbackMode: NativeFeedbackMode {
        didSet {
            guard nativeFeedbackMode == .off else { return }
            clearCinematicNativeFeedbackCue(reason: .modeOff)
        }
    }
    @Published var developSandbox: DevelopSandboxPreference
    @Published var liveLog: [LiveLine] = []
    @Published var phase: LoopPhase = .idle {
        didSet {
            guard oldValue != phase else { return }
            scheduleCinematicBriefingRefresh(reason: .phaseChanged)
        }
    }
    @Published var cinematicBriefing = CinematicBriefing.placeholder
    @Published var cinematicWorldText = CinematicWorldText.placeholder
    @Published var cinematicRunRecapFlavor: CinematicRunRecapFlavor?
    @Published var cinematicRunRecapShareArtifactRecording: CinematicRunRecapShareArtifactRecordingResult?
    @Published var cinematicRunRecapShareArtifactCleanup: CinematicRunRecapShareArtifactCleanupResult?
    @Published var cinematicRunRecapShareArtifactLibraryContext: CinematicRunRecapShareArtifactLibraryContext
    @Published var cinematicRunRecapShareArtifactHistory = CinematicRunRecapShareArtifactHistoryPlan.unavailable(
        reason: "not-scanned"
    )
    @Published var cinematicRunRecapShareArtifactSourceReconciliation =
        CinematicRunRecapShareArtifactSourceReconciliationPlanner.plan(
            activeHistoryPlan: CinematicRunRecapShareArtifactHistoryPlan.unavailable(reason: "not-scanned"),
            activitySourceSnapshot: RepositoryActivitySourceSnapshot.notScanned()
        )
    @Published var cinematicDiagnosticsWarningBundleHistory = CinematicDiagnosticsWarningBundleHistory()
    @Published var cinematicDiagnosticsWarningPulseQuietingDescriptor:
        CinematicDiagnosticsWarningPulseQuietingDescriptor?
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
              let repoURL = CompassWorkspace.discover(from: repoURL) else { return nil }
        return makeWorkspace(repoURL: repoURL)
    }

    private var executor: AgentExecutor?
    private var stopRequested = false
    private var cinematicBriefingTask: Task<Void, Never>?
    private var cinematicNativeFeedbackCueExpiryTask: Task<Void, Never>?
    private var lastCinematicRefreshInput: CinematicRefreshInput?
    private var lastCinematicBriefingGeneratedAt = Date.distantPast
    private let storageMigrationAction: CompassWorkspaceStorageMigrationAction
    private let mutationTestingRunner: ProcessRunner.InvocationRunner?
    private let maxDevelopAttempts = 3
    private let reflectSessionWindow = 10

    init(
        id: UUID = UUID(),
        repoURL: URL,
        activeStorage: KnownProjectActiveStorage = .repoLocal,
        addedAt: Date = Date(),
        lastOpenedAt: Date = Date(),
        cinematicInfluenceSettings: CinematicInfluenceSettings = CinematicInfluenceSettings(),
        nativeFeedbackMode: NativeFeedbackMode = .notifications,
        developSandbox: DevelopSandboxPreference = .host,
        cinematicRunRecapShareArtifactLibraryContext: CinematicRunRecapShareArtifactLibraryContext = .empty,
        storageApplicationSupportRoots: KnownProjectStore.ApplicationSupportRoots = KnownProjectStore.productionApplicationSupportRoots(),
        storageMigrationAction: @escaping CompassWorkspaceStorageMigrationAction = { plan in
            try CompassWorkspaceStorageMigrator().migrate(plan: plan)
        },
        mutationTestingRunner: ProcessRunner.InvocationRunner? = nil
    ) {
        self.id = id
        self.repoURL = repoURL.standardizedFileURL
        self.activeStorage = activeStorage
        let initialActivitySourceSnapshot = RepositoryActivitySourceSnapshot.notScanned(activeStorage: activeStorage)
        activitySourceSnapshot = initialActivitySourceSnapshot
        cinematicRunRecapShareArtifactSourceReconciliation =
            CinematicRunRecapShareArtifactSourceReconciliationPlanner.plan(
                activeHistoryPlan: CinematicRunRecapShareArtifactHistoryPlan.unavailable(reason: "not-scanned"),
                activitySourceSnapshot: initialActivitySourceSnapshot
            )
        self.addedAt = addedAt
        self.lastOpenedAt = lastOpenedAt
        self.cinematicInfluenceSettings = cinematicInfluenceSettings
        self.nativeFeedbackMode = nativeFeedbackMode
        self.developSandbox = developSandbox
        self.cinematicRunRecapShareArtifactLibraryContext = cinematicRunRecapShareArtifactLibraryContext
        self.storageApplicationSupportRoots = storageApplicationSupportRoots
        self.storageMigrationAction = storageMigrationAction
        self.mutationTestingRunner = mutationTestingRunner
        let briefingInput = CinematicBriefingInput(
            repoName: repoURL.lastPathComponent,
            currentPhase: LoopPhase.idle.rawValue,
            immediatePlanTitle: "No immediate plan",
            completedCount: 0,
            latestEvent: nil
        )
        cinematicBriefing = CinematicBriefingService.deterministicBriefing(for: briefingInput)
        cinematicWorldText = CinematicWorldTextService.deterministicWorldText(
            for: CinematicWorldTextInput(
                repoName: briefingInput.repoName,
                currentPhase: briefingInput.currentPhase,
                immediatePlanTitle: briefingInput.immediatePlanTitle,
                completedCount: briefingInput.completedCount,
                latestEvent: briefingInput.latestEvent,
                languageProfile: languageProfile,
                activityProfile: activityProfile
            )
        )
    }

    deinit {
        cinematicBriefingTask?.cancel()
        cinematicNativeFeedbackCueExpiryTask?.cancel()
    }
}

private enum CinematicBriefingRefreshReason {
    case projectRefresh
    case planAccepted
    case phaseChanged
    case liveEvent
}

struct CinematicRefreshInput: Equatable {
    var briefing: CinematicBriefingInput
    var worldText: CinematicWorldTextInput
    var commitConstellationIdentifier: String
    var runRecapFlavor: CinematicRunRecapFlavorInput? = nil
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
            preference: AgentExecutionEnvironmentPreference(developSandbox: developSandbox),
            vmReadiness: SharedCompassVM.shared.readiness
        )
    }

    var runtimeDiagnosticsMenu: AgentExecutionEnvironmentMenu {
        let environment = agentExecutionEnvironment
        // The env-presentation plan represents Develop's bash routing — the
        // phase that actually creates a worktree under the host workspaces
        // root and vsock-syncs it into the guest. Plan/Reflect/mutation
        // testing run against the main repo path (outside the workspaces
        // root) and stay on host by design; using the main repo here would
        // make the dropdown report a spurious "falling back" state whenever
        // the VM is otherwise healthy.
        let envLaunchPlan = agentLaunchPlan(for: SharedCompassVM.shared.workspacesRootURL)
        let mutationLaunchPlan = agentLaunchPlan(for: repoURL)
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

    var cinematicCommitConstellationPlan: CinematicCommitConstellationPlan {
        CinematicCommitConstellationPlan(sessions: sessions, hasRepository: hasRepository)
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
            cinematicRunRecapShareArtifactHistory = CinematicRunRecapShareArtifactHistoryPlan.unavailable(
                reason: "no-repository"
            )
            refreshRunRecapShareArtifactSourceReconciliation(workspace: nil)
            languageProfile = .empty
            activityProfile = .empty
            scheduleCinematicBriefingRefresh(reason: .projectRefresh)
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
            cinematicRunRecapShareArtifactHistory = CinematicRunRecapShareArtifactHistoryPlan.unavailable(
                reason: "storage-root-missing",
                storageRootURL: workspace.compassURL,
                sessionsURL: workspace.sessionsURL
            )
            refreshRunRecapShareArtifactSourceReconciliation(workspace: workspace)
            activityProfile = .empty
            scheduleCinematicBriefingRefresh(reason: .projectRefresh)
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
        cinematicRunRecapShareArtifactHistory = workspace.refreshRunRecapShareArtifactHistory()
        refreshRunRecapShareArtifactSourceReconciliation(workspace: workspace)
        activityProfile = await RepositoryActivityProfileService.scan(workspace: workspace)
        scheduleCinematicBriefingRefresh(reason: .projectRefresh)
    }

    private func refreshRunRecapShareArtifactSourceReconciliation(workspace: CompassWorkspace?) {
        if let workspace {
            cinematicRunRecapShareArtifactSourceReconciliation =
                workspace.refreshRunRecapShareArtifactSourceReconciliation(
                    activeHistoryPlan: cinematicRunRecapShareArtifactHistory,
                    activitySourceSnapshot: activitySourceSnapshot
                )
        } else {
            cinematicRunRecapShareArtifactSourceReconciliation =
                CinematicRunRecapShareArtifactSourceReconciliationPlanner.plan(
                    activeHistoryPlan: cinematicRunRecapShareArtifactHistory,
                    activitySourceSnapshot: activitySourceSnapshot
                )
        }
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

    @discardableResult
    func recordRunRecapShareArtifact(
        sharePlan: CinematicRunRecapSharePlan
    ) async -> CinematicRunRecapShareArtifactRecordingResult {
        let warningPulseAudit = currentRunRecapShareArtifactWarningPulseAudit()
        let result: CinematicRunRecapShareArtifactRecordingResult
        if let workspace {
            result = workspace.recordRunRecapShareArtifact(
                sharePlan: sharePlan,
                sessions: sessions,
                warningPulseAudit: warningPulseAudit
            )
            cinematicRunRecapShareArtifactHistory = workspace.refreshRunRecapShareArtifactHistory()
            refreshRunRecapShareArtifactSourceReconciliation(workspace: workspace)
        } else {
            let artifactPlan = CinematicRunRecapShareArtifactPlanner.plan(
                sharePlan: sharePlan,
                sessions: sessions,
                warningPulseAudit: warningPulseAudit
            )
            result = artifactPlan.isAvailable
                ? .failed(plan: artifactPlan, error: AppModelError.noRepositorySelected)
                : .skipped(plan: artifactPlan)
            cinematicRunRecapShareArtifactHistory = CinematicRunRecapShareArtifactHistoryPlan.unavailable(
                reason: "no-repository"
            )
            refreshRunRecapShareArtifactSourceReconciliation(workspace: nil)
        }

        cinematicRunRecapShareArtifactRecording = result
        switch result.status {
        case .recorded:
            log(
                "Recap share artifact recorded: \(result.artifactURL?.lastPathComponent ?? result.artifactPlan.filename)",
                level: .success
            )
        case .skipped:
            log(result.detail, level: .info)
        case .failed:
            log(result.detail, level: .warning)
        }
        return result
    }

    private func currentRunRecapShareArtifactWarningPulseAudit()
        -> CinematicRunRecapShareArtifactWarningPulseAudit? {
        guard let currentBundle = cinematicDiagnosticsWarningBundleHistory.currentUnresolvedBundle else {
            return nil
        }
        let status = CinematicDiagnosticsWarningPulseQuietingStatusDescriptor(
            currentBundle: currentBundle,
            quietingDescriptor: cinematicDiagnosticsWarningPulseQuietingDescriptor
        )
        return CinematicRunRecapShareArtifactWarningPulseAudit(
            entry: currentBundle,
            status: status
        )
    }

    @discardableResult
    func cleanupRunRecapShareArtifacts() async -> CinematicRunRecapShareArtifactCleanupResult {
        let result: CinematicRunRecapShareArtifactCleanupResult
        if let workspace {
            result = workspace.cleanupRunRecapShareArtifacts()
            cinematicRunRecapShareArtifactHistory = result.refreshedHistory
            refreshRunRecapShareArtifactSourceReconciliation(workspace: workspace)
        } else {
            let history = CinematicRunRecapShareArtifactHistoryPlan.unavailable(
                reason: "no-repository"
            )
            result = CinematicRunRecapShareArtifactCleanupResult(
                retentionLimit: CinematicRunRecapShareArtifactHistoryPlan.retentionLimit,
                cleanupCandidateCount: 0,
                deletedIdentifiers: [],
                skippedIdentifiers: [],
                failedIdentifiers: [],
                refreshedHistory: history
            )
            cinematicRunRecapShareArtifactHistory = history
            refreshRunRecapShareArtifactSourceReconciliation(workspace: nil)
        }

        cinematicRunRecapShareArtifactCleanup = result
        switch result.status {
        case .deleted:
            log(result.detail, level: .success)
        case .skipped:
            log(result.detail, level: .info)
        case .failed:
            log(result.detail, level: .warning)
        }
        return result
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
            log("Active storage activation blocked: \(activeStorageActivationState.detail)", level: .warning)
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
        log("Active storage activation: switching Compass state to \(plan.candidateURL.path).", level: .info)
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
        log("Storage migration: preparing Application Support candidate at \(plan.destinationURL.path).", level: .info)
        await Task.yield()

        do {
            let result = try storageMigrationAction(plan)
            guard result.activeStorageDidChange == false else {
                throw CompassProjectStorageMigrationActionError.activeStorageChanged
            }
            guard FileManager.default.fileExists(atPath: plan.sourceCompassURL.path) else {
                throw CompassProjectStorageMigrationActionError.repoLocalSourceMissing(plan.sourceCompassURL.path)
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
           state.immediate != nil {
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
            scheduleCinematicBriefingRefresh(reason: .planAccepted)
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
                        throw AppModelError.internalInvariant("Session #\(sessionNumber) disappeared while pausing.")
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
                    try? workspace.writeDrafts([consumedDrafts, current].filter { !$0.isEmpty }.joined(separator: "\n"))
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
                try? workspace.writeDrafts([consumedDrafts, current].filter { !$0.isEmpty }.joined(separator: "\n"))
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

            var priorIssues: [String] = []
            var finalIssues: [String] = []
            var finalVerifyOutput: VerifyOutput?
            var succeeded = false

            for attempt in 1...maxDevelopAttempts {
                phase = .developing
                let prompt = Prompts.developPrompt(
                    next: next,
                    lessons: workspace.readLessons(),
                    vision: workspace.readVision(),
                    attempt: attempt,
                    priorIssues: priorIssues
                )

                let launchPlan = agentLaunchPlan(for: workspace.repoURL)
                logExecutionEnvironmentPreflight(
                    phase: "Develop",
                    nativeExecutionURL: workspace.repoURL,
                    launchPlan: launchPlan,
                    sessionIndex: sessionIndex,
                    attempt: attempt
                )
                log("Develop: launching agent (attempt \(attempt)/\(maxDevelopAttempts)).", level: .info)
                let summary = try await runAgent(
                    phase: .develop,
                    agentSettings: agentSettings,
                    modelOverride: modelOverride,
                    workingDirectory: workspace.repoURL,
                    userPrompt: prompt,
                    submitResultSchema: Prompts.developSchema,
                    decode: DevelopSummary.self
                )

                // Under the `.sharedVM` route the agent worked in the
                // guest workspace and Verify ran there too. We defer the
                // host-side pull and commit until Verify passes so a
                // failed attempt doesn't leave the main repo dirty.
                // Under the host route the agent already committed in
                // place using its own `git` tool.

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
                    // Pull guest workspace contents onto the main repo
                    // and create the host-side commit on the user's
                    // current branch. The guest has no `.git`, so the
                    // agent itself cannot commit there. Skipped under
                    // the host route because the agent committed in
                    // place via its `bash` tool.
                    if case .sharedVM = launchPlan.effectiveRoute {
                        await pullDevelopChangesIfNeeded(
                            mainRepoURL: workspace.repoURL,
                            plan: launchPlan
                        )
                        if let commitIssue = await commitAgentChangesOnHost(
                            mainRepoURL: workspace.repoURL,
                            summary: summary
                        ) {
                            finalIssues = [commitIssue]
                            succeeded = false
                            break
                        }
                    }
                    do {
                        logLessonEdits(try workspace.applyLessonEdits(summary.lessonEdits))
                    } catch {
                        let note = "Lesson edits were not applied: \(error.localizedDescription)"
                        appendSessionNote(note, to: sessionIndex)
                        log(note, level: .error)
                    }
                    succeeded = true
                    feedback(.commitsPromoted)
                    break
                }

                priorIssues = post.retryIssues
                if attempt < maxDevelopAttempts {
                    feedback(.developRetrying)
                    log("Develop post-checks failed; retrying with failure context.", level: .warning)
                }
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
            log(succeeded ? "Develop completed." : "Develop finished with failed post-checks.", level: succeeded ? .success : .error)
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
        // The project's `developSandbox` is the authoritative per-project
        // toggle. Translate it into a `AgentExecutionEnvironmentPreference`
        // so the readiness-gated planner can route to the shared VM when
        // readiness is .ready and fall back to host otherwise.
        let preference: AgentExecutionEnvironmentPreference
        switch developSandbox {
        case .host:
            preference = .host
        case .sharedVM:
            preference = .sharedVM
        }
        let host = SharedCompassVM.shared
        let readiness = host.readiness
        return AgentExecutionLaunchPlan.plan(
            repoURL: nativeExecutionURL,
            preference: preference,
            vmReadiness: readiness,
            sharedVMRouteFactory: { hostURL in
                Self.makeSharedVMRoute(
                    hostRepoURL: hostURL,
                    readiness: readiness,
                    bundle: host.bundle,
                    workspacesRootURL: host.workspacesRootURL
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
        bundle: SharedCompassVMBundle,
        workspacesRootURL: URL
    ) -> SharedVMRoute? {
        guard case let .ready(sshDestination) = readiness else { return nil }

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
        _ = workspacesRootURL // retained for API compatibility; no longer used.

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
            preference: AgentExecutionEnvironmentPreference(developSandbox: developSandbox),
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
        let recentSessions = sessions
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
            scheduleCinematicBriefingRefresh(reason: .planAccepted)
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
        case let .sharedVM(route):
            guard let machine = SharedCompassVM.shared.virtualMachine else {
                log("Agent route via Shared VM requested but no live VZVirtualMachine; falling back to host.", level: .warning)
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
            log("Agent route via Shared VM (vsock) at workspace \(guestWorkingDirectory.path)", level: .info)
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
        if case let .sharedVM(route) = launchPlan.effectiveRoute,
           let machine = SharedCompassVM.shared.virtualMachine {
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
            log("Guest workspace at \(result.guestPath) already populated — preserving prior agent state.", level: .info)
        case .freshlyPopulated:
            log("Guest workspace at \(result.guestPath) populated for the first time from \(hostRepoURL.path).", level: .info)
        case .refreshed:
            log("Guest workspace at \(result.guestPath) force-refreshed from \(hostRepoURL.path).", level: .info)
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
        guard case let .sharedVM(route) = plan.effectiveRoute,
              let machine = SharedCompassVM.shared.virtualMachine else {
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
            log("Post-check: running verify command `\(next.verify)` (timeout \(timeoutMs)ms).", level: .info)
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
            log("Post-check: skipping host git-status check under .sharedVM (commits are managed post-Verify by the Develop loop).", level: .info)
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
            return "Host-side commit failed at git status (exit \(status.exitCode)): \(tail(status.stderr + status.stdout, max: 2000))"
        }
        if status.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            log("Host-side commit: pulled guest workspace is identical to the host branch — nothing to commit.", level: .info)
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
        let firstLine = text
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        if firstLine.isEmpty { return "Develop iteration (no summary)" }
        if firstLine.count <= limit { return firstLine }
        return String(firstLine.prefix(limit)).trimmingCharacters(in: .whitespaces)
    }

    private func runGitOrThrow(_ arguments: [String], in directory: URL, failurePrefix: String) async throws {
        let result = try await ProcessRunner.runEnv("git", arguments, workingDirectory: directory)
        guard result.exitCode == 0 else {
            throw AppModelError.gitCommandFailed(
                "\(failurePrefix): \(tail(result.stderr + result.stdout, max: 2000))"
            )
        }
    }

    private func gitCurrentSha(at repoURL: URL) async -> String? {
        guard let result = try? await ProcessRunner.runEnv(
            "git",
            ["rev-parse", "HEAD"],
            workingDirectory: repoURL
        ), result.exitCode == 0 else {
            return nil
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func gitCommits(in repoURL: URL, from before: String?, to after: String?) async -> [SessionCommit] {
        guard let after, before != after else { return [] }
        let range = before.map { "\($0)..\(after)" } ?? after
        guard let result = try? await ProcessRunner.runEnv(
            "git",
            ["log", "--reverse", "--format=%H%x09%h%x09%s", range],
            workingDirectory: repoURL
        ), result.exitCode == 0 else {
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

    func recordCinematicNativeFeedback(
        _ milestone: NativeFeedbackMilestone,
        now: Date = Date()
    ) {
        let reliabilityFeedback = PlanReliabilityFeedback(
            state: state,
            sessions: sessions
        )
        guard let cue = CinematicNativeFeedbackCuePlanner.plan(
            milestone: milestone,
            content: NativeFeedbackContent(milestone: milestone, projectName: displayName),
            phase: isPaused ? .paused : phase,
            feedbackMode: nativeFeedbackMode,
            recentRunCues: reliabilityFeedback.recentRunCues
        ) else {
            clearCinematicNativeFeedbackCue(reason: .cleared, now: now)
            return
        }

        recordCinematicNativeFeedbackCue(cue, now: now)
    }

    @discardableResult
    func recordPlanReadinessNativeFeedback(
        state candidateState: PlanState? = nil,
        gate _: PlanReadinessNativeFeedbackGate,
        now: Date = Date()
    ) -> CinematicNativeFeedbackCuePlan? {
        guard let context = planReadinessNativeFeedbackContext(for: candidateState ?? state) else {
            return nil
        }
        guard let cue = CinematicNativeFeedbackCuePlanner.plan(
            milestone: .developReady,
            content: context.content,
            phase: isPaused ? .paused : phase,
            feedbackMode: nativeFeedbackMode,
            recentRunCues: context.reliabilityFeedback.recentRunCues,
            readinessPlan: context.readinessPlan
        ) else {
            clearCinematicNativeFeedbackCue(reason: .cleared, now: now)
            return nil
        }

        return recordCinematicNativeFeedbackCue(cue, now: now)
    }

    private struct PlanReadinessNativeFeedbackContext {
        var readinessPlan: CinematicPlanCompassReadinessPlan
        var reliabilityFeedback: PlanReliabilityFeedback
        var content: NativeFeedbackContent
    }

    private func planReadinessNativeFeedbackContext(
        for candidateState: PlanState
    ) -> PlanReadinessNativeFeedbackContext? {
        guard candidateState.immediate != nil else { return nil }

        let planCompassPlan = CinematicPlanCompassPlan(state: candidateState)
        let reliabilityFeedback = PlanReliabilityFeedback(
            state: candidateState,
            sessions: sessions
        )
        let readinessPlan = CinematicPlanCompassReadinessPlan(
            state: candidateState,
            planCompassPlan: planCompassPlan,
            reliabilityFeedback: reliabilityFeedback
        )

        return PlanReadinessNativeFeedbackContext(
            readinessPlan: readinessPlan,
            reliabilityFeedback: reliabilityFeedback,
            content: NativeFeedbackContent(readinessPlan: readinessPlan, projectName: displayName)
        )
    }

    @discardableResult
    private func recordCinematicNativeFeedbackCue(
        _ cue: CinematicNativeFeedbackCuePlan,
        now: Date
    ) -> CinematicNativeFeedbackCuePlan {
        var lifecycle = cinematicNativeFeedbackCueLifecycle
        let activeCue = lifecycle.record(cue, now: now)
        cinematicNativeFeedbackCueLifecycle = lifecycle
        cinematicNativeFeedbackCue = activeCue
        scheduleCinematicNativeFeedbackCueExpiry(for: lifecycle.active, now: now)
        scheduleCinematicBriefingRefresh(reason: .projectRefresh)
        return activeCue
    }

    func recordCinematicDiagnosticsWarningBundle(
        _ attentionSummary: CinematicDiagnosticsSummary.AttentionSummary
    ) {
        let updatedHistory = cinematicDiagnosticsWarningBundleHistory.recording(attentionSummary)
        guard updatedHistory != cinematicDiagnosticsWarningBundleHistory else {
            reconcileCinematicDiagnosticsWarningPulseQuietingDescriptor()
            return
        }
        cinematicDiagnosticsWarningBundleHistory = updatedHistory
        reconcileCinematicDiagnosticsWarningPulseQuietingDescriptor()
    }

    func snoozeCinematicDiagnosticsWarningPulse() {
        guard let currentBundle = cinematicDiagnosticsWarningBundleHistory.currentUnresolvedBundle else {
            cinematicDiagnosticsWarningPulseQuietingDescriptor = nil
            return
        }
        let descriptor = CinematicDiagnosticsWarningPulseQuietingDescriptor(entry: currentBundle)
        guard cinematicDiagnosticsWarningPulseQuietingDescriptor != descriptor else { return }
        cinematicDiagnosticsWarningPulseQuietingDescriptor = descriptor
    }

    func resumeCinematicDiagnosticsWarningPulse() {
        guard cinematicDiagnosticsWarningPulseQuietingDescriptor != nil else { return }
        cinematicDiagnosticsWarningPulseQuietingDescriptor = nil
    }

    private func reconcileCinematicDiagnosticsWarningPulseQuietingDescriptor() {
        guard let descriptor = cinematicDiagnosticsWarningPulseQuietingDescriptor else { return }
        guard descriptor.matches(cinematicDiagnosticsWarningBundleHistory.currentUnresolvedBundle) else {
            cinematicDiagnosticsWarningPulseQuietingDescriptor = nil
            return
        }
    }

    private func feedback(_ milestone: NativeFeedbackMilestone) {
        recordCinematicNativeFeedback(milestone)
        NativeFeedbackService.shared.emit(
            milestone,
            projectName: displayName,
            mode: nativeFeedbackMode
        )
    }

    private func feedbackPlanReadinessGate(
        for candidateState: PlanState,
        gate: PlanReadinessNativeFeedbackGate
    ) {
        guard let context = planReadinessNativeFeedbackContext(for: candidateState) else { return }
        recordPlanReadinessNativeFeedback(state: candidateState, gate: gate)
        NativeFeedbackService.shared.emit(
            .developReady,
            projectName: displayName,
            mode: nativeFeedbackMode,
            content: context.content
        )
    }

    @discardableResult
    func expireCinematicNativeFeedbackCue(
        now: Date = Date(),
        expectedLifecycleIdentifier: String? = nil
    ) -> Bool {
        if let expectedLifecycleIdentifier,
           cinematicNativeFeedbackCueLifecycle.active?.lifecycleIdentifier != expectedLifecycleIdentifier {
            return false
        }

        var lifecycle = cinematicNativeFeedbackCueLifecycle
        guard lifecycle.expire(now: now) else {
            if expectedLifecycleIdentifier != nil {
                scheduleCinematicNativeFeedbackCueExpiry(for: lifecycle.active, now: now)
            }
            return false
        }
        cinematicNativeFeedbackCueLifecycle = lifecycle
        cinematicNativeFeedbackCue = lifecycle.activeCue
        if lifecycle.active == nil {
            cinematicNativeFeedbackCueExpiryTask?.cancel()
            cinematicNativeFeedbackCueExpiryTask = nil
        }
        scheduleCinematicBriefingRefresh(reason: .projectRefresh)
        return true
    }

    private func clearCinematicNativeFeedbackCue(
        reason: CinematicNativeFeedbackCueLifecycle.ArchiveReason,
        now: Date = Date()
    ) {
        cinematicNativeFeedbackCueExpiryTask?.cancel()
        cinematicNativeFeedbackCueExpiryTask = nil
        var lifecycle = cinematicNativeFeedbackCueLifecycle
        lifecycle.clear(reason: reason, now: now)
        cinematicNativeFeedbackCueLifecycle = lifecycle
        cinematicNativeFeedbackCue = nil
        scheduleCinematicBriefingRefresh(reason: .projectRefresh)
    }

    private func scheduleCinematicNativeFeedbackCueExpiry(
        for activeCue: CinematicNativeFeedbackCueLifecycle.ActiveCue?,
        now: Date
    ) {
        cinematicNativeFeedbackCueExpiryTask?.cancel()
        guard let activeCue else {
            cinematicNativeFeedbackCueExpiryTask = nil
            return
        }

        let delay = max(0, activeCue.expiresAt.timeIntervalSince(now))
        let lifecycleIdentifier = activeCue.lifecycleIdentifier
        cinematicNativeFeedbackCueExpiryTask = Task { @MainActor [weak self, delay, lifecycleIdentifier] in
            if delay > 0 {
                let nanoseconds = UInt64(delay * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
            }

            guard !Task.isCancelled, let self else { return }
            expireCinematicNativeFeedbackCue(expectedLifecycleIdentifier: lifecycleIdentifier)
        }
    }

    private func log(_ text: String, level: LiveLine.Level) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let line = LiveLine(level: level, text: trimmed)
        liveLog.append(line)
        trimLiveLog()
        scheduleCinematicBriefingRefreshIfMeaningful(line)
    }

    private func log(_ event: LiveEvent) {
        let title = event.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = event.detail?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty || !(detail?.isEmpty ?? true) else { return }

        if event.status == .completed || event.status == .failed,
           let correlationID = event.correlationID,
           let index = liveLog.lastIndex(where: {
               $0.correlationID == correlationID && $0.status == .running
           }) {
            liveLog[index].level = event.level
            liveLog[index].text = title.isEmpty ? liveLog[index].text : title
            liveLog[index].detail = detail?.isEmpty == false ? detail : liveLog[index].detail
            liveLog[index].kind = event.kind
            liveLog[index].status = event.status
            liveLog[index].completedAt = Date()
            scheduleCinematicBriefingRefreshIfMeaningful(liveLog[index])
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
            scheduleCinematicBriefingRefreshIfMeaningful(line)
        }

        trimLiveLog()
    }

    private func trimLiveLog() {
        if liveLog.count > 800 {
            liveLog.removeFirst(liveLog.count - 800)
        }
    }

    private func scheduleCinematicBriefingRefreshIfMeaningful(_ line: LiveLine) {
        guard isMeaningfulBriefingEvent(line) else { return }
        scheduleCinematicBriefingRefresh(reason: .liveEvent)
    }

    private func scheduleCinematicBriefingRefresh(reason: CinematicBriefingRefreshReason) {
        let input = makeCinematicRefreshInput()
        guard input != lastCinematicRefreshInput else { return }
        lastCinematicRefreshInput = input
        if input.runRecapFlavor == nil {
            cinematicRunRecapFlavor = nil
        }

        cinematicBriefingTask?.cancel()
        let delay = cinematicBriefingDelay(for: reason)
        cinematicBriefingTask = Task { @MainActor [weak self, input, delay] in
            if delay > 0 {
                let nanoseconds = UInt64(delay * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
            }

            guard !Task.isCancelled, let self else { return }
            lastCinematicBriefingGeneratedAt = Date()
            let briefing = await CinematicBriefingService.makeBriefing(input: input.briefing)
            let worldText = await CinematicWorldTextService.makeWorldText(input: input.worldText)
            let runRecapFlavor: CinematicRunRecapFlavor?
            if let runRecapFlavorInput = input.runRecapFlavor {
                runRecapFlavor = await CinematicRunRecapFlavorService.makeFlavor(input: runRecapFlavorInput)
            } else {
                runRecapFlavor = nil
            }
            guard !Task.isCancelled else { return }
            cinematicBriefing = briefing
            cinematicWorldText = worldText
            cinematicRunRecapFlavor = runRecapFlavor
        }
    }

    private func makeCinematicRefreshInput() -> CinematicRefreshInput {
        let commitConstellationPlan = cinematicCommitConstellationPlan
        let reliabilityFeedback = PlanReliabilityFeedback(
            state: state,
            sessions: sessions
        )
        let latestCommitSubject = commitConstellationPlan.newestSubject
        let briefing = CinematicBriefingInput(
            repoName: displayName,
            currentPhase: (isPaused ? LoopPhase.paused : phase).rawValue,
            immediatePlanTitle: immediateTitle,
            completedCount: state.completed.count,
            latestEvent: liveLog.last.map(CinematicBriefingEvent.init(line:)),
            latestCommitSubject: latestCommitSubject
        )
        return CinematicRefreshInput(
            briefing: briefing,
            worldText: CinematicWorldTextInput(
                repoName: briefing.repoName,
                currentPhase: briefing.currentPhase,
                immediatePlanTitle: briefing.immediatePlanTitle,
                completedCount: briefing.completedCount,
                latestEvent: briefing.latestEvent,
                latestCommitSubject: briefing.latestCommitSubject,
                languageProfile: languageProfile,
                activityProfile: activityProfile
            ),
            commitConstellationIdentifier: commitConstellationPlan.focusPlan.identifier,
            runRecapFlavor: CinematicRunRecapPlanner.flavorInput(
                state: state,
                sessions: sessions,
                isRunning: isRunning,
                isAutoPlaying: isAutoPlaying,
                recentRunCues: reliabilityFeedback.recentRunCues,
                commitConstellationPlan: commitConstellationPlan,
                nativeFeedbackLifecycle: cinematicNativeFeedbackCueLifecycle
            )
        )
    }

    private func cinematicBriefingDelay(for reason: CinematicBriefingRefreshReason) -> TimeInterval {
        switch reason {
        case .projectRefresh, .planAccepted, .phaseChanged:
            return 0.25
        case .liveEvent:
            let cadenceDelay = max(0, 8 - Date().timeIntervalSince(lastCinematicBriefingGeneratedAt))
            return max(0.8, cadenceDelay)
        }
    }

    private func isMeaningfulBriefingEvent(_ line: LiveLine) -> Bool {
        switch line.kind {
        case .command, .agentMessage, .fileChange, .lifecycle:
            return true
        case .message:
            switch line.level {
            case .success, .warning, .error:
                return true
            case .info:
                let text = line.text.lowercased()
                return text.contains("plan")
                    || text.contains("develop")
                    || text.contains("verify")
                    || text.contains("reflect")
                    || text.contains("workspace")
            case .raw:
                return false
            }
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

    var selectedProject: CompassProject? {
        projects.first { $0.id == selectedProjectID }
    }

    /// Switches the detail pane to the Sandbox section.
    func selectSandbox() {
        workspaceSelection = .sandbox
        errorMessage = nil
    }

    func bootstrap() async {
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

enum CinematicRunRecapShareArtifactComparisonTargetMode: String, Codable, CaseIterable, Identifiable {
    case adjacent
    case pinnedReference = "pinned_reference"

    var id: Self { self }

    var title: String {
        switch self {
        case .adjacent:
            return "Adjacent"
        case .pinnedReference:
            return "Pinned"
        }
    }

    var toggled: Self {
        switch self {
        case .adjacent:
            return .pinnedReference
        case .pinnedReference:
            return .adjacent
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = CinematicRunRecapShareArtifactComparisonTargetMode(rawValue: rawValue) ?? .adjacent
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum CinematicRunRecapShareArtifactWarningPulseFilter: String, Codable, CaseIterable, Identifiable {
    case all
    case any
    case active
    case snoozed

    var id: Self { self }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .any:
            return "Any pulse"
        case .active:
            return "Active"
        case .snoozed:
            return "Snoozed"
        }
    }

    var isActive: Bool {
        self != .all
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = CinematicRunRecapShareArtifactWarningPulseFilter(rawValue: rawValue) ?? .all
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct CinematicRunRecapShareArtifactLibraryContext: Codable, Equatable {
    static let selectedEntryIdentifierMaxCharacters = CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
    static let searchTextMaxCharacters = CinematicRunRecapShareArtifactPreviewBrowserPlan.searchQuerySnippetMaxCharacters
    static let pinnedEntryIdentifierLimit = CinematicRunRecapShareArtifactPinnedReferencePlan.pinIdentifierLimit
    static let savedTourHoldEntryIdentifierMaxCharacters = selectedEntryIdentifierMaxCharacters
    static let empty = CinematicRunRecapShareArtifactLibraryContext()

    var selectedEntryIdentifier: String?
    var searchText: String
    var pinnedEntryIdentifiers: [String]
    var comparisonTargetMode: CinematicRunRecapShareArtifactComparisonTargetMode
    var savedTourHoldEntryIdentifier: String?
    var warningPulseFilter: CinematicRunRecapShareArtifactWarningPulseFilter

    enum CodingKeys: String, CodingKey {
        case selectedEntryIdentifier
        case searchText
        case pinnedEntryIdentifiers
        case comparisonTargetMode
        case savedTourHoldEntryIdentifier
        case warningPulseFilter
    }

    init(
        selectedEntryIdentifier: String? = nil,
        searchText: String = "",
        pinnedEntryIdentifiers: [String] = [],
        comparisonTargetMode: CinematicRunRecapShareArtifactComparisonTargetMode = .adjacent,
        savedTourHoldEntryIdentifier: String? = nil,
        warningPulseFilter: CinematicRunRecapShareArtifactWarningPulseFilter = .all
    ) {
        self.selectedEntryIdentifier = Self.boundedOptionalText(
            selectedEntryIdentifier,
            limit: Self.selectedEntryIdentifierMaxCharacters
        )
        self.searchText = Self.boundedText(
            searchText,
            limit: Self.searchTextMaxCharacters
        )
        self.pinnedEntryIdentifiers = Self.boundedIdentifierList(pinnedEntryIdentifiers)
        self.comparisonTargetMode = comparisonTargetMode
        self.savedTourHoldEntryIdentifier = Self.boundedOptionalText(
            savedTourHoldEntryIdentifier,
            limit: Self.savedTourHoldEntryIdentifierMaxCharacters
        )
        self.warningPulseFilter = warningPulseFilter
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            selectedEntryIdentifier: try container.decodeIfPresent(String.self, forKey: .selectedEntryIdentifier),
            searchText: try container.decodeIfPresent(String.self, forKey: .searchText) ?? "",
            pinnedEntryIdentifiers: try container.decodeIfPresent([String].self, forKey: .pinnedEntryIdentifiers) ?? [],
            comparisonTargetMode: try container.decodeIfPresent(
                CinematicRunRecapShareArtifactComparisonTargetMode.self,
                forKey: .comparisonTargetMode
            ) ?? .adjacent,
            savedTourHoldEntryIdentifier: try container.decodeIfPresent(
                String.self,
                forKey: .savedTourHoldEntryIdentifier
            ),
            warningPulseFilter: try container.decodeIfPresent(
                CinematicRunRecapShareArtifactWarningPulseFilter.self,
                forKey: .warningPulseFilter
            ) ?? .all
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(searchText, forKey: .searchText)
        try container.encodeIfPresent(selectedEntryIdentifier, forKey: .selectedEntryIdentifier)
        if !pinnedEntryIdentifiers.isEmpty {
            try container.encode(pinnedEntryIdentifiers, forKey: .pinnedEntryIdentifiers)
        }
        if comparisonTargetMode != .adjacent {
            try container.encode(comparisonTargetMode, forKey: .comparisonTargetMode)
        }
        try container.encodeIfPresent(savedTourHoldEntryIdentifier, forKey: .savedTourHoldEntryIdentifier)
        if warningPulseFilter != .all {
            try container.encode(warningPulseFilter, forKey: .warningPulseFilter)
        }
    }

    func replacing(
        selectedEntryIdentifier: String?,
        searchText: String,
        pinnedEntryIdentifiers: [String]? = nil,
        comparisonTargetMode: CinematicRunRecapShareArtifactComparisonTargetMode? = nil,
        warningPulseFilter: CinematicRunRecapShareArtifactWarningPulseFilter? = nil
    ) -> CinematicRunRecapShareArtifactLibraryContext {
        CinematicRunRecapShareArtifactLibraryContext(
            selectedEntryIdentifier: selectedEntryIdentifier,
            searchText: searchText,
            pinnedEntryIdentifiers: pinnedEntryIdentifiers ?? self.pinnedEntryIdentifiers,
            comparisonTargetMode: comparisonTargetMode ?? self.comparisonTargetMode,
            savedTourHoldEntryIdentifier: savedTourHoldEntryIdentifier,
            warningPulseFilter: warningPulseFilter ?? self.warningPulseFilter
        )
    }

    func resolvingSelection(
        in historyPlan: CinematicRunRecapShareArtifactHistoryPlan
    ) -> CinematicRunRecapShareArtifactLibraryContext {
        let previewPlan = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: historyPlan,
            selectedEntryIdentifier: selectedEntryIdentifier,
            searchQuery: searchText,
            warningPulseFilter: warningPulseFilter
        )
        return replacing(
            selectedEntryIdentifier: previewPlan.selectedEntryIdentifier,
            searchText: searchText,
            pinnedEntryIdentifiers: resolvedPinnedEntryIdentifiers(in: historyPlan)
        )
    }

    func togglingPinnedEntryIdentifier(
        _ identifier: String?
    ) -> CinematicRunRecapShareArtifactLibraryContext {
        guard let identifier = Self.boundedOptionalText(
            identifier,
            limit: Self.selectedEntryIdentifierMaxCharacters
        ) else {
            return self
        }

        let nextPinnedEntryIdentifiers: [String]
        if pinnedEntryIdentifiers.contains(identifier) {
            nextPinnedEntryIdentifiers = pinnedEntryIdentifiers.filter { $0 != identifier }
        } else {
            nextPinnedEntryIdentifiers = [identifier] + pinnedEntryIdentifiers
        }
        return replacing(
            selectedEntryIdentifier: selectedEntryIdentifier,
            searchText: searchText,
            pinnedEntryIdentifiers: nextPinnedEntryIdentifiers
        )
    }

    func holdingSavedTourEntryIdentifier(
        _ identifier: String?
    ) -> CinematicRunRecapShareArtifactLibraryContext {
        CinematicRunRecapShareArtifactLibraryContext(
            selectedEntryIdentifier: selectedEntryIdentifier,
            searchText: searchText,
            pinnedEntryIdentifiers: pinnedEntryIdentifiers,
            comparisonTargetMode: comparisonTargetMode,
            savedTourHoldEntryIdentifier: identifier,
            warningPulseFilter: warningPulseFilter
        )
    }

    func releasingSavedTourHold() -> CinematicRunRecapShareArtifactLibraryContext {
        holdingSavedTourEntryIdentifier(nil)
    }

    func togglingSavedTourHoldEntryIdentifier(
        _ identifier: String?
    ) -> CinematicRunRecapShareArtifactLibraryContext {
        let boundedIdentifier = Self.boundedOptionalText(
            identifier,
            limit: Self.savedTourHoldEntryIdentifierMaxCharacters
        )
        guard savedTourHoldEntryIdentifier != boundedIdentifier else {
            return releasingSavedTourHold()
        }
        return holdingSavedTourEntryIdentifier(boundedIdentifier)
    }

    func promotingSavedTourHoldToPinnedReference(
        in historyPlan: CinematicRunRecapShareArtifactHistoryPlan
    ) -> CinematicRunRecapShareArtifactLibraryContext {
        guard let savedTourHoldEntryIdentifier,
              historyPlan.entries.contains(where: { $0.identifier == savedTourHoldEntryIdentifier }) else {
            return self
        }

        return CinematicRunRecapShareArtifactLibraryContext(
            selectedEntryIdentifier: selectedEntryIdentifier,
            searchText: searchText,
            pinnedEntryIdentifiers: [savedTourHoldEntryIdentifier] + pinnedEntryIdentifiers,
            comparisonTargetMode: .pinnedReference,
            savedTourHoldEntryIdentifier: savedTourHoldEntryIdentifier,
            warningPulseFilter: warningPulseFilter
        )
    }

    private func resolvedPinnedEntryIdentifiers(
        in historyPlan: CinematicRunRecapShareArtifactHistoryPlan
    ) -> [String] {
        let retainedEntryIdentifiers = Set(historyPlan.entries.map(\.identifier))
        return pinnedEntryIdentifiers.filter { retainedEntryIdentifiers.contains($0) }
    }

    private static func boundedOptionalText(_ text: String?, limit: Int) -> String? {
        let bounded = boundedText(text ?? "", limit: limit)
        return bounded.isEmpty ? nil : bounded
    }

    private static func boundedText(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func boundedIdentifierList(_ identifiers: [String]) -> [String] {
        var seen = Set<String>()
        var boundedIdentifiers: [String] = []

        for identifier in identifiers {
            guard let boundedIdentifier = boundedOptionalText(
                identifier,
                limit: selectedEntryIdentifierMaxCharacters
            ) else {
                continue
            }
            guard seen.insert(boundedIdentifier).inserted else {
                continue
            }
            boundedIdentifiers.append(boundedIdentifier)
            if boundedIdentifiers.count == pinnedEntryIdentifierLimit {
                break
            }
        }

        return boundedIdentifiers
    }
}

struct CompassProjectStorageResolver: Equatable {
    var repoURL: URL
    var activeStorage: KnownProjectActiveStorage
    var applicationSupportRoots: KnownProjectStore.ApplicationSupportRoots

    init(
        repoURL: URL,
        activeStorage: KnownProjectActiveStorage = .repoLocal,
        applicationSupportRoots: KnownProjectStore.ApplicationSupportRoots = KnownProjectStore.productionApplicationSupportRoots()
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
    var cinematicInfluenceSettings: CinematicInfluenceSettings
    var nativeFeedbackMode: NativeFeedbackMode
    var developSandbox: DevelopSandboxPreference
    var cinematicRunRecapShareArtifactLibraryContext: CinematicRunRecapShareArtifactLibraryContext

    enum CodingKeys: String, CodingKey {
        case id
        case path
        case activeStorage
        case addedAt
        case lastOpenedAt
        case cinematicInfluenceSettings
        case nativeFeedbackMode
        // Legacy on-disk key from the pre-Codex-removal schema. Reads only —
        // we no longer write it, but its value seeds `developSandbox` when
        // the new key is absent so an existing user's "Shared VM" choice
        // carries forward.
        case legacyAgentExecutionEnvironmentPreference = "codexExecutionEnvironmentPreference"
        case developSandbox
        case cinematicRunRecapShareArtifactLibraryContext
    }

    init(
        id: UUID,
        path: String,
        activeStorage: KnownProjectActiveStorage = .repoLocal,
        addedAt: Double,
        lastOpenedAt: Double,
        cinematicInfluenceSettings: CinematicInfluenceSettings = CinematicInfluenceSettings(),
        nativeFeedbackMode: NativeFeedbackMode = .notifications,
        developSandbox: DevelopSandboxPreference = .host,
        cinematicRunRecapShareArtifactLibraryContext: CinematicRunRecapShareArtifactLibraryContext = .empty
    ) {
        self.id = id
        self.path = path
        self.activeStorage = activeStorage
        self.addedAt = addedAt
        self.lastOpenedAt = lastOpenedAt
        self.cinematicInfluenceSettings = cinematicInfluenceSettings
        self.nativeFeedbackMode = nativeFeedbackMode
        self.developSandbox = developSandbox
        self.cinematicRunRecapShareArtifactLibraryContext = cinematicRunRecapShareArtifactLibraryContext
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        path = try container.decode(String.self, forKey: .path)
        activeStorage = try container.decodeIfPresent(
            KnownProjectActiveStorage.self,
            forKey: .activeStorage
        ) ?? .repoLocal
        addedAt = try container.decode(Double.self, forKey: .addedAt)
        lastOpenedAt = try container.decode(Double.self, forKey: .lastOpenedAt)
        cinematicInfluenceSettings = try container.decodeIfPresent(
            CinematicInfluenceSettings.self,
            forKey: .cinematicInfluenceSettings
        ) ?? CinematicInfluenceSettings()
        nativeFeedbackMode = try container.decodeIfPresent(
            NativeFeedbackMode.self,
            forKey: .nativeFeedbackMode
        ) ?? .notifications
        if let stored = try container.decodeIfPresent(
            DevelopSandboxPreference.self,
            forKey: .developSandbox
        ) {
            developSandbox = stored
        } else if let legacy = try container.decodeIfPresent(
            AgentExecutionEnvironmentPreference.self,
            forKey: .legacyAgentExecutionEnvironmentPreference
        ) {
            developSandbox = legacy.developSandbox
        } else {
            developSandbox = .host
        }
        cinematicRunRecapShareArtifactLibraryContext = try container.decodeIfPresent(
            CinematicRunRecapShareArtifactLibraryContext.self,
            forKey: .cinematicRunRecapShareArtifactLibraryContext
        ) ?? .empty
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(path, forKey: .path)
        try container.encode(activeStorage, forKey: .activeStorage)
        try container.encode(addedAt, forKey: .addedAt)
        try container.encode(lastOpenedAt, forKey: .lastOpenedAt)
        try container.encode(cinematicInfluenceSettings, forKey: .cinematicInfluenceSettings)
        try container.encode(nativeFeedbackMode, forKey: .nativeFeedbackMode)
        try container.encode(developSandbox, forKey: .developSandbox)
        try container.encode(
            cinematicRunRecapShareArtifactLibraryContext,
            forKey: .cinematicRunRecapShareArtifactLibraryContext
        )
    }
}

private extension CompassProject {
    convenience init(record: KnownProjectRecord) {
        self.init(
            id: record.id,
            repoURL: URL(fileURLWithPath: record.path).standardizedFileURL,
            activeStorage: record.activeStorage,
            addedAt: Date(timeIntervalSince1970: record.addedAt),
            lastOpenedAt: Date(timeIntervalSince1970: record.lastOpenedAt),
            cinematicInfluenceSettings: record.cinematicInfluenceSettings,
            nativeFeedbackMode: record.nativeFeedbackMode,
            developSandbox: record.developSandbox,
            cinematicRunRecapShareArtifactLibraryContext: record.cinematicRunRecapShareArtifactLibraryContext
        )
    }

    var record: KnownProjectRecord {
        KnownProjectRecord(
            id: id,
            path: repoURL.path,
            activeStorage: activeStorage,
            addedAt: addedAt.timeIntervalSince1970,
            lastOpenedAt: lastOpenedAt.timeIntervalSince1970,
            cinematicInfluenceSettings: cinematicInfluenceSettings,
            nativeFeedbackMode: nativeFeedbackMode,
            developSandbox: developSandbox,
            cinematicRunRecapShareArtifactLibraryContext: cinematicRunRecapShareArtifactLibraryContext
        )
    }

    func logProjectSelected() {
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
        let sourceURL = FileManager.default.fileExists(atPath: projectsURL(in: roots.current).path)
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

    static func save(_ records: [KnownProjectRecord], applicationSupportRoots roots: ApplicationSupportRoots) throws {
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
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support", directoryHint: .isDirectory)
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
        case let .notGitRepository(path):
            return "\(path) is not inside a Git repository."
        case let .gitCommandFailed(message):
            return message
        case let .internalInvariant(message):
            return message
        case let .rejectedPlan(message):
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
