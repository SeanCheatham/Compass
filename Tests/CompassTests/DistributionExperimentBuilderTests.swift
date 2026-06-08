import Foundation
import Testing

@testable import Compass

struct DistributionExperimentBuilderTests {
  @Test func createsColdEmailWithBuyerPainIncumbentAndCTA() throws {
    let config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Weekly reporting takes too long.",
      now: Date(timeIntervalSince1970: 100)
    )
    let contenderID = try #require(config.tournamentContenders.first?.id)

    let experiment = try DistributionExperimentBuilder.build(
      contenderID: contenderID,
      in: config,
      artifactKind: .coldEmail,
      now: Date(timeIntervalSince1970: 200)
    )

    try #require(experiment.artifactKind == .coldEmail)
    try #require(experiment.artifactText.contains("Budget owner"))
    try #require(experiment.artifactText.lowercased().contains("weekly reporting"))
    try #require(experiment.artifactText.contains("Manual workflow plus shared document"))
    try #require(experiment.artifactText.lowercased().contains("next step"))
  }

  @Test func createsSEOPageWithQueryIntentAndAlternativeComparison() throws {
    let config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Weekly reporting takes too long.",
      now: Date(timeIntervalSince1970: 100)
    )
    let contenderID = try #require(config.tournamentContenders.first?.id)

    let experiment = try DistributionExperimentBuilder.build(
      contenderID: contenderID,
      in: config,
      artifactKind: .seoPage,
      now: Date(timeIntervalSince1970: 200)
    )

    try #require(experiment.artifactText.contains("Search intent"))
    try #require(experiment.artifactText.contains("Manual workflow plus shared document"))
    try #require(experiment.artifactText.contains("Proof"))
  }

  @Test func createsCommunityPostWithoutUnsupportedHype() throws {
    let config = ProductTournamentConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Weekly reporting takes too long.",
      now: Date(timeIntervalSince1970: 100)
    )
    let contenderID = try #require(config.tournamentContenders.first?.id)

    let experiment = try DistributionExperimentBuilder.build(
      contenderID: contenderID,
      in: config,
      artifactKind: .communityPost,
      now: Date(timeIntervalSince1970: 200)
    )

    let lower = experiment.artifactText.lowercased()
    try #require(lower.contains("honest comparison"))
    try #require(!lower.contains("revolutionary"))
    try #require(!lower.contains("game-changing"))
    try #require(!lower.contains("magic"))
  }
}
