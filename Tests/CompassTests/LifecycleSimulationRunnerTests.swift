import Foundation
import Testing

@testable import Compass

@MainActor
struct LifecycleSimulationRunnerTests {
  @Test func completedFirstUseDoesNotClearRetentionDebt() throws {
    let fixture = try lifecycleFixture()
    let firstUse = try #require(fixture.scenarios.first { $0.stageID.contains("activation") })

    let record = LifecycleSimulationRunner.run(
      cohort: fixture.cohort,
      scenario: firstUse,
      config: fixture.config,
      productEvidence: "User reached a meaningful result.",
      now: Date(timeIntervalSince1970: 200)
    )
    let index = ProductTournamentEvidenceIndex.build(records: [], lifecycleRunRecords: [record])
    let debt = try #require(index.aggregate.lifecycleProofDebtByContender.first)

    try #require(record.outcome == .activated)
    try #require(debt.missingSecondUseProof)
    try #require(debt.summary.contains("second_use"))
  }

  @Test func churnReasonCreatesProofDebt() throws {
    let fixture = try lifecycleFixture()
    let secondUse = try #require(fixture.scenarios.first { $0.stageID.contains("second-use") })

    let record = LifecycleSimulationRunner.run(
      cohort: fixture.cohort,
      scenario: secondUse,
      config: fixture.config,
      productEvidence: "The user churned after novelty and did not return.",
      now: Date(timeIntervalSince1970: 200)
    )
    let index = ProductTournamentEvidenceIndex.build(records: [], lifecycleRunRecords: [record])
    let debt = try #require(index.aggregate.lifecycleProofDebtByContender.first)

    try #require(record.outcome == .churned)
    try #require(record.churnReason != nil)
    try #require(debt.hasUnresolvedChurn)
    try #require(debt.nextMove.contains("Resolve churn reason"))
  }

  @Test func repeatedUseReducesRetentionDebt() throws {
    let fixture = try lifecycleFixture()
    let activation = try #require(fixture.scenarios.first { $0.stageID.contains("activation") })
    let secondUse = try #require(fixture.scenarios.first { $0.stageID.contains("second-use") })
    let budget = try #require(fixture.scenarios.first { $0.stageID.contains("budget") })

    let records = [
      LifecycleSimulationRunner.run(
        cohort: fixture.cohort,
        scenario: activation,
        config: fixture.config,
        productEvidence: "User reached a meaningful result.",
        now: Date(timeIntervalSince1970: 200)
      ),
      LifecycleSimulationRunner.run(
        cohort: fixture.cohort,
        scenario: secondUse,
        config: fixture.config,
        productEvidence: "The user came back for repeated workflow proof and retained the habit.",
        now: Date(timeIntervalSince1970: 210)
      ),
      LifecycleSimulationRunner.run(
        cohort: fixture.cohort,
        scenario: budget,
        config: fixture.config,
        productEvidence: "The buyer paid after repeated proof reduced reporting rework.",
        now: Date(timeIntervalSince1970: 220)
      ),
    ]
    let index = ProductTournamentEvidenceIndex.build(records: [], lifecycleRunRecords: records)
    let debt = try #require(index.aggregate.lifecycleProofDebtByContender.first)

    try #require(debt.repeatedUseProofCount >= 1)
    try #require(!debt.missingSecondUseProof)
    try #require(!debt.missingBudgetMomentProof)
  }

  @Test func lifecycleRecordsPersistInLifecycleNamespace() throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = CompassWorkspace(repoURL: root)
    let fixture = try lifecycleFixture()
    let scenario = try #require(fixture.scenarios.first)
    let record = LifecycleSimulationRunner.run(
      cohort: fixture.cohort,
      scenario: scenario,
      config: fixture.config,
      now: Date(timeIntervalSince1970: 200)
    )

    let stored = try workspace.writeLifecycleRunRecord(record)

    try #require(stored == record)
    try #require(try workspace.readLifecycleRunRecord(id: record.id) == record)
    let index = workspace.readProductTournamentEvidenceIndex()
    try #require(index.lifecycleRunSummaries.map(\.runID) == [record.id])
  }
}

private struct LifecycleFixture {
  var config: ProductTournamentConfig
  var cohort: SyntheticCohort
  var scenarios: [LifecycleScenario]
}

private func lifecycleFixture() throws -> LifecycleFixture {
  let config = ProductTournamentConfig.seedDefaults(
    projectTitle: "Reporting Helper",
    rawPain: "Weekly reporting takes too long.",
    now: Date(timeIntervalSince1970: 100)
  )
  let result = try SyntheticCohortBuilder.build(
    contenderID: try #require(config.tournamentContenders.first?.id),
    in: config
  )
  return LifecycleFixture(config: config, cohort: result.cohort, scenarios: result.scenarios)
}
