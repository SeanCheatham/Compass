import Foundation
import Testing

@testable import Compass

struct AgentRuntimeSettingsTests {
  @Test func testDefaultsFromEmptyEnvironmentSelectFoundationModels() {
    let settings = AgentRuntimeSettings.defaultFromEnvironment([:])
    #require(settings.textProvider == .appleFoundationModels)
    #require(settings.apiKey == "")
    #require(settings.planModelOverride == nil)
    #require(settings.developModelOverride == nil)
    #require(settings.reflectModelOverride == nil)
    // Foundation Models is the on-device default; its built-in
    // context window flows through to the resolved settings so
    // compaction triggers at the right ceiling for FM rather than
    // an unrelated network provider's number.
    #require(
      settings.contextWindowTokens ==
      AgentProviderKind.appleFoundationModels.defaultTextContextWindowTokens)
  }

  @Test func testEmptyEnvWithAPIKeySelectsMiniMaxContextWindow() {
    let settings = AgentRuntimeSettings.defaultFromEnvironment([
      "COMPASS_AGENT_API_KEY": "env-key"
    ])
    #require(settings.textProvider == .minimaxToken)
    #require(
      settings.contextWindowTokens ==
      AgentProviderKind.minimaxToken.defaultTextContextWindowTokens)
  }

  @Test func testContextWindowEnvironmentOverrideIsApplied() {
    let settings = AgentRuntimeSettings.defaultFromEnvironment([
      "COMPASS_AGENT_CONTEXT_WINDOW_TOKENS": "131072"
    ])
    #require(settings.contextWindowTokens == 131_072)
  }

  @Test func testContextWindowEnvironmentZeroDisablesCompaction() {
    let settings = AgentRuntimeSettings.defaultFromEnvironment([
      "COMPASS_AGENT_CONTEXT_WINDOW_TOKENS": "0"
    ])
    #require(settings.contextWindowTokens == 0)
  }

  @Test func testContextWindowEnvironmentNegativeIsClampedToZero() {
    let settings = AgentRuntimeSettings.defaultFromEnvironment([
      "COMPASS_AGENT_CONTEXT_WINDOW_TOKENS": "-50"
    ])
    #require(settings.contextWindowTokens == 0)
  }

  @Test func testContextWindowEnvironmentGarbageFallsBackToProviderDefault() {
    let settings = AgentRuntimeSettings.defaultFromEnvironment([
      "COMPASS_AGENT_CONTEXT_WINDOW_TOKENS": "not-a-number"
    ])
    // Empty API key in env → Foundation Models is the chosen
    // provider, so the fallback is FM's built-in window, not the
    // generic synthetic constant.
    #require(
      settings.contextWindowTokens ==
      AgentProviderKind.appleFoundationModels.defaultTextContextWindowTokens)
  }

  @Test func testProviderBuiltInContextWindowValues() {
    #require(
      AgentProviderKind.appleFoundationModels.defaultTextContextWindowTokens == 4_096)
    #require(
      AgentProviderKind.minimaxToken.defaultTextContextWindowTokens == 200_000)
    #require(
      AgentProviderKind.openAI.defaultTextContextWindowTokens == 128_000)
  }

  @Test func testEnvironmentOverridesAreApplied() {
    let settings = AgentRuntimeSettings.defaultFromEnvironment([
      "COMPASS_AGENT_BASE_URL": "https://example.test/v1",
      "COMPASS_AGENT_API_KEY": "sk-abc",
      "COMPASS_AGENT_MODEL": "gpt-test",
      "COMPASS_AGENT_MODEL_PLAN": "plan-model",
      "COMPASS_AGENT_MODEL_DEV": "dev-model",
      "COMPASS_AGENT_MODEL_REFLECT": "reflect-model",
      "COMPASS_AGENT_MODEL_CRITIC": "critic-model",
    ])

    #require(settings.baseURL.absoluteString == "https://example.test/v1")
    #require(settings.apiKey == "sk-abc")
    #require(settings.model == "gpt-test")
    #require(settings.planModelOverride == "plan-model")
    #require(settings.developModelOverride == "dev-model")
    #require(settings.reflectModelOverride == "reflect-model")
    #require(settings.criticModelOverride == "critic-model")
  }

  @Test func testWhitespaceOnlyEnvironmentValuesAreTreatedAsUnset() {
    let settings = AgentRuntimeSettings.defaultFromEnvironment([
      "COMPASS_AGENT_BASE_URL": "   ",
      "COMPASS_AGENT_API_KEY": "\t\n",
      "COMPASS_AGENT_MODEL": "",
      "COMPASS_AGENT_MODEL_PLAN": "   ",
    ])

    #require(settings.baseURL == AgentRuntimeSettings.defaultBaseURL)
    #require(settings.apiKey == "")
    #require(settings.model == "MiniMax-M2.7")
    #require(settings.planModelOverride == nil)
  }

  @Test func testInvalidBaseURLFallsBackToDefault() {
    let settings = AgentRuntimeSettings.defaultFromEnvironment([
      "COMPASS_AGENT_BASE_URL": ""
    ])
    #require(settings.baseURL == AgentRuntimeSettings.defaultBaseURL)
  }

  @Test func testModelForPhaseUsesDefaultWhenNoOverrides() {
    let settings = AgentRuntimeSettings(model: "default-model")
    #require(settings.model(for: .plan) == "default-model")
    #require(settings.model(for: .develop) == "default-model")
    #require(settings.model(for: .reflect) == "default-model")
  }

  @Test func testModelForPhaseUsesPhaseOverrideOverDefault() {
    let settings = AgentRuntimeSettings(
      model: "default-model",
      planModelOverride: "plan-model",
      developModelOverride: "dev-model",
      reflectModelOverride: "reflect-model",
      criticModelOverride: "critic-model"
    )
    #require(settings.model(for: .plan) == "plan-model")
    #require(settings.model(for: .develop) == "dev-model")
    #require(settings.model(for: .reflect) == "reflect-model")
    #require(settings.model(for: .critic) == "critic-model")
  }

  @Test func testCriticPhaseFallsBackToDefaultWhenNoCriticOverride() {
    let settings = AgentRuntimeSettings(model: "default-model")
    #require(settings.model(for: .critic) == "default-model")
  }

  @Test func testSidebarOverrideBeatsPhaseAndDefault() {
    let settings = AgentRuntimeSettings(
      model: "default-model",
      planModelOverride: "plan-model"
    )
    #require(settings.model(for: .plan, sidebarOverride: "sidebar-model") == "sidebar-model")
    #require(settings.model(for: .develop, sidebarOverride: "sidebar-model") == "sidebar-model")
  }

  @Test func testWhitespaceSidebarOverrideIsIgnored() {
    let settings = AgentRuntimeSettings(
      model: "default-model",
      planModelOverride: "plan-model"
    )
    #require(settings.model(for: .plan, sidebarOverride: "   ") == "plan-model")
    #require(settings.model(for: .develop, sidebarOverride: "\n") == "default-model")
  }
}