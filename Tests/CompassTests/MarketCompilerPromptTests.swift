import Foundation
import Testing

@testable import Compass

struct MarketCompilerPromptTests {
  @Test func promptIncludesMarketFirstRules() throws {
    let prompt = try Prompts.marketCompilerPrompt(
      context: DiscoveryPromptContext(
        rawPain: "Weekly reporting pain.",
        productTournamentConfig: compilerBaseConfig()
      ))

    try #require(prompt.contains("Start with the market, not the product"))
    try #require(prompt.contains("operator, economic buyer"))
    try #require(prompt.contains("current alternative persuasive"))
    try #require(prompt.contains("non-software alternative"))
    try #require(prompt.contains("plausible distribution path"))
  }

  @Test func promptForbidsInventingEvidence() throws {
    let prompt = try Prompts.marketCompilerPrompt(
      context: DiscoveryPromptContext(rawPain: "Support handoff pain.")
    )

    try #require(prompt.contains("Mark every claim as synthetic"))
    try #require(prompt.contains("user-provided text"))
    try #require(prompt.contains("blocked_by_insufficient_pain"))
  }

  @Test func promptRequiresCurrentAlternativesBuyerChannelAndBlockers() throws {
    let prompt = try Prompts.marketCompilerPrompt(
      context: DiscoveryPromptContext(rawPain: "Finance handoff pain.")
    )

    try #require(prompt.contains("likely buyer"))
    try #require(prompt.contains("channel"))
    try #require(prompt.contains("incumbent"))
    try #require(prompt.contains("why it might be unreachable"))
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
