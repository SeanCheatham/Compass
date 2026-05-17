import AppKit
import Foundation

@MainActor
final class CompassProject: ObservableObject, Identifiable {
    let id: UUID
    @Published var repoURL: URL
    @Published var state = PlanState.empty
    @Published var drafts = ""
    @Published var draftEntry = ""
    @Published var lessons = ""
    @Published var vision = ""
    @Published var sessions: [SessionRecord] = []
    @Published var languageProfile = RepositoryLanguageProfile.empty
    @Published var activityProfile = RepositoryActivityProfile.empty
    @Published var cinematicInfluenceSettings: CinematicInfluenceSettings
    @Published var nativeFeedbackMode: NativeFeedbackMode
    @Published var liveLog: [LiveLine] = []
    @Published var phase: LoopPhase = .idle {
        didSet {
            guard oldValue != phase else { return }
            scheduleCinematicBriefingRefresh(reason: .phaseChanged)
        }
    }
    @Published var cinematicBriefing = CinematicBriefing.placeholder
    @Published var isRunning = false
    @Published var isAutoPlaying = false
    @Published var isPaused = false
    @Published var pauseMode: PauseMode = .immediate
    @Published var errorMessage: String?

    var addedAt: Date
    var lastOpenedAt: Date

    private var workspace: CompassWorkspace? {
        guard FileManager.default.fileExists(atPath: repoURL.path),
              let repoURL = CompassWorkspace.discover(from: repoURL) else { return nil }
        return CompassWorkspace(repoURL: repoURL)
    }

    private var executor: CodexExecutor?
    private var stopRequested = false
    private var cinematicBriefingTask: Task<Void, Never>?
    private var lastCinematicBriefingInput: CinematicBriefingInput?
    private var lastCinematicBriefingGeneratedAt = Date.distantPast
    private let maxDevelopAttempts = 3
    private let reflectSessionWindow = 10

    init(
        id: UUID = UUID(),
        repoURL: URL,
        addedAt: Date = Date(),
        lastOpenedAt: Date = Date(),
        cinematicInfluenceSettings: CinematicInfluenceSettings = CinematicInfluenceSettings(),
        nativeFeedbackMode: NativeFeedbackMode = .notifications
    ) {
        self.id = id
        self.repoURL = repoURL.standardizedFileURL
        self.addedAt = addedAt
        self.lastOpenedAt = lastOpenedAt
        self.cinematicInfluenceSettings = cinematicInfluenceSettings
        self.nativeFeedbackMode = nativeFeedbackMode
        cinematicBriefing = CinematicBriefingService.deterministicBriefing(
            for: CinematicBriefingInput(
                repoName: repoURL.lastPathComponent,
                currentPhase: LoopPhase.idle.rawValue,
                immediatePlanTitle: "No immediate plan",
                completedCount: 0,
                latestEvent: nil
            )
        )
    }

    deinit {
        cinematicBriefingTask?.cancel()
    }
}

private enum CinematicBriefingRefreshReason {
    case projectRefresh
    case planAccepted
    case phaseChanged
    case liveEvent
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
        CompassWorkspace(repoURL: repoURL).compassURL.path
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
        guard let workspace else {
            state = .empty
            drafts = ""
            lessons = ""
            vision = ""
            sessions = []
            languageProfile = .empty
            activityProfile = .empty
            scheduleCinematicBriefingRefresh(reason: .projectRefresh)
            return
        }
        do {
            languageProfile = RepositoryLanguageProfileService.scan(repoURL: workspace.repoURL)

            if !FileManager.default.fileExists(atPath: workspace.compassURL.path) {
                state = .empty
                drafts = ""
                lessons = ""
                vision = ""
                sessions = []
                activityProfile = .empty
                scheduleCinematicBriefingRefresh(reason: .projectRefresh)
                return
            }

            state = try workspace.readState()
            drafts = workspace.readDrafts()
            lessons = workspace.readLessons()
            vision = workspace.readVision()
            sessions = workspace.readSessions()
            activityProfile = await RepositoryActivityProfileService.scan(repoURL: workspace.repoURL)
            scheduleCinematicBriefingRefresh(reason: .projectRefresh)
        } catch {
            fail(error)
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
        do {
            guard let workspace else {
                fail(AppModelError.noRepositorySelected)
                return
            }
            try await initializeIfNeeded(workspace)
            try workspace.appendDraft(draftEntry)
            draftEntry = ""
            drafts = workspace.readDrafts()
            log("Draft queued.", level: .success)
        } catch {
            fail(error)
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
                    prompt: prompt
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
                    feedback(.paused)
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
                        prompt: prompt
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
                    workingDirectory: devWorkspace.repoURL
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

    private func resolveWorkspaceForRun() async throws -> CompassWorkspace {
        let resolvedURL = try await resolveGitRoot(from: repoURL)
        if repoURL.path != resolvedURL.path {
            repoURL = resolvedURL
            log("Resolved repo root: \(repoURL.path)", level: .info)
        }

        let workspace = CompassWorkspace(repoURL: repoURL)
        log("Using Compass workspace: \(workspace.compassURL.path)", level: .info)
        return workspace
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
                prompt: prompt
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
        if next.completed.count < current.completed.count {
            throw AppModelError.rejectedPlan(
                "Plan tried to shrink completed history from \(current.completed.count) entries to \(next.completed.count). Refusing to overwrite state.json."
            )
        }

        if !current.midTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            next.midTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            next.completed.count == current.completed.count {
            throw AppModelError.rejectedPlan(
                "Plan tried to clear a non-empty midTerm queue without recording a completion. Refusing to overwrite state.json."
            )
        }

        guard let immediate = next.immediate else { return }
        let verify = immediate.verify.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rejectedVerifyCommands = Set([
            "true",
            "not-running-tests",
            "not running tests",
            "none",
            "n/a"
        ])
        if rejectedVerifyCommands.contains(verify) {
            throw AppModelError.rejectedPlan(
                "Plan returned placeholder verify command `\(immediate.verify)`. Refusing to overwrite state.json."
            )
        }
    }

    private func runPostChecks(
        next: PlanNext,
        summary: DevelopSummary,
        workingDirectory: URL
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
            log("Post-check: running verify command `\(next.verify)` (timeout \(timeoutMs)ms).", level: .info)
            let verify = try await ProcessRunner.runShell(
                next.verify,
                workingDirectory: workingDirectory,
                timeout: TimeInterval(timeoutMs) / 1000
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

    private func feedback(_ milestone: NativeFeedbackMilestone) {
        NativeFeedbackService.shared.emit(
            milestone,
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
        let input = makeCinematicBriefingInput()
        guard input != lastCinematicBriefingInput else { return }
        lastCinematicBriefingInput = input

        cinematicBriefingTask?.cancel()
        let delay = cinematicBriefingDelay(for: reason)
        cinematicBriefingTask = Task { @MainActor [weak self, input, delay] in
            if delay > 0 {
                let nanoseconds = UInt64(delay * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
            }

            guard !Task.isCancelled, let self else { return }
            lastCinematicBriefingGeneratedAt = Date()
            let briefing = await CinematicBriefingService.makeBriefing(input: input)
            guard !Task.isCancelled else { return }
            cinematicBriefing = briefing
        }
    }

    private func makeCinematicBriefingInput() -> CinematicBriefingInput {
        CinematicBriefingInput(
            repoName: displayName,
            currentPhase: (isPaused ? LoopPhase.paused : phase).rawValue,
            immediatePlanTitle: immediateTitle,
            completedCount: state.completed.count,
            latestEvent: liveLog.last.map(CinematicBriefingEvent.init(line:))
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
        NativeFeedbackService.shared.prepare()
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
            try KnownProjectStore.save(projects.map(\.record))
        } catch {
            fail(error)
        }
    }

    private func fail(_ error: Error) {
        errorMessage = error.localizedDescription
    }
}

private struct KnownProjectRecord: Codable, Identifiable, Equatable {
    var id: UUID
    var path: String
    var addedAt: Double
    var lastOpenedAt: Double
    var cinematicInfluenceSettings: CinematicInfluenceSettings
    var nativeFeedbackMode: NativeFeedbackMode

    enum CodingKeys: String, CodingKey {
        case id
        case path
        case addedAt
        case lastOpenedAt
        case cinematicInfluenceSettings
        case nativeFeedbackMode
    }

    init(
        id: UUID,
        path: String,
        addedAt: Double,
        lastOpenedAt: Double,
        cinematicInfluenceSettings: CinematicInfluenceSettings = CinematicInfluenceSettings(),
        nativeFeedbackMode: NativeFeedbackMode = .notifications
    ) {
        self.id = id
        self.path = path
        self.addedAt = addedAt
        self.lastOpenedAt = lastOpenedAt
        self.cinematicInfluenceSettings = cinematicInfluenceSettings
        self.nativeFeedbackMode = nativeFeedbackMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        path = try container.decode(String.self, forKey: .path)
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
    }
}

private extension CompassProject {
    convenience init(record: KnownProjectRecord) {
        self.init(
            id: record.id,
            repoURL: URL(fileURLWithPath: record.path).standardizedFileURL,
            addedAt: Date(timeIntervalSince1970: record.addedAt),
            lastOpenedAt: Date(timeIntervalSince1970: record.lastOpenedAt),
            cinematicInfluenceSettings: record.cinematicInfluenceSettings,
            nativeFeedbackMode: record.nativeFeedbackMode
        )
    }

    var record: KnownProjectRecord {
        KnownProjectRecord(
            id: id,
            path: repoURL.path,
            addedAt: addedAt.timeIntervalSince1970,
            lastOpenedAt: lastOpenedAt.timeIntervalSince1970,
            cinematicInfluenceSettings: cinematicInfluenceSettings,
            nativeFeedbackMode: nativeFeedbackMode
        )
    }

    func logProjectSelected() {
        log("Selected repo: \(repoURL.path)", level: .success)
        log("Compass workspace: \(compassPath)", level: .info)
    }
}

private enum KnownProjectStore {
    static func load() -> [KnownProjectRecord] {
        let sourceURL = FileManager.default.fileExists(atPath: projectsURL.path)
            ? projectsURL
            : legacyProjectsURL
        guard let data = try? Data(contentsOf: sourceURL), !data.isEmpty else {
            return []
        }
        return (try? JSONDecoder().decode([KnownProjectRecord].self, from: data)) ?? []
    }

    static func save(_ records: [KnownProjectRecord]) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(records)
        try data.write(to: projectsURL, options: .atomic)
    }

    private static var projectsURL: URL {
        directoryURL.appending(path: "projects.json")
    }

    private static var legacyProjectsURL: URL {
        legacyDirectoryURL.appending(path: "projects.json")
    }

    private static var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support", directoryHint: .isDirectory)
        return base.appending(path: "Compass", directoryHint: .isDirectory)
    }

    private static var legacyDirectoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support", directoryHint: .isDirectory)
        return base.appending(path: "CompassNative", directoryHint: .isDirectory)
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
