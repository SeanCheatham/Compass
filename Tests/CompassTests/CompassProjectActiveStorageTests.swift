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

    func testProjectRecordsRecapShareArtifactInActiveApplicationSupportStorageWithoutPasteboard() async throws {
        let repoURL = try makeTemporaryGitRepository()
        let roots = try makeApplicationSupportRoots()
        let project = CompassProject(
            repoURL: repoURL,
            activeStorage: .applicationSupport,
            storageApplicationSupportRoots: roots
        )
        let workspace = applicationSupportWorkspace(repoURL: repoURL, roots: roots)
        let session = makeRecapSession(41, endedAt: 41_500)
        let share = makeRecapSharePlan(
            session: session,
            completed: ["Record project recap share artifact"]
        )

        await project.initializeWorkspace()
        project.sessions = [session]

        let result = await project.recordRunRecapShareArtifact(sharePlan: share)

        let url = try XCTUnwrap(result.artifactURL)
        XCTAssertEqual(result.status, .recorded)
        XCTAssertEqual(project.cinematicRunRecapShareArtifactRecording, result)
        XCTAssertEqual(url, workspace.sessionsURL.appending(path: "41-\(result.artifactPlan.filename)"))
        XCTAssertEqual(project.cinematicRunRecapShareArtifactHistory.totalCount, 1)
        XCTAssertEqual(project.cinematicRunRecapShareArtifactHistory.latestEntry?.sessionNumber, 41)
        XCTAssertEqual(
            project.cinematicRunRecapShareArtifactHistory.latestEntry?.url.standardizedFileURL,
            url.standardizedFileURL
        )
        XCTAssertTrue(project.cinematicRunRecapShareArtifactHistory.combinedMarkdownExport.contains(result.artifactPlan.title))
        XCTAssertFileExists(url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.repoLocalCompassURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appending(path: ".gitignore").path))
    }

    func testProjectCleansRecapShareArtifactsInActiveApplicationSupportStorageAndRefreshesHistory() async throws {
        let repoURL = try makeTemporaryGitRepository()
        let roots = try makeApplicationSupportRoots()
        let project = CompassProject(
            repoURL: repoURL,
            activeStorage: .applicationSupport,
            storageApplicationSupportRoots: roots
        )
        let workspace = applicationSupportWorkspace(repoURL: repoURL, roots: roots)
        let artifactCount = CinematicRunRecapShareArtifactHistoryPlan.retentionLimit + 2
        var artifactURLs: [Int: URL] = [:]

        await project.initializeWorkspace()
        for session in 1...artifactCount {
            artifactURLs[session] = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-support-\(session).md",
                contents: recapArtifactMarkdown(session: session)
            )
        }

        await project.refresh()
        let before = project.cinematicRunRecapShareArtifactHistory
        let result = await project.cleanupRunRecapShareArtifacts()

        XCTAssertEqual(before.totalCount, artifactCount)
        XCTAssertEqual(before.cleanupCandidateCount, 2)
        XCTAssertEqual(result.status, .deleted)
        XCTAssertEqual(result.deletedCount, 2)
        XCTAssertEqual(project.cinematicRunRecapShareArtifactCleanup, result)
        XCTAssertEqual(project.cinematicRunRecapShareArtifactHistory, result.refreshedHistory)
        XCTAssertEqual(project.cinematicRunRecapShareArtifactHistory.totalCount, before.retentionLimit)
        XCTAssertEqual(project.cinematicRunRecapShareArtifactHistory.cleanupCandidateCount, 0)
        XCTAssertEqual(project.cinematicRunRecapShareArtifactHistory.warningCount, 0)

        for session in 1...2 {
            XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(artifactURLs[session]).path))
        }
        for session in 3...artifactCount {
            XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(artifactURLs[session]).path))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.repoLocalCompassURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appending(path: ".gitignore").path))
    }

    private func makeTemporaryGitRepository() throws -> URL {
        let directory = try makeTemporaryDirectory()
        try createDirectory(directory.appending(path: ".git", directoryHint: .isDirectory))
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

    private func makeRecapSharePlan(
        session: SessionRecord,
        completed: [String]
    ) -> CinematicRunRecapSharePlan {
        let state = PlanState(completed: completed, immediate: nil, midTerm: "", longTerm: "")
        let commitPlan = CinematicCommitConstellationPlan(sessions: [session])
        let recapPlan = CinematicRunRecapPlanner.plan(
            state: state,
            sessions: [session],
            isRunning: false,
            isAutoPlaying: false,
            recentRunCues: [:],
            commitConstellationPlan: commitPlan,
            nativeFeedbackLifecycle: CinematicNativeFeedbackCueLifecycle()
        )
        let timelinePlan = CinematicSessionTimelinePlan(sessions: [session])
        let focusPlan = CinematicRunRecapSceneFocusPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: recapPlan,
            commitConstellationPlan: commitPlan,
            timelinePlan: timelinePlan
        )
        let endCardPlan = CinematicRunRecapEndCardPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: recapPlan
        )
        return CinematicRunRecapSharePlanner.plan(
            recapPlan: recapPlan,
            recapFocusDescriptor: focusPlan.descriptor,
            endCardDescriptor: endCardPlan.descriptor
        )
    }

    private func makeRecapSession(_ number: Int, endedAt: Double?) -> SessionRecord {
        SessionRecord(
            session: number,
            startedAt: Double(number * 1_000),
            endedAt: endedAt,
            plan: "Record recap share artifact",
            verify: "swift test --filter CompassProjectActiveStorageTests",
            beforeSha: nil,
            afterSha: nil,
            commits: [
                SessionCommit(
                    sha: "abcdef1234567890",
                    short: "abcdef1",
                    subject: "Record project recap share artifact"
                )
            ],
            status: .succeeded,
            notes: [],
            verifyOutput: nil,
            feedback: nil
        )
    }

    private func recapArtifactMarkdown(session: Int) -> String {
        """
        # Compass Run Recap Share

        - Artifact: artifact-\(session)
        - Availability: available
        - Session: \(session)
        - Filename: recap-share-support-\(session).md
        - Share: share-id
        - Recap: recap-id
        - Focus: focus-id
        - End card: end-card-id
        - Title: Support Recap \(session)
        - Status: succeeded
        - Detail: Support detail
        - Commit: Support commit \(session)
        """
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
