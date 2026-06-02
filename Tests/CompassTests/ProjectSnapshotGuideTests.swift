import Foundation
import Testing

@testable import Compass

struct ProjectSnapshotGuideTests {
  @Test
  @MainActor
  func snapshotBuilderPackagesProjectStateFromOnePlace() throws {
    let parentURL = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: parentURL) }
    let repoURL = parentURL.appending(path: "CompassBuilder", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
    try initGitRepo(at: repoURL)
    let workspace = CompassWorkspace(repoURL: repoURL)
    try workspace.writeSessionAuditManifest(
      SessionAuditManifest(
        session: 2,
        artifacts: [
          SessionAuditArtifact(
            path: "sessions/000002/verify-attempt-1-full.log",
            kind: "verify_output",
            byteCount: 1_024,
            note: "Full Verify output."
          )
        ]
      )
    )

    let project = CompassProject(
      repoURL: repoURL
    )
    project.vision = """
      Compass helps non-engineer operators understand generated software because opaque agent work is hard to trust.
      Success shows project snapshots with vision, proof, and plain-language next steps.
      It must preserve privacy and stay macOS native.
      """
    project.drafts =
      "- Improve snapshots because users get lost; success shows the latest run audit."
    project.lessons = """
      - Learned snapshots are trusted when they include durable project memory; tests passed with ProjectSnapshotGuideTests.
      - Decision: reuse lesson signals before future handoff work.
      """
    project.assumptions = [
      record(
        id: "affirmed",
        text: "Snapshots should stay plain-language.",
        status: .affirmed,
        impact: "Non-developers can hand state to another helper without reading logs."
      )
    ]
    project.sessions = [
      sessionRecord(
        2,
        plan: """
          ## Outcome
          Add a shared snapshot builder.

          ## Acceptance checks
          - Snapshot callers use one assembly path.
          """,
        verify: "swift test --filter ProjectSnapshotGuideTests",
        commits: [
          SessionCommit(
            sha: "123456789abc",
            short: "1234567",
            subject: "Share project snapshot builder"
          )
        ]
      )
    ]
    let settings = AgentRuntimeSettings(
      textProvider: .openAI,
      baseURL: try #require(URL(string: "https://api.openai.com/v1")),
      apiKey: "sk-builder-secret",
      model: "gpt-4o"
    )

    let payload = ProjectSnapshotBuilder.payload(
      for: project,
      agentSettings: settings,
      foundationModelsAvailable: false
    )

    #expect(payload.text.contains("Project: CompassBuilder"))
    #expect(payload.text.contains("Project vision:"))
    #expect(payload.text.contains("Status: Vision ready"))
    #expect(payload.text.contains("Vision preview:"))
    #expect(payload.text.contains("opaque agent work is hard to trust"))
    #expect(payload.text.contains("Draft queue:"))
    #expect(payload.text.contains("1 draft is ready for Plan"))
    #expect(payload.text.contains("Prompt lane: 1 active prompt signal"))
    #expect(payload.text.contains("Project lessons:"))
    #expect(payload.text.contains("Status: Lessons reusable"))
    #expect(payload.text.contains("Lesson preview:"))
    #expect(payload.text.contains("reuse lesson signals"))
    #expect(payload.text.contains("Run history:"))
    #expect(payload.text.contains("Status: Latest Run Succeeded"))
    #expect(payload.text.contains("Latest #2: Succeeded: Add a shared snapshot builder."))
    #expect(
      payload.text.contains(
        "1 audit artifact: Verify output - 1.0 KB is saved with the session audit manifest."
      )
    )
    #expect(payload.text.contains("1 commit: Explore can open file changes"))
    #expect(payload.text.contains("Runtime readiness:"))
    #expect(!payload.text.contains("sk-builder-secret"))
  }

  @Test
  @MainActor
  func snapshotBuilderIncludesRecoveryPlanForFailedVerify() throws {
    let parentURL = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: parentURL) }
    let repoURL = parentURL.appending(path: "CompassRecovery", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
    try initGitRepo(at: repoURL)
    let project = CompassProject(
      repoURL: repoURL
    )
    project.sessions = [
      sessionRecord(
        8,
        plan: """
          ## Outcome
          Keep project snapshots recoverable after failed verify.

          ## Acceptance checks
          - The snapshot names the recovery plan.
          """,
        verify: "swift test --filter ProjectSnapshotGuideTests",
        status: .failed,
        verifyOutput: VerifyOutput(
          command: "swift test --filter ProjectSnapshotGuideTests",
          exitCode: 1,
          tail: "Expected project recovery guidance to appear in the copied snapshot."
        )
      )
    ]

    let payload = ProjectSnapshotBuilder.payload(
      for: project,
      agentSettings: AgentRuntimeSettings(textProvider: .appleFoundationModels),
      foundationModelsAvailable: false
    )

    #expect(payload.text.contains("Project recovery:"))
    #expect(payload.text.contains("Plan: Fix the failing check"))
    #expect(payload.text.contains("Inspect the failing assertion:"))
    #expect(
      payload.text.contains(
        "Expected project recovery guidance to appear in the copied snapshot."
      )
    )
    #expect(payload.text.contains("Fix the behavior under test:"))
    #expect(
      payload.text.contains(
        "Plan Next Step: Ask Plan to create one repair slice from the captured verify output before Develop runs again."
      )
    )
    #expect(payload.text.contains("Run history:"))
    #expect(payload.text.contains("Status: Start With Attention"))
    #expect(payload.text.count <= ProjectSnapshotClipboardPayload.textLimit)
  }

  @Test
  @MainActor
  func snapshotBuilderKeepsRuntimeVisibleWithRecoveryAndProjectMemory() throws {
    let parentURL = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: parentURL) }
    let repoURL = parentURL.appending(path: "CompassFullSnapshot", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
    try initGitRepo(at: repoURL)
    let project = CompassProject(
      repoURL: repoURL
    )
    project.vision = """
      Compass helps non-engineer operators ship trustworthy macOS software because agent work can otherwise feel opaque.
      Success shows a copyable project snapshot with recovery, memory, proof, and runtime readiness.
      It must preserve secrets, keep user files safe, and explain what happened in plain language.
      """
    project.drafts = """
      - Improve recovery handoffs because failed runs need clear next steps; success shows the copied snapshot names the repair.
      - Polish the snapshot button because users need to know what context will be copied.
      """
    project.lessons = """
      - Learned full project snapshots must preserve runtime readiness even when new memory sections are added; tests passed with ProjectSnapshotGuideTests.
      - Decision: keep recovery, vision, lessons, and proof visible together before expanding snapshot scope again.
      """
    project.assumptions = [
      record(
        id: "implicit",
        text: "The project owner is reviewing output without reading raw logs.",
        status: .implicit,
        impact: "Snapshot copy should summarize recovery and proof in plain language.",
        updatedAt: 30
      ),
      record(
        id: "affirmed",
        text: "Recovery guidance should be available outside the Live tab.",
        status: .affirmed,
        impact: "Menu and snapshot handoffs should keep recovery visible.",
        updatedAt: 20
      ),
    ]
    project.sessions = [
      sessionRecord(
        9,
        plan: """
          ## Outcome
          Keep full project snapshots useful during recovery.

          ## Why it matters
          Non-developers need one packet that carries memory, failure context, and proof.

          ## Acceptance checks
          - Snapshot includes project recovery.
          - Snapshot still includes runtime readiness.
          """,
        verify: "swift test --filter ProjectSnapshotGuideTests",
        commits: [
          SessionCommit(
            sha: "fedcba987654",
            short: "fedcba9",
            subject: "Keep snapshot runtime visible"
          )
        ],
        status: .failed,
        verifyOutput: VerifyOutput(
          command: "swift test --filter ProjectSnapshotGuideTests",
          exitCode: 1,
          tail: "Expected runtime readiness to remain visible in full snapshots."
        )
      )
    ]
    let settings = AgentRuntimeSettings(
      textProvider: .openAI,
      baseURL: try #require(URL(string: "https://api.openai.com/v1")),
      apiKey: "sk-full-snapshot-secret",
      model: "gpt-4o",
      webSearchAssignment: CapabilityAssignment(
        provider: .minimaxToken,
        baseURL: try #require(URL(string: "https://api.minimax.io/v1")),
        apiKey: "mm-full-snapshot-secret",
        model: ""
      )
    )

    let payload = ProjectSnapshotBuilder.payload(
      for: project,
      agentSettings: settings,
      foundationModelsAvailable: false
    )

    #expect(payload.text.contains("Project recovery:"))
    #expect(payload.text.contains("Project vision:"))
    #expect(payload.text.contains("Draft queue:"))
    #expect(payload.text.contains("Assumption memory:"))
    #expect(payload.text.contains("Project lessons:"))
    #expect(payload.text.contains("Run history:"))
    #expect(payload.text.contains("Runtime readiness:"))
    #expect(payload.text.contains("Status: Agent Stack Ready"))
    #expect(payload.text.contains("[ready] Web Search"))
    #expect(!payload.text.contains("sk-full-snapshot-secret"))
    #expect(!payload.text.contains("mm-full-snapshot-secret"))
    #expect(payload.text.count <= ProjectSnapshotClipboardPayload.textLimit)
  }

  @Test
  func snapshotPayloadPackagesProjectStateWithoutSecrets() throws {
    let drafts = """
      - Make setup faster because users get stuck; success looks like tests pass.
      - Improve onboarding copy
      """
    let runGuide = ProjectRunControlGuide(
      state: makeState(immediate: nil),
      reliabilityStatus: emptyReliabilityStatus(),
      hasRepository: true,
      isRunning: false,
      isAutoPlaying: false,
      isPaused: false,
      drafts: drafts
    )
    let draftGuide = DraftIntakeGuide(drafts: drafts)
    let assumptionGuide = AssumptionReviewGuide(
      ledger: AssumptionLedger(assumptions: [
        record(
          id: "implicit",
          text: "The target user is a non-engineer operator.",
          status: .implicit,
          impact: "Use plain-language controls and copyable context.",
          updatedAt: 30
        ),
        record(
          id: "affirmed",
          text: "Foundation Models narration should stay optional.",
          status: .affirmed,
          impact: "Deterministic summaries must work without model availability.",
          updatedAt: 20
        ),
        record(
          id: "denied",
          text: "Compass can skip local verification.",
          status: .denied,
          impact: "Future agents must run local verification commands.",
          updatedAt: 10
        ),
      ])
    )
    let settings = AgentRuntimeSettings(
      textProvider: .openAI,
      baseURL: try #require(URL(string: "https://api.openai.com/v1")),
      apiKey: "sk-text-secret",
      model: "gpt-4o",
      webSearchAssignment: CapabilityAssignment(
        provider: .minimaxToken,
        baseURL: try #require(URL(string: "https://api.minimax.io/v1")),
        apiKey: "mm-search-secret",
        model: ""
      )
    )
    let settingsGuide = AgentSettingsGuide(settings: settings, foundationModelsAvailable: false)
    let visionGuide = ProjectVisionGuide(
      vision: """
        Compass helps non-engineer operators build high-quality macOS software because setup, planning, and verification are hard.
        Success shows a visible run audit, passing tests, and plain-language next steps.
        It must preserve privacy, use native Apple capabilities where possible, and avoid hiding risky assumptions.
        """
    )
    let lessonsGuide = ProjectLessonsGuide(
      lessons: """
        - Learned snapshots need durable memory because handoffs lose context; tests passed with ProjectSnapshotGuideTests.
        - Decision: preserve project lessons and reuse them before future snapshot work.
        """
    )
    let historyGuide = PlanSessionHistoryGuide(
      display: PlanSessionHistoryDisplay(
        items: [
          historyItem(
            4,
            commits: [
              SessionCommit(
                sha: "abcdef123456",
                short: "abcdef1",
                subject: "Add project snapshot handoff"
              )
            ]
          )
        ],
        mode: .all
      )
    )

    let payload = ProjectSnapshotClipboardPayload(
      projectName: "Compass",
      runGuide: runGuide,
      draftGuide: draftGuide,
      assumptionGuide: assumptionGuide,
      settingsGuide: settingsGuide,
      visionGuide: visionGuide,
      lessonsGuide: lessonsGuide,
      historyGuide: historyGuide
    )

    #expect(payload.text.contains("Compass Project Snapshot"))
    #expect(payload.text.contains("Do not invent repository state, credentials"))
    #expect(payload.text.contains("Project: Compass"))
    #expect(payload.text.contains("Run readiness:"))
    #expect(payload.text.contains("Status: Drafts need detail"))
    #expect(payload.text.contains("Primary action: Run Loop (loop, enabled)"))
    #expect(payload.text.contains("Next run preview:"))
    #expect(payload.text.contains("Plan one slice"))
    #expect(payload.text.contains("Project vision:"))
    #expect(payload.text.contains("Status: Vision ready"))
    #expect(payload.text.contains("Signals present: Audience, Problem, Success signal, Guardrails"))
    #expect(payload.text.contains("Vision preview:"))
    #expect(payload.text.contains("Draft queue:"))
    #expect(payload.text.contains("Plan scope: 1 draft is ready for Plan; 1 draft needs detail."))
    #expect(payload.text.contains("Draft #1: Ready for Plan"))
    #expect(payload.text.contains("Draft #2: Add one more signal"))
    #expect(payload.text.contains("Assumption memory:"))
    #expect(payload.text.contains("Prompt lane: 3 active prompt signals"))
    #expect(payload.text.contains("Assumptions needing review:"))
    #expect(payload.text.contains("The target user is a non-engineer operator."))
    #expect(payload.text.contains("Project lessons:"))
    #expect(payload.text.contains("Status: Lessons reusable"))
    #expect(payload.text.contains("Signals present: Learning, Proof, Decision, Reuse cue"))
    #expect(payload.text.contains("Missing signals: none"))
    #expect(payload.text.contains("Lesson preview:"))
    #expect(payload.text.contains("Run history:"))
    #expect(payload.text.contains("Status: Latest Run Succeeded"))
    #expect(payload.text.contains("Audit coverage: 3 of 4 audit anchors"))
    #expect(payload.text.contains("1 commit: Explore can open file changes"))
    #expect(payload.text.contains("Runtime readiness:"))
    #expect(payload.text.contains("Status: Agent Stack Ready"))
    #expect(payload.text.contains("Runtime coverage: All 1 optional ready"))
    #expect(payload.text.contains("[ready] Web Search"))
    #expect(!payload.text.contains("sk-text-secret"))
    #expect(!payload.text.contains("mm-search-secret"))
    #expect(payload.text.count <= ProjectSnapshotClipboardPayload.textLimit)
    #expect(!payload.isEmpty)
  }

  @Test
  func snapshotPayloadCoversEmptyDraftAndAssumptionState() {
    let runGuide = ProjectRunControlGuide(
      state: makeState(),
      reliabilityStatus: emptyReliabilityStatus(),
      hasRepository: true,
      isRunning: false,
      isAutoPlaying: false,
      isPaused: false
    )
    let draftGuide = DraftIntakeGuide(drafts: "")
    let assumptionGuide = AssumptionReviewGuide(ledger: .empty)
    let settingsGuide = AgentSettingsGuide(
      settings: AgentRuntimeSettings(textProvider: .appleFoundationModels),
      foundationModelsAvailable: true
    )
    let visionGuide = ProjectVisionGuide(vision: "")
    let lessonsGuide = ProjectLessonsGuide(lessons: "")
    let historyGuide = PlanSessionHistoryGuide(display: PlanSessionHistoryDisplay(items: []))

    let payload = ProjectSnapshotClipboardPayload(
      projectName: "  \n  ",
      runGuide: runGuide,
      draftGuide: draftGuide,
      assumptionGuide: assumptionGuide,
      settingsGuide: settingsGuide,
      visionGuide: visionGuide,
      lessonsGuide: lessonsGuide,
      historyGuide: historyGuide
    )

    #expect(payload.text.contains("Project: Untitled project"))
    #expect(payload.text.contains("Status: Ready for Develop"))
    #expect(payload.text.contains("Project vision:"))
    #expect(payload.text.contains("Status: Vision empty"))
    #expect(payload.text.contains("Missing signals: Audience, Problem, Success signal, Guardrails"))
    #expect(payload.text.contains("Draft queue:"))
    #expect(payload.text.contains("Status: No queued drafts"))
    #expect(payload.text.contains("Plan scope: No queued drafts."))
    #expect(payload.text.contains("Assumption memory:"))
    #expect(payload.text.contains("Prompt lane: No active prompt signals"))
    #expect(payload.text.contains("Project lessons:"))
    #expect(payload.text.contains("Status: Lessons empty"))
    #expect(payload.text.contains("Missing signals: Learning, Proof, Decision, Reuse cue"))
    #expect(payload.text.contains("Run history:"))
    #expect(payload.text.contains("Status: No Runs Yet"))
    #expect(payload.text.contains("Audit coverage: No visible audit"))
    #expect(payload.text.contains("Runtime readiness:"))
    #expect(payload.text.contains("Runtime coverage: Core Text ready"))
    #expect(payload.text.count <= ProjectSnapshotClipboardPayload.textLimit)
    #expect(!payload.isEmpty)
  }

  private func emptyReliabilityStatus() -> ProjectReliabilityStatus {
    ProjectReliabilityStatus(
      feedback: PlanReliabilityFeedback(
        state: PlanState(completed: [], immediate: nil, candidates: "", strategicContext: ""),
        sessions: []
      )
    )
  }

  private func makeState(
    immediate: PlanNext? = PlanNext(
      plan: "## Outcome\nImprove project snapshots.\n\n## Acceptance checks\n- Focused tests pass.",
      verify: "swift test --filter ProjectSnapshotGuideTests"
    )
  ) -> PlanState {
    PlanState(
      completed: [],
      immediate: immediate,
      candidates: "",
      strategicContext: ""
    )
  }

  private func record(
    id: String,
    text: String,
    status: AssumptionRecord.Status,
    impact: String = "",
    updatedAt: Double = 1
  ) -> AssumptionRecord {
    AssumptionRecord(
      id: id,
      text: text,
      rationale: "",
      evidence: [],
      impact: impact,
      invalidation: "",
      scope: .project,
      status: status,
      createdByPhase: "plan",
      createdInSession: 2,
      createdAt: 1,
      updatedAt: updatedAt
    )
  }

  private func historyItem(
    _ number: Int,
    commits: [SessionCommit] = []
  ) -> PlanSessionHistoryItem {
    PlanSessionHistoryItem(
      sessionNumber: number,
      status: .succeeded,
      statusText: "Succeeded",
      startedAt: Date(timeIntervalSince1970: Double(number)),
      planExcerpt: "Improve project snapshots.",
      handoffDigest: PlanHandoffDigest(
        plan: """
          ## Outcome
          Improve project snapshots.

          ## Acceptance checks
          - The snapshot includes the latest run audit.
          """
      ),
      verifyCommand: "swift test --filter ProjectSnapshotGuideTests",
      feedback: nil,
      notes: [],
      commits: commits,
      failedVerify: nil,
      runtimeRouteSummary: nil
    )
  }

  private func sessionRecord(
    _ number: Int,
    plan: String?,
    verify: String?,
    commits: [SessionCommit] = [],
    status: SessionStatus = .succeeded,
    notes: [String] = [],
    verifyOutput: VerifyOutput? = nil,
    feedback: String? = nil
  ) -> SessionRecord {
    SessionRecord(
      session: number,
      startedAt: Double(number * 1_000),
      endedAt: Double(number * 1_000 + 500),
      plan: plan,
      verify: verify,
      beforeSha: nil,
      afterSha: nil,
      commits: commits,
      status: status,
      notes: notes,
      verifyOutput: verifyOutput,
      feedback: feedback
    )
  }
}
