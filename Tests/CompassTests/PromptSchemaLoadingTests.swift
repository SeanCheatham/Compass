import Foundation
import Testing

@testable import Compass

/// Smoke tests for the resource-bundle-backed schema constants. Tests
/// don't otherwise hit the schemas (only the live agent execution path
/// reads `Prompts.planSchema` / etc.), so an SPM/Xcode resource-bundle
/// mismatch would slip through CI and only surface when a user clicks
/// Play. Touching every schema here makes the regression loud.
struct PromptSchemaLoadingTests {
  @Test
  func testAllSchemasLoadAndParseAsJSONObjects() throws {
    let schemas: [(String, String)] = [
      ("plan", Prompts.planSchema),
      ("planHostXcode", Prompts.planHostXcodeSchema),
      ("discover", Prompts.discoverSchema),
      ("develop", Prompts.developSchema),
      ("reflect", Prompts.reflectSchema),
      ("reflectHostXcode", Prompts.reflectHostXcodeSchema),
      ("critic", Prompts.criticSchema),
      ("subAgent", Prompts.subAgentSchema),
    ]
    for (name, text) in schemas {
      try #require(!text.isEmpty, "schema \(name) is empty")
      let parsed = try JSONSerialization.jsonObject(with: Data(text.utf8))
      try #require(
        parsed is [String: Any],
        "schema \(name) should decode to a JSON object"
      )
    }
  }

  @Test
  func testHostXcodeSchemasAreOnlySelectedWhenProjectOptInIsEnabled() throws {
    #expect(Prompts.planSchema(hostXcodeBuildTestEnabled: false) == Prompts.planSchema)
    #expect(
      Prompts.planSchema(hostXcodeBuildTestEnabled: true) == Prompts.planHostXcodeSchema
    )
    #expect(Prompts.reflectSchema(hostXcodeBuildTestEnabled: false) == Prompts.reflectSchema)
    #expect(
      Prompts.reflectSchema(hostXcodeBuildTestEnabled: true) == Prompts.reflectHostXcodeSchema
    )
    #expect(!Prompts.planSchema.contains("requiresHostXcode"))
    #expect(Prompts.planHostXcodeSchema.contains("requiresHostXcode"))
  }

  @Test
  func testDevelopAndCriticSchemasDescribeRepairContracts() throws {
    let developProperties = try schemaProperties(Prompts.developSchema)
    let criticProperties = try schemaProperties(Prompts.criticSchema)

    try #require(
      propertyDescription("feedback", in: developProperties)
        .contains("Concrete handoff for the next Plan pass")
    )
    try #require(
      propertyDescription("bypassVerify", in: developProperties)
        .contains("verify command itself is wrong or out of scope")
    )
    try #require(
      propertyDescription("bypassVerify", in: developProperties)
        .contains("concrete file, suite, command, or environment detail")
    )
    try #require(propertyDescription("bypassVerify", in: developProperties).contains("not yet run"))

    try #require(
      propertyDescription("verdict", in: criticProperties)
        .contains("real, fixable problem")
    )
    try #require(
      propertyDescription("feedback", in: criticProperties)
        .contains("concrete punch list")
    )
  }

  @Test
  func testDiscoverSchemaDescribesStructuredProductTournamentEdits() throws {
    let properties = try schemaProperties(Prompts.discoverSchema)

    try #require(try additionalProperties(Prompts.discoverSchema) == false)
    try #require(propertyDescription("summary", in: properties).contains("pain model"))
    try #require(properties.keys.contains("stateEdits"))
    try #require(properties.keys.contains("candidateExperiments"))
    try #require(propertyDescription("stateEdits", in: properties).contains("Product Tournament"))
    try #require(propertyDescription("stateEdits", in: properties).contains("tournament rounds"))
    try #require(
      propertyDescription("candidateExperiments", in: properties)
        .contains("after the plan-only round")
    )
  }

  @Test
  func testReflectSchemasAllowTournamentDecisionUpdates() throws {
    for schema in [Prompts.reflectSchema, Prompts.reflectHostXcodeSchema] {
      let properties = try schemaProperties(schema)
      try #require(properties.keys.contains("tournamentDecisionUpdates"))
      try #require(!properties.keys.contains("productDecisionUpdates"))
      try #require(
        propertyDescription("tournamentDecisionUpdates", in: properties)
          .contains("Tournament experiment decision updates"))
    }
  }

  @Test
  func testPlanSchemasKeepCommandsOutOfAcceptanceChecks() throws {
    for schema in [Prompts.planSchema, Prompts.planHostXcodeSchema] {
      let immediateProperties = try planImmediateProperties(schema)
      try #require(
        propertyDescription("plan", in: immediateProperties)
          .contains("Acceptance checks must describe observable behavior")
      )
      try #require(
        propertyDescription("plan", in: immediateProperties)
          .contains("not shell commands")
      )
      try #require(
        propertyDescription("verify", in: immediateProperties)
          .contains("Put commands here, not in Acceptance checks")
      )
    }
  }

  private func schemaProperties(_ schema: String) throws -> [String: Any] {
    let parsed = try JSONSerialization.jsonObject(with: Data(schema.utf8))
    let root = try #require(parsed as? [String: Any])
    return try #require(root["properties"] as? [String: Any])
  }

  private func additionalProperties(_ schema: String) throws -> Bool {
    let parsed = try JSONSerialization.jsonObject(with: Data(schema.utf8))
    let root = try #require(parsed as? [String: Any])
    return try #require(root["additionalProperties"] as? Bool)
  }

  private func propertyDescription(_ name: String, in properties: [String: Any]) throws -> String {
    let property = try #require(properties[name] as? [String: Any])
    return try #require(property["description"] as? String)
  }

  private func planImmediateProperties(_ schema: String) throws -> [String: Any] {
    let parsed = try JSONSerialization.jsonObject(with: Data(schema.utf8))
    let root = try #require(parsed as? [String: Any])
    let rootProperties = try #require(root["properties"] as? [String: Any])
    let state = try #require(rootProperties["state"] as? [String: Any])
    let stateProperties = try #require(state["properties"] as? [String: Any])
    let immediate = try resolvedSchemaObject(
      try #require(stateProperties["immediate"] as? [String: Any]),
      root: root
    )
    let variants = try #require(immediate["anyOf"] as? [[String: Any]])
    let objectVariant = try #require(variants.first { $0["type"] as? String == "object" })
    return try #require(objectVariant["properties"] as? [String: Any])
  }

  private func resolvedSchemaObject(
    _ object: [String: Any],
    root: [String: Any]
  ) throws -> [String: Any] {
    guard let ref = object["$ref"] as? String else { return object }
    let components = ref.split(separator: "/").map(String.init)
    guard components == ["#", "$defs", "immediate"] else {
      return object
    }
    let defs = try #require(root["$defs"] as? [String: Any])
    return try #require(defs["immediate"] as? [String: Any])
  }
}
