import Foundation
import OpenAI
import Testing

@testable import Compass

struct AgentExecutorTests {
  // MARK: - stripThinkBlocks

  @Test func testStripThinkBlocksOnPlainTextIsNoop() throws {
    let (text, reasoning) = AgentExecutor.stripThinkBlocks("hello world")
    try #require(text == "hello world")
    try #require(reasoning == "")
  }

  @Test func testStripThinkBlocksExtractsSingleBlock() throws {
    let (text, reasoning) = AgentExecutor.stripThinkBlocks("before <think>secret</think> after")
    try #require(text == "before  after")
    try #require(reasoning == "secret")
  }

  @Test func testStripThinkBlocksExtractsMultipleBlocks() throws {
    let (text, reasoning) = AgentExecutor.stripThinkBlocks(
      "a<think>one</think>b<think>two</think>c")
    try #require(text == "abc")
    try #require(reasoning == "onetwo")
  }

  @Test func testStripThinkBlocksHandlesUnterminatedBlock() throws {
    let (text, reasoning) = AgentExecutor.stripThinkBlocks("visible <think>oops never closed")
    try #require(text == "visible ")
    try #require(reasoning == "oops never closed")
  }

  // MARK: - Budget exhaustion classification

  @Test func testIsAgentBudgetExhaustionCoversWallClockAndIterationLimits() throws {
    try #require(AgentExecutionError.wallClockExceeded(3600).isAgentBudgetExhaustion)
    try #require(AgentExecutionError.maxIterationsExceeded(512).isAgentBudgetExhaustion)
  }

  @Test func testIsAgentBudgetExhaustionRejectsNonBudgetCauses() throws {
    try #require(!AgentExecutionError.cancelled.isAgentBudgetExhaustion)
    try #require(!AgentExecutionError.streamFailed("boom").isAgentBudgetExhaustion)
    try #require(!AgentExecutionError.modelStoppedWithoutSubmitResult.isAgentBudgetExhaustion)
    try #require(
      !AgentExecutionError.toolCallDecodeFailed(name: "x", detail: "y").isAgentBudgetExhaustion
    )
    try #require(!AgentExecutionError.duplicateToolName("z").isAgentBudgetExhaustion)
  }

  @Test func testDefaultWallClockTimeoutIsOneHour() throws {
    let configuration = makeConfiguration(phase: .plan, tools: ToolRegistry.readOnlyTools())
    try #require(configuration.wallClockTimeout == 60 * 60)
  }

  // MARK: - Transient stream-error classification

  @Test func testTransientHTTPStatusesCoverOverloadAndCloudflareCodes() throws {
    let transient = [408, 425, 429, 500, 502, 503, 504, 520, 521, 522, 523, 524, 525, 526, 529]
    for code in transient {
      try #require(
        AgentExecutor.isTransientHTTPStatus(code),
        "Expected \(code) to be classified transient"
      )
    }
  }

  @Test func testTransientHTTPStatusesRejectClientAndSuccessCodes() throws {
    let permanent = [200, 201, 204, 301, 400, 401, 403, 404, 422, 451]
    for code in permanent {
      try #require(
        !AgentExecutor.isTransientHTTPStatus(code),
        "Expected \(code) to be classified permanent"
      )
    }
  }

  @Test func testShouldRetryAcceptsOpenAIStatusErrorsForTransientStatuses() throws {
    let response = HTTPURLResponse(
      url: URL(string: "https://api.example.com")!,
      statusCode: 529,
      httpVersion: nil,
      headerFields: nil
    )!
    let error = OpenAIError.statusError(response: response, statusCode: 529)
    try #require(AgentExecutor.shouldRetry(error))
  }

  @Test func testShouldRetryRejectsOpenAIStatusErrorsForPermanentStatuses() throws {
    let response = HTTPURLResponse(
      url: URL(string: "https://api.example.com")!,
      statusCode: 400,
      httpVersion: nil,
      headerFields: nil
    )!
    let error = OpenAIError.statusError(response: response, statusCode: 400)
    try #require(!AgentExecutor.shouldRetry(error))
  }

  @Test func testShouldRetryAcceptsTransientURLErrors() throws {
    try #require(AgentExecutor.shouldRetry(URLError(.timedOut)))
    try #require(AgentExecutor.shouldRetry(URLError(.networkConnectionLost)))
    try #require(AgentExecutor.shouldRetry(URLError(.notConnectedToInternet)))
  }

  @Test func testShouldRetryRejectsPermanentURLErrors() throws {
    try #require(!AgentExecutor.shouldRetry(URLError(.badURL)))
    try #require(!AgentExecutor.shouldRetry(URLError(.unsupportedURL)))
    try #require(!AgentExecutor.shouldRetry(URLError(.cancelled)))
  }

  @Test func testShouldRetryRejectsUnrelatedErrors() throws {
    struct OtherError: Error {}
    try #require(!AgentExecutor.shouldRetry(OtherError()))
    try #require(!AgentExecutor.shouldRetry(AgentExecutionError.cancelled))
  }

  @Test func testRetryDelayGrowsExponentiallyWithJitterAndCaps() throws {
    // Attempt 1 should sit around 1s (0.8 - 1.2 with jitter).
    let first = AgentExecutor.retryDelay(forAttempt: 1)
    try #require(first >= AgentExecutor.baseStreamRetryDelay * 0.8)
    try #require(first <= AgentExecutor.baseStreamRetryDelay * 1.2)

    // Attempt 4 = base * 2^3 = 8s before jitter, well under the cap.
    let fourth = AgentExecutor.retryDelay(forAttempt: 4)
    try #require(fourth >= 8.0 * 0.8)
    try #require(fourth <= 8.0 * 1.2)

    // Attempt 100 would explode to 2^99 seconds; the cap must hold.
    let huge = AgentExecutor.retryDelay(forAttempt: 100)
    try #require(huge >= AgentExecutor.maxStreamRetryDelay * 0.8)
    try #require(huge <= AgentExecutor.maxStreamRetryDelay * 1.2)
  }

  // MARK: - ensureUniqueToolNames

  @Test func testEnsureUniqueToolNamesAcceptsDistinctTools() throws {
    try AgentExecutor.ensureUniqueToolNames(ToolRegistry.readOnlyTools())
    try AgentExecutor.ensureUniqueToolNames(ToolRegistry.developTools())
    try AgentExecutor.ensureUniqueToolNames(ToolRegistry.inspectionTools())
  }

  // MARK: - Tool registry per phase

  @Test func testCriticPhaseGetsReadOnlyPlusBash() throws {
    let names = Set(ToolRegistry.tools(for: .critic).map { $0.spec.name })
    try #require(names.contains(AgentBashTool.toolName))
    try #require(names.contains(AgentReadFileTool.toolName))
    try #require(names.contains(AgentFindSymbolTool.toolName))
    try #require(names.contains(AgentDelegateTool.toolName))
    try #require(
      !names.contains(AgentWriteFileTool.toolName),
      "Critic must not have write_file")
    try #require(
      !names.contains(AgentEditFileTool.toolName),
      "Critic must not have edit_file")
  }

  @Test func testDelegateToolIsExposedToAllPhases() throws {
    for phase in AgentPhase.allCases {
      let names = Set(ToolRegistry.tools(for: phase).map { $0.spec.name })
      try #require(
        names.contains(AgentDelegateTool.toolName),
        "phase \(phase) must include `delegate`")
    }
  }

  @Test func testEnsureUniqueToolNamesRejectsDuplicates() throws {
    let tools: [AgentTool] = [AgentReadFileTool(), AgentReadFileTool()]
    do {
      try AgentExecutor.ensureUniqueToolNames(tools)
      #expect(Bool(false), "expected error")
    } catch let error as AgentExecutionError {
      guard case AgentExecutionError.duplicateToolName(let name) = error else {
        #expect(Bool(false), "expected duplicateToolName, got \(error)")
        return
      }
      try #require(name == AgentReadFileTool.toolName)
    } catch {
      #expect(Bool(false), "expected AgentExecutionError")
    }
  }

  @Test func testEnsureUniqueToolNamesRejectsCollisionWithSubmitResult() throws {
    struct FakeSubmit: AgentTool {
      let spec = AgentToolSpec(
        name: AgentExecutor.submitResultToolName,
        description: "shadow",
        parameters: AgentToolParametersSchema(literal: ["type": "object"])
      )
      func invoke(arguments: Data, context: AgentToolContext) async throws
        -> AgentToolInvocationResult
      { .ok("") }
    }
    do {
      try AgentExecutor.ensureUniqueToolNames([FakeSubmit()])
      #expect(Bool(false), "expected error")
    } catch let error as AgentExecutionError {
      guard case AgentExecutionError.duplicateToolName(let name) = error else {
        #expect(Bool(false), "expected duplicateToolName, got \(error)")
        return
      }
      try #require(name == AgentExecutor.submitResultToolName)
    } catch {
      #expect(Bool(false), "expected AgentExecutionError")
    }
  }

  // MARK: - buildOpenAITools

  @Test func testBuildOpenAIToolsIncludesEveryToolPlusSubmitResult() throws {
    let configuration = makeConfiguration(
      phase: .plan,
      tools: ToolRegistry.readOnlyTools()
    )
    let params = try AgentExecutor.buildOpenAITools(configuration: configuration)
    let names = params.map { $0.function.name }
    try #require(
      Set(names)
        == Set([
          AgentReadFileTool.toolName,
          AgentLsTool.toolName,
          AgentGrepTool.toolName,
          AgentGlobTool.toolName,
          AgentOutlineTool.toolName,
          AgentFindSymbolTool.toolName,
          AgentSummaryTool.toolName,
          AgentListFilesTool.toolName,
          AgentImportersOfTool.toolName,
          AgentDelegateTool.toolName,
          AgentRecordAssumptionTool.toolName,
          AgentRemoveAssumptionTool.toolName,
          AgentExecutor.submitResultToolName,
        ]))
  }

  @Test func testBuildOpenAIToolsCarriesSubmitSchemaThroughDecodeReencode() throws {
    let schema = try AgentToolParametersSchema([
      "type": "object",
      "additionalProperties": false,
      "required": ["status"],
      "properties": [
        "status": [
          "type": "string",
          "enum": ["succeeded", "blocked", "failed"],
        ]
      ],
    ])
    let configuration = makeConfiguration(
      phase: .develop,
      tools: ToolRegistry.developTools(),
      submitResultSchema: schema
    )
    let params = try AgentExecutor.buildOpenAITools(configuration: configuration)
    let submit = try #require(
      params.first { $0.function.name == AgentExecutor.submitResultToolName })
    let rendered = try JSONEncoder().encode(submit.function.parameters)
    let object = try JSONSerialization.jsonObject(with: rendered) as? [String: Any]
    try #require(object?["type"] as? String == "object")
    try #require(object?["additionalProperties"] as? Bool == false)
    let properties = object?["properties"] as? [String: Any]
    let status = properties?["status"] as? [String: Any]
    try #require(status?["type"] as? String == "string")
    try #require(status?["enum"] as? [String] == ["succeeded", "blocked", "failed"])
  }

  // MARK: - phase routing

  @Test func testToolsForPhasePicksInspectionSetForPlanAndReflect() throws {
    let planNames = Set(ToolRegistry.tools(for: .plan).map { $0.spec.name })
    let reflectNames = Set(ToolRegistry.tools(for: .reflect).map { $0.spec.name })
    let inspectionNames = Set(ToolRegistry.inspectionTools().map { $0.spec.name })
    try #require(planNames.isSuperset(of: inspectionNames))
    try #require(reflectNames == inspectionNames)
    try #require(planNames.contains(AgentPlanHistoryTool.toolName))
    try #require(!reflectNames.contains(AgentPlanHistoryTool.toolName))
    try #require(
      planNames.contains(AgentBashTool.toolName),
      "Plan must have bash so it can run builds/tests to ground its plan")
    try #require(
      reflectNames.contains(AgentBashTool.toolName),
      "Reflect must have bash so it can probe the project during course-correction")
    try #require(!planNames.contains(AgentWriteFileTool.toolName))
    try #require(!planNames.contains(AgentEditFileTool.toolName))
    try #require(!reflectNames.contains(AgentWriteFileTool.toolName))
    try #require(!reflectNames.contains(AgentEditFileTool.toolName))
  }

  @Test func testToolsForPhasePicksFullSetForDevelop() throws {
    let names = Set(ToolRegistry.tools(for: .develop).map { $0.spec.name })
    try #require(names.contains(AgentBashTool.toolName))
    try #require(names.contains(AgentWriteFileTool.toolName))
    try #require(names.contains(AgentEditFileTool.toolName))
    try #require(names.contains(AgentReadFileTool.toolName))
  }

  // MARK: - Invalid submit_result remediation

  @Test func testInvalidSubmitResultNudgeUsesTruncationCopyWhenFinishReasonIsLength() throws {
    let nudge = AgentExecutor.invalidSubmitResultNudge(
      finishReason: "length",
      argumentsPreview: "{\"state\":{...",
      maxCompletionTokens: 65_536
    )
    try #require(nudge.eventText == "submit_result truncated")
    try #require(nudge.eventDetail.contains("65536"))
    try #require(nudge.userMessage.contains("truncated by the output-token limit"))
    try #require(nudge.userMessage.contains("complete, valid JSON"))
  }

  @Test func testInvalidSubmitResultNudgeUsesRejectedCopyWhenFinishReasonIsNotLength() throws {
    // MiniMax in production was observed truncating submit_result
    // mid-token while reporting finish_reason "tool_calls" — the
    // old gated remediation skipped the pop-and-nudge path and the
    // next request 400'd on the bad tool_calls.arguments. The
    // generic branch must still produce a retry nudge.
    for reason: String? in [nil, "stop", "tool_calls", "content_filter"] {
      let nudge = AgentExecutor.invalidSubmitResultNudge(
        finishReason: reason,
        argumentsPreview: "{\"state\":{\"completed\":[\"…GitReposit",
        maxCompletionTokens: 65_536
      )
      try #require(
        nudge.eventText == "submit_result rejected",
        "finishReason=\(reason ?? "nil") should not be treated as the length variant")
      try #require(
        nudge.eventDetail.contains("GitReposit"),
        "rejected detail should include the args preview so the user can see what was bad")
      try #require(
        nudge.userMessage.contains("could not be parsed as JSON"),
        "rejected nudge should explain the parse failure")
      try #require(
        nudge.userMessage.contains("shorter"),
        "rejected nudge should still push the model toward shorter output, since silent truncation is the most common cause"
      )
    }
  }

  @Test func testInvalidLessonEditsNudgeExplainsMismatchAndRetry() throws {
    let nudge = AgentExecutor.invalidLessonEditsNudge(
      errorMessage: "Lesson edit `find` text was not found in lessons.md."
    )
    try #require(nudge.eventText == "submit_result lesson edits rejected")
    try #require(nudge.eventDetail.contains("was not found"))
    try #require(nudge.userMessage.contains("lessonEdits"))
    try #require(nudge.userMessage.contains("Call `submit_result` again"))
    try #require(nudge.userMessage.contains("Use `[]`"))
  }

  @Test func testInvalidDevelopFeedbackNudgeExplainsConcreteRetry() throws {
    let nudge = AgentExecutor.submitResultValidationNudge(
      for: DevelopFeedbackValidationError(
        message: "Develop feedback `done` is too generic to guide the next Plan pass.",
        reason: .placeholder,
        feedback: "done"
      )
    )

    try #require(nudge.eventText == "submit_result feedback rejected")
    try #require(nudge.eventDetail.contains("too generic"))
    try #require(nudge.userMessage.contains("next Plan pass"))
    try #require(nudge.userMessage.contains("Keep the same `status`"))
    try #require(nudge.userMessage.contains("smallest recovery action"))
    try #require(nudge.userMessage.contains("Use this exact retry shape"))
    try #require(nudge.userMessage.contains("\"status\": \"<same status>\""))
    try #require(
      nudge.userMessage.contains(
        "changed surface plus verification/follow-up, or blocker/failure plus smallest Plan recovery action"
      )
    )
    try #require(nudge.userMessage.contains("\"lessonEdits\": []"))
    try #require(nudge.userMessage.contains("Do not answer in prose"))
  }

  @Test func testInvalidDevelopVerifyBypassNudgeExplainsFallbackToVerify() throws {
    let nudge = AgentExecutor.submitResultValidationNudge(
      for: DevelopVerifyBypassValidationError(
        message:
          "Develop set bypassVerify=true without explaining why the verify command itself is wrong or out of scope.",
        reason: .missingReason
      )
    )

    try #require(nudge.eventText == "submit_result verify bypass rejected")
    try #require(nudge.eventDetail.contains("bypassVerify=true"))
    try #require(nudge.userMessage.contains("set `bypassVerify` to false"))
    try #require(nudge.userMessage.contains("verify command itself is wrong"))
    try #require(nudge.userMessage.contains("smallest Plan recovery action"))
    try #require(nudge.userMessage.contains("Use this exact retry shape when verify can run"))
    try #require(nudge.userMessage.contains("\"bypassVerify\": false"))
    try #require(nudge.userMessage.contains("exact verify-command problem plus"))
    try #require(nudge.userMessage.contains("\"lessonEdits\": []"))
    try #require(nudge.userMessage.contains("Do not answer in prose"))
  }

  @Test func testInvalidCriticFeedbackNudgeExplainsApproveEscapeHatch() throws {
    let nudge = AgentExecutor.submitResultValidationNudge(
      for: CriticFeedbackValidationError(
        message: "Critic feedback `fix it` is too generic to guide the next Develop pass.",
        reason: .placeholder,
        feedback: "fix it"
      )
    )

    try #require(nudge.eventText == "submit_result critic feedback rejected")
    try #require(nudge.eventDetail.contains("too generic"))
    try #require(nudge.userMessage.contains("request_changes"))
    try #require(nudge.userMessage.contains("smallest recovery action"))
    try #require(nudge.userMessage.contains("approve with"))
    try #require(
      nudge.userMessage.contains("Use this exact retry shape for real requested changes"))
    try #require(nudge.userMessage.contains("\"verdict\": \"request_changes\""))
    try #require(nudge.userMessage.contains("<specific failing behavior or file>"))
    try #require(nudge.userMessage.contains("use this approve shape"))
    try #require(nudge.userMessage.contains("\"verdict\": \"approve\""))
    try #require(nudge.userMessage.contains("\"feedback\": \"\""))
    try #require(nudge.userMessage.contains("Do not answer in prose"))
  }

  @Test func testInvalidSubmitResultDecodeNudgeExplainsContractMismatch() throws {
    let nudge = AgentExecutor.invalidSubmitResultDecodeNudge(
      errorMessage: "Missing required field `lessonEdits`."
    )
    try #require(nudge.eventText == "submit_result contract rejected")
    try #require(nudge.userMessage.contains("required shape"))
    try #require(nudge.userMessage.contains("lessonEdits: []"))
  }

  @Test func testSubmitResultValidationNudgeUsesDecodeCopyForDecodingErrors() throws {
    let payload = Data(
      """
      {"state":{"midTerm":"x","immediate":null},"summary":"done"}
      """.utf8)
    do {
      _ = try JSONDecoder().decode(ReflectSummary.self, from: payload)
      #expect(Bool(false), "expected decode to fail")
    } catch {
      let nudge = AgentExecutor.submitResultValidationNudge(for: error)
      try #require(nudge.eventText == "submit_result contract rejected")
    }
  }

  @Test func testSubmitResultValidationNudgeUsesLessonEditCopyForOtherErrors() throws {
    let nudge = AgentExecutor.submitResultValidationNudge(
      for: NSError(
        domain: "test", code: 1,
        userInfo: [
          NSLocalizedDescriptionKey: "Lesson edit `find` text was not found in lessons.md."
        ])
    )
    try #require(nudge.eventText == "submit_result lesson edits rejected")
  }

  @Test func testSubmitResultValidationNudgeUsesPlanCopyForRejectedPlan() throws {
    let nudge = AgentExecutor.submitResultValidationNudge(
      for: PlanTransitionValidationError(
        message: "Plan returned no immediate work.",
        reason: .noImmediateWork
      )
    )

    try #require(nudge.eventText == "submit_result plan rejected")
    try #require(nudge.userMessage.contains("Immediate Plan"))
    try #require(nudge.userMessage.contains("Acceptance checks"))
    try #require(nudge.userMessage.contains("Repair checklist:"))
    try #require(nudge.userMessage.contains("Replace `state.immediate: null`"))
    try #require(nudge.userMessage.contains("\"lessonEdits\": []"))
    try #require(nudge.userMessage.contains("\"state\""))
    try #require(nudge.userMessage.contains("\"immediate\""))
    try #require(nudge.userMessage.contains("\"verifyTimeoutMs\": 600000"))
    try #require(nudge.userMessage.contains("## Outcome\\n"))
    try #require(nudge.userMessage.contains("keep shell commands only in `state.immediate.verify`"))
    try #require(
      nudge.userMessage.contains(
        "<another observable result; state.immediate.verify proves it>"
      )
    )
    try #require(!nudge.userMessage.contains("<the verify command proves the change>"))
    try #require(nudge.userMessage.contains("do not answer in prose"))
  }

  @Test func testSubmitResultValidationNudgeTargetsPlaceholderVerify() throws {
    let nudge = AgentExecutor.submitResultValidationNudge(
      for: PlanTransitionValidationError(
        message: "Plan returned placeholder verify command `true`.",
        reason: .placeholderVerify,
        missingLabels: ["Verify command"],
        rejectedVerify: "true"
      )
    )

    try #require(nudge.userMessage.contains("Replace the placeholder verify command"))
    try #require(nudge.userMessage.contains("Rejected verify: `true`"))
    try #require(
      nudge.userMessage.contains(
        "Do not use no-op commands such as `true`, `exit 0`, `echo no tests`, "
          + "`none`, `n/a`, or `not-running-tests`"))
    try #require(
      nudge.userMessage.contains("Keep the plan text if its Outcome and Acceptance checks"))
  }

  @Test func testSubmitResultValidationNudgeTargetsWeakHandoffFields() throws {
    let nudge = AgentExecutor.submitResultValidationNudge(
      for: PlanTransitionValidationError(
        message: "Plan returned an immediate handoff that is not executable enough.",
        reason: .weakHandoff,
        missingLabels: ["Outcome", "Acceptance checks"]
      )
    )

    try #require(nudge.userMessage.contains("Add Outcome and Acceptance checks"))
    try #require(nudge.userMessage.contains("Keep the slice commit-sized"))
    try #require(nudge.userMessage.contains("Make every acceptance check observable"))
  }

  @Test func testSubmitResultValidationNudgeTargetsCommandOnlyAcceptanceChecks() throws {
    let nudge = AgentExecutor.submitResultValidationNudge(
      for: PlanTransitionValidationError(
        message: "Plan returned command-only acceptance checks.",
        reason: .weakHandoff,
        missingLabels: ["Acceptance checks"],
        rejectedAcceptanceChecks: ["Verify: swift test --filter RecoveryTests"]
      )
    )

    try #require(nudge.userMessage.contains("Replace command-only acceptance checks"))
    try #require(nudge.userMessage.contains("`Verify: swift test --filter RecoveryTests`"))
    try #require(nudge.userMessage.contains("Keep shell commands in `state.immediate.verify`"))
    try #require(nudge.userMessage.contains("observable finish-line behavior"))
  }

  @Test func testSubmitResultValidationNudgeTargetsCoverageRequirement() throws {
    let nudge = AgentExecutor.submitResultValidationNudge(
      for: PlanTransitionValidationError(
        message: "Swift test verify must declare coverage.",
        reason: .coverageRequirement,
        missingLabels: ["Coverage-ready verify command"],
        rejectedVerify: "swift test"
      )
    )

    try #require(nudge.userMessage.contains("satisfy the forge profile coverage requirement"))
    try #require(nudge.userMessage.contains("Keep the same Immediate Plan"))
    try #require(nudge.userMessage.contains("Do not bypass coverage"))
  }

  @Test func testDecodingErrorMessageSurfacesMissingKey() throws {
    let payload = Data(
      """
      {"state":{"midTerm":"x","immediate":null},"summary":"done"}
      """.utf8)
    do {
      _ = try JSONDecoder().decode(ReflectSummary.self, from: payload)
      #expect(Bool(false), "expected decode to fail")
    } catch {
      let message = AgentExecutor.decodingErrorMessage(error)
      try #require(message.contains("longTerm"), "message was: \(message)")
    }
  }

  // MARK: - Invalid generic-tool-args remediation

  @Test func testInvalidToolArgumentsNudgeUsesTruncationCopyWhenFinishReasonIsLength() throws {
    // The `edit_file` MiniMax 400 cascade in the bug screenshot was a
    // turn whose `tool_calls.arguments` was invalid JSON; the local
    // tool returned "Invalid arguments…", the assistant turn stayed in
    // `messages`, and the *next* request 400'd. The truncation-coded
    // branch should call that out and steer toward smaller payloads.
    let nudge = AgentExecutor.invalidToolArgumentsNudge(
      toolName: "edit_file",
      finishReason: "length",
      argumentsPreview: "{\"path\":\"foo.swift\",\"edits\":[{\"oldStri",
      maxCompletionTokens: 80_000
    )
    try #require(nudge.eventText == "edit_file truncated")
    try #require(nudge.eventDetail.contains("80000"))
    try #require(nudge.userMessage.contains("`edit_file`"))
    try #require(nudge.userMessage.contains("truncated by the output-token limit"))
    try #require(
      nudge.userMessage.contains("smaller"),
      "truncation nudge should push the model toward smaller payloads")
    try #require(nudge.userMessage.contains("complete, valid JSON"))
  }

  @Test func testInvalidToolArgumentsNudgeUsesRejectedCopyWhenFinishReasonIsNotLength() throws {
    // Generic-tool args go bad without `finishReason == "length"` for
    // two reasons: silent mid-token truncation (MiniMax) and model-side
    // escaping bugs in large payloads. The fallback wording must cover
    // both — call out JSON escaping *and* offer the split-up-the-call
    // out — without mentioning submit_result-specific concepts.
    for reason: String? in [nil, "stop", "tool_calls", "content_filter"] {
      let nudge = AgentExecutor.invalidToolArgumentsNudge(
        toolName: "edit_file",
        finishReason: reason,
        argumentsPreview: "{\"path\":\"foo.swift\",\"edits\":[{\"oldString\":\"let x = 1\nlet y",
        maxCompletionTokens: 80_000
      )
      try #require(
        nudge.eventText == "edit_file rejected",
        "finishReason=\(reason ?? "nil") should not be treated as the length variant")
      try #require(
        nudge.eventDetail.contains("oldString"),
        "rejected detail should include the args preview so the user can see what was bad")
      try #require(
        nudge.userMessage.contains("`edit_file`"),
        "rejected nudge should name the specific tool that failed")
      try #require(
        nudge.userMessage.contains("could not be parsed as JSON"),
        "rejected nudge should explain the parse failure")
      try #require(
        nudge.userMessage.contains("escaping"),
        "rejected nudge should mention escaping — model-side escape bugs are a common cause")
      try #require(
        !nudge.userMessage.contains("submit_result"),
        "generic-tool nudge must not leak submit_result-specific wording")
    }
  }

  // MARK: - Rollback helpers

  /// Convenience constructors so the rollback assertions stay readable.
  private func sys(_ text: String) -> ChatQuery.ChatCompletionMessageParam {
    .system(.init(content: .textContent(text)))
  }
  private func usr(_ text: String) -> ChatQuery.ChatCompletionMessageParam {
    .user(.init(content: .string(text)))
  }
  private func asst(text: String? = nil, toolCallIDs: [String] = [])
    -> ChatQuery.ChatCompletionMessageParam
  {
    let calls = toolCallIDs.map {
      ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam(
        id: $0, function: .init(arguments: "{}", name: "stub"))
    }
    return .assistant(
      .init(
        content: text.map { .textContent($0) },
        toolCalls: calls.isEmpty ? nil : calls
      ))
  }
  private func tool(_ payload: String, toolCallId: String)
    -> ChatQuery.ChatCompletionMessageParam
  {
    .tool(.init(content: .textContent(payload), toolCallId: toolCallId))
  }

  @Test func testRollbackDropsOnlyAssistantWhenSubmitResultWasTheOnlyToolCall() throws {
    // Iteration 6 in the bug screenshot: model called submit_result alone
    // and the args were truncated. Rolling back must drop only the
    // assistant turn — prior tool responses from iter 5 must survive.
    var messages: [ChatQuery.ChatCompletionMessageParam] = [
      sys("SYS"),
      usr("TASK"),
      tool("iter5 result", toolCallId: "t5"),
      asst(text: "thinking...", toolCallIDs: ["submit-bad"]),
    ]
    var indices: Set<Int> = []
    AgentExecutor.rollback(messages: &messages, nudgeIndices: &indices, to: 3)
    try #require(messages.count == 3)
    if case .tool = messages.last {
    } else {
      #expect(
        Bool(false), "rollback should land on the prior tool response, got \(messages.last as Any)")
    }
  }

  @Test func testRollbackDropsOrphanedToolResponsesAlongsideAssistant() throws {
    // The harder case: the model issued [read_file, submit_result] in the
    // same turn, we already appended read_file's tool response before
    // hitting the malformed submit_result. Leaving that tool response
    // behind would orphan its toolCallId against an assistant turn that
    // no longer exists — that's the MiniMax-400 cascade. Rollback must
    // drop both the assistant *and* the tool response from this turn.
    var messages: [ChatQuery.ChatCompletionMessageParam] = [
      sys("SYS"),
      usr("TASK"),
      asst(toolCallIDs: ["t-read", "t-submit"]),
      tool("contents of foo.swift", toolCallId: "t-read"),
    ]
    var indices: Set<Int> = []
    AgentExecutor.rollback(messages: &messages, nudgeIndices: &indices, to: 2)
    try #require(messages.count == 2)
    if case .user = messages.last {
    } else {
      #expect(Bool(false), "rollback should leave the original user task as the tail")
    }
  }

  @Test func testRollbackDropsStaleNudgeIndices() throws {
    var messages: [ChatQuery.ChatCompletionMessageParam] = [
      sys("SYS"), usr("TASK"), usr("nudge-old"), asst(toolCallIDs: ["t1"]),
    ]
    var indices: Set<Int> = [2]
    AgentExecutor.rollback(messages: &messages, nudgeIndices: &indices, to: 3)
    try #require(messages.count == 3)
    try #require(
      indices.contains(2),
      "rollback to index 3 must keep nudge-tracking entries whose index < 3")
  }

  @Test func testRollbackToEqualOrGreaterCountIsNoop() throws {
    var messages: [ChatQuery.ChatCompletionMessageParam] = [sys("SYS"), usr("TASK")]
    var indices: Set<Int> = [1]
    AgentExecutor.rollback(messages: &messages, nudgeIndices: &indices, to: 2)
    try #require(messages.count == 2)
    AgentExecutor.rollback(messages: &messages, nudgeIndices: &indices, to: 99)
    try #require(messages.count == 2)
    try #require(indices == [1])
  }

  @Test func testAppendRemediationNudgeReplacesConsecutiveNudge() throws {
    // Back-to-back failed iterations would otherwise leave two `.user`
    // messages in a row, which strict providers (MiniMax) reject with a
    // 400. Confirm the helper collapses the second append into a
    // replacement.
    var messages: [ChatQuery.ChatCompletionMessageParam] = [sys("SYS"), usr("TASK")]
    var indices: Set<Int> = []

    AgentExecutor.appendRemediationNudge("first", messages: &messages, nudgeIndices: &indices)
    try #require(messages.count == 3)
    try #require(indices == [2])

    AgentExecutor.appendRemediationNudge("second", messages: &messages, nudgeIndices: &indices)
    try #require(messages.count == 3, "second nudge must replace the first, not stack")
    try #require(indices == [2])
    guard case .user(let body) = messages[2], case .string(let text) = body.content else {
      #expect(Bool(false), "replacement message should be a .user(.string)")
      return
    }
    try #require(text == "second")
  }

  @Test func testAppendRemediationNudgeAppendsWhenTailIsNotANudge() throws {
    var messages: [ChatQuery.ChatCompletionMessageParam] = [
      sys("SYS"), usr("TASK"), tool("iter5 result", toolCallId: "t5"),
    ]
    var indices: Set<Int> = []
    AgentExecutor.appendRemediationNudge("nudge", messages: &messages, nudgeIndices: &indices)
    try #require(messages.count == 4)
    try #require(indices == [3])
  }

  @Test func testAppendRemediationNudgeDoesNotCollapseOriginalUserTask() throws {
    // On the very first iteration the tail of the conversation is the
    // user task itself. A nudge appended after a first-iter failure must
    // *append* — collapsing here would silently delete the task prompt.
    var messages: [ChatQuery.ChatCompletionMessageParam] = [sys("SYS"), usr("TASK")]
    var indices: Set<Int> = []
    AgentExecutor.appendRemediationNudge("nudge", messages: &messages, nudgeIndices: &indices)
    try #require(messages.count == 3)
    guard case .user(let task) = messages[1], case .string(let taskText) = task.content else {
      #expect(Bool(false), "original task at index 1 should still be present")
      return
    }
    try #require(taskText == "TASK")
  }

  // MARK: - Auto-compaction

  @Test func testShouldCompactReturnsFalseWhenContextWindowIsZero() throws {
    try #require(
      !AgentExecutor.shouldCompact(estimatedTokens: 1_000_000, contextWindowTokens: 0))
    try #require(
      !AgentExecutor.shouldCompact(estimatedTokens: 1_000_000, contextWindowTokens: -1))
  }

  @Test func testShouldCompactReturnsTrueAtOrAboveThreshold() throws {
    let window = 200_000
    let threshold = Int(Double(window) * AgentExecutor.compactionThresholdFraction)
    try #require(
      !AgentExecutor.shouldCompact(estimatedTokens: threshold - 1, contextWindowTokens: window))
    try #require(
      AgentExecutor.shouldCompact(estimatedTokens: threshold, contextWindowTokens: window))
    try #require(
      AgentExecutor.shouldCompact(estimatedTokens: window, contextWindowTokens: window))
  }

  @Test func testShouldCompactTracksArbitraryWindowSizes() throws {
    try #require(!AgentExecutor.shouldCompact(estimatedTokens: 80, contextWindowTokens: 128))
    // 128 * 0.75 = 96
    try #require(AgentExecutor.shouldCompact(estimatedTokens: 96, contextWindowTokens: 128))
  }

  @Test func testEstimatedTokensGrowsWithEncodedMessagePayload() throws {
    let short = AgentExecutor.estimatedTokens(in: [sys("SYS"), usr("hi")])
    let long = AgentExecutor.estimatedTokens(
      in: [sys("SYS"), usr(String(repeating: "x", count: 4_000))])
    try #require(long > short)
    // ~4_000 chars of payload plus JSON envelope should sit comfortably
    // above 1_000 / 4 tokens — anything dramatically smaller would mean
    // the estimator silently lost the payload (e.g. a swallowed encoder
    // failure that left the message contributing zero).
    try #require(long > 1_000)
  }

  @Test func testEstimatedTokensCountsAssistantToolCallsAndToolResponses() throws {
    // The whole point of the chars/4 estimator over provider-reported
    // usage is that a long tool-call-heavy run can't slip under the
    // threshold just because the provider dropped usage on those
    // chunks. Make sure assistant tool_calls and tool responses both
    // contribute to the estimate.
    let textOnly = AgentExecutor.estimatedTokens(in: [sys("SYS"), usr("TASK")])
    let withToolTraffic = AgentExecutor.estimatedTokens(
      in: [
        sys("SYS"),
        usr("TASK"),
        asst(toolCallIDs: ["t1", "t2", "t3"]),
        tool(String(repeating: "log line\n", count: 200), toolCallId: "t1"),
        tool(String(repeating: "log line\n", count: 200), toolCallId: "t2"),
        tool(String(repeating: "log line\n", count: 200), toolCallId: "t3"),
      ])
    try #require(withToolTraffic > textOnly + 1_000)
  }

  @Test func testCompactedMessagesPreservesSystemAndOriginalUser() throws {
    let system: ChatQuery.ChatCompletionMessageParam = .system(
      .init(content: .textContent("SYS"))
    )
    let originalUser: ChatQuery.ChatCompletionMessageParam = .user(
      .init(content: .string("ORIGINAL TASK PROMPT"))
    )
    let result = AgentExecutor.compactedMessages(
      system: system,
      originalUser: originalUser,
      summary: "Summary body here."
    )
    try #require(result.count == 3)
    try #require(result[0] == system)
    try #require(result[1] == originalUser)
    guard case .user(let recap) = result[2],
      case .string(let recapText) = recap.content
    else {
      #expect(Bool(false), "expected third message to be a .user(.string) recap")
      return
    }
    try #require(recapText.contains("Summary body here."))
    try #require(
      recapText.contains("Compacted conversation summary"),
      "recap should label itself as a compaction so the model knows context was dropped")
    try #require(
      recapText.contains("submit_result"),
      "recap should remind the model how to finish the phase")
  }

  // MARK: - Typed tool errors

  @Test func testAgentToolErrorKindMapsThroughFailureOverload() throws {
    try #require(
      AgentToolInvocationResult.failure(.fileNotFound("missing.txt")).errorKind == .fileNotFound
    )
    try #require(
      AgentToolInvocationResult.failure(.editConflict("oldString not found")).errorKind
        == .editConflict
    )
    try #require(
      AgentToolInvocationResult.failure(.rpcFailure("vsock disconnected")).errorKind == .rpcFailure
    )
    try #require(
      AgentToolInvocationResult.failure(.invalidArguments("bad json")).errorKind
        == .invalidArguments
    )
  }

  @Test func testAgentToolErrorKindIsNilForSuccess() throws {
    try #require(AgentToolInvocationResult.ok("done").errorKind == nil)
  }

  @Test func testLegacyStringFailureKeepsNilKindForBackwardsCompat() throws {
    try #require(AgentToolInvocationResult.failure("plain string").errorKind == nil)
  }

  // MARK: - helpers

  private func makeConfiguration(
    phase: AgentPhase,
    tools: [AgentTool],
    submitResultSchema: AgentToolParametersSchema? = nil
  ) -> AgentExecutionConfiguration {
    let schema =
      submitResultSchema
      ?? (AgentToolParametersSchema(literal: [
        "type": "object",
        "additionalProperties": false,
        "properties": [:],
      ]))
    return AgentExecutionConfiguration(
      settings: AgentRuntimeSettings(),
      phase: phase,
      systemPrompt: "test",
      userPrompt: "test",
      tools: tools,
      submitResultSchema: schema,
      workingDirectory: FileManager.default.temporaryDirectory
    )
  }
}
