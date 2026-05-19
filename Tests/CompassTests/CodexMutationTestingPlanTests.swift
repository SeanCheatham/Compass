import Foundation
@testable import Compass
import XCTest

final class CodexMutationTestingPlanTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
    }

    func testSupportedLanguageReadinessUsesVerifyCommandAsSeed() {
        let cases: [(RepositoryLanguage, String, String)] = [
            (.swift, "swift", "swift test --filter CodexMutationTestingPlanTests"),
            (.typeScriptJavaScript, "typescript-javascript", "npm test -- --runInBand"),
            (.python, "python", "pytest -q"),
            (.go, "go", "go test ./..."),
            (.rust, "rust", "cargo test")
        ]

        for (language, expectedIdentifier, verifyCommand) in cases {
            let plan = CodexMutationTestingPlan(
                state: makeState(verify: verifyCommand),
                languageProfile: profile(language),
                launchPlan: nativeLaunchPlan()
            )

            XCTAssertTrue(plan.isReady, "Expected \(language) to be mutation-ready.")
            XCTAssertEqual(plan.statusIdentifier, "ready")
            XCTAssertEqual(plan.routeIdentifier, "native-route")
            XCTAssertEqual(plan.languageIdentifier, expectedIdentifier)
            XCTAssertEqual(plan.seedCommand, verifyCommand)
            XCTAssertEqual(plan.seedCommandLabel, verifyCommand)
            XCTAssertTrue(plan.badgeLabel.contains("Mutation: Native"))
            XCTAssertTrue(plan.detailText.contains("later mutation pass would use native macOS"))
            XCTAssertTrue(plan.copyText.contains("seed-command: \(verifyCommand)"))
        }
    }

    func testMissingAndUnsupportedStatesAreBounded() {
        let noImmediate = CodexMutationTestingPlan(
            state: PlanState(completed: [], immediate: nil, midTerm: "", longTerm: ""),
            languageProfile: profile(.swift),
            launchPlan: nativeLaunchPlan()
        )
        XCTAssertFalse(noImmediate.isReady)
        XCTAssertEqual(noImmediate.statusIdentifier, "missing-immediate")
        XCTAssertEqual(noImmediate.badgeLabel, "Mutation: Missing immediate")
        XCTAssertNil(noImmediate.seedCommand)
        XCTAssertEqual(noImmediate.seedCommandLabel, "none")

        let missingVerify = CodexMutationTestingPlan(
            state: makeState(verify: " "),
            languageProfile: profile(.swift),
            launchPlan: nativeLaunchPlan()
        )
        XCTAssertFalse(missingVerify.isReady)
        XCTAssertEqual(missingVerify.statusIdentifier, "missing-verify")
        XCTAssertEqual(missingVerify.badgeLabel, "Mutation: Missing verify")

        let unsupported = CodexMutationTestingPlan(
            state: makeState(verify: "markdownlint README.md"),
            languageProfile: profile(.markdown),
            launchPlan: nativeLaunchPlan()
        )
        XCTAssertFalse(unsupported.isReady)
        XCTAssertEqual(unsupported.statusIdentifier, "unsupported-language")
        XCTAssertEqual(unsupported.languageIdentifier, "markdown")
        XCTAssertEqual(unsupported.badgeLabel, "Mutation: Unsupported language")

        for plan in [noImmediate, missingVerify, unsupported] {
            XCTAssertLessThanOrEqual(plan.identifier.count, CodexMutationTestingPlan.identifierMaxCharacters)
            XCTAssertLessThanOrEqual(plan.badgeLabel.count, CodexMutationTestingPlan.labelMaxCharacters)
            XCTAssertLessThanOrEqual(plan.detailText.count, CodexMutationTestingPlan.detailMaxCharacters)
            XCTAssertLessThanOrEqual(plan.copyText.count, CodexMutationTestingPlan.copyTextMaxCharacters)
        }
    }

    func testAppleContainerAndNativeFallbackRoutesAreReportedWithoutExecutingMutationTools() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexMutationTestingPlanRoute")
        let vmRoute = SharedVMRoute(
            sshDestination: "compass@192.0.2.10",
            hostWorktreeURL: repoURL,
            guestWorkspacePath: "/opt/compass/workspaces/dev-AAA/worktree",
            guestCodexPath: "/opt/compass/codex/codex"
        )
        let vmPlan = CodexExecutionLaunchPlan(
            selectedPreference: .sharedVM,
            effectiveRoute: .sharedVM(vmRoute),
            vmReadiness: .ready(sshDestination: vmRoute.sshDestination)
        )
        let vmReadiness = CodexMutationTestingPlan(
            state: makeState(verify: "swift test"),
            languageProfile: profile(.swift),
            launchPlan: vmPlan
        )

        XCTAssertEqual(vmReadiness.statusIdentifier, "ready")
        XCTAssertEqual(vmReadiness.routeIdentifier, "shared-vm-route")
        XCTAssertTrue(vmReadiness.badgeLabel.contains("Shared VM"))
        XCTAssertTrue(vmReadiness.detailText.contains("Shared VM"))

        let fallbackPlan = CodexExecutionLaunchPlan.host(
            selectedPreference: .sharedVM,
            vmReadiness: .unavailable(reason: "2-guest cap reached"),
            fallbackReason: "Shared VM unavailable: 2-guest cap reached."
        )
        let fallbackReadiness = CodexMutationTestingPlan(
            state: makeState(verify: "swift test"),
            languageProfile: profile(.swift),
            launchPlan: fallbackPlan
        )

        XCTAssertEqual(fallbackReadiness.statusIdentifier, "ready")
        XCTAssertEqual(fallbackReadiness.routeIdentifier, "native-fallback")
        XCTAssertTrue(fallbackReadiness.badgeLabel.contains("Native fallback"))
        XCTAssertTrue(fallbackReadiness.detailText.contains("native macOS fallback"))
    }

    func testIdentifierCopyAndSeedCommandAreStableBoundedAndSanitized() throws {
        let repoURL = try makeTemporaryDirectory(prefix: "CodexMutationTestingPlanSanitized")
        let secretEnvValue = "secret-mutation-env-value"
        let route = SharedVMRoute(
            sshDestination: "compass@192.0.2.10",
            hostWorktreeURL: repoURL,
            guestWorkspacePath: "/opt/compass/workspaces/dev-AAA/worktree",
            guestCodexPath: "/opt/compass/codex/codex",
            environmentVariables: ["SECRET_TOKEN": secretEnvValue]
        )
        let launchPlan = CodexExecutionLaunchPlan(
            selectedPreference: .sharedVM,
            effectiveRoute: .sharedVM(route),
            vmReadiness: .ready(sshDestination: route.sshDestination)
        )
        let state = makeState(
            verify: "swift test --package-path \(repoURL.path) --filter CodexMutationTestingPlanTests \(secretEnvValue)"
        )
        let first = CodexMutationTestingPlan(
            state: state,
            languageProfile: profile(.swift),
            launchPlan: launchPlan
        )
        let second = CodexMutationTestingPlan(
            state: state,
            languageProfile: profile(.swift),
            launchPlan: launchPlan
        )
        let exposedText = [
            first.identifier,
            first.badgeLabel,
            first.detailText,
            first.copyText,
            first.seedCommandLabel
        ].joined(separator: "\n")

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.statusIdentifier, "ready")
        XCTAssertEqual(first.routeIdentifier, "shared-vm-route")
        XCTAssertFalse(exposedText.contains(repoURL.standardizedFileURL.path))
        XCTAssertFalse(exposedText.contains(secretEnvValue))
        XCTAssertLessThanOrEqual(first.identifier.count, CodexMutationTestingPlan.identifierMaxCharacters)
        XCTAssertLessThanOrEqual(first.seedCommandLabel.count, CodexMutationTestingPlan.commandMaxCharacters)
        XCTAssertLessThanOrEqual(first.copyText.count, CodexMutationTestingPlan.copyTextMaxCharacters)
    }

    private func makeState(verify: String) -> PlanState {
        PlanState(
            completed: [],
            immediate: PlanNext(
                plan: "Run mutation readiness planning",
                verify: verify,
                verifyTimeoutMs: 120_000,
                estimatedDifficulty: .medium
            ),
            midTerm: "",
            longTerm: ""
        )
    }

    private func profile(_ language: RepositoryLanguage) -> RepositoryLanguageProfile {
        var counts = RepositoryLanguageCounts()
        counts[language] = 1
        return RepositoryLanguageProfile(
            counts: counts,
            manifestHints: [],
            primaryLanguage: language,
            scannedFileCount: language == .unknown ? 0 : 1,
            scannedDirectoryCount: 1,
            wasTruncated: false
        )
    }

    private func nativeLaunchPlan() -> CodexExecutionLaunchPlan {
        CodexExecutionLaunchPlan.host(selectedPreference: .host)
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

    private func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}
