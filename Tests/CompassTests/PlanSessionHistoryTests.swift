import Foundation
@testable import Compass
import XCTest

final class PlanSessionHistoryTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories = []
        try super.tearDownWithError()
    }

    func testOrdersSessionsReverseChronologically() {
        let sessions = [
            makeSession(1, startedAt: 1_000),
            makeSession(3, startedAt: 2_000),
            makeSession(2, startedAt: 3_000),
            makeSession(4, startedAt: 3_000)
        ]

        let items = PlanSessionHistory.displayItems(for: sessions)

        XCTAssertEqual(items.map(\.sessionNumber), [4, 2, 3, 1])
    }

    func testHandlesEmptyAndPlanlessSessions() {
        XCTAssertEqual(PlanSessionHistory.displayItems(for: []), [])

        let items = PlanSessionHistory.displayItems(
            for: [
                makeSession(
                    1,
                    startedAt: 1_000,
                    plan: nil,
                    verify: "   ",
                    feedback: "\n"
                )
            ]
        )

        XCTAssertEqual(items.count, 1)
        XCTAssertNil(items[0].planExcerpt)
        XCTAssertNil(items[0].verifyCommand)
        XCTAssertNil(items[0].feedback)
        XCTAssertEqual(items[0].statusText, "Succeeded")
    }

    func testPreservesFailedVerifyMetadata() throws {
        let items = PlanSessionHistory.displayItems(
            for: [
                makeSession(
                    1,
                    startedAt: 1_000,
                    status: .failed,
                    verify: "swift test",
                    verifyOutput: VerifyOutput(
                        command: "swift test --filter PlanSessionHistoryTests",
                        exitCode: 65,
                        tail: "failure tail"
                    )
                )
            ]
        )

        let failedVerify = try XCTUnwrap(items[0].failedVerify)
        XCTAssertEqual(failedVerify.command, "swift test --filter PlanSessionHistoryTests")
        XCTAssertEqual(failedVerify.exitCodeText, "exit 65")
        XCTAssertEqual(failedVerify.tail, "failure tail")
    }

    func testPreservesCommitsNotesAndFeedback() {
        let commit = SessionCommit(
            sha: "abcdef123456",
            short: "abcdef1",
            subject: "Ship plan history"
        )
        let items = PlanSessionHistory.displayItems(
            for: [
                makeSession(
                    1,
                    startedAt: 1_000,
                    commits: [commit],
                    notes: ["first note", "second note"],
                    feedback: "  useful handoff  "
                )
            ]
        )

        XCTAssertEqual(items[0].commits, [commit])
        XCTAssertEqual(items[0].notes, ["first note", "second note"])
        XCTAssertEqual(items[0].feedback, "useful handoff")
    }

    func testUsesLatestRuntimeRouteSummaryForHistoryItems() throws {
        let planSnapshot = SessionExecutionEnvironmentSnapshot(
            phase: "Plan",
            launchPlan: CodexExecutionLaunchPlan.native()
        )
        let verifySnapshot = SessionExecutionEnvironmentSnapshot(
            phase: "Verify",
            attempt: 2,
            launchPlan: CodexExecutionLaunchPlan.native(
                selectedPreference: .devcontainerPreferred,
                fallbackReason: "Apple container CLI is unavailable."
            )
        )

        let items = PlanSessionHistory.displayItems(
            for: [
                makeSession(
                    1,
                    startedAt: 1_000,
                    executionEnvironmentSnapshots: [planSnapshot, verifySnapshot]
                ),
                makeSession(
                    2,
                    startedAt: 2_000,
                    executionEnvironmentSnapshots: [planSnapshot]
                )
            ]
        )

        XCTAssertEqual(items.map(\.sessionNumber), [2, 1])
        XCTAssertEqual(items[0].runtimeRouteSummary, planSnapshot.routeSummary)
        XCTAssertEqual(items[1].runtimeRouteSummary, verifySnapshot.routeSummary)
        XCTAssertTrue(items[1].runtimeRouteSummary?.contains("Verify attempt 2") == true)
        XCTAssertTrue(items[1].runtimeRouteSummary?.contains("fallback Apple container CLI is unavailable.") == true)
        XCTAssertLessThanOrEqual(
            items[1].runtimeRouteSummary?.count ?? 0,
            SessionExecutionEnvironmentSnapshot.summaryLimit
        )
    }

    func testRuntimeDescriptorsCoverAppleContainerNativeAndFallbackRoutes() throws {
        let imageSnapshot = try makeRuntimeSnapshot(
            repoPrefix: "PlanSessionHistoryRuntimeImage",
            devcontainerJSON: #"{"image":"swift:6.0","workspaceFolder":"/workspace/app"}"#,
            preference: .devcontainerPreferred,
            containerToolPath: "/usr/local/bin/container"
        )
        let buildSnapshot = try makeRuntimeSnapshot(
            repoPrefix: "PlanSessionHistoryRuntimeBuild",
            devcontainerJSON: #"{"build":{"dockerfile":"Dockerfile","context":"..","target":"runtime","args":{"TOKEN":"secret-build-arg"}}}"#,
            preference: .devcontainerPreferred,
            containerToolPath: "/usr/local/bin/container"
        )
        let nativeSnapshot = try makeRuntimeSnapshot(
            repoPrefix: "PlanSessionHistoryRuntimeNative",
            devcontainerJSON: #"{"image":"swift:6.0"}"#,
            preference: .nativeMacOS,
            containerToolPath: "/usr/local/bin/container"
        )
        let fallbackSnapshot = try makeRuntimeSnapshot(
            repoPrefix: "PlanSessionHistoryRuntimeFallback",
            devcontainerJSON: #"{"image":"swift:6.0"}"#,
            preference: .devcontainerPreferred,
            containerToolPath: nil
        )

        let items = PlanSessionHistory.displayItems(
            for: [
                makeSession(1, startedAt: 1_000, executionEnvironmentSnapshots: [imageSnapshot]),
                makeSession(2, startedAt: 2_000, executionEnvironmentSnapshots: [buildSnapshot]),
                makeSession(3, startedAt: 3_000, executionEnvironmentSnapshots: [nativeSnapshot]),
                makeSession(4, startedAt: 4_000, executionEnvironmentSnapshots: [fallbackSnapshot])
            ]
        )

        let descriptorsBySession = Dictionary(
            uniqueKeysWithValues: items.map { ($0.sessionNumber, $0.runtimeRouteDescriptor) }
        )
        XCTAssertEqual(descriptorsBySession[1]?.snapshotAvailabilityIdentifier, "available")
        XCTAssertEqual(descriptorsBySession[1]?.selectedPreferenceIdentifier, "devcontainer_preferred")
        XCTAssertEqual(descriptorsBySession[1]?.effectiveRouteIdentifier, "apple-container")
        XCTAssertEqual(descriptorsBySession[1]?.supportClassificationIdentifier, "image-routeable")
        XCTAssertEqual(descriptorsBySession[1]?.fallbackStateIdentifier, "direct")

        XCTAssertEqual(descriptorsBySession[2]?.effectiveRouteIdentifier, "apple-container")
        XCTAssertEqual(descriptorsBySession[2]?.supportClassificationIdentifier, "build-based")
        XCTAssertEqual(descriptorsBySession[2]?.fallbackStateIdentifier, "direct")

        XCTAssertEqual(descriptorsBySession[3]?.selectedPreferenceIdentifier, "native_macos")
        XCTAssertEqual(descriptorsBySession[3]?.effectiveRouteIdentifier, "native-macos")
        XCTAssertEqual(descriptorsBySession[3]?.supportClassificationIdentifier, "image-routeable")
        XCTAssertEqual(descriptorsBySession[3]?.fallbackStateIdentifier, "direct")

        XCTAssertEqual(descriptorsBySession[4]?.selectedPreferenceIdentifier, "devcontainer_preferred")
        XCTAssertEqual(descriptorsBySession[4]?.effectiveRouteIdentifier, "native-macos")
        XCTAssertEqual(descriptorsBySession[4]?.supportClassificationIdentifier, "image-routeable")
        XCTAssertEqual(descriptorsBySession[4]?.fallbackStateIdentifier, "fallback")
    }

    func testRuntimeFiltersUseLatestSnapshotAndPreserveOrdering() throws {
        let appleImageSnapshot = try makeRuntimeSnapshot(
            repoPrefix: "PlanSessionHistoryFilterImage",
            devcontainerJSON: #"{"image":"swift:6.0","workspaceFolder":"/workspace/app"}"#,
            preference: .devcontainerPreferred,
            containerToolPath: "/usr/local/bin/container"
        )
        let appleBuildSnapshot = try makeRuntimeSnapshot(
            repoPrefix: "PlanSessionHistoryFilterBuild",
            devcontainerJSON: #"{"build":{"dockerfile":"Dockerfile","context":"..","target":"runtime"}}"#,
            preference: .devcontainerPreferred,
            containerToolPath: "/usr/local/bin/container"
        )
        let nativeSnapshot = try makeRuntimeSnapshot(
            repoPrefix: "PlanSessionHistoryFilterNative",
            devcontainerJSON: #"{"image":"swift:6.0"}"#,
            preference: .nativeMacOS,
            containerToolPath: "/usr/local/bin/container"
        )
        let nativeFallbackSnapshot = try makeRuntimeSnapshot(
            repoPrefix: "PlanSessionHistoryFilterFallback",
            devcontainerJSON: #"{"image":"swift:6.0"}"#,
            preference: .devcontainerPreferred,
            containerToolPath: nil
        )

        let items = PlanSessionHistory.displayItems(
            for: [
                makeSession(1, startedAt: 1_000),
                makeSession(2, startedAt: 2_000, executionEnvironmentSnapshots: [nativeSnapshot]),
                makeSession(3, startedAt: 3_000, executionEnvironmentSnapshots: [appleImageSnapshot]),
                makeSession(4, startedAt: 4_000, executionEnvironmentSnapshots: [nativeFallbackSnapshot]),
                makeSession(5, startedAt: 5_000, executionEnvironmentSnapshots: [appleBuildSnapshot]),
                makeSession(
                    6,
                    startedAt: 6_000,
                    executionEnvironmentSnapshots: [appleImageSnapshot, nativeFallbackSnapshot]
                )
            ]
        )

        let allDisplay = PlanSessionHistoryDisplay(items: items, mode: .all)
        XCTAssertEqual(allDisplay.visibleItems.map(\.sessionNumber), [6, 5, 4, 3, 2, 1])
        XCTAssertEqual(
            allDisplay.visibleItems.last?.runtimeRouteDescriptor.snapshotAvailabilityIdentifier,
            "missing"
        )

        let appleDisplay = PlanSessionHistoryDisplay(items: items, mode: .all, filter: .appleContainer)
        XCTAssertEqual(appleDisplay.visibleItems.map(\.sessionNumber), [5, 3])
        XCTAssertEqual(appleDisplay.totalCount, 2)

        let nativeDisplay = PlanSessionHistoryDisplay(items: items, mode: .all, filter: .nativeRuntime)
        XCTAssertEqual(nativeDisplay.visibleItems.map(\.sessionNumber), [6, 4, 2])
        XCTAssertEqual(nativeDisplay.totalCount, 3)

        XCTAssertEqual(
            allDisplay.filterOptions.first { $0.filter == .appleContainer }?.count,
            2
        )
        XCTAssertEqual(
            allDisplay.filterOptions.first { $0.filter == .nativeRuntime }?.count,
            3
        )
        XCTAssertEqual(
            allDisplay.filterOptions.first { $0.filter == .all }?.count,
            6
        )
    }

    func testRuntimeBadgeSummariesAreBoundedAndDoNotLeakSnapshotDetails() throws {
        let secretPath = "/Users/private/project"
        let secretValue = "secret-container-value"
        let snapshotJSON = """
        {
          "phase": "Plan",
          "phaseIdentifier": "plan",
          "attempt": 1,
          "selectedPreferenceIdentifier": "devcontainer_preferred",
          "selectedPreferenceTitle": "\(secretPath)",
          "effectiveRouteIdentifier": "apple-container",
          "effectiveRouteTitle": "\(secretPath)",
          "supportClassificationIdentifier": "build-based",
          "visibleSupportTokens": ["env:TOKEN", "arg:SECRET", "composeFile:\(secretPath)/compose.yml"],
          "omittedSupportTokenCount": 17,
          "imageLabel": "\(secretValue)",
          "workspaceLabel": "\(secretPath)",
          "fallbackReason": "Fallback includes \(secretPath) and \(secretValue)"
        }
        """
        let snapshot = try JSONDecoder().decode(
            SessionExecutionEnvironmentSnapshot.self,
            from: Data(snapshotJSON.utf8)
        )
        let descriptor = PlanSessionHistory.displayItems(
            for: [
                makeSession(1, startedAt: 1_000, executionEnvironmentSnapshots: [snapshot])
            ]
        )[0].runtimeRouteDescriptor
        let displayText = [descriptor.badgeText, descriptor.helpText].joined(separator: "\n")

        XCTAssertLessThanOrEqual(
            descriptor.badgeText.count,
            PlanSessionHistoryItem.RuntimeRouteDescriptor.badgeTextLimit
        )
        XCTAssertLessThanOrEqual(
            descriptor.helpText.count,
            PlanSessionHistoryItem.RuntimeRouteDescriptor.helpTextLimit
        )
        XCTAssertTrue(displayText.contains("Dev Container Preferred"))
        XCTAssertTrue(displayText.contains("Apple container"))
        XCTAssertTrue(displayText.contains("build-based"))
        XCTAssertTrue(displayText.contains("omitted 17"))
        XCTAssertTrue(displayText.contains("Fallback: fallback"))
        XCTAssertFalse(displayText.contains(secretPath))
        XCTAssertFalse(displayText.contains(secretValue))
        XCTAssertFalse(displayText.contains("env:TOKEN"))
        XCTAssertFalse(displayText.contains("arg:SECRET"))
        XCTAssertFalse(displayText.contains("compose.yml"))
    }

    func testLatestMutationTestingDescriptorUsesLatestExecution() throws {
        let first = makeMutationExecution(
            verify: "swift test --filter OldMutation",
            exitCode: 0,
            startedAt: 1_000,
            endedAt: 1_250,
            outputTail: "old mutation ok"
        )
        let latest = makeMutationExecution(
            verify: "swift test --filter LatestMutation",
            exitCode: 12,
            startedAt: 2_000,
            endedAt: 3_500,
            outputTail: """
            failed in /Users/private/project
            secret-tail-token
            latest mutation failure
            """
        )

        let descriptor = try XCTUnwrap(
            PlanSessionHistory.displayItems(
                for: [
                    makeSession(
                        1,
                        startedAt: 1_000,
                        mutationTestingExecutions: [first, latest]
                    )
                ]
            ).first?.mutationTestingDescriptor
        )

        XCTAssertEqual(descriptor.statusIdentifier, "failed")
        XCTAssertEqual(descriptor.routeIdentifier, "native-route")
        XCTAssertEqual(descriptor.languageIdentifier, "swift")
        XCTAssertEqual(descriptor.seedCommandLabel, "swift test --filter LatestMutation")
        XCTAssertEqual(descriptor.exitCodeText, "exit 12")
        XCTAssertEqual(descriptor.durationText, "1.5 s")
        XCTAssertTrue(descriptor.badgeText.contains("Mutation failed"))
        XCTAssertTrue(descriptor.tailSummary.contains("latest mutation failure"))
        XCTAssertFalse(descriptor.tailSummary.contains("/Users/private/project"))
        XCTAssertFalse(descriptor.tailSummary.contains("secret-tail-token"))
        XCTAssertLessThanOrEqual(
            descriptor.badgeText.count,
            PlanSessionHistoryItem.MutationTestingDescriptor.badgeTextLimit
        )
        XCTAssertLessThanOrEqual(
            descriptor.helpText.count,
            PlanSessionHistoryItem.MutationTestingDescriptor.helpTextLimit
        )
        XCTAssertLessThanOrEqual(
            descriptor.tailSummary.count,
            PlanSessionHistoryItem.MutationTestingDescriptor.tailSummaryLimit
        )
    }

    func testMutationTestingDescriptorStaysEmptyForOldAndExecutionlessSessions() throws {
        let executionless = makeSession(1, startedAt: 1_000)
        let legacyJSON = """
        {
          "session": 2,
          "startedAt": 2000,
          "endedAt": 2500,
          "commits": [],
          "status": "succeeded",
          "notes": []
        }
        """
        let legacy = try JSONDecoder().decode(SessionRecord.self, from: Data(legacyJSON.utf8))

        let items = PlanSessionHistory.displayItems(for: [executionless, legacy])

        XCTAssertEqual(items.map(\.sessionNumber), [2, 1])
        XCTAssertNil(items[0].mutationTestingDescriptor)
        XCTAssertNil(items[1].mutationTestingDescriptor)
    }

    func testMutationTestingDescriptorSanitizesLegacyRawExecutionFields() throws {
        let repoPath = "/Users/private/project"
        let containerToolPath = "/private/tooling/container"
        let secretEnv = "secret-mutation-container-env"
        let featureValue = "secret-mutation-feature-option"
        let legacyJSON = """
        {
          "session": 7,
          "startedAt": 7000,
          "endedAt": 7500,
          "commits": [],
          "status": "failed",
          "notes": [],
          "mutationTestingExecutions": [
            {
              "readinessIdentifier": "legacy",
              "statusIdentifier": "failed",
              "routeIdentifier": "native-fallback",
              "languageIdentifier": "swift",
              "seedCommandLabel": "swift test \(repoPath) \(containerToolPath) .devcontainer/devcontainer.json \(secretEnv)",
              "exitCode": 65,
              "startedAt": 7000,
              "endedAt": 8200,
              "outputTail": "failure \(repoPath) \(containerToolPath) ../compose.yml ghcr.io/devcontainers/features/node:1 \(secretEnv) \(featureValue)"
            }
          ]
        }
        """
        let session = try JSONDecoder().decode(SessionRecord.self, from: Data(legacyJSON.utf8))

        let descriptor = try XCTUnwrap(
            PlanSessionHistory.displayItems(for: [session]).first?.mutationTestingDescriptor
        )
        let exposedText = [
            descriptor.seedCommandLabel,
            descriptor.tailSummary,
            descriptor.badgeText,
            descriptor.helpText
        ].joined(separator: "\n")

        XCTAssertEqual(descriptor.statusIdentifier, "failed")
        XCTAssertEqual(descriptor.routeIdentifier, "native-fallback")
        XCTAssertTrue(exposedText.contains("[path]"))
        for leaked in [
            repoPath,
            containerToolPath,
            ".devcontainer/devcontainer.json",
            "../compose.yml",
            "ghcr.io/devcontainers/features/node:1",
            secretEnv,
            featureValue
        ] {
            XCTAssertFalse(exposedText.contains(leaked), "Leaked \(leaked)")
        }
    }

    func testBoundsPlanExcerpt() {
        let items = PlanSessionHistory.displayItems(
            for: [
                makeSession(
                    1,
                    startedAt: 1_000,
                    plan: "Build \n a\t very detailed plan with many words and extra detail."
                )
            ],
            planExcerptLimit: 24
        )

        XCTAssertEqual(items[0].planExcerpt, "Build a very detailed...")
        XCTAssertLessThanOrEqual(items[0].planExcerpt?.count ?? 0, 24)
    }

    func testDisplayDefaultsToRecentLimit() {
        let sessionCount = PlanSessionHistoryDisplay.defaultRecentLimit + 3
        let items = PlanSessionHistory.displayItems(
            for: (1...sessionCount).map { number in
                makeSession(number, startedAt: Double(number * 1_000))
            }
        )

        let display = PlanSessionHistoryDisplay(items: items)

        XCTAssertEqual(display.totalCount, sessionCount)
        XCTAssertEqual(display.visibleCount, PlanSessionHistoryDisplay.defaultRecentLimit)
        XCTAssertEqual(display.hiddenCount, 3)
        XCTAssertEqual(
            display.visibleItems.map(\.sessionNumber),
            Array((sessionCount - PlanSessionHistoryDisplay.defaultRecentLimit + 1...sessionCount).reversed())
        )
        XCTAssertEqual(display.countSummary, "Showing latest 8 of 11")
        XCTAssertTrue(display.shouldOfferModeToggle)
        XCTAssertEqual(display.filter, .all)
        XCTAssertEqual(display.unfilteredTotalCount, sessionCount)
        XCTAssertEqual(display.filterOptions.map(\.filter), PlanSessionHistoryFilter.allCases)
        XCTAssertEqual(display.filterOptions.map(\.count), [sessionCount, 0, 0, 0, sessionCount, 0, 0])
    }

    func testDisplayShowAllModeIncludesEveryRun() {
        let items = PlanSessionHistory.displayItems(
            for: (1...7).map { number in
                makeSession(number, startedAt: Double(number * 1_000))
            }
        )

        let display = PlanSessionHistoryDisplay(items: items, mode: .all, recentLimit: 4)

        XCTAssertEqual(display.visibleItems.map(\.sessionNumber), [7, 6, 5, 4, 3, 2, 1])
        XCTAssertEqual(display.totalCount, 7)
        XCTAssertEqual(display.visibleCount, 7)
        XCTAssertEqual(display.hiddenCount, 0)
        XCTAssertNil(display.hiddenStatusSummary)
        XCTAssertEqual(display.countSummary, "Showing all 7")
        XCTAssertTrue(display.shouldOfferModeToggle)
    }

    func testDisplaySummarizesHiddenStatuses() {
        let items = PlanSessionHistory.displayItems(
            for: [
                makeSession(1, startedAt: 1_000, status: .awaitingApproval),
                makeSession(2, startedAt: 2_000, status: .succeeded),
                makeSession(3, startedAt: 3_000, status: .cancelled),
                makeSession(4, startedAt: 4_000, status: .failed),
                makeSession(5, startedAt: 5_000, status: .failed),
                makeSession(6, startedAt: 6_000, status: .succeeded)
            ]
        )

        let display = PlanSessionHistoryDisplay(items: items, recentLimit: 1)

        XCTAssertEqual(display.visibleItems.map(\.sessionNumber), [6])
        XCTAssertEqual(display.hiddenCount, 5)
        XCTAssertEqual(
            display.hiddenStatusSummary,
            "2 failed, 1 cancelled, 1 succeeded, 1 awaiting approval"
        )
    }

    func testDisplayHandlesNoHiddenAndEmptyStates() {
        let items = PlanSessionHistory.displayItems(
            for: [
                makeSession(1, startedAt: 1_000),
                makeSession(2, startedAt: 2_000)
            ]
        )

        let noHiddenDisplay = PlanSessionHistoryDisplay(items: items, recentLimit: 3)
        XCTAssertEqual(noHiddenDisplay.totalCount, 2)
        XCTAssertEqual(noHiddenDisplay.visibleCount, 2)
        XCTAssertEqual(noHiddenDisplay.hiddenCount, 0)
        XCTAssertNil(noHiddenDisplay.hiddenStatusSummary)
        XCTAssertEqual(noHiddenDisplay.countSummary, "2 runs")
        XCTAssertFalse(noHiddenDisplay.shouldOfferModeToggle)

        let emptyDisplay = PlanSessionHistoryDisplay(items: [])
        XCTAssertEqual(emptyDisplay.totalCount, 0)
        XCTAssertEqual(emptyDisplay.visibleCount, 0)
        XCTAssertEqual(emptyDisplay.hiddenCount, 0)
        XCTAssertNil(emptyDisplay.hiddenStatusSummary)
        XCTAssertEqual(emptyDisplay.countSummary, "0 runs")
        XCTAssertFalse(emptyDisplay.shouldOfferModeToggle)
    }

    func testDisplayPreservesIncomingOrder() {
        let items = [
            makeHistoryItem(2, status: .failed),
            makeHistoryItem(5),
            makeHistoryItem(1, status: .failed),
            makeHistoryItem(4, status: .failed)
        ]

        let recentDisplay = PlanSessionHistoryDisplay(items: items, recentLimit: 2)
        XCTAssertEqual(recentDisplay.visibleItems.map(\.sessionNumber), [2, 5])

        let allDisplay = PlanSessionHistoryDisplay(items: items, mode: .all, recentLimit: 2)
        XCTAssertEqual(allDisplay.visibleItems.map(\.sessionNumber), [2, 5, 1, 4])

        let filteredRecentDisplay = PlanSessionHistoryDisplay(
            items: items,
            recentLimit: 2,
            filter: .failedRejected
        )
        XCTAssertEqual(filteredRecentDisplay.visibleItems.map(\.sessionNumber), [2, 1])

        let filteredAllDisplay = PlanSessionHistoryDisplay(
            items: items,
            mode: .all,
            recentLimit: 2,
            filter: .failedRejected
        )
        XCTAssertEqual(filteredAllDisplay.visibleItems.map(\.sessionNumber), [2, 1, 4])
    }

    func testDisplayPreservesFailedVerifyMetadataForVisibleRows() throws {
        let items = PlanSessionHistory.displayItems(
            for: [
                makeSession(
                    1,
                    startedAt: 1_000,
                    status: .failed,
                    verify: "swift test",
                    verifyOutput: VerifyOutput(
                        command: "swift test --filter PlanSessionHistoryTests",
                        exitCode: 65,
                        tail: "failure tail"
                    )
                )
            ]
        )

        let display = PlanSessionHistoryDisplay(items: items)

        let failedVerify = try XCTUnwrap(display.visibleItems[0].failedVerify)
        XCTAssertEqual(failedVerify.command, "swift test --filter PlanSessionHistoryTests")
        XCTAssertEqual(failedVerify.exitCodeText, "exit 65")
        XCTAssertEqual(failedVerify.tail, "failure tail")
    }

    func testDisplayFiltersAttentionRunsFromRunCues() {
        let items = [
            makeHistoryItem(4),
            makeHistoryItem(3),
            makeHistoryItem(2),
            makeHistoryItem(1)
        ]
        let display = PlanSessionHistoryDisplay(
            items: items,
            mode: .all,
            filter: .attention,
            runCues: [
                4: makeRunCue(kind: .resumeDevelop, severity: .paused),
                2: makeRunCue(kind: .failedVerify)
            ]
        )

        XCTAssertEqual(display.totalCount, 2)
        XCTAssertEqual(display.visibleItems.map(\.sessionNumber), [4, 2])
        XCTAssertEqual(display.countSummary, "2 matching runs")
        XCTAssertEqual(
            display.filterOptions.first { $0.filter == .attention }?.count,
            2
        )
    }

    func testDisplayGroupsFailedAndRejectedRuns() {
        let items = [
            makeHistoryItem(7),
            makeHistoryItem(6),
            makeHistoryItem(5),
            makeHistoryItem(4, status: .rejectedByPlan),
            makeHistoryItem(3, status: .failed),
            makeHistoryItem(2),
            makeHistoryItem(1)
        ]
        let display = PlanSessionHistoryDisplay(
            items: items,
            mode: .all,
            filter: .failedRejected,
            runCues: [
                7: makeRunCue(kind: .promotionFailed),
                6: makeRunCue(kind: .dirtyWorktree, severity: .warning),
                5: makeRunCue(kind: .failedVerify),
                2: makeRunCue(kind: .developFailed)
            ]
        )

        XCTAssertEqual(display.visibleItems.map(\.sessionNumber), [7, 6, 5, 4, 3, 2])
        XCTAssertEqual(display.totalCount, 6)
    }

    func testDisplayGroupsActiveAndPausedRuns() {
        let items = [
            makeHistoryItem(5),
            makeHistoryItem(4, status: .awaitingApproval),
            makeHistoryItem(3, status: .developing),
            makeHistoryItem(2, status: .planning),
            makeHistoryItem(1)
        ]
        let display = PlanSessionHistoryDisplay(
            items: items,
            mode: .all,
            filter: .activePaused,
            runCues: [
                5: makeRunCue(kind: .resumeDevelop, severity: .paused)
            ]
        )

        XCTAssertEqual(display.visibleItems.map(\.sessionNumber), [5, 4, 3, 2])
        XCTAssertEqual(display.totalCount, 4)
    }

    func testDisplayGroupsCompletedAndFinishedRuns() {
        let items = [
            makeHistoryItem(6, status: .succeeded),
            makeHistoryItem(5, status: .cancelled),
            makeHistoryItem(4, status: .skipped),
            makeHistoryItem(3, status: .failed),
            makeHistoryItem(2, status: .rejectedByPlan),
            makeHistoryItem(1, status: .awaitingApproval)
        ]
        let display = PlanSessionHistoryDisplay(
            items: items,
            mode: .all,
            filter: .completedFinished
        )

        XCTAssertEqual(display.visibleItems.map(\.sessionNumber), [6, 5, 4])
        XCTAssertEqual(display.totalCount, 3)
    }

    func testDisplaySummariesUseFilteredCounts() {
        let items = [
            makeHistoryItem(6),
            makeHistoryItem(5),
            makeHistoryItem(4),
            makeHistoryItem(3),
            makeHistoryItem(2),
            makeHistoryItem(1)
        ]
        let runCues = [
            6: makeRunCue(kind: .failedVerify),
            5: makeRunCue(kind: .developFailed),
            4: makeRunCue(kind: .resumeDevelop, severity: .paused)
        ]

        let recentDisplay = PlanSessionHistoryDisplay(
            items: items,
            recentLimit: 2,
            filter: .attention,
            runCues: runCues
        )
        XCTAssertEqual(recentDisplay.visibleItems.map(\.sessionNumber), [6, 5])
        XCTAssertEqual(recentDisplay.totalCount, 3)
        XCTAssertEqual(recentDisplay.hiddenCount, 1)
        XCTAssertEqual(recentDisplay.countSummary, "Showing latest 2 of 3 matching")
        XCTAssertTrue(recentDisplay.shouldOfferModeToggle)

        let allDisplay = PlanSessionHistoryDisplay(
            items: items,
            mode: .all,
            recentLimit: 2,
            filter: .attention,
            runCues: runCues
        )
        XCTAssertEqual(allDisplay.countSummary, "Showing all 3 matching")

        let noHiddenDisplay = PlanSessionHistoryDisplay(
            items: items,
            recentLimit: 4,
            filter: .attention,
            runCues: runCues
        )
        XCTAssertEqual(noHiddenDisplay.countSummary, "3 matching runs")

        let emptyFilteredDisplay = PlanSessionHistoryDisplay(
            items: items,
            filter: .failedRejected
        )
        XCTAssertEqual(emptyFilteredDisplay.unfilteredTotalCount, 6)
        XCTAssertEqual(emptyFilteredDisplay.totalCount, 0)
        XCTAssertEqual(emptyFilteredDisplay.countSummary, "0 matching runs")
    }

    func testDisplaySummarizesHiddenStatusesAfterFiltering() {
        let items = [
            makeHistoryItem(6, status: .failed),
            makeHistoryItem(5, status: .succeeded),
            makeHistoryItem(4, status: .rejectedByPlan),
            makeHistoryItem(3, status: .cancelled),
            makeHistoryItem(2, status: .skipped),
            makeHistoryItem(1, status: .awaitingApproval)
        ]

        let display = PlanSessionHistoryDisplay(
            items: items,
            recentLimit: 1,
            filter: .completedFinished
        )

        XCTAssertEqual(display.visibleItems.map(\.sessionNumber), [5])
        XCTAssertEqual(display.hiddenCount, 2)
        XCTAssertEqual(display.hiddenStatusSummary, "1 cancelled, 1 skipped")
    }

    private func makeHistoryItem(
        _ number: Int,
        status: SessionStatus = .succeeded
    ) -> PlanSessionHistoryItem {
        PlanSessionHistoryItem(
            sessionNumber: number,
            status: status,
            statusText: statusText(for: status),
            startedAt: Date(timeIntervalSince1970: Double(number)),
            planExcerpt: "Plan",
            verifyCommand: "swift test",
            feedback: nil,
            notes: [],
            commits: [],
            failedVerify: nil,
            runtimeRouteSummary: nil
        )
    }

    private func makeRunCue(
        kind: PlanReliabilityFeedback.Kind,
        severity: PlanReliabilityFeedback.Severity = .failure
    ) -> PlanReliabilityFeedback.RunCue {
        PlanReliabilityFeedback.RunCue(
            notice: PlanReliabilityFeedback.Notice(
                id: "\(kind.rawValue)-test",
                kind: kind,
                severity: severity,
                sessionNumber: 0,
                title: "Cue",
                detail: "Run needs attention.",
                actionLabel: "Review",
                metadata: nil,
                systemImage: "exclamationmark.triangle"
            )
        )
    }

    private func statusText(for status: SessionStatus) -> String {
        switch status {
        case .planning:
            return "Planning"
        case .awaitingApproval:
            return "Awaiting approval"
        case .developing:
            return "Developing"
        case .succeeded:
            return "Succeeded"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        case .rejectedByPlan:
            return "Rejected by plan"
        case .skipped:
            return "Skipped"
        }
    }

    private func makeSession(
        _ number: Int,
        startedAt: Double,
        status: SessionStatus = .succeeded,
        plan: String? = "Plan",
        verify: String? = "swift test",
        commits: [SessionCommit] = [],
        notes: [String] = [],
        verifyOutput: VerifyOutput? = nil,
        feedback: String? = nil,
        executionEnvironmentSnapshots: [SessionExecutionEnvironmentSnapshot] = [],
        mutationTestingExecutions: [SessionMutationTestingExecution] = []
    ) -> SessionRecord {
        SessionRecord(
            session: number,
            startedAt: startedAt,
            endedAt: startedAt + 500,
            plan: plan,
            verify: verify,
            beforeSha: nil,
            afterSha: nil,
            commits: commits,
            status: status,
            notes: notes,
            verifyOutput: verifyOutput,
            feedback: feedback,
            executionEnvironmentSnapshots: executionEnvironmentSnapshots,
            mutationTestingExecutions: mutationTestingExecutions
        )
    }

    private func makeMutationExecution(
        verify: String,
        exitCode: Int?,
        startedAt: Double,
        endedAt: Double,
        outputTail: String
    ) -> SessionMutationTestingExecution {
        let launchPlan = CodexExecutionLaunchPlan.native()
        let readiness = CodexMutationTestingPlan(
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
        repoPrefix: String,
        devcontainerJSON: String,
        preference: CodexExecutionEnvironmentPreference,
        containerToolPath: String?,
        phase: String = "Plan"
    ) throws -> SessionExecutionEnvironmentSnapshot {
        let repoURL = try makeTemporaryDirectory(prefix: repoPrefix)
        try write(devcontainerJSON, to: devcontainerURL(in: repoURL))
        let plan = CodexExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: preference,
            containerToolResolver: { _ in containerToolPath }
        )
        return SessionExecutionEnvironmentSnapshot(phase: phase, launchPlan: plan)
    }

    private func makeTemporaryDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryDirectories.append(url)
        return url.standardizedFileURL
    }

    private func devcontainerURL(in repoURL: URL) -> URL {
        repoURL
            .appending(path: ".devcontainer", directoryHint: .isDirectory)
            .appending(path: "devcontainer.json")
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.data(using: .utf8)?.write(to: url)
    }
}
