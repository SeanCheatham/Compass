import Foundation
@testable import Compass
import XCTest

final class CinematicRunRecapShareArtifactTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
    }

    func testArtifactPlanUsesLatestFinishedSessionAndStableMarkdown() throws {
        let older = makeSession(
            30,
            commits: [makeCommit(subject: "Older recap share artifact")],
            endedAt: 30_500
        )
        let latest = makeSession(
            31,
            commits: [makeCommit(subject: "Ship recap share artifact")],
            endedAt: 31_500
        )
        let running = makeSession(32, status: .developing, endedAt: nil)
        let share = makeSharePlan(
            session: latest,
            completed: ["Completed recap share artifact recording"],
            runCues: [
                latest.session: runCue(
                    kind: .failedVerify,
                    severity: .failure,
                    label: "Retry Develop",
                    detail: "verify failed before artifact",
                    systemImage: "checkmark.seal.fill"
                )
            ]
        )

        let first = CinematicRunRecapShareArtifactPlanner.plan(
            sharePlan: share,
            sessions: [older, running, latest]
        )
        let repeated = CinematicRunRecapShareArtifactPlanner.plan(
            sharePlan: share,
            sessions: [older, running, latest]
        )

        XCTAssertEqual(first, repeated)
        XCTAssertTrue(first.isAvailable)
        XCTAssertEqual(first.availabilityReason, "available")
        XCTAssertEqual(first.sessionNumber, latest.session)
        XCTAssertEqual(first.shareIdentifier, share.identifier)
        XCTAssertEqual(first.recapIdentifier, share.recapIdentifier)
        XCTAssertEqual(first.recapFocusIdentifier, share.recapFocusIdentifier)
        XCTAssertEqual(first.endCardIdentifier, share.endCardIdentifier)
        XCTAssertEqual(first.commitHighlight, "Ship recap share artifact")
        XCTAssertEqual(first.eventSummaryCount, 1)
        XCTAssertGreaterThan(first.visualDescriptorTokenCount, 0)
        XCTAssertTrue(first.filename.hasPrefix("recap-share-"))
        XCTAssertTrue(first.filename.hasSuffix(".md"))
        XCTAssertFalse(first.filename.contains("/"))
        XCTAssertFalse(first.filename.contains(":"))
        XCTAssertTrue(first.markdownContents.contains("# Compass Run Recap Share"))
        XCTAssertTrue(first.markdownContents.contains("- Artifact: \(first.identifier)"))
        XCTAssertTrue(first.markdownContents.contains("- Session: 31"))
        XCTAssertTrue(first.markdownContents.contains("- Filename: \(first.filename)"))
        XCTAssertTrue(first.markdownContents.contains("- Share:"))
        XCTAssertTrue(first.markdownContents.contains("- Recap:"))
        XCTAssertTrue(first.markdownContents.contains("## Events"))
        XCTAssertTrue(first.markdownContents.contains("Retry Develop"))
        XCTAssertTrue(first.markdownContents.contains("## Visual Tokens"))
        XCTAssertTrue(first.markdownContents.contains("focus-shot:victory"))
        XCTAssertTrue(first.markdownContents.contains("## Share Text"))
        XCTAssertLessThanOrEqual(first.identifier.count, CinematicRunRecapShareArtifactPlan.identifierMaxCharacters)
        XCTAssertLessThanOrEqual(first.filename.count, CinematicRunRecapShareArtifactPlan.filenameMaxCharacters)
        XCTAssertLessThanOrEqual(first.markdownLength, CinematicRunRecapShareArtifactPlan.markdownMaxCharacters)
        XCTAssertLessThanOrEqual(first.feedback.count, CinematicRunRecapShareArtifactPlan.feedbackMaxCharacters)
    }

    func testUnavailableShareArtifactIsSkippedWithBoundedFeedback() throws {
        let workspace = try makeInitializedWorkspace()
        let finished = makeSession(29, endedAt: 29_500)
        let share = CinematicRunRecapSharePlanner.plan(
            recapPlan: .empty(reason: "active-run")
        )

        let result = workspace.recordRunRecapShareArtifact(
            sharePlan: share,
            sessions: [finished]
        )

        XCTAssertEqual(result.status, .skipped)
        XCTAssertFalse(result.artifactPlan.isAvailable)
        XCTAssertEqual(result.artifactPlan.availabilityReason, "active-run")
        XCTAssertNil(result.artifactPlan.sessionNumber)
        XCTAssertNil(result.artifactURL)
        XCTAssertTrue(result.detail.contains("active-run"))
        XCTAssertLessThanOrEqual(result.detail.count, CinematicRunRecapShareArtifactRecordingResult.detailMaxCharacters)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: workspace.sessionsURL.path), [])
    }

    func testFilenameAndMarkdownBoundsHoldForLongShareInputs() {
        let session = makeSession(
            33,
            commits: [makeCommit(subject: String(repeating: "Very long commit subject ", count: 20))],
            endedAt: 33_500
        )
        let share = makeSharePlan(
            session: session,
            completed: [String(repeating: "Completed very long recap share artifact copy ", count: 24)]
        )

        let artifact = CinematicRunRecapShareArtifactPlanner.plan(
            sharePlan: share,
            sessions: [session]
        )

        XCTAssertTrue(artifact.isAvailable)
        XCTAssertLessThanOrEqual(artifact.identifier.count, CinematicRunRecapShareArtifactPlan.identifierMaxCharacters)
        XCTAssertLessThanOrEqual(artifact.filename.count, CinematicRunRecapShareArtifactPlan.filenameMaxCharacters)
        XCTAssertLessThanOrEqual(artifact.markdownLength, CinematicRunRecapShareArtifactPlan.markdownMaxCharacters)
        XCTAssertLessThanOrEqual(artifact.title.count, CinematicRunRecapPlan.titleLimit)
        XCTAssertLessThanOrEqual(artifact.detail.count, CinematicRunRecapPlan.detailLimit)
        XCTAssertLessThanOrEqual(artifact.status.count, CinematicRunRecapPlan.statusLimit)
        XCTAssertFalse(artifact.filename.contains("/"))
        XCTAssertFalse(artifact.filename.contains(":"))
        XCTAssertFalse(artifact.filename.contains(" "))
        XCTAssertTrue(artifact.markdownContents.hasPrefix("# Compass Run Recap Share"))
    }

    func testWorkspaceRecordsArtifactInActiveStorageSessionsDirectory() throws {
        let repoURL = try makeTemporaryGitRepository()
        let storageRootURL = try makeTemporaryDirectory(prefix: "RecapShareArtifactSupport")
            .appending(path: "Compass", directoryHint: .isDirectory)
            .appending(path: "Projects", directoryHint: .isDirectory)
            .appending(path: "project-storage", directoryHint: .isDirectory)
        let workspace = CompassWorkspace(repoURL: repoURL, storageRootURL: storageRootURL)
        let session = makeSession(34, endedAt: 34_500)
        let share = makeSharePlan(session: session, completed: ["Record in active storage"])

        try workspace.initialize()
        let result = workspace.recordRunRecapShareArtifact(
            sharePlan: share,
            sessions: [session]
        )

        let url = try XCTUnwrap(result.artifactURL)
        XCTAssertEqual(result.status, .recorded)
        XCTAssertEqual(result.artifactPlan.sessionNumber, 34)
        XCTAssertEqual(url, workspace.sessionsURL.appending(path: "34-\(result.artifactPlan.filename)"))
        XCTAssertEqual(try read(url), result.artifactPlan.markdownContents)
        let history = workspace.refreshRunRecapShareArtifactHistory()
        XCTAssertEqual(history.totalCount, 1)
        XCTAssertEqual(history.latestEntry?.sessionNumber, 34)
        XCTAssertEqual(history.latestEntry?.filename, "34-\(result.artifactPlan.filename)")
        XCTAssertTrue(history.combinedMarkdownExport.contains(result.artifactPlan.title))
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.repoLocalCompassURL.path))
    }

    func testWriteFailureReturnsFailedResultWithoutThrowing() throws {
        let workspace = try makeInitializedWorkspace()
        let session = makeSession(35, endedAt: 35_500)
        let share = makeSharePlan(session: session, completed: ["Surface write failure"])
        try FileManager.default.removeItem(at: workspace.sessionsURL)
        try write("not a directory", to: workspace.sessionsURL)

        let result = workspace.recordRunRecapShareArtifact(
            sharePlan: share,
            sessions: [session]
        )

        XCTAssertEqual(result.status, .failed)
        XCTAssertNil(result.artifactURL)
        XCTAssertTrue(result.artifactPlan.isAvailable)
        XCTAssertEqual(result.artifactPlan.sessionNumber, 35)
        XCTAssertTrue(result.detail.contains("Could not save recap artifact"))
        XCTAssertTrue(result.help.contains("Pasteboard copy is independent"))
        XCTAssertLessThanOrEqual(result.detail.count, CinematicRunRecapShareArtifactRecordingResult.detailMaxCharacters)
        XCTAssertLessThanOrEqual(result.help.count, CinematicRunRecapShareArtifactRecordingResult.helpMaxCharacters)
        XCTAssertEqual(try read(workspace.sessionsURL), "not a directory")
    }

    func testArtifactPlanningPreservesRecapTimelineAndIdleCycleInputs() throws {
        let session = makeSession(36, endedAt: 36_500)
        let state = PlanState(
            completed: ["Preserve artifact invariants"],
            immediate: nil,
            midTerm: "",
            longTerm: ""
        )
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
        let recapBefore = recapPlan
        let timelineBefore = CinematicSessionTimelinePlan(
            sessions: [session],
            selectedBeatID: try XCTUnwrap(CinematicSessionTimelinePlan(sessions: [session]).beats.first?.stableID)
        )
        let focusPlan = CinematicRunRecapSceneFocusPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: recapPlan,
            commitConstellationPlan: commitPlan,
            timelinePlan: timelineBefore
        )
        let endCardPlan = CinematicRunRecapEndCardPlanner.plan(
            isRecapOverlaySelected: true,
            recapPlan: recapPlan
        )
        let idleInput = CinematicIdleStoryCyclePlan.SessionInput(
            elapsedTime: 42,
            sessionOrdinal: session.session
        )
        let idleBefore = CinematicIdleStoryCyclePlanner.plan(
            session: idleInput,
            isLiveFollowActive: false,
            hasExplicitUserFocus: false,
            influenceSettings: CinematicInfluenceSettings(),
            commitConstellationPlan: commitPlan,
            timelineSceneFocusPlan: .none,
            nativeFeedbackCue: nil,
            nativeFeedbackPlaqueDescriptor: nil,
            runRecapPlan: recapPlan,
            runRecapSceneFocusPlan: focusPlan,
            runRecapEndCardPlan: endCardPlan
        )
        let sharePlan = CinematicRunRecapSharePlanner.plan(
            recapPlan: recapPlan,
            recapFocusDescriptor: focusPlan.descriptor,
            endCardDescriptor: endCardPlan.descriptor
        )

        _ = CinematicRunRecapShareArtifactPlanner.plan(
            sharePlan: sharePlan,
            sessions: [session]
        )

        XCTAssertEqual(recapPlan, recapBefore)
        XCTAssertEqual(
            CinematicSessionTimelinePlan(
                sessions: [session],
                selectedBeatID: timelineBefore.selectedBeatID
            ),
            timelineBefore
        )
        XCTAssertEqual(
            CinematicIdleStoryCyclePlanner.plan(
                session: idleInput,
                isLiveFollowActive: false,
                hasExplicitUserFocus: false,
                influenceSettings: CinematicInfluenceSettings(),
                commitConstellationPlan: commitPlan,
                timelineSceneFocusPlan: .none,
                nativeFeedbackCue: nil,
                nativeFeedbackPlaqueDescriptor: nil,
                runRecapPlan: recapPlan,
                runRecapSceneFocusPlan: focusPlan,
                runRecapEndCardPlan: endCardPlan
            ),
            idleBefore
        )
    }

    private func makeSharePlan(
        session: SessionRecord,
        completed: [String],
        runCues: [Int: PlanReliabilityFeedback.RunCue] = [:]
    ) -> CinematicRunRecapSharePlan {
        let state = PlanState(completed: completed, immediate: nil, midTerm: "", longTerm: "")
        let commitPlan = CinematicCommitConstellationPlan(sessions: [session])
        let recapPlan = CinematicRunRecapPlanner.plan(
            state: state,
            sessions: [session],
            isRunning: false,
            isAutoPlaying: false,
            recentRunCues: runCues,
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

    private func makeSession(
        _ number: Int,
        status: SessionStatus = .succeeded,
        commits: [SessionCommit] = [],
        endedAt: Double? = nil
    ) -> SessionRecord {
        SessionRecord(
            session: number,
            startedAt: Double(number * 1_000),
            endedAt: endedAt,
            plan: "Implement recap share artifact",
            verify: "swift test --filter CinematicRunRecapShareArtifactTests",
            beforeSha: nil,
            afterSha: nil,
            commits: commits,
            status: status,
            notes: [],
            verifyOutput: nil,
            feedback: nil
        )
    }

    private func makeCommit(subject: String) -> SessionCommit {
        SessionCommit(
            sha: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
            short: "abcdef1",
            subject: subject
        )
    }

    private func runCue(
        kind: PlanReliabilityFeedback.Kind,
        severity: PlanReliabilityFeedback.Severity,
        label: String,
        detail: String,
        systemImage: String
    ) -> PlanReliabilityFeedback.RunCue {
        PlanReliabilityFeedback.RunCue(
            notice: PlanReliabilityFeedback.Notice(
                id: "\(kind.rawValue)-artifact-test",
                kind: kind,
                severity: severity,
                sessionNumber: 0,
                title: label,
                detail: detail,
                actionLabel: label,
                metadata: nil,
                systemImage: systemImage
            )
        )
    }

    private func makeInitializedWorkspace() throws -> CompassWorkspace {
        let repoURL = try makeTemporaryGitRepository()
        let workspace = CompassWorkspace(repoURL: repoURL)
        try workspace.initialize()
        return workspace
    }

    private func makeTemporaryGitRepository() throws -> URL {
        let directory = try makeTemporaryDirectory()
        try createDirectory(directory.appending(path: ".git", directoryHint: .isDirectory))
        return directory
    }

    private func makeTemporaryDirectory(prefix: String = "CinematicRunRecapShareArtifactTests") throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
        temporaryDirectories.append(directory)
        try createDirectory(directory)
        return directory
    }

    private func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private func write(_ contents: String, to url: URL) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}
