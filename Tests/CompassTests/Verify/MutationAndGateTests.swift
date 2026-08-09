import Foundation
import Testing

@testable import CompassCore

@Suite("MutationReportParser")
struct MutationReportParserTests {
  @Test
  func parsesTallyAndMissedSection() {
    let output = """
      info: Running 1 job
      crates/core/src/lib.rs:12: replace add -> i64 with 0 ... caught in 1.2s build + 0.3s test
      crates/core/src/lib.rs:18: replace is_empty -> bool with true ... missed in 0.8s build + 0.2s test
      Missed mutants:
      crates/core/src/lib.rs:18: replace is_empty -> bool with true
      2 mutants tested in 3.1s: 1 caught, 1 missed
      """

    let snapshot = MutationReportParser.parse(
      output: output, exitCode: 1, command: "cargo mutants --no-shuffle -j 1")

    #expect(snapshot.caught == 1)
    #expect(snapshot.missed == 1)
    #expect(snapshot.timeout == 0)
    #expect(snapshot.mutationScorePercent == 50)
    #expect(snapshot.missedMutants.count == 1)
    #expect(snapshot.missedMutants[0].contains("is_empty"))
  }

  @Test
  func parsesTimeoutsAndUnviable() {
    let output = "5 mutants tested in 12s: 3 caught, 1 missed, 1 timeout, 2 unviable"

    let snapshot = MutationReportParser.parse(
      output: output, exitCode: 1, command: "cargo mutants")

    #expect(snapshot.caught == 3)
    #expect(snapshot.missed == 1)
    #expect(snapshot.timeout == 1)
    #expect(snapshot.unviable == 2)
    #expect(snapshot.tested == 5)
    #expect(snapshot.mutationScorePercent == 60)
  }

  @Test
  func parsesRealCargoMutantsPrefixedOutput() {
    let output = """
      MISSED   crates/cli/src/main.rs:214:42: replace - with / in today in 0s build + 0s test
      MISSED   crates/cli/src/main.rs:214:32: replace + with - in today in 0s build + 0s test
      CAUGHT   crates/core/src/lib.rs:18:5: replace is_empty -> bool with true in 1.0s build + 0.2s test
      NOT CAUGHT   crates/core/src/lib.rs:44:20: replace match guard !p.is_empty() with true in load in 0s build + 0s test
      148 mutants tested in 42s: 72 caught, 76 missed
      """

    let snapshot = MutationReportParser.parse(
      output: output, exitCode: 3, command: "cargo mutants --no-shuffle -j 1")

    #expect(snapshot.caught == 72)
    #expect(snapshot.missed == 76)
    #expect(snapshot.missedMutants.count == 3)
    #expect(snapshot.missedMutants[0] == "crates/cli/src/main.rs:214:42: replace - with / in today")
    #expect(
      snapshot.missedMutants[2]
        == "crates/core/src/lib.rs:44:20: replace match guard !p.is_empty() with true in load")
  }

  @Test
  func emptyOutputYieldsNoScore() {
    let snapshot = MutationReportParser.parse(
      output: "error: could not compile", exitCode: 2, command: "cargo mutants")

    #expect(snapshot.tested == 0)
    #expect(snapshot.mutationScorePercent == nil)
    #expect(snapshot.missedMutants.isEmpty)
  }

  @Test
  func scopesCommandToChangedRustSources() {
    let command = GeneratedProjectQuality.mutationTestCommand(
      forChangedFiles: [
        "crates/core/src/lib.rs",
        "crates/core/tests/lib.rs",
        "README.md",
        "crates/cli/src/main.rs",
      ])

    #expect(command.contains("-f 'crates/core/src/lib.rs'"))
    #expect(command.contains("-f 'crates/cli/src/main.rs'"))
    #expect(!command.contains("tests/lib.rs"))
    #expect(!command.contains("README.md"))
    #expect(command.hasPrefix(GeneratedProjectQuality.mutationTestCommand))
  }

  @Test
  func formattedPromptExcludesGreetingScaffoldSurvivors() {
    let snapshot = MutationSnapshot(
      collectedAt: Date(),
      sessionNumber: 1,
      command: "cargo mutants",
      exitCode: 1,
      caught: 2,
      missed: 2,
      timeout: 0,
      unviable: 0,
      missedMutants: [
        "crates/core/src/lib.rs:10: replace GreetingError::Display with empty",
        "crates/core/src/store.rs:40: replace absorb guard with true",
      ],
      rawSummary: nil
    )
    let prompt = snapshot.formattedForPrompt()
    #expect(prompt.contains("absorb guard"))
    #expect(!prompt.contains("GreetingError"))
    #expect(prompt.contains("excluding 1 greeting-scaffold"))
    #expect(MutationSnapshot.isGreetingScaffoldMutant("personalized_greeting Display"))
  }

  @Test
  func fallsBackToFullRunWithoutRustSources() {
    let command = GeneratedProjectQuality.mutationTestCommand(forChangedFiles: ["README.md"])
    #expect(command == GeneratedProjectQuality.mutationTestCommand)
  }

  @Test
  func snapshotStoreRoundTrips() throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "mutation-store-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let workspace = CompassWorkspace(repoURL: directory)
    try FileManager.default.createDirectory(
      at: workspace.compassURL, withIntermediateDirectories: true)

    var snapshot = MutationReportParser.parse(
      output: "3 mutants tested in 2s: 3 caught", exitCode: 0, command: "cargo mutants")
    snapshot.collectedAt = Date(timeIntervalSince1970: 1_700_000_000)
    snapshot.sessionNumber = 7
    try MutationSnapshotStore.writeMutationSnapshot(snapshot, workspace: workspace)

    let loaded = MutationSnapshotStore.readMutationSnapshot(from: workspace)
    #expect(loaded == snapshot)
  }
}

@Suite("AcceptanceGates")
struct AcceptanceGatesTests {
  private func coverage(_ percent: Double?) -> CoverageSnapshot {
    CoverageSnapshot(
      collectedAt: Date(),
      sessionNumber: nil,
      overallLineCoveragePercent: percent,
      files: [],
      rawSummary: nil
    )
  }

  private func mutation(caught: Int, missed: Int) -> MutationSnapshot {
    MutationSnapshot(
      collectedAt: Date(),
      sessionNumber: nil,
      command: "cargo mutants",
      exitCode: missed > 0 ? 1 : 0,
      caught: caught,
      missed: missed,
      timeout: 0,
      unviable: 0,
      missedMutants: [],
      rawSummary: nil
    )
  }

  @Test
  func noGatesMeansNoViolations() {
    let gates = AcceptanceGates()
    #expect(gates.isEmpty)
    #expect(gates.violations(coverage: nil, mutation: nil).isEmpty)
  }

  @Test
  func missingEvidenceViolatesConfiguredGate() {
    let gates = AcceptanceGates(minLineCoveragePercent: 80)
    let violations = gates.violations(coverage: nil, mutation: nil)
    #expect(violations.count == 1)
    #expect(violations[0].contains("no coverage snapshot"))
  }

  @Test
  func belowThresholdViolates() {
    let gates = AcceptanceGates(minLineCoveragePercent: 80, minMutationScorePercent: 90)
    let violations = gates.violations(
      coverage: coverage(72.5), mutation: mutation(caught: 4, missed: 1))
    #expect(violations.count == 2)
    #expect(violations[0].contains("72.5%"))
    #expect(violations[1].contains("80.0%"))
  }

  @Test
  func passingEvidenceYieldsNoViolations() {
    let gates = AcceptanceGates(
      minLineCoveragePercent: 80, minMutationScorePercent: 75, maxMissedMutants: 1)
    let violations = gates.violations(
      coverage: coverage(95), mutation: mutation(caught: 9, missed: 1))
    #expect(violations.isEmpty)
  }

  @Test
  func environmentDefaultsParse() {
    let gates = AcceptanceGates.defaultFromEnvironment([
      "COMPASS_GATE_MIN_COVERAGE": "85",
      "COMPASS_GATE_MIN_MUTATION_SCORE": "70.5",
      "COMPASS_GATE_MAX_MISSED_MUTANTS": "0",
    ])
    #expect(gates?.minLineCoveragePercent == 85)
    #expect(gates?.minMutationScorePercent == 70.5)
    #expect(gates?.maxMissedMutants == 0)
    #expect(AcceptanceGates.defaultFromEnvironment([:]) == nil)
  }

  @Test
  func planStateRoundTripsGates() throws {
    var state = PlanState.empty
    state.acceptanceGates = AcceptanceGates(minMutationScorePercent: 80)

    let encoder = JSONEncoder()
    let data = try encoder.encode(state)
    let decoded = try JSONDecoder().decode(PlanState.self, from: data)

    #expect(decoded.acceptanceGates == state.acceptanceGates)
  }

  @Test
  func planStateDecodesWithoutGates() throws {
    let payload = """
      {"schemaVersion":1,"completed":[],"queue":[],"brief":{"summary":"x","targetUsers":[],"desiredOutcomes":[],"constraints":[],"acceptanceSignals":[]},"openQuestions":[]}
      """
    let decoded = try JSONDecoder().decode(PlanState.self, from: Data(payload.utf8))
    #expect(decoded.acceptanceGates == nil)
  }

  @Test
  func applyingProposalPreservesGates() {
    var state = PlanState.empty
    state.acceptanceGates = AcceptanceGates(maxMissedMutants: 2)

    let proposal = PlanProposal(
      immediate: nil, queue: [], brief: .empty, openQuestions: [])
    let applied = proposal.applying(to: state)

    #expect(applied.acceptanceGates == state.acceptanceGates)
  }
}
