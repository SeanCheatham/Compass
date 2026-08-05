import Foundation
import Testing

@testable import CompassCore

@Suite("CompassCLI")
struct CompassCLITests {
  @Test
  func parsesSupportedCommands() throws {
    if case .doctor(let repo, let checkCloud, let format) = try CompassCLICommand.parse([
      "doctor", "--repo", "/tmp/project", "--format", "text",
    ]) {
      #expect(repo.path == "/tmp/project")
      #expect(!checkCloud)
      #expect(format == .text)
    } else {
      Issue.record("Expected doctor command.")
    }

    if case .doctor(_, let checkCloud, _) = try CompassCLICommand.parse([
      "doctor", "--repo", "/tmp/project", "--check-cloud",
    ]) {
      #expect(checkCloud)
    } else {
      Issue.record("Expected doctor command with --check-cloud.")
    }

    if case .help(let format) = try CompassCLICommand.parse(["help", "--format", "text"]) {
      #expect(format == .text)
    } else {
      Issue.record("Expected help command.")
    }

    if case .vmSmoke(let repo, let command, let format) = try CompassCLICommand.parse([
      "vm", "smoke", "--repo", "/tmp/project", "--command", "sw_vers",
    ]) {
      #expect(repo.path == "/tmp/project")
      #expect(command == "sw_vers")
      #expect(format == .json)
    } else {
      Issue.record("Expected vm smoke command.")
    }

    if case .vmResetWorkspace(let repo, let mode, let format) = try CompassCLICommand.parse([
      "vm", "reset-workspace", "--repo", "/tmp/project", "--dirt",
    ]) {
      #expect(repo.path == "/tmp/project")
      #expect(mode == .dirt)
      #expect(format == .json)
    } else {
      Issue.record("Expected vm reset-workspace --dirt command.")
    }

    if case .vmResetWorkspace(_, let mode, _) = try CompassCLICommand.parse([
      "vm", "reset-workspace", "--repo", "/tmp/project",
    ]) {
      #expect(mode == .full)
    } else {
      Issue.record("Expected vm reset-workspace default --full.")
    }

    for flag in ["--help", "-h"] {
      if case .help = try CompassCLICommand.parse([flag]) {
      } else {
        Issue.record("Expected \(flag) to parse as help command.")
      }
    }

    if case .scaffoldRust(let path, let name, let products, let format) =
      try CompassCLICommand.parse([
        "scaffold", "rust", "/tmp/new-project", "--name", "new-project",
      ])
    {
      #expect(path.path == "/tmp/new-project")
      #expect(name == "new-project")
      #expect(products == GeneratedProducts.default)
      #expect(format == .json)
    } else {
      Issue.record("Expected scaffold command.")
    }

    if case .scaffoldRust(_, _, let products, _) = try CompassCLICommand.parse([
      "scaffold", "rust", "/tmp/cli-only", "--product", "cli",
    ]) {
      #expect(products == [.cli])
    } else {
      Issue.record("Expected scaffold with --product cli.")
    }

    if case .run(let options, let format) = try CompassCLICommand.parse([
      "run", "--repo", "/tmp/project", "--brief", "Add a slice", "--mode", "auto",
      "--fixture", "/tmp/fixture.jsonl", "--max-iterations", "3", "--max-develop-attempts", "4",
      "--max-verify-repairs", "0", "--sessions", "2", "--prompt-log", "/tmp/prompts", "--critic",
      "--format", "text",
    ]) {
      #expect(options.repoURL.path == "/tmp/project")
      #expect(options.brief == "Add a slice")
      #expect(options.mode == .auto)
      #expect(options.fixtureURL?.path == "/tmp/fixture.jsonl")
      #expect(options.promptLogDirectory?.path == "/tmp/prompts")
      #expect(options.maxIterations == 3)
      #expect(options.maxDevelopAttempts == 4)
      #expect(options.maxVerifyRepairAttempts == 0)
      #expect(options.sessionCount == 2)
      #expect(options.runCritic)
      #expect(format == .text)
    } else {
      Issue.record("Expected run command.")
    }

    if case .run(let options, _) = try CompassCLICommand.parse([
      "run", "--repo", "/tmp/project", "--brief", "Add a slice",
    ]) {
      #expect(options.sessionCount == 1)
    } else {
      Issue.record("Expected run command with default session count.")
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
      "verify", "--repo", "/tmp/project", "--command",
      "cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace",
      "--format", "text",
    ]) {
      #expect(repo.path == "/tmp/project")
      #expect(
        command
          == "cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace"
      )
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
      "scaffold", "rust", tempURL.path, "--name", "cli-git-baseline-fixture",
    ])

    #expect(exitCode == 0)
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
      try CompassCLICommand.parse(["scaffold", "typescript", "/tmp/project"])
    }
    #expect(throws: CompassCLIError.self) {
      try CompassCLICommand.parse(["run", "--repo", "/tmp/project"])
    }
    #expect(throws: CompassCLIError.self) {
      try CompassCLICommand.parse(["replay", "--repo", "/tmp/project", "--session", "nope"])
    }
  }

  @Test
  func helpCommandExitsZero() async {
    let exitCode = await CompassCLI.run(arguments: ["help"])
    #expect(exitCode == 0)
  }

  @Test
  func requestedOutputFormatScansRawArguments() {
    #expect(
      CompassCLIParser.requestedOutputFormat(in: ["run", "--format", "text"]) == .text)
    #expect(CompassCLIParser.requestedOutputFormat(in: ["run"]) == .json)
    #expect(
      CompassCLIParser.requestedOutputFormat(in: ["run", "--format"]) == .json)
    #expect(
      CompassCLIParser.requestedOutputFormat(in: ["run", "--format", "yaml"]) == .json)
  }

  @Test
  func cloudConnectivityCheckReportsPingOutcome() async {
    let events = HeadlessEventRecorder()
    let record: @Sendable (HeadlessCompassEvent) -> Void = { event in
      events.record(event)
    }
    let settings = AgentRuntimeSettings(
      baseURL: URL(string: "https://example.invalid/v1")!,
      apiKey: "test-key",
      model: "test-model"
    )

    let healthy = HeadlessCompassRunner(
      bashRunnerFactory: { _, _ in FixtureBashRunner() },
      cloudPing: { endpoint in
        #expect(endpoint.trimmedAPIKey == "test-key")
        #expect(endpoint.trimmedModel == "test-model")
        return OpenAICompatiblePingResult(
          ok: true, statusCode: 200, latencyMs: 12, message: "ok")
      }
    )
    let healthyOK = await healthy.runCloudConnectivityCheck(
      settings: settings, onEvent: record)
    #expect(healthyOK)

    let failing = HeadlessCompassRunner(
      bashRunnerFactory: { _, _ in FixtureBashRunner() },
      cloudPing: { _ in
        OpenAICompatiblePingResult(
          ok: false, statusCode: 401, latencyMs: 8, message: "unauthorized")
      }
    )
    let failingOK = await failing.runCloudConnectivityCheck(
      settings: settings, onEvent: record)
    #expect(!failingOK)

    let snapshot = events.snapshot()
    #expect(snapshot.contains { $0.kind == "cloud_connectivity" && $0.status == "checking" })
    #expect(
      snapshot.contains {
        $0.kind == "cloud_connectivity" && $0.status == "ready"
          && $0.metadata?["statusCode"] == "200"
      })
    #expect(
      snapshot.contains {
        $0.kind == "cloud_connectivity" && $0.status == "failed" && $0.level == "error"
          && ($0.detail ?? "").contains("unauthorized")
      })
  }

  @Test
  func cloudConnectivityCheckSkipsWhenNotConfigured() async {
    let events = HeadlessEventRecorder()
    let record: @Sendable (HeadlessCompassEvent) -> Void = { event in
      events.record(event)
    }
    let runner = HeadlessCompassRunner(
      bashRunnerFactory: { _, _ in FixtureBashRunner() },
      cloudPing: { _ in
        Issue.record("Ping handler should not run without cloud credentials.")
        return OpenAICompatiblePingResult(ok: false, statusCode: nil, latencyMs: 0, message: "")
      }
    )
    let ok = await runner.runCloudConnectivityCheck(
      settings: AgentRuntimeSettings(apiKey: "", model: ""),
      onEvent: record
    )
    #expect(ok)
    #expect(
      events.snapshot().contains {
        $0.kind == "cloud_connectivity" && $0.status == "skipped" && $0.level == "warning"
      })
  }

  @Test
  func legacySharedVMSessionPreferenceDecodesAsMacOSVM() throws {
    let decoded = try JSONDecoder().decode(
      AgentExecutionEnvironmentPreference.self,
      from: Data(#""shared_vm""#.utf8)
    )
    #expect(decoded == .macOSVM)
    #expect(decoded.rawValue == "macos_vm")
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
    #expect(
      insertion.edits[0].replacementLines == [
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
    try runner.scaffoldRust(at: tempURL, name: "cli-fixture", products: [.cli], onEvent: record)

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
  func fixtureRunnerRunsMultipleSessionsAndRecordsCompletions() async throws {
    let tempURL = try makeCLITempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    let events = HeadlessEventRecorder()
    let record: @Sendable (HeadlessCompassEvent) -> Void = { event in
      events.record(event)
    }
    let runner = HeadlessCompassRunner { _, _ in
      FixtureBashRunner()
    }
    try runner.scaffoldRust(
      at: tempURL, name: "cli-multi-session-fixture", products: [.cli], onEvent: record)

    let fixtureURL = tempURL.appending(path: "multi-session-fixture.jsonl")
    try fixtureJSONL.write(to: fixtureURL, atomically: true, encoding: .utf8)

    let ok = try await runner.runSessions(
      options: HeadlessRunOptions(
        repoURL: tempURL,
        brief: "Add a fixture smoke note to the README",
        mode: .fixture,
        fixtureURL: fixtureURL,
        maxIterations: 8,
        sessionCount: 2,
        runCritic: false
      ),
      onEvent: record
    )

    #expect(ok)
    let readme = try String(contentsOf: tempURL.appending(path: "README.md"), encoding: .utf8)
    #expect(readme.contains("Fixture smoke note."))
    let snapshot = events.snapshot()
    #expect(snapshot.filter { $0.kind == "factory_iteration" && $0.status == "running" }.count == 2)
    #expect(snapshot.filter { $0.kind == "session_end" && $0.status == "completed" }.count == 2)
    let state = try CompassWorkspace(repoURL: tempURL).readState()
    #expect(state.completed.count == 2)
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
    try runner.scaffoldRust(
      at: tempURL, name: "cli-retry-fixture", products: [.cli], onEvent: record)

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
      RustToolchainBootstrapFailureBashRunner()
    }
    try runner.scaffoldRust(
      at: tempURL, name: "cli-bootstrap-failure-fixture", products: [.cli], onEvent: record)

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
      RustToolchainBootstrapFailureBashRunner()
    }
    try runner.scaffoldRust(
      at: tempURL, name: "cli-bootstrap-verify-fixture", products: [.cli], onEvent: record)

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
    #expect(
      sessionEnd.metadata?["command"]
        == "cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace"
    )
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
    try runner.scaffoldRust(
      at: tempURL, name: "cli-no-change-fixture", products: [.cli], onEvent: record)

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
    try runner.scaffoldRust(
      at: tempURL, name: "cli-verify-repair-fixture", products: [.cli], onEvent: record)

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
    try runner.scaffoldRust(
      at: tempURL, name: "cli-coverage-gap-fixture", products: [.cli], onEvent: record)
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
        atPath: tempURL.appending(path: "crates/cli/tests/summarize.rs").path))
    let snapshot = events.snapshot()
    #expect(
      snapshot.contains {
        $0.kind == "develop_retry" && $0.metadata?["retryKind"] == "coverage_gap"
          && ($0.detail ?? "").contains("summarize.rs")
          && ($0.detail ?? "").contains("coverage shows changed source")
      })
    let coverageRetry = snapshot.first {
      $0.kind == "develop_retry" && $0.metadata?["retryKind"] == "coverage_gap"
    }
    #expect(coverageRetry?.detail?.contains("Coverage repair instructions") == true)
    #expect(
      coverageRetry?.detail?.contains("Your next Develop action should be test-focused") == true)
    #expect(coverageRetry?.detail?.contains("Suggested test targets") == true)
    #expect(
      coverageRetry?.detail?.contains(
        "`crates/cli/tests/summarize.rs` (write_file)"
      ) == true)
    #expect(
      coverageRetry?.detail?.contains(
        "`crates/cli/tests/cli.rs` (read_file then edit_file)"
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
    try runner.scaffoldRust(
      at: tempURL, name: "cli-required-tests-fixture", products: [.cli], onEvent: record)
    try await initializeFixtureGitRepo(at: tempURL)

    let fixtureURL = tempURL.appending(path: "required-tests-fixture.jsonl")
    try writeFixture(requiredTestsFixtureOutputs, to: fixtureURL)

    let ok = try await runner.run(
      options: HeadlessRunOptions(
        repoURL: tempURL,
        brief: "Add a CLI --format json flag and update crates/cli/tests/cli.rs",
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
      contentsOf: tempURL.appending(path: "crates/cli/tests/cli.rs"),
      encoding: .utf8
    )
    #expect(mainTest.contains("prints JSON output"))
    let snapshot = events.snapshot()
    let requiredTestRetry = snapshot.first {
      $0.kind == "develop_retry" && $0.metadata?["retryKind"] == "missing_required_tests"
    }
    #expect(requiredTestRetry?.detail?.contains("explicitly requires test changes") == true)
    #expect(requiredTestRetry?.detail?.contains("crates/cli/tests/cli.rs") == true)
    #expect(requiredTestRetry?.detail?.contains("crates/cli/src/main.rs") == true)
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
        return CargoVerifyAlwaysPassBashRunner()
      }
      return FixtureBashRunner()
    }
    try runner.scaffoldRust(
      at: tempURL, name: "cli-flag-split-fixture", products: [.cli], onEvent: record)
    try await initializeFixtureGitRepo(at: tempURL)

    let fixtureURL = tempURL.appending(path: "weak-cli-flag-fixture.jsonl")
    try writeFixture(weakCLIFlagTestFixtureOutputs, to: fixtureURL)

    let ok = try await runner.run(
      options: HeadlessRunOptions(
        repoURL: tempURL,
        brief: "Add a CLI --format json flag and update crates/cli/tests/cli.rs",
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
      contentsOf: tempURL.appending(path: "crates/cli/tests/cli.rs"),
      encoding: .utf8
    )
    #expect(mainTest.contains(#"cli_args(["--format", "json", "Ship", "it"])"#))
    let snapshot = events.snapshot()
    let flagRetry = snapshot.first {
      $0.kind == "develop_retry" && $0.metadata?["retryKind"] == "weak_cli_flag_tests"
    }
    #expect(flagRetry?.detail?.contains("real argv splitting") == true)
    #expect(flagRetry?.detail?.contains(#"["--format", "json", "Ship", "it"]"#) == true)
    #expect(flagRetry?.detail?.contains("crates/cli/tests/cli.rs") == true)
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
        return CargoVerifyAlwaysPassBashRunner()
      }
      return FixtureBashRunner()
    }
    try runner.scaffoldRust(
      at: tempURL, name: "missing-entry-fixture", products: [.cli], onEvent: record)
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
      contentsOf: tempURL.appending(path: "crates/cli/Cargo.toml"),
      encoding: .utf8
    )
    #expect(cliPackage.contains(#"path = "src/main.rs""#))
    let snapshot = events.snapshot()
    let entryRetry = snapshot.first {
      $0.kind == "develop_retry" && $0.metadata?["retryKind"] == "missing_package_entry"
    }
    #expect(entryRetry?.detail?.contains("package entry points") == true)
    #expect(entryRetry?.detail?.contains("crates/cli/Cargo.toml") == true)
    #expect(entryRetry?.detail?.contains("crates/cli/src/missing_entry.rs") == true)
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
        return CargoVerifyAlwaysPassBashRunner()
      }
      return FixtureBashRunner()
    }
    try runner.scaffoldRust(
      at: tempURL, name: "metadata-only-fixture", products: [.cli], onEvent: record)
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
      contentsOf: tempURL.appending(path: "crates/cli/src/main.rs"),
      encoding: .utf8
    )
    #expect(main.contains("weekly momentum"))
    let snapshot = events.snapshot()
    let metadataRetry = snapshot.first {
      $0.kind == "develop_retry" && $0.metadata?["retryKind"] == "metadata_only_implementation"
    }
    #expect(metadataRetry?.detail?.contains("changed only package metadata") == true)
    #expect(metadataRetry?.detail?.contains("crates/cli/Cargo.toml") == true)
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
    try runner.scaffoldRust(
      at: tempURL, name: "cli-budget-fixture", products: [.cli], onEvent: record)

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
    if command.contains("grep") && command.contains("README.md") {
      let readmeURL = workingDirectory.appending(path: "README.md")
      let readme = (try? String(contentsOf: readmeURL, encoding: .utf8)) ?? ""
      if command.contains("Fixture smoke note") && readme.contains("Fixture smoke note.") {
        return ProcessResult(exitCode: 0, stdout: "Fixture smoke note present.\n", stderr: "")
      }
      if command.contains("Retry marker") && readme.contains("Retry marker.") {
        return ProcessResult(exitCode: 0, stdout: "Retry marker present.\n", stderr: "")
      }
      if command.contains("No-change retry marker") && readme.contains("No-change retry marker.") {
        return ProcessResult(exitCode: 0, stdout: "No-change retry marker present.\n", stderr: "")
      }
      if command.contains("Fixed verify marker") && readme.contains("Fixed verify marker.") {
        return ProcessResult(exitCode: 0, stdout: "Fixed verify marker present.\n", stderr: "")
      }
      if command.contains("Package bootstrap marker")
        && readme.contains("Package bootstrap marker.")
      {
        return ProcessResult(exitCode: 0, stdout: "Package bootstrap marker present.\n", stderr: "")
      }
      return ProcessResult(exitCode: 1, stdout: "", stderr: "README marker missing.\n")
    }
    if command.trimmingCharacters(in: .whitespacesAndNewlines) == "rustc --version" {
      return ProcessResult(exitCode: 0, stdout: "Version 5.0.0\n", stderr: "")
    }
    if command.trimmingCharacters(in: .whitespacesAndNewlines) == "rustc retry-marker-check" {
      let readmeURL = workingDirectory.appending(path: "README.md")
      let readme = (try? String(contentsOf: readmeURL, encoding: .utf8)) ?? ""
      if readme.contains("Retry marker.") {
        return ProcessResult(exitCode: 0, stdout: "Retry marker present.\n", stderr: "")
      }
      return ProcessResult(exitCode: 1, stdout: "", stderr: "Retry marker missing.\n")
    }
    if command.trimmingCharacters(in: .whitespacesAndNewlines) == "rustc verify-repair-check" {
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

private struct RustToolchainBootstrapFailureBashRunner: AgentBashRunner {
  func run(
    command: String,
    workingDirectory: URL,
    timeout: TimeInterval
  ) async throws -> ProcessResult {
    guard
      command.trimmingCharacters(in: .whitespacesAndNewlines)
        == "cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace"
    else {
      return try await FixtureBashRunner().run(
        command: command,
        workingDirectory: workingDirectory,
        timeout: timeout
      )
    }
    return ProcessResult(exitCode: 1, stdout: rustToolchainBootstrapFailureOutput, stderr: "")
  }
}

private final class CoverageGapFixtureBashRunner: AgentBashRunner, @unchecked Sendable {
  private var verifyCount = 0

  func run(
    command: String,
    workingDirectory: URL,
    timeout: TimeInterval
  ) async throws -> ProcessResult {
    guard
      command.trimmingCharacters(in: .whitespacesAndNewlines)
        == "cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace"
    else {
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
    guard
      command.trimmingCharacters(in: .whitespacesAndNewlines)
        == "cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace"
    else {
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

private struct CargoVerifyAlwaysPassBashRunner: AgentBashRunner {
  func run(
    command: String,
    workingDirectory: URL,
    timeout: TimeInterval
  ) async throws -> ProcessResult {
    guard
      command.trimmingCharacters(in: .whitespacesAndNewlines)
        == "cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace"
    else {
      return try await FixtureBashRunner().run(
        command: command,
        workingDirectory: workingDirectory,
        timeout: timeout
      )
    }
    return ProcessResult(
      exitCode: 0,
      stdout:
        "cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace passed.\n",
      stderr: "")
  }
}

private actor StaticLocalModelRuntime: LocalModelGenerating {
  let output: String

  init(output: String) {
    self.output = output
  }

  func generateText(request: LocalModelGenerationRequest) async throws -> LocalModelGenerationResult
  {
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
  {"kind":"plan_submit","payload":{"state":{"immediate":{"plan":"## Outcome\\nAdd a Retry marker. sentence near the top of README.md.\\n\\n## Why it matters\\nThis proves HeadlessCompassRunner can retry Develop after a verify failure.\\n\\n## Acceptance checks\\n- README.md contains Retry marker.","verify":"grep -q 'Retry marker.' README.md","verifyTimeoutMs":60000,"estimatedDifficulty":"low","selectedBecause":"This tiny documentation slice has a deterministic failing then passing verify command.","source":"repository","candidateID":null},"queue":[],"brief":{"summary":"Exercise CLI Develop retry after verify failure.","targetUsers":["Compass maintainers"],"desiredOutcomes":["Verify failure output reaches a second Develop attempt."],"constraints":["No cargo dependency for this retry test."],"acceptanceSignals":["README.md contains Retry marker."]},"openQuestions":[]},"lessonEdits":[]}}
  """,
  """
  {"kind":"develop_continue","tool":"read_file","arguments":{"path":"README.md"},"reason":"Need the current README contents before editing it."}
  """,
  """
  {"kind":"develop_continue","tool":"edit_file","arguments":{"path":"README.md","startLine":3,"endLine":2,"insert":["Placeholder note.",""]},"reason":"Add an unrelated placeholder sentence so verify can catch the missing marker."}
  """,
  """
  {"kind":"develop_submit","payload":{"status":"succeeded","summary":"Reported the README marker complete, but the placeholder sentence does not satisfy verify.","feedback":"README.md was reported as ready for retry coverage, but the marker sentence is absent so the configured command can surface a concrete failure.","bypassVerify":false,"lessonEdits":[]}}
  """,
  """
  {"kind":"develop_continue","tool":"read_file","arguments":{"path":"README.md"},"reason":"Need the current README contents before repairing the failed verify check."}
  """,
  """
  {"kind":"develop_continue","tool":"edit_file","arguments":{"path":"README.md","startLine":3,"endLine":3,"replacement":["Retry marker."]},"reason":"Replace the placeholder with the marker sentence required by verify."}
  """,
  """
  {"kind":"develop_submit","payload":{"status":"succeeded","summary":"README.md now contains the Retry marker sentence required by verify.","feedback":"Retry marker is present in README.md and grep verification can pass; Plan can choose another small slice.","bypassVerify":false,"lessonEdits":[]}}
  """,
]

private let packageBootstrapDevelopFailureFixtureOutputs = [
  """
  {"kind":"plan_submit","payload":{"state":{"immediate":{"plan":"## Outcome\\nExercise package-manager bootstrap failure handling.\\n\\n## Acceptance checks\\n- `cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace` reports the package-manager bootstrap failure.","verify":"cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace","verifyTimeoutMs":60000,"estimatedDifficulty":"low","selectedBecause":"This fixture proves infrastructure failures are not treated as code retries.","source":"repository","candidateID":null},"queue":[],"brief":{"summary":"Exercise package-manager bootstrap failure handling.","targetUsers":["Compass maintainers"],"desiredOutcomes":["Compass stops instead of asking Develop to rewrite app code."],"constraints":["Use cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace."],"acceptanceSignals":["Infrastructure failure is surfaced."]},"openQuestions":[]},"lessonEdits":[]}}
  """,
  """
  {"kind":"develop_continue","tool":"bash","arguments":{"command":"cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace"},"reason":"Run verify before submitting."}
  """,
  """
  {"kind":"develop_submit","payload":{"status":"failed","summary":"The verify command failed because cargo-llvm-cov could not be installed from crates.io.","feedback":"Check network access and ensure cargo/rustup can reach crates.io before rerunning Compass.","bypassVerify":false,"lessonEdits":[]}}
  """,
]

private let packageBootstrapVerifyFailureFixtureOutputs = [
  """
  {"kind":"plan_submit","payload":{"state":{"immediate":{"plan":"## Outcome\\nAdd a Package bootstrap marker. sentence near the top of README.md.\\n\\n## Acceptance checks\\n- README.md contains Package bootstrap marker.\\n- `cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace` runs after Develop.","verify":"cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace","verifyTimeoutMs":60000,"estimatedDifficulty":"low","selectedBecause":"This fixture proves runner verify bootstrap failures are not treated as code retries.","source":"repository","candidateID":null},"queue":[],"brief":{"summary":"Exercise package-manager bootstrap verify handling.","targetUsers":["Compass maintainers"],"desiredOutcomes":["Compass stops when the verify runtime cannot bootstrap the Rust toolchain."],"constraints":["Use cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace."],"acceptanceSignals":["Infrastructure failure is surfaced."]},"openQuestions":[]},"lessonEdits":[]}}
  """,
  """
  {"kind":"develop_continue","tool":"read_file","arguments":{"path":"README.md"},"reason":"Need the current README contents before editing."}
  """,
  """
  {"kind":"develop_continue","tool":"edit_file","arguments":{"path":"README.md","startLine":3,"endLine":2,"insert":["Package bootstrap marker.",""]},"reason":"Add the marker sentence required by the handoff."}
  """,
  """
  {"kind":"develop_submit","payload":{"status":"succeeded","summary":"README.md now contains the Package bootstrap marker sentence.","feedback":"Package bootstrap marker is present in README.md; cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace should run next.","bypassVerify":false,"lessonEdits":[]}}
  """,
]

private let rustToolchainBootstrapFailureOutput = """
  cargo install cargo-llvm-cov --locked
  error: failed to download from https://crates.io
  network: Error when performing the request
  """

private let noChangeRetryFixtureOutputs = [
  """
  {"kind":"plan_submit","payload":{"state":{"immediate":{"plan":"## Outcome\\nAdd a No-change retry marker. sentence near the top of README.md.\\n\\n## Why it matters\\nThis proves HeadlessCompassRunner does not accept baseline verify when Develop changed nothing.\\n\\n## Acceptance checks\\n- README.md contains No-change retry marker.","verify":"grep -q 'No-change retry marker.' README.md","verifyTimeoutMs":60000,"estimatedDifficulty":"low","selectedBecause":"This tiny documentation slice catches false-positive Develop success without file changes.","source":"repository","candidateID":null},"queue":[],"brief":{"summary":"Exercise CLI no-change retry after a false success.","targetUsers":["Compass maintainers"],"desiredOutcomes":["Develop retries when a Git-backed run changes no files."],"constraints":["No cargo dependency for this retry test."],"acceptanceSignals":["README.md contains No-change retry marker."]},"openQuestions":[]},"lessonEdits":[]}}
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
  {"kind":"plan_submit","payload":{"state":{"immediate":{"plan":"## Outcome\\nAdd a Fixed verify marker. sentence near the top of README.md.\\n\\n## Why it matters\\nThis proves HeadlessCompassRunner reserves a verify-repair pass after earlier Develop failures.\\n\\n## Acceptance checks\\n- README.md contains Fixed verify marker.","verify":"grep -q 'Fixed verify marker.' README.md","verifyTimeoutMs":60000,"estimatedDifficulty":"low","selectedBecause":"This tiny documentation slice fails verify once after exhausting the regular Develop budget.","source":"repository","candidateID":null},"queue":[],"brief":{"summary":"Exercise CLI reserved verify repair after failed Develop attempts.","targetUsers":["Compass maintainers"],"desiredOutcomes":["A concrete verify failure still reaches one repair attempt."],"constraints":["No cargo dependency for this retry test."],"acceptanceSignals":["README.md contains Fixed verify marker."]},"openQuestions":[]},"lessonEdits":[]}}
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
  {"kind":"plan_submit","payload":{"state":{"immediate":{"plan":"## Outcome\\nCreate new file `crates/cli/src/summarize.rs` with a `summarize_cli` helper and create new file `crates/cli/tests/summarize.rs` to cover it.\\n\\n## Acceptance checks\\n- Create new file `crates/cli/tests/summarize.rs` that exercises `summarize_cli`.\\n- `cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace` passes with coverage for `summarize.rs`.","verify":"cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace","verifyTimeoutMs":60000,"estimatedDifficulty":"low","selectedBecause":"This fixture proves green verify is not accepted when changed source has 0% coverage.","source":"repository","candidateID":null},"queue":[],"brief":{"summary":"Exercise coverage-gap retry after a green verify.","targetUsers":["Compass maintainers"],"desiredOutcomes":["Changed source with 0% coverage triggers another Develop pass."],"constraints":["Use cargo test coverage output."],"acceptanceSignals":["summarize.rs is covered by summarize.rs."]},"openQuestions":[]},"lessonEdits":[]}}
  """,
  """
  {"kind":"develop_continue","tool":"write_file","arguments":{"path":"crates/cli/src/summarize.rs","content":"pub fn summarize_cli() -> String {\\n    \\"Done: 0, Pending: 0\\".to_string()\\n}\\n"},"reason":"Create the new helper, intentionally without its test so coverage catches the gap."}
  """,
  """
  {"kind":"develop_submit","payload":{"status":"succeeded","summary":"Added crates/cli/src/summarize.rs with summarize_cli.","feedback":"summarize.rs was added with summarize_cli.","bypassVerify":false,"lessonEdits":[]}}
  """,
  """
  {"kind":"develop_continue","tool":"write_file","arguments":{"path":"crates/cli/tests/summarize.rs","content":"#[test]\\nfn summarize_cli_reports_done_and_pending_counts() {\\n    let summary = format!(\\"Done: {}, Pending: {}\\", 0, 0);\\n    assert_eq!(summary, \\"Done: 0, Pending: 0\\");\\n}\\n"},"reason":"Add the missing test that exercises summarize_cli."}
  """,
  """
  {"kind":"develop_submit","payload":{"status":"succeeded","summary":"Added summarize.rs so summarize_cli is executed by cargo test.","feedback":"summarize.rs exercises summarize_cli.","bypassVerify":false,"lessonEdits":[]}}
  """,
]

private let requiredTestsFixtureOutputs = [
  """
  {"kind":"plan_submit","payload":{"state":{"immediate":{"plan":"## Outcome\\nUpdate `crates/cli/src/main.rs` to support `--format json` and update `crates/cli/tests/cli.rs` with CLI-facing assertions.\\n\\n## Acceptance checks\\n- `crates/cli/tests/cli.rs` covers default text output, JSON output, and a title containing multiple words.\\n- `cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace` passes.","verify":"cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace","verifyTimeoutMs":60000,"estimatedDifficulty":"low","selectedBecause":"This fixture proves a green verify is not accepted when explicit test-file acceptance work is skipped.","source":"repository","candidateID":null},"queue":[],"brief":{"summary":"Add a CLI --format json flag.","targetUsers":["Compass maintainers"],"desiredOutcomes":["The CLI behavior has direct tests."],"constraints":["Modify the existing entrypoint and test file."],"acceptanceSignals":["crates/cli/tests/cli.rs covers JSON output."]},"openQuestions":[]},"lessonEdits":[]}}
  """,
  """
  {"kind":"develop_continue","tool":"read_file","arguments":{"path":"crates/cli/src/main.rs"},"reason":"Need current line numbers before editing the existing CLI entrypoint."}
  """,
  """
  {"kind":"develop_continue","tool":"edit_file","arguments":{"path":"crates/cli/src/main.rs","startLine":1,"endLine":15,"content":"use app_core::greeting;\\n\\nfn main() {\\n    let args: Vec<String> = std::env::args().skip(1).collect();\\n    let format_requested = args.iter().any(|arg| arg == \\"--format\\")\\n        && args.iter().any(|arg| arg == \\"json\\");\\n    let title: Vec<String> = args\\n        .iter()\\n        .filter(|arg| arg.as_str() != \\"--format\\" && arg.as_str() != \\"json\\")\\n        .cloned()\\n        .collect();\\n    let title = if title.is_empty() {\\n        \\"First Compass task\\".to_string()\\n    } else {\\n        title.join(\\" \\")\\n    };\\n    if format_requested {\\n        println!(\\"json title {title}\\");\\n    } else {\\n        println!(\\"{}\\", greeting(&title));\\n    }\\n}"},"reason":"Add the new flag parsing in the existing CLI entrypoint."}
  """,
  """
  {"kind":"develop_submit","payload":{"status":"succeeded","summary":"Added --format json support to the CLI entrypoint.","feedback":"cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace can pass for the CLI change.","bypassVerify":false,"lessonEdits":[]}}
  """,
  """
  {"kind":"develop_continue","tool":"read_file","arguments":{"path":"crates/cli/tests/cli.rs"},"reason":"Need current line numbers before adding the required CLI assertions."}
  """,
  """
  {"kind":"develop_continue","tool":"edit_file","arguments":{"path":"crates/cli/tests/cli.rs","startLine":1,"endLine":12,"content":"use std::process::Command;\\n\\nfn cli_args(args: &[&str]) -> String {\\n    let output = Command::new(env!(\\"CARGO_BIN_EXE_app-cli\\"))\\n        .args(args)\\n        .output()\\n        .expect(\\"run app-cli\\");\\n    String::from_utf8_lossy(&output.stdout).trim().to_string()\\n}\\n\\n#[test]\\nfn status_prints_greeting() {\\n    assert!(cli_args(&[\\"status\\"]).contains(\\"hello, world\\"));\\n}\\n\\n// Covers: prints JSON output for a multi-word title.\\n#[test]\\nfn prints_json_output_for_multi_word_title() {\\n    assert!(cli_args(&[\\"--format\\", \\"json\\", \\"Ship\\", \\"it\\"]).contains(\\"Ship it\\"));\\n}"},"reason":"Add the missing CLI-facing tests required by the plan."}
  """,
  """
  {"kind":"develop_submit","payload":{"status":"succeeded","summary":"Updated cli.rs with the required CLI assertions.","feedback":"crates/cli/tests/cli.rs covers default and JSON CLI output; cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace passes.","bypassVerify":false,"lessonEdits":[]}}
  """,
]

private let weakCLIFlagTestFixtureOutputs = [
  """
  {"kind":"plan_submit","payload":{"state":{"immediate":{"plan":"## Outcome\\nUpdate `crates/cli/src/main.rs` to support `--format json` and update `crates/cli/tests/cli.rs` with CLI-facing assertions.\\n\\n## Acceptance checks\\n- `crates/cli/tests/cli.rs` covers default text output, JSON output, and a title containing multiple words.\\n- The JSON test calls `cli_args([\\"--format\\", \\"json\\", \\"Ship\\", \\"it\\"])` because real process arguments split the flag and value.\\n- `cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace` passes.","verify":"cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace","verifyTimeoutMs":60000,"estimatedDifficulty":"low","selectedBecause":"This fixture proves a green verify is not accepted when CLI flag-value tests use a single combined argv token.","source":"repository","candidateID":null},"queue":[],"brief":{"summary":"Add a CLI --format json flag.","targetUsers":["Compass maintainers"],"desiredOutcomes":["The CLI behavior has direct tests."],"constraints":["Modify the existing entrypoint and test file."],"acceptanceSignals":["crates/cli/tests/cli.rs covers split --format json argv."]},"openQuestions":[]},"lessonEdits":[]}}
  """,
  """
  {"kind":"develop_continue","tool":"read_file","arguments":{"path":"crates/cli/src/main.rs"},"reason":"Need current line numbers before editing the existing CLI entrypoint."}
  """,
  """
  {"kind":"develop_continue","tool":"edit_file","arguments":{"path":"crates/cli/src/main.rs","startLine":1,"endLine":15,"content":"use app_core::greeting;\\n\\nfn main() {\\n    let args: Vec<String> = std::env::args().skip(1).collect();\\n    let joined = args.join(\\" \\");\\n    let format_requested = joined.contains(\\"--format=json\\");\\n    let title: Vec<String> = args\\n        .iter()\\n        .filter(|arg| arg.as_str() != \\"--format=json\\")\\n        .cloned()\\n        .collect();\\n    let title = if title.is_empty() {\\n        \\"First Compass task\\".to_string()\\n    } else {\\n        title.join(\\" \\")\\n    };\\n    if format_requested {\\n        println!(\\"json title {title}\\");\\n    } else {\\n        println!(\\"{}\\", greeting(&title));\\n    }\\n}"},"reason":"Add an intentionally weak combined-token flag parser so the test post-check catches the matching weak assertion."}
  """,
  """
  {"kind":"develop_continue","tool":"read_file","arguments":{"path":"crates/cli/tests/cli.rs"},"reason":"Need current line numbers before adding the CLI assertions."}
  """,
  """
  {"kind":"develop_continue","tool":"edit_file","arguments":{"path":"crates/cli/tests/cli.rs","startLine":1,"endLine":12,"content":"use std::process::Command;\\n\\nfn cli_args(args: &[&str]) -> String {\\n    let output = Command::new(env!(\\"CARGO_BIN_EXE_app-cli\\"))\\n        .args(args)\\n        .output()\\n        .expect(\\"run app-cli\\");\\n    String::from_utf8_lossy(&output.stdout).trim().to_string()\\n}\\n\\n#[test]\\nfn prints_default_text_output() {\\n    assert!(cli_args(&[\\"Ship\\", \\"it\\"]).contains(\\"hello\\"));\\n}\\n\\n#[test]\\nfn prints_json_output_for_combined_flag_token() {\\n    assert!(cli_args(&[\\"--format=json\\", \\"Ship\\", \\"it\\"]).contains(\\"Ship it\\"));\\n}"},"reason":"Add a weak combined-token JSON assertion that should not satisfy the CLI flag-value acceptance check."}
  """,
  """
  {"kind":"develop_submit","payload":{"status":"succeeded","summary":"Updated main.rs and cli.rs with JSON output coverage.","feedback":"crates/cli/tests/cli.rs covers JSON output and cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace passes.","bypassVerify":false,"lessonEdits":[]}}
  """,
  """
  {"kind":"develop_continue","tool":"read_file","arguments":{"path":"crates/cli/tests/cli.rs"},"reason":"Need current line numbers before repairing the weak combined-token flag assertion."}
  """,
  """
  {"kind":"develop_continue","tool":"edit_file","arguments":{"path":"crates/cli/tests/cli.rs","startLine":1,"endLine":19,"content":"use std::process::Command;\\n\\nfn cli_args(args: &[&str]) -> String {\\n    let output = Command::new(env!(\\"CARGO_BIN_EXE_app-cli\\"))\\n        .args(args)\\n        .output()\\n        .expect(\\"run app-cli\\");\\n    String::from_utf8_lossy(&output.stdout).trim().to_string()\\n}\\n\\n#[test]\\nfn prints_default_text_output() {\\n    assert!(cli_args(&[\\"Ship\\", \\"it\\"]).contains(\\"hello\\"));\\n}\\n\\n#[test]\\nfn prints_json_output_for_split_format_flag() {\\n    assert!(cli_args([\\"--format\\", \\"json\\", \\"Ship\\", \\"it\\"]).contains(\\"Ship it\\"));\\n}"},"reason":"Repair the CLI-facing test to exercise real split argv tokens for --format json."}
  """,
  """
  {"kind":"develop_submit","payload":{"status":"succeeded","summary":"Updated cli.rs with split argv coverage for --format json.","feedback":"crates/cli/tests/cli.rs calls cli_args([\\"--format\\", \\"json\\", \\"Ship\\", \\"it\\"]) and cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace passes.","bypassVerify":false,"lessonEdits":[]}}
  """,
]

private let missingPackageEntryFixtureOutputs = [
  """
  {"kind":"plan_submit","payload":{"state":{"immediate":{"plan":"## Outcome\\nAdd a CLI weekly habit momentum command and tests.\\n\\n## Acceptance checks\\n- The CLI command prints a readable weekly momentum summary.\\n- `crates/cli/tests/cli.rs` covers the CLI output.","verify":"cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace","verifyTimeoutMs":60000,"estimatedDifficulty":"low","selectedBecause":"This fixture proves green verify is not accepted when package bin points at a missing replacement entry point.","source":"repository","candidateID":null},"queue":[],"brief":{"summary":"Add a CLI weekly habit momentum command with tests.","targetUsers":["Compass maintainers"],"desiredOutcomes":["Package entry-point mistakes trigger repair."],"constraints":["Use cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace."],"acceptanceSignals":["The CLI entry point exists and is tested."]},"openQuestions":[]},"lessonEdits":[]}}
  """,
  """
  {"kind":"develop_continue","tool":"read_file","arguments":{"path":"crates/cli/Cargo.toml"},"reason":"Need current package manifest line numbers before changing the bin entry."}
  """,
  """
  {"kind":"develop_continue","tool":"edit_file","arguments":{"path":"crates/cli/Cargo.toml","startLine":6,"endLine":5,"content":"[[bin]]\\nname = \\"missing-entry-fixture\\"\\npath = \\"src/missing_entry.rs\\""},"reason":"Point the CLI bin at a replacement file without creating it so the post-verify package-entry check can catch the gap."}
  """,
  """
  {"kind":"develop_submit","payload":{"status":"succeeded","summary":"Updated the CLI package bin to point at crates/cli/src/missing_entry.rs.","feedback":"The CLI weekly habit command is complete and cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace passes.","bypassVerify":false,"lessonEdits":[]}}
  """,
  """
  {"kind":"develop_continue","tool":"read_file","arguments":{"path":"crates/cli/Cargo.toml"},"reason":"Need current package manifest line numbers before restoring the existing entry point."}
  """,
  """
  {"kind":"develop_continue","tool":"edit_file","arguments":{"path":"crates/cli/Cargo.toml","startLine":8,"endLine":8,"content":"path = \\"src/main.rs\\""},"reason":"Restore the manifest to the existing CLI entry point named in the repair guidance."}
  """,
  """
  {"kind":"develop_continue","tool":"read_file","arguments":{"path":"crates/cli/src/main.rs"},"reason":"Need current CLI entry point line numbers before implementing the weekly momentum output."}
  """,
  """
  {"kind":"develop_continue","tool":"edit_file","arguments":{"path":"crates/cli/src/main.rs","startLine":1,"endLine":15,"content":"use app_core::greeting;\\n\\nfn main() {\\n    let args: Vec<String> = std::env::args().skip(1).collect();\\n    let title = if args.is_empty() {\\n        \\"Weekly habit\\".to_string()\\n    } else {\\n        args.join(\\" \\")\\n    };\\n    println!(\\"weekly momentum: {}\\", greeting(&title));\\n}"},"reason":"Make a concrete source change in the existing CLI entry point."}
  """,
  """
  {"kind":"develop_continue","tool":"read_file","arguments":{"path":"crates/cli/tests/cli.rs"},"reason":"Need current CLI test line numbers before adding the required weekly momentum assertion."}
  """,
  """
  {"kind":"develop_continue","tool":"edit_file","arguments":{"path":"crates/cli/tests/cli.rs","startLine":1,"endLine":12,"content":"use std::process::Command;\\n\\nfn cli_args(args: &[&str]) -> String {\\n    let output = Command::new(env!(\\"CARGO_BIN_EXE_app-cli\\"))\\n        .args(args)\\n        .output()\\n        .expect(\\"run app-cli\\");\\n    String::from_utf8_lossy(&output.stdout).trim().to_string()\\n}\\n\\n#[test]\\nfn prints_weekly_momentum_output() {\\n    assert!(cli_args(&[\\"Ship\\", \\"it\\"]).contains(\\"weekly momentum\\"));\\n}"},"reason":"Add the CLI-facing test required by the accepted plan."}
  """,
  """
  {"kind":"develop_submit","payload":{"status":"succeeded","summary":"Restored the package bin to src/main.rs, updated the existing CLI entry point, and covered the weekly momentum summary in cli.rs.","feedback":"crates/cli/src/main.rs and crates/cli/tests/cli.rs implement and verify the weekly momentum CLI output; cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace passes.","bypassVerify":false,"lessonEdits":[]}}
  """,
]

private let metadataOnlyImplementationFixtureOutputs = [
  """
  {"kind":"plan_submit","payload":{"state":{"immediate":{"plan":"## Outcome\\nAdd a CLI weekly habit momentum command and tests.\\n\\n## Acceptance checks\\n- The CLI command prints a readable weekly momentum summary.\\n- `crates/cli/tests/cli.rs` covers the CLI output.","verify":"cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace","verifyTimeoutMs":60000,"estimatedDifficulty":"low","selectedBecause":"This fixture proves green verify is not accepted when a source-behavior handoff changes only package metadata.","source":"repository","candidateID":null},"queue":[],"brief":{"summary":"Add a CLI weekly habit momentum command with tests.","targetUsers":["Compass maintainers"],"desiredOutcomes":["Metadata-only false success triggers repair."],"constraints":["Use cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace."],"acceptanceSignals":["The CLI behavior is implemented and tested."]},"openQuestions":[]},"lessonEdits":[]}}
  """,
  """
  {"kind":"develop_continue","tool":"read_file","arguments":{"path":"crates/cli/Cargo.toml"},"reason":"Need current package manifest line numbers before changing dependencies."}
  """,
  """
  {"kind":"develop_continue","tool":"edit_file","arguments":{"path":"crates/cli/Cargo.toml","startLine":9,"endLine":8,"content":"\\n# Track workspace metadata for the weekly habit momentum command."},"reason":"Change only package metadata while claiming implementation work is complete."}
  """,
  """
  {"kind":"develop_submit","payload":{"status":"succeeded","summary":"Added a metadata note for the CLI weekly momentum command.","feedback":"The CLI weekly habit command is complete and cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace passes.","bypassVerify":false,"lessonEdits":[]}}
  """,
  """
  {"kind":"develop_continue","tool":"read_file","arguments":{"path":"crates/cli/src/main.rs"},"reason":"Need current CLI entry point line numbers before implementing the weekly momentum output."}
  """,
  """
  {"kind":"develop_continue","tool":"edit_file","arguments":{"path":"crates/cli/src/main.rs","startLine":1,"endLine":15,"content":"use app_core::greeting;\\n\\nfn main() {\\n    let args: Vec<String> = std::env::args().skip(1).collect();\\n    let title = if args.is_empty() {\\n        \\"Weekly habit\\".to_string()\\n    } else {\\n        args.join(\\" \\")\\n    };\\n    println!(\\"weekly momentum: {}\\", greeting(&title));\\n}"},"reason":"Make the source behavior change required by the metadata-only repair guidance."}
  """,
  """
  {"kind":"develop_continue","tool":"read_file","arguments":{"path":"crates/cli/tests/cli.rs"},"reason":"Need current CLI test line numbers before adding the required weekly momentum assertion."}
  """,
  """
  {"kind":"develop_continue","tool":"edit_file","arguments":{"path":"crates/cli/tests/cli.rs","startLine":1,"endLine":12,"content":"use std::process::Command;\\n\\nfn cli_args(args: &[&str]) -> String {\\n    let output = Command::new(env!(\\"CARGO_BIN_EXE_app-cli\\"))\\n        .args(args)\\n        .output()\\n        .expect(\\"run app-cli\\");\\n    String::from_utf8_lossy(&output.stdout).trim().to_string()\\n}\\n\\n#[test]\\nfn prints_weekly_momentum_output() {\\n    assert!(cli_args(&[\\"Ship\\", \\"it\\"]).contains(\\"weekly momentum\\"));\\n}"},"reason":"Add the CLI-facing test required by the accepted plan."}
  """,
  """
  {"kind":"develop_submit","payload":{"status":"succeeded","summary":"Updated crates/cli/src/main.rs and crates/cli/tests/cli.rs with a weekly momentum summary and coverage.","feedback":"crates/cli/src/main.rs implements the weekly momentum CLI output, crates/cli/tests/cli.rs covers it, and cargo fmt --all --check && cargo clippy --workspace --all-targets --all-features -- -D warnings && cargo test --workspace passes.","bypassVerify":false,"lessonEdits":[]}}
  """,
]

private let budgetExhaustionFixtureOutputs = [
  """
  {"kind":"plan_submit","payload":{"state":{"immediate":{"plan":"## Outcome\\nAdd a Fixture smoke note. sentence near the top of README.md.\\n\\n## Why it matters\\nThis proves HeadlessCompassRunner retries Develop after max-iteration exhaustion.\\n\\n## Acceptance checks\\n- The second Develop attempt submits successfully.","verify":"grep -q 'Fixture smoke note.' README.md","verifyTimeoutMs":60000,"estimatedDifficulty":"low","selectedBecause":"The first Develop output intentionally consumes the full max-iteration budget without submitting.","source":"repository","candidateID":null},"queue":[],"brief":{"summary":"Exercise CLI Develop retry after iteration budget exhaustion.","targetUsers":["Compass maintainers"],"desiredOutcomes":["Budget exhaustion reaches a fresh Develop attempt."],"constraints":["No file changes required for this control fixture."],"acceptanceSignals":["Verify runs after the second attempt."]},"openQuestions":[]},"lessonEdits":[]}}
  """,
  """
  {"kind":"develop_continue","tool":"bash","arguments":{"command":"echo 'Fixture smoke note.' >> README.md"},"reason":"Consume the only allowed Develop iteration while still recording a concrete change to README.md."}
  """,
  """
  {"kind":"develop_submit","payload":{"status":"succeeded","summary":"Recovered after the first Develop attempt exhausted its iteration budget.","feedback":"The headless runner converted budget exhaustion into retry context and verification can run.","bypassVerify":false,"lessonEdits":[]}}
  """,
]

private let firstCoverageGapVerifyOutput = """
   RUN  v2.1.9 /workspace
        Coverage enabled with v8

   ✓ crates/cli/tests/cli.rs (1 test) 1ms

   % Coverage report from v8
  -------------------|---------|----------|---------|---------|-------------------
  File               | % Stmts | % Branch | % Funcs | % Lines | Uncovered Line #s
  -------------------|---------|----------|---------|---------|-------------------
  All files          |   17.02 |     37.5 |   33.33 |   17.02 |
   crates/cli/src |   31.57 |       25 |      50 |   31.57 |
    main.rs          |      75 |    33.33 |     100 |      75 | 10-11
    summarize.rs     |       0 |        0 |       0 |       0 | 1-3
  -------------------|---------|----------|---------|---------|-------------------
  """

private let repairedCoverageVerifyOutput = """
   RUN  v2.1.9 /workspace
        Coverage enabled with v8

   ✓ crates/cli/tests/summarize.rs (1 test) 1ms
   ✓ crates/cli/tests/cli.rs (1 test) 1ms

   % Coverage report from v8
  -------------------|---------|----------|---------|---------|-------------------
  File               | % Stmts | % Branch | % Funcs | % Lines | Uncovered Line #s
  -------------------|---------|----------|---------|---------|-------------------
  All files          |     100 |      100 |     100 |     100 |
   crates/cli/src |     100 |      100 |     100 |     100 |
    main.rs          |     100 |      100 |     100 |     100 |
    summarize.rs     |     100 |      100 |     100 |     100 |
  -------------------|---------|----------|---------|---------|-------------------
  """

private let requiredTestsFirstVerifyOutput = """
   RUN  v2.1.9 /workspace
        Coverage enabled with v8

   ✓ crates/cli/tests/cli.rs (1 test) 1ms

   % Coverage report from v8
  -------------------|---------|----------|---------|---------|-------------------
  File               | % Stmts | % Branch | % Funcs | % Lines | Uncovered Line #s
  -------------------|---------|----------|---------|---------|-------------------
  All files          |   47.05 |       50 |      50 |   47.05 |
   crates/cli/src |   77.77 |       40 |     100 |   77.77 |
    main.rs          |   77.77 |       40 |     100 |   77.77 | 11-12
  -------------------|---------|----------|---------|---------|-------------------
  """

private let requiredTestsRepairedVerifyOutput = """
   RUN  v2.1.9 /workspace
        Coverage enabled with v8

   ✓ crates/cli/tests/cli.rs (2 tests) 1ms

   % Coverage report from v8
  -------------------|---------|----------|---------|---------|-------------------
  File               | % Stmts | % Branch | % Funcs | % Lines | Uncovered Line #s
  -------------------|---------|----------|---------|---------|-------------------
  All files          |     100 |      100 |     100 |     100 |
   crates/cli/src |     100 |      100 |     100 |     100 |
    main.rs          |     100 |      100 |     100 |     100 |
  -------------------|---------|----------|---------|---------|-------------------
  """

private let fixtureJSONL = """
  {"text":"{\\"kind\\":\\"plan_submit\\",\\"payload\\":{\\"state\\":{\\"immediate\\":{\\"plan\\":\\"## Outcome\\\\nAdd a short README note that says Fixture smoke note.\\\\n\\\\n## Why it matters\\\\nThis proves the CLI fixture loop can plan a small observable documentation edit.\\\\n\\\\n## Acceptance checks\\\\n- README.md contains the sentence Fixture smoke note.\\",\\"verify\\":\\"grep -q 'Fixture smoke note.' README.md\\",\\"verifyTimeoutMs\\":60000,\\"estimatedDifficulty\\":\\"low\\",\\"selectedBecause\\":\\"This is a tiny deterministic slice for the CLI fixture harness.\\",\\"source\\":\\"repository\\",\\"candidateID\\":null},\\"queue\\":[],\\"brief\\":{\\"summary\\":\\"Smoke test the CompassCLI fixture harness on a generated Rust workspace.\\",\\"targetUsers\\":[\\"Compass maintainers\\"],\\"desiredOutcomes\\":[\\"A deterministic CLI run edits a file and verifies on host.\\"],\\"constraints\\":[\\"No cargo dependency for this smoke test.\\"],\\"acceptanceSignals\\":[\\"README.md contains Fixture smoke note.\\"]},\\"openQuestions\\":[]},\\"lessonEdits\\":[]}}"}
  {"text":"{\\"kind\\":\\"develop_continue\\",\\"tool\\":\\"read_file\\",\\"arguments\\":{\\"path\\":\\"README.md\\"},\\"reason\\":\\"Need the current README contents before editing.\\"}"}
  {"text":"{\\"kind\\":\\"develop_continue\\",\\"tool\\":\\"edit_file\\",\\"arguments\\":{\\"path\\":\\"README.md\\",\\"startLine\\":3,\\"endLine\\":2,\\"insert\\":[\\"Fixture smoke note.\\",\\"\\"]},\\"reason\\":\\"Insert the planned smoke-test note near the top of the README.\\"}"}
  {"text":"{\\"kind\\":\\"develop_continue\\",\\"tool\\":\\"bash\\",\\"arguments\\":{\\"command\\":\\"grep -q 'Fixture smoke note.' README.md\\",\\"timeoutSeconds\\":60},\\"reason\\":\\"Confirm the README edit is present before submit (project Git is host-only; do not commit from factory bash).\\"}"}
  {"text":"{\\"kind\\":\\"develop_submit\\",\\"payload\\":{\\"status\\":\\"succeeded\\",\\"summary\\":\\"README.md now includes the Fixture smoke note near the top of the file.\\",\\"feedback\\":\\"README.md contains the Fixture smoke note; Plan can pick the next small Rust workspace slice.\\",\\"bypassVerify\\":false,\\"lessonEdits\\":[]}}"}
  """
