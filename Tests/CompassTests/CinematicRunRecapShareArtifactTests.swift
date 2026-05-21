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



    func testMutationTestingAuditWritesMarkdownAndPropagatesThroughExports() throws {
        let repoURL = try makeTemporaryGitRepository(prefix: "MutationAuditPropagation")
        let workspace = CompassWorkspace(repoURL: repoURL)
        try workspace.initialize()
        let launchPlan = AgentExecutionLaunchPlan.host()
        let snapshot = SessionExecutionEnvironmentSnapshot(
            phase: "Mutation",
            attempt: 1,
            launchPlan: launchPlan
        )
        let execution = makeMutationExecution(
            verify: "swift test --filter MutationAuditPropagation",
            exitCode: 0,
            startedAt: 41_000,
            endedAt: 42_250,
            outputTail: "mutation ok",
            launchPlan: launchPlan
        )
        let session = makeSession(
            46,
            endedAt: 46_500,
            executionEnvironmentSnapshots: [snapshot],
            mutationTestingExecutions: [execution]
        )
        let result = workspace.recordRunRecapShareArtifact(
            sharePlan: makeSharePlan(session: session, completed: ["Persist mutation audit"]),
            sessions: [session]
        )

        let artifactURL = try XCTUnwrap(result.artifactURL)
        let savedMarkdown = try read(artifactURL)
        let mutationAudit = try XCTUnwrap(result.artifactPlan.mutationTestingAudit)
        let runtimeAudit = try XCTUnwrap(result.artifactPlan.runtimeRouteAudit)
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
        let tour = CinematicRunRecapShareArtifactTourPlanner.plan(historyPlan: history)

        XCTAssertEqual(result.status, .recorded)
        XCTAssertTrue(savedMarkdown.contains("## Mutation Tests"))
        XCTAssertTrue(savedMarkdown.contains("- Mutation audit: \(mutationAudit.identifier)"))
        XCTAssertTrue(savedMarkdown.contains("- Status: succeeded (Succeeded)"))
        XCTAssertTrue(savedMarkdown.contains("- Route: native-route (Native)"))
        XCTAssertTrue(savedMarkdown.contains("- Language: swift (Swift)"))
        XCTAssertTrue(savedMarkdown.contains("- Seed command: swift test --filter MutationAuditPropagation"))
        XCTAssertTrue(savedMarkdown.contains("- Exit code: exit 0"))
        XCTAssertTrue(savedMarkdown.contains("- Runtime route audit:"))
        XCTAssertTrue(savedMarkdown.contains(String(runtimeAudit.identifier.prefix(80))))
        XCTAssertTrue(savedMarkdown.contains("route-aligned"))
        XCTAssertTrue(try XCTUnwrap(history.latestEntry).markdownContents.contains("## Mutation Tests"))
        XCTAssertTrue(history.combinedMarkdownExport.contains("## Mutation Tests"))
        XCTAssertTrue(selectedExport.markdownContents.contains("## Mutation Tests"))
        XCTAssertTrue(filteredExport.markdownContents.contains("## Mutation Tests"))
        XCTAssertEqual(rollup.mutationTestingAuditCount, 1)
        XCTAssertEqual(rollup.mutationTestingSummary, "succeeded 1")
        XCTAssertEqual(tour.mutationTestingCueStatusIdentifier, "succeeded")
        XCTAssertEqual(tour.mutationTestingCueAvailabilityIdentifier, "available")
        XCTAssertEqual(tour.mutationTestingTreatment.stateIdentifier, "succeeded")
        XCTAssertEqual(tour.mutationTestingTreatment.accentIdentifier, "mutation-green")
        XCTAssertTrue(rollup.insightText.contains("mutation succeeded 1"))
        XCTAssertTrue(rollup.exportText.contains("## Mutation Tests"))
        XCTAssertTrue(rollup.exportText.contains("mutation succeeded | route native-route | language swift"))
        XCTAssertLessThanOrEqual(
            mutationAudit.identifier.count,
            CinematicRunRecapShareArtifactMutationTestingAudit.identifierMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            mutationAudit.markdownLength,
            CinematicRunRecapShareArtifactMutationTestingAudit.markdownMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            rollup.mutationTestingSummary.count,
            CinematicRunRecapShareArtifactRollupPlan.statusBucketSummaryMaxCharacters
        )
    }

    func testMutationTestingAuditIsOmittedForUnavailableMissingAndOldArtifacts() throws {
        let session = makeSession(47, endedAt: 47_500)
        let artifact = CinematicRunRecapShareArtifactPlanner.plan(
            sharePlan: makeSharePlan(session: session, completed: ["No mutation audit"]),
            sessions: [session]
        )
        XCTAssertNil(artifact.mutationTestingAudit)
        XCTAssertFalse(artifact.markdownContents.contains("## Mutation Tests"))

        let unavailable = CinematicRunRecapShareArtifactPlanner.plan(
            sharePlan: CinematicRunRecapSharePlanner.plan(recapPlan: .empty(reason: "active-run")),
            sessions: [session]
        )
        XCTAssertFalse(unavailable.isAvailable)
        XCTAssertNil(unavailable.mutationTestingAudit)
        XCTAssertFalse(unavailable.markdownContents.contains("## Mutation Tests"))

        let workspace = try makeInitializedWorkspace()
        _ = try workspace.writeSessionArtifact(
            session: 48,
            name: "recap-share-old.md",
            contents: oldArtifactMarkdown(session: 48)
        )
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let rollup = CinematicRunRecapShareArtifactRollupPlanner.plan(historyPlan: history)

        XCTAssertTrue(history.isAvailable)
        XCTAssertNil(
            CinematicRunRecapShareArtifactMutationTestingCue(
                markdownContents: try XCTUnwrap(history.latestEntry).markdownContents
            )
        )
        XCTAssertFalse(history.combinedMarkdownExport.contains("## Mutation Tests"))
        XCTAssertEqual(rollup.mutationTestingAuditCount, 0)
        XCTAssertEqual(rollup.mutationTestingSummary, "none")
        XCTAssertFalse(rollup.exportText.contains("## Mutation Tests"))
    }

    func testMutationTestingAuditSanitizesLegacyRawExecutionFields() throws {
        let repoPath = "/Users/private/project"
        let containerToolPath = "/private/tooling/container"
        let secretEnv = "secret-mutation-container-env"
        let secretBuildArg = "secret-mutation-build-arg"
        let secretFeatureValue = "secret-mutation-feature-option"
        let secretNestedValue = "secret-mutation-nested-option"
        let composePath = "/Users/private/project/compose.override.yml"
        let legacyJSON = """
        {
          "session": 49,
          "startedAt": 49000,
          "endedAt": 49500,
          "commits": [],
          "status": "failed",
          "notes": [],
          "mutationTestingExecutions": [
            {
              "readinessIdentifier": "legacy",
              "statusIdentifier": "failed",
              "routeIdentifier": "native-fallback",
              "languageIdentifier": "swift",
              "seedCommandLabel": "swift test \(repoPath) \(containerToolPath) .devcontainer/devcontainer.json \(secretEnv) \(secretBuildArg) \(secretFeatureValue)",
              "exitCode": 65,
              "startedAt": 49000,
              "endedAt": 50500,
              "outputTail": "failure \(repoPath) \(containerToolPath) \(secretEnv) \(secretBuildArg) \(secretFeatureValue) \(secretNestedValue) \(composePath) ../compose.yml .devcontainer/devcontainer.json ghcr.io/devcontainers/features/node:1"
            }
          ]
        }
        """
        let session = try JSONDecoder().decode(SessionRecord.self, from: Data(legacyJSON.utf8))

        let artifact = CinematicRunRecapShareArtifactPlanner.plan(
            sharePlan: makeSharePlan(session: session, completed: ["Sanitize legacy mutation audit"]),
            sessions: [session]
        )
        let audit = try XCTUnwrap(artifact.mutationTestingAudit)
        let cue = try XCTUnwrap(
            CinematicRunRecapShareArtifactMutationTestingCue(markdownContents: artifact.markdownContents)
        )
        let treatment = CinematicRunRecapShareArtifactMutationTestingTreatmentDescriptor(cue: cue)
        let exposedText = [
            audit.identifier,
            audit.markdownSection,
            artifact.markdownContents,
            cue.detailCopy,
            cue.helpCopy,
            treatment.identifier,
            treatment.compactCopy,
            treatment.helpCopy
        ].joined(separator: "\n")

        XCTAssertTrue(artifact.markdownContents.contains("## Mutation Tests"))
        XCTAssertTrue(exposedText.contains("[path]"))
        XCTAssertTrue(exposedText.contains("[redacted]"))
        XCTAssertLessThanOrEqual(artifact.markdownLength, CinematicRunRecapShareArtifactPlan.markdownMaxCharacters)
        XCTAssertLessThanOrEqual(audit.tailSummary.count, CinematicRunRecapShareArtifactMutationTestingAudit.tailSummaryMaxCharacters)
        for sensitive in [
            repoPath,
            containerToolPath,
            secretEnv,
            secretBuildArg,
            secretFeatureValue,
            secretNestedValue,
            composePath,
            "../compose.yml",
            ".devcontainer/devcontainer.json",
            "ghcr.io/devcontainers/features/node:1"
        ] {
            XCTAssertFalse(exposedText.contains(sensitive), "Leaked mutation-sensitive text: \(sensitive)")
        }
    }

    func testWarningPulseAuditWritesActiveSnoozedAndSkipsClearedBundles() throws {
        let session = makeSession(50, endedAt: 50_500)
        let share = makeSharePlan(session: session, completed: ["Persist warning pulse audit"])
        let targetText = "RAW_TARGET_TEXT_SHOULD_NOT_LEAK"
        let notificationBody = "SECRET_NATIVE_NOTIFICATION_BODY_SHOULD_NOT_LEAK"
        let entry = makeWarningPulseEntry(
            suffix: "active",
            targetIdentifiers: ["target-\(targetText)"],
            warningIdentifiers: (0..<8).map { "visual-smoke.warning-pulse-\($0)" },
            targetAnchors: (0..<7).map { "visual-smoke-check-warning-pulse-\($0)" },
            relatedRowAnchors: (0..<6).map { "diagnostics-row-warning-pulse-\($0)" }
        )
        let activeAudit = makeWarningPulseAudit(entry: entry, snoozed: false)
        let activeArtifact = CinematicRunRecapShareArtifactPlanner.plan(
            sharePlan: share,
            sessions: [session],
            warningPulseAudit: activeAudit
        )
        let activeCue = try XCTUnwrap(
            CinematicRunRecapShareArtifactWarningPulseCue(
                markdownContents: activeArtifact.markdownContents
            )
        )

        XCTAssertEqual(activeArtifact.warningPulseAudit, activeAudit)
        XCTAssertTrue(activeArtifact.markdownContents.contains("## Diagnostics Warning Pulse"))
        XCTAssertTrue(activeArtifact.markdownContents.contains("- State: active"))
        XCTAssertTrue(activeArtifact.markdownContents.contains("- Bundle: \(entry.bundleIdentifier)"))
        XCTAssertTrue(activeArtifact.markdownContents.contains("- Capture count: 3"))
        XCTAssertTrue(activeArtifact.markdownContents.contains("- Warning count: 8"))
        XCTAssertTrue(activeArtifact.markdownContents.contains("- Omitted warning identifiers: 2"))
        XCTAssertTrue(activeArtifact.markdownContents.contains("- Omitted target anchors: 2"))
        XCTAssertTrue(activeArtifact.markdownContents.contains("- Omitted related rows: 1"))
        XCTAssertEqual(activeCue.stateIdentifier, "active")
        XCTAssertEqual(activeCue.captureCount, 3)
        XCTAssertEqual(activeCue.warningIdentifiers.count, CinematicRunRecapShareArtifactWarningPulseAudit.warningIdentifierLimit)
        XCTAssertEqual(activeCue.targetAnchors.count, CinematicRunRecapShareArtifactWarningPulseAudit.anchorLimit)
        XCTAssertEqual(activeCue.relatedRowAnchors.count, CinematicRunRecapShareArtifactWarningPulseAudit.anchorLimit)
        XCTAssertFalse(activeArtifact.markdownContents.contains(targetText))
        XCTAssertFalse(activeArtifact.markdownContents.contains(notificationBody))
        XCTAssertLessThanOrEqual(
            activeAudit.identifier.count,
            CinematicRunRecapShareArtifactWarningPulseAudit.identifierMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            activeAudit.markdownLength,
            CinematicRunRecapShareArtifactWarningPulseAudit.markdownMaxCharacters
        )
        XCTAssertLessThanOrEqual(
            activeArtifact.markdownLength,
            CinematicRunRecapShareArtifactPlan.markdownMaxCharacters
        )

        let snoozedAudit = makeWarningPulseAudit(entry: entry, snoozed: true)
        let snoozedArtifact = CinematicRunRecapShareArtifactPlanner.plan(
            sharePlan: share,
            sessions: [session],
            warningPulseAudit: snoozedAudit
        )
        let snoozedCue = try XCTUnwrap(
            CinematicRunRecapShareArtifactWarningPulseCue(
                markdownContents: snoozedArtifact.markdownContents
            )
        )
        XCTAssertTrue(snoozedArtifact.markdownContents.contains("- State: snoozed"))
        XCTAssertEqual(snoozedCue.stateIdentifier, "snoozed")

        let clearedArtifact = CinematicRunRecapShareArtifactPlanner.plan(
            sharePlan: share,
            sessions: [session]
        )
        XCTAssertNil(clearedArtifact.warningPulseAudit)
        XCTAssertNil(CinematicRunRecapShareArtifactWarningPulseCue(markdownContents: clearedArtifact.markdownContents))
        XCTAssertFalse(clearedArtifact.markdownContents.contains("## Diagnostics Warning Pulse"))

        let unavailable = CinematicRunRecapShareArtifactPlanner.plan(
            sharePlan: CinematicRunRecapSharePlanner.plan(recapPlan: .empty(reason: "active-run")),
            sessions: [session],
            warningPulseAudit: activeAudit
        )
        XCTAssertFalse(unavailable.isAvailable)
        XCTAssertNil(unavailable.warningPulseAudit)
        XCTAssertFalse(unavailable.markdownContents.contains("## Diagnostics Warning Pulse"))
    }

    func testWarningPulseAuditPropagatesThroughSavedHistorySubsetAndRollupExports() throws {
        let workspace = try makeInitializedWorkspace()
        let session = makeSession(51, endedAt: 51_500)
        let entry = makeWarningPulseEntry(suffix: "propagation")
        let audit = makeWarningPulseAudit(entry: entry, snoozed: false)

        let result = workspace.recordRunRecapShareArtifact(
            sharePlan: makeSharePlan(session: session, completed: ["Propagate warning pulse audit"]),
            sessions: [session],
            warningPulseAudit: audit
        )

        let savedMarkdown = try read(try XCTUnwrap(result.artifactURL))
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
        XCTAssertTrue(savedMarkdown.contains("## Diagnostics Warning Pulse"))
        XCTAssertTrue(try XCTUnwrap(history.latestEntry).markdownContents.contains("## Diagnostics Warning Pulse"))
        XCTAssertTrue(history.combinedMarkdownExport.contains("## Diagnostics Warning Pulse"))
        XCTAssertTrue(selectedExport.markdownContents.contains("## Diagnostics Warning Pulse"))
        XCTAssertTrue(filteredExport.markdownContents.contains("## Diagnostics Warning Pulse"))
        XCTAssertEqual(selectedExport.warningPulseAuditCount, 1)
        XCTAssertEqual(filteredExport.warningPulseAuditCount, 1)
        XCTAssertEqual(selectedExport.warningPulseStateSummary, "active 1")
        XCTAssertEqual(rollup.warningPulseAuditCount, 1)
        XCTAssertEqual(rollup.warningPulseStateSummary, "active 1")
        XCTAssertEqual(rollup.warningPulseAuditIdentifiers, [audit.identifier])
        XCTAssertTrue(rollup.insightText.contains("warning pulse active 1"))
        XCTAssertTrue(rollup.exportText.contains("## Diagnostics Warning Pulses"))
        XCTAssertTrue(rollup.exportText.contains("pulse active"))
        XCTAssertTrue(rollup.exportText.contains("warnings 2"))
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
        executionEnvironmentSnapshots: [SessionExecutionEnvironmentSnapshot] = [],
        mutationTestingExecutions: [SessionMutationTestingExecution] = []
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
            executionEnvironmentSnapshots: executionEnvironmentSnapshots,
            mutationTestingExecutions: mutationTestingExecutions
        )
    }

    private func makeMutationExecution(
        verify: String,
        exitCode: Int?,
        startedAt: Double,
        endedAt: Double,
        outputTail: String,
        launchPlan: AgentExecutionLaunchPlan
    ) -> SessionMutationTestingExecution {
        let readiness = AgentMutationTestingPlan(
            state: PlanState(
                completed: [],
                immediate: PlanNext(plan: "Run mutation testing", verify: verify),
                midTerm: "",
                longTerm: ""
            ),
            languageProfile: profile(.swift),
            launchPlan: launchPlan
        )
        return SessionMutationTestingExecution(
            readiness: readiness,
            exitCode: exitCode,
            startedAt: startedAt,
            endedAt: endedAt,
            outputTail: outputTail,
            launchPlan: launchPlan
        )
    }

    private func profile(_ language: RepositoryLanguage) -> RepositoryLanguageProfile {
        var counts = RepositoryLanguageCounts()
        counts[language] = language == .unknown ? 0 : 1
        return RepositoryLanguageProfile(
            counts: counts,
            manifestHints: [],
            primaryLanguage: language,
            scannedFileCount: language == .unknown ? 0 : 1,
            scannedDirectoryCount: 1,
            wasTruncated: false
        )
    }

    private func makeRuntimeSnapshot(
        repoURL: URL,
        phase: String,
        attempt: Int? = 1,
        preference: AgentExecutionEnvironmentPreference,
        vmReadiness: SharedCompassVMReadiness? = nil,
        sharedVMRouteFactory: (URL) -> SharedVMRoute? = { _ in nil }
    ) -> SessionExecutionEnvironmentSnapshot {
        let launchPlan = AgentExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: preference,
            vmReadiness: vmReadiness,
            sharedVMRouteFactory: sharedVMRouteFactory
        )
        return SessionExecutionEnvironmentSnapshot(
            phase: phase,
            attempt: attempt,
            launchPlan: launchPlan
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

    private func oldArtifactMarkdown(session: Int) -> String {
        """
        # Compass Run Recap Share

        - Artifact: old-artifact-\(session)
        - Availability: available
        - Session: \(session)
        - Filename: recap-share-old.md
        - Share: share-id
        - Recap: recap-id
        - Focus: focus-id
        - End card: end-card-id
        - Title: Old Artifact
        - Status: succeeded
        - Detail: Detail text
        - Commit: none

        ## Events
        - event

        ## Share Text

        ```text
        Old artifact body.
        ```
        """
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

    private func makeWarningPulseEntry(
        suffix: String,
        targetIdentifiers: [String] = ["target-warning-pulse"],
        warningIdentifiers: [String] = ["visual-smoke.warning-pulse-a", "visual-smoke.warning-pulse-b"],
        targetAnchors: [String] = ["visual-smoke-check-warning-pulse"],
        relatedRowAnchors: [String] = ["diagnostics-row-warning-pulse"]
    ) -> CinematicDiagnosticsWarningBundleHistory.Entry {
        CinematicDiagnosticsWarningBundleHistory.Entry(
            sequence: 4,
            bundleIdentifier: "warning-bundle-\(suffix)",
            captureCount: 3,
            targetCount: targetIdentifiers.count,
            warningCount: warningIdentifiers.count,
            targetIdentifiers: targetIdentifiers,
            warningIdentifiers: warningIdentifiers,
            repeatedWarningIdentifiers: [],
            targetAnchors: targetAnchors,
            relatedRowAnchors: relatedRowAnchors
        )
    }

    private func makeWarningPulseAudit(
        entry: CinematicDiagnosticsWarningBundleHistory.Entry,
        snoozed: Bool
    ) -> CinematicRunRecapShareArtifactWarningPulseAudit {
        let quieting = snoozed
            ? CinematicDiagnosticsWarningPulseQuietingDescriptor(entry: entry)
            : nil
        let status = CinematicDiagnosticsWarningPulseQuietingStatusDescriptor(
            currentBundle: entry,
            quietingDescriptor: quieting
        )
        return CinematicRunRecapShareArtifactWarningPulseAudit(
            entry: entry,
            status: status
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
