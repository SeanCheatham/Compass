import Foundation
import FoundationModels
import Testing

@testable import Compass

struct FoundationModelsSchemaTranslatorTests {
  @Test
  func testNullableAnyOfBranchesResolveToConcreteSchemaNodes() throws {
    let developProperties = try properties(in: schemaObject(Prompts.developSchema))
    let bypassVerify = try property("bypassVerify", in: developProperties)
    #expect(try nullableBranchType(in: bypassVerify) == "boolean")

    let developLessonEdits = try property("lessonEdits", in: developProperties)
    let developLessonItem = try #require(developLessonEdits["items"] as? [String: Any])
    let developLessonProperties = try properties(in: developLessonItem)
    let developReplaceAll = try property("replaceAll", in: developLessonProperties)
    #expect(try nullableBranchType(in: developReplaceAll) == "boolean")

    let planSchema = try schemaObject(Prompts.planSchema)
    let planProperties = try properties(in: planSchema)
    let state = try property("state", in: planProperties)
    let stateProperties = try properties(in: state)
    let immediate = try property("immediate", in: stateProperties)
    let immediateBranch = try nullableBranch(in: immediate, root: planSchema)
    #expect(immediateBranch["type"] as? String == "object")

    let immediateProperties = try properties(in: immediateBranch)
    let verifyTimeout = try property("verifyTimeoutMs", in: immediateProperties)
    #expect(try nullableBranchType(in: verifyTimeout) == "integer")

    let difficulty = try property("estimatedDifficulty", in: immediateProperties)
    let difficultyBranch = try nullableBranch(in: difficulty)
    #expect(difficultyBranch["type"] as? String == "string")
    #expect((difficultyBranch["enum"] as? [String]) == ["low", "medium", "high"])
  }

  @Test
  func testNullableAnyOfBranchesAreDetectedThroughReferences() throws {
    let planSchema = try schemaObject(Prompts.planSchema)
    let planProperties = try properties(in: planSchema)
    let state = try property("state", in: planProperties)
    let stateProperties = try properties(in: state)
    let immediate = try property("immediate", in: stateProperties)

    #expect(CompassJSONSchemaTranslation.containsNullAnyOf(in: immediate, root: planSchema))
  }

  @Test
  func testDynamicSchemaBuildsPlanSchemaWithNullableImmediate() throws {
    let schema = try FoundationModelsSchemaTranslator.dynamicSchema(
      name: "submit_result",
      description: "Submit the final structured result for this phase.",
      from: AgentToolParametersSchema(json: Data(Prompts.planSchema.utf8))
    )

    #expect(!schema.debugDescription.isEmpty)
  }

  @Test
  func testSubmitResultSchemaBuilderKeepsNestedPayloadPermissive() throws {
    let schema = try FoundationModelsSchemaTranslator.topLevelGeneratedContentSchema(
      name: "submit_result",
      description: "Submit the final structured result for this phase.",
      from: AgentToolParametersSchema(json: Data(Prompts.planSchema.utf8))
    )

    #expect(!schema.debugDescription.isEmpty)
  }

  @Test
  func testGeneratedContentJSONDataEncodesLineRangeEditArguments() throws {
    let replacementLines = ["let a = \"quoted\"", "let b = 3"]
    let edit = GeneratedContent(
      properties: [
        "startLine": 10,
        "endLine": 11,
        "replacementLines": GeneratedContent(elements: replacementLines),
      ]
    )
    let arguments = GeneratedContent(
      properties: [
        "path": "Sources/App.swift",
        "edits": GeneratedContent(elements: [edit]),
      ]
    )

    let data = try FoundationModelsAgentRuntime.jsonData(from: arguments)
    let json = String(decoding: data, as: UTF8.self)
    #expect(json.contains("startLine"))
    #expect(json.contains("replacementLines"))
    #expect(json.contains(#"\"quoted\""#))

    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let edits = try #require(object?["edits"] as? [[String: Any]])
    let firstEdit = try #require(edits.first)
    #expect(firstEdit["startLine"] as? Int == 10)
    #expect(firstEdit["endLine"] as? Int == 11)
    #expect(firstEdit["replacementLines"] as? [String] == replacementLines)
  }

  @Test
  func testUnsupportedAnyOfUnionsRemainUnsupported() {
    let unsupported: [String: Any] = [
      "anyOf": [
        ["type": "string"],
        ["type": "boolean"],
      ]
    ]

    #expect(CompassJSONSchemaTranslation.concreteNullableAnyOfBranch(in: unsupported) == nil)
  }

  private func nullableBranchType(in property: [String: Any]) throws -> String {
    let branch = try nullableBranch(in: property)
    return try #require(branch["type"] as? String)
  }

  private func nullableBranch(
    in property: [String: Any],
    root: [String: Any]? = nil
  ) throws -> [String: Any] {
    try #require(CompassJSONSchemaTranslation.concreteNullableAnyOfBranch(in: property, root: root))
  }

  private func schemaObject(_ schema: String) throws -> [String: Any] {
    let parsed = try JSONSerialization.jsonObject(with: Data(schema.utf8))
    return try #require(parsed as? [String: Any])
  }

  private func properties(in object: [String: Any]) throws -> [String: Any] {
    try #require(object["properties"] as? [String: Any])
  }

  private func property(_ name: String, in properties: [String: Any]) throws -> [String: Any] {
    try #require(properties[name] as? [String: Any])
  }
}
