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
      "verify", "--repo", "/tmp/project", "--command", "tessera verify . --json", "--format",
      "text",
    ]) {
      #expect(repo.path == "/tmp/project")
      #expect(command == "tessera verify . --json")
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
    #expect(
      FileManager.default.fileExists(atPath: tempURL.appending(path: "src/display-name.tes").path))
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
        Add a small Tessera display helper
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
        #"{"path":"README.md","startLine":2,"endLine":1,"insertion":"(display user.name)\n"}"#
          .utf8
      )
    )
    #expect(
      insertion.edits[0].replacementLines == [
        "(display user.name)", "",
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
    try runner.scaffoldTessera(at: tempURL, name: "cli-fixture", onEvent: record)

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
    #expect(snapshot.contains { $0.kind == "verify_result" && $0.status == "completed" })
    #expect(
      FileManager.default.fileExists(atPath: tempURL.appending(path: ".compass/state.json").path))
  }

  @Test
  func fixtureRunnerCommitsVerifiedChangesOnHost() async throws {
    let tempURL = try makeCLITempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    let projectURL = tempURL.appending(path: "project", directoryHint: .isDirectory)
    let events = HeadlessEventRecorder()
    let record: @Sendable (HeadlessCompassEvent) -> Void = { event in
      events.record(event)
    }
    let runner = HeadlessCompassRunner { _, _ in
      FixtureBashRunner()
    }
    try runner.scaffoldTessera(at: projectURL, name: "cli-host-commit-fixture", onEvent: record)
    try await initializeFixtureGitRepo(at: projectURL)

    let fixtureURL = tempURL.appending(path: "fixture.jsonl")
    try fixtureJSONL.write(to: fixtureURL, atomically: true, encoding: .utf8)

    let ok = try await runner.run(
      options: HeadlessRunOptions(
        repoURL: projectURL,
        brief: "Add a fixture smoke note to the README",
        mode: .fixture,
        fixtureURL: fixtureURL,
        maxIterations: 8,
        runCritic: false
      ),
      onEvent: record
    )

    #expect(ok)
    let status = try await AgentHostBashRunner().run(
      command: "git status --porcelain --untracked-files=all",
      workingDirectory: projectURL,
      timeout: 30
    )
    #expect(status.exitCode == 0)
    #expect(status.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

    let latest = try await AgentHostBashRunner().run(
      command: "git log -1 --format=%s",
      workingDirectory: projectURL,
      timeout: 30
    )
    #expect(
      latest.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        == "README.md now includes the Fixture smoke note near the top of the file.")
    let snapshot = events.snapshot()
    #expect(snapshot.contains { $0.kind == "host_commit_result" && $0.status == "completed" })
  }

  @Test
  func fixtureRunnerCheckpointsDirtyWorktreeBeforeRun() async throws {
    let tempURL = try makeCLITempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    let projectURL = tempURL.appending(path: "project", directoryHint: .isDirectory)
    let events = HeadlessEventRecorder()
    let record: @Sendable (HeadlessCompassEvent) -> Void = { event in
      events.record(event)
    }
    let runner = HeadlessCompassRunner { _, _ in
      FixtureBashRunner()
    }
    try runner.scaffoldTessera(at: projectURL, name: "cli-dirty-start-fixture", onEvent: record)
    try await initializeFixtureGitRepo(at: projectURL)

    let readmeURL = projectURL.appending(path: "README.md")
    let readme = try String(contentsOf: readmeURL, encoding: .utf8)
    try (readme + "\nOwner draft note before Compass run.\n")
      .write(to: readmeURL, atomically: true, encoding: .utf8)

    let fixtureURL = tempURL.appending(path: "dirty-start-fixture.jsonl")
    try writeFixture(greetingFixtureOutputs(projectName: "cli-dirty-start-fixture"), to: fixtureURL)

    let ok = try await runner.run(
      options: HeadlessRunOptions(
        repoURL: projectURL,
        brief: "Exercise dirty-start Compass CLI commit separation",
        mode: .fixture,
        fixtureURL: fixtureURL,
        maxIterations: 8,
        runCritic: false
      ),
      onEvent: record
    )

    #expect(ok)
    let status = try await AgentHostBashRunner().run(
      command: "git status --porcelain --untracked-files=all",
      workingDirectory: projectURL,
      timeout: 30
    )
    #expect(status.exitCode == 0)
    #expect(status.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

    let latestPaths = try await AgentHostBashRunner().run(
      command: "git diff-tree --no-commit-id --name-only -r HEAD",
      workingDirectory: projectURL,
      timeout: 30
    )
    #expect(latestPaths.stdout.contains("src/display-name.tes"))
    #expect(latestPaths.stdout.contains("tests/display-name.json"))
    #expect(!latestPaths.stdout.contains("README.md"))

    let preflightPaths = try await AgentHostBashRunner().run(
      command: "git diff-tree --no-commit-id --name-only -r HEAD^",
      workingDirectory: projectURL,
      timeout: 30
    )
    #expect(preflightPaths.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "README.md")

    let subjects = try await AgentHostBashRunner().run(
      command: "git log --format=%s --max-count=3",
      workingDirectory: projectURL,
      timeout: 30
    )
    #expect(subjects.stdout.contains("Checkpoint pending changes before Compass run"))
    #expect(
      subjects.stdout.contains(
        "Updated the generated Tessera display function and JSON test to produce"))
    let snapshot = events.snapshot()
    #expect(
      snapshot.contains { $0.kind == "preflight_commit_result" && $0.status == "completed" })
    #expect(snapshot.contains { $0.kind == "host_commit_result" && $0.status == "completed" })
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
    try runner.scaffoldTessera(at: tempURL, name: "cli-retry-fixture", onEvent: record)

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
    try runner.scaffoldTessera(at: tempURL, name: "cli-no-change-fixture", onEvent: record)

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
    try runner.scaffoldTessera(at: tempURL, name: "cli-verify-repair-fixture", onEvent: record)

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
    try runner.scaffoldTessera(at: tempURL, name: "cli-budget-fixture", onEvent: record)

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
    if command.trimmingCharacters(in: .whitespacesAndNewlines) == "tessera verify . --json" {
      return ProcessResult(exitCode: 0, stdout: "tessera verify ok\n", stderr: "")
    }
    if command.trimmingCharacters(in: .whitespacesAndNewlines)
      == #"grep -q "Retry marker." README.md"#
      || command.trimmingCharacters(in: .whitespacesAndNewlines)
        == "grep -q 'Retry marker.' README.md"
    {
      let readmeURL = workingDirectory.appending(path: "README.md")
      let readme = (try? String(contentsOf: readmeURL, encoding: .utf8)) ?? ""
      if readme.contains("Retry marker.") {
        return ProcessResult(exitCode: 0, stdout: "Retry marker present.\n", stderr: "")
      }
      return ProcessResult(exitCode: 1, stdout: "", stderr: "Retry marker missing.\n")
    }
    if command.trimmingCharacters(in: .whitespacesAndNewlines)
      == #"grep -q "Fixed verify marker." README.md"#
      || command.trimmingCharacters(in: .whitespacesAndNewlines)
        == "grep -q 'Fixed verify marker.' README.md"
    {
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
  try makeCompassTestDirectory(named: "CompassCLITests")
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

private func greetingFixtureOutputs(projectName: String) -> [String] {
  [
    #"""
    {"kind":"plan_submit","payload":{"state":{"immediate":{"plan":"## Outcome\nUpdate the generated Tessera display function to greet users with a Hello prefix and update its JSON test expectation.\n\n## Acceptance checks\n- src/display-name.tes prefixes the display label with Hello.\n- tests/display-name.json expects Hello, \#(projectName)!.\n- The embedded Tessera run_test tool passes for tests/display-name.json.\n- tessera verify . --json passes.","verify":"tessera verify . --json","verifyTimeoutMs":60000,"estimatedDifficulty":"low","selectedBecause":"This deterministic slice exercises dirty-start host commit separation in a generated Tessera app.","source":"repository","candidateID":null},"queue":[],"brief":{"summary":"Exercise dirty-start Compass CLI behavior on a generated Tessera workspace.","targetUsers":["Compass maintainers"],"desiredOutcomes":["Compass keeps pre-existing dirty work separate from verified agent changes."],"constraints":["Keep the implementation tiny and deterministic."],"acceptanceSignals":["The Tessera test and standard verify command pass after Compass runs."]},"openQuestions":[]},"lessonEdits":[]}}
    """#,
    #"""
    {"kind":"develop_continue","tool":"read_file","arguments":{"path":"src/display-name.tes"},"reason":"Need current source before editing."}
    """#,
    #"""
    {"kind":"develop_continue","tool":"edit_file","arguments":{"path":"src/display-name.tes","startLine":2,"endLine":2,"content":"(def display ((name Text)) (concat \"Hello, \" (concat name \"!\")))"},"reason":"Prefix display labels with Hello."}
    """#,
    #"""
    {"kind":"develop_continue","tool":"read_file","arguments":{"path":"tests/display-name.json"},"reason":"Need current test expectation before editing."}
    """#,
    #"""
    {"kind":"develop_continue","tool":"edit_file","arguments":{"path":"tests/display-name.json","startLine":5,"endLine":5,"content":"  \"expect\": \"Hello, \#(projectName)!\""},"reason":"Align the generated test expectation."}
    """#,
    #"""
    {"kind":"develop_continue","tool":"tessera","arguments":{"action":"run_test","test_path":"tests/display-name.json"},"reason":"Run the focused embedded Tessera test."}
    """#,
    #"""
    {"kind":"develop_submit","payload":{"status":"succeeded","summary":"Updated the generated Tessera display function and JSON test to produce Hello-prefixed display labels.","feedback":"The embedded Tessera run_test tool passed for tests/display-name.json; Compass can run standard verify and commit verified host changes.","bypassVerify":false,"lessonEdits":[]}}
    """#,
  ]
}

private let retryFixtureOutputs = [
  """
  {"kind":"plan_submit","payload":{"state":{"immediate":{"plan":"## Outcome\\nAdd a Retry marker. sentence near the top of README.md.\\n\\n## Why it matters\\nThis proves HeadlessCompassRunner can retry Develop after a verify failure.\\n\\n## Acceptance checks\\n- README.md contains Retry marker.","verify":"grep -q 'Retry marker.' README.md","verifyTimeoutMs":60000,"estimatedDifficulty":"low","selectedBecause":"This tiny documentation slice has a deterministic failing then passing verify command.","source":"repository","candidateID":null},"queue":[],"brief":{"summary":"Exercise CLI Develop retry after verify failure.","targetUsers":["Compass maintainers"],"desiredOutcomes":["Verify failure output reaches a second Develop attempt."],"constraints":["No Tessera dependency for this retry test."],"acceptanceSignals":["README.md contains Retry marker."]},"openQuestions":[]},"lessonEdits":[]}}
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

private let noChangeRetryFixtureOutputs = [
  """
  {"kind":"plan_submit","payload":{"state":{"immediate":{"plan":"## Outcome\\nAdd a No-change retry marker. sentence near the top of README.md.\\n\\n## Why it matters\\nThis proves HeadlessCompassRunner does not accept baseline verify when Develop changed nothing.\\n\\n## Acceptance checks\\n- README.md contains No-change retry marker.","verify":"tessera verify . --json","verifyTimeoutMs":60000,"estimatedDifficulty":"low","selectedBecause":"This tiny documentation slice catches false-positive Develop success without file changes.","source":"repository","candidateID":null},"queue":[],"brief":{"summary":"Exercise CLI no-change retry after a false success.","targetUsers":["Compass maintainers"],"desiredOutcomes":["Develop retries when a Git-backed run changes no files."],"constraints":["No Tessera dependency for this retry test."],"acceptanceSignals":["README.md contains No-change retry marker."]},"openQuestions":[]},"lessonEdits":[]}}
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
  {"kind":"plan_submit","payload":{"state":{"immediate":{"plan":"## Outcome\\nAdd a Fixed verify marker. sentence near the top of README.md.\\n\\n## Why it matters\\nThis proves HeadlessCompassRunner reserves a verify-repair pass after earlier Develop failures.\\n\\n## Acceptance checks\\n- README.md contains Fixed verify marker.","verify":"grep -q 'Fixed verify marker.' README.md","verifyTimeoutMs":60000,"estimatedDifficulty":"low","selectedBecause":"This tiny documentation slice fails verify once after exhausting the regular Develop budget.","source":"repository","candidateID":null},"queue":[],"brief":{"summary":"Exercise CLI reserved verify repair after failed Develop attempts.","targetUsers":["Compass maintainers"],"desiredOutcomes":["A concrete verify failure still reaches one repair attempt."],"constraints":["No Tessera dependency for this retry test."],"acceptanceSignals":["README.md contains Fixed verify marker."]},"openQuestions":[]},"lessonEdits":[]}}
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

private let budgetExhaustionFixtureOutputs = [
  """
  {"kind":"plan_submit","payload":{"state":{"immediate":{"plan":"## Outcome\\nExercise budget exhaustion recovery without changing files.\\n\\n## Why it matters\\nThis proves HeadlessCompassRunner retries Develop after max-iteration exhaustion.\\n\\n## Acceptance checks\\n- The second Develop attempt submits successfully.","verify":"tessera verify . --json","verifyTimeoutMs":60000,"estimatedDifficulty":"low","selectedBecause":"The first Develop output intentionally consumes the full max-iteration budget without submitting.","source":"repository","candidateID":null},"queue":[],"brief":{"summary":"Exercise CLI Develop retry after iteration budget exhaustion.","targetUsers":["Compass maintainers"],"desiredOutcomes":["Budget exhaustion reaches a fresh Develop attempt."],"constraints":["No file changes required for this control fixture."],"acceptanceSignals":["Verify runs after the second attempt."]},"openQuestions":[]},"lessonEdits":[]}}
  """,
  """
  {"kind":"develop_continue","tool":"read_file","arguments":{"path":"README.md"},"reason":"Consume the only allowed Develop iteration without submitting."}
  """,
  """
  {"kind":"develop_submit","payload":{"status":"succeeded","summary":"Recovered after the first Develop attempt exhausted its iteration budget.","feedback":"The headless runner converted budget exhaustion into retry context and verification can run.","bypassVerify":false,"lessonEdits":[]}}
  """,
]

private let fixtureJSONL = """
  {"text":"{\\"kind\\":\\"plan_submit\\",\\"payload\\":{\\"state\\":{\\"immediate\\":{\\"plan\\":\\"## Outcome\\\\nAdd a short README note that says Fixture smoke note.\\\\n\\\\n## Why it matters\\\\nThis proves the CLI fixture loop can plan a small observable documentation edit.\\\\n\\\\n## Acceptance checks\\\\n- README.md contains the sentence Fixture smoke note.\\",\\"verify\\":\\"tessera verify . --json\\",\\"verifyTimeoutMs\\":60000,\\"estimatedDifficulty\\":\\"low\\",\\"selectedBecause\\":\\"This is a tiny deterministic slice for the CLI fixture harness.\\",\\"source\\":\\"repository\\",\\"candidateID\\":null},\\"queue\\":[],\\"brief\\":{\\"summary\\":\\"Smoke test the CompassCLI fixture harness on a generated Tessera workspace.\\",\\"targetUsers\\":[\\"Compass maintainers\\"],\\"desiredOutcomes\\":[\\"A deterministic CLI run edits a file and verifies on host.\\"],\\"constraints\\":[\\"No Tessera dependency for this smoke test.\\"],\\"acceptanceSignals\\":[\\"README.md contains Fixture smoke note.\\"]},\\"openQuestions\\":[]},\\"lessonEdits\\":[]}}"}
  {"text":"{\\"kind\\":\\"develop_continue\\",\\"tool\\":\\"read_file\\",\\"arguments\\":{\\"path\\":\\"README.md\\"},\\"reason\\":\\"Need the current README contents before editing.\\"}"}
  {"text":"{\\"kind\\":\\"develop_continue\\",\\"tool\\":\\"edit_file\\",\\"arguments\\":{\\"path\\":\\"README.md\\",\\"startLine\\":3,\\"endLine\\":2,\\"insert\\":[\\"Fixture smoke note.\\",\\"\\"]},\\"reason\\":\\"Insert the planned smoke-test note near the top of the README.\\"}"}
  {"text":"{\\"kind\\":\\"develop_submit\\",\\"payload\\":{\\"status\\":\\"succeeded\\",\\"summary\\":\\"README.md now includes the Fixture smoke note near the top of the file.\\",\\"feedback\\":\\"README.md contains the Fixture smoke note; Plan can pick the next small Tessera workspace slice.\\",\\"bypassVerify\\":false,\\"lessonEdits\\":[]}}"}
  """
