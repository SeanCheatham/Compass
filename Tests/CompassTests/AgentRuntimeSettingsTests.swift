import Foundation
import XCTest

@testable import Compass

final class AgentRuntimeSettingsTests: XCTestCase {
  func testDefaultsFromEmptyEnvironmentSelectFoundationModels() {
    let settings = AgentRuntimeSettings.defaultFromEnvironment([:])
    XCTAssertEqual(settings.textProvider, .appleFoundationModels)
    XCTAssertEqual(settings.apiKey, "")
    XCTAssertNil(settings.planModelOverride)
    XCTAssertNil(settings.developModelOverride)
    XCTAssertNil(settings.reflectModelOverride)
    // Foundation Models is the on-device default; its built-in
    // context window flows through to the resolved settings so
    // compaction triggers at the right ceiling for FM rather than
    // an unrelated network provider's number.
    XCTAssertEqual(
      settings.contextWindowTokens,
      AgentProviderKind.appleFoundationModels.defaultTextContextWindowTokens)
  }

  func testEmptyEnvWithAPIKeySelectsMiniMaxContextWindow() {
    let settings = AgentRuntimeSettings.defaultFromEnvironment([
      "COMPASS_AGENT_API_KEY": "env-key"
    ])
    XCTAssertEqual(settings.textProvider, .minimaxToken)
    XCTAssertEqual(
      settings.contextWindowTokens,
      AgentProviderKind.minimaxToken.defaultTextContextWindowTokens)
  }

  func testContextWindowEnvironmentOverrideIsApplied() {
    let settings = AgentRuntimeSettings.defaultFromEnvironment([
      "COMPASS_AGENT_CONTEXT_WINDOW_TOKENS": "131072"
    ])
    XCTAssertEqual(settings.contextWindowTokens, 131_072)
  }

  func testContextWindowEnvironmentZeroDisablesCompaction() {
    let settings = AgentRuntimeSettings.defaultFromEnvironment([
      "COMPASS_AGENT_CONTEXT_WINDOW_TOKENS": "0"
    ])
    XCTAssertEqual(settings.contextWindowTokens, 0)
  }

  func testContextWindowEnvironmentNegativeIsClampedToZero() {
    let settings = AgentRuntimeSettings.defaultFromEnvironment([
      "COMPASS_AGENT_CONTEXT_WINDOW_TOKENS": "-50"
    ])
    XCTAssertEqual(settings.contextWindowTokens, 0)
  }

  func testContextWindowEnvironmentGarbageFallsBackToProviderDefault() {
    let settings = AgentRuntimeSettings.defaultFromEnvironment([
      "COMPASS_AGENT_CONTEXT_WINDOW_TOKENS": "not-a-number"
    ])
    // Empty API key in env → Foundation Models is the chosen
    // provider, so the fallback is FM's built-in window, not the
    // generic synthetic constant.
    XCTAssertEqual(
      settings.contextWindowTokens,
      AgentProviderKind.appleFoundationModels.defaultTextContextWindowTokens)
  }

  func testProviderBuiltInContextWindowValues() {
    XCTAssertEqual(
      AgentProviderKind.appleFoundationModels.defaultTextContextWindowTokens, 4_096)
    XCTAssertEqual(
      AgentProviderKind.minimaxToken.defaultTextContextWindowTokens, 200_000)
    XCTAssertEqual(
      AgentProviderKind.openAI.defaultTextContextWindowTokens, 128_000)
  }

  func testEnvironmentOverridesAreApplied() {
    let settings = AgentRuntimeSettings.defaultFromEnvironment([
      "COMPASS_AGENT_BASE_URL": "https://example.test/v1",
      "COMPASS_AGENT_API_KEY": "sk-abc",
      "COMPASS_AGENT_MODEL": "gpt-test",
      "COMPASS_AGENT_MODEL_PLAN": "plan-model",
      "COMPASS_AGENT_MODEL_DEV": "dev-model",
      "COMPASS_AGENT_MODEL_REFLECT": "reflect-model",
      "COMPASS_AGENT_MODEL_CRITIC": "critic-model",
    ])

    XCTAssertEqual(settings.baseURL.absoluteString, "https://example.test/v1")
    XCTAssertEqual(settings.apiKey, "sk-abc")
    XCTAssertEqual(settings.model, "gpt-test")
    XCTAssertEqual(settings.planModelOverride, "plan-model")
    XCTAssertEqual(settings.developModelOverride, "dev-model")
    XCTAssertEqual(settings.reflectModelOverride, "reflect-model")
    XCTAssertEqual(settings.criticModelOverride, "critic-model")
  }

  func testWhitespaceOnlyEnvironmentValuesAreTreatedAsUnset() {
    let settings = AgentRuntimeSettings.defaultFromEnvironment([
      "COMPASS_AGENT_BASE_URL": "   ",
      "COMPASS_AGENT_API_KEY": "\t\n",
      "COMPASS_AGENT_MODEL": "",
      "COMPASS_AGENT_MODEL_PLAN": "   ",
    ])

    XCTAssertEqual(settings.baseURL, AgentRuntimeSettings.defaultBaseURL)
    XCTAssertEqual(settings.apiKey, "")
    XCTAssertEqual(settings.model, "MiniMax-M2.7")
    XCTAssertNil(settings.planModelOverride)
  }

  func testInvalidBaseURLFallsBackToDefault() {
    let settings = AgentRuntimeSettings.defaultFromEnvironment([
      "COMPASS_AGENT_BASE_URL": ""
    ])
    XCTAssertEqual(settings.baseURL, AgentRuntimeSettings.defaultBaseURL)
  }

  func testModelForPhaseUsesDefaultWhenNoOverrides() {
    let settings = AgentRuntimeSettings(model: "default-model")
    XCTAssertEqual(settings.model(for: .plan), "default-model")
    XCTAssertEqual(settings.model(for: .develop), "default-model")
    XCTAssertEqual(settings.model(for: .reflect), "default-model")
  }

  func testModelForPhaseUsesPhaseOverrideOverDefault() {
    let settings = AgentRuntimeSettings(
      model: "default-model",
      planModelOverride: "plan-model",
      developModelOverride: "dev-model",
      reflectModelOverride: "reflect-model",
      criticModelOverride: "critic-model"
    )
    XCTAssertEqual(settings.model(for: .plan), "plan-model")
    XCTAssertEqual(settings.model(for: .develop), "dev-model")
    XCTAssertEqual(settings.model(for: .reflect), "reflect-model")
    XCTAssertEqual(settings.model(for: .critic), "critic-model")
  }

  func testCriticPhaseFallsBackToDefaultWhenNoCriticOverride() {
    let settings = AgentRuntimeSettings(model: "default-model")
    XCTAssertEqual(settings.model(for: .critic), "default-model")
  }

  func testSidebarOverrideBeatsPhaseAndDefault() {
    let settings = AgentRuntimeSettings(
      model: "default-model",
      planModelOverride: "plan-model"
    )
    XCTAssertEqual(settings.model(for: .plan, sidebarOverride: "sidebar-model"), "sidebar-model")
    XCTAssertEqual(settings.model(for: .develop, sidebarOverride: "sidebar-model"), "sidebar-model")
  }

  func testWhitespaceSidebarOverrideIsIgnored() {
    let settings = AgentRuntimeSettings(
      model: "default-model",
      planModelOverride: "plan-model"
    )
    XCTAssertEqual(settings.model(for: .plan, sidebarOverride: "   "), "plan-model")
    XCTAssertEqual(settings.model(for: .develop, sidebarOverride: "\n"), "default-model")
  }
}
