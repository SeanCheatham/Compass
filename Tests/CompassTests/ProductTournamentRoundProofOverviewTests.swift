import Foundation
import Testing

@testable import Compass

@MainActor
struct ProductTournamentRoundProofOverviewTests {
  @Test func activeRoundControlsTheOnlyRoundSpecificProofOverview() async throws {
    let cases = try [
      ProofOverviewCase(
        name: "round-1-plan",
        config: roundOneConfig(),
        expectedDigestHeading: "Round 1 plan-proof contender overview",
        expectedWorkbenchHeading: "Round 1 Proof Deltas",
        absentDigestHeadings: [
          "Round 2 core-technology proof overview",
          "Round 3 prototype proof overview",
        ],
        absentWorkbenchHeadings: [
          "Core Technology Proof",
          "Prototype Winner Proof",
        ]
      ),
      ProofOverviewCase(
        name: "round-2-core-technology",
        config: roundTwoConfig(),
        expectedDigestHeading: "Round 2 core-technology proof overview",
        expectedWorkbenchHeading: "Core Technology Proof",
        absentDigestHeadings: [
          "Round 1 plan-proof contender overview",
          "Round 3 prototype proof overview",
        ],
        absentWorkbenchHeadings: [
          "Round 1 Proof Deltas",
          "Prototype Winner Proof",
        ]
      ),
      ProofOverviewCase(
        name: "round-3-prototype",
        config: roundThreeConfig(),
        expectedDigestHeading: "Round 3 prototype proof overview",
        expectedWorkbenchHeading: "Prototype Winner Proof",
        absentDigestHeadings: [
          "Round 1 plan-proof contender overview",
          "Round 2 core-technology proof overview",
        ],
        absentWorkbenchHeadings: [
          "Round 1 Proof Deltas",
          "Core Technology Proof",
        ]
      ),
    ]

    for proofCase in cases {
      let evidenceIndex = ProductTournamentEvidenceIndex.build(records: [])
      let digest = ProductTournamentPlanningDigestFormatter.promptText(
        config: proofCase.config,
        evidenceIndex: evidenceIndex
      )
      let workbenchBody = try await workbenchBody(for: proofCase.config)

      try #require(
        digest.contains(proofCase.expectedDigestHeading),
        "Expected \(proofCase.name) context to include \(proofCase.expectedDigestHeading)."
      )
      try #require(
        workbenchBody.contains(proofCase.expectedWorkbenchHeading),
        "Expected \(proofCase.name) Workbench to include \(proofCase.expectedWorkbenchHeading)."
      )
      for absentHeading in proofCase.absentDigestHeadings {
        try #require(
          !digest.contains(absentHeading),
          "Did not expect \(proofCase.name) context to include \(absentHeading)."
        )
      }
      for absentHeading in proofCase.absentWorkbenchHeadings {
        try #require(
          !workbenchBody.contains(absentHeading),
          "Did not expect \(proofCase.name) Workbench to include \(absentHeading)."
        )
      }
    }
  }
}

private struct ProofOverviewCase {
  var name: String
  var config: ProductTournamentConfig
  var expectedDigestHeading: String
  var expectedWorkbenchHeading: String
  var absentDigestHeadings: [String]
  var absentWorkbenchHeadings: [String]
}

private func roundOneConfig() throws -> ProductTournamentConfig {
  ProductTournamentConfig.seedDefaults(
    projectTitle: "Reporting Helper",
    rawPain: "Weekly reporting takes too long.",
    now: Date(timeIntervalSince1970: 1_700_000_000)
  )
}

private func roundTwoConfig() throws -> ProductTournamentConfig {
  try configWithActiveRound(.coreTechnology)
}

private func roundThreeConfig() throws -> ProductTournamentConfig {
  try configWithActiveRound(.prototype)
}

private func configWithActiveRound(
  _ activeKind: ProductTournamentRoundKind
) throws -> ProductTournamentConfig {
  var config = try roundOneConfig()
  let tournament = try #require(config.tournaments.first)
  let contender = try #require(config.tournamentContenders.first)
  let planRound = try #require(config.tournamentRounds.first { $0.kind == .productPlans })
  let coreRound = try #require(config.tournamentRounds.first { $0.kind == .coreTechnology })
  let prototypeRound = try #require(config.tournamentRounds.first { $0.kind == .prototype })

  let activeRound: ProductTournamentRound
  switch activeKind {
  case .productPlans:
    activeRound = planRound
  case .coreTechnology:
    activeRound = coreRound
  case .prototype:
    activeRound = prototypeRound
  }

  if let tournamentIndex = config.tournaments.firstIndex(where: { $0.id == tournament.id }) {
    config.tournaments[tournamentIndex].currentRoundID = activeRound.id
  }
  for index in config.tournamentRounds.indices {
    switch config.tournamentRounds[index].kind {
    case .productPlans:
      config.tournamentRounds[index].status =
        activeKind == .productPlans ? .active : .completed
    case .coreTechnology:
      config.tournamentRounds[index].status =
        activeKind == .coreTechnology ? .active : activeKind == .prototype ? .completed : .planned
      config.tournamentRounds[index].contenderIDs = [contender.id]
    case .prototype:
      config.tournamentRounds[index].status =
        activeKind == .prototype ? .active : .planned
      config.tournamentRounds[index].contenderIDs = [contender.id]
    }
  }
  if activeKind != .productPlans,
    let contenderIndex = config.tournamentContenders.firstIndex(where: { $0.id == contender.id })
  {
    config.tournamentContenders[contenderIndex].status = .narrowed
  }
  return config
}

@MainActor
private func workbenchBody(
  for config: ProductTournamentConfig
) async throws -> String {
  let root = try makeTempDir()
  defer { try? FileManager.default.removeItem(at: root) }
  try initGitRepo(at: root)
  let workspace = CompassWorkspace(repoURL: root)
  try workspace.initialize()
  try workspace.writeProductTournamentConfig(config)

  let project = CompassProject(repoURL: root)
  await project.refresh()
  return String(reflecting: ProductTournamentWorkbenchTab(project: project).body)
}
