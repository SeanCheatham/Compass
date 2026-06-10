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
          "reason": "Need scripts."
        }
        """
      let parsed = try AgentContinuationParser.parse(
        json,
        phase: phase,
        availableToolNames: tools
      )
      guard case .continueTool(let toolName, let arguments, let reason) = parsed.action else {
        Issue.record("Expected continue action")
        return
      }
      #expect(toolName == "read_file")
      #expect(String(decoding: arguments, as: UTF8.self).contains("package.json"))
      #expect(reason == "Need scripts.")
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

    guard case .continueTool(let toolName, let arguments, let reason) = parsed.action else {
      Issue.record("Expected continue action")
      return
    }
    #expect(toolName == "read_file")
    #expect(String(decoding: arguments, as: UTF8.self).contains("package.json"))
    #expect(reason == "Need current package scripts.")
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
      #"{"kind":"develop_continue","tool":"read_file","arguments":{"path":"index.ts"},"reason":"Need current exports."}"#,
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
    try await Task.sleep(nanoseconds: 40_000_000)
    let snapshot = await LocalModelLease.shared.snapshot()
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

private func makeTempDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appending(path: "CompassFactoryPivotTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

private func testConfiguration(
  phase: AgentPhase,
  runtime: any LocalModelGenerating,
  tools: [AgentTool],
  workingDirectory: URL,
  submitResultSchema: String,
  maxIterations: Int = 8,
  wallClockTimeout: TimeInterval = 60
) -> AgentExecutionConfiguration {
  AgentExecutionConfiguration(
    settings: AgentRuntimeSettings(),
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
    validateSubmitResult: { data in
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
