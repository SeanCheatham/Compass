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

    if case .scaffoldTypeScript(let path, let name, let format) = try CompassCLICommand.parse([
      "scaffold", "typescript", "/tmp/new-project", "--name", "new-project",
    ]) {
      #expect(path.path == "/tmp/new-project")
      #expect(name == "new-project")
      #expect(format == .json)
    } else {
      Issue.record("Expected scaffold command.")
    }

    if case .run(let options, let format) = try CompassCLICommand.parse([
      "run", "--repo", "/tmp/project", "--brief", "Add a slice", "--mode", "fixture",
      "--fixture", "/tmp/fixture.jsonl", "--max-iterations", "3", "--max-develop-attempts", "4",
      "--prompt-log", "/tmp/prompts", "--critic", "--format", "text",
    ]) {
      #expect(options.repoURL.path == "/tmp/project")
      #expect(options.brief == "Add a slice")
      #expect(options.mode == .fixture)
      #expect(options.fixtureURL?.path == "/tmp/fixture.jsonl")
      #expect(options.promptLogDirectory?.path == "/tmp/prompts")
      #expect(options.maxIterations == 3)
      #expect(options.maxDevelopAttempts == 4)
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
    return try await AgentHostBashRunner().run(
      command: command,
      workingDirectory: workingDirectory,
      timeout: timeout
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
  {"kind":"develop_submit","payload":{"status":"succeeded","summary":"Reported the README marker complete before editing it so verify can catch the missing sentence.","feedback":"Verify should fail until README.md contains the exact Retry marker sentence; the next Develop attempt should patch README.md.","bypassVerify":false,"lessonEdits":[]}}
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

private let fixtureJSONL = """
  {"text":"{\\"kind\\":\\"plan_submit\\",\\"payload\\":{\\"state\\":{\\"immediate\\":{\\"plan\\":\\"## Outcome\\\\nAdd a short README note that says Fixture smoke note.\\\\n\\\\n## Why it matters\\\\nThis proves the CLI fixture loop can plan a small observable documentation edit.\\\\n\\\\n## Acceptance checks\\\\n- README.md contains the sentence Fixture smoke note.\\",\\"verify\\":\\"tsc --version\\",\\"verifyTimeoutMs\\":60000,\\"estimatedDifficulty\\":\\"low\\",\\"selectedBecause\\":\\"This is a tiny deterministic slice for the CLI fixture harness.\\",\\"source\\":\\"repository\\",\\"candidateID\\":null},\\"queue\\":[],\\"brief\\":{\\"summary\\":\\"Smoke test the CompassCLI fixture harness on a generated TypeScript workspace.\\",\\"targetUsers\\":[\\"Compass maintainers\\"],\\"desiredOutcomes\\":[\\"A deterministic CLI run edits a file and verifies on host.\\"],\\"constraints\\":[\\"No pnpm dependency for this smoke test.\\"],\\"acceptanceSignals\\":[\\"README.md contains Fixture smoke note.\\"]},\\"openQuestions\\":[]},\\"lessonEdits\\":[]}}"}
  {"text":"{\\"kind\\":\\"develop_continue\\",\\"tool\\":\\"read_file\\",\\"arguments\\":{\\"path\\":\\"README.md\\"},\\"reason\\":\\"Need the current README contents before editing.\\"}"}
  {"text":"{\\"kind\\":\\"develop_continue\\",\\"tool\\":\\"edit_file\\",\\"arguments\\":{\\"path\\":\\"README.md\\",\\"startLine\\":3,\\"endLine\\":2,\\"insert\\":[\\"Fixture smoke note.\\",\\"\\"]},\\"reason\\":\\"Insert the planned smoke-test note near the top of the README.\\"}"}
  {"text":"{\\"kind\\":\\"develop_continue\\",\\"tool\\":\\"bash\\",\\"arguments\\":{\\"command\\":\\"git add README.md && git -c user.name='Compass Agent' -c user.email='compass-agent@localhost' commit -m 'Add fixture smoke note'\\",\\"timeoutSeconds\\":60},\\"reason\\":\\"Commit the README edit so post-check git status is clean.\\"}"}
  {"text":"{\\"kind\\":\\"develop_submit\\",\\"payload\\":{\\"status\\":\\"succeeded\\",\\"summary\\":\\"README.md now includes the Fixture smoke note near the top of the file.\\",\\"feedback\\":\\"README.md contains the Fixture smoke note; Plan can pick the next small TypeScript workspace slice.\\",\\"bypassVerify\\":false,\\"lessonEdits\\":[]}}"}
  """
