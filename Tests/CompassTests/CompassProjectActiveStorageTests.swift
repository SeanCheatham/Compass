import Foundation
@testable import Compass
import XCTest

@MainActor
final class CompassProjectActiveStorageTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
    }

    func testResolverDefaultsToRepoLocalStorage() throws {
        let repoURL = try makeTemporaryGitRepository()
        let roots = try makeApplicationSupportRoots()
        let resolver = CompassProjectStorageResolver(
            repoURL: repoURL,
            applicationSupportRoots: roots
        )
        let standardizedRepoURL = repoURL.standardizedFileURL
        let repoLocalURL = CompassWorkspace.repoLocalStorageRootURL(for: standardizedRepoURL)

        XCTAssertEqual(resolver.activeStorage, .repoLocal)
        XCTAssertEqual(resolver.repoURL, standardizedRepoURL)
        XCTAssertEqual(resolver.storageRootURL, repoLocalURL)
        XCTAssertEqual(resolver.workspace.repoURL, standardizedRepoURL)
        XCTAssertEqual(resolver.workspace.compassURL, repoLocalURL)
    }

    func testResolverMapsApplicationSupportStorageToCurrentCandidate() throws {
        let repoURL = try makeTemporaryGitRepository()
        let roots = try makeApplicationSupportRoots()
        let resolver = CompassProjectStorageResolver(
            repoURL: repoURL,
            activeStorage: .applicationSupport,
            applicationSupportRoots: roots
        )
        let expectedURL = CompassWorkspaceStorageAssessment.currentApplicationSupportCandidateURL(
            for: repoURL.standardizedFileURL,
            applicationSupportRoots: roots
        )

        XCTAssertEqual(resolver.storageRootURL, expectedURL)
        XCTAssertEqual(resolver.workspace.repoURL, repoURL.standardizedFileURL)
        XCTAssertEqual(resolver.workspace.compassURL, expectedURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: expectedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: resolver.workspace.repoLocalCompassURL.path))
    }

    func testProjectDefaultsToRepoLocalStorage() async throws {
        let repoURL = try makeTemporaryGitRepository()
        let roots = try makeApplicationSupportRoots()
        let project = CompassProject(
            repoURL: repoURL,
            storageApplicationSupportRoots: roots
        )
        let repoLocalURL = CompassWorkspace.repoLocalStorageRootURL(for: repoURL.standardizedFileURL)
        let applicationSupportURL = CompassWorkspaceStorageAssessment.currentApplicationSupportCandidateURL(
            for: repoURL.standardizedFileURL,
            applicationSupportRoots: roots
        )

        XCTAssertEqual(project.activeStorage, .repoLocal)
        XCTAssertEqual(project.compassPath, repoLocalURL.path)

        await project.initializeWorkspace()

        XCTAssertDirectoryExists(repoLocalURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: applicationSupportURL.path))
    }

    func testApplicationSupportActiveStorageRoundTripsCompassFilesWithoutRepoLocalCompass() async throws {
        let repoURL = try makeTemporaryGitRepository()
        let roots = try makeApplicationSupportRoots()
        let project = CompassProject(
            repoURL: repoURL,
            activeStorage: .applicationSupport,
            storageApplicationSupportRoots: roots
        )
        let resolver = CompassProjectStorageResolver(
            repoURL: repoURL,
            activeStorage: .applicationSupport,
            applicationSupportRoots: roots
        )
        let workspace = resolver.workspace
        let state = PlanState(
            completed: ["application support"],
            immediate: PlanNext(plan: "Honor active storage", verify: "swift test"),
            midTerm: "persist",
            longTerm: "factory"
        )
        let records = [
            SessionRecord(
                session: 7,
                startedAt: 10,
                endedAt: 20,
                plan: "Plan",
                verify: "true",
                beforeSha: nil,
                afterSha: nil,
                commits: [],
                status: .succeeded,
                notes: ["done"],
                verifyOutput: nil,
                feedback: "ok"
            )
        ]

        XCTAssertEqual(project.compassPath, workspace.compassURL.path)

        await project.initializeWorkspace()
        try workspace.writeState(state)
        try workspace.writeDrafts("draft from support\n")
        try workspace.writeLessons("- lesson from support\n")
        try workspace.writeVision("vision from support\n")
        try workspace.writeSessions(records)

        await project.refresh()

        XCTAssertEqual(project.state, state)
        XCTAssertEqual(project.drafts, "draft from support\n")
        XCTAssertEqual(project.lessons, "- lesson from support\n")
        XCTAssertEqual(project.vision, "vision from support\n")
        XCTAssertEqual(project.sessions, records)
        XCTAssertDirectoryExists(workspace.compassURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.repoLocalCompassURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appending(path: ".gitignore").path))

        project.drafts = "updated support draft\n"
        await project.saveDrafts()
        project.lessons = "- updated support lesson\n"
        await project.saveLessons()

        XCTAssertEqual(workspace.readDrafts(), "updated support draft\n")
        XCTAssertEqual(workspace.readLessons(), "- updated support lesson\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.repoLocalCompassURL.path))
    }

    func testApplicationSupportActiveStorageDerivesActivityProfileFromSupportSessionsWhenRepoLocalSessionsMissing() async throws {
        let repoURL = try await makeInitializedGitRepository()
        let roots = try makeApplicationSupportRoots()
        let workspace = applicationSupportWorkspace(repoURL: repoURL, roots: roots)
        let supportState = PlanState(
            completed: ["scan support sessions"],
            immediate: PlanNext(plan: "Keep Plan state stable", verify: "swift test"),
            midTerm: "support activity",
            longTerm: "factory"
        )
        let supportSessions = [
            makeActivitySession(21, status: .failed, endedAt: 21_000, commits: 1),
            makeActivitySession(22, status: .succeeded, endedAt: 22_000, commits: 2),
            makeActivitySession(23, status: .succeeded, endedAt: 23_000, commits: 3)
        ]
        let project = CompassProject(
            repoURL: repoURL,
            activeStorage: .applicationSupport,
            storageApplicationSupportRoots: roots
        )

        try workspace.initialize()
        try workspace.writeState(supportState)
        try workspace.writeSessions(supportSessions)
        try write("pending repo worktree\n", to: repoURL.appending(path: "pending.txt"))
        project.state = supportState

        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.repoLocalCompassURL.path))

        await project.refresh()

        let sourceSnapshot = project.activitySourceSnapshot

        XCTAssertTrue(project.activityProfile.isAvailable)
        XCTAssertEqual(project.activityProfile.recentSessionCount, 3)
        XCTAssertEqual(project.activityProfile.recentSucceededCount, 2)
        XCTAssertEqual(project.activityProfile.recentFailedCount, 1)
        XCTAssertEqual(project.activityProfile.recentCommitCount, 6)
        XCTAssertEqual(project.activityProfile.lastTerminalStatus, .succeeded)
        XCTAssertEqual(project.activityProfile.lastSuccessfulSession, 23)
        XCTAssertEqual(project.activityProfile.lastFailedSession, 21)
        XCTAssertEqual(project.activityProfile.successStreak, 2)
        XCTAssertEqual(project.activityProfile.failureStreak, 0)
        XCTAssertTrue(project.activityProfile.recoveredFromFailure)
        XCTAssertEqual(project.activityProfile.worktreeChanges.untracked, 1)
        XCTAssertEqual(project.sessions, supportSessions)
        XCTAssertEqual(sourceSnapshot.activeStorage, .applicationSupport)
        XCTAssertEqual(sourceSnapshot.storageRootURL, workspace.compassURL.standardizedFileURL)
        XCTAssertEqual(sourceSnapshot.sessionsRecordURL, workspace.sessionsRecordURL.standardizedFileURL)
        XCTAssertEqual(sourceSnapshot.sourceAvailability, .available)
        XCTAssertEqual(sourceSnapshot.repoLocalSessionsState, .ignoredMissing)
        XCTAssertTrue(sourceSnapshot.ignoresRepoLocalSessions)
        XCTAssertEqual(project.state, supportState)
        XCTAssertEqual(project.activeStorage, .applicationSupport)
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.repoLocalCompassURL.path))
    }

    func testApplicationSupportActiveStorageIgnoresStaleRepoLocalSessionsForActivityProfile() async throws {
        let repoURL = try await makeInitializedGitRepository()
        let roots = try makeApplicationSupportRoots()
        let workspace = applicationSupportWorkspace(repoURL: repoURL, roots: roots)
        let repoLocalWorkspace = CompassWorkspace(repoURL: repoURL)
        let supportSessions = [
            makeActivitySession(31, status: .failed, endedAt: 31_000, commits: 1),
            makeActivitySession(32, status: .succeeded, endedAt: 32_000, commits: 2)
        ]
        let staleRepoLocalSessions = [
            makeActivitySession(2, status: .failed, endedAt: 2_000, commits: 8),
            makeActivitySession(3, status: .failed, endedAt: 3_000, commits: 8)
        ]
        let project = CompassProject(
            repoURL: repoURL,
            activeStorage: .applicationSupport,
            storageApplicationSupportRoots: roots
        )

        try workspace.initialize()
        try workspace.writeSessions(supportSessions)
        try createDirectory(repoLocalWorkspace.compassURL)
        try repoLocalWorkspace.writeSessions(staleRepoLocalSessions)
        let staleRepoLocalText = try String(contentsOf: repoLocalWorkspace.sessionsRecordURL, encoding: .utf8)

        await project.refresh()

        let sourceSnapshot = project.activitySourceSnapshot

        XCTAssertTrue(project.activityProfile.isAvailable)
        XCTAssertEqual(project.activityProfile.recentSessionCount, 2)
        XCTAssertEqual(project.activityProfile.recentSucceededCount, 1)
        XCTAssertEqual(project.activityProfile.recentFailedCount, 1)
        XCTAssertEqual(project.activityProfile.recentCommitCount, 3)
        XCTAssertEqual(project.activityProfile.lastTerminalStatus, .succeeded)
        XCTAssertEqual(project.activityProfile.lastSuccessfulSession, 32)
        XCTAssertEqual(project.activityProfile.lastFailedSession, 31)
        XCTAssertEqual(project.activityProfile.successStreak, 1)
        XCTAssertEqual(project.activityProfile.failureStreak, 0)
        XCTAssertTrue(project.activityProfile.recoveredFromFailure)
        XCTAssertEqual(project.activeStorage, .applicationSupport)
        XCTAssertEqual(project.sessions, supportSessions)
        XCTAssertEqual(sourceSnapshot.sourceAvailability, .available)
        XCTAssertEqual(sourceSnapshot.repoLocalSessionsState, .ignoredCompatible)
        XCTAssertTrue(sourceSnapshot.ignoresRepoLocalSessions)
        XCTAssertEqual(
            try String(contentsOf: repoLocalWorkspace.sessionsRecordURL, encoding: .utf8),
            staleRepoLocalText
        )
    }

    func testActivitySourceDiagnosticsReportMissingActiveSupportRootReadOnly() async throws {
        let repoURL = try makeTemporaryGitRepository()
        let roots = try makeApplicationSupportRoots()
        let workspace = applicationSupportWorkspace(repoURL: repoURL, roots: roots)
        let project = CompassProject(
            repoURL: repoURL,
            activeStorage: .applicationSupport,
            storageApplicationSupportRoots: roots
        )

        await project.refresh()

        let snapshot = project.activitySourceSnapshot
        let stateBeforeDiagnostics = project.state
        let activeStorageBeforeDiagnostics = project.activeStorage
        let sessionsBeforeDiagnostics = project.sessions

        XCTAssertEqual(project.activityProfile, .empty)
        XCTAssertEqual(snapshot.activeStorage, .applicationSupport)
        XCTAssertEqual(snapshot.storageRootURL, workspace.compassURL.standardizedFileURL)
        XCTAssertEqual(snapshot.sessionsRecordURL, workspace.sessionsRecordURL.standardizedFileURL)
        XCTAssertEqual(snapshot.sourceAvailability, .storageRootMissing)
        XCTAssertEqual(snapshot.repoLocalSessionsState, .ignoredMissing)
        XCTAssertEqual(project.state, stateBeforeDiagnostics)
        XCTAssertEqual(project.activeStorage, activeStorageBeforeDiagnostics)
        XCTAssertEqual(project.sessions, sessionsBeforeDiagnostics)
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.compassURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.repoLocalCompassURL.path))
    }

    func testActivitySourceDiagnosticsReportNoRepositoryFallbackReadOnly() async throws {
        let parentURL = try makeTemporaryDirectory(prefix: "CompassProjectMissingRepoParent")
        let missingRepoURL = parentURL.appending(path: "MissingRepo", directoryHint: .isDirectory)
        let roots = try makeApplicationSupportRoots()
        let project = CompassProject(
            repoURL: missingRepoURL,
            activeStorage: .applicationSupport,
            storageApplicationSupportRoots: roots
        )

        await project.refresh()

        let snapshot = project.activitySourceSnapshot
        let stateBeforeDiagnostics = project.state
        let activeStorageBeforeDiagnostics = project.activeStorage
        let sessionsBeforeDiagnostics = project.sessions

        XCTAssertEqual(project.activityProfile, .empty)
        XCTAssertEqual(snapshot.activeStorage, .applicationSupport)
        XCTAssertNil(snapshot.storageRootURL)
        XCTAssertNil(snapshot.sessionsRecordURL)
        XCTAssertEqual(snapshot.sourceAvailability, .noRepository)
        XCTAssertEqual(snapshot.repoLocalSessionsState, .ignoredMissing)
        XCTAssertEqual(project.state, stateBeforeDiagnostics)
        XCTAssertEqual(project.activeStorage, activeStorageBeforeDiagnostics)
        XCTAssertEqual(project.sessions, sessionsBeforeDiagnostics)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingRepoURL.path))
    }

    func testInitializeWorkspaceRepairsActiveSupportStorageWithoutRepoLocalSideEffects() async throws {
        let repoURL = try makeTemporaryGitRepository()
        let roots = try makeApplicationSupportRoots()
        let project = CompassProject(
            repoURL: repoURL,
            activeStorage: .applicationSupport,
            storageApplicationSupportRoots: roots
        )
        let workspace = applicationSupportWorkspace(repoURL: repoURL, roots: roots)

        var display = CompassWorkspaceStorageDisplayStatus(
            repoURL: repoURL,
            activeStorage: .applicationSupport,
            applicationSupportRoots: roots
        )

        XCTAssertEqual(display.supportRepairAction?.kind, .initializeApplicationSupportWorkspace)
        XCTAssertEqual(display.supportRepairAction?.issueKind, .applicationSupportActiveMissing)
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.compassURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.repoLocalCompassURL.path))

        await project.initializeWorkspace()

        XCTAssertDirectoryExists(workspace.compassURL)
        XCTAssertDirectoryExists(workspace.sessionsURL)
        XCTAssertFileExists(workspace.stateURL)
        XCTAssertFileExists(workspace.draftsURL)
        XCTAssertFileExists(workspace.lessonsURL)
        XCTAssertFileExists(workspace.visionURL)
        XCTAssertFileExists(workspace.sessionsRecordURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.repoLocalCompassURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appending(path: ".gitignore").path))

        display = CompassWorkspaceStorageDisplayStatus(
            repoURL: repoURL,
            activeStorage: .applicationSupport,
            applicationSupportRoots: roots
        )
        XCTAssertNil(display.supportRepairAction)

        try write("- support lesson survives repair\n", to: workspace.lessonsURL)
        try FileManager.default.removeItem(at: workspace.draftsURL)
        try FileManager.default.removeItem(at: workspace.sessionsRecordURL)
        try FileManager.default.removeItem(at: workspace.sessionsURL)

        display = CompassWorkspaceStorageDisplayStatus(
            repoURL: repoURL,
            activeStorage: .applicationSupport,
            applicationSupportRoots: roots
        )
        XCTAssertEqual(display.supportRepairAction?.kind, .initializeApplicationSupportWorkspace)
        XCTAssertEqual(display.supportRepairAction?.issueKind, .applicationSupportActiveIncomplete)

        await project.initializeWorkspace()

        XCTAssertFileExists(workspace.draftsURL)
        XCTAssertFileExists(workspace.sessionsRecordURL)
        XCTAssertDirectoryExists(workspace.sessionsURL)
        XCTAssertEqual(workspace.readLessons(), "- support lesson survives repair\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.repoLocalCompassURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appending(path: ".gitignore").path))
    }

    func testActivationGatingRequiresIdleRepoLocalAndUsableCandidate() async throws {
        let repoURL = try makeTemporaryGitRepository()
        let roots = try makeApplicationSupportRoots()
        let project = CompassProject(
            repoURL: repoURL,
            storageApplicationSupportRoots: roots
        )

        var plan = project.activeStorageActivationPlan()
        XCTAssertFalse(plan.isAvailable)
        XCTAssertEqual(plan.kind, .candidateMissing)

        project.prepareActiveStorageActivationConfirmation()

        XCTAssertNil(project.activeStorageActivationConfirmation)
        XCTAssertEqual(project.activeStorageActivationState.phase, .blocked)

        let supportWorkspace = applicationSupportWorkspace(repoURL: repoURL, roots: roots)
        try supportWorkspace.initialize()

        plan = project.activeStorageActivationPlan()
        XCTAssertTrue(plan.isAvailable)

        project.isRunning = true
        project.prepareActiveStorageActivationConfirmation()

        XCTAssertNil(project.activeStorageActivationConfirmation)
        XCTAssertEqual(project.activeStorageActivationState.phase, .blocked)

        project.isRunning = false
        project.activeStorage = .applicationSupport
        plan = project.activeStorageActivationPlan()

        XCTAssertFalse(plan.isAvailable)
        XCTAssertEqual(plan.kind, .alreadyApplicationSupport)
    }

    func testActivationPersistsThroughCallbackAndRefreshesSupportState() async throws {
        let repoURL = try makeTemporaryGitRepository()
        let roots = try makeApplicationSupportRoots()
        let workspace = applicationSupportWorkspace(repoURL: repoURL, roots: roots)
        try workspace.initialize()
        let state = PlanState(
            completed: ["prepared"],
            immediate: PlanNext(plan: "Use support state", verify: "swift test"),
            midTerm: "storage",
            longTerm: "factory"
        )
        try workspace.writeState(state)
        try workspace.writeDrafts("support draft\n")
        try workspace.writeLessons("- support lesson\n")
        try workspace.writeVision("support vision\n")
        let project = CompassProject(
            repoURL: repoURL,
            storageApplicationSupportRoots: roots
        )

        project.prepareActiveStorageActivationConfirmation()
        let confirmation = try XCTUnwrap(project.activeStorageActivationConfirmation)
        var persistedActiveStorage: [KnownProjectActiveStorage] = []

        await project.confirmActiveStorageActivation(confirmation) {
            persistedActiveStorage.append(project.activeStorage)
        }

        XCTAssertEqual(persistedActiveStorage, [.applicationSupport])
        XCTAssertEqual(project.activeStorage, .applicationSupport)
        XCTAssertEqual(project.activeStorageActivationState.phase, .succeeded)
        XCTAssertEqual(project.compassPath, workspace.compassURL.path)
        XCTAssertEqual(project.state, state)
        XCTAssertEqual(project.drafts, "support draft\n")
        XCTAssertEqual(project.lessons, "- support lesson\n")
        XCTAssertEqual(project.vision, "support vision\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.repoLocalCompassURL.path))

        project.drafts = "updated after activation\n"
        await project.saveDrafts()

        XCTAssertEqual(workspace.readDrafts(), "updated after activation\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.repoLocalCompassURL.path))
    }

    func testActivationRollsBackWhenPersistenceCallbackFails() async throws {
        let repoURL = try makeTemporaryGitRepository()
        let roots = try makeApplicationSupportRoots()
        let workspace = applicationSupportWorkspace(repoURL: repoURL, roots: roots)
        try workspace.initialize()
        let project = CompassProject(
            repoURL: repoURL,
            storageApplicationSupportRoots: roots
        )

        project.prepareActiveStorageActivationConfirmation()
        let confirmation = try XCTUnwrap(project.activeStorageActivationConfirmation)
        var persistedActiveStorage: [KnownProjectActiveStorage] = []

        await project.confirmActiveStorageActivation(confirmation) {
            persistedActiveStorage.append(project.activeStorage)
            throw ActiveStoragePersistenceTestError.failed("registry save failed")
        }

        XCTAssertEqual(persistedActiveStorage, [.applicationSupport, .repoLocal])
        XCTAssertEqual(project.activeStorage, .repoLocal)
        XCTAssertEqual(project.activeStorageActivationState.phase, .failed)
        XCTAssertEqual(project.errorMessage, project.activeStorageActivationState.detail)
        XCTAssertLessThanOrEqual(project.activeStorageActivationState.label.count, CompassProjectActiveStorageState.labelLimit)
        XCTAssertLessThanOrEqual(project.activeStorageActivationState.detail.count, CompassProjectActiveStorageState.detailLimit)
        XCTAssertLessThanOrEqual(project.activeStorageActivationState.helpText.count, CompassProjectActiveStorageState.helpLimit)
        XCTAssertEqual(project.compassPath, workspace.repoLocalCompassURL.path)
    }

    func testActivationReportsMissingAndInvalidCandidateFailuresWithoutSwitching() async throws {
        let missingRepoURL = try makeTemporaryGitRepository()
        let missingRoots = try makeApplicationSupportRoots()
        let missingProject = CompassProject(
            repoURL: missingRepoURL,
            storageApplicationSupportRoots: missingRoots
        )
        let missingConfirmation = CompassWorkspaceStorageActivationConfirmation(
            plan: missingProject.activeStorageActivationPlan()
        )
        var missingPersistCalls = 0

        await missingProject.confirmActiveStorageActivation(missingConfirmation) {
            missingPersistCalls += 1
        }

        XCTAssertEqual(missingPersistCalls, 0)
        XCTAssertEqual(missingProject.activeStorage, .repoLocal)
        XCTAssertEqual(missingProject.activeStorageActivationState.phase, .failed)
        XCTAssertEqual(missingProject.activeStorageActivationPlan().kind, .candidateMissing)

        let invalidRepoURL = try makeTemporaryGitRepository()
        let invalidRoots = try makeApplicationSupportRoots()
        let invalidWorkspace = applicationSupportWorkspace(repoURL: invalidRepoURL, roots: invalidRoots)
        try invalidWorkspace.initialize()
        try write("{", to: invalidWorkspace.stateURL)
        let invalidProject = CompassProject(
            repoURL: invalidRepoURL,
            storageApplicationSupportRoots: invalidRoots
        )

        invalidProject.prepareActiveStorageActivationConfirmation()

        XCTAssertNil(invalidProject.activeStorageActivationConfirmation)
        XCTAssertEqual(invalidProject.activeStorage, .repoLocal)
        XCTAssertEqual(invalidProject.activeStorageActivationPlan().kind, .candidateInvalid)
        XCTAssertEqual(invalidProject.activeStorageActivationState.phase, .blocked)
        XCTAssertEqual(invalidProject.errorMessage, invalidProject.activeStorageActivationState.detail)
        XCTAssertLessThanOrEqual(invalidProject.activeStorageActivationState.detail.count, CompassProjectActiveStorageState.detailLimit)
    }

    private func makeTemporaryGitRepository() throws -> URL {
        let directory = try makeTemporaryDirectory()
        try createDirectory(directory.appending(path: ".git", directoryHint: .isDirectory))
        return directory
    }

    private func makeInitializedGitRepository() async throws -> URL {
        let directory = try makeTemporaryDirectory()
        let result = try await ProcessRunner.runEnv(
            "git",
            ["init", "-q"],
            workingDirectory: directory
        )
        guard result.exitCode == 0 else {
            throw ActiveStoragePersistenceTestError.failed(result.stderr)
        }
        return directory
    }

    private func makeApplicationSupportRoots() throws -> KnownProjectStore.ApplicationSupportRoots {
        let base = try makeTemporaryDirectory(prefix: "CompassProjectActiveStorageSupport")
        return KnownProjectStore.ApplicationSupportRoots(
            current: base.appending(path: "CurrentSupport", directoryHint: .isDirectory),
            legacy: base.appending(path: "LegacySupport", directoryHint: .isDirectory)
        )
    }

    private func makeTemporaryDirectory(prefix: String = "CompassProjectActiveStorageTests") throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
        temporaryDirectories.append(directory)
        try createDirectory(directory)
        return directory
    }

    private func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func write(_ contents: String, to url: URL) throws {
        try createDirectory(url.deletingLastPathComponent())
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func applicationSupportWorkspace(
        repoURL: URL,
        roots: KnownProjectStore.ApplicationSupportRoots
    ) -> CompassWorkspace {
        CompassProjectStorageResolver(
            repoURL: repoURL,
            activeStorage: .applicationSupport,
            applicationSupportRoots: roots
        )
        .workspace
    }

    private func makeActivitySession(
        _ number: Int,
        status: SessionStatus,
        endedAt: Double,
        commits: Int
    ) -> SessionRecord {
        SessionRecord(
            session: number,
            startedAt: endedAt - 300,
            endedAt: endedAt,
            plan: "Activity scan \(number)",
            verify: "swift test",
            beforeSha: nil,
            afterSha: nil,
            commits: (0..<commits).map {
                SessionCommit(
                    sha: "activity-\(number)-\($0)-abcdef1234567890",
                    short: "a\(number)\($0)",
                    subject: "Activity commit \(number)-\($0)"
                )
            },
            status: status,
            notes: [],
            verifyOutput: nil,
            feedback: nil
        )
    }

    private func XCTAssertDirectoryExists(
        _ url: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var isDirectory = ObjCBool(false)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
            "Expected directory to exist at \(url.path).",
            file: file,
            line: line
        )
        XCTAssertTrue(isDirectory.boolValue, "Expected \(url.path) to be a directory.", file: file, line: line)
    }

    private func XCTAssertFileExists(
        _ url: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var isDirectory = ObjCBool(false)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
            "Expected file to exist at \(url.path).",
            file: file,
            line: line
        )
        XCTAssertFalse(isDirectory.boolValue, "Expected \(url.path) to be a file.", file: file, line: line)
    }
}

private enum ActiveStoragePersistenceTestError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case let .failed(message):
            return message
        }
    }
}
