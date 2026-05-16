import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var repoPath = ""
    @Published var codexBinary = ProcessInfo.processInfo.environment["COMPASS_CODEX_BIN"] ?? "codex"
    @Published var modelOverride = ""
    @Published var state = PlanState.empty
    @Published var drafts = ""
    @Published var draftEntry = ""
    @Published var lessons = ""
    @Published var vision = ""
    @Published var sessions: [SessionRecord] = []
    @Published var activity: [ActivityLine] = []
    @Published var phase: LoopPhase = .idle
    @Published var isRunning = false
    @Published var errorMessage: String?

    private var workspace: CompassWorkspace? {
        let trimmed = repoPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let url = URL(fileURLWithPath: trimmed)
        guard CompassWorkspace.isGitRepository(url) else { return nil }
        return CompassWorkspace(repoURL: url)
    }

    private var executor: CodexExecutor?

    var hasRepository: Bool {
        workspace != nil
    }

    var immediateTitle: String {
        guard let immediate = state.immediate else { return "No immediate plan" }
        return immediate.plan
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? "Immediate plan"
    }

    func bootstrap() async {
        log("Choose a Git repository to begin.", level: .info)
    }

    func chooseRepository() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a Git repository for CompassNative"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let repoURL = CompassWorkspace.discover(from: url) else {
            fail(AppModelError.notGitRepository(url.path))
            return
        }
        repoPath = repoURL.path
        log("Selected \(repoURL.path)", level: .success)
        await refresh()
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
            return
        }
        do {
            if !FileManager.default.fileExists(atPath: workspace.compassURL.path) {
                state = .empty
                drafts = ""
                lessons = ""
                vision = ""
                sessions = []
                return
            }

            state = try workspace.readState()
            drafts = workspace.readDrafts()
            lessons = workspace.readLessons()
            vision = workspace.readVision()
            sessions = workspace.readSessions()
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
            try workspace.writeLessons(lessons)
            log("Saved lessons.", level: .success)
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
            try workspace.appendDraft(draftEntry)
            draftEntry = ""
            drafts = workspace.readDrafts()
            log("Draft queued.", level: .success)
        } catch {
            fail(error)
        }
    }

    func runIteration() async {
        guard !isRunning else { return }
        await runPlanPass(continueToDevelop: true)
    }

    func runPlanOnly() async {
        guard !isRunning else { return }
        await runPlanPass(continueToDevelop: false)
    }

    func runDevelopOnly() async {
        guard !isRunning else { return }
        await runDevelopPass(existingSessionIndex: nil)
    }

    func cancelRun() {
        executor?.cancel()
        phase = .cancelled
        isRunning = false
        log("Cancellation requested.", level: .warning)
    }

    private func runPlanPass(continueToDevelop: Bool) async {
        guard let workspace else {
            fail(AppModelError.noRepositorySelected)
            return
        }
        await initializeIfNeeded(workspace)

        isRunning = true
        phase = .planning
        errorMessage = nil
        let sessionIndex = startSession()
        var consumedDrafts = ""

        do {
            let priorFeedback = previousFeedback(excluding: sessions[sessionIndex].session)
            consumedDrafts = try workspace.snapshotAndClearDrafts()
            drafts = ""

            let prompt = try Prompts.planPrompt(
                state: workspace.readState(),
                drafts: consumedDrafts,
                feedback: priorFeedback,
                lessons: workspace.readLessons(),
                vision: workspace.readVision()
            )

            log("Plan: launching codex exec.", level: .info)
            let codex = CodexExecutor()
            executor = codex
            let nextState = try await codex.run(
                CodexRunConfiguration(
                    codexBinary: codexBinary,
                    repoURL: workspace.repoURL,
                    sandbox: "read-only",
                    model: modelOverride,
                    schema: Prompts.planSchema,
                    prompt: prompt
                ),
                decode: PlanState.self,
                onEvent: { [weak self] line in
                    Task { @MainActor in self?.log(line, level: .raw) }
                }
            )

            try workspace.writeState(nextState)
            state = nextState
            sessions[sessionIndex].plan = nextState.immediate?.plan
            sessions[sessionIndex].verify = nextState.immediate?.verify
            try persistSessions()

            if nextState.immediate == nil {
                endSession(sessionIndex, status: .skipped)
                phase = .idle
                log("Plan returned no immediate work.", level: .info)
                isRunning = false
                executor = nil
                await refresh()
                return
            }

            log("Plan selected: \(immediateTitle)", level: .success)

            if continueToDevelop {
                isRunning = false
                executor = nil
                await runDevelopPass(existingSessionIndex: sessionIndex)
            } else {
                phase = .idle
                isRunning = false
                executor = nil
            }
        } catch {
            if !consumedDrafts.isEmpty {
                let current = workspace.readDrafts()
                try? workspace.writeDrafts([consumedDrafts, current].filter { !$0.isEmpty }.joined(separator: "\n"))
            }
            sessions[sessionIndex].notes.append(error.localizedDescription)
            endSession(sessionIndex, status: .failed)
            phase = .failed
            isRunning = false
            executor = nil
            fail(error)
        }

        await refresh()
    }

    private func runDevelopPass(existingSessionIndex: Int?) async {
        guard let workspace else {
            fail(AppModelError.noRepositorySelected)
            return
        }
        await initializeIfNeeded(workspace)

        guard let next = state.immediate else {
            log("No immediate plan to develop.", level: .warning)
            return
        }

        isRunning = true
        phase = .developing
        errorMessage = nil
        let sessionIndex = existingSessionIndex ?? startSession()
        sessions[sessionIndex].status = .developing
        sessions[sessionIndex].plan = next.plan
        sessions[sessionIndex].verify = next.verify
        sessions[sessionIndex].beforeSha = await gitCurrentSha(workspace)
        try? persistSessions()

        do {
            let prompt = Prompts.developPrompt(
                next: next,
                lessons: workspace.readLessons(),
                vision: workspace.readVision()
            )

            log("Develop: launching codex exec.", level: .info)
            let codex = CodexExecutor()
            executor = codex
            let summary = try await codex.run(
                CodexRunConfiguration(
                    codexBinary: codexBinary,
                    repoURL: workspace.repoURL,
                    sandbox: "danger-full-access",
                    model: modelOverride,
                    schema: Prompts.developSchema,
                    prompt: prompt
                ),
                decode: DevelopSummary.self,
                onEvent: { [weak self] line in
                    Task { @MainActor in self?.log(line, level: .raw) }
                }
            )

            sessions[sessionIndex].feedback = summary.feedback
            sessions[sessionIndex].notes.append(summary.summary)

            var succeeded = summary.status == .succeeded
            if summary.bypassVerify == true {
                log("Develop requested verify bypass: \(summary.feedback)", level: .warning)
            } else {
                phase = .verifying
                let verify = try await ProcessRunner.runShell(
                    next.verify,
                    workingDirectory: workspace.repoURL,
                    timeout: TimeInterval(next.verifyTimeoutMs ?? 600_000) / 1000
                )
                sessions[sessionIndex].verifyOutput = VerifyOutput(
                    command: next.verify,
                    exitCode: Int(verify.exitCode),
                    tail: tail(verify.stdout + verify.stderr, max: 4000)
                )
                succeeded = succeeded && verify.exitCode == 0
                log("Verify exited \(verify.exitCode).", level: verify.exitCode == 0 ? .success : .error)
            }

            let clean = await gitStatusIsClean(workspace)
            succeeded = succeeded && clean
            if !clean {
                sessions[sessionIndex].notes.append("Working tree is not clean after Develop.")
                log("Working tree is not clean after Develop.", level: .error)
            }

            sessions[sessionIndex].afterSha = await gitCurrentSha(workspace)
            sessions[sessionIndex].commits = await gitCommits(
                workspace,
                from: sessions[sessionIndex].beforeSha,
                to: sessions[sessionIndex].afterSha
            )

            endSession(sessionIndex, status: succeeded ? .succeeded : .failed)
            phase = succeeded ? .succeeded : .failed
            log(succeeded ? "Develop completed." : "Develop finished with failed post-checks.", level: succeeded ? .success : .error)
        } catch {
            sessions[sessionIndex].notes.append(error.localizedDescription)
            endSession(sessionIndex, status: .failed)
            phase = .failed
            fail(error)
        }

        isRunning = false
        executor = nil
        await refresh()
    }

    private func initializeIfNeeded(_ workspace: CompassWorkspace) async {
        guard !FileManager.default.fileExists(atPath: workspace.compassURL.path) else { return }
        try? workspace.initialize()
        await refresh()
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

    private func previousFeedback(excluding session: Int) -> String {
        sessions
            .filter { $0.session != session && $0.endedAt != nil }
            .sorted { $0.startedAt > $1.startedAt }
            .compactMap { $0.feedback?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
    }

    private func persistSessions() throws {
        try workspace?.writeSessions(sessions)
    }

    private func gitCurrentSha(_ workspace: CompassWorkspace) async -> String? {
        guard let result = try? await ProcessRunner.runEnv(
            "git",
            ["rev-parse", "HEAD"],
            workingDirectory: workspace.repoURL
        ), result.exitCode == 0 else {
            return nil
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func gitStatusIsClean(_ workspace: CompassWorkspace) async -> Bool {
        guard let result = try? await ProcessRunner.runEnv(
            "git",
            ["status", "--porcelain"],
            workingDirectory: workspace.repoURL
        ), result.exitCode == 0 else {
            return false
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func gitCommits(_ workspace: CompassWorkspace, from before: String?, to after: String?) async -> [SessionCommit] {
        guard let after, before != after else { return [] }
        let range = before.map { "\($0)..\(after)" } ?? after
        guard let result = try? await ProcessRunner.runEnv(
            "git",
            ["log", "--format=%H%x09%h%x09%s", range],
            workingDirectory: workspace.repoURL
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

    private func log(_ text: String, level: ActivityLine.Level) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        activity.append(ActivityLine(level: level, text: trimmed))
        if activity.count > 800 {
            activity.removeFirst(activity.count - 800)
        }
    }

    private func fail(_ error: Error) {
        errorMessage = error.localizedDescription
        log(error.localizedDescription, level: .error)
    }

    private func tail(_ text: String, max: Int) -> String {
        guard text.count > max else { return text }
        return String(text.suffix(max))
    }
}

private enum AppModelError: LocalizedError {
    case noRepositorySelected
    case notGitRepository(String)

    var errorDescription: String? {
        switch self {
        case .noRepositorySelected:
            return "Choose a Git repository before running CompassNative."
        case let .notGitRepository(path):
            return "\(path) is not inside a Git repository."
        }
    }
}
