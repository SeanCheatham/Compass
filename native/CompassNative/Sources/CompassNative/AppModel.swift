import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var repoPath = ""
    @Published var codexBinary = CodexBinaryLocator.defaultBinary()
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
        let url = CompassWorkspace.normalizedURL(from: trimmed)
        guard let repoURL = CompassWorkspace.discover(from: url) else { return nil }
        return CompassWorkspace(repoURL: repoURL)
    }

    private var executor: CodexExecutor?
    private let maxDevelopAttempts = 3
    private let reflectSessionWindow = 10

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
extension AppModel {
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
        let repoURL: URL
        do {
            repoURL = try await resolveGitRoot(from: url)
        } catch {
            fail(AppModelError.notGitRepository(url.path))
            return
        }
        repoPath = repoURL.path
        log("Selected repo: \(repoURL.path)", level: .success)
        log("Compass workspace: \(CompassWorkspace(repoURL: repoURL).compassURL.path)", level: .info)
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

    func saveDrafts() async {
        do {
            guard let workspace else {
                fail(AppModelError.noRepositorySelected)
                return
            }
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
            try await runReflectIfNeeded(workspace, sessionIndex: sessionIndex)

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
            let nextState = try await codex.run(
                CodexRunConfiguration(
                    codexBinary: codexBinary,
                    repoURL: workspace.repoURL,
                    sandbox: "read-only",
                    model: modelForPhase(envKey: "COMPASS_CODEX_PLAN_MODEL"),
                    schema: Prompts.planSchema,
                    prompt: prompt
                ),
                decode: PlanState.self,
                onEvent: { [weak self] line in
                    Task { @MainActor in self?.log(line, level: .raw) }
                }
            )

            try validatePlanTransition(from: currentState, to: nextState)
            try workspace.writeState(nextState)
            state = nextState
            log(
                "Plan accepted: \(nextState.completed.count) completed, immediate: \(firstLine(nextState.immediate?.plan) ?? "none").",
                level: .success
            )
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
                appendSessionNote("Plan-only run; Develop was not started.", to: sessionIndex)
                endSession(sessionIndex, status: .awaitingApproval)
                phase = .idle
                isRunning = false
                executor = nil
            }
        } catch {
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

    private func runDevelopPass(existingSessionIndex: Int?) async {
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
        sessions[sessionIndex].plan = next.plan
        sessions[sessionIndex].verify = next.verify
        let beforeSha = await gitCurrentSha(at: workspace.repoURL)
        sessions[sessionIndex].beforeSha = beforeSha
        try? persistSessions()

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
                        model: modelForPhase(envKey: "COMPASS_CODEX_DEV_MODEL"),
                        schema: Prompts.developSchema,
                        prompt: prompt
                    ),
                    decode: DevelopSummary.self,
                    onEvent: { [weak self] line in
                        Task { @MainActor in self?.log(line, level: .raw) }
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
        } catch {
            appendSessionNote(error.localizedDescription, to: sessionIndex)
            endSession(sessionIndex, status: .failed)
            phase = .failed
            fail(error)
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
        let trimmed = repoPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AppModelError.noRepositorySelected
        }

        let repoURL = try await resolveGitRoot(from: CompassWorkspace.normalizedURL(from: trimmed))
        if repoPath != repoURL.path {
            repoPath = repoURL.path
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

    private func previousFeedback(excluding session: Int) -> String {
        sessions
            .filter { $0.session != session && $0.endedAt != nil }
            .sorted { $0.startedAt > $1.startedAt }
            .compactMap { $0.feedback?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
    }

    private func runReflectIfNeeded(_ workspace: CompassWorkspace, sessionIndex: Int) async throws {
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
                model: modelForPhase(envKey: "COMPASS_CODEX_REFLECT_MODEL"),
                schema: Prompts.reflectSchema,
                prompt: prompt
            ),
            decode: ReflectSummary.self,
            onEvent: { [weak self] line in
                Task { @MainActor in self?.log(line, level: .raw) }
            }
        )

        if let reflectedState = result.state {
            try workspace.writeState(reflectedState)
            state = reflectedState
            log("Reflect updated state.json: \(result.summary)", level: .success)
        } else {
            log("Reflect: \(result.summary)", level: .info)
        }
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

    private func modelForPhase(envKey: String) -> String? {
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

    private func log(_ text: String, level: ActivityLine.Level) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        activity.append(ActivityLine(level: level, text: trimmed))
        if activity.count > 800 {
            activity.removeFirst(activity.count - 800)
        }
    }

    private func firstLine(_ text: String?) -> String? {
        text?
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)
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

private enum AppModelError: LocalizedError {
    case noRepositorySelected
    case notGitRepository(String)
    case gitCommandFailed(String)
    case internalInvariant(String)
    case rejectedPlan(String)

    var errorDescription: String? {
        switch self {
        case .noRepositorySelected:
            return "Choose a Git repository before running CompassNative."
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
