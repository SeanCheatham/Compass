import Foundation
import OpenAI
import Testing

@testable import Compass

struct AgentExecutorTests {
  // MARK: - stripThinkBlocks

  @Test func testStripThinkBlocksOnPlainTextIsNoop() {
    let (text, reasoning) = AgentExecutor.stripThinkBlocks("hello world")
    #require(text == "hello world")
    #require(reasoning == "")
  }

  @Test func testStripThinkBlocksExtractsSingleBlock() {
    let (text, reasoning) = AgentExecutor.stripThinkBlocks("before <think>secret after")
    #require(text == "before  after")
    #require(reasoning == "secret")
  }

  @Test func testStripThinkBlocksExtractsMultipleBlocks() {
    let (text, reasoning) = AgentExecutor.stripThinkBlocks(
      "a<think>oneb<think>twoc")
    #require(text == "abc")
    #require(reasoning == "onetwo")
  }

  @Test func testStripThinkBlocksHandlesUnterminatedBlock() {
    let (text, reasoning) = AgentExecutor.stripThinkBlocks("visible <think>oops never closed")
    #require(text == "visible ")
    #require(reasoning == "oops never closed")
  }

  // MARK: - Budget exhaustion classification

  @Test func testIsAgentBudgetExhaustionCoversWallClockAndIterationLimits() {
    #require(AgentExecutionError.wallClockExceeded(3600).isAgentBudgetExhaustion)
    #require(AgentExecutionError.maxIterationsExceeded(512).isAgentBudgetExhaustion)
  }

  @Test func testIsAgentBudgetExhaustionRejectsNonBudgetCauses() {
    #require(!AgentExecutionError.cancelled.isAgentBudgetExhaustion)
    #require(!AgentExecutionError.streamFailed("boom").isAgentBudgetExhaustion)
    #require(!AgentExecutionError.modelStoppedWithoutSubmitResult.isAgentBudgetExhaustion)
    #require(
      !AgentExecutionError.toolCallDecodeFailed(name: "x", detail: "y").isAgentBudgetExhaustion
    )
    #require(!AgentExecutionError.duplicateToolName("z").isAgentBudgetExhaustion)
  }

  @Test func testDefaultWallClockTimeoutIsOneHour() {
    let configuration = makeConfiguration(phase: .plan, tools: ToolRegistry.readOnlyTools())
    #require(configuration.wallClockTimeout == 60 * 60)
  }

  // MARK: - Transient stream-error classification

  @Test func testTransientHTTPStatusesCoverOverloadAndCloudflareCodes() {
    let transient = [408, 425, 429, 500, 502, 503, 504, 520, 521, 522, 523, 524, 525, 526, 529]
    for code in transient {
      #require(
        AgentExecutor.isTransientHTTPStatus(code),
        "Expected \(code) to be classified transient"
      )
    }
  }

  @Test func testTransientHTTPStatusesRejectClientAndSuccessCodes() {
    let permanent = [200, 201, 204, 301, 400, 401, 403, 404, 422, 451]
    for code in permanent {
      #require(
        !AgentExecutor.isTransientHTTPStatus(code),
        "Expected \(code) to be classified permanent"
      )
    }
  }

  @Test func testShouldRetryAcceptsOpenAIStatusErrorsForTransientStatuses() {
    let response = HTTPURLResponse(
      url: URL(string: "https://api.example.com")!,
      statusCode: 529,
      httpVersion: nil,
      headerFields: nil
    )!
    let error = OpenAIError.statusError(response: response, statusCode: 529)
    #require(AgentExecutor.shouldRetry(error))
  }

  @Test func testShouldRetryRejectsOpenAIStatusErrorsForPermanentStatuses() {
    let response = HTTPURLResponse(
      url: URL(string: "https://api.example.com")!,
      statusCode: 400,
      httpVersion: nil,
      headerFields: nil
    )!
    let error = OpenAIError.statusError(response: response, statusCode: 400)
    #require(!AgentExecutor.shouldRetry(error))
  }

  @Test func testShouldRetryAcceptsTransientURLErrors() {
    #require(AgentExecutor.shouldRetry(URLError(.timedOut)))
    #require(AgentExecutor.shouldRetry(URLError(.networkConnectionLost)))
    #require(AgentExecutor.shouldRetry(URLError(.notConnectedToInternet)))
  }

  @Test func testShouldRetryRejectsPermanentURLErrors() {
    #require(!AgentExecutor.shouldRetry(URLError(.badURL)))
    #require(!AgentExecutor.shouldRetry(URLError(.unsupportedURL)))
    #require(!AgentExecutor.shouldRetry(URLError(.cancelled)))
  }

  @Test func testShouldRetryRejectsUnrelatedErrors() {
    struct OtherError: Error {}
    #require(!AgentExecutor.shouldRetry(OtherError()))
    #require(!AgentExecutor.shouldRetry(AgentExecutionError.cancelled))
  }

  @Test func testRetryDelayGrowsExponentiallyWithJitterAndCaps() {
    // Attempt 1 should sit around 1s (0.8 - 1.2 with jitter).
    let first = AgentExecutor.retryDelay(forAttempt: 1)
    #require(first >= AgentExecutor.baseStreamRetryDelay * 0.8)
    #require(first <= AgentExecutor.baseStreamRetryDelay * 1.2)

    // Attempt 4 = base * 2^3 = 8s before jitter, well under the cap.
    let fourth = AgentExecutor.retryDelay(forAttempt: 4)
    #require(fourth >= 8.0 * 0.8)
    #require(fourth <= 8.0 * 1.2)

    // Attempt 100 would explode to 2^99 seconds; the cap must hold.
    let huge = AgentExecutor.retryDelay(forAttempt: 100)
    #require(huge >= AgentExecutor.maxStreamRetryDelay * 0.8)
    #require(huge <= AgentExecutor.maxStreamRetryDelay * 1.2)
  }

  // MARK: - ensureUniqueToolNames

  @Test func testEnsureUniqueToolNamesAcceptsDistinctTools() throws {
    try AgentExecutor.ensureUniqueToolNames(ToolRegistry.readOnlyTools())
    try AgentExecutor.ensureUniqueToolNames(ToolRegistry.developTools())
    try AgentExecutor.ensureUniqueToolNames(ToolRegistry.inspectionTools())
  }

  // MARK: - Tool registry per phase

  @Test func testCriticPhaseGetsReadOnlyPlusBash() {
    let names = Set(ToolRegistry.tools(for: .critic).map { $0.spec.name })
    #require(names.contains(AgentBashTool.toolName))
    #require(names.contains(AgentReadFileTool.toolName))
    #require(names.contains(AgentFindSymbolTool.toolName))
    #require(names.contains(AgentDelegateTool.toolName))
    #require(
      !names.contains(AgentWriteFileTool.toolName),
      "Critic must not have write_file")
    #require(
      !names.contains(AgentEditFileTool.toolName),
      "Critic must not have edit_file")
  }

  @Test func testDelegateToolIsExposedToAllPhases() {
    for phase in AgentPhase.allCases {
      let names = Set(ToolRegistry.tools(for: phase).map { $0.spec.name })
      #require(
        names.contains(AgentDelegateTool.toolName),
        "phase \(phase) must include `delegate`")
    }
  }

  @Test func testEnsureUniqueToolNamesRejectsDuplicates() {
    let tools: [AgentTool] = [AgentReadFileTool(), AgentReadFileTool()]
    do {
      try AgentExecutor.ensureUniqueToolNames(tools)
      #require(false, "expected error")
    } catch let error as AgentExecutionError {
      guard case AgentExecutionError.duplicateToolName(let name) = error else {
        #require(false, "expected duplicateToolName, got \(error)")
        return
      }
      #require(name == AgentReadFileTool.toolName)
    } catch {
      #require(false, "expected AgentExecutionError")
    }
  }

  @Test func testEnsureUniqueToolNamesRejectsCollisionWithSubmitResult() {
    struct FakeSubmit: AgentTool {
      let spec = AgentToolSpec(
        name: AgentExecutor.submitResultToolName,
        description: "shadow",
        parameters: AgentToolParametersSchema(literal:["type": "object"])
      )
      func invoke(arguments: Data, context: AgentToolContext) async throws
        -> AgentToolInvocationResult
      { .ok("") }
    }
    do {
      try AgentExecutor.ensureUniqueToolNames([FakeSubmit()])
      #require(false, "expected error")
    } catch let error as AgentExecutionError {
      guard case AgentExecutionError.duplicateToolName(let name) = error else {
        #require(false, "expected duplicateToolName, got \(error)")
        return
      }
      #require(name == AgentExecutor.submitResultToolName)
    } catch {
      #require(false, "expected AgentExecutionError")
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
    #require(
      Set(names) ==
      Set([
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
    let submit = #require(
      params.first { $0.function.name == AgentExecutor.submitResultToolName })
    let rendered = try JSONEncoder().encode(submit.function.parameters)
    let object = try JSONSerialization.jsonObject(with: rendered) as? [String: Any]
    #require(object?["type"] as? String == "object")
    #require(object?["additionalProperties"] as? Bool == false)
    let properties = object?["properties"] as? [String: Any]
    let status = properties?["status"] as? [String: Any]
    #require(status?["type"] as? String == "string")
    #require(status?["enum"] as? [String] == ["succeeded", "blocked", "failed"])
  }

  // MARK: - phase routing

  @Test func testToolsForPhasePicksInspectionSetForPlanAndReflect() {
    let planNames = Set(ToolRegistry.tools(for: .plan).map { $0.spec.name })
    let reflectNames = Set(ToolRegistry.tools(for: .reflect).map { $0.spec.name })
    let inspectionNames = Set(ToolRegistry.inspectionTools().map { $0.spec.name })
    #require(planNames.isSuperset(of: inspectionNames))
    #require(reflectNames == inspectionNames)
    #require(planNames.contains(AgentPlanHistoryTool.toolName))
    #require(!reflectNames.contains(AgentPlanHistoryTool.toolName))
    #require(
      planNames.contains(AgentBashTool.toolName),
      "Plan must have bash so it can run builds/tests to ground its plan")
    #require(
      reflectNames.contains(AgentBashTool.toolName),
      "Reflect must have bash so it can probe the project during course-correction")
    #require(!planNames.contains(AgentWriteFileTool.toolName))
    #require(!planNames.contains(AgentEditFileTool.toolName))
    #require(!reflectNames.contains(AgentWriteFileTool.toolName))
    #require(!reflectNames.contains(AgentEditFileTool.toolName))
  }

  @Test func testToolsForPhasePicksFullSetForDevelop() {
    let names = Set(ToolRegistry.tools(for: .develop).map { $0.spec.name })
    #require(names.contains(AgentBashTool.toolName))
    #require(names.contains(AgentWriteFileTool.toolName))
    #require(names.contains(AgentEditFileTool.toolName))
    #require(names.contains(AgentReadFileTool.toolName))
  }

  // MARK: - Invalid submit_result remediation

  @Test func testInvalidSubmitResultNudgeUsesTruncationCopyWhenFinishReasonIsLength() {
    let nudge = AgentExecutor.invalidSubmitResultNudge(
      finishReason: "length",
      argumentsPreview: "{\"state\":{...",
      maxCompletionTokens: 65_536
    )
    #require(nudge.eventText == "submit_result truncated")
    #require(nudge.eventDetail.contains("65536"))
    #require(nudge.userMessage.contains("truncated by the output-token limit"))
    #require(nudge.userMessage.contains("complete, valid JSON"))
  }

  @Test func testInvalidSubmitResultNudgeUsesRejectedCopyWhenFinishReasonIsNotLength() {
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
      #require(
        nudge.eventText == "submit_result rejected",
        "finishReason=\(reason ?? "nil") should not be treated as the length variant")
      #require(
        nudge.eventDetail.contains("GitReposit"),
        "rejected detail should include the args preview so the user can see what was bad")
      #require(
        nudge.userMessage.contains("could not be parsed as JSON"),
        "rejected nudge should explain the parse failure")
      #require(
        nudge.userMessage.contains("shorter"),
        "rejected nudge should still push the model toward shorter output, since silent truncation is the most common cause"
      )
    }
  }

  @Test func testInvalidLessonEditsNudgeExplainsMismatchAndRetry() {
    let nudge = AgentExecutor.invalidLessonEditsNudge(
      errorMessage: "Lesson edit `find` text was not found in lessons.md."
    )
    #require(nudge.eventText == "submit_result lesson edits rejected")
    #require(nudge.eventDetail.contains("was not found"))
    #require(nudge.userMessage.contains("lessonEdits"))
    #require(nudge.userMessage.contains("Call `submit_result` again"))
    #require(nudge.userMessage.contains("Use `[]`"))
  }

  @Test func testInvalidSubmitResultDecodeNudgeExplainsContractMismatch() {
    let nudge = AgentExecutor.invalidSubmitResultDecodeNudge(
      errorMessage: "Missing required field `lessonEdits`."
    )
    #require(nudge.eventText == "submit_result contract rejected")
    #require(nudge.userMessage.contains("required shape"))
    #require(nudge.userMessage.contains("lessonEdits: []"))
  }

  @Test func testSubmitResultValidationNudgeUsesDecodeCopyForDecodingErrors() {
    let payload = Data("""
      {"state":{"midTerm":"x","immediate":null},"summary":"done"}
      """.utf8)
    do {
      _ = try JSONDecoder().decode(ReflectSummary.self, from: payload)
      #require(false, "expected decode to fail")
    } catch {
      let nudge = AgentExecutor.submitResultValidationNudge(for: error)
      #require(nudge.eventText == "submit_result contract rejected")
    }
  }

  @Test func testSubmitResultValidationNudgeUsesLessonEditCopyForOtherErrors() {
    let nudge = AgentExecutor.submitResultValidationNudge(
      for: NSError(domain: "test", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "Lesson edit `find` text was not found in lessons.md.",
      ])
    )
    #require(nudge.eventText == "submit_result lesson edits rejected")
  }

  @Test func testDecodingErrorMessageSurfacesMissingKey() {
    let payload = Data("""
      {"state":{"midTerm":"x","immediate":null},"summary":"done"}
      """.utf8)
    do {
      _ = try JSONDecoder().decode(ReflectSummary.self, from: payload)
      #require(false, "expected decode to fail")
    } catch {
      let message = AgentExecutor.decodingErrorMessage(error)
      #require(message.contains("longTerm"), "message was: \(message)")
    }
  }

  // MARK: - Invalid generic-tool-args remediation

  @Test func testInvalidToolArgumentsNudgeUsesTruncationCopyWhenFinishReasonIsLength() {
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
    #require(nudge.eventText == "edit_file truncated")
    #require(nudge.eventDetail.contains("80000"))
    #require(nudge.userMessage.contains("`edit_file`"))
    #require(nudge.userMessage.contains("truncated by the output-token limit"))
    #require(
      nudge.userMessage.contains("smaller"),
      "truncation nudge should push the model toward smaller payloads")
    #require(nudge.userMessage.contains("complete, valid JSON"))
  }

  @Test func testInvalidToolArgumentsNudgeUsesRejectedCopyWhenFinishReasonIsNotLength() {
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
      #require(
        nudge.eventText == "edit_file rejected",
        "finishReason=\(reason ?? "nil") should not be treated as the length variant")
      #require(
        nudge.eventDetail.contains("oldString"),
        "rejected detail should include the args preview so the user can see what was bad")
      #require(
        nudge.userMessage.contains("`edit_file`"),
        "rejected nudge should name the specific tool that failed")
      #require(
        nudge.userMessage.contains("could not be parsed as JSON"),
        "rejected nudge should explain the parse failure")
      #require(
        nudge.userMessage.contains("escaping"),
        "rejected nudge should mention escaping — model-side escape bugs are a common cause")
      #require(
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

  @Test func testRollbackDropsOnlyAssistantWhenSubmitResultWasTheOnlyToolCall() {
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
    #require(messages.count == 3)
    if case .tool = messages.last {
    } else {
      #require(false, "rollback should land on the prior tool response, got \(messages.last as Any)")
    }
  }

  @Test func testRollbackDropsOrphanedToolResponsesAlongsideAssistant() {
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
    #require(messages.count == 2)
    if case .user = messages.last {
    } else {
      #require(false, "rollback should leave the original user task as the tail")
    }
  }

  @Test func testRollbackDropsStaleNudgeIndices() {
    var messages: [ChatQuery.ChatCompletionMessageParam] = [
      sys("SYS"), usr("TASK"), usr("nudge-old"), asst(toolCallIDs: ["t1"]),
    ]
    var indices: Set<Int> = [2]
    AgentExecutor.rollback(messages: &messages, nudgeIndices: &indices, to: 3)
    #require(messages.count == 3)
    #require(
      indices.contains(2),
      "rollback to index 3 must keep nudge-tracking entries whose index < 3")
  }

  @Test func testRollbackToEqualOrGreaterCountIsNoop() {
    var messages: [ChatQuery.ChatCompletionMessageParam] = [sys("SYS"), usr("TASK")]
    var indices: Set<Int> = [1]
    AgentExecutor.rollback(messages: &messages, nudgeIndices: &indices, to: 2)
    #require(messages.count == 2)
    AgentExecutor.rollback(messages: &messages, nudgeIndices: &indices, to: 99)
    #require(messages.count == 2)
    #require(indices == [1])
  }

  @Test func testAppendRemediationNudgeReplacesConsecutiveNudge() {
    // Back-to-back failed iterations would otherwise leave two `.user`
    // messages in a row, which strict providers (MiniMax) reject with a
    // 400. Confirm the helper collapses the second append into a
    // replacement.
    var messages: [ChatQuery.ChatCompletionMessageParam] = [sys("SYS"), usr("TASK")]
    var indices: Set<Int> = []

    AgentExecutor.appendRemediationNudge("first", messages: &messages, nudgeIndices: &indices)
    #require(messages.count == 3)
    #require(indices == [2])

    AgentExecutor.appendRemediationNudge("second", messages: &messages, nudgeIndices: &indices)
    #require(messages.count == 3, "second nudge must replace the first, not stack")
    #require(indices == [2])
    guard case .user(let body) = messages[2], case .string(let text) = body.content else {
      #require(false, "replacement message should be a .user(.string)")
      return
    }
    #require(text == "second")
  }

  @Test func testAppendRemediationNudgeAppendsWhenTailIsNotANudge() {
    var messages: [ChatQuery.ChatCompletionMessageParam] = [
      sys("SYS"), usr("TASK"), tool("iter5 result", toolCallId: "t5"),
    ]
    var indices: Set<Int> = []
    AgentExecutor.appendRemediationNudge("nudge", messages: &messages, nudgeIndices: &indices)
    #require(messages.count == 4)
    #require(indices == [3])
  }

  @Test func testAppendRemediationNudgeDoesNotCollapseOriginalUserTask() {
    // On the very first iteration the tail of the conversation is the
    // user task itself. A nudge appended after a first-iter failure must
    // *append* — collapsing here would silently delete the task prompt.
    var messages: [ChatQuery.ChatCompletionMessageParam] = [sys("SYS"), usr("TASK")]
    var indices: Set<Int> = []
    AgentExecutor.appendRemediationNudge("nudge", messages: &messages, nudgeIndices: &indices)
    #require(messages.count == 3)
    guard case .user(let task) = messages[1], case .string(let taskText) = task.content else {
      #require(false, "original task at index 1 should still be present")
      return
    }
    #require(taskText == "TASK")
  }

  // MARK: - Auto-compaction

  @Test func testShouldCompactReturnsFalseWhenContextWindowIsZero() {
    #require(
      !AgentExecutor.shouldCompact(estimatedTokens: 1_000_000, contextWindowTokens: 0))
    #require(
      !AgentExecutor.shouldCompact(estimatedTokens: 1_000_000, contextWindowTokens: -1))
  }

  @Test func testShouldCompactReturnsTrueAtOrAboveThreshold() {
    let window = 200_000
    let threshold = Int(Double(window) * AgentExecutor.compactionThresholdFraction)
    #require(
      !AgentExecutor.shouldCompact(estimatedTokens: threshold - 1, contextWindowTokens: window))
    #require(
      AgentExecutor.shouldCompact(estimatedTokens: threshold, contextWindowTokens: window))
    #require(
      AgentExecutor.shouldCompact(estimatedTokens: window, contextWindowTokens: window))
  }

  @Test func testShouldCompactTracksArbitraryWindowSizes() {
    #require(!AgentExecutor.shouldCompact(estimatedTokens: 80, contextWindowTokens: 128))
    // 128 * 0.75 = 96
    #require(AgentExecutor.shouldCompact(estimatedTokens: 96, contextWindowTokens: 128))
  }

  @Test func testEstimatedTokensGrowsWithEncodedMessagePayload() {
    let short = AgentExecutor.estimatedTokens(in: [sys("SYS"), usr("hi")])
    let long = AgentExecutor.estimatedTokens(
      in: [sys("SYS"), usr(String(repeating: "x", count: 4_000))])
    #require(long > short)
    // ~4_000 chars of payload plus JSON envelope should sit comfortably
    // above 1_000 / 4 tokens — anything dramatically smaller would mean
    // the estimator silently lost the payload (e.g. a swallowed encoder
    // failure that left the message contributing zero).
    #require(long > 1_000)
  }

  @Test func testEstimatedTokensCountsAssistantToolCallsAndToolResponses() {
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
    #require(withToolTraffic > textOnly + 1_000)
  }

  @Test func testCompactedMessagesPreservesSystemAndOriginalUser() {
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
    #require(result.count == 3)
    #require(result[0] == system)
    #require(result[1] == originalUser)
    guard case .user(let recap) = result[2],
      case .string(let recapText) = recap.content
    else {
      #require(false, "expected third message to be a .user(.string) recap")
      return
    }
    #require(recapText.contains("Summary body here."))
    #require(
      recapText.contains("Compacted conversation summary"),
      "recap should label itself as a compaction so the model knows context was dropped")
    #require(
      recapText.contains("submit_result"),
      "recap should remind the model how to finish the phase")
  }

  // MARK: - Typed tool errors

  @Test func testAgentToolErrorKindMapsThroughFailureOverload() {
    #require(
      AgentToolInvocationResult.failure(.fileNotFound("missing.txt")).errorKind ==
      .fileNotFound
    )
    #require(
      AgentToolInvocationResult.failure(.editConflict("oldString not found")).errorKind ==
      .editConflict
    )
    #require(
      AgentToolInvocationResult.failure(.rpcFailure("vsock disconnected")).errorKind ==
      .rpcFailure
    )
    #require(
      AgentToolInvocationResult.failure(.invalidArguments("bad json")).errorKind ==
      .invalidArguments
    )
  }

  @Test func testAgentToolErrorKindIsNilForSuccess() {
    #require(AgentToolInvocationResult.ok("done").errorKind == nil)
  }

  @Test func testLegacyStringFailureKeepsNilKindForBackwardsCompat() {
    #require(AgentToolInvocationResult.failure("plain string").errorKind == nil)
  }

  // MARK: - helpers

  private func makeConfiguration(
    phase: AgentPhase,
    tools: [AgentTool],
    submitResultSchema: AgentToolParametersSchema? = nil
  ) -> AgentExecutionConfiguration {
    let schema =
      submitResultSchema
      ?? (AgentToolParametersSchema(literal:[
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
