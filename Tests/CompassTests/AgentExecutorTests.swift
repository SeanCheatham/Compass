import Foundation
import OpenAI
import XCTest

@testable import Compass

final class AgentExecutorTests: XCTestCase {
  // MARK: - stripThinkBlocks

  func testStripThinkBlocksOnPlainTextIsNoop() {
    let (text, reasoning) = AgentExecutor.stripThinkBlocks("hello world")
    XCTAssertEqual(text, "hello world")
    XCTAssertEqual(reasoning, "")
  }

  func testStripThinkBlocksExtractsSingleBlock() {
    let (text, reasoning) = AgentExecutor.stripThinkBlocks("before <think>secret</think> after")
    XCTAssertEqual(text, "before  after")
    XCTAssertEqual(reasoning, "secret")
  }

  func testStripThinkBlocksExtractsMultipleBlocks() {
    let (text, reasoning) = AgentExecutor.stripThinkBlocks(
      "a<think>one</think>b<think>two</think>c")
    XCTAssertEqual(text, "abc")
    XCTAssertEqual(reasoning, "onetwo")
  }

  func testStripThinkBlocksHandlesUnterminatedBlock() {
    let (text, reasoning) = AgentExecutor.stripThinkBlocks("visible <think>oops never closed")
    XCTAssertEqual(text, "visible ")
    XCTAssertEqual(reasoning, "oops never closed")
  }

  // MARK: - Budget exhaustion classification

  func testIsAgentBudgetExhaustionCoversWallClockAndIterationLimits() {
    XCTAssertTrue(AgentExecutionError.wallClockExceeded(3600).isAgentBudgetExhaustion)
    XCTAssertTrue(AgentExecutionError.maxIterationsExceeded(512).isAgentBudgetExhaustion)
  }

  func testIsAgentBudgetExhaustionRejectsNonBudgetCauses() {
    XCTAssertFalse(AgentExecutionError.cancelled.isAgentBudgetExhaustion)
    XCTAssertFalse(AgentExecutionError.streamFailed("boom").isAgentBudgetExhaustion)
    XCTAssertFalse(AgentExecutionError.modelStoppedWithoutSubmitResult.isAgentBudgetExhaustion)
    XCTAssertFalse(
      AgentExecutionError.toolCallDecodeFailed(name: "x", detail: "y").isAgentBudgetExhaustion
    )
    XCTAssertFalse(AgentExecutionError.duplicateToolName("z").isAgentBudgetExhaustion)
  }

  func testDefaultWallClockTimeoutIsOneHour() {
    let configuration = makeConfiguration(phase: .plan, tools: ToolRegistry.readOnlyTools())
    XCTAssertEqual(configuration.wallClockTimeout, 60 * 60)
  }

  // MARK: - Transient stream-error classification

  func testTransientHTTPStatusesCoverOverloadAndCloudflareCodes() {
    let transient = [408, 425, 429, 500, 502, 503, 504, 520, 521, 522, 523, 524, 525, 526, 529]
    for code in transient {
      XCTAssertTrue(
        AgentExecutor.isTransientHTTPStatus(code),
        "Expected \(code) to be classified transient"
      )
    }
  }

  func testTransientHTTPStatusesRejectClientAndSuccessCodes() {
    let permanent = [200, 201, 204, 301, 400, 401, 403, 404, 422, 451]
    for code in permanent {
      XCTAssertFalse(
        AgentExecutor.isTransientHTTPStatus(code),
        "Expected \(code) to be classified permanent"
      )
    }
  }

  func testShouldRetryAcceptsOpenAIStatusErrorsForTransientStatuses() {
    let response = HTTPURLResponse(
      url: URL(string: "https://api.example.com")!,
      statusCode: 529,
      httpVersion: nil,
      headerFields: nil
    )!
    let error = OpenAIError.statusError(response: response, statusCode: 529)
    XCTAssertTrue(AgentExecutor.shouldRetry(error))
  }

  func testShouldRetryRejectsOpenAIStatusErrorsForPermanentStatuses() {
    let response = HTTPURLResponse(
      url: URL(string: "https://api.example.com")!,
      statusCode: 400,
      httpVersion: nil,
      headerFields: nil
    )!
    let error = OpenAIError.statusError(response: response, statusCode: 400)
    XCTAssertFalse(AgentExecutor.shouldRetry(error))
  }

  func testShouldRetryAcceptsTransientURLErrors() {
    XCTAssertTrue(AgentExecutor.shouldRetry(URLError(.timedOut)))
    XCTAssertTrue(AgentExecutor.shouldRetry(URLError(.networkConnectionLost)))
    XCTAssertTrue(AgentExecutor.shouldRetry(URLError(.notConnectedToInternet)))
  }

  func testShouldRetryRejectsPermanentURLErrors() {
    XCTAssertFalse(AgentExecutor.shouldRetry(URLError(.badURL)))
    XCTAssertFalse(AgentExecutor.shouldRetry(URLError(.unsupportedURL)))
    XCTAssertFalse(AgentExecutor.shouldRetry(URLError(.cancelled)))
  }

  func testShouldRetryRejectsUnrelatedErrors() {
    struct OtherError: Error {}
    XCTAssertFalse(AgentExecutor.shouldRetry(OtherError()))
    XCTAssertFalse(AgentExecutor.shouldRetry(AgentExecutionError.cancelled))
  }

  func testRetryDelayGrowsExponentiallyWithJitterAndCaps() {
    // Attempt 1 should sit around 1s (0.8 - 1.2 with jitter).
    let first = AgentExecutor.retryDelay(forAttempt: 1)
    XCTAssertGreaterThanOrEqual(first, AgentExecutor.baseStreamRetryDelay * 0.8)
    XCTAssertLessThanOrEqual(first, AgentExecutor.baseStreamRetryDelay * 1.2)

    // Attempt 4 = base * 2^3 = 8s before jitter, well under the cap.
    let fourth = AgentExecutor.retryDelay(forAttempt: 4)
    XCTAssertGreaterThanOrEqual(fourth, 8.0 * 0.8)
    XCTAssertLessThanOrEqual(fourth, 8.0 * 1.2)

    // Attempt 100 would explode to 2^99 seconds; the cap must hold.
    let huge = AgentExecutor.retryDelay(forAttempt: 100)
    XCTAssertGreaterThanOrEqual(huge, AgentExecutor.maxStreamRetryDelay * 0.8)
    XCTAssertLessThanOrEqual(huge, AgentExecutor.maxStreamRetryDelay * 1.2)
  }

  // MARK: - ensureUniqueToolNames

  func testEnsureUniqueToolNamesAcceptsDistinctTools() throws {
    XCTAssertNoThrow(try AgentExecutor.ensureUniqueToolNames(ToolRegistry.readOnlyTools()))
    XCTAssertNoThrow(try AgentExecutor.ensureUniqueToolNames(ToolRegistry.developTools()))
    XCTAssertNoThrow(try AgentExecutor.ensureUniqueToolNames(ToolRegistry.inspectionTools()))
  }

  // MARK: - Tool registry per phase

  func testCriticPhaseGetsReadOnlyPlusBash() {
    let names = Set(ToolRegistry.tools(for: .critic).map { $0.spec.name })
    XCTAssertTrue(names.contains(AgentBashTool.toolName))
    XCTAssertTrue(names.contains(AgentReadFileTool.toolName))
    XCTAssertTrue(names.contains(AgentFindSymbolTool.toolName))
    XCTAssertTrue(names.contains(AgentDelegateTool.toolName))
    XCTAssertFalse(
      names.contains(AgentWriteFileTool.toolName),
      "Critic must not have write_file")
    XCTAssertFalse(
      names.contains(AgentEditFileTool.toolName),
      "Critic must not have edit_file")
  }

  func testDelegateToolIsExposedToAllPhases() {
    for phase in AgentPhase.allCases {
      let names = Set(ToolRegistry.tools(for: phase).map { $0.spec.name })
      XCTAssertTrue(
        names.contains(AgentDelegateTool.toolName),
        "phase \(phase) must include `delegate`")
    }
  }

  func testEnsureUniqueToolNamesRejectsDuplicates() {
    let tools: [AgentTool] = [AgentReadFileTool(), AgentReadFileTool()]
    XCTAssertThrowsError(try AgentExecutor.ensureUniqueToolNames(tools)) { error in
      guard case AgentExecutionError.duplicateToolName(let name) = error else {
        return XCTFail("expected duplicateToolName, got \(error)")
      }
      XCTAssertEqual(name, AgentReadFileTool.toolName)
    }
  }

  func testEnsureUniqueToolNamesRejectsCollisionWithSubmitResult() {
    struct FakeSubmit: AgentTool {
      let spec = AgentToolSpec(
        name: AgentExecutor.submitResultToolName,
        description: "shadow",
        parameters: try! AgentToolParametersSchema(["type": "object"])
      )
      func invoke(arguments: Data, context: AgentToolContext) async throws
        -> AgentToolInvocationResult
      { .ok("") }
    }
    XCTAssertThrowsError(try AgentExecutor.ensureUniqueToolNames([FakeSubmit()])) { error in
      guard case AgentExecutionError.duplicateToolName(let name) = error else {
        return XCTFail("expected duplicateToolName, got \(error)")
      }
      XCTAssertEqual(name, AgentExecutor.submitResultToolName)
    }
  }

  // MARK: - buildOpenAITools

  func testBuildOpenAIToolsIncludesEveryToolPlusSubmitResult() throws {
    let configuration = makeConfiguration(
      phase: .plan,
      tools: ToolRegistry.readOnlyTools()
    )
    let params = try AgentExecutor.buildOpenAITools(configuration: configuration)
    let names = params.map { $0.function.name }
    XCTAssertEqual(
      Set(names),
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

  func testBuildOpenAIToolsCarriesSubmitSchemaThroughDecodeReencode() throws {
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
    let submit = try XCTUnwrap(
      params.first { $0.function.name == AgentExecutor.submitResultToolName })
    let rendered = try JSONEncoder().encode(submit.function.parameters)
    let object = try JSONSerialization.jsonObject(with: rendered) as? [String: Any]
    XCTAssertEqual(object?["type"] as? String, "object")
    XCTAssertEqual(object?["additionalProperties"] as? Bool, false)
    let properties = object?["properties"] as? [String: Any]
    let status = properties?["status"] as? [String: Any]
    XCTAssertEqual(status?["type"] as? String, "string")
    XCTAssertEqual(status?["enum"] as? [String], ["succeeded", "blocked", "failed"])
  }

  // MARK: - phase routing

  func testToolsForPhasePicksInspectionSetForPlanAndReflect() {
    let planNames = Set(ToolRegistry.tools(for: .plan).map { $0.spec.name })
    let reflectNames = Set(ToolRegistry.tools(for: .reflect).map { $0.spec.name })
    let inspectionNames = Set(ToolRegistry.inspectionTools().map { $0.spec.name })
    XCTAssertEqual(planNames, inspectionNames)
    XCTAssertEqual(reflectNames, inspectionNames)
    XCTAssertTrue(
      planNames.contains(AgentBashTool.toolName),
      "Plan must have bash so it can run builds/tests to ground its plan")
    XCTAssertTrue(
      reflectNames.contains(AgentBashTool.toolName),
      "Reflect must have bash so it can probe the project during course-correction")
    XCTAssertFalse(planNames.contains(AgentWriteFileTool.toolName))
    XCTAssertFalse(planNames.contains(AgentEditFileTool.toolName))
    XCTAssertFalse(reflectNames.contains(AgentWriteFileTool.toolName))
    XCTAssertFalse(reflectNames.contains(AgentEditFileTool.toolName))
  }

  func testToolsForPhasePicksFullSetForDevelop() {
    let names = Set(ToolRegistry.tools(for: .develop).map { $0.spec.name })
    XCTAssertTrue(names.contains(AgentBashTool.toolName))
    XCTAssertTrue(names.contains(AgentWriteFileTool.toolName))
    XCTAssertTrue(names.contains(AgentEditFileTool.toolName))
    XCTAssertTrue(names.contains(AgentReadFileTool.toolName))
  }

  // MARK: - Invalid submit_result remediation

  func testInvalidSubmitResultNudgeUsesTruncationCopyWhenFinishReasonIsLength() {
    let nudge = AgentExecutor.invalidSubmitResultNudge(
      finishReason: "length",
      argumentsPreview: "{\"state\":{...}",
      maxCompletionTokens: 65_536
    )
    XCTAssertEqual(nudge.eventText, "submit_result truncated")
    XCTAssertTrue(nudge.eventDetail.contains("65536"))
    XCTAssertTrue(nudge.userMessage.contains("truncated by the output-token limit"))
    XCTAssertTrue(nudge.userMessage.contains("complete, valid JSON"))
  }

  func testInvalidSubmitResultNudgeUsesRejectedCopyWhenFinishReasonIsNotLength() {
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
      XCTAssertEqual(
        nudge.eventText, "submit_result rejected",
        "finishReason=\(reason ?? "nil") should not be treated as the length variant")
      XCTAssertTrue(
        nudge.eventDetail.contains("GitReposit"),
        "rejected detail should include the args preview so the user can see what was bad")
      XCTAssertTrue(
        nudge.userMessage.contains("could not be parsed as JSON"),
        "rejected nudge should explain the parse failure")
      XCTAssertTrue(
        nudge.userMessage.contains("shorter"),
        "rejected nudge should still push the model toward shorter output, since silent truncation is the most common cause"
      )
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

  func testRollbackDropsOnlyAssistantWhenSubmitResultWasTheOnlyToolCall() {
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
    XCTAssertEqual(messages.count, 3)
    if case .tool = messages.last {
    } else {
      XCTFail("rollback should land on the prior tool response, got \(messages.last as Any)")
    }
  }

  func testRollbackDropsOrphanedToolResponsesAlongsideAssistant() {
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
    XCTAssertEqual(messages.count, 2)
    if case .user = messages.last {
    } else {
      XCTFail("rollback should leave the original user task as the tail")
    }
  }

  func testRollbackDropsStaleNudgeIndices() {
    var messages: [ChatQuery.ChatCompletionMessageParam] = [
      sys("SYS"), usr("TASK"), usr("nudge-old"), asst(toolCallIDs: ["t1"]),
    ]
    var indices: Set<Int> = [2]
    AgentExecutor.rollback(messages: &messages, nudgeIndices: &indices, to: 3)
    XCTAssertEqual(messages.count, 3)
    XCTAssertTrue(
      indices.contains(2),
      "rollback to index 3 must keep nudge-tracking entries whose index < 3")
  }

  func testRollbackToEqualOrGreaterCountIsNoop() {
    var messages: [ChatQuery.ChatCompletionMessageParam] = [sys("SYS"), usr("TASK")]
    var indices: Set<Int> = [1]
    AgentExecutor.rollback(messages: &messages, nudgeIndices: &indices, to: 2)
    XCTAssertEqual(messages.count, 2)
    AgentExecutor.rollback(messages: &messages, nudgeIndices: &indices, to: 99)
    XCTAssertEqual(messages.count, 2)
    XCTAssertEqual(indices, [1])
  }

  func testAppendRemediationNudgeReplacesConsecutiveNudge() {
    // Back-to-back failed iterations would otherwise leave two `.user`
    // messages in a row, which strict providers (MiniMax) reject with a
    // 400. Confirm the helper collapses the second append into a
    // replacement.
    var messages: [ChatQuery.ChatCompletionMessageParam] = [sys("SYS"), usr("TASK")]
    var indices: Set<Int> = []

    AgentExecutor.appendRemediationNudge("first", messages: &messages, nudgeIndices: &indices)
    XCTAssertEqual(messages.count, 3)
    XCTAssertEqual(indices, [2])

    AgentExecutor.appendRemediationNudge("second", messages: &messages, nudgeIndices: &indices)
    XCTAssertEqual(messages.count, 3, "second nudge must replace the first, not stack")
    XCTAssertEqual(indices, [2])
    guard case .user(let body) = messages[2], case .string(let text) = body.content else {
      return XCTFail("replacement message should be a .user(.string)")
    }
    XCTAssertEqual(text, "second")
  }

  func testAppendRemediationNudgeAppendsWhenTailIsNotANudge() {
    var messages: [ChatQuery.ChatCompletionMessageParam] = [
      sys("SYS"), usr("TASK"), tool("iter5 result", toolCallId: "t5"),
    ]
    var indices: Set<Int> = []
    AgentExecutor.appendRemediationNudge("nudge", messages: &messages, nudgeIndices: &indices)
    XCTAssertEqual(messages.count, 4)
    XCTAssertEqual(indices, [3])
  }

  func testAppendRemediationNudgeDoesNotCollapseOriginalUserTask() {
    // On the very first iteration the tail of the conversation is the
    // user task itself. A nudge appended after a first-iter failure must
    // *append* — collapsing here would silently delete the task prompt.
    var messages: [ChatQuery.ChatCompletionMessageParam] = [sys("SYS"), usr("TASK")]
    var indices: Set<Int> = []
    AgentExecutor.appendRemediationNudge("nudge", messages: &messages, nudgeIndices: &indices)
    XCTAssertEqual(messages.count, 3)
    guard case .user(let task) = messages[1], case .string(let taskText) = task.content else {
      return XCTFail("original task at index 1 should still be present")
    }
    XCTAssertEqual(taskText, "TASK")
  }

  // MARK: - Auto-compaction

  func testShouldCompactReturnsFalseWhenContextWindowIsZero() {
    XCTAssertFalse(
      AgentExecutor.shouldCompact(estimatedTokens: 1_000_000, contextWindowTokens: 0))
    XCTAssertFalse(
      AgentExecutor.shouldCompact(estimatedTokens: 1_000_000, contextWindowTokens: -1))
  }

  func testShouldCompactReturnsTrueAtOrAboveThreshold() {
    let window = 200_000
    let threshold = Int(Double(window) * AgentExecutor.compactionThresholdFraction)
    XCTAssertFalse(
      AgentExecutor.shouldCompact(estimatedTokens: threshold - 1, contextWindowTokens: window))
    XCTAssertTrue(
      AgentExecutor.shouldCompact(estimatedTokens: threshold, contextWindowTokens: window))
    XCTAssertTrue(
      AgentExecutor.shouldCompact(estimatedTokens: window, contextWindowTokens: window))
  }

  func testShouldCompactTracksArbitraryWindowSizes() {
    XCTAssertFalse(AgentExecutor.shouldCompact(estimatedTokens: 80, contextWindowTokens: 128))
    // 128 * 0.75 = 96
    XCTAssertTrue(AgentExecutor.shouldCompact(estimatedTokens: 96, contextWindowTokens: 128))
  }

  func testEstimatedTokensGrowsWithEncodedMessagePayload() {
    let short = AgentExecutor.estimatedTokens(in: [sys("SYS"), usr("hi")])
    let long = AgentExecutor.estimatedTokens(
      in: [sys("SYS"), usr(String(repeating: "x", count: 4_000))])
    XCTAssertGreaterThan(long, short)
    // ~4_000 chars of payload plus JSON envelope should sit comfortably
    // above 1_000 / 4 tokens — anything dramatically smaller would mean
    // the estimator silently lost the payload (e.g. a swallowed encoder
    // failure that left the message contributing zero).
    XCTAssertGreaterThan(long, 1_000)
  }

  func testEstimatedTokensCountsAssistantToolCallsAndToolResponses() {
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
    XCTAssertGreaterThan(withToolTraffic, textOnly + 1_000)
  }

  func testCompactedMessagesPreservesSystemAndOriginalUser() {
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
    XCTAssertEqual(result.count, 3)
    XCTAssertEqual(result[0], system)
    XCTAssertEqual(result[1], originalUser)
    guard case .user(let recap) = result[2],
      case .string(let recapText) = recap.content
    else {
      return XCTFail("expected third message to be a .user(.string) recap")
    }
    XCTAssertTrue(recapText.contains("Summary body here."))
    XCTAssertTrue(
      recapText.contains("Compacted conversation summary"),
      "recap should label itself as a compaction so the model knows context was dropped")
    XCTAssertTrue(
      recapText.contains("submit_result"),
      "recap should remind the model how to finish the phase")
  }

  // MARK: - Typed tool errors

  func testAgentToolErrorKindMapsThroughFailureOverload() {
    XCTAssertEqual(
      AgentToolInvocationResult.failure(.fileNotFound("missing.txt")).errorKind,
      .fileNotFound
    )
    XCTAssertEqual(
      AgentToolInvocationResult.failure(.editConflict("oldString not found")).errorKind,
      .editConflict
    )
    XCTAssertEqual(
      AgentToolInvocationResult.failure(.rpcFailure("vsock disconnected")).errorKind,
      .rpcFailure
    )
    XCTAssertEqual(
      AgentToolInvocationResult.failure(.invalidArguments("bad json")).errorKind,
      .invalidArguments
    )
  }

  func testAgentToolErrorKindIsNilForSuccess() {
    XCTAssertNil(AgentToolInvocationResult.ok("done").errorKind)
  }

  func testLegacyStringFailureKeepsNilKindForBackwardsCompat() {
    XCTAssertNil(AgentToolInvocationResult.failure("plain string").errorKind)
  }

  // MARK: - helpers

  private func makeConfiguration(
    phase: AgentPhase,
    tools: [AgentTool],
    submitResultSchema: AgentToolParametersSchema? = nil
  ) -> AgentExecutionConfiguration {
    let schema =
      submitResultSchema
      ?? (try! AgentToolParametersSchema([
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
