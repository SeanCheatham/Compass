import Foundation
import Testing

@testable import Compass

struct ProductMarketModelTests {
  @Test func configRoundTripsWithMarkets() throws {
    let config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Market Desk",
      rawPain: "Operators cannot tell which weekly risks are budget-worthy.",
      now: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let data = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(ProductTournamentConfig.self, from: data)

    try #require(decoded == config)
    try #require(decoded.markets.count == 1)
    try #require(decoded.markets[0].actors.contains { $0.role == .economicBuyer })
    try #require(decoded.markets[0].buyingCommittees[0].actorIDs.count >= 2)
  }

  @Test func strictDecodeRejectsUnsupportedMarketFreeKeys() throws {
    let payload = """
      {
        "schemaVersion": 6,
        "rawPain": "Pain",
        "painHypotheses": [],
        "userSegments": [],
        "currentWorkflows": [],
        "alternatives": [],
        "markets": [],
        "contenderPlans": [],
        "tournamentExperiments": [],
        "tournaments": [],
        "tournamentContenders": [],
        "tournamentRounds": [],
        "scenarios": [],
        "scenarioCohorts": [],
        "decisions": [],
        "legacyMarketSummary": "retired"
      }
      """

    do {
      _ = try JSONDecoder().decode(ProductTournamentConfig.self, from: Data(payload.utf8))
      #expect(Bool(false), "Expected unsupported config key.")
    } catch let error as ProductTournamentConfigError {
      try #require(error == .unsupportedKey("legacyMarketSummary"))
    }
  }

  @Test func modelTextIsBoundedAndIdentifiersAreNormalized() throws {
    let actor = MarketActor(
      id: " Buyer Actor ",
      marketID: " Market One ",
      segmentID: " Segment One ",
      role: .economicBuyer,
      name: "",
      jobToBeDone: String(repeating: "budget ", count: 120),
      successCriteria: [String(repeating: "success ", count: 80)],
      objections: [String(repeating: "objection ", count: 80)],
      informationSources: ["  Roadmap Review  "],
      trustThreshold: String(repeating: "trust ", count: 120)
    )
    let market = ProductMarket(
      id: " Market One ",
      painID: " Pain One ",
      category: "",
      summary: String(repeating: "summary ", count: 300),
      actors: [actor],
      marketProofDebt: MarketProofDebt(attentionDeficit: -1, urgencyDeficit: 2)
    )

    try #require(market.id == "market-one")
    try #require(market.painID == "pain-one")
    try #require(market.category == "Synthetic market")
    try #require(market.summary.count <= 1_000)
    try #require(market.actors[0].id == "buyer-actor")
    try #require(market.actors[0].segmentID == "segment-one")
    try #require(market.actors[0].name == "Market actor")
    try #require(market.marketProofDebt.attentionDeficit == 0)
    try #require(market.marketProofDebt.urgencyDeficit == 2)
  }
}
