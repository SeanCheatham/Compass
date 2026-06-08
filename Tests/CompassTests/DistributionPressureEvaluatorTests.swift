import Foundation
import Testing

@testable import Compass

struct DistributionPressureEvaluatorTests {
  @Test func ignoresVaguePitch() throws {
    let config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Weekly reporting takes too long.",
      now: Date(timeIntervalSince1970: 100)
    )
    var experiment = try #require(config.distributionExperiments.first)
    experiment.artifactText = "A revolutionary app for teams. Click now."

    let record = DistributionPressureEvaluator.evaluate(
      experiment: experiment,
      config: config,
      now: Date(timeIntervalSince1970: 200)
    )

    try #require(record.verdict == .ignored || record.verdict == .needsSharperWedge)
    try #require(record.scores.attention <= 2)
    try #require(record.rewriteRecommendations.contains { $0.contains("painful workflow") })
  }

  @Test func flagsWrongChannel() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Weekly reporting takes too long.",
      now: Date(timeIntervalSince1970: 100)
    )
    let marketID = try #require(config.markets.first?.id)
    let channel = AcquisitionChannel(
      id: "unsupported-paid-channel",
      marketID: marketID,
      kind: .paidAds,
      audience: "Broad audience with no known buyer intent.",
      userIntent: "Scrolling past generic productivity ads.",
      messageFit: "Weak fit.",
      reachability: 0,
      costRisk: 5
    )
    config.markets[0].channels = [channel]
    let contenderID = try #require(config.tournamentContenders.first?.id)
    let experiment = DistributionExperiment(
      id: "wrong-channel",
      marketID: marketID,
      contenderID: contenderID,
      channelID: channel.id,
      title: "Wrong channel",
      artifactKind: .paidAd,
      artifactText: "Weekly reporting takes too long. Try a workflow proof against the manual workaround.",
      successThreshold: "Buyer asks for proof.",
      killCriteria: "Ignored.",
      createdAt: 100
    )

    let record = DistributionPressureEvaluator.evaluate(
      experiment: experiment,
      config: config,
      now: Date(timeIntervalSince1970: 200)
    )

    try #require(record.verdict == .wrongChannel || record.verdict == .tooExpensive)
    try #require(record.scores.buyerReachability <= 1 || record.scores.channelEconomics <= 1)
  }

  @Test func rewardsSpecificUrgentPainAndCredibleWedge() throws {
    var config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Weekly reporting takes too long.",
      now: Date(timeIntervalSince1970: 100)
    )
    config.markets[0].channels[0] = AcquisitionChannel(
      id: config.markets[0].channels[0].id,
      marketID: config.markets[0].id,
      kind: .founderLedSales,
      audience: "Budget owner already feeling the reporting workflow pain.",
      userIntent: "They want a clearer path through the painful handoff.",
      messageFit: "Lead with the exact weekly reporting failure.",
      reachability: 5,
      costRisk: 1,
      proofRequired: ["A 15 minute proof against the manual workflow."]
    )
    let experiment = try DistributionExperimentBuilder.build(
      contenderID: try #require(config.tournamentContenders.first?.id),
      in: config,
      artifactKind: .salesScript,
      now: Date(timeIntervalSince1970: 150)
    )

    let record = DistributionPressureEvaluator.evaluate(
      experiment: experiment,
      config: config,
      now: Date(timeIntervalSince1970: 200)
    )

    try #require(record.verdict == .getsAttention)
    try #require(record.scores.attention >= 4)
    try #require(record.scores.buyerReachability >= 3)
  }
}
