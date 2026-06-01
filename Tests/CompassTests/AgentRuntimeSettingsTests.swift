import Foundation
import Testing

@testable import Compass

struct AgentRuntimeSettingsTests {
  @Test func testDefaultsFromEmptyEnvironmentSelectFoundationModels() throws {
    let settings = AgentRuntimeSettings.defaultFromEnvironment([:])
    try #require(settings.textProvider == .appleFoundationModels)
    try #require(settings.apiKey == "")
    try #require(settings.planModelOverride == nil)
    try #require(settings.developModelOverride == nil)
    try #require(settings.reflectModelOverride == nil)
    // Foundation Models is the on-device default; its built-in
    // context window flows through to the resolved settings so
    // compaction triggers at the right ceiling for FM rather than
    // an unrelated network provider's number.
    try #require(
      settings.contextWindowTokens
        == AgentProviderKind.appleFoundationModels.defaultTextContextWindowTokens)
  }

  @Test func testEmptyEnvWithAPIKeySelectsMiniMaxContextWindow() throws {
    let settings = AgentRuntimeSettings.defaultFromEnvironment([
      "COMPASS_AGENT_API_KEY": "env-key"
    ])
    try #require(settings.textProvider == .minimaxToken)
    try #require(
      settings.contextWindowTokens == AgentProviderKind.minimaxToken.defaultTextContextWindowTokens)
  }

  @Test func testContextWindowEnvironmentOverrideIsApplied() throws {
    let settings = AgentRuntimeSettings.defaultFromEnvironment([
      "COMPASS_AGENT_CONTEXT_WINDOW_TOKENS": "131072"
    ])
    try #require(settings.contextWindowTokens == 131_072)
  }

  @Test func testContextWindowEnvironmentZeroDisablesCompaction() throws {
    let settings = AgentRuntimeSettings.defaultFromEnvironment([
      "COMPASS_AGENT_CONTEXT_WINDOW_TOKENS": "0"
    ])
    try #require(settings.contextWindowTokens == 0)
  }

  @Test func testContextWindowEnvironmentNegativeIsClampedToZero() throws {
    let settings = AgentRuntimeSettings.defaultFromEnvironment([
      "COMPASS_AGENT_CONTEXT_WINDOW_TOKENS": "-50"
    ])
    try #require(settings.contextWindowTokens == 0)
  }

  @Test func testContextWindowEnvironmentGarbageFallsBackToProviderDefault() throws {
    let settings = AgentRuntimeSettings.defaultFromEnvironment([
      "COMPASS_AGENT_CONTEXT_WINDOW_TOKENS": "not-a-number"
    ])
    // Empty API key in env → Foundation Models is the chosen
    // provider, so the fallback is FM's built-in window, not the
    // generic synthetic constant.
    try #require(
      settings.contextWindowTokens
        == AgentProviderKind.appleFoundationModels.defaultTextContextWindowTokens)
  }

  @Test func testProviderBuiltInContextWindowValues() throws {
    try #require(
      AgentProviderKind.appleFoundationModels.defaultTextContextWindowTokens == 4_096)
    try #require(
      AgentProviderKind.minimaxToken.defaultTextContextWindowTokens == 1_000_000)
    try #require(
      AgentProviderKind.openAI.defaultTextContextWindowTokens == 128_000)
  }

  @Test func testEnvironmentOverridesAreApplied() throws {
    let settings = AgentRuntimeSettings.defaultFromEnvironment([
      "COMPASS_AGENT_BASE_URL": "https://example.test/v1",
      "COMPASS_AGENT_API_KEY": "sk-abc",
      "COMPASS_AGENT_MODEL": "gpt-test",
      "COMPASS_AGENT_MODEL_PLAN": "plan-model",
      "COMPASS_AGENT_MODEL_DEV": "dev-model",
      "COMPASS_AGENT_MODEL_REFLECT": "reflect-model",
      "COMPASS_AGENT_MODEL_CRITIC": "critic-model",
    ])

    try #require(settings.baseURL.absoluteString == "https://example.test/v1")
    try #require(settings.apiKey == "sk-abc")
    try #require(settings.model == "gpt-test")
    try #require(settings.planModelOverride == "plan-model")
    try #require(settings.developModelOverride == "dev-model")
    try #require(settings.reflectModelOverride == "reflect-model")
    try #require(settings.criticModelOverride == "critic-model")
  }

  @Test func testWhitespaceOnlyEnvironmentValuesAreTreatedAsUnset() throws {
    let settings = AgentRuntimeSettings.defaultFromEnvironment([
      "COMPASS_AGENT_BASE_URL": "   ",
      "COMPASS_AGENT_API_KEY": "\t\n",
      "COMPASS_AGENT_MODEL": "",
      "COMPASS_AGENT_MODEL_PLAN": "   ",
    ])

    try #require(settings.baseURL == AgentRuntimeSettings.defaultBaseURL)
    try #require(settings.apiKey == "")
    try #require(settings.model == "MiniMax-M3")
    try #require(settings.planModelOverride == nil)
  }

  @Test func testInvalidBaseURLFallsBackToDefault() throws {
    let settings = AgentRuntimeSettings.defaultFromEnvironment([
      "COMPASS_AGENT_BASE_URL": ""
    ])
    try #require(settings.baseURL == AgentRuntimeSettings.defaultBaseURL)
  }

  @Test func testModelForPhaseUsesDefaultWhenNoOverrides() throws {
    let settings = AgentRuntimeSettings(model: "default-model")
    try #require(settings.model(for: .plan) == "default-model")
    try #require(settings.model(for: .develop) == "default-model")
    try #require(settings.model(for: .reflect) == "default-model")
  }

  @Test func testModelForPhaseUsesPhaseOverrideOverDefault() throws {
    let settings = AgentRuntimeSettings(
      model: "default-model",
      planModelOverride: "plan-model",
      developModelOverride: "dev-model",
      reflectModelOverride: "reflect-model",
      criticModelOverride: "critic-model"
    )
    try #require(settings.model(for: .plan) == "plan-model")
    try #require(settings.model(for: .develop) == "dev-model")
    try #require(settings.model(for: .reflect) == "reflect-model")
    try #require(settings.model(for: .critic) == "critic-model")
  }

  @Test func testCriticPhaseFallsBackToDefaultWhenNoCriticOverride() throws {
    let settings = AgentRuntimeSettings(model: "default-model")
    try #require(settings.model(for: .critic) == "default-model")
  }

  @Test func testSidebarOverrideBeatsPhaseAndDefault() throws {
    let settings = AgentRuntimeSettings(
      model: "default-model",
      planModelOverride: "plan-model"
    )
    try #require(settings.model(for: .plan, sidebarOverride: "sidebar-model") == "sidebar-model")
    try #require(settings.model(for: .develop, sidebarOverride: "sidebar-model") == "sidebar-model")
  }

  @Test func testWhitespaceSidebarOverrideIsIgnored() throws {
    let settings = AgentRuntimeSettings(
      model: "default-model",
      planModelOverride: "plan-model"
    )
    try #require(settings.model(for: .plan, sidebarOverride: "   ") == "plan-model")
    try #require(settings.model(for: .develop, sidebarOverride: "\n") == "default-model")
  }
}
