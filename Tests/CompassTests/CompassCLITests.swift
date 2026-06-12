import Foundation
import Testing

@testable import CompassCore

@Suite("CompassCLI")
struct CompassCLITests {
  @Test
  func parsesSupportedCommands() throws {
    if case .doctor(let repo, let format) = try CompassCLICommand.parse([
      "doctor", "--repo", "/tmp/project", "--format", "text",
    ]) {
      #expect(repo.path == "/tmp/project")
      #expect(format == .text)
    } else {
      Issue.record("Expected doctor command.")
    }

    if case .scaffoldTessera(let path, let name, let format) = try CompassCLICommand.parse([
      "scaffold", "tessera", "/tmp/new-tessera-project", "--name", "new-tessera-project",
    ]) {
      #expect(path.path == "/tmp/new-tessera-project")
      #expect(name == "new-tessera-project")
      #expect(format == .json)
    } else {
      Issue.record("Expected Tessera scaffold command.")
    }

    if case .scaffoldTypeScript(let path, let name, let format) = try CompassCLICommand.parse([
      "scaffold", "typescript", "/tmp/new-project", "--name", "new-project",
    ]) {
      #expect(path.path == "/tmp/new-project")
      #expect(name == "new-project")
      #expect(format == .json)
    } else {
      Issue.record("Expected TypeScript scaffold command.")
    }

    if case .run(let options, let format) = try CompassCLICommand.parse([
      "run", "--repo", "/tmp/project", "--brief", "Add a slice", "--mode", "auto",
      "--fixture", "/tmp/fixture.jsonl", "--max-iterations", "3", "--max-develop-attempts", "4",
      "--max-verify-repairs", "0", "--prompt-log", "/tmp/prompts", "--critic", "--format", "text",
    ]) {
      #expect(options.repoURL.path == "/tmp/project")
      #expect(options.brief == "Add a slice")
      #expect(options.mode == .auto)
      #expect(options.fixtureURL?.path == "/tmp/fixture.jsonl")
      #expect(options.promptLogDirectory?.path == "/tmp/prompts")
      #expect(options.maxIterations == 3)
      #expect(options.maxDevelopAttempts == 4)
      #expect(options.maxVerifyRepairAttempts == 0)
      #expect(options.runCritic)
      #expect(format == .text)
    } else {
      Issue.record("Expected run command.")
    }

    if case .replay(let repo, let session, let mode, let fixture, _, let maxIterations, _) =
      try CompassCLICommand.parse([
        "replay", "--repo", "/tmp/project", "--session", "7", "--mode", "fixture",
        "--fixture", "/tmp/fixture.jsonl", "--max-iterations", "2",
      ])
    {
      #expect(repo.path == "/tmp/project")
      #expect(session == 7)
      #expect(mode == .fixture)
      #expect(fixture?.path == "/tmp/fixture.jsonl")
      #expect(maxIterations == 2)
    } else {
      Issue.record("Expected replay command.")
    }

    if case .verify(let repo, let command, let format) = try CompassCLICommand.parse([
      "verify", "--repo", "/tmp/project", "--command", "pnpm verify", "--format", "text",
    ]) {
      #expect(repo.path == "/tmp/project")
      #expect(command == "pnpm verify")
      #expect(format == .text)
    } else {
      Issue.record("Expected verify command.")
    }
  }

  @Test
  func promptLoggingRuntimeWritesPromptAndOutputArtifacts() async throws {
    let tempURL = try makeCLITempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    let runtime = PromptLoggingLocalModelRuntime(
      base: StaticLocalModelRuntime(output: #"{"kind":"plan_submit","payload":{}}"#),
      promptLogDirectory: tempURL
    )

    let result = try await runtime.generateText(
      request: LocalModelGenerationRequest(
        systemPrompt: "system marker",
        prompt: "prompt marker",
        maxOutputTokens: 32,
        logLabel: "Plan Iteration 1"
      )
    )

    #expect(result.text.contains("plan_submit"))
    #expect(
      try String(
        contentsOf: tempURL.appending(path: "001-plan-iteration-1-system.md"), encoding: .utf8)
        == "system marker"
    )
    #expect(
      try String(
        contentsOf: tempURL.appending(path: "001-plan-iteration-1-prompt.md"), encoding: .utf8)
        == "prompt marker"
    )
    #expect(
      try String(
        contentsOf: tempURL.appending(path: "001-plan-iteration-1-output.md"), encoding: .utf8
      )
      .contains("plan_submit")
    )
    let index = try String(contentsOf: tempURL.appending(path: "index.jsonl"), encoding: .utf8)
    #expect(index.contains(#""label":"plan-iteration-1""#))
    #expect(index.contains(#""status":"completed""#))
  }

  @Test
  func scaffoldCommandInitializesCleanGitBaseline() async throws {
    let tempURL = try makeCLITempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let exitCode = await CompassCLI.run(arguments: [
      "scaffold", "tessera", tempURL.path, "--name", "cli-git-baseline-fixture",
    ])

    #expect(exitCode == 0)
    #expect(FileManager.default.fileExists(atPath: tempURL.appending(path: "tessera.json").path))
    #expect(FileManager.default.fileExists(atPath: tempURL.appending(path: "src/display-name.tes").path))
    #expect(!FileManager.default.fileExists(atPath: tempURL.appending(path: "package.json").path))
    let result = try await AgentHostBashRunner().run(
      command: "git rev-parse --verify HEAD && git status --porcelain --untracked-files=all",
      workingDirectory: tempURL,
      timeout: 30
    )
    #expect(result.exitCode == 0)
    let lines = result.stdout.split(separator: "\n", omittingEmptySubsequences: false)
    #expect(lines.first?.isEmpty == false)
    #expect(lines.dropFirst().allSatisfy { $0.isEmpty })
  }

  @Test
  func headlessBriefSeedFillsMissingStrategicFields() {
    let state = PlanState(
      completed: ["prior-item"],
      immediate: nil,
      brief: PlanStrategicContext(
        summary: "Existing structured summary.",
        constraints: ["Keep current constraints."]
      )
    )

    let seeded = HeadlessCompassRunner.stateBySeedingHeadlessBrief(
      state,
      brief: """
        Add a small CLI summarize helper
        with tests and verification.
        """
    )

    #expect(seeded.completed == ["prior-item"])
    #expect(seeded.brief.summary == "Existing structured summary.")
    #expect(seeded.brief.constraints == ["Keep current constraints."])
    #expect(!seeded.brief.targetUsers.isEmpty)
    #expect(!seeded.brief.desiredOutcomes.isEmpty)
    #expect(!seeded.brief.acceptanceSignals.isEmpty)
  }

  @Test
  func parserRejectsMissingArguments() {
    #expect(throws: CompassCLIError.self) {
      try CompassCLICommand.parse(["doctor"])
    }
    #expect(throws: CompassCLIError.self) {
      try CompassCLICommand.parse(["scaffold", "rust", "/tmp/project"])
    }
    #expect(throws: CompassCLIError.self) {
      try CompassCLICommand.parse(["run", "--repo", "/tmp/project"])
    }
    #expect(throws: CompassCLIError.self) {
      try CompassCLICommand.parse(["replay", "--repo", "/tmp/project", "--session", "nope"])
    }
  }

  @Test
  func legacySharedVMSessionPreferenceDecodesAsContainerizedLinux() throws {
    let decoded = try JSONDecoder().decode(
      AgentExecutionEnvironmentPreference.self,
      from: Data(#""shared_vm""#.utf8)
    )
    #expect(decoded == .containerizedLinux)
    #expect(decoded.rawValue == "containerized_linux")
  }

  @Test
  func editFileAcceptsInsertAliases() throws {
    let plain = try JSONDecoder().decode(
      AgentEditFileTool.Arguments.self,
      from: Data(
        #"{"path":"README.md","startLine":2,"endLine":1,"insert":["hello",""]}"#.utf8
      )
    )
    #expect(plain.path == "README.md")
    #expect(plain.edits[0].replacementLines == ["hello", ""])

    let underscored = try JSONDecoder().decode(
      AgentEditFileTool.Arguments.self,
      from: Data(
        #"{"path":"README.md","edits":[{"startLine":2,"endLine":1,"_insert":"hello"}]}"#.utf8
      )
    )
    #expect(underscored.edits[0].replacementLines == ["hello"])

    let insertion = try JSONDecoder().decode(
      AgentEditFileTool.Arguments.self,
      from: Data(
        #"{"path":"README.md","startLine":2,"endLine":1,"insertion":"import { summarizeCLI } from './summarize';\n"}"#
          .utf8
      )
    )
    #expect(insertion.edits[0].replacementLines == [
      "import { summarizeCLI } from './summarize';", "",
    ])
  }

  @Test
  func fixtureRunnerPlansDevelopsAndVerifiesHostRepo() async throws {
    let tempURL = try makeCLITempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    let events = HeadlessEventRecorder()
    let record: @Sendable (HeadlessCompassEvent) -> Void = { event in
      events.record(event)
    }
    let runner = HeadlessCompassRunner { _, _ in
      FixtureBashRunner()
    }
    try runner.scaffoldTypeScript(at: tempURL, name: "cli-fixture", onEvent: record)

    let fixtureURL = tempURL.appending(path: "fixture.jsonl")
    try fixtureJSONL.write(to: fixtureURL, atomically: true, encoding: .utf8)

    let ok = try await runner.run(
      options: HeadlessRunOptions(
        repoURL: tempURL,
        brief: "Add a fixture smoke note to the README",
        mode: .fixture,
        fixtureURL: fixtureURL,
        maxIterations: 8,
        runCritic: false
      ),
      onEvent: record
    )

    #expect(ok)
    let readme = try String(contentsOf: tempURL.appending(path: "README.md"), encoding: .utf8)
    #expect(readme.contains("Fixture smoke note."))
    let snapshot = events.snapshot()
    #expect(snapshot.contains { $0.kind == "assistant_json" && $0.phase == "plan" })
    #expect(snapshot.contains { $0.kind == "tool_end" && $0.metadata?["tool"] == "edit_file" })
    #expect(snapshot.contains { $0.kind == "tool_end" && $0.metadata?["tool"] == "bash" })
    #expect(snapshot.contains { $0.kind == "verify_result" && $0.status == "completed" })
    #expect(
      FileManager.default.fileExists(atPath: tempURL.appending(path: ".compass/state.json").path))
  }

  @Test
  func fixtureRunnerRetriesDevelopAfterVerifyFailure() async throws {
    let tempURL = try makeCLITempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    let events = HeadlessEventRecorder()
    let record: @Sendable (HeadlessCompassEvent) -> Void = { event in
      events.record(event)
    }
    let runner = HeadlessCompassRunner { _, _ in
      FixtureBashRunner()
    }
    try runner.scaffoldTypeScript(at: tempURL, name: "cli-retry-fixture", onEvent: record)

    let fixtureURL = tempURL.appending(path: "retry-fixture.jsonl")
    try writeFixture(retryFixtureOutputs, to: fixtureURL)

    let ok = try await runner.run(
      options: HeadlessRunOptions(
        repoURL: tempURL,
        brief: "Add a retry marker to the README",
        mode: .fixture,
        fixtureURL: fixtureURL,
        maxIterations: 6,
        maxDevelopAttempts: 2,
        runCritic: false
      ),
      onEvent: record
    )

    #expect(ok)
    let readme = try String(contentsOf: tempURL.appending(path: "README.md"), encoding: .utf8)
    #expect(readme.contains("Retry marker."))
    let snapshot = events.snapshot()
    #expect(snapshot.contains { $0.kind == "develop_retry" })
    #expect(snapshot.contains { $0.kind == "verify_result" && $0.status == "failed" })
    #expect(snapshot.contains { $0.kind == "verify_result" && $0.status == "completed" })
    let auditDir = tempURL.appending(path: ".compass/sessions/000001", directoryHint: .isDirectory)
    #expect(
      FileManager.default.fileExists(atPath: auditDir.appending(path: "verify-attempt-1.log").path))
    #expect(
      FileManager.default.fileExists(atPath: auditDir.appending(path: "verify-attempt-2.log").path))
  }

  @Test
  func fixtureRunnerStopsAfterDevelopPackageManagerBootstrapFailure() async throws {
    let tempURL = try makeCLITempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    let events = HeadlessEventRecorder()
    let record: @Sendable (HeadlessCompassEvent) -> Void = { event in
      events.record(event)
    }
    let runner = HeadlessCompassRunner { _, _ in
      CorepackBootstrapFailureBashRunner()
    }
    try runner.scaffoldTypeScript(at: tempURL, name: "cli-bootstrap-failure-fixture", onEvent: record)

    let fixtureURL = tempURL.appending(path: "package-bootstrap-develop-fixture.jsonl")
    try writeFixture(packageBootstrapDevelopFailureFixtureOutputs, to: fixtureURL)

    let ok = try await runner.run(
      options: HeadlessRunOptions(
        repoURL: tempURL,
        brief: "Exercise package-manager bootstrap failure handling",
        mode: .fixture,
        fixtureURL: fixtureURL,
        maxIterations: 4,
        maxDevelopAttempts: 3,
        runCritic: false
      ),
      onEvent: record
    )

    #expect(!ok)
    let snapshot = events.snapshot()
    #expect(snapshot.contains { $0.kind == "tool_end" && $0.metadata?["tool"] == "bash" })
    #expect(!snapshot.contains { $0.kind == "develop_retry" })
    let sessionEnd = try #require(snapshot.last { $0.kind == "session_end" })
    #expect(sessionEnd.message == "Develop hit a package-manager bootstrap failure.")
    #expect(sessionEnd.metadata?["retryKind"] == "infrastructure_failure")
    #expect(sessionEnd.detail?.contains("before project verification could run") == true)
    #expect(sessionEnd.detail?.contains("will not retry Develop") == true)
  }

  @Test
  func fixtureRunnerStopsAfterVerifyPackageManagerBootstrapFailure() async throws {
    let tempURL = try makeCLITempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    let events = HeadlessEventRecorder()
    let record: @Sendable (HeadlessCompassEvent) -> Void = { event in
      events.record(event)
    }
    let runner = HeadlessCompassRunner { _, _ in
      CorepackBootstrapFailureBashRunner()
    }
    try runner.scaffoldTypeScript(at: tempURL, name: "cli-bootstrap-verify-fixture", onEvent: record)

    let fixtureURL = tempURL.appending(path: "package-bootstrap-verify-fixture.jsonl")
    try writeFixture(packageBootstrapVerifyFailureFixtureOutputs, to: fixtureURL)

    let ok = try await runner.run(
      options: HeadlessRunOptions(
        repoURL: tempURL,
        brief: "Exercise package-manager bootstrap verify failure handling",
        mode: .fixture,
        fixtureURL: fixtureURL,
        maxIterations: 6,
        maxDevelopAttempts: 3,
        runCritic: false
      ),
      onEvent: record
    )

    #expect(!ok)
    let snapshot = events.snapshot()
    #expect(snapshot.contains { $0.kind == "verify_result" && $0.status == "failed" })
    #expect(!snapshot.contains { $0.kind == "develop_retry" })
    let sessionEnd = try #require(snapshot.last { $0.kind == "session_end" })
    #expect(sessionEnd.message == "Verify hit a package-manager bootstrap failure.")
    #expect(sessionEnd.metadata?["retryKind"] == "infrastructure_failure")
    #expect(sessionEnd.metadata?["command"] == "pnpm verify")
    #expect(sessionEnd.detail?.contains("Do not ask Develop to rewrite app code") == true)
  }

  @Test
  func fixtureRunnerRetriesDevelopWhenSuccessHasNoGitChanges() async throws {
    let tempURL = try makeCLITempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    let events = HeadlessEventRecorder()
    let record: @Sendable (HeadlessCompassEvent) -> Void = { event in
      events.record(event)
    }
    let runner = HeadlessCompassRunner { _, _ in
      FixtureBashRunner()
    }
    try runner.scaffoldTypeScript(at: tempURL, name: "cli-no-change-fixture", onEvent: record)

    let fixtureURL = tempURL.appending(path: "no-change-fixture.jsonl")
    try writeFixture(noChangeRetryFixtureOutputs, to: fixtureURL)
    try await initializeFixtureGitRepo(at: tempURL)

    let ok = try await runner.run(
      options: HeadlessRunOptions(
        repoURL: tempURL,
        brief: "Add a no-change retry marker to the README",
        mode: .fixture,
        fixtureURL: fixtureURL,
        maxIterations: 6,
        maxDevelopAttempts: 2,
        runCritic: false
      ),
      onEvent: record
    )

    #expect(ok)
    let readme = try String(contentsOf: tempURL.appending(path: "README.md"), encoding: .utf8)
    #expect(readme.contains("No-change retry marker."))
    let snapshot = events.snapshot()
    #expect(snapshot.contains { $0.kind == "develop_retry" })
    #expect(
      snapshot.contains {
        $0.kind == "develop_retry"
          && ($0.detail ?? "").contains("did not detect any Git-visible file changes")
      })
    #expect(snapshot.contains { $0.kind == "verify_result" && $0.status == "completed" })
  }

  @Test
  func fixtureRunnerUsesReservedVerifyRepairAfterDevelopFailures() async throws {
    let tempURL = try makeCLITempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    let events = HeadlessEventRecorder()
    let record: @Sendable (HeadlessCompassEvent) -> Void = { event in
      events.record(event)
    }
    let runner = HeadlessCompassRunner { _, _ in
      FixtureBashRunner()
    }
    try runner.scaffoldTypeScript(at: tempURL, name: "cli-verify-repair-fixture", onEvent: record)

    let fixtureURL = tempURL.appending(path: "verify-repair-fixture.jsonl")
    try writeFixture(verifyRepairFixtureOutputs, to: fixtureURL)

    let ok = try await runner.run(
      options: HeadlessRunOptions(
        repoURL: tempURL,
        brief: "Add a verify repair marker to the README",
        mode: .fixture,
        fixtureURL: fixtureURL,
        maxIterations: 6,
        maxDevelopAttempts: 3,
        maxVerifyRepairAttempts: 1,
        runCritic: false
      ),
      onEvent: record
    )

    #expect(ok)
    let readme = try String(contentsOf: tempURL.appending(path: "README.md"), encoding: .utf8)
    #expect(readme.contains("Fixed verify marker."))
    #expect(!readme.contains("Broken verify marker."))
    let snapshot = events.snapshot()
    #expect(
      snapshot.contains {
        $0.kind == "develop_retry" && $0.metadata?["retryKind"] == "verify_repair"
          && $0.metadata?["attempt"] == "3" && $0.metadata?["nextAttempt"] == "4"
      })
    #expect(snapshot.contains { $0.kind == "verify_result" && $0.status == "failed" })
    #expect(snapshot.contains { $0.kind == "verify_result" && $0.status == "completed" })
    let auditDir = tempURL.appending(path: ".compass/sessions/000001", directoryHint: .isDirectory)
    #expect(
      FileManager.default.fileExists(atPath: auditDir.appending(path: "verify-attempt-3.log").path))
    #expect(
      FileManager.default.fileExists(atPath: auditDir.appending(path: "verify-attempt-4.log").path))
  }

  @Test
  func fixtureRunnerRetriesDevelopWhenChangedSourceHasZeroCoverage() async throws {
    let tempURL = try makeCLITempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    let events = HeadlessEventRecorder()
    let record: @Sendable (HeadlessCompassEvent) -> Void = { event in
      events.record(event)
    }
    let verifyRunner = CoverageGapFixtureBashRunner()
    let runner = HeadlessCompassRunner { _, label in
      if label == "verify" {
        return verifyRunner
      }
      return FixtureBashRunner()
    }
    try runner.scaffoldTypeScript(at: tempURL, name: "cli-coverage-gap-fixture", onEvent: record)
    try await initializeFixtureGitRepo(at: tempURL)

    let fixtureURL = tempURL.appending(path: "coverage-gap-fixture.jsonl")
    try writeFixture(coverageGapFixtureOutputs, to: fixtureURL)

    let ok = try await runner.run(
      options: HeadlessRunOptions(
        repoURL: tempURL,
        brief: "Add a small summarize helper with tests",
        mode: .fixture,
        fixtureURL: fixtureURL,
        maxIterations: 8,
        maxDevelopAttempts: 2,
        maxVerifyRepairAttempts: 0,
        runCritic: false
      ),
      onEvent: record
    )

    #expect(ok)
    #expect(
      FileManager.default.fileExists(
        atPath: tempURL.appending(path: "packages/cli/src/summarize.test.ts").path))
    let snapshot = events.snapshot()
    #expect(
      snapshot.contains {
        $0.kind == "develop_retry" && $0.metadata?["retryKind"] == "coverage_gap"
          && ($0.detail ?? "").contains("summarize.ts")
          && ($0.detail ?? "").contains("coverage shows changed source")
      })
    let coverageRetry = snapshot.first {
      $0.kind == "develop_retry" && $0.metadata?["retryKind"] == "coverage_gap"
    }
    #expect(coverageRetry?.detail?.contains("Coverage repair instructions") == true)
    #expect(coverageRetry?.detail?.contains("Your next Develop action should be test-focused") == true)
    #expect(coverageRetry?.detail?.contains("Suggested test targets") == true)
    #expect(
      coverageRetry?.detail?.contains(
        "`packages/cli/src/summarize.test.ts` (write_file)"
      ) == true)
    #expect(
      coverageRetry?.detail?.contains(
        "`packages/cli/src/main.test.ts` (read_file then edit_file)"
      ) == true)
    #expect(snapshot.filter { $0.kind == "verify_result" && $0.status == "completed" }.count == 2)
  }

  @Test
  func fixtureRunnerRetriesDevelopWhenRequiredTestPathWasNotChanged() async throws {
    let tempURL = try makeCLITempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    let events = HeadlessEventRecorder()
    let record: @Sendable (HeadlessCompassEvent) -> Void = { event in
      events.record(event)
    }
    let verifyRunner = RequiredTestsFixtureBashRunner()
    let runner = HeadlessCompassRunner { _, label in
      if label == "verify" {
        return verifyRunner
      }
      return FixtureBashRunner()
    }
    try runner.scaffoldTypeScript(at: tempURL, name: "cli-required-tests-fixture", onEvent: record)
    try await initializeFixtureGitRepo(at: tempURL)

    let fixtureURL = tempURL.appending(path: "required-tests-fixture.jsonl")
    try writeFixture(requiredTestsFixtureOutputs, to: fixtureURL)

    let ok = try await runner.run(
      options: HeadlessRunOptions(
        repoURL: tempURL,
        brief: "Add a CLI --format json flag and update packages/cli/src/main.test.ts",
        mode: .fixture,
        fixtureURL: fixtureURL,
        maxIterations: 8,
        maxDevelopAttempts: 2,
        maxVerifyRepairAttempts: 0,
        runCritic: false
      ),
      onEvent: record
    )

    #expect(ok)
    let mainTest = try String(
      contentsOf: tempURL.appending(path: "packages/cli/src/main.test.ts"),
      encoding: .utf8
    )
    #expect(mainTest.contains("prints JSON output"))
    let snapshot = events.snapshot()
    let requiredTestRetry = snapshot.first {
      $0.kind == "develop_retry" && $0.metadata?["retryKind"] == "missing_required_tests"
    }
    #expect(requiredTestRetry?.detail?.contains("explicitly requires test changes") == true)
    #expect(requiredTestRetry?.detail?.contains("packages/cli/src/main.test.ts") == true)
    #expect(requiredTestRetry?.detail?.contains("packages/cli/src/main.ts") == true)
    #expect(snapshot.filter { $0.kind == "verify_result" && $0.status == "completed" }.count == 2)
  }

  @Test
  func fixtureRunnerRetriesDevelopWhenCLIFlagTestUsesCombinedArg() async throws {
    let tempURL = try makeCLITempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    let events = HeadlessEventRecorder()
    let record: @Sendable (HeadlessCompassEvent) -> Void = { event in
      events.record(event)
    }
    let runner = HeadlessCompassRunner { _, label in
      if label == "verify" {
        return PnpmVerifyAlwaysPassBashRunner()
      }
      return FixtureBashRunner()
    }
    try runner.scaffoldTypeScript(at: tempURL, name: "cli-flag-split-fixture", onEvent: record)
    try await initializeFixtureGitRepo(at: tempURL)

    let fixtureURL = tempURL.appending(path: "weak-cli-flag-fixture.jsonl")
    try writeFixture(weakCLIFlagTestFixtureOutputs, to: fixtureURL)

    let ok = try await runner.run(
      options: HeadlessRunOptions(
        repoURL: tempURL,
        brief: "Add a CLI --format json flag and update packages/cli/src/main.test.ts",
        mode: .fixture,
        fixtureURL: fixtureURL,
        maxIterations: 8,
        maxDevelopAttempts: 2,
        maxVerifyRepairAttempts: 0,
        runCritic: false
      ),
      onEvent: record
    )

    #expect(ok)
    let mainTest = try String(
      contentsOf: tempURL.appending(path: "packages/cli/src/main.test.ts"),
      encoding: .utf8
    )
    #expect(mainTest.contains(#"main(["--format", "json", "Ship", "it"])"#))
    let snapshot = events.snapshot()
    let flagRetry = snapshot.first {
      $0.kind == "develop_retry" && $0.metadata?["retryKind"] == "weak_cli_flag_tests"
    }
    #expect(flagRetry?.detail?.contains("real argv splitting") == true)
    #expect(flagRetry?.detail?.contains(#"main(["--format", "json", "Ship", "it"])"#) == true)
    #expect(flagRetry?.detail?.contains("packages/cli/src/main.test.ts") == true)
    #expect(snapshot.filter { $0.kind == "verify_result" && $0.status == "completed" }.count == 2)
  }

  @Test
  func fixtureRunnerRetriesDevelopWhenPackageEntryPointsAtMissingFile() async throws {
    let tempURL = try makeCLITempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    let events = HeadlessEventRecorder()
    let record: @Sendable (HeadlessCompassEvent) -> Void = { event in
      events.record(event)
    }
    let runner = HeadlessCompassRunner { _, label in
      if label == "verify" {
        return PnpmVerifyAlwaysPassBashRunner()
      }
      return FixtureBashRunner()
    }
    try runner.scaffoldTypeScript(at: tempURL, name: "missing-entry-fixture", onEvent: record)
    try await initializeFixtureGitRepo(at: tempURL)

    let fixtureURL = tempURL.appending(path: "missing-entry-fixture.jsonl")
    try writeFixture(missingPackageEntryFixtureOutputs, to: fixtureURL)

    let ok = try await runner.run(
      options: HeadlessRunOptions(
        repoURL: tempURL,
        brief: "Add a CLI weekly habit momentum command with tests",
        mode: .fixture,
        fixtureURL: fixtureURL,
        maxIterations: 8,
        maxDevelopAttempts: 2,
        maxVerifyRepairAttempts: 0,
        runCritic: false
      ),
      onEvent: record
    )

    #expect(ok)
    let cliPackage = try String(
      contentsOf: tempURL.appending(path: "packages/cli/package.json"),
      encoding: .utf8
    )
    #expect(cliPackage.contains(#""missing-entry-fixture": "./src/main.ts""#))
    let snapshot = events.snapshot()
    let entryRetry = snapshot.first {
      $0.kind == "develop_retry" && $0.metadata?["retryKind"] == "missing_package_entry"
    }
    #expect(entryRetry?.detail?.contains("package entry points") == true)
    #expect(entryRetry?.detail?.contains("packages/cli/package.json") == true)
    #expect(entryRetry?.detail?.contains("packages/cli/src/index.ts") == true)
    #expect(snapshot.filter { $0.kind == "verify_result" && $0.status == "completed" }.count == 2)
  }

  @Test
  func fixtureRunnerRetriesDevelopWhenImplementationOnlyChangesPackageMetadata() async throws {
    let tempURL = try makeCLITempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    let events = HeadlessEventRecorder()
    let record: @Sendable (HeadlessCompassEvent) -> Void = { event in
      events.record(event)
    }
    let runner = HeadlessCompassRunner { _, label in
      if label == "verify" {
        return PnpmVerifyAlwaysPassBashRunner()
      }
      return FixtureBashRunner()
    }
    try runner.scaffoldTypeScript(at: tempURL, name: "metadata-only-fixture", onEvent: record)
    try await initializeFixtureGitRepo(at: tempURL)

    let fixtureURL = tempURL.appending(path: "metadata-only-fixture.jsonl")
    try writeFixture(metadataOnlyImplementationFixtureOutputs, to: fixtureURL)

    let ok = try await runner.run(
      options: HeadlessRunOptions(
        repoURL: tempURL,
        brief: "Add a CLI weekly habit momentum command with tests",
        mode: .fixture,
        fixtureURL: fixtureURL,
        maxIterations: 8,
        maxDevelopAttempts: 2,
        maxVerifyRepairAttempts: 0,
        runCritic: false
      ),
      onEvent: record
    )

    #expect(ok)
    let main = try String(
      contentsOf: tempURL.appending(path: "packages/cli/src/main.ts"),
      encoding: .utf8
    )
    #expect(main.contains("weekly momentum"))
    let snapshot = events.snapshot()
    let metadataRetry = snapshot.first {
      $0.kind == "develop_retry" && $0.metadata?["retryKind"] == "metadata_only_implementation"
    }
    #expect(metadataRetry?.detail?.contains("changed only package metadata") == true)
    #expect(metadataRetry?.detail?.contains("packages/cli/package.json") == true)
    #expect(snapshot.filter { $0.kind == "verify_result" && $0.status == "completed" }.count == 2)
  }

  @Test
  func fixtureRunnerRetriesDevelopAfterIterationBudgetExhaustion() async throws {
    let tempURL = try makeCLITempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    let events = HeadlessEventRecorder()
    let record: @Sendable (HeadlessCompassEvent) -> Void = { event in
      events.record(event)
    }
    let runner = HeadlessCompassRunner { _, _ in
      FixtureBashRunner()
    }
    try runner.scaffoldTypeScript(at: tempURL, name: "cli-budget-fixture", onEvent: record)

    let fixtureURL = tempURL.appending(path: "budget-fixture.jsonl")
    try writeFixture(budgetExhaustionFixtureOutputs, to: fixtureURL)

    let ok = try await runner.run(
      options: HeadlessRunOptions(
        repoURL: tempURL,
        brief: "Exercise Develop budget retry handling",
        mode: .fixture,
        fixtureURL: fixtureURL,
        maxIterations: 1,
        maxDevelopAttempts: 2,
        runCritic: false
      ),
      onEvent: record
    )

    #expect(ok)
    let snapshot = events.snapshot()
    #expect(
      snapshot.contains {
        $0.kind == "develop_retry" && $0.metadata?["retryKind"] == "budget_exhaustion"
          && ($0.detail ?? "").contains("Agent exceeded max iterations")
      })
    #expect(snapshot.contains { $0.kind == "verify_result" && $0.status == "completed" })
  }
}

private struct FixtureBashRunner: AgentBashRunner {
  func run(
    command: String,
    workingDirectory: URL,
    timeout: TimeInterval
  ) async throws -> ProcessResult {
    if command.trimmingCharacters(in: .whitespacesAndNewlines) == "tsc --version" {
      return ProcessResult(exitCode: 0, stdout: "Version 5.0.0\n", stderr: "")
    }
    if command.trimmingCharacters(in: .whitespacesAndNewlines) == "tsc retry-marker-check" {
      let readmeURL = workingDirectory.appending(path: "README.md")
      let readme = (try? String(contentsOf: readmeURL, encoding: .utf8)) ?? ""
      if readme.contains("Retry marker.") {
        return ProcessResult(exitCode: 0, stdout: "Retry marker present.\n", stderr: "")
      }
      return ProcessResult(exitCode: 1, stdout: "", stderr: "Retry marker missing.\n")
    }
    if command.trimmingCharacters(in: .whitespacesAndNewlines) == "tsc verify-repair-check" {
      let readmeURL = workingDirectory.appending(path: "README.md")
      let readme = (try? String(contentsOf: readmeURL, encoding: .utf8)) ?? ""
      if readme.contains("Fixed verify marker.") {
        return ProcessResult(exitCode: 0, stdout: "Fixed verify marker present.\n", stderr: "")
      }
      return ProcessResult(exitCode: 1, stdout: "", stderr: "Fixed verify marker missing.\n")
    }
    return try await AgentHostBashRunner().run(
      command: command,
      workingDirectory: workingDirectory,
      timeout: timeout
    )
  }
}

private struct CorepackBootstrapFailureBashRunner: AgentBashRunner {
  func run(
    command: String,
    workingDirectory: URL,
    timeout: TimeInterval
  ) async throws -> ProcessResult {
    guard command.trimmingCharacters(in: .whitespacesAndNewlines) == "pnpm verify" else {
      return try await FixtureBashRunner().run(
        command: command,
        workingDirectory: workingDirectory,
        timeout: timeout
      )
    }
    return ProcessResult(exitCode: 1, stdout: corepackBootstrapFailureOutput, stderr: "")
  }
}

private final class CoverageGapFixtureBashRunner: AgentBashRunner, @unchecked Sendable {
  private var verifyCount = 0

  func run(
    command: String,
    workingDirectory: URL,
    timeout: TimeInterval
  ) async throws -> ProcessResult {
    guard command.trimmingCharacters(in: .whitespacesAndNewlines) == "pnpm verify" else {
      return try await FixtureBashRunner().run(
        command: command,
        workingDirectory: workingDirectory,
        timeout: timeout
      )
    }

    verifyCount += 1
    let count = verifyCount

    if count == 1 {
      return ProcessResult(exitCode: 0, stdout: firstCoverageGapVerifyOutput, stderr: "")
    }
    return ProcessResult(exitCode: 0, stdout: repairedCoverageVerifyOutput, stderr: "")
  }
}

private final class RequiredTestsFixtureBashRunner: AgentBashRunner, @unchecked Sendable {
  private var verifyCount = 0

  func run(
    command: String,
    workingDirectory: URL,
    timeout: TimeInterval
  ) async throws -> ProcessResult {
    guard command.trimmingCharacters(in: .whitespacesAndNewlines) == "pnpm verify" else {
      return try await FixtureBashRunner().run(
        command: command,
        workingDirectory: workingDirectory,
        timeout: timeout
      )
    }

    verifyCount += 1
    let count = verifyCount

    if count == 1 {
      return ProcessResult(exitCode: 0, stdout: requiredTestsFirstVerifyOutput, stderr: "")
    }
    return ProcessResult(exitCode: 0, stdout: requiredTestsRepairedVerifyOutput, stderr: "")
  }
}

private struct PnpmVerifyAlwaysPassBashRunner: AgentBashRunner {
  func run(
    command: String,
    workingDirectory: URL,
    timeout: TimeInterval
  ) async throws -> ProcessResult {
    guard command.trimmingCharacters(in: .whitespacesAndNewlines) == "pnpm verify" else {
      return try await FixtureBashRunner().run(
        command: command,
        workingDirectory: workingDirectory,
        timeout: timeout
      )
    }
    return ProcessResult(exitCode: 0, stdout: "pnpm verify passed.\n", stderr: "")
  }
}

private actor StaticLocalModelRuntime: LocalModelGenerating {
  let output: String

  init(output: String) {
    self.output = output
  }

  func generateText(request: LocalModelGenerationRequest) async throws -> LocalModelGenerationResult {
    LocalModelGenerationResult(
      text: output,
      tokenUsage: .estimated(
        inputCharacters: request.systemPrompt.count + request.prompt.count,
        outputCharacters: output.count
      )
    )
  }
}

private final class HeadlessEventRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var events: [HeadlessCompassEvent] = []

  func record(_ event: HeadlessCompassEvent) {
    lock.lock()
    events.append(event)
    lock.unlock()
  }

  func snapshot() -> [HeadlessCompassEvent] {
    lock.lock()
    defer { lock.unlock() }
    return events
  }
}

private func makeCLITempDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appending(path: "CompassCLITests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

private func initializeFixtureGitRepo(at url: URL) async throws {
  let result = try await AgentHostBashRunner().run(
    command:
      "git init && git add . && git -c user.name='Compass Test' -c user.email='compass-test@localhost' commit -m 'Baseline fixture'",
    workingDirectory: url,
    timeout: 30
  )
  #expect(result.exitCode == 0)
}

private struct FixtureLine: Encodable {
  var text: String
}

private func writeFixture(_ outputs: [String], to url: URL) throws {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
  let lines = try outputs.map { output in
    let data = try encoder.encode(FixtureLine(text: output))
    return String(decoding: data, as: UTF8.self)
  }
  .joined(separator: "\n")
  try lines.write(to: url, atomically: true, encoding: .utf8)
}

private let retryFixtureOutputs = [
  """
  {"kind":"plan_submit","payload":{"state":{"immediate":{"plan":"## Outcome\\nAdd a Retry marker. sentence near the top of README.md.\\n\\n## Why it matters\\nThis proves HeadlessCompassRunner can retry Develop after a verify failure.\\n\\n## Acceptance checks\\n- README.md contains Retry marker.","verify":"tsc retry-marker-check","verifyTimeoutMs":60000,"estimatedDifficulty":"low","selectedBecause":"This tiny documentation slice has a deterministic failing then passing verify command.","source":"repository","candidateID":null},"queue":[],"brief":{"summary":"Exercise CLI Develop retry after verify failure.","targetUsers":["Compass maintainers"],"desiredOutcomes":["Verify failure output reaches a second Develop attempt."],"constraints":["No pnpm dependency for this retry test."],"acceptanceSignals":["README.md contains Retry marker."]},"openQuestions":[]},"lessonEdits":[]}}
  """,
  """
  {"kind":"develop_submit","payload":{"status":"succeeded","summary":"Reported the README marker complete before editing it so verify can catch the missing sentence.","feedback":"README.md was reported as ready for retry coverage, but the marker sentence is absent so the configured command can surface a concrete failure.","bypassVerify":false,"lessonEdits":[]}}
  """,
  """
  {"kind":"develop_continue","tool":"read_file","arguments":{"path":"README.md"},"reason":"Need the current README contents before repairing the failed verify check."}
  """,
  """
  {"kind":"develop_continue","tool":"edit_file","arguments":{"path":"README.md","startLine":3,"endLine":2,"insert":["Retry marker.",""]},"reason":"Add the marker sentence required by verify."}
  """,
  """
  {"kind":"develop_submit","payload":{"status":"succeeded","summary":"README.md now contains the Retry marker sentence required by verify.","feedback":"Retry marker is present in README.md and grep verification can pass; Plan can choose another small slice.","bypassVerify":false,"lessonEdits":[]}}
  """,
]

private let packageBootstrapDevelopFailureFixtureOutputs = [
  """
  {"kind":"plan_submit","payload":{"state":{"immediate":{"plan":"## Outcome\\nExercise package-manager bootstrap failure handling.\\n\\n## Acceptance checks\\n- `pnpm verify` reports the package-manager bootstrap failure.","verify":"pnpm verify","verifyTimeoutMs":60000,"estimatedDifficulty":"low","selectedBecause":"This fixture proves infrastructure failures are not treated as code retries.","source":"repository","candidateID":null},"queue":[],"brief":{"summary":"Exercise package-manager bootstrap failure handling.","targetUsers":["Compass maintainers"],"desiredOutcomes":["Compass stops instead of asking Develop to rewrite app code."],"constraints":["Use pnpm verify."],"acceptanceSignals":["Infrastructure failure is surfaced."]},"openQuestions":[]},"lessonEdits":[]}}
  """,
  """
  {"kind":"develop_continue","tool":"bash","arguments":{"command":"pnpm verify"},"reason":"Run verify before submitting."}
  """,
  """
  {"kind":"develop_submit","payload":{"status":"failed","summary":"The verify command failed due to an internal error when fetching pnpm@9.15.4 from the npm registry.","feedback":"Check network access and ensure Corepack can activate pnpm before rerunning Compass.","bypassVerify":false,"lessonEdits":[]}}
  """,
]

private let packageBootstrapVerifyFailureFixtureOutputs = [
  """
  {"kind":"plan_submit","payload":{"state":{"immediate":{"plan":"## Outcome\\nAdd a Package bootstrap marker. sentence near the top of README.md.\\n\\n## Acceptance checks\\n- README.md contains Package bootstrap marker.\\n- `pnpm verify` runs after Develop.","verify":"pnpm verify","verifyTimeoutMs":60000,"estimatedDifficulty":"low","selectedBecause":"This fixture proves runner verify bootstrap failures are not treated as code retries.","source":"repository","candidateID":null},"queue":[],"brief":{"summary":"Exercise package-manager bootstrap verify handling.","targetUsers":["Compass maintainers"],"desiredOutcomes":["Compass stops when the verify runtime cannot start pnpm."],"constraints":["Use pnpm verify."],"acceptanceSignals":["Infrastructure failure is surfaced."]},"openQuestions":[]},"lessonEdits":[]}}
  """,
  """
  {"kind":"develop_continue","tool":"read_file","arguments":{"path":"README.md"},"reason":"Need the current README contents before editing."}
  """,
  """
  {"kind":"develop_continue","tool":"edit_file","arguments":{"path":"README.md","startLine":3,"endLine":2,"insert":["Package bootstrap marker.",""]},"reason":"Add the marker sentence required by the handoff."}
  """,
  """
  {"kind":"develop_submit","payload":{"status":"succeeded","summary":"README.md now contains the Package bootstrap marker sentence.","feedback":"Package bootstrap marker is present in README.md; pnpm verify should run next.","bypassVerify":false,"lessonEdits":[]}}
  """,
]

private let corepackBootstrapFailureOutput = """
Preparing pnpm@9.15.4 for immediate activation...
Internal Error: Error when performing the request to https://registry.npmjs.org/pnpm/-/pnpm-9.15.4.tgz; for troubleshooting help, see https://github.com/nodejs/corepack#troubleshooting
"""

private let noChangeRetryFixtureOutputs = [
  """
  {"kind":"plan_submit","payload":{"state":{"immediate":{"plan":"## Outcome\\nAdd a No-change retry marker. sentence near the top of README.md.\\n\\n## Why it matters\\nThis proves HeadlessCompassRunner does not accept baseline verify when Develop changed nothing.\\n\\n## Acceptance checks\\n- README.md contains No-change retry marker.","verify":"tsc --version","verifyTimeoutMs":60000,"estimatedDifficulty":"low","selectedBecause":"This tiny documentation slice catches false-positive Develop success without file changes.","source":"repository","candidateID":null},"queue":[],"brief":{"summary":"Exercise CLI no-change retry after a false success.","targetUsers":["Compass maintainers"],"desiredOutcomes":["Develop retries when a Git-backed run changes no files."],"constraints":["No pnpm dependency for this retry test."],"acceptanceSignals":["README.md contains No-change retry marker."]},"openQuestions":[]},"lessonEdits":[]}}
  """,
  """
  {"kind":"develop_submit","payload":{"status":"succeeded","summary":"Claimed the README marker was added without making any file changes.","feedback":"No-change retry marker is present in README.md and verify can pass.","bypassVerify":false,"lessonEdits":[]}}
  """,
  """
  {"kind":"develop_continue","tool":"read_file","arguments":{"path":"README.md"},"reason":"Need the current README contents before adding the missing marker."}
  """,
  """
  {"kind":"develop_continue","tool":"edit_file","arguments":{"path":"README.md","startLine":3,"endLine":2,"insert":["No-change retry marker.",""]},"reason":"Add the marker sentence required by the handoff."}
  """,
  """
  {"kind":"develop_submit","payload":{"status":"succeeded","summary":"README.md now contains the No-change retry marker sentence.","feedback":"No-change retry marker is present in README.md and verify can pass; Plan can choose another small slice.","bypassVerify":false,"lessonEdits":[]}}
  """,
]

private let verifyRepairFixtureOutputs = [
  """
  {"kind":"plan_submit","payload":{"state":{"immediate":{"plan":"## Outcome\\nAdd a Fixed verify marker. sentence near the top of README.md.\\n\\n## Why it matters\\nThis proves HeadlessCompassRunner reserves a verify-repair pass after earlier Develop failures.\\n\\n## Acceptance checks\\n- README.md contains Fixed verify marker.","verify":"tsc verify-repair-check","verifyTimeoutMs":60000,"estimatedDifficulty":"low","selectedBecause":"This tiny documentation slice fails verify once after exhausting the regular Develop budget.","source":"repository","candidateID":null},"queue":[],"brief":{"summary":"Exercise CLI reserved verify repair after failed Develop attempts.","targetUsers":["Compass maintainers"],"desiredOutcomes":["A concrete verify failure still reaches one repair attempt."],"constraints":["No pnpm dependency for this retry test."],"acceptanceSignals":["README.md contains Fixed verify marker."]},"openQuestions":[]},"lessonEdits":[]}}
  """,
  """
  {"kind":"develop_submit","payload":{"status":"failed","summary":"Could not identify the target file on the first pass.","feedback":"Retry should still have enough budget to continue toward a concrete implementation.","bypassVerify":false,"lessonEdits":[]}}
  """,
  """
  {"kind":"develop_submit","payload":{"status":"failed","summary":"Still did not produce a verifiable change on the second pass.","feedback":"The next attempt should edit README.md before submitting success.","bypassVerify":false,"lessonEdits":[]}}
  """,
  """
  {"kind":"develop_continue","tool":"read_file","arguments":{"path":"README.md"},"reason":"Need the current README contents before adding the marker."}
  """,
  """
  {"kind":"develop_continue","tool":"edit_file","arguments":{"path":"README.md","startLine":3,"endLine":2,"insert":["Broken verify marker.",""]},"reason":"Add an intentionally wrong marker so verify produces concrete repair feedback."}
  """,
  """
  {"kind":"develop_submit","payload":{"status":"succeeded","summary":"README.md now contains a marker sentence, but it is intentionally wrong for verify.","feedback":"If verify fails, replace Broken verify marker. with Fixed verify marker.","bypassVerify":false,"lessonEdits":[]}}
  """,
  """
  {"kind":"develop_continue","tool":"read_file","arguments":{"path":"README.md"},"reason":"Need the current README contents before repairing the failed verify check."}
  """,
  """
  {"kind":"develop_continue","tool":"edit_file","arguments":{"path":"README.md","startLine":3,"endLine":3,"replacement":["Fixed verify marker."]},"reason":"Repair the marker sentence required by verify."}
  """,
  """
  {"kind":"develop_submit","payload":{"status":"succeeded","summary":"README.md now contains the Fixed verify marker sentence required by verify.","feedback":"Fixed verify marker is present in README.md and verification can pass; Plan can choose another small slice.","bypassVerify":false,"lessonEdits":[]}}
  """,
]

private let coverageGapFixtureOutputs = [
  """
  {"kind":"plan_submit","payload":{"state":{"immediate":{"plan":"## Outcome\\nCreate new file `packages/cli/src/summarize.ts` with a `summarizeCLI` helper and create new file `packages/cli/src/summarize.test.ts` to cover it.\\n\\n## Acceptance checks\\n- Create new file `packages/cli/src/summarize.test.ts` that imports and executes `summarizeCLI`.\\n- `pnpm verify` passes with coverage for `summarize.ts`.","verify":"pnpm verify","verifyTimeoutMs":60000,"estimatedDifficulty":"low","selectedBecause":"This fixture proves green verify is not accepted when changed source has 0% coverage.","source":"repository","candidateID":null},"queue":[],"brief":{"summary":"Exercise coverage-gap retry after a green verify.","targetUsers":["Compass maintainers"],"desiredOutcomes":["Changed source with 0% coverage triggers another Develop pass."],"constraints":["Use Vitest coverage output."],"acceptanceSignals":["summarize.ts is covered by summarize.test.ts."]},"openQuestions":[]},"lessonEdits":[]}}
  """,
  """
  {"kind":"develop_continue","tool":"write_file","arguments":{"path":"packages/cli/src/summarize.ts","content":"export function summarizeCLI(): string {\\n  return 'Done: 0, Pending: 0';\\n}\\n"},"reason":"Create the new helper, intentionally without its test so coverage catches the gap."}
  """,
  """
  {"kind":"develop_submit","payload":{"status":"succeeded","summary":"Added packages/cli/src/summarize.ts with summarizeCLI.","feedback":"summarize.ts was added with summarizeCLI.","bypassVerify":false,"lessonEdits":[]}}
  """,
  """
  {"kind":"develop_continue","tool":"write_file","arguments":{"path":"packages/cli/src/summarize.test.ts","content":"import { describe, expect, it } from \\"vitest\\";\\nimport { summarizeCLI } from \\"./summarize\\";\\n\\ndescribe(\\"summarizeCLI\\", () => {\\n  it(\\"formats the empty summary\\", () => {\\n    expect(summarizeCLI()).toBe(\\"Done: 0, Pending: 0\\");\\n  });\\n});\\n"},"reason":"Add the missing test that exercises summarizeCLI."}
  """,
  """
  {"kind":"develop_submit","payload":{"status":"succeeded","summary":"Added summarize.test.ts so summarizeCLI is executed by Vitest.","feedback":"summarize.test.ts imports and exercises summarizeCLI.","bypassVerify":false,"lessonEdits":[]}}
  """,
]

private let requiredTestsFixtureOutputs = [
  """
  {"kind":"plan_submit","payload":{"state":{"immediate":{"plan":"## Outcome\\nUpdate `packages/cli/src/main.ts` to support `--format json` and update `packages/cli/src/main.test.ts` with CLI-facing assertions.\\n\\n## Acceptance checks\\n- `packages/cli/src/main.test.ts` covers default text output, JSON output, and a title containing multiple words.\\n- `pnpm verify` passes.","verify":"pnpm verify","verifyTimeoutMs":60000,"estimatedDifficulty":"low","selectedBecause":"This fixture proves a green verify is not accepted when explicit test-file acceptance work is skipped.","source":"repository","candidateID":null},"queue":[],"brief":{"summary":"Add a CLI --format json flag.","targetUsers":["Compass maintainers"],"desiredOutcomes":["The CLI behavior has direct tests."],"constraints":["Modify the existing entrypoint and test file."],"acceptanceSignals":["packages/cli/src/main.test.ts covers JSON output."]},"openQuestions":[]},"lessonEdits":[]}}
  """,
  """
  {"kind":"develop_continue","tool":"read_file","arguments":{"path":"packages/cli/src/main.ts"},"reason":"Need current line numbers before editing the existing CLI entrypoint."}
  """,
  """
  {"kind":"develop_continue","tool":"edit_file","arguments":{"path":"packages/cli/src/main.ts","startLine":5,"endLine":5,"content":"  const format = argv.includes('--format json') ? 'json' : 'text';\\n  const title = argv.filter(arg => !arg.includes('--format')).join(' ').trim() || 'First Compass task';"},"reason":"Add the new flag parsing in the existing CLI entrypoint."}
  """,
  """
  {"kind":"develop_submit","payload":{"status":"succeeded","summary":"Added --format json support to the CLI entrypoint.","feedback":"pnpm verify can pass for the CLI change.","bypassVerify":false,"lessonEdits":[]}}
  """,
  """
  {"kind":"develop_continue","tool":"read_file","arguments":{"path":"packages/cli/src/main.test.ts"},"reason":"Need current line numbers before adding the required CLI assertions."}
  """,
  """
  {"kind":"develop_continue","tool":"edit_file","arguments":{"path":"packages/cli/src/main.test.ts","startLine":1,"endLine":8,"content":"import { describe, expect, it } from \\"vitest\\";\\nimport { main } from \\"./main\\";\\n\\ndescribe(\\"@cli-required-tests-fixture/cli\\", () => {\\n  it(\\"prints the queue summary\\", () => {\\n    expect(main([\\"Ship\\", \\"it\\"])).toBe(\\"1 open / 1 total\\");\\n  });\\n\\n  it(\\"prints JSON output for a multi-word title\\", () => {\\n    expect(JSON.parse(main([\\"--format\\", \\"json\\", \\"Ship\\", \\"it\\"]))).toEqual({\\n      open: 1,\\n      total: 1,\\n      title: \\"Ship it\\",\\n    });\\n  });\\n});\\n"},"reason":"Add the missing CLI-facing tests required by the plan."}
  """,
  """
  {"kind":"develop_submit","payload":{"status":"succeeded","summary":"Updated main.test.ts with the required CLI assertions.","feedback":"packages/cli/src/main.test.ts covers default and JSON CLI output; pnpm verify passes.","bypassVerify":false,"lessonEdits":[]}}
  """,
]

private let weakCLIFlagTestFixtureOutputs = [
  """
  {"kind":"plan_submit","payload":{"state":{"immediate":{"plan":"## Outcome\\nUpdate `packages/cli/src/main.ts` to support `--format json` and update `packages/cli/src/main.test.ts` with CLI-facing assertions.\\n\\n## Acceptance checks\\n- `packages/cli/src/main.test.ts` covers default text output, JSON output, and a title containing multiple words.\\n- The JSON test calls `main([\\"--format\\", \\"json\\", \\"Ship\\", \\"it\\"])` because real argv splits the flag and value.\\n- `pnpm verify` passes.","verify":"pnpm verify","verifyTimeoutMs":60000,"estimatedDifficulty":"low","selectedBecause":"This fixture proves a green verify is not accepted when CLI flag-value tests use a single combined argv token.","source":"repository","candidateID":null},"queue":[],"brief":{"summary":"Add a CLI --format json flag.","targetUsers":["Compass maintainers"],"desiredOutcomes":["The CLI behavior has direct tests."],"constraints":["Modify the existing entrypoint and test file."],"acceptanceSignals":["packages/cli/src/main.test.ts covers split --format json argv."]},"openQuestions":[]},"lessonEdits":[]}}
  """,
  """
  {"kind":"develop_continue","tool":"read_file","arguments":{"path":"packages/cli/src/main.ts"},"reason":"Need current line numbers before editing the existing CLI entrypoint."}
  """,
  """
  {"kind":"develop_continue","tool":"edit_file","arguments":{"path":"packages/cli/src/main.ts","startLine":5,"endLine":6,"content":"  const format = argv.includes(\\"--format json\\");\\n  const title = argv.filter((arg) => arg !== \\"--format json\\").join(\\" \\").trim() || \\"First Compass task\\";\\n  if (format) {\\n    return JSON.stringify({ open: 1, total: 1, title });\\n  }\\n  return summarizeQueue([{ id: \\"task-1\\", title, done: false }]);"},"reason":"Add an intentionally weak combined-token flag parser so the test post-check catches the matching weak assertion."}
  """,
  """
  {"kind":"develop_continue","tool":"read_file","arguments":{"path":"packages/cli/src/main.test.ts"},"reason":"Need current line numbers before adding the CLI assertions."}
  """,
  """
  {"kind":"develop_continue","tool":"edit_file","arguments":{"path":"packages/cli/src/main.test.ts","startLine":1,"endLine":8,"content":"import { describe, expect, it } from \\"vitest\\";\\nimport { main } from \\"./main\\";\\n\\ndescribe(\\"@cli-flag-split-fixture/cli\\", () => {\\n  it(\\"prints default text output\\", () => {\\n    expect(main([\\"Ship\\", \\"it\\"])).toBe(\\"1 open / 1 total\\");\\n  });\\n\\n  it(\\"prints JSON output for a multi-word title\\", () => {\\n    expect(JSON.parse(main([\\"--format json\\", \\"Ship\\", \\"it\\"]))).toEqual({\\n      open: 1,\\n      total: 1,\\n      title: \\"Ship it\\",\\n    });\\n  });\\n});\\n"},"reason":"Add a weak combined-token JSON assertion that should not satisfy the CLI flag-value acceptance check."}
  """,
  """
  {"kind":"develop_submit","payload":{"status":"succeeded","summary":"Updated main.ts and main.test.ts with JSON output coverage.","feedback":"packages/cli/src/main.test.ts covers JSON output and pnpm verify passes.","bypassVerify":false,"lessonEdits":[]}}
  """,
  """
  {"kind":"develop_continue","tool":"read_file","arguments":{"path":"packages/cli/src/main.test.ts"},"reason":"Need current line numbers before repairing the weak combined-token flag assertion."}
  """,
  """
  {"kind":"develop_continue","tool":"edit_file","arguments":{"path":"packages/cli/src/main.test.ts","startLine":1,"endLine":16,"content":"import { describe, expect, it } from \\"vitest\\";\\nimport { main } from \\"./main\\";\\n\\ndescribe(\\"@cli-flag-split-fixture/cli\\", () => {\\n  it(\\"prints default text output\\", () => {\\n    expect(main([\\"Ship\\", \\"it\\"])).toBe(\\"1 open / 1 total\\");\\n  });\\n\\n  it(\\"prints JSON output for split --format json args\\", () => {\\n    expect(JSON.parse(main([\\"--format\\", \\"json\\", \\"Ship\\", \\"it\\"]))).toEqual({\\n      open: 1,\\n      total: 1,\\n      title: \\"Ship it\\",\\n    });\\n  });\\n});\\n"},"reason":"Repair the CLI-facing test to exercise real split argv tokens for --format json."}
  """,
  """
  {"kind":"develop_submit","payload":{"status":"succeeded","summary":"Updated main.test.ts with split argv coverage for --format json.","feedback":"packages/cli/src/main.test.ts calls main([\\"--format\\", \\"json\\", \\"Ship\\", \\"it\\"]) and pnpm verify passes.","bypassVerify":false,"lessonEdits":[]}}
  """,
]

private let missingPackageEntryFixtureOutputs = [
  """
  {"kind":"plan_submit","payload":{"state":{"immediate":{"plan":"## Outcome\\nAdd a CLI weekly habit momentum command and tests.\\n\\n## Acceptance checks\\n- The CLI command prints a readable weekly momentum summary.\\n- `packages/cli/src/main.test.ts` covers the CLI output.","verify":"pnpm verify","verifyTimeoutMs":60000,"estimatedDifficulty":"low","selectedBecause":"This fixture proves green verify is not accepted when package bin points at a missing replacement entry point.","source":"repository","candidateID":null},"queue":[],"brief":{"summary":"Add a CLI weekly habit momentum command with tests.","targetUsers":["Compass maintainers"],"desiredOutcomes":["Package entry-point mistakes trigger repair."],"constraints":["Use pnpm verify."],"acceptanceSignals":["The CLI entry point exists and is tested."]},"openQuestions":[]},"lessonEdits":[]}}
  """,
  """
  {"kind":"develop_continue","tool":"read_file","arguments":{"path":"packages/cli/package.json"},"reason":"Need current package manifest line numbers before changing the bin entry."}
  """,
  """
  {"kind":"develop_continue","tool":"edit_file","arguments":{"path":"packages/cli/package.json","startLine":6,"endLine":6,"content":"    \\"missing-entry-fixture\\": \\"./src/index.ts\\""},"reason":"Point the CLI bin at a replacement file without creating it so the post-verify package-entry check can catch the gap."}
  """,
  """
  {"kind":"develop_submit","payload":{"status":"succeeded","summary":"Updated the CLI package bin to point at packages/cli/src/index.ts.","feedback":"The CLI weekly habit command is complete and pnpm verify passes.","bypassVerify":false,"lessonEdits":[]}}
  """,
  """
  {"kind":"develop_continue","tool":"read_file","arguments":{"path":"packages/cli/package.json"},"reason":"Need current package manifest line numbers before restoring the existing entry point."}
  """,
  """
  {"kind":"develop_continue","tool":"edit_file","arguments":{"path":"packages/cli/package.json","startLine":6,"endLine":6,"content":"    \\"missing-entry-fixture\\": \\"./src/main.ts\\""},"reason":"Restore the manifest to the existing CLI entry point named in the repair guidance."}
  """,
  """
  {"kind":"develop_continue","tool":"read_file","arguments":{"path":"packages/cli/src/main.ts"},"reason":"Need current CLI entry point line numbers before implementing the weekly momentum output."}
  """,
  """
  {"kind":"develop_continue","tool":"edit_file","arguments":{"path":"packages/cli/src/main.ts","startLine":5,"endLine":6,"content":"  const title = argv.join(\\" \\").trim() || \\"Weekly habit\\";\\n  return `weekly momentum: ${summarizeQueue([{ id: \\"task-1\\", title, done: false }])}`;"},"reason":"Make a concrete source change in the existing CLI entry point."}
  """,
  """
  {"kind":"develop_continue","tool":"read_file","arguments":{"path":"packages/cli/src/main.test.ts"},"reason":"Need current CLI test line numbers before adding the required weekly momentum assertion."}
  """,
  """
  {"kind":"develop_continue","tool":"edit_file","arguments":{"path":"packages/cli/src/main.test.ts","startLine":1,"endLine":8,"content":"import { describe, expect, it } from \\"vitest\\";\\nimport { main } from \\"./main\\";\\n\\ndescribe(\\"@missing-entry-fixture/cli\\", () => {\\n  it(\\"prints weekly momentum output\\", () => {\\n    expect(main([\\"Ship\\", \\"it\\"])).toBe(\\"weekly momentum: 1 open / 1 total\\");\\n  });\\n});\\n"},"reason":"Add the CLI-facing test required by the accepted plan."}
  """,
  """
  {"kind":"develop_submit","payload":{"status":"succeeded","summary":"Restored the package bin to src/main.ts, updated the existing CLI entry point, and covered the weekly momentum summary in main.test.ts.","feedback":"packages/cli/src/main.ts and packages/cli/src/main.test.ts implement and verify the weekly momentum CLI output; pnpm verify passes.","bypassVerify":false,"lessonEdits":[]}}
  """,
]

private let metadataOnlyImplementationFixtureOutputs = [
  """
  {"kind":"plan_submit","payload":{"state":{"immediate":{"plan":"## Outcome\\nAdd a CLI weekly habit momentum command and tests.\\n\\n## Acceptance checks\\n- The CLI command prints a readable weekly momentum summary.\\n- `packages/cli/src/main.test.ts` covers the CLI output.","verify":"pnpm verify","verifyTimeoutMs":60000,"estimatedDifficulty":"low","selectedBecause":"This fixture proves green verify is not accepted when a source-behavior handoff changes only package metadata.","source":"repository","candidateID":null},"queue":[],"brief":{"summary":"Add a CLI weekly habit momentum command with tests.","targetUsers":["Compass maintainers"],"desiredOutcomes":["Metadata-only false success triggers repair."],"constraints":["Use pnpm verify."],"acceptanceSignals":["The CLI behavior is implemented and tested."]},"openQuestions":[]},"lessonEdits":[]}}
  """,
  """
  {"kind":"develop_continue","tool":"read_file","arguments":{"path":"packages/cli/package.json"},"reason":"Need current package manifest line numbers before changing dependencies."}
  """,
  """
  {"kind":"develop_continue","tool":"edit_file","arguments":{"path":"packages/cli/package.json","startLine":14,"endLine":14,"content":"    \\"@metadata-only-fixture/core\\": \\"workspace:*\\",\\n    \\"zod\\": \\"^4.4.3\\""},"reason":"Change only package metadata while claiming implementation work is complete."}
  """,
  """
  {"kind":"develop_submit","payload":{"status":"succeeded","summary":"Added a dependency for the CLI weekly momentum command.","feedback":"The CLI weekly habit command is complete and pnpm verify passes.","bypassVerify":false,"lessonEdits":[]}}
  """,
  """
  {"kind":"develop_continue","tool":"read_file","arguments":{"path":"packages/cli/src/main.ts"},"reason":"Need current CLI entry point line numbers before implementing the weekly momentum output."}
  """,
  """
  {"kind":"develop_continue","tool":"edit_file","arguments":{"path":"packages/cli/src/main.ts","startLine":5,"endLine":6,"content":"  const title = argv.join(\\" \\").trim() || \\"Weekly habit\\";\\n  return `weekly momentum: ${summarizeQueue([{ id: \\"task-1\\", title, done: false }])}`;"},"reason":"Make the source behavior change required by the metadata-only repair guidance."}
  """,
  """
  {"kind":"develop_continue","tool":"read_file","arguments":{"path":"packages/cli/src/main.test.ts"},"reason":"Need current CLI test line numbers before adding the required weekly momentum assertion."}
  """,
  """
  {"kind":"develop_continue","tool":"edit_file","arguments":{"path":"packages/cli/src/main.test.ts","startLine":1,"endLine":8,"content":"import { describe, expect, it } from \\"vitest\\";\\nimport { main } from \\"./main\\";\\n\\ndescribe(\\"@metadata-only-fixture/cli\\", () => {\\n  it(\\"prints weekly momentum output\\", () => {\\n    expect(main([\\"Ship\\", \\"it\\"])).toBe(\\"weekly momentum: 1 open / 1 total\\");\\n  });\\n});\\n"},"reason":"Add the CLI-facing test required by the accepted plan."}
  """,
  """
  {"kind":"develop_submit","payload":{"status":"succeeded","summary":"Updated packages/cli/src/main.ts and packages/cli/src/main.test.ts with a weekly momentum summary and coverage.","feedback":"packages/cli/src/main.ts implements the weekly momentum CLI output, packages/cli/src/main.test.ts covers it, and pnpm verify passes.","bypassVerify":false,"lessonEdits":[]}}
  """,
]

private let budgetExhaustionFixtureOutputs = [
  """
  {"kind":"plan_submit","payload":{"state":{"immediate":{"plan":"## Outcome\\nExercise budget exhaustion recovery without changing files.\\n\\n## Why it matters\\nThis proves HeadlessCompassRunner retries Develop after max-iteration exhaustion.\\n\\n## Acceptance checks\\n- The second Develop attempt submits successfully.","verify":"tsc --version","verifyTimeoutMs":60000,"estimatedDifficulty":"low","selectedBecause":"The first Develop output intentionally consumes the full max-iteration budget without submitting.","source":"repository","candidateID":null},"queue":[],"brief":{"summary":"Exercise CLI Develop retry after iteration budget exhaustion.","targetUsers":["Compass maintainers"],"desiredOutcomes":["Budget exhaustion reaches a fresh Develop attempt."],"constraints":["No file changes required for this control fixture."],"acceptanceSignals":["Verify runs after the second attempt."]},"openQuestions":[]},"lessonEdits":[]}}
  """,
  """
  {"kind":"develop_continue","tool":"read_file","arguments":{"path":"README.md"},"reason":"Consume the only allowed Develop iteration without submitting."}
  """,
  """
  {"kind":"develop_submit","payload":{"status":"succeeded","summary":"Recovered after the first Develop attempt exhausted its iteration budget.","feedback":"The headless runner converted budget exhaustion into retry context and verification can run.","bypassVerify":false,"lessonEdits":[]}}
  """,
]

private let firstCoverageGapVerifyOutput = """
> compass-test@0.1.0 verify /workspace
> pnpm typecheck && pnpm test -- --coverage && pnpm build

 RUN  v2.1.9 /workspace
      Coverage enabled with v8

 ✓ packages/cli/src/main.test.ts (1 test) 1ms

 % Coverage report from v8
-------------------|---------|----------|---------|---------|-------------------
File               | % Stmts | % Branch | % Funcs | % Lines | Uncovered Line #s
-------------------|---------|----------|---------|---------|-------------------
All files          |   17.02 |     37.5 |   33.33 |   17.02 |
 cli/src           |   31.57 |       25 |      50 |   31.57 |
  main.ts          |      75 |    33.33 |     100 |      75 | 10-11
  summarize.ts     |       0 |        0 |       0 |       0 | 1-3
-------------------|---------|----------|---------|---------|-------------------
"""

private let repairedCoverageVerifyOutput = """
> compass-test@0.1.0 verify /workspace
> pnpm typecheck && pnpm test -- --coverage && pnpm build

 RUN  v2.1.9 /workspace
      Coverage enabled with v8

 ✓ packages/cli/src/summarize.test.ts (1 test) 1ms
 ✓ packages/cli/src/main.test.ts (1 test) 1ms

 % Coverage report from v8
-------------------|---------|----------|---------|---------|-------------------
File               | % Stmts | % Branch | % Funcs | % Lines | Uncovered Line #s
-------------------|---------|----------|---------|---------|-------------------
All files          |     100 |      100 |     100 |     100 |
 cli/src           |     100 |      100 |     100 |     100 |
 main.ts          |     100 |      100 |     100 |     100 |
 summarize.ts     |     100 |      100 |     100 |     100 |
-------------------|---------|----------|---------|---------|-------------------
"""

private let requiredTestsFirstVerifyOutput = """
> compass-test@0.1.0 verify /workspace
> pnpm typecheck && pnpm test -- --coverage && pnpm build

 RUN  v2.1.9 /workspace
      Coverage enabled with v8

 ✓ packages/cli/src/main.test.ts (1 test) 1ms

 % Coverage report from v8
-------------------|---------|----------|---------|---------|-------------------
File               | % Stmts | % Branch | % Funcs | % Lines | Uncovered Line #s
-------------------|---------|----------|---------|---------|-------------------
All files          |   47.05 |       50 |      50 |   47.05 |
 cli/src           |   77.77 |       40 |     100 |   77.77 |
  main.ts          |   77.77 |       40 |     100 |   77.77 | 11-12
-------------------|---------|----------|---------|---------|-------------------
"""

private let requiredTestsRepairedVerifyOutput = """
> compass-test@0.1.0 verify /workspace
> pnpm typecheck && pnpm test -- --coverage && pnpm build

 RUN  v2.1.9 /workspace
      Coverage enabled with v8

 ✓ packages/cli/src/main.test.ts (2 tests) 1ms

 % Coverage report from v8
-------------------|---------|----------|---------|---------|-------------------
File               | % Stmts | % Branch | % Funcs | % Lines | Uncovered Line #s
-------------------|---------|----------|---------|---------|-------------------
All files          |     100 |      100 |     100 |     100 |
 cli/src           |     100 |      100 |     100 |     100 |
  main.ts          |     100 |      100 |     100 |     100 |
-------------------|---------|----------|---------|---------|-------------------
"""

private let fixtureJSONL = """
  {"text":"{\\"kind\\":\\"plan_submit\\",\\"payload\\":{\\"state\\":{\\"immediate\\":{\\"plan\\":\\"## Outcome\\\\nAdd a short README note that says Fixture smoke note.\\\\n\\\\n## Why it matters\\\\nThis proves the CLI fixture loop can plan a small observable documentation edit.\\\\n\\\\n## Acceptance checks\\\\n- README.md contains the sentence Fixture smoke note.\\",\\"verify\\":\\"tsc --version\\",\\"verifyTimeoutMs\\":60000,\\"estimatedDifficulty\\":\\"low\\",\\"selectedBecause\\":\\"This is a tiny deterministic slice for the CLI fixture harness.\\",\\"source\\":\\"repository\\",\\"candidateID\\":null},\\"queue\\":[],\\"brief\\":{\\"summary\\":\\"Smoke test the CompassCLI fixture harness on a generated TypeScript workspace.\\",\\"targetUsers\\":[\\"Compass maintainers\\"],\\"desiredOutcomes\\":[\\"A deterministic CLI run edits a file and verifies on host.\\"],\\"constraints\\":[\\"No pnpm dependency for this smoke test.\\"],\\"acceptanceSignals\\":[\\"README.md contains Fixture smoke note.\\"]},\\"openQuestions\\":[]},\\"lessonEdits\\":[]}}"}
  {"text":"{\\"kind\\":\\"develop_continue\\",\\"tool\\":\\"read_file\\",\\"arguments\\":{\\"path\\":\\"README.md\\"},\\"reason\\":\\"Need the current README contents before editing.\\"}"}
  {"text":"{\\"kind\\":\\"develop_continue\\",\\"tool\\":\\"edit_file\\",\\"arguments\\":{\\"path\\":\\"README.md\\",\\"startLine\\":3,\\"endLine\\":2,\\"insert\\":[\\"Fixture smoke note.\\",\\"\\"]},\\"reason\\":\\"Insert the planned smoke-test note near the top of the README.\\"}"}
  {"text":"{\\"kind\\":\\"develop_continue\\",\\"tool\\":\\"bash\\",\\"arguments\\":{\\"command\\":\\"git add README.md && git -c user.name='Compass Agent' -c user.email='compass-agent@localhost' commit -m 'Add fixture smoke note'\\",\\"timeoutSeconds\\":60},\\"reason\\":\\"Commit the README edit so post-check git status is clean.\\"}"}
  {"text":"{\\"kind\\":\\"develop_submit\\",\\"payload\\":{\\"status\\":\\"succeeded\\",\\"summary\\":\\"README.md now includes the Fixture smoke note near the top of the file.\\",\\"feedback\\":\\"README.md contains the Fixture smoke note; Plan can pick the next small TypeScript workspace slice.\\",\\"bypassVerify\\":false,\\"lessonEdits\\":[]}}"}
  """
