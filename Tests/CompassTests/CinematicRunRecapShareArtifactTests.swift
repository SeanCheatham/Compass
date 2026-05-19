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

    func testRuntimeRouteAuditCoversAppleNativeFallbackAndMissingSnapshots() throws {
        let appleRepoURL = try makeTemporaryGitRepository(prefix: "RuntimeRouteApple")
        try writeDevcontainer(
            #"{"image":"swift:6.0","workspaceFolder":"/workspace/app","containerEnv":{"TOKEN":"secret-runtime-route-env"}}"#,
            in: appleRepoURL
        )
        let appleSnapshot = makeRuntimeSnapshot(
            repoURL: appleRepoURL,
            phase: "Verify",
            attempt: 2,
            preference: .devcontainerPreferred,
            containerToolPath: "/usr/local/bin/container",
            provisioning: true
        )
        let appleSession = makeSession(
            37,
            endedAt: 37_500,
            executionEnvironmentSnapshots: [appleSnapshot]
        )
        let appleArtifact = CinematicRunRecapShareArtifactPlanner.plan(
            sharePlan: makeSharePlan(session: appleSession, completed: ["Audit Apple container route"]),
            sessions: [appleSession]
        )
        let appleAudit = try XCTUnwrap(appleArtifact.runtimeRouteAudit)

        XCTAssertTrue(appleArtifact.markdownContents.contains("## Runtime Route"))
        XCTAssertTrue(appleArtifact.markdownContents.contains("- Runtime audit: \(appleAudit.identifier)"))
        XCTAssertTrue(appleArtifact.markdownContents.contains("- Phase: Verify (verify)"))
        XCTAssertTrue(appleArtifact.markdownContents.contains("- Attempt: 2"))
        XCTAssertTrue(
            appleArtifact.markdownContents.contains(
                "- Selected preference: devcontainer_preferred (Dev Container Preferred)"
            )
        )
        XCTAssertTrue(appleArtifact.markdownContents.contains("- Effective route: apple-container (Apple container)"))
        XCTAssertTrue(appleArtifact.markdownContents.contains("- Support classification: image-routeable"))
        XCTAssertTrue(appleArtifact.markdownContents.contains("- Visible support tokens: image, containerEnv:1, env:TOKEN"))
        XCTAssertTrue(appleArtifact.markdownContents.contains("- Omitted support tokens: 0"))
        XCTAssertTrue(appleArtifact.markdownContents.contains("- Image label: swift:6.0"))
        XCTAssertTrue(appleArtifact.markdownContents.contains("- Workspace label: /workspace/app"))
        XCTAssertTrue(appleArtifact.markdownContents.contains("- Fallback state: direct"))
        XCTAssertTrue(appleArtifact.markdownContents.contains("- Fallback reason: none"))
        XCTAssertTrue(appleArtifact.markdownContents.contains("- Provisioning availability: unavailable"))
        XCTAssertTrue(appleArtifact.markdownContents.contains("- Provisioning status: already-present"))
        XCTAssertTrue(appleArtifact.markdownContents.contains("- Provisioning action: devcontainer-provisioning.create"))
        XCTAssertLessThanOrEqual(
            appleAudit.identifier.count,
            CinematicRunRecapShareArtifactRuntimeRouteAudit.identifierMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            appleAudit.markdownLength,
            CinematicRunRecapShareArtifactRuntimeRouteAudit.markdownMaxCharacters
        )

        let nativeRepoURL = try makeTemporaryGitRepository(prefix: "RuntimeRouteNative")
        let nativeSnapshot = makeRuntimeSnapshot(
            repoURL: nativeRepoURL,
            phase: "Plan",
            preference: .nativeMacOS,
            containerToolPath: "/usr/local/bin/container"
        )
        let nativeSession = makeSession(
            38,
            endedAt: 38_500,
            executionEnvironmentSnapshots: [nativeSnapshot]
        )
        let nativeArtifact = CinematicRunRecapShareArtifactPlanner.plan(
            sharePlan: makeSharePlan(session: nativeSession, completed: ["Audit native route"]),
            sessions: [nativeSession]
        )

        XCTAssertTrue(nativeArtifact.markdownContents.contains("## Runtime Route"))
        XCTAssertTrue(nativeArtifact.markdownContents.contains("- Selected preference: native_macos (Native macOS)"))
        XCTAssertTrue(nativeArtifact.markdownContents.contains("- Effective route: native-macos (Native macOS)"))
        XCTAssertTrue(nativeArtifact.markdownContents.contains("- Support classification: missing"))
        XCTAssertTrue(nativeArtifact.markdownContents.contains("- Workspace label: host"))
        XCTAssertTrue(nativeArtifact.markdownContents.contains("- Fallback state: direct"))

        let fallbackRepoURL = try makeTemporaryGitRepository(prefix: "RuntimeRouteFallback")
        try writeDevcontainer(#"{"image":"swift:6.0","workspaceFolder":"/workspace/app"}"#, in: fallbackRepoURL)
        let fallbackSnapshot = makeRuntimeSnapshot(
            repoURL: fallbackRepoURL,
            phase: "Develop",
            attempt: 3,
            preference: .devcontainerPreferred,
            containerToolPath: nil
        )
        let fallbackSession = makeSession(
            39,
            endedAt: 39_500,
            executionEnvironmentSnapshots: [fallbackSnapshot]
        )
        let fallbackArtifact = CinematicRunRecapShareArtifactPlanner.plan(
            sharePlan: makeSharePlan(session: fallbackSession, completed: ["Audit fallback route"]),
            sessions: [fallbackSession]
        )

        XCTAssertTrue(fallbackArtifact.markdownContents.contains("## Runtime Route"))
        XCTAssertTrue(
            fallbackArtifact.markdownContents.contains(
                "- Selected preference: devcontainer_preferred (Dev Container Preferred)"
            )
        )
        XCTAssertTrue(fallbackArtifact.markdownContents.contains("- Effective route: native-macos (Native macOS)"))
        XCTAssertTrue(fallbackArtifact.markdownContents.contains("- Support classification: image-routeable"))
        XCTAssertTrue(fallbackArtifact.markdownContents.contains("- Fallback state: fallback"))
        XCTAssertTrue(fallbackArtifact.markdownContents.contains("- Fallback reason: Apple container CLI is unavailable."))

        let missingSnapshotSession = makeSession(40, endedAt: 40_500)
        let missingSnapshotArtifact = CinematicRunRecapShareArtifactPlanner.plan(
            sharePlan: makeSharePlan(session: missingSnapshotSession, completed: ["No runtime snapshot"]),
            sessions: [missingSnapshotSession]
        )

        XCTAssertNil(missingSnapshotArtifact.runtimeRouteAudit)
        XCTAssertFalse(missingSnapshotArtifact.markdownContents.contains("## Runtime Route"))
    }

    func testRuntimeRouteAuditPropagatesThroughSavedHistorySubsetAndRollupExports() throws {
        let repoURL = try makeTemporaryGitRepository(prefix: "RuntimeRoutePropagation")
        try writeDevcontainer(
            #"{"image":"swift:6.0","workspaceFolder":"/workspace/app","containerEnv":{"TOKEN":"secret-runtime-route-propagation"}}"#,
            in: repoURL
        )
        let workspace = CompassWorkspace(repoURL: repoURL)
        try workspace.initialize()
        let snapshot = makeRuntimeSnapshot(
            repoURL: repoURL,
            phase: "Verify",
            attempt: 4,
            preference: .devcontainerPreferred,
            containerToolPath: "/usr/local/bin/container",
            provisioning: true
        )
        let session = makeSession(
            41,
            endedAt: 41_500,
            executionEnvironmentSnapshots: [snapshot]
        )
        let result = workspace.recordRunRecapShareArtifact(
            sharePlan: makeSharePlan(session: session, completed: ["Persist runtime route audit"]),
            sessions: [session]
        )

        let artifactURL = try XCTUnwrap(result.artifactURL)
        let savedMarkdown = try read(artifactURL)
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let selectedExport = CinematicRunRecapShareArtifactSubsetExportPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: history.latestEntry?.identifier,
            scope: .selected
        )
        let filteredExport = CinematicRunRecapShareArtifactSubsetExportPlanner.plan(
            historyPlan: history,
            scope: .filtered
        )
        let rollup = CinematicRunRecapShareArtifactRollupPlanner.plan(historyPlan: history)

        XCTAssertEqual(result.status, .recorded)
        XCTAssertTrue(savedMarkdown.contains("## Runtime Route"))
        XCTAssertTrue(try XCTUnwrap(history.latestEntry).markdownContents.contains("## Runtime Route"))
        XCTAssertTrue(history.combinedMarkdownExport.contains("## Runtime Route"))
        XCTAssertTrue(selectedExport.markdownContents.contains("## Runtime Route"))
        XCTAssertTrue(filteredExport.markdownContents.contains("## Runtime Route"))
        XCTAssertTrue(rollup.exportText.contains("## Runtime Routes"))
        XCTAssertTrue(rollup.exportText.contains("route apple-container (Apple container)"))
        XCTAssertLessThanOrEqual(
            result.artifactPlan.runtimeRouteAudit?.identifier.count ?? 0,
            CinematicRunRecapShareArtifactRuntimeRouteAudit.identifierMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            result.artifactPlan.markdownLength,
            CinematicRunRecapShareArtifactPlan.markdownMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            history.combinedMarkdownLength,
            CinematicRunRecapShareArtifactHistoryPlan.combinedMarkdownMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            selectedExport.markdownLength,
            CinematicRunRecapShareArtifactSubsetExportPlan.markdownMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            rollup.exportTextLength,
            CinematicRunRecapShareArtifactRollupPlan.exportTextMaxCharacters
        )
    }

    func testRuntimeRouteAuditMarkdownAndExportsDoNotLeakRuntimeInternals() throws {
        let imageRepoURL = try makeTemporaryGitRepository(prefix: "RuntimeRouteLeakImage")
        let envSecret = "secret-runtime-route-container-env-value"
        let containerToolPath = "/usr/local/bin/container"
        try writeDevcontainer(
            #"{"image":"swift:6.0","workspaceFolder":"/workspace/app","containerEnv":{"TOKEN":"\#(envSecret)"}}"#,
            in: imageRepoURL
        )
        let imageText = try recordedRuntimeExportText(
            repoURL: imageRepoURL,
            snapshot: makeRuntimeSnapshot(
                repoURL: imageRepoURL,
                phase: "Verify",
                preference: .devcontainerPreferred,
                containerToolPath: containerToolPath,
                provisioning: true
            ),
            sessionNumber: 42
        )

        let buildRepoURL = try makeTemporaryGitRepository(prefix: "RuntimeRouteLeakBuild")
        let buildSecret = "secret-runtime-route-build-arg-value"
        try writeDevcontainer(
            #"{"build":{"dockerfile":"Dockerfile","context":"..","target":"runtime","args":{"TOKEN":"\#(buildSecret)"}}}"#,
            in: buildRepoURL
        )
        let buildText = try recordedRuntimeExportText(
            repoURL: buildRepoURL,
            snapshot: makeRuntimeSnapshot(
                repoURL: buildRepoURL,
                phase: "Develop",
                preference: .devcontainerPreferred,
                containerToolPath: containerToolPath
            ),
            sessionNumber: 43
        )

        let composeRepoURL = try makeTemporaryGitRepository(prefix: "RuntimeRouteLeakCompose")
        let composePath = "/Users/private/project/compose.override.yml"
        try writeDevcontainer(
            #"{"dockerComposeFile":["../compose.yml","\#(composePath)"],"service":"api"}"#,
            in: composeRepoURL
        )
        let composeText = try recordedRuntimeExportText(
            repoURL: composeRepoURL,
            snapshot: makeRuntimeSnapshot(
                repoURL: composeRepoURL,
                phase: "Reflect",
                preference: .devcontainerPreferred,
                containerToolPath: containerToolPath
            ),
            sessionNumber: 44
        )

        let featureRepoURL = try makeTemporaryGitRepository(prefix: "RuntimeRouteLeakFeature")
        let featureSecret = "secret-runtime-route-feature-option-value"
        try writeDevcontainer(
            #"{"image":"swift:6.0","features":{"ghcr.io/devcontainers/features/node:1":{"version":"\#(featureSecret)","nested":{"token":"hidden-feature-token"}}}}"#,
            in: featureRepoURL
        )
        let featureText = try recordedRuntimeExportText(
            repoURL: featureRepoURL,
            snapshot: makeRuntimeSnapshot(
                repoURL: featureRepoURL,
                phase: "Plan",
                preference: .devcontainerPreferred,
                containerToolPath: containerToolPath
            ),
            sessionNumber: 45
        )

        let combinedText = [imageText, buildText, composeText, featureText].joined(separator: "\n---\n")
        XCTAssertTrue(combinedText.contains("## Runtime Route"))
        XCTAssertTrue(combinedText.contains("arg:TOKEN"))
        XCTAssertTrue(combinedText.contains("composeFile:compose.override.yml"))
        XCTAssertTrue(combinedText.contains("feature:node:1"))
        for sensitive in [
            imageRepoURL.standardizedFileURL.path,
            buildRepoURL.standardizedFileURL.path,
            composeRepoURL.standardizedFileURL.path,
            featureRepoURL.standardizedFileURL.path,
            envSecret,
            buildSecret,
            featureSecret,
            "hidden-feature-token",
            "nested",
            composePath,
            "../compose.yml",
            containerToolPath
        ] {
            XCTAssertFalse(combinedText.contains(sensitive), "Leaked runtime-sensitive text: \(sensitive)")
        }
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
        endedAt: Double? = nil,
        executionEnvironmentSnapshots: [SessionExecutionEnvironmentSnapshot] = []
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
            feedback: nil,
            executionEnvironmentSnapshots: executionEnvironmentSnapshots
        )
    }

    private func makeRuntimeSnapshot(
        repoURL: URL,
        phase: String,
        attempt: Int? = 1,
        preference: CodexExecutionEnvironmentPreference,
        containerToolPath: String?,
        provisioning: Bool = false
    ) -> SessionExecutionEnvironmentSnapshot {
        let launchPlan = CodexExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: preference,
            containerToolResolver: { _ in containerToolPath }
        )
        return SessionExecutionEnvironmentSnapshot(
            phase: phase,
            attempt: attempt,
            launchPlan: launchPlan,
            provisioningPlan: provisioning
                ? CodexDevcontainerProvisioningPlan.plan(repoURL: repoURL, languageProfile: .empty)
                : nil
        )
    }

    private func recordedRuntimeExportText(
        repoURL: URL,
        snapshot: SessionExecutionEnvironmentSnapshot,
        sessionNumber: Int
    ) throws -> String {
        let workspace = CompassWorkspace(repoURL: repoURL)
        try workspace.initialize()
        let session = makeSession(
            sessionNumber,
            endedAt: Double(sessionNumber * 1_000 + 500),
            executionEnvironmentSnapshots: [snapshot]
        )
        let result = workspace.recordRunRecapShareArtifact(
            sharePlan: makeSharePlan(session: session, completed: ["Record sanitized runtime audit"]),
            sessions: [session]
        )
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let selectedExport = CinematicRunRecapShareArtifactSubsetExportPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: history.latestEntry?.identifier,
            scope: .selected
        )
        let rollup = CinematicRunRecapShareArtifactRollupPlanner.plan(historyPlan: history)
        return [
            result.artifactPlan.filename,
            result.artifactPlan.feedback,
            result.detail,
            result.help,
            result.artifactPlan.markdownContents,
            history.latestEntry?.markdownContents ?? "",
            history.combinedMarkdownExport,
            selectedExport.markdownContents,
            rollup.exportText
        ].joined(separator: "\n")
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

    private func makeTemporaryGitRepository(prefix: String = "CinematicRunRecapShareArtifactTests") throws -> URL {
        let directory = try makeTemporaryDirectory(prefix: prefix)
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

    private func writeDevcontainer(_ contents: String, in repoURL: URL) throws {
        let devcontainerDirectory = repoURL.appending(path: ".devcontainer", directoryHint: .isDirectory)
        try createDirectory(devcontainerDirectory)
        try write(
            contents,
            to: devcontainerDirectory.appending(path: "devcontainer.json")
        )
    }
}
