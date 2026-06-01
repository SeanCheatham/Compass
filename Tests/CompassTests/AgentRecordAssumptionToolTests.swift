import Foundation
import Testing

@testable import Compass

struct AgentRecordAssumptionToolTests {
  @Test func testRecordAssumptionWritesHostLedger() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let assumptionsURL = root.appending(path: "assumptions.json")
    let tool = AgentRecordAssumptionTool()
    let context = AgentToolContext(
      workingDirectory: root,
      assumptionsURL: assumptionsURL,
      phase: .plan,
      sessionNumber: 7
    )

    let result = try await tool.invoke(
      arguments: Data(
        """
        {
          "text": "The user wants a native macOS implementation.",
          "rationale": "The project vision calls Compass macOS-native.",
          "impact": "Plan should prefer SwiftUI and AppKit surfaces.",
          "evidence": ["COMPASS.md"],
          "invalidation": "User asks for a web app.",
          "scope": "project"
        }
        """.utf8),
      context: context
    )

    try #require(!result.isError)
    let ledger = try AssumptionLedgerStore(url: assumptionsURL).read()
    let record = try #require(ledger.assumptions.first)
    try #require(record.text == "The user wants a native macOS implementation.")
    try #require(record.createdByPhase == AgentPhase.plan.rawValue)
    try #require(record.createdInSession == 7)
  }

  @Test func testRecordAssumptionAcceptsCompatibilityArguments() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let assumptionsURL = root.appending(path: "assumptions.json")
    let tool = AgentRecordAssumptionTool()

    let result = try await tool.invoke(
      arguments: Data(
        """
        {
          "assumption": "The next slice should finish the apply workflow.",
          "rationale": "The active plan focuses on end-to-end apply.",
          "impact": "Plan should wire patch application instead of adding more coverage.",
          "evidence": "state.json immediate item",
          "scope": "Feature"
        }
        """.utf8),
      context: AgentToolContext(
        workingDirectory: root,
        assumptionsURL: assumptionsURL,
        phase: .plan,
        sessionNumber: 8
      )
    )

    try #require(!result.isError)
    let record = try #require(try AssumptionLedgerStore(url: assumptionsURL).read().assumptions.first)
    try #require(record.text == "The next slice should finish the apply workflow.")
    try #require(record.evidence == ["state.json immediate item"])
    try #require(record.scope == .feature)
  }

  @Test func testRecordAssumptionRejectsMissingRequiredDetails() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let assumptionsURL = root.appending(path: "assumptions.json")
    let tool = AgentRecordAssumptionTool()

    let result = try await tool.invoke(
      arguments: Data(
        """
        {
          "text": "The project targets macOS only.",
          "rationale": "Package.swift declares only macOS."
        }
        """.utf8),
      context: AgentToolContext(
        workingDirectory: root,
        assumptionsURL: assumptionsURL,
        phase: .plan,
        sessionNumber: 9
      )
    )

    try #require(result.isError)
    try #require(result.errorKind == .invalidArguments)
    try #require(result.content.contains("Assumption impact cannot be empty"))
    try #require(try AssumptionLedgerStore(url: assumptionsURL).read().assumptions.isEmpty)
  }

  @Test func testRecordAssumptionPreservesDeniedReview() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let assumptionsURL = root.appending(path: "assumptions.json")
    let store = AssumptionLedgerStore(url: assumptionsURL)
    let draft = AssumptionDraft(
      text: "The user wants all generated files committed.",
      rationale: "Past runs landed everything.",
      evidence: ["session history"],
      impact: "Develop might include generated artifacts.",
      invalidation: "User asks to exclude generated files.",
      scope: .project
    )
    let existing = try store.record(draft: draft, phase: .plan, sessionNumber: 1)
    _ = try store.review(
      id: existing.id,
      status: .denied,
      comment: "Generated files should stay untracked."
    )

    let tool = AgentRecordAssumptionTool()
    let result = try await tool.invoke(
      arguments: try JSONEncoder().encode(draft),
      context: AgentToolContext(
        workingDirectory: root,
        assumptionsURL: assumptionsURL,
        phase: .develop,
        sessionNumber: 2
      )
    )

    try #require(!result.isError)
    try #require(result.content.contains("currently denied"))
    let record = try #require(try store.read().assumptions.first)
    try #require(record.status == .denied)
    try #require(record.userComment == "Generated files should stay untracked.")
  }

  @Test func testRemoveAssumptionSupersedesHostLedger() async throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let assumptionsURL = root.appending(path: "assumptions.json")
    let store = AssumptionLedgerStore(url: assumptionsURL)
    let existing = try store.record(
      draft: AssumptionDraft(
        text: "The app only needs coverage work.",
        rationale: "Recent sessions focused on coverage.",
        evidence: ["sessions.jsonl"],
        impact: "Planning would keep selecting tests.",
        invalidation: "The roadmap points to a feature slice.",
        scope: .feature
      ),
      phase: .plan,
      sessionNumber: 3
    )

    let result = try await AgentRemoveAssumptionTool().invoke(
      arguments: Data(
        """
        {
          "id": "\(existing.id)",
          "reason": "The current roadmap item supersedes the coverage focus."
        }
        """.utf8),
      context: AgentToolContext(
        workingDirectory: root,
        assumptionsURL: assumptionsURL,
        phase: .plan,
        sessionNumber: 4
      )
    )

    try #require(!result.isError)
    let record = try #require(try store.read().assumptions.first)
    try #require(record.status == .superseded)
    try #require(record.userComment == "The current roadmap item supersedes the coverage focus.")
    try #require(try store.read().formattedForPrompt().isEmpty)
  }

  @Test func testToolRegistryExposesAssumptionsToEveryPhase() throws {
    for phase in AgentPhase.allCases {
      let names = Set(ToolRegistry.tools(for: phase).map { $0.spec.name })
      try #require(names.contains(AgentRecordAssumptionTool.toolName))
      try #require(names.contains(AgentRemoveAssumptionTool.toolName))
    }
  }
}
