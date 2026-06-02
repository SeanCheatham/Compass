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
    project.drafts =
      "- Improve snapshots because users get lost; success shows the latest run audit."
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
    #expect(payload.text.contains("Draft queue:"))
    #expect(payload.text.contains("1 draft is ready for Plan"))
    #expect(payload.text.contains("Prompt lane: 1 active prompt signal"))
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
    #expect(payload.text.contains("Draft queue:"))
    #expect(payload.text.contains("Plan scope: 1 draft is ready for Plan; 1 draft needs detail."))
    #expect(payload.text.contains("Draft #1: Ready for Plan"))
    #expect(payload.text.contains("Draft #2: Add one more signal"))
    #expect(payload.text.contains("Assumption memory:"))
    #expect(payload.text.contains("Prompt lane: 3 active prompt signals"))
    #expect(payload.text.contains("Assumptions needing review:"))
    #expect(payload.text.contains("The target user is a non-engineer operator."))
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
    let historyGuide = PlanSessionHistoryGuide(display: PlanSessionHistoryDisplay(items: []))

    let payload = ProjectSnapshotClipboardPayload(
      projectName: "  \n  ",
      runGuide: runGuide,
      draftGuide: draftGuide,
      assumptionGuide: assumptionGuide,
      settingsGuide: settingsGuide,
      historyGuide: historyGuide
    )

    #expect(payload.text.contains("Project: Untitled project"))
    #expect(payload.text.contains("Status: Ready for Develop"))
    #expect(payload.text.contains("Draft queue:"))
    #expect(payload.text.contains("Status: No queued drafts"))
    #expect(payload.text.contains("Plan scope: No queued drafts."))
    #expect(payload.text.contains("Assumption memory:"))
    #expect(payload.text.contains("Prompt lane: No active prompt signals"))
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
    commits: [SessionCommit] = []
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
      status: .succeeded,
      notes: [],
      verifyOutput: nil,
      feedback: nil
    )
  }
}
