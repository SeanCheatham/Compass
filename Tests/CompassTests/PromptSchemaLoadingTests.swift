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

  private func schemaProperties(_ schema: String) throws -> [String: Any] {
    let parsed = try JSONSerialization.jsonObject(with: Data(schema.utf8))
    let root = try #require(parsed as? [String: Any])
    return try #require(root["properties"] as? [String: Any])
  }

  private func propertyDescription(_ name: String, in properties: [String: Any]) throws -> String {
    let property = try #require(properties[name] as? [String: Any])
    return try #require(property["description"] as? String)
  }
}
