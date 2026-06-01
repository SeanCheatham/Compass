import Testing

@testable import Compass

struct LiveFailureInsightTests {
  @Test func ignoresSuccessfulRows() throws {
    let line = LiveLine(
      level: .success,
      text: "bash · swift test",
      detail: "[exit 0]",
      kind: .command,
      status: .completed
    )

    try #require(LiveFailureInsight(line: line) == nil)
  }

  @Test func explainsToolArgumentFailuresForNonEngineers() throws {
    let insight = try #require(
      LiveFailureInsight(
        line: LiveLine(
          level: .error,
          text: "edit_file · Sources/App.swift",
          detail: "Invalid arguments: Missing required field `path` at root.",
          kind: .fileChange,
          status: .failed
        )
      )
    )

    try #require(insight.kind == .argumentRepair)
    try #require(insight.title == "Tool Request Needs Repair")
    try #require(insight.explanation.contains("could not understand"))
    try #require(insight.nextStep.contains("required fields"))
    try #require(insight.narrationIdentifier.contains("argumentRepair"))
  }

  @Test func explainsFileSafetyGate() throws {
    let insight = try #require(
      LiveFailureInsight(
        line: LiveLine(
          level: .error,
          text: "write_file · Sources/App.swift",
          detail:
            "write_file would overwrite Sources/App.swift but it has not been read in this session.",
          kind: .fileChange,
          status: .failed
        )
      )
    )

    try #require(insight.kind == .safetyGate)
    try #require(insight.title == "File Safety Gate Stopped It")
    try #require(insight.explanation.contains("blocked an overwrite"))
    try #require(insight.nextStep.contains("read the file first"))
  }

  @Test func explainsCommandFailuresFromExitOutput() throws {
    let insight = try #require(
      LiveFailureInsight(
        line: LiveLine(
          level: .error,
          text: "bash · swift test",
          detail: "[stderr]\nerror: compile failed\n\n[exit 1]",
          kind: .command,
          status: .failed
        )
      )
    )

    try #require(insight.kind == .commandFailure)
    try #require(insight.title == "Command Reported A Failure")
    try #require(insight.nextStep.contains("rerun the proof"))
  }

  @Test func timeoutClassificationWinsOverGenericCommandFailure() throws {
    let insight = try #require(
      LiveFailureInsight(
        line: LiveLine(
          level: .error,
          text: "bash · sleep 10",
          detail: "[timed out after 500 ms]\n\n[exit 143]",
          kind: .command,
          status: .failed
        )
      )
    )

    try #require(insight.kind == .timeout)
    try #require(insight.title == "Step Ran Out Of Time")
  }

  @Test func narratorUsesFoundationModelsAsOptionalFailurePolish() async throws {
    let insight = try #require(
      LiveFailureInsight(
        line: LiveLine(
          level: .error,
          text: "grep · Widget",
          detail: "File not found: Sources/Widget.swift",
          kind: .lifecycle,
          status: .failed
        )
      )
    )

    try await withMockFoundationModels(
      response: "Compass could not find that file, so the next step is to list current paths."
    ) {
      let generated = await LiveFailureInsightNarrator.narrate(insight: insight)
      let narration = try #require(generated)
      try #require(narration.insightIdentifier == insight.narrationIdentifier)
      try #require(
        narration.text
          == "Compass could not find that file, so the next step is to list current paths.")
    }
  }

  @Test func narratorRejectsStructuredBulletedOrLinkedOutput() async throws {
    let insight = try #require(
      LiveFailureInsight(
        line: LiveLine(
          level: .error,
          text: "bash · swift test",
          detail: "[exit 1]",
          kind: .command,
          status: .failed
        )
      )
    )

    await withMockFoundationModels(response: #"{"text":"Invented JSON"}"#) {
      let narration = await LiveFailureInsightNarrator.narrate(insight: insight)
      #expect(narration == nil)
    }

    await withMockFoundationModels(response: "- Retry with a hidden command") {
      let narration = await LiveFailureInsightNarrator.narrate(insight: insight)
      #expect(narration == nil)
    }

    await withMockFoundationModels(response: "Read more at https://example.com") {
      let narration = await LiveFailureInsightNarrator.narrate(insight: insight)
      #expect(narration == nil)
    }
  }
}
