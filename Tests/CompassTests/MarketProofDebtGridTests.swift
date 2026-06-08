import Foundation
import Testing

@testable import Compass

struct MarketProofDebtGridTests {
  @Test func debtStatusesMapToDisplayLabels() throws {
    let market = ProductMarket(
      id: "market",
      painID: "pain",
      category: "ops",
      summary: "Operations workflow",
      marketProofDebt: MarketProofDebt(
        attentionDeficit: 0,
        urgencyDeficit: 1,
        buyerClarityDeficit: 0,
        budgetFitDeficit: 2,
        incumbentDefeatDeficit: 0,
        channelFitDeficit: 1,
        retentionDeficit: 0,
        committeeDeficit: 0
      )
    )

    let grid = MarketProofDebtGrid.build(market: market)

    try #require(cell(.attention, in: grid).status == .clear)
    try #require(cell(.urgency, in: grid).status == .missing)
    try #require(cell(.budget, in: grid).label == "Budget")
    try #require(cell(.budget, in: grid).status.label == "missing")
  }

  @Test func latestMovementIsShown() throws {
    let market = ProductMarket(
      id: "market",
      painID: "pain",
      category: "ops",
      summary: "Operations workflow",
      marketProofDebt: MarketProofDebt(incumbentDefeatDeficit: 0)
    )
    let row = MarketPressureRow(
      id: "pressure",
      kind: .incumbentDefense,
      contenderID: "contender",
      actorIDs: [],
      verdict: "survives",
      status: .survived,
      strongestObjection: "",
      debtMovement: "incumbent -1",
      nextAction: "Advance"
    )

    let grid = MarketProofDebtGrid.build(market: market, pressureRows: [row])

    try #require(cell(.incumbent, in: grid).status == .moved)
    try #require(cell(.incumbent, in: grid).latestMovement == "-1")
  }

  @Test func blockedDebtOutranksMissingDebt() throws {
    let market = ProductMarket(
      id: "market",
      painID: "pain",
      category: "ops",
      summary: "Operations workflow",
      marketProofDebt: MarketProofDebt(
        urgencyDeficit: 1,
        incumbentDefeatDeficit: 1
      )
    )
    let row = MarketPressureRow(
      id: "pressure",
      kind: .incumbentDefense,
      contenderID: "contender",
      actorIDs: [],
      verdict: "blocked",
      status: .blocked,
      strongestObjection: "Incumbent wins.",
      debtMovement: "incumbent +1",
      nextAction: "Reframe"
    )

    let grid = MarketProofDebtGrid.build(market: market, pressureRows: [row])

    try #require(cell(.incumbent, in: grid).status == .blocked)
    try #require(cell(.urgency, in: grid).status == .missing)
    try #require(grid.dominantStatus == .blocked)
  }

  private func cell(
    _ dimension: MarketProofDebtDimension,
    in grid: MarketProofDebtSummary
  ) throws -> MarketProofDebtCell {
    try #require(grid.cells.first { $0.dimension == dimension })
  }
}
