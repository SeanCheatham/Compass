import Foundation
import Testing

@testable import Compass

struct MarketCompilerPromptTests {
  @Test func promptIncludesPMFProofLoopRules() throws {
    let prompt = try Prompts.marketCompilerPrompt(
      context: DiscoveryPromptContext(
        rawPain: "Weekly reporting pain.",
        productTournamentConfig: compilerBaseConfig()
      ))

    try #require(prompt.contains("PMF Proof Loop seed compiler"))
    try #require(prompt.contains("Start with the pain, current alternative"))
    try #require(prompt.contains("current alternative persuasive"))
    try #require(prompt.contains("non-software alternative"))
    try #require(prompt.contains("marketEdits as a legacy compatibility holder"))
  }

  @Test func promptForbidsInventingEvidence() throws {
    let prompt = try Prompts.marketCompilerPrompt(
      context: DiscoveryPromptContext(rawPain: "Support handoff pain.")
    )

    try #require(prompt.contains("Mark every claim as synthetic"))
    try #require(prompt.contains("user-provided text"))
    try #require(prompt.contains("blocked_by_insufficient_pain"))
  }

  @Test func promptRetiresDistributionLifecycleAndMarketPressure() throws {
    let prompt = try Prompts.marketCompilerPrompt(
      context: DiscoveryPromptContext(rawPain: "Finance handoff pain.")
    )

    try #require(prompt.contains("likely buyer"))
    try #require(prompt.contains("incumbent"))
    try #require(prompt.contains("Leave distributionExperimentEdits empty"))
    try #require(prompt.contains("Do not create lifecycle cohorts"))
    try #require(prompt.contains("market-pressure runs"))
    try #require(!prompt.contains("plausible distribution path"))
  }
}

private func compilerBaseConfig() -> ProductTournamentConfig {
  var config = ProductTournamentConfig.seedDefaults(
    projectTitle: "Compiler Base",
    rawPain: "Weekly reporting pain.",
    now: Date(timeIntervalSince1970: 1_700_000_000)
  )
  config.markets = []
  return config
}
