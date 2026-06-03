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
    try #require(insight.repairOwner.label == "Project proof")
    try #require(insight.repairOwner.detail.contains("first clear command error"))
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

  @Test func explainsProviderStreamFailuresAsConnectionRepair() throws {
    let insight = try #require(
      LiveFailureInsight(
        line: LiveLine(
          level: .error,
          text: "Develop failed",
          detail:
            "Chat completions stream failed: status code: 401 - upstream body: unauthorized.",
          kind: .lifecycle,
          status: .failed
        )
      )
    )

    try #require(insight.kind == .providerFailure)
    try #require(insight.title == "Model Provider Needs Attention")
    try #require(insight.explanation.contains("Text provider"))
    try #require(insight.nextStep.contains("API key"))
    try #require(insight.repairOwner.label == "Text provider")
    try #require(insight.narrationIdentifier.contains("providerFailure"))
  }

  @Test func explainsGuestBridgeFailuresAsPrivateWorkspaceRepair() throws {
    let insight = try #require(
      LiveFailureInsight(
        line: LiveLine(
          level: .error,
          text: "Develop failed",
          detail: "guest rpc transport failed: vsock connect failed",
          kind: .lifecycle,
          status: .failed
        )
      )
    )

    try #require(insight.kind == .guestBridge)
    try #require(insight.title == "Private Workspace Connection Had Trouble")
    try #require(insight.explanation.contains("private workspace"))
    try #require(insight.nextStep.contains("repair or restart the workspace"))
    try #require(insight.badge == "Workspace")
    try #require(insight.repairOwner.label == "Private workspace")
    try #require(insight.repairOwner.detail.contains("Repair or restart"))
    try #require(!insight.explanation.contains("guest"))
    try #require(!insight.explanation.contains("bridge"))
    try #require(!insight.nextStep.contains("route"))

    let payload = LiveFailureInsightClipboardPayload(insight: insight)
    try #require(payload.text.contains("Failure type: Private Workspace Connection Had Trouble"))
    try #require(payload.text.contains("Repair owner: Private workspace"))
    try #require(payload.text.contains("Plain explanation:"))
    try #require(!payload.text.contains("guest workspace"))
    try #require(!payload.text.contains("tool bridge"))
    try #require(!payload.text.contains("shared workspace route"))
  }

  @Test func explainsMissingSubmitResultAsResultHandoff() throws {
    let insight = try #require(
      LiveFailureInsight(
        line: LiveLine(
          level: .error,
          text: "submit_result missing",
          detail: "Model ended with finish_reason=stop without calling submit_result.",
          kind: .lifecycle,
          status: .failed
        )
      )
    )

    try #require(insight.kind == .missingResult)
    try #require(insight.title == "Agent Did Not Hand Back A Result")
    try #require(insight.explanation.contains("result tool"))
    try #require(insight.nextStep.contains("`submit_result`"))
    try #require(insight.narrationIdentifier.contains("missingResult"))
  }

  @Test func explainsDevelopAttemptWithoutSubmitResultAsResultHandoff() throws {
    let insight = try #require(
      LiveFailureInsight(
        line: LiveLine(
          level: .warning,
          text: "Develop attempt 1 ended without submit_result",
          detail: "Agent exceeded max iterations (10).",
          kind: .lifecycle,
          status: .failed
        )
      )
    )

    try #require(insight.kind == .missingResult)
    try #require(insight.title == "Agent Did Not Hand Back A Result")
    try #require(insight.explanation.contains("result tool"))
    try #require(insight.nextStep.contains("`submit_result`"))
  }

  @Test func explainsMalformedToolCallNoteAsArgumentRepair() throws {
    let insight = try #require(
      LiveFailureInsight(
        line: LiveLine(
          level: .warning,
          text: "Tool call edit_file had undecodable args",
          detail: "Args are not valid JSON: missing required field `path`.",
          kind: .agentMessage,
          status: .failed
        )
      )
    )

    try #require(insight.kind == .argumentRepair)
    try #require(insight.title == "Tool Request Needs Repair")
    try #require(insight.nextStep.contains("required fields"))
    try #require(insight.nextStep.contains("smaller JSON"))
  }

  @Test func explainsSubmitResultContractFailuresAsResultShapeRepair() throws {
    let insight = try #require(
      LiveFailureInsight(
        line: LiveLine(
          level: .warning,
          text: "submit_result contract rejected",
          detail: "Wrong type at `state.strategicContext.principles`: expected Array<Any>.",
          kind: .agentMessage,
          status: .failed
        )
      )
    )

    try #require(insight.kind == .resultContractRepair)
    try #require(insight.title == "Result Shape Needs Repair")
    try #require(insight.explanation.contains("`submit_result`"))
    try #require(insight.nextStep.contains("object-vs-string"))
    try #require(insight.nextStep.contains("array-vs-string"))
    try #require(!insight.nextStep.contains("smaller JSON"))
    try #require(insight.repairOwner.label == "Agent handoff")
  }

  @Test func explainsRejectedPlanAsHandoffRepair() throws {
    let insight = try #require(
      LiveFailureInsight(
        line: LiveLine(
          level: .error,
          text: "submit_result plan rejected",
          detail: "Plan returned vague acceptance checks.",
          kind: .lifecycle,
          status: .failed
        )
      )
    )

    try #require(insight.kind == .handoffRepair)
    try #require(insight.title == "Plan Needs A Clearer Handoff")
    try #require(insight.explanation.contains("Immediate Work"))
    try #require(insight.nextStep.contains("real verify command"))
    try #require(insight.repairOwner.label == "Plan handoff")
  }

  @Test func explainsVerifyBypassAsVerifyGateRepair() throws {
    let insight = try #require(
      LiveFailureInsight(
        line: LiveLine(
          level: .error,
          text: "submit_result verify bypass rejected",
          detail:
            "Develop set bypassVerify=true without explaining why the verify command itself is wrong or out of scope.",
          kind: .lifecycle,
          status: .failed
        )
      )
    )

    try #require(insight.kind == .verifyBypass)
    try #require(insight.title == "Verify Bypass Needs A Reason")
    try #require(insight.explanation.contains("skip the verification command"))
    try #require(insight.nextStep.contains("run verification"))
  }

  @Test func explainsWeakSubmitFeedbackAsConcreteRepairNeed() throws {
    let insight = try #require(
      LiveFailureInsight(
        line: LiveLine(
          level: .error,
          text: "submit_result feedback rejected",
          detail: "submit_result.feedback was too weak to hand to the next Plan pass.",
          kind: .lifecycle,
          status: .failed
        )
      )
    )

    try #require(insight.kind == .feedbackRepair)
    try #require(insight.title == "Follow-Up Feedback Was Too Vague")
    try #require(insight.explanation.contains("next Plan pass"))
    try #require(insight.nextStep.contains("exact blocker"))
  }

  @Test func failureClipboardPayloadPackagesRepairContextForReuse() throws {
    let insight = try #require(
      LiveFailureInsight(
        line: LiveLine(
          level: .error,
          text: "bash · swift test --filter LiveFailureInsightTests",
          detail: "[stderr]\nerror: copy failure packet assertion failed\n\n[exit 1]",
          kind: .command,
          status: .failed
        )
      )
    )
    let payload = LiveFailureInsightClipboardPayload(insight: insight)

    try #require(payload.text.contains("Compass Live Failure Handoff"))
    try #require(payload.text.contains("Recipient instructions:"))
    try #require(payload.text.contains("Do not invent files, commands, credentials"))
    try #require(payload.text.contains("Failure type: Command Reported A Failure"))
    try #require(payload.text.contains("Category: commandFailure"))
    try #require(payload.text.contains("Badge: Command"))
    try #require(payload.text.contains("Repair owner: Project proof"))
    try #require(payload.text.contains("Plain explanation:"))
    try #require(payload.text.contains("A command finished with a failing result"))
    try #require(payload.text.contains("Safe next step:"))
    try #require(payload.text.contains("rerun the proof"))
    try #require(
      payload.text.contains("Raw live row:\nbash · swift test --filter LiveFailureInsightTests")
    )
    try #require(payload.text.contains("Raw detail:\n[stderr] error: copy failure packet"))
    try #require(payload.text.count <= LiveFailureInsightClipboardPayload.textLimit)
    try #require(!payload.isEmpty)
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
      let prompt = LiveFailureInsightNarrator.prompt(for: insight)
      try #require(prompt.contains("Repair owner: Workspace edit"))

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

    await withMockFoundationModels(response: "Compass should retry after SSH reaches the guest.") {
      let narration = await LiveFailureInsightNarrator.narrate(insight: insight)
      #expect(narration == nil)
    }
  }
}
