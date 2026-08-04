import Foundation
import Testing

@testable import CompassCore

@Suite("Bash mutation policy")
struct AgentBashMutationPolicyTests {
  @Test
  func developAllowsMutation() {
    #expect(AgentBashMutationPolicy.allowsMutation(for: .develop))
    #expect(!AgentBashMutationPolicy.allowsMutation(for: .plan))
    #expect(!AgentBashMutationPolicy.allowsMutation(for: .critic))
  }

  @Test(arguments: [
    "rm -rf src",
    "echo hi > out.txt",
    "git commit -am 'x'",
    "git add .",
    "mkdir -p foo",
    "sed -i '' 's/a/b/' file.swift",
    "tee output.log",
    "python3 -c 'open(\"f\",\"w\").write(\"x\")'",
    "ruby -e 'File.write(\"f\",\"x\")'",
    "node -e 'require(\"fs\").writeFileSync(\"f\",\"x\")'",
    "cargo fmt --all",
    "npm install lodash",
    "git update-ref refs/heads/x HEAD",
  ])
  func rejectsMutatingCommands(_ command: String) {
    #expect(AgentBashMutationPolicy.mutationRejectionReason(for: command) != nil)
  }

  @Test(arguments: [
    "git status",
    "git diff HEAD",
    "git log -1 --oneline",
    "cargo test --workspace",
    "cargo fmt --all --check",
    "ls -la",
    "rg 'fn main' crates",
    "echo hello 2>/dev/null",
    "python3 -m json.tool < file.json",
  ])
  func allowsReadOnlyCommands(_ command: String) {
    #expect(AgentBashMutationPolicy.mutationRejectionReason(for: command) == nil)
  }

  @Test
  func planPhaseBashRejectsMutationBeforeRunning() async throws {
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("compass-bash-policy-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let runner = CountingBashRunner()
    let context = AgentToolContext(
      workingDirectory: tempURL,
      bashRunner: runner,
      phase: .plan
    )
    let result = try await AgentBashTool().invoke(
      arguments: Data(#"{"command":"rm -rf src"}"#.utf8),
      context: context
    )
    #expect(result.isError)
    #expect(result.errorKind == .bashFailure)
    #expect(result.content.contains("read-only"))
    #expect(await runner.invocationCount == 0)
  }

  @Test
  func developPhaseBashAllowsMutation() async throws {
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("compass-bash-policy-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let runner = CountingBashRunner()
    let context = AgentToolContext(
      workingDirectory: tempURL,
      bashRunner: runner,
      phase: .develop
    )
    let result = try await AgentBashTool().invoke(
      arguments: Data(#"{"command":"rm -rf src"}"#.utf8),
      context: context
    )
    #expect(!result.isError)
    #expect(await runner.invocationCount == 1)
  }
}

@Suite("Delegate profiles and structured findings")
struct AgentDelegateProfileTests {
  @Test
  func exploreProfileIsReadOnly() throws {
    let names = try AgentExecutorDelegateRunner.toolNames(forProfile: "explore") ?? []
    #expect(names.contains(AgentReadFileTool.toolName))
    #expect(names.contains(AgentListFilesTool.toolName))
    #expect(!names.contains(AgentBashTool.toolName))
    #expect(!names.contains(AgentWriteFileTool.toolName))
  }

  @Test
  func verifyProfileIncludesBash() throws {
    let names = try AgentExecutorDelegateRunner.toolNames(forProfile: "verify") ?? []
    #expect(names.contains(AgentBashTool.toolName))
    #expect(names.contains(AgentReadFileTool.toolName))
    #expect(!names.contains(AgentWriteFileTool.toolName))
  }

  @Test
  func repairProfileUsesFullParentToolSet() throws {
    #expect(try AgentExecutorDelegateRunner.toolNames(forProfile: "repair") == nil)
  }

  @Test
  func unknownProfileFailsClosed() {
    #expect(throws: AgentDelegateRunnerError.self) {
      _ = try AgentExecutorDelegateRunner.validatedProfile("admin")
    }
    #expect(throws: AgentDelegateRunnerError.self) {
      _ = try AgentExecutorDelegateRunner.toolNames(forProfile: "admin")
    }
  }

  @Test
  func structuredFindingsFormatIncludesSections() {
    let payload = SubAgentResult(
      findings: "Symbol X is only used in cli.",
      filesRead: ["crates/cli/src/main.rs"],
      commandsRun: ["rg SymbolX"],
      openQuestions: ["Should macos also import it?"]
    )
    let text = payload.formattedToolResult()
    #expect(text.contains("Symbol X is only used in cli."))
    #expect(text.contains("[filesRead]\ncrates/cli/src/main.rs"))
    #expect(text.contains("[commandsRun]\nrg SymbolX"))
    #expect(text.contains("[openQuestions]\nShould macos also import it?"))
  }

  @Test
  func findingsOnlyPayloadStillDecodes() throws {
    let data = Data(#"{"findings":"ok"}"#.utf8)
    let payload = try JSONDecoder().decode(SubAgentResult.self, from: data)
    #expect(payload.findings == "ok")
    #expect(payload.filesRead.isEmpty)
    #expect(payload.formattedToolResult() == "ok")
  }
}

private actor CountingBashRunner: AgentBashRunner {
  private(set) var invocationCount = 0

  func run(
    command _: String,
    workingDirectory _: URL,
    timeout _: TimeInterval
  ) async throws -> ProcessResult {
    invocationCount += 1
    return ProcessResult(exitCode: 0, stdout: "ok\n", stderr: "")
  }
}
