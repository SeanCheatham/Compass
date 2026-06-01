import Testing

@testable import Compass

struct LiveTimelineGuideTests {
  @Test
  func emptyTimelineExplainsWhatWillAppear() {
    let guide = makeGuide(liveLog: [])

    #expect(guide.shouldShow)
    #expect(guide.title == "Ready for a Run")
    #expect(guide.detail.contains("agent notes"))
    #expect(guide.statusLabel == "No events yet")
    #expect(guide.tone == .idle)
    #expect(guide.checkpoints.map(\.id) == ["plan", "develop", "verify"])
    #expect(guide.allowsNarration)
  }

  @Test
  func runningTimelineNamesTheActivePhase() {
    let guide = makeGuide(
      phase: .developing,
      isRunning: true,
      liveLog: [
        liveLine(
          text: "Editing ContentView",
          kind: .fileChange,
          status: .running
        )
      ]
    )

    #expect(guide.title == "Developing Current Slice")
    #expect(guide.statusLabel == "Live: 1 running")
    #expect(guide.tone == .running)
    #expect(guide.systemImageName == "hammer.fill")
    #expect(guide.checkpoints.map(\.id) == ["notes", "commands", "files"])
    #expect(!guide.allowsNarration)
  }

  @Test
  func pausedTimelineExplainsResumeAndStopChoices() {
    let guide = makeGuide(isPaused: true)

    #expect(guide.title == "Factory Paused")
    #expect(guide.statusLabel == "Paused")
    #expect(guide.tone == .paused)
    #expect(guide.checkpoints.map(\.id) == ["context", "resume", "stop"])
  }

  @Test
  func failedTimelineStartsFromConcreteSymptoms() {
    let guide = makeGuide(
      phase: .failed,
      liveLog: [
        liveLine(
          level: .error,
          text: "Verify failed",
          detail: "Expected true but got false",
          kind: .command,
          status: .failed
        )
      ]
    )

    #expect(guide.title == "Latest Run Needs Review")
    #expect(guide.statusLabel == "1 event")
    #expect(guide.tone == .attention)
    #expect(guide.checkpoints.map(\.id) == ["symptom", "narrow", "proof"])
    #expect(guide.narrationIdentifier.contains("failedEvents:1"))
    #expect(guide.latestEvents.map(\.text) == ["Verify failed"])
    #expect(guide.latestEvents.map(\.detail) == ["Expected true but got false"])
  }

  @Test
  func reliabilityBannerOwnsAttentionStateWhenPresent() {
    let guide = LiveTimelineGuide(
      phase: .failed,
      isRunning: false,
      isAutoPlaying: false,
      isPaused: false,
      liveLog: [
        liveLine(
          level: .error,
          text: "Verify failed",
          kind: .command,
          status: .failed
        )
      ],
      reliabilityStatus: failedReliabilityStatus()
    )

    #expect(!guide.shouldShow)
    #expect(!guide.allowsNarration)
  }

  @Test
  func clipboardPayloadPackagesRunningTimelineForReuse() {
    let guide = makeGuide(
      phase: .developing,
      isRunning: true,
      liveLog: [
        liveLine(
          text: "Develop started",
          kind: .lifecycle,
          status: .completed
        ),
        liveLine(
          text: "swift test --filter LiveTimelineGuideTests",
          kind: .command,
          status: .running
        ),
        liveLine(
          text: "Sources/Compass/LiveTimelineGuide.swift",
          detail: "Updated live timeline copy handoff.",
          kind: .fileChange,
          status: .completed
        ),
      ]
    )

    let payload = LiveTimelineClipboardPayload(guide: guide)
    let runningCommandLine = "[running command info] swift test --filter LiveTimelineGuideTests"
    let fileChangeLine = "[completed file-change info] Sources/Compass/LiveTimelineGuide.swift"

    #expect(payload.text.contains("Compass Live Timeline Handoff"))
    #expect(payload.text.contains("Do not invent commands"))
    #expect(payload.text.contains("Status: Developing Current Slice (running)"))
    #expect(payload.text.contains("Phase: Developing"))
    #expect(payload.text.contains("Events: 3 total, 1 running, 0 failed"))
    #expect(payload.text.contains(runningCommandLine))
    #expect(payload.text.contains(fileChangeLine))
    #expect(payload.text.count <= LiveTimelineClipboardPayload.textLimit)
    #expect(!payload.isEmpty)
  }

  @Test
  func clipboardPayloadStartsFailedTimelineFromConcreteLatestEvent() {
    let guide = makeGuide(
      phase: .failed,
      liveLog: [
        liveLine(
          level: .error,
          text: "Verify failed",
          detail: "Expected true but got false",
          kind: .command,
          status: .failed
        )
      ]
    )

    let payload = LiveTimelineClipboardPayload(guide: guide)
    let failedEventLine = "[failed command error] Verify failed: Expected true but got false"

    #expect(payload.text.contains("Status: Latest Run Needs Review (attention)"))
    #expect(payload.text.contains("Events: 1 total, 0 running, 1 failed"))
    #expect(payload.text.contains(failedEventLine))
    #expect(payload.text.contains("smallest repair plus a proof rerun"))
  }

  @Test
  func clipboardPayloadIsEmptyWhenReliabilityBannerOwnsAttention() {
    let guide = LiveTimelineGuide(
      phase: .failed,
      isRunning: false,
      isAutoPlaying: false,
      isPaused: false,
      liveLog: [
        liveLine(
          level: .error,
          text: "Verify failed",
          kind: .command,
          status: .failed
        )
      ],
      reliabilityStatus: failedReliabilityStatus()
    )

    let payload = LiveTimelineClipboardPayload(guide: guide)

    #expect(payload.isEmpty)
    #expect(payload.text.isEmpty)
  }

  @Test
  func narratorUsesFoundationModelsOnlyAsIdlePolish() async throws {
    let idleGuide = makeGuide(liveLog: [])

    try await withMockFoundationModels(response: "Compass is ready; start Plan for a proposal.") {
      let generatedNarration = await LiveTimelineGuideNarrator.narrate(guide: idleGuide)
      let narration = try #require(generatedNarration)
      #expect(narration.guideIdentifier == idleGuide.narrationIdentifier)
      #expect(narration.text == "Compass is ready; start Plan for a proposal.")
    }

    let runningGuide = makeGuide(isRunning: true)
    await withMockFoundationModels(response: "Should not be used") {
      let narration = await LiveTimelineGuideNarrator.narrate(guide: runningGuide)
      #expect(narration == nil)
    }
  }

  @Test
  func narratorRejectsStructuredOrLinkedOutput() async {
    let guide = makeGuide(liveLog: [])

    await withMockFoundationModels(response: #"{"text":"Invented JSON"}"#) {
      let narration = await LiveTimelineGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }

    await withMockFoundationModels(response: "Read more at https://example.com") {
      let narration = await LiveTimelineGuideNarrator.narrate(guide: guide)
      #expect(narration == nil)
    }
  }

  private func makeGuide(
    phase: LoopPhase = .idle,
    isRunning: Bool = false,
    isAutoPlaying: Bool = false,
    isPaused: Bool = false,
    liveLog: [LiveLine] = []
  ) -> LiveTimelineGuide {
    LiveTimelineGuide(
      phase: phase,
      isRunning: isRunning,
      isAutoPlaying: isAutoPlaying,
      isPaused: isPaused,
      liveLog: liveLog,
      reliabilityStatus: emptyReliabilityStatus()
    )
  }

  private func liveLine(
    level: LiveLine.Level = .info,
    text: String,
    detail: String? = nil,
    kind: LiveLine.Kind = .message,
    status: LiveLine.Status = .none
  ) -> LiveLine {
    LiveLine(
      level: level,
      text: text,
      detail: detail,
      kind: kind,
      status: status
    )
  }

  private func emptyReliabilityStatus() -> ProjectReliabilityStatus {
    ProjectReliabilityStatus(
      feedback: PlanReliabilityFeedback(
        state: PlanState(
          completed: [],
          immediate: nil,
          midTerm: "",
          longTerm: ""
        ),
        sessions: []
      )
    )
  }

  private func failedReliabilityStatus() -> ProjectReliabilityStatus {
    ProjectReliabilityStatus(
      feedback: PlanReliabilityFeedback(
        state: PlanState(
          completed: [],
          immediate: PlanNext(
            plan: "Fix the failing check.",
            verify: "swift test --filter LiveTimelineGuideTests"
          ),
          midTerm: "",
          longTerm: ""
        ),
        sessions: [
          SessionRecord(
            session: 1,
            startedAt: 1_000,
            endedAt: 1_500,
            plan: "Fix the failing check.",
            verify: "swift test --filter LiveTimelineGuideTests",
            beforeSha: nil,
            afterSha: nil,
            commits: [],
            status: .failed,
            notes: [],
            verifyOutput: VerifyOutput(
              command: "swift test --filter LiveTimelineGuideTests",
              exitCode: 1,
              tail: "Expected true but got false"
            ),
            feedback: nil
          )
        ]
      )
    )
  }
}
