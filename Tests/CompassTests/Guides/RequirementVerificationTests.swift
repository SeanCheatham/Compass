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
          status: .unsatisfied,
          lastAudit: RequirementAuditRecord(
            verdict: .unsatisfied,
            evidence: ["missing CLI flag"],
            commit: "abc123",
            timestamp: 1_700_000_000_000
          )
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
  }
}

@Suite("RequirementAuditEvaluator")
struct RequirementAuditEvaluatorTests {
  @Test
  func criterionFailureOverridesSatisfiedVerdict() {
    let ledger = RequirementLedger(
      entries: [RequirementLedgerEntry(requirementID: "req-1", criteria: ["false"])]
    )
    let agent = RequirementsAuditResult(
      results: [
        RequirementAuditItemResult(
          requirementID: "req-1",
          verdict: .satisfied,
          evidence: ["looks good"],
          proposedCriteria: ["cargo test -p core"]
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
      commit: "deadbeef"
    )

    #expect(next.entry(for: "req-1")?.status == .unsatisfied)
    #expect(next.entry(for: "req-1")?.criteria.contains("cargo test -p core") == true)
    #expect(
      next.entry(for: "req-1")?.lastAudit?.evidence.contains(where: {
        $0.contains("Criterion failed")
      }) == true
    )
  }

  @Test
  func criterionPassKeepsSatisfied() {
    let ledger = RequirementLedger(
      entries: [RequirementLedgerEntry(requirementID: "req-1", criteria: ["true"])]
    )
    let agent = RequirementsAuditResult(
      results: [
        RequirementAuditItemResult(
          requirementID: "req-1",
          verdict: .satisfied,
          evidence: ["behavior present"]
        )
      ],
      summary: "done"
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
      into: ledger
    )
    #expect(next.entry(for: "req-1")?.status == .satisfied)
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
      productRequirements: [ProductRequirement(id: "r1", text: "Ship checklist")]
    )
    let ledger = RequirementLedger(
      entries: [
        RequirementLedgerEntry(requirementID: "r1", criteria: ["cargo test -p core"])
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
  }
}
