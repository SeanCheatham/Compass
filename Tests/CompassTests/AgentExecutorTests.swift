import Foundation
@testable import Compass
import XCTest

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
        let (text, reasoning) = AgentExecutor.stripThinkBlocks("a<think>one</think>b<think>two</think>c")
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

    // MARK: - ensureUniqueToolNames

    func testEnsureUniqueToolNamesAcceptsDistinctTools() throws {
        XCTAssertNoThrow(try AgentExecutor.ensureUniqueToolNames(AgentExecutor.readOnlyTools()))
        XCTAssertNoThrow(try AgentExecutor.ensureUniqueToolNames(AgentExecutor.developTools()))
    }

    func testEnsureUniqueToolNamesRejectsDuplicates() {
        let tools: [AgentTool] = [AgentReadFileTool(), AgentReadFileTool()]
        XCTAssertThrowsError(try AgentExecutor.ensureUniqueToolNames(tools)) { error in
            guard case let AgentExecutionError.duplicateToolName(name) = error else {
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
            func invoke(arguments: Data, context: AgentToolContext) async throws -> AgentToolInvocationResult { .ok("") }
        }
        XCTAssertThrowsError(try AgentExecutor.ensureUniqueToolNames([FakeSubmit()])) { error in
            guard case let AgentExecutionError.duplicateToolName(name) = error else {
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
        XCTAssertEqual(Set(names), Set([
            AgentReadFileTool.toolName,
            AgentLsTool.toolName,
            AgentGrepTool.toolName,
            AgentGlobTool.toolName,
            AgentExecutor.submitResultToolName
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
                    "enum": ["succeeded", "blocked", "failed"]
                ]
            ]
        ])
        let configuration = makeConfiguration(
            phase: .develop,
            tools: AgentExecutor.developTools(),
            submitResultSchema: schema
        )
        let params = try AgentExecutor.buildOpenAITools(configuration: configuration)
        let submit = try XCTUnwrap(params.first { $0.function.name == AgentExecutor.submitResultToolName })
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

    // MARK: - helpers

    private func makeConfiguration(
        phase: AgentPhase,
        tools: [AgentTool],
        submitResultSchema: AgentToolParametersSchema? = nil
    ) -> AgentExecutionConfiguration {
        let schema = submitResultSchema ?? (try! AgentToolParametersSchema([
            "type": "object",
            "additionalProperties": false,
            "properties": [:]
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
