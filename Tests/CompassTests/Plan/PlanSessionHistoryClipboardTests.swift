import Foundation
import Testing

@testable import CompassCore

@Suite("PlanSessionHistoryClipboardPayload")
struct PlanSessionHistoryClipboardTests {
  @Test
  func includesRunStatusVerifyAndCommits() {
    let item = PlanSessionHistoryItem(
      sessionNumber: 12,
      status: .succeeded,
      statusText: "Success",
      startedAt: Date(timeIntervalSince1970: 1_700_000_000),
      planExcerpt: "Ship clipboard handoff for Activity rows",
      handoffDigest: PlanHandoffDigest(
        plan: """
          ## Outcome
          Wire run history copy

          ## Why it matters
          Agents need bounded audit context

          ## Acceptance checks
          - Activity row copies a handoff packet
          """
      ),
      verifyCommand: "swift test --filter PlanSessionHistoryClipboard",
      feedback: nil,
      notes: ["Verified on Activity tab"],
      commits: [
        SessionCommit(sha: "abcdef0123456789", short: "abcdef0", subject: "Wire run history copy")
      ],
      failedVerify: nil,
      runtimeRouteSummary: nil
    )

    let payload = PlanSessionHistoryClipboardPayload(item: item)
    #expect(!payload.isEmpty)
    #expect(payload.text.contains("Compass Run History Handoff"))
    #expect(payload.text.contains("Run: #12"))
    #expect(payload.text.contains("Status: Success"))
    #expect(payload.text.contains("Wire run history copy"))
    #expect(payload.text.contains("swift test --filter PlanSessionHistoryClipboard"))
    #expect(payload.text.contains("abcdef0 Wire run history copy"))
    #expect(payload.text.contains("Verified on Activity tab"))
    #expect(payload.text.count <= PlanSessionHistoryClipboardPayload.textLimit)
  }

  @Test
  func includesReliabilityCueAndFailedVerify() {
    let item = PlanSessionHistoryItem(
      sessionNumber: 3,
      status: .failed,
      statusText: "Failed",
      startedAt: Date(timeIntervalSince1970: 1_700_000_100),
      planExcerpt: nil,
      verifyCommand: "cargo test",
      feedback: "Retry after fixing compile errors",
      notes: [],
      commits: [],
      failedVerify: .init(
        command: "cargo test",
        exitCodeText: "exit 101",
        tail: "error[E0308]: mismatched types"
      ),
      runtimeRouteSummary: "host"
    )
    let cue = PlanReliabilityFeedback.RunCue(
      notice: PlanReliabilityFeedback.Notice(
        id: "failed-verify-3",
        kind: .failedVerify,
        severity: .failure,
        sessionNumber: 3,
        title: "Verify failed",
        detail: "cargo test exited 101",
        actionLabel: "Repair verify",
        metadata: nil,
        systemImage: "xmark.octagon"
      )
    )

    let payload = PlanSessionHistoryClipboardPayload(item: item, reliabilityCue: cue)
    #expect(payload.text.contains("Attention cue:"))
    #expect(payload.text.contains("Repair verify: cargo test exited 101"))
    #expect(payload.text.contains("Failed verify:"))
    #expect(payload.text.contains("error[E0308]: mismatched types"))
    #expect(payload.text.contains("Retry after fixing compile errors"))
  }

  @Test
  func truncatesToTextLimit() {
    let longTail = String(repeating: "x", count: 5_000)
    let item = PlanSessionHistoryItem(
      sessionNumber: 99,
      status: .failed,
      statusText: "Failed",
      startedAt: Date(),
      planExcerpt: nil,
      verifyCommand: "swift test",
      feedback: longTail,
      notes: Array(repeating: longTail, count: 8),
      commits: (0..<20).map { index in
        SessionCommit(
          sha: String(repeating: "a", count: 40),
          short: "aaaaaaa",
          subject: "\(longTail)-\(index)"
        )
      },
      failedVerify: .init(
        command: "swift test",
        exitCodeText: "exit 1",
        tail: longTail
      ),
      runtimeRouteSummary: nil
    )

    let payload = PlanSessionHistoryClipboardPayload(item: item)
    #expect(payload.text.count <= PlanSessionHistoryClipboardPayload.textLimit)
    #expect(payload.text.hasSuffix("..."))
  }
}
