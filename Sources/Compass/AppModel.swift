import AppKit
import Foundation

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
                "Git/Codex repo: \(boundedPath(plan.repoURL.path, limit: 180))",
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
        detail: "Switch a prepared Application Support candidate into active Compass state while keeping repoURL as the Git/Codex workspace.",
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
            detail: "Stop the active Codex run before preparing Application Support candidate storage.",
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
    @Published var codexExecutionEnvironmentPreference: CodexExecutionEnvironmentPreference
    @Published var devcontainerProvisioningState = CompassProjectDevcontainerProvisioningState.idle
    @Published var devcontainerProvisioningConfirmation: CodexDevcontainerProvisioningConfirmation?
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

    private var executor: CodexExecutor?
    private var stopRequested = false
    private var cinematicBriefingTask: Task<Void, Never>?
    private var cinematicNativeFeedbackCueExpiryTask: Task<Void, Never>?
    private var lastCinematicRefreshInput: CinematicRefreshInput?
    private var lastCinematicBriefingGeneratedAt = Date.distantPast
    private let storageMigrationAction: CompassWorkspaceStorageMigrationAction
    private let devcontainerProvisioningAction: CodexDevcontainerProvisioningAction
    private let containerToolResolver: (String) -> String?
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
        codexExecutionEnvironmentPreference: CodexExecutionEnvironmentPreference = .nativeMacOS,
        cinematicRunRecapShareArtifactLibraryContext: CinematicRunRecapShareArtifactLibraryContext = .empty,
        storageApplicationSupportRoots: KnownProjectStore.ApplicationSupportRoots = KnownProjectStore.productionApplicationSupportRoots(),
        storageMigrationAction: @escaping CompassWorkspaceStorageMigrationAction = { plan in
            try CompassWorkspaceStorageMigrator().migrate(plan: plan)
        },
        devcontainerProvisioningAction: @escaping CodexDevcontainerProvisioningAction = { plan in
            try CodexDevcontainerProvisioner.write(plan: plan)
        },
        containerToolResolver: @escaping (String) -> String? = CodexExecutionLaunchPlan.defaultContainerToolResolver,
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
        self.codexExecutionEnvironmentPreference = codexExecutionEnvironmentPreference
        self.cinematicRunRecapShareArtifactLibraryContext = cinematicRunRecapShareArtifactLibraryContext
        self.storageApplicationSupportRoots = storageApplicationSupportRoots
        self.storageMigrationAction = storageMigrationAction
        self.devcontainerProvisioningAction = devcontainerProvisioningAction
        self.containerToolResolver = containerToolResolver
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

private enum CodexBinaryLocator {
    static func defaultBinary() -> String {
        if let configured = ProcessInfo.processInfo.environment["COMPASS_CODEX_BIN"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !configured.isEmpty {
            return configured
        }

        let candidates = [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "codex"
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

    var codexExecutionEnvironment: CodexExecutionEnvironment {
        CodexExecutionEnvironment.discover(
            repoURL: repoURL,
            preference: codexExecutionEnvironmentPreference
        )
    }

    var runtimeDiagnosticsMenu: CodexExecutionEnvironmentMenu {
        let environment = codexExecutionEnvironment
        let launchPlan = codexLaunchPlan(for: repoURL)
        let mutationTestingPlan = CodexMutationTestingPlan(
            state: state,
            languageProfile: languageProfile,
            launchPlan: launchPlan
        )
        let mutationRecoveryDescriptor = MutationTestingRecoveryDescriptor.runtimeDescriptor(
            sessions: sessions,
            readiness: mutationTestingPlan
        )
        return CodexExecutionEnvironmentMenu(
            environment: environment,
            provisioningPlan: devcontainerProvisioningPlan(),
            launchPlan: launchPlan,
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

    func devcontainerProvisioningPlan() -> CodexDevcontainerProvisioningPlan {
        CodexDevcontainerProvisioningPlan.plan(
            repoURL: repoURL,
            languageProfile: languageProfile
        )
    }

    func prepareDevcontainerProvisioningConfirmation() {
        guard isIdleForDevcontainerProvisioning else {
            devcontainerProvisioningConfirmation = nil
            devcontainerProvisioningState = .blockedWhileBusy()
            errorMessage = devcontainerProvisioningState.detail
            log(devcontainerProvisioningState.detail, level: .warning)
            return
        }

        let plan = devcontainerProvisioningPlan()
        guard plan.isAvailable else {
            devcontainerProvisioningConfirmation = nil
            devcontainerProvisioningState = .blocked(plan: plan)
            errorMessage = devcontainerProvisioningState.detail
            log("Dev Container creation blocked: \(devcontainerProvisioningState.detail)", level: .warning)
            return
        }

        let confirmation = CodexDevcontainerProvisioningConfirmation(plan: plan)
        devcontainerProvisioningConfirmation = confirmation
        devcontainerProvisioningState = .awaitingConfirmation(confirmation)
        errorMessage = nil
    }

    func cancelDevcontainerProvisioningConfirmation() {
        devcontainerProvisioningConfirmation = nil
        if devcontainerProvisioningState.phase == .awaitingConfirmation {
            devcontainerProvisioningState = .idle
        }
    }

    func confirmDevcontainerProvisioning(
        _ confirmation: CodexDevcontainerProvisioningConfirmation,
        persistProjectRegistry: () throws -> Void
    ) async {
        devcontainerProvisioningConfirmation = nil

        guard isIdleForDevcontainerProvisioning else {
            devcontainerProvisioningState = .blockedWhileBusy()
            errorMessage = devcontainerProvisioningState.detail
            log(devcontainerProvisioningState.detail, level: .warning)
            return
        }

        let currentPlan = devcontainerProvisioningPlan()
        guard currentPlan.isAvailable else {
            devcontainerProvisioningState = .blocked(plan: currentPlan)
            errorMessage = devcontainerProvisioningState.detail
            log("Dev Container creation blocked: \(devcontainerProvisioningState.detail)", level: .warning)
            return
        }

        let plan = confirmation.plan
        guard currentPlan.configURL == plan.configURL else {
            let error = CodexDevcontainerProvisioningError.unavailable(
                "The confirmed repository no longer matches the selected project."
            )
            devcontainerProvisioningState = .failed(error)
            errorMessage = devcontainerProvisioningState.detail
            log(devcontainerProvisioningState.detail, level: .error)
            return
        }

        devcontainerProvisioningState = .running(plan: plan)
        errorMessage = nil
        log("Dev Container creation: writing \(plan.configURL.path).", level: .info)
        await Task.yield()

        let previousPreference = codexExecutionEnvironmentPreference
        do {
            let result = try devcontainerProvisioningAction(plan)
            let parseOutcome = CodexExecutionLaunchPlan.parseDevcontainerImageConfig(repoURL: repoURL)
            guard case .ready = parseOutcome else {
                throw CodexDevcontainerProvisioningError.writtenConfigNotReady(
                    devcontainerVerificationReason(parseOutcome)
                )
            }

            codexExecutionEnvironmentPreference = .devcontainerPreferred
            do {
                try persistProjectRegistry()
            } catch {
                codexExecutionEnvironmentPreference = previousPreference
                try? persistProjectRegistry()
                throw error
            }

            await refresh()
            devcontainerProvisioningState = .succeeded(result)
            errorMessage = nil
            log(devcontainerProvisioningState.detail, level: .success)
        } catch {
            devcontainerProvisioningState = .failed(error)
            errorMessage = devcontainerProvisioningState.detail
            log(devcontainerProvisioningState.detail, level: .error)
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

    func play(codexBinary: String, modelOverride: String) async {
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
                codexBinary: codexBinary,
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
                codexBinary: codexBinary,
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

    func runPlanOnly(codexBinary: String, modelOverride: String) async {
        guard !isRunning else { return }
        isAutoPlaying = false
        await runPlanPass(
            continueToDevelop: false,
            codexBinary: codexBinary,
            modelOverride: modelOverride
        )
    }

    func runDevelopOnly(codexBinary: String, modelOverride: String) async {
        guard !isRunning else { return }
        isAutoPlaying = false
        isPaused = false
        await runDevelopPass(
            existingSessionIndex: nil,
            codexBinary: codexBinary,
            modelOverride: modelOverride
        )
    }

    func runMutationTesting() async {
        let initialLaunchPlan = codexLaunchPlan(for: repoURL)
        let initialReadiness = CodexMutationTestingPlan(
            state: state,
            languageProfile: languageProfile,
            launchPlan: initialLaunchPlan
        )
        let initialAction = CodexMutationTestingMenuAction(
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

        let launchPlan = codexLaunchPlan(for: workspace.repoURL)
        let readiness = CodexMutationTestingPlan(
            state: state,
            languageProfile: languageProfile,
            launchPlan: launchPlan
        )
        let action = CodexMutationTestingMenuAction(
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
            let safeError = CodexMutationTestingMetadataSanitizer.sanitizedOutputTail(
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
        codexBinary: String,
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
                codexBinary: codexBinary,
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

            let launchPlan = codexLaunchPlan(for: workspace.repoURL)
            logExecutionEnvironmentPreflight(
                phase: "Plan",
                nativeExecutionURL: workspace.repoURL,
                launchPlan: launchPlan,
                sessionIndex: sessionIndex
            )
            log("Plan: launching codex exec.", level: .info)
            let codex = CodexExecutor()
            executor = codex
            let planResult = try await codex.run(
                CodexRunConfiguration(
                    codexBinary: codexBinary,
                    repoURL: workspace.repoURL,
                    sandbox: "read-only",
                    model: modelForPhase(envKey: "COMPASS_CODEX_PLAN_MODEL", modelOverride: modelOverride),
                    schema: Prompts.planSchema,
                    prompt: prompt,
                    launchPlan: launchPlan
                ),
                decode: PlanRunResult.self,
                onEvent: { [weak self] event in
                    Task { @MainActor in self?.log(event) }
                }
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
                    codexBinary: codexBinary,
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
        codexBinary: String,
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

        var devWorkspace: DevRunWorkspace?
        do {
            devWorkspace = try await createDevWorkspace(
                mainRepoURL: workspace.repoURL,
                beforeSha: beforeSha
            )
            guard let devWorkspace else { throw AppModelError.internalInvariant("Develop workspace was not created.") }

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
                    priorIssues: priorIssues,
                    sandboxed: devWorkspace.sandboxed
                )

                let launchPlan = codexLaunchPlan(for: devWorkspace.repoURL)
                logExecutionEnvironmentPreflight(
                    phase: "Develop",
                    nativeExecutionURL: devWorkspace.repoURL,
                    launchPlan: launchPlan,
                    sessionIndex: sessionIndex,
                    attempt: attempt
                )
                log("Develop: launching codex exec (attempt \(attempt)/\(maxDevelopAttempts)).", level: .info)
                let codex = CodexExecutor()
                executor = codex
                let summary = try await codex.run(
                    CodexRunConfiguration(
                        codexBinary: codexBinary,
                        repoURL: devWorkspace.repoURL,
                        sandbox: "danger-full-access",
                        model: modelForPhase(envKey: "COMPASS_CODEX_DEV_MODEL", modelOverride: modelOverride),
                        schema: Prompts.developSchema,
                        prompt: prompt,
                        launchPlan: launchPlan
                    ),
                    decode: DevelopSummary.self,
                    onEvent: { [weak self] event in
                        Task { @MainActor in self?.log(event) }
                    }
                )

                guard sessions.indices.contains(sessionIndex) else {
                    throw AppModelError.internalInvariant("Develop session disappeared during Codex run.")
                }
                sessions[sessionIndex].feedback = summary.feedback
                appendSessionNote(summary.summary, to: sessionIndex)

                let post = try await runPostChecks(
                    next: next,
                    summary: summary,
                    workingDirectory: devWorkspace.repoURL,
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
                    if let promotionIssue = try await promoteDevWorkspace(devWorkspace, mainRepoURL: workspace.repoURL) {
                        finalIssues = [promotionIssue]
                        succeeded = false
                    } else {
                        do {
                            logLessonEdits(try workspace.applyLessonEdits(summary.lessonEdits))
                        } catch {
                            let note = "Lesson edits were not applied: \(error.localizedDescription)"
                            appendSessionNote(note, to: sessionIndex)
                            log(note, level: .error)
                        }
                        succeeded = true
                    }
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

        if let devWorkspace {
            await cleanupDevWorkspace(devWorkspace, mainRepoURL: workspace.repoURL)
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

    private var isIdleForDevcontainerProvisioning: Bool {
        !isRunning && !isAutoPlaying && !isPaused
    }

    private var isIdleForMutationTesting: Bool {
        !isRunning
            && !isAutoPlaying
            && !isPaused
            && !devcontainerProvisioningState.isRunning
            && !storageMigrationState.isRunning
            && !activeStorageActivationState.isRunning
    }

    private var mutationTestingExecutionState: CodexMutationTestingMenuAction.ExecutionState {
        if isPaused { return .paused }
        if !isIdleForMutationTesting { return .running }
        return .idle
    }

    private func devcontainerVerificationReason(
        _ outcome: CodexExecutionLaunchPlan.ParseOutcome
    ) -> String {
        switch outcome {
        case .missing:
            return "No .devcontainer/devcontainer.json was found after writing."
        case let .malformed(_, reason):
            return reason
        case let .unsupported(_, reason):
            return reason
        case .ready:
            return "The generated config is ready."
        }
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

    private func codexLaunchPlan(for nativeExecutionURL: URL) -> CodexExecutionLaunchPlan {
        CodexExecutionLaunchPlan.plan(
            repoURL: nativeExecutionURL,
            preference: codexExecutionEnvironmentPreference,
            containerToolResolver: containerToolResolver
        )
    }

    private func logExecutionEnvironmentPreflight(
        phase: String,
        nativeExecutionURL: URL,
        launchPlan: CodexExecutionLaunchPlan? = nil,
        sessionIndex: Int? = nil,
        attempt: Int? = nil
    ) {
        let environment = CodexExecutionEnvironment.discover(
            repoURL: nativeExecutionURL,
            preference: codexExecutionEnvironmentPreference
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
                nativeExecutionURL: nativeExecutionURL,
                launchPlan: effectiveLaunchPlan,
                sessionIndex: sessionIndex
            )
        }
        let presentation = environment.presentation
        let detail = [presentation.status, presentation.detail, effectiveLaunchPlan.routeDetail()]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        log(detail, level: presentation.isWarning || effectiveLaunchPlan.fallbackReason != nil ? .warning : .info)
    }

    private func recordSessionExecutionEnvironmentSnapshot(
        phase: String,
        attempt: Int?,
        nativeExecutionURL: URL,
        launchPlan: CodexExecutionLaunchPlan,
        sessionIndex: Int
    ) {
        guard sessions.indices.contains(sessionIndex) else { return }
        let provisioningPlan = CodexDevcontainerProvisioningPlan.plan(
            repoURL: nativeExecutionURL,
            languageProfile: languageProfile
        )
        let snapshot = SessionExecutionEnvironmentSnapshot(
            phase: phase,
            attempt: attempt,
            launchPlan: launchPlan,
            provisioningPlan: provisioningPlan
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
        codexBinary: String,
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

        let launchPlan = codexLaunchPlan(for: workspace.repoURL)
        logExecutionEnvironmentPreflight(
            phase: "Reflect",
            nativeExecutionURL: workspace.repoURL,
            launchPlan: launchPlan,
            sessionIndex: sessionIndex
        )
        log("Reflect: launching codex exec.", level: .info)
        let codex = CodexExecutor()
        executor = codex
        let result = try await codex.run(
            CodexRunConfiguration(
                codexBinary: codexBinary,
                repoURL: workspace.repoURL,
                sandbox: "read-only",
                model: modelForPhase(envKey: "COMPASS_CODEX_REFLECT_MODEL", modelOverride: modelOverride),
                schema: Prompts.reflectSchema,
                prompt: prompt,
                launchPlan: launchPlan
            ),
            decode: ReflectSummary.self,
            onEvent: { [weak self] event in
                Task { @MainActor in self?.log(event) }
            }
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

    private func modelForPhase(envKey: String, modelOverride: String) -> String? {
        let override = modelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !override.isEmpty { return override }

        let env = ProcessInfo.processInfo.environment[envKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return env?.isEmpty == false ? env : nil
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
        launchPlan: CodexExecutionLaunchPlan,
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
            let verify = try await ProcessRunner.runShell(
                next.verify,
                workingDirectory: workingDirectory,
                timeout: TimeInterval(timeoutMs) / 1000,
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

    private func createDevWorkspace(mainRepoURL: URL, beforeSha: String?) async throws -> DevRunWorkspace {
        guard let beforeSha, !beforeSha.isEmpty else {
            log("Develop sandbox: using main worktree because this repo has no HEAD yet.", level: .info)
            return DevRunWorkspace(
                repoURL: mainRepoURL,
                sandboxed: false,
                branchName: nil,
                parentURL: nil,
                worktreeURL: nil
            )
        }

        let parentURL = FileManager.default.temporaryDirectory
            .appending(path: "compass-dev-\(UUID().uuidString)", directoryHint: .isDirectory)
        let worktreeURL = parentURL.appending(path: "worktree", directoryHint: .isDirectory)
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let suffix = UUID().uuidString.prefix(8).lowercased()
        let branchName = "compass/dev-\(ProcessInfo.processInfo.processIdentifier)-\(timestamp)-\(suffix)"

        try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)
        do {
            try await runGitOrThrow(
                ["worktree", "add", "-b", branchName, worktreeURL.path, beforeSha],
                in: mainRepoURL,
                failurePrefix: "Failed to create Develop worktree"
            )
        } catch {
            try? FileManager.default.removeItem(at: parentURL)
            throw error
        }

        log("Develop sandbox: \(branchName) at \(worktreeURL.path)", level: .info)
        return DevRunWorkspace(
            repoURL: worktreeURL,
            sandboxed: true,
            branchName: branchName,
            parentURL: parentURL,
            worktreeURL: worktreeURL
        )
    }

    private func promoteDevWorkspace(_ devWorkspace: DevRunWorkspace, mainRepoURL: URL) async throws -> String? {
        guard devWorkspace.sandboxed, let branchName = devWorkspace.branchName else { return nil }
        guard let afterSha = await gitCurrentSha(at: devWorkspace.repoURL) else {
            return "Develop sandbox produced no commit to promote."
        }

        do {
            try await runGitOrThrow(
                ["merge", "--ff-only", branchName],
                in: mainRepoURL,
                failurePrefix: "Failed to promote Develop sandbox branch \(branchName)"
            )
            log("Develop sandbox: promoted \(String(afterSha.prefix(12))) to the main worktree.", level: .success)
            feedback(.commitsPromoted)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func cleanupDevWorkspace(_ devWorkspace: DevRunWorkspace, mainRepoURL: URL) async {
        guard devWorkspace.sandboxed else { return }

        if let worktreeURL = devWorkspace.worktreeURL {
            do {
                try await runGitOrThrow(
                    ["worktree", "remove", "--force", worktreeURL.path],
                    in: mainRepoURL,
                    failurePrefix: "Failed to remove Develop worktree"
                )
            } catch {
                log(error.localizedDescription, level: .error)
            }
        }

        if let branchName = devWorkspace.branchName {
            do {
                try await runGitOrThrow(
                    ["branch", "-D", branchName],
                    in: mainRepoURL,
                    failurePrefix: "Failed to delete Develop branch \(branchName)"
                )
            } catch {
                log(error.localizedDescription, level: .error)
            }
        }

        if let parentURL = devWorkspace.parentURL {
            try? FileManager.default.removeItem(at: parentURL)
        }
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

@MainActor
final class AppModel: ObservableObject {
    @Published var projects: [CompassProject] = []
    @Published var selectedProjectID: UUID?
    @Published var codexBinary = CodexBinaryLocator.defaultBinary()
    @Published var modelOverride = ""
    @Published var errorMessage: String?

    var selectedProject: CompassProject? {
        projects.first { $0.id == selectedProjectID }
    }

    func bootstrap() async {
        projects = KnownProjectStore.load().map(CompassProject.init(record:))
        selectedProjectID = projects.sorted { $0.lastOpenedAt > $1.lastOpenedAt }.first?.id

        if projects.isEmpty {
            errorMessage = nil
        } else {
            for project in projects {
                await project.refresh()
            }
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
        }
        saveProjects()
    }

    func playSelectedProject() async {
        guard let selectedProject else { return }
        await selectedProject.play(codexBinary: codexBinary, modelOverride: modelOverride)
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
    var codexExecutionEnvironmentPreference: CodexExecutionEnvironmentPreference
    var cinematicRunRecapShareArtifactLibraryContext: CinematicRunRecapShareArtifactLibraryContext

    enum CodingKeys: String, CodingKey {
        case id
        case path
        case activeStorage
        case addedAt
        case lastOpenedAt
        case cinematicInfluenceSettings
        case nativeFeedbackMode
        case codexExecutionEnvironmentPreference
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
        codexExecutionEnvironmentPreference: CodexExecutionEnvironmentPreference = .nativeMacOS,
        cinematicRunRecapShareArtifactLibraryContext: CinematicRunRecapShareArtifactLibraryContext = .empty
    ) {
        self.id = id
        self.path = path
        self.activeStorage = activeStorage
        self.addedAt = addedAt
        self.lastOpenedAt = lastOpenedAt
        self.cinematicInfluenceSettings = cinematicInfluenceSettings
        self.nativeFeedbackMode = nativeFeedbackMode
        self.codexExecutionEnvironmentPreference = codexExecutionEnvironmentPreference
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
        codexExecutionEnvironmentPreference = try container.decodeIfPresent(
            CodexExecutionEnvironmentPreference.self,
            forKey: .codexExecutionEnvironmentPreference
        ) ?? .nativeMacOS
        cinematicRunRecapShareArtifactLibraryContext = try container.decodeIfPresent(
            CinematicRunRecapShareArtifactLibraryContext.self,
            forKey: .cinematicRunRecapShareArtifactLibraryContext
        ) ?? .empty
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
            codexExecutionEnvironmentPreference: record.codexExecutionEnvironmentPreference,
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
            codexExecutionEnvironmentPreference: codexExecutionEnvironmentPreference,
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

private struct DevRunWorkspace {
    var repoURL: URL
    var sandboxed: Bool
    var branchName: String?
    var parentURL: URL?
    var worktreeURL: URL?
}

private struct PostCheckResult {
    var ok: Bool
    var retryIssues: [String]
    var displayIssues: [String]
    var verifyOutput: VerifyOutput?
}
