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
      ("develop", Prompts.developSchema),
      ("reflect", Prompts.reflectSchema),
      ("critic", Prompts.criticSchema),
      ("subAgent", Prompts.subAgentSchema),
    ]
    for (name, text) in schemas {
      #require(!text.isEmpty, "schema \(name) is empty")
      let parsed = try JSONSerialization.jsonObject(with: Data(text.utf8))
      #require(
        parsed is [String: Any],
        "schema \(name) should decode to a JSON object"
      )
    }
  }
}
