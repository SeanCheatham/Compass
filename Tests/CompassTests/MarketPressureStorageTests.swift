import Foundation
import Testing

@testable import Compass

@MainActor
struct MarketPressureStorageTests {
  @Test func recordWritesToMarketPressureNamespace() throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = CompassWorkspace(repoURL: root)
    let record = pressureRecord(kind: .buyingCommittee, verdict: .narrowed, createdAt: 100)

    let stored = try workspace.writeMarketPressureRecord(record)

    try #require(stored == record)
    try #require(
      FileManager.default.fileExists(
        atPath: workspace.productTournamentURL
          .appending(path: "market-pressure", directoryHint: .isDirectory)
          .appending(path: record.id, directoryHint: .isDirectory)
          .appending(path: "record.json")
          .path
      ))
    try #require(try workspace.readMarketPressureRecord(id: record.id) == record)
  }

  @Test func evidenceIndexIncludesPressureSummaries() throws {
    let first = pressureRecord(kind: .buyingCommittee, verdict: .narrowed, createdAt: 100)
    let second = pressureRecord(kind: .incumbentDefense, verdict: .survives, createdAt: 200)

    let index = ProductTournamentEvidenceIndex.build(
      records: [],
      marketPressureRecords: [first, second],
      now: Date(timeIntervalSince1970: 300)
    )

    try #require(index.marketPressureSummaries.map(\.evaluationID) == [second.id, first.id])
    try #require(index.aggregate.latestMarketPressureByContender["contender-one"] == second.id)
    try #require(index.aggregate.marketPressureByContender["contender-one"]?.count == 2)
  }

  @Test func aggregateFindsRepeatedPressureObjections() throws {
    let first = pressureRecord(
      kind: .buyingCommittee,
      verdict: .blocked,
      objection: "No clear buyer.",
      createdAt: 100
    )
    let second = pressureRecord(
      kind: .budgetChallenge,
      verdict: .blocked,
      objection: "No clear buyer.",
      createdAt: 200
    )

    let index = ProductTournamentEvidenceIndex.build(
      records: [],
      marketPressureRecords: [first, second],
      now: Date(timeIntervalSince1970: 300)
    )

    try #require(index.aggregate.marketPressureObjections.first?.objection == "no clear buyer.")
    try #require(index.aggregate.marketPressureObjections.first?.count == 2)
  }
}

private func pressureRecord(
  kind: MarketPressureKind,
  verdict: MarketPressureVerdict,
  objection: String = "No clear buyer.",
  createdAt: Double
) -> MarketPressureEvaluationRecord {
  MarketPressureEvaluationRecord(
    id: "pressure-\(kind.rawValue)-\(Int(createdAt))",
    tournamentID: "tournament-one",
    roundID: "round-one",
    marketID: "market-one",
    contenderID: "contender-one",
    pressureKind: kind,
    actorIDs: ["actor-one"],
    verdict: verdict,
    scores: MarketPressureScores(
      attention: 3,
      urgency: 3,
      incumbentAdvantage: 2,
      buyerClarity: 2,
      budgetFit: 2,
      trustReadiness: 3,
      channelFit: 2,
      retentionRisk: 3
    ),
    objections: [objection],
    proofDebtDelta: MarketProofDebtDelta(buyerClarityDelta: 1),
    requiredNextProof: ["Find buyer."],
    transcriptSummary: "Pressure summary.",
    createdAt: createdAt
  )
}
