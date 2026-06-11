import Foundation
import Testing

@testable import Compass

@Suite("Factory pivot")
struct FactoryPivotTests {
  @Test
  func factoryStateCreatesAndEncodesNewShape() throws {
    let state = FactoryState.empty

    #expect(state.schemaVersion == 1)
    #expect(state.brief == .empty)
    #expect(state.queue.isEmpty)
    #expect(state.immediate == nil)
    #expect(state.completed.isEmpty)
    #expect(state.openQuestions.isEmpty)

    let data = try JSONEncoder().encode(state)
    let json = String(decoding: data, as: UTF8.self)
    #expect(json.contains("\"brief\""))
    #expect(json.contains("\"queue\""))
    #expect(json.contains("\"immediate\""))
    #expect(!json.contains("\"strategicContext\""))
    #expect(!json.contains("\"candidates\""))
  }

  @Test
  func factoryStateDecodesLegacyPlanningShape() throws {
    let legacy = """
      {
        "completed": ["first"],
        "strategicContext": {
          "thesis": "Ship a tiny app",
          "principles": ["Be useful"],
          "risks": ["Verify with tests"]
        },
        "candidates": [
          {
            "id": "slice-one",
            "title": "Add the first slice",
            "outcome": "The workspace has a runnable check",
            "why": "It gives Develop a finish line",
            "category": "test",
            "origin": "plan",
            "priority": "high",
            "status": "available",
            "evidence": [],
            "blockedBy": []
          }
        ]
      }
      """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(FactoryState.self, from: legacy)

    #expect(decoded.schemaVersion == 1)
    #expect(decoded.completed == ["first"])
    #expect(decoded.brief.summary == "Ship a tiny app")
    #expect(decoded.brief.desiredOutcomes == ["Be useful"])
    #expect(decoded.brief.acceptanceSignals == ["Verify with tests"])
    #expect(decoded.queue.map(\.id) == ["slice-one"])
  }

  @Test
  func applyingPlanProposalPreservesOmittedBriefFields() {
    let current = PlanState(
      completed: [],
      immediate: nil,
      brief: PlanStrategicContext(
        summary: "Build decision notes.",
        targetUsers: ["Product teams"],
        desiredOutcomes: ["List decision records"],
        constraints: ["No new dependencies"],
        acceptanceSignals: ["pnpm verify passes"]
      )
    )
    let proposal = PlanProposal(
      immediate: PlanNext(
        plan: "## Outcome\nAdd decision records\n\n## Acceptance checks\n- pnpm verify passes",
        verify: "pnpm verify"
      ),
      candidates: [],
      strategicContext: PlanStrategicContext(summary: "Build decision notes."),
      openQuestions: []
    )

    let next = proposal.applying(to: current)

    #expect(next.brief.summary == "Build decision notes.")
    #expect(next.brief.targetUsers == ["Product teams"])
    #expect(next.brief.desiredOutcomes == ["List decision records"])
    #expect(next.brief.constraints == ["No new dependencies"])
    #expect(next.brief.acceptanceSignals == ["pnpm verify passes"])
  }

  @Test
  func mlxOnlyRuntimeReadiness() {
    let settings = AgentRuntimeSettings()

    #expect(settings.textProvider == .mlx)
    #expect(settings.textProvider.requiresCredentials == false)
    #expect(AgentCapability.allCases == [.text])
    #expect(AgentProviderKind.allCases == [.mlx])
    #expect(settings.model(for: .plan) == LocalModelCatalog.blessedModelID)
    #expect(settings.isTextCapabilityRunnable(localModelReady: true))
    #expect(!settings.isTextCapabilityRunnable(localModelReady: false))
  }

  @Test
  func modelDownloadingGuidesDoNotReportBlocked() {
    let snapshot = LocalModelSnapshot(
      runtimeName: LocalModelCatalog.runtimeName,
      modelID: LocalModelCatalog.blessedModelID,
      status: .downloading,
      progressFraction: 0.42,
      errorMessage: nil,
      directory: URL(fileURLWithPath: "/tmp/CompassModel")
    )
    let settings = AgentRuntimeSettings()

    let settingsGuide = AgentSettingsGuide(settings: settings, modelSnapshot: snapshot)
    #expect(settingsGuide.title == "Local Model Downloading")
    #expect(settingsGuide.actionLabel == "Downloading 42%")
    #expect(settingsGuide.tone == .optionalAttention)
    #expect(settingsGuide.rows.first?.status == .attention)
    #expect(!settingsGuide.actionLabel.localizedCaseInsensitiveContains("blocked"))

  }

  @Test
  func promptsDoNotMentionRemovedDirections() throws {
    let state = PlanProposal(from: FactoryState.empty)
    let next = PlanNext(
      plan: "## Outcome\nAdd a TypeScript slice\n\n## Acceptance checks\n- pnpm verify passes",
      verify: "pnpm verify",
      estimatedDifficulty: .low
    )
    let developSummary = DevelopSummary(
      status: .succeeded,
      summary: "Implemented the slice",
      feedback: "Verified with pnpm verify",
      bypassVerify: false,
      lessonEdits: []
    )
    let prompts = [
      try Prompts.planPrompt(
        state: state,
        completedCount: 0,
        drafts: "",
        feedback: "",
        lessons: "",
        vision: "",
        focus: .feature,
        forgeProfile: .typeScriptPnpmVite
      ),
      Prompts.developPrompt(
        next: next,
        lessons: "",
        vision: "",
        attempt: 1,
        priorIssues: []
      ),
      Prompts.criticPrompt(
        next: next,
        developSummary: developSummary,
        verifyCommand: "pnpm verify",
        verifyExitCode: 0,
        verifyOutput: "ok",
        gitDiff: "",
        priorCritiques: [],
        lessons: "",
        vision: "",
        forgeProfile: .typeScriptPnpmVite,
        iteration: 1,
        maxIterations: 2
      ),
      Prompts.agentSystemPrompt(
        phase: .develop,
        workingDirectoryPath: "/tmp/workspace"
      ),
    ].joined(separator: "\n")

    for removed in [
      "PMF",
      "Product Tournament",
      "MiniMax",
      "OpenAI",
      "Foundation Models",
      "native tool calling",
      "remote providers",
      "Rust",
      "cargo",
    ] {
      #expect(!prompts.contains(removed))
    }
    #expect(prompts.contains("local software factory"))
    #expect(prompts.contains("TypeScript"))
    #expect(prompts.contains("pnpm verify"))
    #expect(prompts.contains("Do not use bare `pnpm test`"))
    #expect(prompts.contains("develop_continue"))
    #expect(prompts.contains("develop_submit"))
  }

  @Test
  func typeScriptScaffoldHasWorkspaceScriptsAndPackages() throws {
    let files = TypeScriptProjectScaffold.files(
      options: .init(projectName: "My Factory App")
    )
    let byPath = Dictionary(uniqueKeysWithValues: files.map { ($0.path, $0.contents) })

    #expect(byPath.keys.contains("pnpm-workspace.yaml"))
    #expect(byPath.keys.contains("package.json"))
    #expect(byPath.keys.contains("tsconfig.base.json"))
    #expect(byPath.keys.contains("packages/core/package.json"))
    #expect(byPath.keys.contains("packages/cli/package.json"))
    #expect(byPath.keys.contains("packages/web/package.json"))

    let rootPackage = try #require(byPath["package.json"])
    #expect(rootPackage.contains("\"verify\": \"pnpm typecheck && pnpm test -- --coverage && pnpm build\""))
    #expect(rootPackage.contains("\"test\": \"vitest run\""))
    #expect(rootPackage.contains("\"build\": \"pnpm -r build\""))
    #expect(rootPackage.contains("\"typecheck\": \"pnpm -r typecheck\""))

    let workspace = try #require(byPath["pnpm-workspace.yaml"])
    #expect(workspace.contains("\"packages/*\""))

    let cliPackage = try #require(byPath["packages/cli/package.json"])
    #expect(cliPackage.contains("\"tsx\""))
    #expect(cliPackage.contains("\"workspace:*\""))

    let webPackage = try #require(byPath["packages/web/package.json"])
    #expect(webPackage.contains("\"vite\""))
    #expect(webPackage.contains("\"react\""))
    #expect(webPackage.contains("\"@types/jsdom\""))
  }

  @Test
  func forgeProfileDefaultsToTypeScriptGeneratedProjects() throws {
    #expect(ForgeProfile.generatedProjectDefault == .typeScriptPnpmVite)
    #expect(ForgeProfile.generatedProjectTargets == [.typeScriptPnpmVite])
    #expect(RepositoryManifestHint.packageJSON.forgeProfile == .typeScriptPnpmVite)

    let tempURL = FileManager.default.temporaryDirectory
      .appending(path: "CompassForgeProfileTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: tempURL,
      withIntermediateDirectories: true,
      attributes: nil
    )
    defer { try? FileManager.default.removeItem(at: tempURL) }
    try TypeScriptProjectScaffold.write(to: tempURL, options: .init(projectName: "Detected App"))

    #expect(TypeScriptProjectScaffold.isGeneratedWorkspace(at: tempURL))
    #expect(ForgeProfileService.detect(in: tempURL) == .typeScriptPnpmVite)
  }

  @Test
  func typeScriptVerifyGateAcceptsCompassStandardVerify() {
    #expect(
      ForgeVerifyValidator.coverageViolation(
        verify: "pnpm verify",
        profile: .typeScriptPnpmVite
      ) == nil
    )
    #expect(
      ForgeVerifyValidator.coverageViolation(
        verify: "pnpm run verify",
        profile: .typeScriptPnpmVite
      ) == nil
    )
    #expect(
      ForgeVerifyValidator.coverageViolation(
        verify: "pnpm typecheck",
        profile: .typeScriptPnpmVite
      ) == nil
    )
    #expect(
      ForgeVerifyValidator.coverageViolation(
        verify: "pnpm test -- --coverage",
        profile: .typeScriptPnpmVite
      ) == nil
    )

    let violation = ForgeVerifyValidator.coverageViolation(
      verify: "pnpm test",
      profile: .typeScriptPnpmVite
    )
    #expect(violation != nil)
    #expect(violation?.contains("pnpm verify") == true)
  }

  @Test
  func coverageRepairNudgeNamesExactTypeScriptVerifyCommand() {
    let error = PlanTransitionValidationError(
      message: "Verify command must collect coverage.",
      reason: .coverageRequirement,
      missingLabels: ["Coverage-ready verify command"],
      rejectedVerify: "pnpm test"
    )

    let nudge = AgentExecutor.submitResultValidationNudge(for: error, phase: .plan)

    #expect(nudge.eventText == "plan_submit rejected")
    #expect(nudge.userMessage.contains("`pnpm test`"))
    #expect(nudge.userMessage.contains("`pnpm verify`"))
    #expect(nudge.userMessage.contains("Do not use bare `pnpm test`"))
  }

  @Test
  func droppedBriefNudgeTellsPlanToResubmitWithoutTools() {
    let error = PlanTransitionValidationError(
      message: """
        Plan tried to drop non-empty brief fields: brief.acceptanceSignals.

        Set `state.brief` exactly to this current brief in the next `plan_submit`:
        ```json
        {"acceptanceSignals":["pnpm verify passes"],"constraints":[],"desiredOutcomes":[],"summary":"Build the slice.","targetUsers":[]}
        ```
        """,
      reason: .invalidStateMutation,
      missingLabels: ["brief.acceptanceSignals"]
    )

    let nudge = AgentExecutor.submitResultValidationNudge(for: error, phase: .plan)

    #expect(nudge.eventText == "plan_submit rejected")
    #expect(nudge.userMessage.contains("Do not call another tool"))
    #expect(nudge.userMessage.contains("copy the current `state.brief` exactly"))
    #expect(nudge.userMessage.contains(#""acceptanceSignals":["pnpm verify passes"]"#))
  }

  @Test
  func planQueueDecodeNudgeTellsPlanToUseEmptyQueueWithoutTools() throws {
    let invalidPayload = """
      {
        "state": {
          "immediate": {
            "plan": "## Outcome\\nAdd decision records.\\n\\n## Acceptance checks\\n- pnpm verify passes",
            "verify": "pnpm verify",
            "verifyTimeoutMs": 600000,
            "estimatedDifficulty": "low",
            "selectedBecause": "First useful slice.",
            "source": "repository",
            "candidateID": null
          },
          "queue": [
            { "title": "Wire the web UI later" }
          ],
          "brief": {
            "summary": "Build decision notes.",
            "targetUsers": [],
            "desiredOutcomes": [],
            "constraints": [],
            "acceptanceSignals": []
          },
          "openQuestions": []
        },
        "lessonEdits": []
      }
      """.data(using: .utf8)!

    do {
      _ = try JSONDecoder().decode(PlanRunResult.self, from: invalidPayload)
      Issue.record("Expected invalid queue payload to fail decoding.")
    } catch {
      let nudge = AgentExecutor.submitResultValidationNudge(for: error, phase: .plan)

      #expect(nudge.eventText == "phase payload contract rejected")
      #expect(nudge.userMessage.contains("Plan queue repair"))
      #expect(nudge.userMessage.contains(#"set `"queue": []`"#))
      #expect(nudge.userMessage.contains("Do not call a tool just to repair queue JSON"))
      #expect(nudge.userMessage.contains("Do not call another tool"))
      #expect(nudge.userMessage.contains("`id`, `title`, `outcome`"))
    }
  }

  @Test
  func weakCLIProofNudgeTellsPlanToRepairWithoutTools() {
    let error = PlanTransitionValidationError(
      message: """
        Plan selected generic `pnpm verify` for new CLI behavior, but the handoff does not include a CLI test or direct proof.

        `pnpm verify` only proves this packet if Develop also adds or updates a test for the claimed CLI behavior, such as `packages/cli/src/main.test.ts`.
        """,
      reason: .weakVerifyCoverage,
      rejectedVerify: "pnpm verify"
    )

    let nudge = AgentExecutor.submitResultValidationNudge(for: error, phase: .plan)

    #expect(nudge.eventText == "plan_submit rejected")
    #expect(nudge.userMessage.contains("Do not call another tool"))
    #expect(nudge.userMessage.contains("packages/cli/src/main.test.ts"))
    #expect(nudge.userMessage.contains(#"main(["--format", "json", "Ship", "it"])"#))
    #expect(nudge.userMessage.contains("parsed JSON title is `Ship it`"))
    #expect(nudge.userMessage.contains("Keep `state.immediate.verify` as `pnpm verify`"))
    #expect(nudge.userMessage.contains("narrow the Outcome to core-only work"))
    #expect(nudge.userMessage.contains("exactly one repair"))
  }

  @Test
  func unfinishedDevelopSuccessNudgeTellsAgentToContinueOrFail() {
    let error = DevelopFeedbackValidationError(
      message:
        "Develop reported status=succeeded, but feedback says planned work remains: `Run pnpm verify`.",
      reason: .unfinishedSuccess,
      feedback: "Run `pnpm verify` to check if the changes pass."
    )

    let nudge = AgentExecutor.submitResultValidationNudge(for: error, phase: .develop)

    #expect(nudge.eventText == "develop_submit feedback rejected")
    #expect(nudge.userMessage.contains("Do not resubmit that success packet"))
    #expect(nudge.userMessage.contains("Return `develop_continue`"))
    #expect(nudge.userMessage.contains("status=failed"))
    #expect(nudge.userMessage.contains("status=blocked"))
    #expect(nudge.userMessage.contains("Return status=succeeded only after"))
    #expect(nudge.userMessage.contains("Detected missing verification command"))
    #expect(nudge.userMessage.contains(#""tool": "bash""#))
    #expect(nudge.userMessage.contains(#""command": "pnpm verify""#))
    #expect(nudge.userMessage.contains("Do not call `read_file`"))
  }

  @Test
  func containerRuntimePromptAndToolsAreTypeScriptOnly() {
    let prompt = Prompts.agentSystemPrompt(
      phase: .develop,
      workingDirectoryPath: "/tmp/workspace"
    )
    let toolNames = Set(ToolRegistry.tools(for: .develop).map(\.spec.name))

    #expect(prompt.contains("containerized Linux runtime"))
    #expect(prompt.contains("/workspace"))
    #expect(prompt.contains("Docker, Xcode, and Homebrew are unavailable"))
    #expect(!toolNames.contains("list_toolchains"))
    #expect(!toolNames.contains("install_toolchain"))
  }

  @Test
  func continuationParserAcceptsValidContinuePerPhase() throws {
    let tools: Set<String> = ["read_file", "bash"]
    for phase in AgentContinuationPhase.allCases {
      let json = """
        {
          "kind": "\(phase.continueKind)",
          "tool": "read-file",
          "arguments": { "path": "package.json" },
          "reason": "Need scripts.",
          "note": "  If scripts exist, choose the matching verify command.  "
        }
        """
      let parsed = try AgentContinuationParser.parse(
        json,
        phase: phase,
        availableToolNames: tools
      )
      guard case .continueTool(let toolName, let arguments, let reason, let note) = parsed.action else {
        Issue.record("Expected continue action")
        return
      }
      #expect(toolName == "read_file")
      #expect(String(decoding: arguments, as: UTF8.self).contains("package.json"))
      #expect(reason == "Need scripts.")
      #expect(note == "If scripts exist, choose the matching verify command.")
    }
  }

  @Test
  func continuationParserUnwrapsSingleJSONCodeFence() throws {
    let json = """
      ```json
      {
        "kind": "plan_continue",
        "tool": "read_file",
        "arguments": {
          "path": "package.json"
        },
        "reason": "Need current package scripts."
      }
      ```
      """
    let parsed = try AgentContinuationParser.parse(
      json,
      phase: .plan,
      availableToolNames: ["read_file"]
    )

    guard case .continueTool(let toolName, let arguments, let reason, let note) = parsed.action else {
      Issue.record("Expected continue action")
      return
    }
    #expect(toolName == "read_file")
    #expect(String(decoding: arguments, as: UTF8.self).contains("package.json"))
    #expect(reason == "Need current package scripts.")
    #expect(note == nil)
  }

  @Test
  func continuationParserSanitizesAndRejectsNotes() throws {
    let emptyNote = try AgentContinuationParser.parse(
      #"{"kind":"develop_continue","tool":"read_file","arguments":{"path":"index.ts"},"note":"   "}"#,
      phase: .develop,
      availableToolNames: ["read_file"]
    )
    guard case .continueTool(_, _, _, let empty) = emptyNote.action else {
      Issue.record("Expected continue action")
      return
    }
    #expect(empty == nil)

    let longNote = String(repeating: "x", count: AgentContinuationParser.noteCharacterLimit + 20)
    let longJSON = """
      {"kind":"develop_continue","tool":"read_file","arguments":{"path":"index.ts"},"note":"\(longNote)"}
      """
    let truncated = try AgentContinuationParser.parse(
      longJSON,
      phase: .develop,
      availableToolNames: ["read_file"]
    )
    guard case .continueTool(_, _, _, let note) = truncated.action else {
      Issue.record("Expected continue action")
      return
    }
    #expect(note?.count == AgentContinuationParser.noteCharacterLimit)

    #expect(throws: AgentContinuationParseError.noteNotString) {
      try AgentContinuationParser.parse(
        #"{"kind":"develop_continue","tool":"read_file","arguments":{"path":"index.ts"},"note":{"next":"edit"}}"#,
        phase: .develop,
        availableToolNames: ["read_file"]
      )
    }
  }

  @Test
  func continuationParserAcceptsValidSubmitPerPhase() throws {
    let payloads: [AgentContinuationPhase: String] = [
      .plan: #"{"state":{"immediate":null,"queue":[],"brief":{"summary":"","targetUsers":[],"desiredOutcomes":[],"constraints":[],"acceptanceSignals":[]},"openQuestions":[]},"lessonEdits":[]}"#,
      .develop: #"{"status":"succeeded","summary":"Done","feedback":"Verified pnpm verify","bypassVerify":false,"lessonEdits":[]}"#,
      .critic: #"{"verdict":"approve","summary":"No blockers","feedback":""}"#,
      .delegate: #"{"findings":"No blockers found."}"#,
    ]

    for phase in AgentContinuationPhase.allCases {
      let json = #"{"kind":"\#(phase.submitKind)","payload":\#(payloads[phase]!)}"#
      let parsed = try AgentContinuationParser.parse(
        json,
        phase: phase,
        availableToolNames: []
      )
      guard case .submit(let payload) = parsed.action else {
        Issue.record("Expected submit action")
        return
      }
      #expect(!payload.isEmpty)
    }
  }

  @Test
  func continuationParserRejectsMalformedAndInvalidContinuations() {
    #expect(throws: AgentContinuationParseError.self) {
      try AgentContinuationParser.parse("not json", phase: .develop, availableToolNames: [])
    }
    #expect(throws: AgentContinuationParseError.self) {
      try AgentContinuationParser.parse(
        """
        Here is the JSON:
        ```json
        {"kind":"develop_continue","tool":"read_file","arguments":{}}
        ```
        """,
        phase: .develop,
        availableToolNames: ["read_file"]
      )
    }
    #expect(throws: AgentContinuationParseError.self) {
      try AgentContinuationParser.parse(
        #"{"kind":"plan_continue","tool":"read_file","arguments":{}}"#,
        phase: .develop,
        availableToolNames: ["read_file"]
      )
    }
    #expect(throws: AgentContinuationParseError.self) {
      try AgentContinuationParser.parse(
        #"{"kind":"develop_continue","tool":"missing","arguments":{}}"#,
        phase: .develop,
        availableToolNames: ["read_file"]
      )
    }
    #expect(throws: AgentContinuationParseError.self) {
      try AgentContinuationParser.parse(
        #"{"kind":"develop_continue","tool":"read_file","arguments":[]}"#,
        phase: .develop,
        availableToolNames: ["read_file"]
      )
    }
  }

  @Test
  func continuationParserExplainsBacktickTemplateLiteralJSON() {
    do {
      _ = try AgentContinuationParser.parse(
        """
        {
          "kind": "develop_continue",
          "tool": "edit_file",
          "arguments": {
            "path": "packages/cli/src/main.ts",
            "startLine": 1,
            "endLine": 1,
            "content": `const one = 1;
        const two = 2;`
          }
        }
        """,
        phase: .develop,
        availableToolNames: ["edit_file"]
      )
      Issue.record("Expected malformed JSON error")
    } catch let error as AgentContinuationParseError {
      let message = error.errorDescription ?? ""
      #expect(message.contains("backtick/template-literal strings are invalid"))
      #expect(message.contains("replacementLines as an array with one source line per string"))
      #expect(message.contains("Do not wrap content in backticks"))
    } catch {
      Issue.record("Expected AgentContinuationParseError, got \(error)")
    }
  }

  @Test
  func executorRunsToolObservationThenSubmitWithFakeRuntime() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    try "export const answer = 42\n".write(
      to: tempURL.appending(path: "index.ts"),
      atomically: true,
      encoding: .utf8
    )

    let runtime = FakeLocalModelRuntime(outputs: [
      #"{"kind":"develop_continue","tool":"read_file","arguments":{"path":"index.ts"},"reason":"Need current exports.","note":"after-read-note: edit this file if it exports answer."}"#,
      #"{"kind":"develop_submit","payload":{"status":"succeeded","summary":"Read the file.","feedback":"Verified with pnpm verify.","bypassVerify":false,"lessonEdits":[]}}"#,
    ])
    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .develop,
        runtime: runtime,
        tools: [AgentReadFileTool()],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.developSchema
      )
    )

    #expect(result.iterations == 2)
    #expect(String(decoding: result.submitResultArguments, as: UTF8.self).contains("succeeded"))
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 2)
    #expect(prompts[1].contains("export const answer"))
    #expect(prompts[1].contains("### Assistant Note (unverified)"))
    #expect(prompts[1].contains("after-read-note: edit this file if it exports answer."))
    if let observationRange = prompts[1].range(of: "### Compass Observation"),
      let noteRange = prompts[1].range(
        of: "### Assistant Note (unverified)",
        range: observationRange.upperBound..<prompts[1].endIndex
      )
    {
      let observationSection = String(prompts[1][observationRange.upperBound..<noteRange.lowerBound])
      #expect(!observationSection.contains("after-read-note"))
    } else {
      Issue.record("Expected separate observation and note sections")
    }
  }

  @Test
  func executorReturnsToolFailureObservationAndCanRecover() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let runtime = FakeLocalModelRuntime(outputs: [
      #"{"kind":"develop_continue","tool":"read_file","arguments":{"path":"missing.ts"},"reason":"Need current contents."}"#,
      #"{"kind":"develop_submit","payload":{"status":"blocked","summary":"The file is missing.","feedback":"Plan should pick an existing file or create missing.ts explicitly.","bypassVerify":true,"lessonEdits":[]}}"#,
    ])
    _ = try await AgentExecutor().run(
      testConfiguration(
        phase: .develop,
        runtime: runtime,
        tools: [AgentReadFileTool()],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.developSchema
      )
    )

    let prompts = await runtime.capturedPrompts()
    #expect(prompts[1].contains(#""isError" : true"#) || prompts[1].contains(#""isError":true"#))
    #expect(prompts[1].contains("File not found"))
  }

  @Test
  func executorEscalatesRepeatedIdenticalToolFailures() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    try """
    export function one() { return 1; }
    export function two() { return 2; }
    export function three() { return 3; }
    """.write(
      to: tempURL.appending(path: "index.ts"),
      atomically: true,
      encoding: .utf8
    )
    let invalidEdit =
      #"{"kind":"develop_continue","tool":"edit_file","arguments":{"path":"index.ts","startLine":1,"endLine":1,"content":"import { next } from './next';\n\nexport function replacement() {\n  return next();\n}\n\nexport function extra() {\n  return 42;\n}"},"reason":"Replace the module."}"#

    let runtime = FakeLocalModelRuntime(outputs: [
      #"{"kind":"develop_continue","tool":"read_file","arguments":{"path":"index.ts"},"reason":"Need current exports."}"#,
      invalidEdit,
      invalidEdit,
      #"{"kind":"develop_submit","payload":{"status":"blocked","summary":"The edit range needs correction.","feedback":"Use a different edit_file range based on read_file output.","bypassVerify":true,"lessonEdits":[]}}"#,
    ])
    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .develop,
        runtime: runtime,
        tools: [AgentReadFileTool(), AgentEditFileTool()],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.developSchema,
        maxIterations: 4
      )
    )

    #expect(result.iterations == 4)
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 4)
    #expect(prompts[3].contains("You repeated the exact same failed `edit_file` call 2 times"))
    #expect(prompts[3].contains("Do not call `edit_file` again with the same arguments"))
    #expect(prompts[3].contains("use its concrete repair shape"))
    #expect(prompts[3].contains("whole-file replacement"))
    #expect(prompts[3].contains("Do not submit"))
    #expect(prompts[3].contains("failed/blocked"))
    #expect(prompts[3].contains("previous edit range was wrong"))
    #expect(prompts[3].contains(#""path":"index.ts""#))
  }

  @Test
  func executorEscalatesRepeatedPartialRewriteFailureFamily() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    try """
    import { current } from "./current";
    export function one() { return 1; }
    export function two() { return 2; }
    export function three() { return 3; }
    export function four() { return 4; }
    export function five() { return 5; }
    """.write(
      to: tempURL.appending(path: "index.ts"),
      atomically: true,
      encoding: .utf8
    )
    let replacement = """
    import { next } from './next';

    export function replacement() {
      return next();
    }

    export function extra() {
      return 42;
    }
    """
    let partialRewriteAtTop =
      #"{"kind":"develop_continue","tool":"edit_file","arguments":{"path":"index.ts","startLine":1,"endLine":1,"content":\#(jsonStringLiteral(replacement))},"reason":"Rewrite the module."}"#
    let partialRewriteShifted =
      #"{"kind":"develop_continue","tool":"edit_file","arguments":{"path":"index.ts","startLine":2,"endLine":2,"content":\#(jsonStringLiteral(replacement))},"reason":"Try a nearby range."}"#

    let runtime = FakeLocalModelRuntime(outputs: [
      #"{"kind":"develop_continue","tool":"read_file","arguments":{"path":"index.ts"},"reason":"Need current exports."}"#,
      partialRewriteAtTop,
      partialRewriteShifted,
      #"{"kind":"develop_submit","payload":{"status":"failed","summary":"Could not repair the edit shape.","feedback":"The edit kept moving the same partial rewrite to nearby ranges.","bypassVerify":false,"lessonEdits":[]}}"#,
    ])
    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .develop,
        runtime: runtime,
        tools: [AgentReadFileTool(), AgentEditFileTool()],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.developSchema,
        maxIterations: 4
      )
    )

    #expect(result.iterations == 4)
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 4)
    #expect(prompts[3].contains("You repeated `edit_file` failures in the same repair family"))
    #expect(prompts[3].contains("Failure family: partial whole-file rewrite"))
    #expect(prompts[3].contains("Changing only `startLine`/`endLine`"))
    #expect(prompts[3].contains("use the full file range"))
    #expect(prompts[3].contains("Do not move the same multi-line replacement"))
    #expect(prompts[3].contains("Latest failure"))
    #expect(prompts[3].contains(#""path":"index.ts""#))
  }

  @Test
  func executorEscalatesRepeatedBodyOnlyFunctionReplacementFamily() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    try """
    export function main(argv = process.argv.slice(2)): string {
      const title = argv.join(" ").trim() || "First Compass task";
      return title;
    }

    console.log(main());
    """.write(
      to: tempURL.appending(path: "main.ts"),
      atomically: true,
      encoding: .utf8
    )
    let bodyOnly = """
      const count = Number.parseInt(argv[0] ?? "1", 10);
      const title = argv.slice(1).join(" ").trim() || "First Compass task";
      return `${count}: ${title}`;
    """
    let replaceDeclarationOnly =
      #"{"kind":"develop_continue","tool":"edit_file","arguments":{"path":"main.ts","startLine":1,"endLine":1,"content":\#(jsonStringLiteral(bodyOnly))},"reason":"Replace main logic."}"#
    let replaceDeclarationAndBody =
      #"{"kind":"develop_continue","tool":"edit_file","arguments":{"path":"main.ts","startLine":1,"endLine":3,"content":\#(jsonStringLiteral(bodyOnly))},"reason":"Try a wider range."}"#

    let runtime = FakeLocalModelRuntime(outputs: [
      #"{"kind":"develop_continue","tool":"read_file","arguments":{"path":"main.ts"},"reason":"Need current main function."}"#,
      replaceDeclarationOnly,
      replaceDeclarationAndBody,
      #"{"kind":"develop_submit","payload":{"status":"failed","summary":"Could not repair the function edit.","feedback":"The edit kept replacing a declaration with body-only lines.","bypassVerify":false,"lessonEdits":[]}}"#,
    ])
    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .develop,
        runtime: runtime,
        tools: [AgentReadFileTool(), AgentEditFileTool()],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.developSchema,
        maxIterations: 4
      )
    )

    #expect(result.iterations == 4)
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 4)
    #expect(prompts[3].contains("You repeated `edit_file` failures in the same repair family"))
    #expect(prompts[3].contains("Failure family: body-only function declaration replacement"))
    #expect(prompts[3].contains("include the complete function declaration"))
    #expect(prompts[3].contains("edit only the body lines inside the function"))
    #expect(prompts[3].contains("Do not replace a function declaration line"))
    #expect(prompts[3].contains(#""path":"main.ts""#))
  }

  @Test
  func executorEscalatesRepeatedReadOnlyDevelopLoopBeforeSubmitRejection() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    try """
    export function main(argv = process.argv.slice(2)): string {
      return argv.join(" ");
    }
    """.write(
      to: tempURL.appending(path: "index.ts"),
      atomically: true,
      encoding: .utf8
    )

    let readIndex =
      #"{"kind":"develop_continue","tool":"read_file","arguments":{"path":"index.ts"},"reason":"Need current line numbers before editing."}"#
    let runtime = FakeLocalModelRuntime(outputs: [
      readIndex,
      readIndex,
      #"{"kind":"develop_submit","payload":{"status":"failed","summary":"Did not edit the CLI.","feedback":"The model repeated reads instead of calling edit_file.","bypassVerify":false,"lessonEdits":[]}}"#,
    ])

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .develop,
        runtime: runtime,
        tools: [AgentReadFileTool()],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.developSchema,
        maxIterations: 3
      )
    )

    #expect(result.iterations == 3)
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 3)
    #expect(prompts[2].contains("You repeated successful read-only Develop tool calls"))
    #expect(prompts[2].contains("Do not call `read_file` again with the same arguments"))
    #expect(prompts[2].contains("Choose exactly one next action"))
    #expect(prompts[2].contains("Call `edit_file` or `write_file`"))
    #expect(prompts[2].contains("status=failed or status=blocked"))
    #expect(prompts[2].contains(#""path":"index.ts""#))
  }

  @Test
  func executorEscalatesRepeatedSuccessfulToolCallsAfterSubmitRejection() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    try #"{"scripts":{"verify":"pnpm verify"}}"#.write(
      to: tempURL.appending(path: "package.json"),
      atomically: true,
      encoding: .utf8
    )

    let planSubmit =
      #"{"kind":"plan_submit","payload":{"state":{"immediate":null,"queue":[],"brief":{"summary":"Build decision notes.","targetUsers":[],"desiredOutcomes":[],"constraints":[],"acceptanceSignals":[]},"openQuestions":[]},"lessonEdits":[]}}"#
    let readPackage =
      #"{"kind":"plan_continue","tool":"read_file","arguments":{"path":"package.json"},"reason":"Need current scripts."}"#
    let validator = RejectFirstPlanSubmitValidator()
    let runtime = FakeLocalModelRuntime(outputs: [
      planSubmit,
      readPackage,
      readPackage,
      planSubmit,
    ])

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .plan,
        runtime: runtime,
        tools: [AgentReadFileTool()],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.planSchema,
        maxIterations: 4,
        validateSubmitResult: { data in
          try validator.validate(data)
        }
      )
    )

    #expect(result.iterations == 4)
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 4)
    #expect(
      prompts[3].contains(
        "Compass already rejected a recent `plan_submit` payload"
      ))
    #expect(prompts[3].contains("called\n`read_file` with the same arguments 2 times")
      || prompts[3].contains("called `read_file` with the same arguments 2 times"))
    #expect(prompts[3].contains("The repeated observation\ndid not repair the rejected continuation")
      || prompts[3].contains("The repeated observation did not repair the rejected continuation"))
    #expect(prompts[3].contains("If the rejected payload said a verify command still needs to run"))
    #expect(prompts[3].contains("Do not call `read_file`, `list_files`, or reread"))
    #expect(prompts[3].contains("Return `plan_submit` with a corrected `payload`"))
    #expect(prompts[3].contains("For Plan, read-only tools cannot repair a rejected handoff"))
    #expect(prompts[3].contains("Latest rejected-payload repair to apply now"))
    #expect(prompts[3].contains("Your previous Plan payload claimed new CLI behavior without proof"))
    #expect(prompts[3].contains("Do not call another tool to repair this"))
    #expect(prompts[3].contains(#"main(["--format", "json", "Ship", "it"])"#))
    #expect(prompts[3].contains(#""path":"package.json""#))
  }

  @Test
  func executorEscalatesRepeatedToolCallsAfterMalformedContinuationRejection() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    try #"{"scripts":{"verify":"pnpm verify"}}"#.write(
      to: tempURL.appending(path: "package.json"),
      atomically: true,
      encoding: .utf8
    )

    let readPackage =
      #"{"kind":"plan_continue","tool":"read_file","arguments":{"path":"package.json"},"reason":"Need current scripts."}"#
    let planSubmit =
      #"{"kind":"plan_submit","payload":{"state":{"immediate":null,"queue":[],"brief":{"summary":"Build decision notes.","targetUsers":[],"desiredOutcomes":[],"constraints":[],"acceptanceSignals":[]},"openQuestions":[]},"lessonEdits":[]}}"#
    let runtime = FakeLocalModelRuntime(outputs: [
      "not valid continuation json",
      readPackage,
      readPackage,
      planSubmit,
    ])

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .plan,
        runtime: runtime,
        tools: [AgentReadFileTool()],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.planSchema,
        maxIterations: 4
      )
    )

    #expect(result.iterations == 4)
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 4)
    #expect(prompts[1].contains("Your previous response could not be used"))
    #expect(prompts[3].contains("malformed Plan continuation response"))
    #expect(prompts[3].contains("called\n`read_file` with the same arguments 2 times")
      || prompts[3].contains("called `read_file` with the same arguments 2 times"))
    #expect(prompts[3].contains("did not repair the rejected continuation"))
    #expect(prompts[3].contains("Do not call `read_file`, `list_files`, or reread"))
    #expect(prompts[3].contains("Return `plan_submit` with a corrected `payload`"))
    #expect(prompts[3].contains("Latest continuation repair to apply now"))
    #expect(prompts[3].contains("Invalid response"))
    #expect(prompts[3].contains(#""path":"package.json""#))
  }

  @Test
  func executorEscalatesRepeatedSubmitRejections() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let weakPlanSubmit =
      #"{"kind":"plan_submit","payload":{"state":{"immediate":null,"queue":[],"brief":{"summary":"Add JSON CLI output.","targetUsers":[],"desiredOutcomes":[],"constraints":[],"acceptanceSignals":[]},"openQuestions":[]},"lessonEdits":[]}}"#
    let runtime = FakeLocalModelRuntime(outputs: [
      weakPlanSubmit,
      weakPlanSubmit,
      weakPlanSubmit,
    ])
    let validator = RejectFirstTwoPlanSubmitValidator()

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .plan,
        runtime: runtime,
        tools: [],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.planSchema,
        maxIterations: 3,
        validateSubmitResult: { data in
          try validator.validate(data)
        }
      )
    )

    #expect(result.iterations == 3)
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 3)
    #expect(prompts[1].contains("Your previous Plan payload claimed new CLI behavior without proof"))
    #expect(prompts[2].contains("Compass rejected `plan_submit` for the same reason 2 times"))
    #expect(prompts[2].contains("Do not return the same payload again"))
    #expect(prompts[2].contains("Plan repair checklist"))
    #expect(prompts[2].contains("Do not resubmit the same `state.immediate.plan`"))
    #expect(prompts[2].contains("Keep `state.immediate.verify` as `pnpm verify`"))
    #expect(prompts[2].contains(#"main(["--format", "json", "Ship", "it"])"#))
    #expect(prompts[2].contains("Latest rejected-payload repair to apply now"))
  }

  @Test
  func executorGivesConcreteVerifyCommandAfterUnfinishedDevelopSuccess() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    try #"{"scripts":{"verify":"pnpm verify"}}"#.write(
      to: tempURL.appending(path: "package.json"),
      atomically: true,
      encoding: .utf8
    )

    let unfinishedSubmit =
      #"{"kind":"develop_submit","payload":{"status":"succeeded","summary":"Edited main.ts.","feedback":"Run `pnpm verify` to check if the changes meet the acceptance criteria.","bypassVerify":false,"lessonEdits":[]}}"#
    let readPackage =
      #"{"kind":"develop_continue","tool":"read_file","arguments":{"path":"package.json"},"reason":"Need current package scripts."}"#
    let runVerify =
      #"{"kind":"develop_continue","tool":"bash","arguments":{"command":"pnpm verify"},"reason":"Run the missing verification command before submitting success."}"#
    let finishedSubmit =
      #"{"kind":"develop_submit","payload":{"status":"succeeded","summary":"Verified the completed packet.","feedback":"Verified with pnpm verify; no follow-up work remains.","bypassVerify":false,"lessonEdits":[]}}"#
    let runtime = FakeLocalModelRuntime(outputs: [
      unfinishedSubmit,
      readPackage,
      readPackage,
      runVerify,
      finishedSubmit,
    ])

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .develop,
        runtime: runtime,
        tools: [
          AgentReadFileTool(),
          FakeBashTool(output: "[stdout]\nAll checks passed.\n\n[exit 0]\n\n[next]\nSubmit success."),
        ],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.developSchema,
        maxIterations: 5,
        validateSubmitResult: { data in
          let summary = try JSONDecoder().decode(DevelopSummary.self, from: data)
          try DevelopFeedbackValidator.validate(summary)
        }
      )
    )

    #expect(result.iterations == 5)
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 5)
    #expect(prompts[1].contains("Detected missing verification command"))
    #expect(prompts[1].contains(#""tool": "bash""#))
    #expect(prompts[1].contains(#""command": "pnpm verify""#))
    #expect(prompts[1].contains("Do not call `read_file`"))
    #expect(prompts[3].contains("If the rejected payload said a verify command still needs to run"))
    #expect(prompts[3].contains("Do not call `read_file`, `list_files`, or reread"))
  }

  @Test
  func executorRejectsFailedDevelopSubmitAfterSuccessfulVerify() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let runtime = FakeLocalModelRuntime(outputs: [
      #"{"kind":"develop_continue","tool":"bash","arguments":{"command":"pnpm verify"},"reason":"Run verification."}"#,
      #"{"kind":"develop_submit","payload":{"status":"failed","summary":"Typecheck failed due to a missing summarizeQueue import.","feedback":"Fix the summarizeQueue import before trying again.","bypassVerify":false,"lessonEdits":[]}}"#,
      #"{"kind":"develop_submit","payload":{"status":"succeeded","summary":"Verification passed after the requested changes.","feedback":"Verified with pnpm verify; the packet is ready for Plan.","bypassVerify":false,"lessonEdits":[]}}"#,
    ])

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .develop,
        runtime: runtime,
        tools: [FakeBashTool(output: "[stdout]\nAll checks passed.\n\n[exit 0]\n\n[next]\nSubmit success.")],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.developSchema,
        maxIterations: 3
      )
    )

    #expect(result.iterations == 3)
    #expect(String(decoding: result.submitResultArguments, as: UTF8.self).contains("succeeded"))
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 3)
    #expect(prompts[1].contains("Compass observed `pnpm verify` exit 0"))
    #expect(prompts[2].contains("Compass already observed this verify command pass"))
    #expect(prompts[2].contains("status=failed, bypassVerify=false"))
    #expect(prompts[2].contains("return `develop_submit` again with"))
  }

  @Test
  func executorClearsSuccessfulVerifyAfterFileMutation() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let runtime = FakeLocalModelRuntime(outputs: [
      #"{"kind":"develop_continue","tool":"bash","arguments":{"command":"pnpm verify"},"reason":"Run baseline verification."}"#,
      #"{"kind":"develop_continue","tool":"write_file","arguments":{"path":"generated.ts","content":"export const generated = true;\n"},"reason":"Repair missing acceptance check: generated.ts must exist after verify."}"#,
      #"{"kind":"develop_submit","payload":{"status":"failed","summary":"A later file mutation still needs verification.","feedback":"Run pnpm verify after generated.ts was created.","bypassVerify":false,"lessonEdits":[]}}"#,
    ])

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .develop,
        runtime: runtime,
        tools: [
          FakeBashTool(output: "[stdout]\nBaseline passed.\n\n[exit 0]\n\n[next]\nSubmit success."),
          AgentWriteFileTool(),
        ],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.developSchema,
        maxIterations: 3
      )
    )

    #expect(result.iterations == 3)
    #expect(String(decoding: result.submitResultArguments, as: UTF8.self).contains("failed"))
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 3)
    #expect(prompts[1].contains("Compass observed `pnpm verify` exit 0"))
    #expect(prompts[2].contains("You just changed files with `write_file` after Compass observed `pnpm verify` exit 0"))
    #expect(prompts[2].contains("That earlier verify result no longer proves the current worktree"))
    #expect(prompts[2].contains("call `bash` with `pnpm verify` again"))
    #expect(!prompts[2].contains("Compass already observed this verify command pass"))
  }

  @Test
  func executorRejectsGenericFileMutationAfterSuccessfulVerify() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let runtime = FakeLocalModelRuntime(outputs: [
      #"{"kind":"develop_continue","tool":"bash","arguments":{"command":"pnpm verify"},"reason":"Run verification."}"#,
      #"{"kind":"develop_continue","tool":"write_file","arguments":{"path":"generated.ts","content":"export const generated = true;\n"},"reason":"Create the file after verify."}"#,
      #"{"kind":"develop_submit","payload":{"status":"succeeded","summary":"The packet was already verified.","feedback":"Verified with pnpm verify; no follow-up work remains.","bypassVerify":false,"lessonEdits":[]}}"#,
    ])

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .develop,
        runtime: runtime,
        tools: [
          FakeBashTool(output: "[stdout]\nAll checks passed.\n\n[exit 0]\n\n[next]\nSubmit success."),
          AgentWriteFileTool(),
        ],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.developSchema,
        maxIterations: 3
      )
    )

    #expect(result.iterations == 3)
    #expect(!FileManager.default.fileExists(atPath: tempURL.appending(path: "generated.ts").path))
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 3)
    #expect(prompts[1].contains("Compass observed `pnpm verify` exit 0"))
    #expect(prompts[2].contains("A generic `write_file` call after a"))
    #expect(prompts[2].contains("passing verify would invalidate that proof"))
    #expect(prompts[2].contains("retry `write_file` only with a `reason`"))
    #expect(prompts[2].contains("explicitly names the missing acceptance check"))
    #expect(String(decoding: result.submitResultArguments, as: UTF8.self).contains("succeeded"))
  }

  @Test
  func executorCompactsContinuationHistoryWithoutCountingAnAgentIteration() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    for index in 1...5 {
      try "export const answer\(index) = \(index)\n".write(
        to: tempURL.appending(path: "file\(index).ts"),
        atomically: true,
        encoding: .utf8
      )
    }

    let continues = (1...5).map { index in
      #"{"kind":"develop_continue","tool":"read_file","arguments":{"path":"file\#(index).ts"},"reason":"Read pass \#(index)."}"#
    }
    let summary = """
      Goal / Current Phase
      Develop is reading small fixture files before deciding.

      Established Facts
      Older summary from compactor.

      Files / Symbols
      Small fixture files have been read in prior turns.

      Errors / Repairs
      None.

      Current Step / Next Action
      Continue from the latest raw observation.
      """
    let runtime = FakeLocalModelRuntime(outputs: continues + [
      summary,
      #"{"kind":"develop_submit","payload":{"status":"succeeded","summary":"Compaction preserved enough context.","feedback":"Verified with pnpm verify.","bypassVerify":false,"lessonEdits":[]}}"#,
    ])

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .develop,
        settings: AgentRuntimeSettings(contextWindowTokens: 300),
        runtime: runtime,
        tools: [AgentReadFileTool()],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.developSchema,
        maxIterations: 6
      )
    )

    #expect(result.iterations == 6)
    #expect(result.tokenUsage.compactionCount == 1)
    #expect(result.tokenUsage.summaryTokens > 0)

    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 7)
    #expect(prompts[5].contains("## Raw History To Compact"))
    #expect(prompts[5].contains("## Latest Raw History Kept Verbatim"))

    let finalPrompt = prompts[6]
    #expect(finalPrompt.contains("## Compacted History"))
    #expect(finalPrompt.contains("lower authority than real `Compass Observation` entries"))
    #expect(finalPrompt.contains("Older summary from compactor"))
    #expect(finalPrompt.contains("Read pass 5."))
    #expect(!finalPrompt.contains("Read pass 1."))
  }

  @Test
  func executorRepairsMalformedOutput() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let runtime = FakeLocalModelRuntime(outputs: [
      "I am done.",
      #"{"kind":"critic_submit","payload":{"verdict":"approve","summary":"No blockers.","feedback":""}}"#,
    ])
    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .critic,
        runtime: runtime,
        tools: [],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.criticSchema
      )
    )

    #expect(result.iterations == 2)
    let prompts = await runtime.capturedPrompts()
    #expect(prompts[1].contains("could not be used"))
    #expect(prompts[1].contains("critic_submit"))
  }

  @Test
  func executorEscalatesRepeatedMalformedSubmitJSONAcrossToolReads() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    try #"{"scripts":{"verify":"pnpm verify"}}"#.write(
      to: tempURL.appending(path: "package.json"),
      atomically: true,
      encoding: .utf8
    )

    let malformedPlanSubmit = """
      ```json
      {
        "kind": "plan_submit",
        "payload": {
          "state": {
            "immediate": {
              "plan": "## Outcome\\nAdd count support.\\n\\n## Acceptance checks\\n- main(["--count", "3", "Ship", "it"]) returns 3 open / 3 total.",
              "verify": "pnpm verify"
            },
            "queue": [],
            "brief": {
              "summary": "Add count support.",
              "targetUsers": [],
              "desiredOutcomes": [],
              "constraints": [],
              "acceptanceSignals": []
            },
            "openQuestions": []
          },
          "lessonEdits": []
        }
      }
      ```
      """
    let readPackage =
      #"{"kind":"plan_continue","tool":"read_file","arguments":{"path":"package.json"},"reason":"Need current scripts."}"#
    let validPlanSubmit =
      #"{"kind":"plan_submit","payload":{"state":{"immediate":null,"queue":[],"brief":{"summary":"Build decision notes.","targetUsers":[],"desiredOutcomes":[],"constraints":[],"acceptanceSignals":[]},"openQuestions":[]},"lessonEdits":[]}}"#
    let runtime = FakeLocalModelRuntime(outputs: [
      malformedPlanSubmit,
      readPackage,
      malformedPlanSubmit,
      validPlanSubmit,
    ])

    let result = try await AgentExecutor().run(
      testConfiguration(
        phase: .plan,
        runtime: runtime,
        tools: [AgentReadFileTool()],
        workingDirectory: tempURL,
        submitResultSchema: Prompts.planSchema,
        maxIterations: 4
      )
    )

    #expect(result.iterations == 4)
    let prompts = await runtime.capturedPrompts()
    #expect(prompts.count == 4)
    #expect(prompts[3].contains("Compass rejected malformed `plan_submit` JSON 2 times"))
    #expect(prompts[3].contains("This is a JSON syntax problem"))
    #expect(prompts[3].contains("Do not call\n`read_file`")
      || prompts[3].contains("Do not call `read_file`"))
    #expect(prompts[3].contains("quotes inside string fields must be escaped"))
    #expect(prompts[3].contains("For Plan, do not call more tools"))
    #expect(prompts[3].contains("Return exactly one valid JSON object now"))
  }

  @Test
  func executorStopsAtMaxIterationsAndWallClock() async throws {
    let tempURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let malformedRuntime = FakeLocalModelRuntime(outputs: ["nope"])
    await #expect(throws: AgentExecutionError.self) {
      try await AgentExecutor().run(
        testConfiguration(
          phase: .develop,
          runtime: malformedRuntime,
          tools: [],
          workingDirectory: tempURL,
          submitResultSchema: Prompts.developSchema,
          maxIterations: 1
        )
      )
    }

    let slowRuntime = FakeLocalModelRuntime(outputs: ["nope", "nope"], delayNanoseconds: 20_000_000)
    await #expect(throws: AgentExecutionError.self) {
      try await AgentExecutor().run(
        testConfiguration(
          phase: .develop,
          runtime: slowRuntime,
          tools: [],
          workingDirectory: tempURL,
          submitResultSchema: Prompts.developSchema,
          maxIterations: 4,
          wallClockTimeout: 0.001
        )
      )
    }
  }

  @Test
  func localModelLeaseAllowsOneLoadedModelAndUnloadsAfterIdle() async throws {
    await LocalModelLease.shared.resetForTesting()
    await LocalModelLease.shared.setIdleTimeoutForTesting(seconds: 0.01)
    try await LocalModelLease.shared.beginRun(modelID: "model-a")
    await #expect(throws: LocalModelRuntimeError.self) {
      try await LocalModelLease.shared.beginRun(modelID: "model-b")
    }
    await LocalModelLease.shared.endRun(modelID: "model-a")
    var snapshot = await LocalModelLease.shared.snapshot()
    let deadline = Date().addingTimeInterval(1)
    while snapshot.loadedModelID != nil, Date() < deadline {
      try await Task.sleep(nanoseconds: 10_000_000)
      snapshot = await LocalModelLease.shared.snapshot()
    }
    #expect(snapshot.loadedModelID == nil)
    #expect(snapshot.activeRunCount == 0)
    await LocalModelLease.shared.resetForTesting()
  }

  @Test
  func localModelCatalogMissingAndReadyStates() throws {
    let missingURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: missingURL) }
    LocalModelCatalog.withTestingModelDirectory(missingURL) {
      #expect(!LocalModelCatalog.isBlessedModelReady())
      #expect(LocalModelCatalog.snapshot().status == .missing)
    }

    let readyURL = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: readyURL) }
    try "{}".write(to: readyURL.appending(path: "config.json"), atomically: true, encoding: .utf8)
    try "{}".write(to: readyURL.appending(path: "tokenizer.json"), atomically: true, encoding: .utf8)
    try Data([0]).write(to: readyURL.appending(path: "model.safetensors"))
    LocalModelCatalog.withTestingModelDirectory(readyURL) {
      #expect(LocalModelCatalog.isBlessedModelReady())
      #expect(LocalModelCatalog.snapshot().status == .ready)
    }
  }
}

private actor FakeLocalModelRuntime: LocalModelGenerating {
  private var outputs: [String]
  private var requests: [LocalModelGenerationRequest] = []
  private let delayNanoseconds: UInt64

  init(outputs: [String], delayNanoseconds: UInt64 = 0) {
    self.outputs = outputs
    self.delayNanoseconds = delayNanoseconds
  }

  func generateText(request: LocalModelGenerationRequest) async throws -> LocalModelGenerationResult {
    requests.append(request)
    if delayNanoseconds > 0 {
      try await Task.sleep(nanoseconds: delayNanoseconds)
    }
    guard !outputs.isEmpty else {
      throw LocalModelRuntimeError.generationFailed("Fake runtime has no queued output.")
    }
    let text = outputs.removeFirst()
    return LocalModelGenerationResult(
      text: text,
      tokenUsage: .estimated(
        inputCharacters: request.systemPrompt.count + request.prompt.count,
        outputCharacters: text.count
      )
    )
  }

  func capturedPrompts() -> [String] {
    requests.map(\.prompt)
  }
}

private final class RejectFirstPlanSubmitValidator: @unchecked Sendable {
  private let lock = NSLock()
  private var attempts = 0

  func validate(_ data: Data) throws {
    lock.lock()
    attempts += 1
    let attempt = attempts
    lock.unlock()

    if attempt == 1 {
      throw PlanTransitionValidationError(
        message:
          "Plan selected generic `pnpm verify` for new CLI behavior, but the handoff does not include a CLI test or direct proof.",
        reason: .weakVerifyCoverage,
        rejectedVerify: "pnpm verify"
      )
    }
    _ = try JSONDecoder().decode(PlanRunResult.self, from: data)
  }
}

private final class RejectFirstTwoPlanSubmitValidator: @unchecked Sendable {
  private let lock = NSLock()
  private var attempts = 0

  func validate(_ data: Data) throws {
    lock.lock()
    attempts += 1
    let attempt = attempts
    lock.unlock()

    if attempt <= 2 {
      throw PlanTransitionValidationError(
        message:
          "Plan selected generic `pnpm verify` for new CLI behavior, but the handoff does not include a CLI test or direct proof.",
        reason: .weakVerifyCoverage,
        rejectedVerify: "pnpm verify"
      )
    }
    _ = try JSONDecoder().decode(PlanRunResult.self, from: data)
  }
}

private struct FakeBashTool: AgentTool {
  var output: String
  var spec: AgentToolSpec {
    AgentToolSpec(
      name: AgentBashTool.toolName,
      description: "Fake bash tool.",
      parameters: AgentToolParametersSchema(literal: [
        "type": "object",
        "additionalProperties": true,
      ])
    )
  }

  func invoke(arguments: Data, context: AgentToolContext) async throws -> AgentToolInvocationResult {
    .ok(output)
  }
}

private func makeTempDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appending(path: "CompassFactoryPivotTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

private func jsonStringLiteral(_ value: String) -> String {
  let data = (try? JSONEncoder().encode(value)) ?? Data(#""""#.utf8)
  return String(decoding: data, as: UTF8.self)
}

private func testConfiguration(
  phase: AgentPhase,
  settings: AgentRuntimeSettings = AgentRuntimeSettings(),
  runtime: any LocalModelGenerating,
  tools: [AgentTool],
  workingDirectory: URL,
  submitResultSchema: String,
  maxIterations: Int = 8,
  wallClockTimeout: TimeInterval = 60,
  validateSubmitResult: (@Sendable (Data) throws -> Void)? = nil
) -> AgentExecutionConfiguration {
  AgentExecutionConfiguration(
    settings: settings,
    phase: phase,
    systemPrompt: Prompts.agentSystemPrompt(
      phase: phase,
      workingDirectoryPath: workingDirectory.path,
      executionEnvironment: .host
    ),
    userPrompt: "Test phase packet.",
    tools: tools,
    modelRuntime: runtime,
    submitResultSchema: AgentToolParametersSchema(json: Data(submitResultSchema.utf8)),
    workingDirectory: workingDirectory,
    validateSubmitResult: validateSubmitResult ?? { data in
      switch phase {
      case .plan:
        _ = try JSONDecoder().decode(PlanRunResult.self, from: data)
      case .develop:
        _ = try JSONDecoder().decode(DevelopSummary.self, from: data)
      case .critic:
        _ = try JSONDecoder().decode(CriticVerdict.self, from: data)
      }
    },
    maxIterations: maxIterations,
    wallClockTimeout: wallClockTimeout
  )
}
