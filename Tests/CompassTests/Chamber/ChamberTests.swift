import CompassCore
import Foundation
import Testing

@Suite("Chamber")
struct ChamberTests {
  @Test("normalizeGeneratedTestFileName forces prefix and .rs")
  func normalizeName() {
    #expect(ChamberPaths.normalizeGeneratedTestFileName("foo") == "compass_gen_foo.rs")
    #expect(ChamberPaths.normalizeGeneratedTestFileName("compass_gen_bar.rs") == "compass_gen_bar.rs")
    #expect(ChamberPaths.isGeneratedTestFileName("compass_gen_x.rs"))
    #expect(!ChamberPaths.isGeneratedTestFileName("lib.rs"))
  }

  @Test("FP guard demotes invented numeric assert without docs")
  func fpGuard() {
    let finding = ChamberFinding(
      kind: .failingGeneratedTest,
      title: "weird",
      description: "assert_eq!(bump(1), 1) failed",
      confidence: 0.8,
      triage: ChamberTriageResult(isRealBug: true, rationale: "I guessed"),
      evidence: "assert_eq!(bump(1), 99)"
    )
    let guarded = ChamberFPGuards.apply(to: [finding])
    #expect(guarded.first?.triage?.isRealBug == false)
  }

  @Test("eval scores recall and control false positives")
  func evalScore() throws {
    let bugsTOML = """
      [[bugs]]
      id = "bump_identity"
      function = "bump"
      control = false
      match = ["bump"]

      [[bugs]]
      id = "clamp_control"
      function = "clamp"
      control = true
      match = ["clamp"]
      """
    let bugs = ChamberEval.parseBugsTOML(bugsTOML)
    #expect(bugs.count == 2)

    let hit = ChamberSnapshot(
      findings: [
        ChamberFinding(
          kind: .failingGeneratedTest,
          title: "bump wrong",
          description: "bump should be identity",
          testPath: "tests/compass_gen_bump.rs",
          confidence: 0.9,
          triage: ChamberTriageResult(isRealBug: true, rationale: "documented identity"),
          evidence: "bump failed"
        ),
        ChamberFinding(
          kind: .failingGeneratedTest,
          title: "clamp false positive",
          description: "clamp",
          confidence: 0.5,
          triage: ChamberTriageResult(isRealBug: true, rationale: "wrong"),
          evidence: "clamp"
        ),
      ]
    )
    let score = ChamberEval.score(bugs: bugs, snapshot: hit)
    #expect(score.hits == ["bump_identity"])
    #expect(score.missed.isEmpty)
    #expect(score.controlFalsePositives == 1)
    #expect(score.recall == 1.0)
  }

  @Test("PlanState defaults projectKind to factory and round-trips chamber")
  func planStateKind() throws {
    let empty = PlanState.empty
    #expect(empty.projectKind == .factory)

    var state = PlanState.empty
    state.projectKind = .chamber
    state.chamberBudget = .chamberLoopDefault
    let data = try JSONEncoder().encode(state)
    let decoded = try JSONDecoder().decode(PlanState.self, from: data)
    #expect(decoded.projectKind == .chamber)
    #expect(decoded.chamberBudget?.maxIterations == ChamberBudget.chamberLoopDefault.maxIterations)

    let legacy = Data(#"{"schemaVersion":1,"completed":[],"queue":[],"brief":{"summary":"","targetUsers":[],"desiredOutcomes":[],"constraints":[],"acceptanceSignals":[]},"openQuestions":[],"products":["cli"],"successfulShipCount":0}"#.utf8)
    let fromLegacy = try JSONDecoder().decode(PlanState.self, from: legacy)
    #expect(fromLegacy.projectKind == .factory)
  }

  @Test("chamber snapshot formats Plan pressure")
  func snapshotPrompt() {
    let snap = ChamberSnapshot(
      findings: [
        ChamberFinding(
          kind: .failingGeneratedTest,
          title: "real bug",
          description: "contract broken",
          triage: ChamberTriageResult(isRealBug: true, rationale: "docs"),
          evidence: "fail"
        ),
        ChamberFinding(
          kind: .survivingMutant,
          title: "mutant X",
          description: "unkilled",
          triage: ChamberTriageResult(isRealBug: false, rationale: "coverage gap")
        ),
      ]
    )
    let text = snap.formattedForPrompt()
    #expect(text.contains("Confirmed bugs"))
    #expect(text.contains("real bug"))
    #expect(text.contains("Surviving mutants"))
  }

  @Test("CLI parses chamber run and eval")
  func cliChamber() throws {
    let run = try CompassCLICommand.parse([
      "chamber", "run", "--repo", "/tmp/repo", "--recon-only", "--format", "text",
    ])
    if case .chamberRun(let repo, _, _, let skipHunt, let format) = run {
      #expect(repo.path == "/tmp/repo")
      #expect(skipHunt)
      #expect(format == .text)
    } else {
      Issue.record("Expected chamberRun")
    }

    let eval = try CompassCLICommand.parse([
      "chamber", "eval", "--repo", "/tmp/repo", "--bugs", "/tmp/bugs.toml",
    ])
    if case .chamberEval(let repo, let bugs, _) = eval {
      #expect(repo.path == "/tmp/repo")
      #expect(bugs.path == "/tmp/bugs.toml")
    } else {
      Issue.record("Expected chamberEval")
    }
  }
}
