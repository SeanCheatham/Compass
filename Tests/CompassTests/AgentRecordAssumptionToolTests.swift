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

  @Test func testToolRegistryExposesAssumptionsToEveryPhase() throws {
    for phase in AgentPhase.allCases {
      let names = Set(ToolRegistry.tools(for: phase).map { $0.spec.name })
      try #require(names.contains(AgentRecordAssumptionTool.toolName))
    }
  }
}
