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
    XCTAssertFalse(AgentExecutionError.configurationInvalid("nope").isAgentBudgetExhaustion)
    XCTAssertFalse(
      AgentExecutionError.toolCallDecodeFailed(name: "x", detail: "y").isAgentBudgetExhaustion
    )
    XCTAssertFalse(AgentExecutionError.duplicateToolName("z").isAgentBudgetExhaustion)
  }

  func testDefaultWallClockTimeoutIsOneHour() {
    let configuration = makeConfiguration(phase: .plan, tools: AgentExecutor.readOnlyTools())
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
    XCTAssertNoThrow(try AgentExecutor.ensureUniqueToolNames(AgentExecutor.readOnlyTools()))
    XCTAssertNoThrow(try AgentExecutor.ensureUniqueToolNames(AgentExecutor.developTools()))
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
      tools: AgentExecutor.readOnlyTools()
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
      tools: AgentExecutor.developTools(),
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

  func testToolsForPhasePicksReadOnlyForPlanAndReflect() {
    let planNames = Set(AgentExecutor.toolsForPhase(.plan).map { $0.spec.name })
    let reflectNames = Set(AgentExecutor.toolsForPhase(.reflect).map { $0.spec.name })
    let readOnlyNames = Set(AgentExecutor.readOnlyTools().map { $0.spec.name })
    XCTAssertEqual(planNames, readOnlyNames)
    XCTAssertEqual(reflectNames, readOnlyNames)
    XCTAssertFalse(planNames.contains(AgentBashTool.toolName))
    XCTAssertFalse(planNames.contains(AgentWriteFileTool.toolName))
    XCTAssertFalse(planNames.contains(AgentEditFileTool.toolName))
  }

  func testToolsForPhasePicksFullSetForDevelop() {
    let names = Set(AgentExecutor.toolsForPhase(.develop).map { $0.spec.name })
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

  // MARK: - Auto-compaction

  func testShouldCompactReturnsFalseWhenContextWindowIsZero() {
    XCTAssertFalse(AgentExecutor.shouldCompact(totalTokens: 1_000_000, contextWindowTokens: 0))
    XCTAssertFalse(AgentExecutor.shouldCompact(totalTokens: 1_000_000, contextWindowTokens: -1))
  }

  func testShouldCompactReturnsTrueAtOrAboveThreshold() {
    let window = 200_000
    let threshold = Int(Double(window) * AgentExecutor.compactionThresholdFraction)
    XCTAssertFalse(
      AgentExecutor.shouldCompact(totalTokens: threshold - 1, contextWindowTokens: window))
    XCTAssertTrue(AgentExecutor.shouldCompact(totalTokens: threshold, contextWindowTokens: window))
    XCTAssertTrue(AgentExecutor.shouldCompact(totalTokens: window, contextWindowTokens: window))
  }

  func testShouldCompactTrackesArbitraryWindowSizes() {
    XCTAssertFalse(AgentExecutor.shouldCompact(totalTokens: 80, contextWindowTokens: 128))
    // 128 * 0.75 = 96
    XCTAssertTrue(AgentExecutor.shouldCompact(totalTokens: 96, contextWindowTokens: 128))
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
