import Foundation

extension Prompts {
  public static func subAgentSystemPrompt(
    parentPhase: AgentPhase,
    workingDirectoryPath: String,
    toolNames: [String],
    executionEnvironment: ExecutionEnvironmentDescriptor = .macOSVM,
    promptMode: AgentPromptMode = .envelope
  ) -> String {
    let visibleWorkingDirectory = Self.visibleWorkingDirectory(
      workingDirectoryPath,
      executionEnvironment: executionEnvironment
    )
    let protocolSection =
      promptMode == .nativeTools
      ? """
      Response protocol:
      - Use the provided Compass tools directly; do not write JSON envelopes.
      - Finish by calling the `delegate_submit` tool with \
      `{"findings":"<grounded findings>","filesRead":["path"],"commandsRun":["cmd"],"openQuestions":["..."]}`. \
      `filesRead`, `commandsRun`, and `openQuestions` are optional arrays (use `[]` when empty).
      Do not delegate further.
      """
      : """
      Response protocol:
      - Emit exactly one JSON object per turn, with no prose or Markdown fences.
      - Request a tool with `{"kind":"delegate_continue","tool":"read_file","arguments":{"path":"package.json"},"reason":"Need current scripts.","note":"If scripts exist, report the relevant verify command."}`.
      - Finish with `{"kind":"delegate_submit","payload":{"findings":"<grounded findings>","filesRead":[],"commandsRun":[],"openQuestions":[]}}`.
      Do not delegate further.
      """
    return """
      You are a focused sub-agent inside Compass's local software factory. Investigate the
      delegated task and return a self-contained `findings` string through `delegate_submit`.

      \(compassOverviewSection())

      Working directory: \(visibleWorkingDirectory)
      All tool paths are resolved against this directory. Prefer relative paths.
      Tools available: \(toolNames.isEmpty ? "(none)" : toolNames.joined(separator: ", "))

      \(executionEnvironmentSection(executionEnvironment))

      \(protocolSection)
      """
  }

  public enum ExecutionEnvironmentDescriptor {
    case host
    case macOSVM
  }

  public static func agentSystemPrompt(
    phase: AgentPhase,
    workingDirectoryPath: String,
    executionEnvironment: ExecutionEnvironmentDescriptor = .macOSVM,
    promptMode: AgentPromptMode = .envelope
  ) -> String {
    let fileTools = "read_file, ls, grep, glob"
    let codemapTools = "outline, find_symbol, summary, list_files, importers_of"
    let assumptionTools = "record_assumption, remove_assumption"
    let delegateTool = "delegate"
    let toolList: String
    switch phase {
    case .plan:
      toolList = """
        - Codemap: \(codemapTools)
        - Files: \(fileTools)
        - Shell: bash for read-only probes (hard-enforced; no writes/git mutations)
        - History: plan_history
        - Sub-agent: \(delegateTool) — prefer `profile: explore` for focused codebase questions
        - Assumptions: \(assumptionTools)
        """
    case .develop:
      toolList = """
        - Codemap: \(codemapTools)
        - Files: \(fileTools)
        - Mutation: write_file, edit_file, bash
        - Sub-agent: \(delegateTool) — `explore` for investigation, `verify` for check commands, `repair` for a tight fix pass
        - Assumptions: \(assumptionTools)
        """
    case .critic:
      toolList = """
        - Codemap: \(codemapTools)
        - Files: \(fileTools)
        - Shell: bash for read-only probes (hard-enforced; no writes/git mutations)
        - Sub-agent: \(delegateTool) — prefer `profile: explore` for focused review questions
        - Assumptions: \(assumptionTools)
        """
    case .requirementsAudit:
      toolList = """
        - Codemap: \(codemapTools)
        - Files: \(fileTools)
        - Shell: bash for read-only probes (hard-enforced; no writes/git mutations)
        - Sub-agent: \(delegateTool) — prefer `profile: explore` for focused evidence gathering
        - Assumptions: \(assumptionTools)
        """
    case .health:
      toolList = """
        - Codemap: \(codemapTools)
        - Files: \(fileTools)
        - Health: write_generated_test and/or scoped write_file/edit_file (focus-dependent)
        - Shell: bash for cargo test and read-only probes (no production file mutation via shell)
        - Assumptions: \(assumptionTools)
        """
    }

    let visibleWorkingDirectory = Self.visibleWorkingDirectory(
      workingDirectoryPath,
      executionEnvironment: executionEnvironment
    )

    let protocolSection =
      promptMode == .nativeTools
      ? """
      Response protocol:
      - Call the provided Compass tools directly; do not write JSON envelopes or prose turn protocols.
      - Prefer batching independent reads in one turn when the provider allows parallel tool calls.
      - Finish the phase by calling the `\(phaseSubmitKind(phase))` tool with arguments matching the phase schema in the user message.
      """
      : """
      Response protocol:
      - Emit exactly one JSON object per turn, with no prose or Markdown fences.
      - Request one Compass tool with `{"kind":"\(phaseContinuationKind(phase))","tool":"read_file","arguments":{"path":"package.json"},"reason":"Need current scripts.","note":"If scripts exist, choose the relevant verify command next."}`.
      - Finish the phase with `{"kind":"\(phaseSubmitKind(phase))","payload":{...}}`, where `payload` matches the phase schema in the user message.
      - Use `reason` for why the requested tool is needed now. Use optional `note` only for a short unverified next-step hint after the real tool observation.
      """

    return """
      You are operating inside Compass's local software factory.

      \(compassOverviewSection())

      \(workLoopSection(phase: phase))

      Working directory: \(visibleWorkingDirectory)
      All tool paths are resolved against this directory. Prefer relative paths
      (or paths under \(visibleWorkingDirectory) when an absolute path is required).

      Compass-owned `.compass/` files are injected into the user prompt. Do not read or edit
      `.compass/*` directly. Return lesson updates through `lessonEdits`; manage assumptions
      through assumption tools.

      \(lessonEditsGuidance())

      \(assumptionGuidance())

      \(executionEnvironmentSection(executionEnvironment))

      Tools available:
      \(toolList)

      \(protocolSection)

      Use codemap tools before broad file reads when possible.
      """
  }

  public static func compassOverviewSection() -> String {
    """
    Compass is a macOS host app with two project kinds: factory and health.
    Factory loop: Brief -> Plan -> Develop -> Verify -> Critic -> Health (Plan pressure)
    -> Requirements Audit. Health projects improve an imported Rust repo
    (recon -> focused pass -> triage) with proposed patches on a Compass branch.
    Compass uses an OpenAI-compatible cloud model for agent turns when configured, with
    optional local MLX assist for cheap work, and keeps the harness responsible for state,
    verification, files, history, assumptions, and retries.
    Factory-generated output requires Rust `crates/core` plus at least one product (`cli`
    and/or `macos`). Domain logic stays in `crates/core`; UI policy in `crates/ui`
    when macOS is enabled; CLI and macOS shells are adapters.
    Rust verification uses `cargo fmt`, Clippy, and `cargo test` (UI simulation included);
    coverage uses `cargo llvm-cov`. When `macos` is enabled, also run
    `bash scripts/verify-macos.sh` inside the embedded macOS VM. Headed launch/screenshot
    is opt-in via `COMPASS_MACOS_UI_FIDELITY=1` (see `docs/ui-runtime.md`).
    Health focuses include bug hunt (compass_gen tests), tests, docs, and cleanup/sprawl;
    agent bash runs inside the same macOS VM.
    """
  }

  public static func workLoopSection(phase: AgentPhase) -> String {
    switch phase {
    case .plan:
      return "Current role: Plan. Decompose or revise the queue, then select one immediate packet."
    case .develop:
      return "Current role: Develop. Implement the immediate packet and report a concrete result."
    case .critic:
      return "Current role: Critic. Review the diff and approve or request one focused repair."
    case .requirementsAudit:
      return
        "Current role: Requirements Audit. Judge in-scope product requirements against the repo with evidence."
    case .health:
      return
        "Current role: Health. Improve the repo along the current focus (bug hunt, tests, docs, or cleanup); propose patches without merging upstream."
    }
  }

  public static func phaseContinuationKind(_ phase: AgentPhase) -> String {
    AgentContinuationPhase(agentPhase: phase).continueKind
  }

  public static func phaseSubmitKind(_ phase: AgentPhase) -> String {
    AgentContinuationPhase(agentPhase: phase).submitKind
  }

  public static func lessonEditsGuidance() -> String {
    """
    Persistent lessons:
    Use `lessonEdits` for durable technical facts future agents should not rediscover.
    Each edit is `{ "find": "...", "replace": "...", "replaceAll": false }`. Use
    `lessonEdits: []` when there is no durable lesson.
    """
  }

  public static func assumptionGuidance() -> String {
    """
    Assumptions:
    Record consequential guesses about user intent, environment, or acceptance criteria with
    `record_assumption`. Remove stale assumptions with `remove_assumption`.
    """
  }

  public static func executionEnvironmentSection(
    _ env: ExecutionEnvironmentDescriptor
  ) -> String {
    switch env {
    case .host:
      return """
        Execution environment: native macOS host.
        File tools and bash both operate on the host worktree. Probe tools before relying on them.
        """
    case .macOSVM:
      return """
        Execution environment: embedded macOS VM (Apple Virtualization.framework).
        File tools read and write the host Git worktree through the virtual root `/workspace`.
        Bash and verify run inside the macOS guest against a CAS/tar-synced file copy of
        that tree (no `.git` in the guest). `/workspace/...` paths in bash are rewritten to
        the guest worktree automatically — use relative paths or `/workspace/...` for every
        tool. Project Git (status, commit, push) is host-only; do not use `git` in factory
        bash. Dirty host files after Develop are expected — the harness lands a commit after
        Critic approves.         The guest has the Rust toolchain (cargo, rustc, rustfmt, clippy) and
        Swift via Xcode Command Line Tools (`swift`, `swift build`, `swift run`, clang).
        The guest does **not** ship XCTest or swift-testing — macOS adapter verify uses the
        `FFIChecks` executable (`swift run FFIChecks`), not `swift test`.
        Outbound internet is available via NAT — do not treat failing network tests as
        "sandbox has no network" without verifying connectivity first.
        """
    }
  }

  public static func visibleWorkingDirectory(
    _ workingDirectoryPath: String,
    executionEnvironment: ExecutionEnvironmentDescriptor
  ) -> String {
    switch executionEnvironment {
    case .macOSVM:
      return "/workspace"
    case .host:
      return workingDirectoryPath
    }
  }
}
