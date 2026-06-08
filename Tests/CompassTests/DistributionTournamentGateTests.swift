import Foundation
import Testing

@testable import Compass

@MainActor
struct DistributionTournamentGateTests {
  @Test func winnerBlocksWithoutChannelProof() throws {
    let config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Weekly reporting takes too long.",
      now: Date(timeIntervalSince1970: 100)
    )
    let contenderID = try #require(config.tournamentContenders.first?.id)

    let blocker = DistributionTournamentGate.winnerBlocker(
      contenderID: contenderID,
      config: config,
      evidenceIndex: .empty
    )

    try #require(blocker?.contains("run distribution pressure") == true)
  }

  @Test func failedChannelProofCreatesRewriteOrChannelMove() throws {
    let config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Weekly reporting takes too long.",
      now: Date(timeIntervalSince1970: 100)
    )
    let contenderID = try #require(config.tournamentContenders.first?.id)
    let record = distributionRecord(
      contenderID: contenderID,
      experimentID: try #require(config.distributionExperiments.first?.id),
      marketID: try #require(config.markets.first?.id),
      channelID: try #require(config.markets.first?.channels.first?.id),
      verdict: .ignored,
      attention: 1,
      buyerReachability: 1,
      createdAt: 200
    )
    let index = ProductTournamentEvidenceIndex.build(
      records: [],
      distributionPressureRecords: [record],
      now: Date(timeIntervalSince1970: 300)
    )

    let blocker = DistributionTournamentGate.winnerBlocker(
      contenderID: contenderID,
      config: config,
      evidenceIndex: index
    )

    try #require(blocker?.contains("channel proof is unresolved") == true)
    try #require(
      index.aggregate.distributionChannelProofByContender.first?.nextMove.contains("Rewrite")
        == true
        || index.aggregate.distributionChannelProofByContender.first?.nextMove.contains("Narrow")
          == true
    )
  }

  @Test func strongChannelProofReducesMarketProofDebt() throws {
    let config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Weekly reporting takes too long.",
      now: Date(timeIntervalSince1970: 100)
    )
    let contenderID = try #require(config.tournamentContenders.first?.id)
    let record = distributionRecord(
      contenderID: contenderID,
      experimentID: try #require(config.distributionExperiments.first?.id),
      marketID: try #require(config.markets.first?.id),
      channelID: try #require(config.markets.first?.channels.first?.id),
      verdict: .getsAttention,
      attention: 5,
      buyerReachability: 4,
      createdAt: 200
    )
    let index = ProductTournamentEvidenceIndex.build(
      records: [],
      distributionPressureRecords: [record],
      now: Date(timeIntervalSince1970: 300)
    )
    let proof = try #require(index.aggregate.distributionChannelProofByContender.first)

    try #require(proof.proofDebt.attentionDeficit == 0)
    try #require(proof.proofDebt.buyerReachabilityDeficit == 0)
    try #require(
      DistributionTournamentGate.winnerBlocker(
        contenderID: contenderID,
        config: config,
        evidenceIndex: index
      ) == nil
    )
  }

  @Test func pressureRecordsPersistInDistributionNamespace() throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = CompassWorkspace(repoURL: root)
    let record = distributionRecord(
      contenderID: "contender-one",
      experimentID: "distribution-one",
      marketID: "market-one",
      channelID: "channel-one",
      verdict: .needsSharperWedge,
      attention: 3,
      buyerReachability: 2,
      createdAt: 200
    )

    let stored = try workspace.writeDistributionPressureRecord(record)

    try #require(stored == record)
    try #require(try workspace.readDistributionPressureRecord(id: record.id) == record)
    let index = workspace.readProductTournamentEvidenceIndex()
    try #require(index.distributionPressureSummaries.map(\.pressureID) == [record.id])
  }
}

private func distributionRecord(
  contenderID: String,
  experimentID: String,
  marketID: String,
  channelID: String,
  verdict: DistributionVerdict,
  attention: Int,
  buyerReachability: Int,
  createdAt: Double
) -> DistributionPressureRecord {
  DistributionPressureRecord(
    id: "distribution-\(verdict.rawValue)-\(Int(createdAt))",
    experimentID: experimentID,
    marketID: marketID,
    contenderID: contenderID,
    channelID: channelID,
    simulatedAudience: "Budget owner inbox.",
    verdict: verdict,
    scores: DistributionScores(
      attention: attention,
      intentMatch: attention,
      credibility: 4,
      differentiation: 4,
      buyerReachability: buyerReachability,
      channelEconomics: 4
    ),
    objections: ["The message needs sharper buyer intent."],
    rewriteRecommendations: ["Rewrite the wedge around the urgent workflow."],
    createdAt: createdAt
  )
}
