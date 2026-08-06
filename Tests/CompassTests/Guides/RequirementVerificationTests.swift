import Foundation
import Testing

@testable import CompassCore

@Suite("RequirementLedger")
struct RequirementLedgerTests {
  @Test
  func encodeDecodeRoundTrip() throws {
    let ledger = RequirementLedger(
      entries: [
        RequirementLedgerEntry(
          requirementID: "req-1",
          criteria: ["cargo test -p core"],
          scenarios: [
            RequirementScenario(
              given: "built CLI",
              whenAction: "run --help",
              thenExpectations: ["exit 0"],
              command: "cargo run -p cli -- --help"
            )
          ],
          ownedPaths: ["crates/cli/src"],
          status: .unsatisfied,
          lastAudit: RequirementAuditRecord(
            verdict: .unsatisfied,
            evidence: ["missing CLI flag"],
            commit: "abc123",
            timestamp: 1_700_000_000_000
          ),
          shipTraces: [
            RequirementShipTrace(
              session: 3,
              commit: "abc123",
              verify: "cargo test --workspace",
              planSummary: "## Outcome\nShip help"
            )
          ]
        )
      ]
    )

    let data = try JSONEncoder().encode(ledger)
    let decoded = try JSONDecoder().decode(RequirementLedger.self, from: data)
    #expect(decoded == ledger)
  }

  @Test
  func reconcilesAgainstBrief() {
    let brief = ProjectBrief(
      audience: "Users",
      problem: "Need checklist",
      productRequirements: [
        ProductRequirement(id: "keep", text: "Keep me"),
        ProductRequirement(id: "new", text: "Add me"),
      ]
    )
    let ledger = RequirementLedger(
      entries: [
        RequirementLedgerEntry(
          requirementID: "keep",
          criteria: ["true"],
          status: .satisfied
        ),
        RequirementLedgerEntry(
          requirementID: "stale",
          status: .unsatisfied
        ),
      ]
    )

    let reconciled = ledger.reconciled(with: brief)
    #expect(reconciled.entries.map(\.requirementID) == ["keep", "new"])
    #expect(reconciled.entry(for: "keep")?.status == .satisfied)
    #expect(reconciled.entry(for: "new")?.status == .unverified)
    #expect(reconciled.entry(for: "stale") == nil)
  }

  @Test
  func recordingShipAppendsTrace() {
    let ledger = RequirementLedger(
      entries: [RequirementLedgerEntry(requirementID: "req-1", status: .unverified)]
    )
    let next = ledger.recordingShip(
      requirementIDs: ["req-1"],
      session: 7,
      commit: "deadbeef",
      verify: "cargo test --workspace",
      planSummary: "Ship feature"
    )
    #expect(next.entry(for: "req-1")?.shipTraces.count == 1)
    #expect(next.entry(for: "req-1")?.shipTraces.first?.session == 7)
    #expect(next.entry(for: "req-1")?.shipTraces.first?.commit == "deadbeef")
  }

  @Test
  func markingStaleWhenOwnedPathsChange() {
    let ledger = RequirementLedger(
      entries: [
        RequirementLedgerEntry(
          requirementID: "req-a",
          ownedPaths: ["crates/cli/src"],
          status: .satisfied
        ),
        RequirementLedgerEntry(
          requirementID: "req-b",
          ownedPaths: ["crates/core/src"],
          status: .satisfied
        ),
      ]
    )
    let next = ledger.markingStale(
      changedPaths: ["crates/cli/src/main.rs"],
      excludingRequirementIDs: ["req-a"]
    )
    #expect(next.entry(for: "req-a")?.status == .satisfied)
    #expect(next.entry(for: "req-b")?.status == .satisfied)

    let stale = ledger.markingStale(changedPaths: ["crates/cli/src/main.rs"])
    #expect(stale.entry(for: "req-a")?.status == .stale)
    #expect(stale.entry(for: "req-b")?.status == .satisfied)
  }

  @Test
  func executableCommandsMergeCriteriaAndScenarios() {
    let entry = RequirementLedgerEntry(
      requirementID: "r1",
      criteria: ["true"],
      scenarios: [
        RequirementScenario(command: "cargo test -p core"),
        RequirementScenario(command: "true"),
      ]
    )
    #expect(entry.executableCommands == ["true", "cargo test -p core"])
  }

  @Test
  func renderedStatusIncludesVerdict() {
    let brief = ProjectBrief.problemFocused("Ship it")
    let id = brief.productRequirements[0].id
    let ledger = RequirementLedger(
      entries: [
        RequirementLedgerEntry(
          requirementID: id,
          status: .satisfied,
          lastAudit: RequirementAuditRecord(
            verdict: .satisfied,
            evidence: ["cargo test passed"]
          )
        )
      ]
    )
    let markdown = ledger.renderedStatusMarkdown(brief: brief)
    #expect(markdown.contains("[satisfied]"))
    #expect(markdown.contains(id))
    #expect(markdown.contains("cargo test passed"))
    #expect(markdown.contains("behavior/hybrid"))
  }
}

@Suite("RequirementAuditEvaluator")
struct RequirementAuditEvaluatorTests {
  @Test
  func criterionFailureOverridesSatisfiedVerdictForHybrid() {
    let brief = ProjectBrief(
      audience: "a",
      problem: "p",
      productRequirements: [
        ProductRequirement(id: "req-1", text: "x", kind: .behavior, proofLevel: .hybrid)
      ]
    )
    let ledger = RequirementLedger(
      entries: [RequirementLedgerEntry(requirementID: "req-1", criteria: ["false"])]
    )
    let agent = RequirementsAuditResult(
      results: [
        RequirementAuditItemResult(
          requirementID: "req-1",
          verdict: .satisfied,
          evidence: ["looks good"],
          proposedCriteria: ["cargo test -p core"],
          proposedOwnedPaths: ["crates/core/src"]
        )
      ],
      summary: "ok"
    )
    let criterionResults = [
      RequirementCriterionResult(
        requirementID: "req-1",
        command: "false",
        exitCode: 1,
        output: "failed"
      )
    ]

    let next = RequirementAuditEvaluator.apply(
      agentResult: agent,
      criterionResults: criterionResults,
      into: ledger,
      brief: brief,
      commit: "deadbeef"
    )

    #expect(next.entry(for: "req-1")?.status == .unsatisfied)
    #expect(next.entry(for: "req-1")?.criteria.contains("cargo test -p core") == true)
    #expect(next.entry(for: "req-1")?.ownedPaths.contains("crates/core/src") == true)
    #expect(
      next.entry(for: "req-1")?.lastAudit?.evidence.contains(where: {
        $0.contains("Criterion failed")
      }) == true
    )
  }

  @Test
  func deterministicForcesSatisfiedWhenCriteriaPass() {
    let brief = ProjectBrief(
      audience: "a",
      problem: "p",
      productRequirements: [
        ProductRequirement(
          id: "req-1", text: "x", kind: .constraint, proofLevel: .deterministic)
      ]
    )
    let ledger = RequirementLedger(
      entries: [RequirementLedgerEntry(requirementID: "req-1", criteria: ["true"])]
    )
    let agent = RequirementsAuditResult(
      results: [
        RequirementAuditItemResult(
          requirementID: "req-1",
          verdict: .unsatisfied,
          evidence: ["agent unsure"]
        )
      ],
      summary: "unsure"
    )
    let next = RequirementAuditEvaluator.apply(
      agentResult: agent,
      criterionResults: [
        RequirementCriterionResult(
          requirementID: "req-1",
          command: "true",
          exitCode: 0,
          output: "ok"
        )
      ],
      into: ledger,
      brief: brief
    )
    #expect(next.entry(for: "req-1")?.status == .satisfied)
    #expect(next.entry(for: "req-1")?.satisfiedCommit != nil || next.entry(for: "req-1")?.satisfiedAt != nil)
  }

  @Test
  func judgmentIgnoresFailedCriteriaHardOverride() {
    let brief = ProjectBrief(
      audience: "a",
      problem: "p",
      productRequirements: [
        ProductRequirement(id: "req-1", text: "feels calm", kind: .narrative, proofLevel: .judgment)
      ]
    )
    let ledger = RequirementLedger(
      entries: [RequirementLedgerEntry(requirementID: "req-1")]
    )
    let agent = RequirementsAuditResult(
      results: [
        RequirementAuditItemResult(
          requirementID: "req-1",
          verdict: .satisfied,
          evidence: ["copy reads calm"]
        )
      ],
      summary: "ok"
    )
    let next = RequirementAuditEvaluator.apply(
      agentResult: agent,
      criterionResults: [
        RequirementCriterionResult(
          requirementID: "req-1",
          command: "false",
          exitCode: 1,
          output: "n/a"
        )
      ],
      into: ledger,
      brief: brief
    )
    #expect(next.entry(for: "req-1")?.status == .satisfied)
  }
}

@Suite("RequirementTargetingValidator")
struct RequirementTargetingValidatorTests {
  @Test
  func requiresTargetingWhenIncomplete() {
    let brief = ProjectBrief.problemFocused("Need work")
    let id = brief.productRequirements[0].id
    let ledger = RequirementLedger(
      entries: [RequirementLedgerEntry(requirementID: id, status: .unverified)]
    )
    let immediate = PlanNext(plan: "## Outcome\nX\n\n## Acceptance checks\n- y", verify: "true")
    #expect(throws: PlanTransitionValidationError.self) {
      try RequirementTargetingValidator.validate(
        immediate: immediate,
        brief: brief,
        ledger: ledger
      )
    }
  }

  @Test
  func acceptsValidTargeting() throws {
    let brief = ProjectBrief.problemFocused("Need work")
    let id = brief.productRequirements[0].id
    let ledger = RequirementLedger(
      entries: [RequirementLedgerEntry(requirementID: id, status: .unsatisfied)]
    )
    let immediate = PlanNext(
      plan: "## Outcome\nX\n\n## Acceptance checks\n- y",
      verify: "true",
      targetedRequirementIDs: [id]
    )
    try RequirementTargetingValidator.validate(
      immediate: immediate,
      brief: brief,
      ledger: ledger
    )
  }

  @Test
  func allowsEmptyTargetingWhenAllSatisfied() throws {
    let brief = ProjectBrief.problemFocused("Done")
    let id = brief.productRequirements[0].id
    let ledger = RequirementLedger(
      entries: [RequirementLedgerEntry(requirementID: id, status: .satisfied)]
    )
    let immediate = PlanNext(plan: "## Outcome\nX\n\n## Acceptance checks\n- y", verify: "true")
    try RequirementTargetingValidator.validate(
      immediate: immediate,
      brief: brief,
      ledger: ledger
    )
  }
}

@Suite("RequirementsLoopCompletion")
struct RequirementsLoopCompletionTests {
  @Test
  func completeWhenNoRequirements() {
    let decision = RequirementsLoopCompletion.decide(
      brief: .empty,
      ledger: .empty,
      alreadyReplannedAfterUnsatisfiedAudit: false
    )
    #expect(decision == .complete)
  }

  @Test
  func completeWhenAllSatisfied() {
    let brief = ProjectBrief.problemFocused("Done")
    let id = brief.productRequirements[0].id
    let ledger = RequirementLedger(
      entries: [RequirementLedgerEntry(requirementID: id, status: .satisfied)]
    )
    let decision = RequirementsLoopCompletion.decide(
      brief: brief,
      ledger: ledger,
      alreadyReplannedAfterUnsatisfiedAudit: false
    )
    #expect(decision == .complete)
  }

  @Test
  func staleIsIncomplete() {
    let brief = ProjectBrief.problemFocused("Need revalidation")
    let id = brief.productRequirements[0].id
    let ledger = RequirementLedger(
      entries: [RequirementLedgerEntry(requirementID: id, status: .stale)]
    )
    let decision = RequirementsLoopCompletion.decide(
      brief: brief,
      ledger: ledger,
      alreadyReplannedAfterUnsatisfiedAudit: false
    )
    guard case .replan = decision else {
      Issue.record("expected replan for stale")
      return
    }
  }

  @Test
  func replanWhenUnsatisfied() {
    let brief = ProjectBrief.problemFocused("Need work")
    let id = brief.productRequirements[0].id
    let ledger = RequirementLedger(
      entries: [
        RequirementLedgerEntry(
          requirementID: id,
          status: .unsatisfied,
          lastAudit: RequirementAuditRecord(
            verdict: .unsatisfied,
            evidence: ["missing feature"]
          )
        )
      ]
    )
    let decision = RequirementsLoopCompletion.decide(
      brief: brief,
      ledger: ledger,
      alreadyReplannedAfterUnsatisfiedAudit: false
    )
    guard case .replan(let draft) = decision else {
      Issue.record("expected replan")
      return
    }
    #expect(draft.contains("unsatisfied"))
    #expect(draft.contains(id))
  }

  @Test
  func stopUnverifiedAfterReplan() {
    let brief = ProjectBrief.problemFocused("Need work")
    let id = brief.productRequirements[0].id
    let ledger = RequirementLedger(
      entries: [RequirementLedgerEntry(requirementID: id, status: .unverified)]
    )
    let decision = RequirementsLoopCompletion.decide(
      brief: brief,
      ledger: ledger,
      alreadyReplannedAfterUnsatisfiedAudit: true
    )
    guard case .stopUnverified = decision else {
      Issue.record("expected stopUnverified")
      return
    }
  }
}

@Suite("RequirementsAuditPrompt")
struct RequirementsAuditPromptTests {
  @Test
  func promptIncludesScopedRequirementsAndCriteria() {
    let brief = ProjectBrief(
      audience: "Ops",
      problem: "Need audit",
      productRequirements: [
        ProductRequirement(id: "r1", text: "Ship checklist", kind: .behavior)
      ]
    )
    let ledger = RequirementLedger(
      entries: [
        RequirementLedgerEntry(
          requirementID: "r1",
          criteria: ["cargo test -p core"],
          scenarios: [
            RequirementScenario(
              given: "tests exist",
              whenAction: "cargo test -p core",
              thenExpectations: ["exit 0"],
              command: "cargo test -p core"
            )
          ],
          ownedPaths: ["crates/core/src"]
        )
      ]
    )
    let prompt = Prompts.requirementsAuditPrompt(
      brief: brief,
      ledger: ledger,
      requirementIDs: ["r1"],
      criterionResults: [
        RequirementCriterionResult(
          requirementID: "r1",
          command: "cargo test -p core",
          exitCode: 0,
          output: "ok"
        )
      ],
      promptMode: .envelope
    )
    #expect(prompt.contains("requirements_audit_submit"))
    #expect(prompt.contains("r1"))
    #expect(prompt.contains("Ship checklist"))
    #expect(prompt.contains("cargo test -p core"))
    #expect(prompt.contains("Host-run criterion results"))
    #expect(prompt.contains("proposedScenarios"))
    #expect(prompt.contains("behavior/hybrid"))
  }
}

@Suite("ProductRequirementTaxonomy")
struct ProductRequirementTaxonomyTests {
  @Test
  func encodeDecodePreservesKindAndProof() throws {
    let requirement = ProductRequirement(
      id: "r1",
      text: "CLI lists posts",
      kind: .behavior,
      proofLevel: .deterministic
    )
    let data = try JSONEncoder().encode(requirement)
    let decoded = try JSONDecoder().decode(ProductRequirement.self, from: data)
    #expect(decoded == requirement)
  }

  @Test
  func defaultsProofFromKind() {
    #expect(
      ProductRequirement(text: "x", kind: .narrative).proofLevel == .judgment
    )
    #expect(
      ProductRequirement(text: "x", kind: .constraint).proofLevel == .deterministic
    )
  }
}
