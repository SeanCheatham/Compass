import Foundation
import Testing

@testable import Compass

struct PlanSessionHistoryGuideTests {
  @Test
  func emptyHistoryExplainsFutureAuditTrailWithoutNarration() async {
    let guide = PlanSessionHistoryGuide(display: PlanSessionHistoryDisplay(items: []))

    #expect(guide.title == "No Runs Yet")
    #expect(guide.tone == .empty)
    #expect(guide.statusLabel == "0 runs")
    #expect(guide.facts.map(\.id) == ["auditTrail"])
    #expect(guide.auditCoverage.label == "No visible audit")
    #expect(guide.auditCoverage.coveredCount == 0)
    #expect(guide.auditCoverage.fraction == 0)
    #expect(!guide.allowsNarration)

    await withMockFoundationModels(response: "Should not be used.") {
      let narration = await PlanSessionHistoryGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }
  }

  @Test
  func attentionCueBecomesTheFirstReadSummary() {
    let items = [
      historyItem(
        3,
        status: .failed,
        failedVerify: PlanSessionHistoryItem.FailedVerify(
          command: "swift test",
          exitCodeText: "exit 1",
          tail: "Expected true but got false"
        )
      ),
      historyItem(2),
      historyItem(1),
    ]
    let display = PlanSessionHistoryDisplay(items: items, mode: .all)
    let guide = PlanSessionHistoryGuide(
      display: display,
      runCues: [
        3: runCue(kind: .failedVerify, label: "Retry Develop", detail: "Verify failed.")
      ]
    )

    #expect(guide.title == "Start With Attention")
    #expect(guide.tone == .attention)
    #expect(guide.detail.contains("1 visible cue"))
    #expect(guide.facts.map(\.id).contains("attention"))
    #expect(guide.facts.first { $0.id == "latest" }?.detail == "Expected true but got false")
    #expect(guide.allowsNarration)
  }

  @Test
  func activeRunWarnsThatSummariesAreProvisional() {
    let display = PlanSessionHistoryDisplay(
      items: [
        historyItem(4, status: .awaitingApproval),
        historyItem(3),
      ],
      mode: .all
    )

    let guide = PlanSessionHistoryGuide(display: display)

    #expect(guide.title == "Run Still Open")
    #expect(guide.tone == .active)
    #expect(guide.detail.contains("provisional"))
    #expect(guide.facts.first { $0.id == "latest" }?.label == "Latest #4: Awaiting approval")
  }

  @Test
  func successfulLatestRunHighlightsTrustableProofAndCommits() {
    let display = PlanSessionHistoryDisplay(
      items: [
        historyItem(
          5,
          commits: [
            SessionCommit(sha: "abcdef123456", short: "abcdef1", subject: "Ship history guide")
          ]
        )
      ],
      mode: .all
    )

    let guide = PlanSessionHistoryGuide(display: display)

    #expect(guide.title == "Latest Run Succeeded")
    #expect(guide.tone == .steady)
    #expect(guide.facts.map(\.id).contains("proof"))
    #expect(guide.facts.map(\.id).contains("commits"))
    #expect(guide.auditCoverage.coveredCount == 3)
    #expect(guide.auditCoverage.missingLabels == ["Runtime route"])
    #expect(guide.auditCoverage.detail == "Latest run is missing: Runtime route.")
  }

  @Test
  func latestRunWithAuditArtifactsAddsArtifactFact() {
    let artifact = PlanSessionHistoryItem.AuditArtifact(
      SessionAuditArtifact(
        path: "sessions/000008/verify-attempt-1-full.log",
        kind: "verify_output",
        byteCount: 1_024,
        note: "Full Verify output."
      )
    )
    let display = PlanSessionHistoryDisplay(
      items: [
        historyItem(8, auditArtifacts: [artifact])
      ],
      mode: .all
    )

    let guide = PlanSessionHistoryGuide(display: display)
    let artifactFact = guide.facts.first { $0.id == "artifacts" }

    #expect(artifactFact?.label == "1 audit artifact")
    #expect(
      artifactFact?.detail == "Verify output - 1.0 KB is saved with the session audit manifest."
    )
    #expect(artifactFact?.systemImageName == "archivebox")
  }

  @Test
  func auditCoverageMarksCompleteLatestRunAndFeedsNarrationPrompt() {
    let display = PlanSessionHistoryDisplay(
      items: [
        historyItem(
          6,
          commits: [
            SessionCommit(sha: "123456789abc", short: "1234567", subject: "Ship audit gauge")
          ],
          runtimeRouteSummary: "Develop used Shared VM on macOS."
        )
      ],
      mode: .all
    )

    let guide = PlanSessionHistoryGuide(display: display)

    #expect(guide.auditCoverage.label == "Audit trail complete")
    #expect(guide.auditCoverage.coveredCount == 4)
    #expect(guide.auditCoverage.totalCount == 4)
    #expect(guide.auditCoverage.fraction == 1)
    #expect(guide.auditCoverage.missingLabels.isEmpty)
    #expect(guide.narrationIdentifier.contains("audit:Audit trail complete"))
    #expect(
      PlanSessionHistoryGuideNarrator.prompt(for: guide)
        .contains("Audit coverage: Audit trail complete"))
  }

  @Test
  func filteredOutHistoryExplainsTheFilter() {
    let display = PlanSessionHistoryDisplay(
      items: [historyItem(2), historyItem(1)],
      filter: .failedRejected
    )

    let guide = PlanSessionHistoryGuide(display: display)

    #expect(guide.title == "Filter Hides Runs")
    #expect(guide.tone == .empty)
    #expect(guide.detail.contains("none match Failed/Rejected"))
    #expect(guide.facts.map(\.id) == ["filter"])
    #expect(guide.auditCoverage.label == "No visible audit")
  }

  @Test
  func narratorUsesFoundationModelsAsOptionalPolish() async throws {
    let guide = PlanSessionHistoryGuide(
      display: PlanSessionHistoryDisplay(items: [historyItem(1)], mode: .all)
    )

    try await withMockFoundationModels(
      response: "The latest run succeeded and keeps its proof available."
    ) {
      let generatedNarration = await PlanSessionHistoryGuideNarrator.narrate(guide: guide)
      let narration = try #require(generatedNarration)
      #expect(narration.guideIdentifier == guide.narrationIdentifier)
      #expect(narration.text == "The latest run succeeded and keeps its proof available.")
    }

    await withMockFoundationModels(available: false) {
      let narration = await PlanSessionHistoryGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }
  }

  @Test
  func narratorRejectsStructuredOrLinkedOutput() async {
    let guide = PlanSessionHistoryGuide(
      display: PlanSessionHistoryDisplay(items: [historyItem(1)], mode: .all)
    )

    await withMockFoundationModels(response: #"{"text":"Invented JSON"}"#) {
      let narration = await PlanSessionHistoryGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }

    await withMockFoundationModels(response: "Read more at https://example.com") {
      let narration = await PlanSessionHistoryGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }
  }

  private func historyItem(
    _ number: Int,
    status: SessionStatus = .succeeded,
    commits: [SessionCommit] = [],
    failedVerify: PlanSessionHistoryItem.FailedVerify? = nil,
    runtimeRouteSummary: String? = nil,
    auditArtifacts: [PlanSessionHistoryItem.AuditArtifact] = []
  ) -> PlanSessionHistoryItem {
    PlanSessionHistoryItem(
      sessionNumber: number,
      status: status,
      statusText: statusText(for: status),
      startedAt: Date(timeIntervalSince1970: Double(number)),
      planExcerpt: "Make Run History easier to trust.",
      handoffDigest: PlanHandoffDigest(
        plan: """
          ## Outcome
          Make Run History easier to trust.

          ## Acceptance checks
          - History shows a first-read summary.
          """
      ),
      verifyCommand: "swift test --filter PlanSessionHistoryGuideTests",
      feedback: nil,
      notes: [],
      commits: commits,
      failedVerify: failedVerify,
      runtimeRouteSummary: runtimeRouteSummary,
      auditArtifacts: auditArtifacts
    )
  }

  private func runCue(
    kind: PlanReliabilityFeedback.Kind,
    label: String,
    detail: String
  ) -> PlanReliabilityFeedback.RunCue {
    PlanReliabilityFeedback.RunCue(
      notice: PlanReliabilityFeedback.Notice(
        id: "\(kind.rawValue)-test",
        kind: kind,
        severity: .failure,
        sessionNumber: 0,
        title: "Cue",
        detail: detail,
        actionLabel: label,
        metadata: nil,
        systemImage: "exclamationmark.triangle"
      )
    )
  }

  private func statusText(for status: SessionStatus) -> String {
    switch status {
    case .planning:
      return "Planning"
    case .awaitingApproval:
      return "Awaiting approval"
    case .developing:
      return "Developing"
    case .succeeded:
      return "Succeeded"
    case .failed:
      return "Failed"
    case .cancelled:
      return "Cancelled"
    case .rejectedByPlan:
      return "Rejected by plan"
    case .skipped:
      return "Skipped"
    }
  }
}
