import Foundation
import Testing

@testable import CompassCore

@Suite("AgentAssumptionTools")
struct AgentAssumptionToolTests {
  @Test
  func recordAndRemoveRoundTrip() async throws {
    let tempURL = try makeAssumptionTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    let ledgerURL = tempURL.appending(path: "assumptions.json")
    let context = AgentToolContext(
      workingDirectory: tempURL,
      assumptionsURL: ledgerURL,
      phase: .plan,
      sessionNumber: 4
    )

    let recordResult = try await AgentRecordAssumptionTool().invoke(
      arguments: Data(
        #"""
        {
          "text": "Users prefer host-native runs by default",
          "rationale": "Settings default to host preference",
          "impact": "Plan should not require VM unless asked",
          "evidence": ["settings.json defaults"],
          "scope": "project"
        }
        """#.utf8
      ),
      context: context
    )
    #expect(!recordResult.isError)
    #expect(recordResult.content.contains("Recorded assumption"))
    #expect(recordResult.content.contains("implicit"))

    let ledger = try AssumptionLedgerStore(url: ledgerURL).read()
    #expect(ledger.assumptions.count == 1)
    let id = try #require(ledger.assumptions.first?.id)

    let removeResult = try await AgentRemoveAssumptionTool().invoke(
      arguments: Data(
        #"{"id":"\#(id)","reason":"User clarified VM is preferred"}"#.utf8
      ),
      context: context
    )
    #expect(!removeResult.isError)
    #expect(removeResult.content.contains("Removed assumption \(id)"))

    let afterRemove = try AssumptionLedgerStore(url: ledgerURL).read()
    #expect(afterRemove.assumptions.first?.status == .superseded)
  }

  @Test
  func missingLedgerIsIoFailure() async throws {
    let tempURL = try makeAssumptionTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let result = try await AgentRecordAssumptionTool().invoke(
      arguments: Data(
        #"""
        {
          "text": "Something",
          "rationale": "Because",
          "impact": "Affects plan"
        }
        """#.utf8
      ),
      context: AgentToolContext(workingDirectory: tempURL)
    )

    #expect(result.isError)
    #expect(result.errorKind == .ioFailure)
    #expect(result.content.contains("Assumption ledger is unavailable"))
  }

  @Test
  func emptyRationaleIsInvalidArguments() async throws {
    let tempURL = try makeAssumptionTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    let ledgerURL = tempURL.appending(path: "assumptions.json")

    let result = try await AgentRecordAssumptionTool().invoke(
      arguments: Data(
        #"""
        {
          "claim": "Host is enough",
          "impact": "Skip VM setup"
        }
        """#.utf8
      ),
      context: AgentToolContext(
        workingDirectory: tempURL,
        assumptionsURL: ledgerURL
      )
    )

    #expect(result.isError)
    #expect(result.errorKind == .invalidArguments)
    #expect(result.content.contains("rationale"))
  }

  @Test
  func removeUnknownIdIsInvalidArguments() async throws {
    let tempURL = try makeAssumptionTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    let ledgerURL = tempURL.appending(path: "assumptions.json")
    try AssumptionLedgerStore(url: ledgerURL).write(AssumptionLedger())

    let result = try await AgentRemoveAssumptionTool().invoke(
      arguments: Data(#"{"assumption_id":"missing-id"}"#.utf8),
      context: AgentToolContext(
        workingDirectory: tempURL,
        assumptionsURL: ledgerURL
      )
    )

    #expect(result.isError)
    #expect(result.errorKind == .invalidArguments)
    #expect(result.content.contains("Assumption not found"))
  }

  @Test
  func deniedAssumptionNotesDoNotRely() async throws {
    let tempURL = try makeAssumptionTempDirectory()
    defer { try? FileManager.default.removeItem(at: tempURL) }
    let ledgerURL = tempURL.appending(path: "assumptions.json")
    var ledger = AssumptionLedger()
    let existing = try AssumptionRecord(
      draft: AssumptionDraft(
        text: "API keys live in .env",
        rationale: "Common local setup",
        impact: "Skip secrets UI"
      ),
      phase: .plan,
      sessionNumber: 1
    )
    let denied = try existing.reviewed(status: .denied, comment: "Keys are injected")
    ledger.assumptions = [denied]
    try AssumptionLedgerStore(url: ledgerURL).write(ledger)

    let result = try await AgentRecordAssumptionTool().invoke(
      arguments: Data(
        #"""
        {
          "text": "API keys live in .env",
          "rationale": "Saw .env.example",
          "impact": "Skip secrets UI",
          "scope": "repo"
        }
        """#.utf8
      ),
      context: AgentToolContext(
        workingDirectory: tempURL,
        assumptionsURL: ledgerURL
      )
    )

    #expect(!result.isError)
    #expect(result.content.contains("denied"))
    #expect(result.content.contains("do not rely"))
  }
}

@Suite("AgentPlanHistoryTool")
struct AgentPlanHistoryToolTests {
  @Test
  func emptyHistoryReturnsHint() async throws {
    let result = try await AgentPlanHistoryTool().invoke(
      arguments: Data(#"{}"#.utf8),
      context: AgentToolContext(
        workingDirectory: FileManager.default.temporaryDirectory,
        planHistoryEntries: []
      )
    )
    #expect(!result.isError)
    #expect(result.content == "plan history: empty")
  }

  @Test
  func pagesNewestFirstWithMoreHint() async throws {
    let entries = ["first", "second", "third", "fourth"]
    let page = try await AgentPlanHistoryTool().invoke(
      arguments: Data(#"{"limit":2}"#.utf8),
      context: AgentToolContext(
        workingDirectory: FileManager.default.temporaryDirectory,
        planHistoryEntries: entries
      )
    )
    #expect(!page.isError)
    #expect(page.content.contains("4 total, showing 2"))
    #expect(page.content.contains("#4: fourth"))
    #expect(page.content.contains("#3: third"))
    #expect(page.content.contains("offset 2"))

    let older = try await AgentPlanHistoryTool().invoke(
      arguments: Data(#"{"offset":2,"count":2}"#.utf8),
      context: AgentToolContext(
        workingDirectory: FileManager.default.temporaryDirectory,
        planHistoryEntries: entries
      )
    )
    #expect(!older.isError)
    #expect(older.content.contains("#2: second"))
    #expect(older.content.contains("#1: first"))
    #expect(!older.content.contains("more:"))
  }

  @Test
  func clampsLimitAndOffset() {
    let page = PlanHistoryPage.read(
      entries: ["a", "b", "c"],
      offset: -3,
      limit: 500
    )
    #expect(page.offset == 0)
    #expect(page.limit == PlanHistoryPage.maxLimit)
    #expect(page.entries.map(\.iteration) == [3, 2, 1])
  }
}

private func makeAssumptionTempDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appending(path: "AgentAssumptionToolTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}
