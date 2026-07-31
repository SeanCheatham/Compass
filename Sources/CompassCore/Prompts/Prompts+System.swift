import CompassSandbox
import Foundation

extension Prompts {
  static func subAgentSystemPrompt(
    parentPhase: AgentPhase,
    workingDirectoryPath: String,
    toolNames: [String],
    executionEnvironment: ExecutionEnvironmentDescriptor = .containerizedLinux,
    hostXcodeBuildTestEnabled: Bool = false
  ) -> String {
    let visibleWorkingDirectory = Self.visibleWorkingDirectory(
      workingDirectoryPath,
      executionEnvironment: executionEnvironment
    )
    return """
    You are a focused sub-agent inside Compass's local software factory. Investigate the
    delegated task and return a self-contained `findings` string through `delegate_submit`.

    \(compassOverviewSection())

    Working directory: \(visibleWorkingDirectory)
    All tool paths are resolved against this directory. Prefer relative paths.
    Tools available: \(toolNames.isEmpty ? "(none)" : toolNames.joined(separator: ", "))

    \(executionEnvironmentSection(executionEnvironment, hostXcodeBuildTestEnabled: hostXcodeBuildTestEnabled))

    Response protocol:
    - Emit exactly one JSON object per turn, with no prose or Markdown fences.
    - Request a tool with `{"kind":"delegate_continue","tool":"read_file","arguments":{"path":"package.json"},"reason":"Need current scripts.","note":"If scripts exist, report the relevant verify command."}`.
    - Finish with `{"kind":"delegate_submit","payload":{"findings":"<grounded findings>"}}`.
    Do not delegate further.
    """
  }

  enum ExecutionEnvironmentDescriptor {
    case host
    case containerizedLinux
  }

  static func agentSystemPrompt(
    phase: AgentPhase,
    workingDirectoryPath: String,
    executionEnvironment: ExecutionEnvironmentDescriptor = .containerizedLinux,
    hostXcodeBuildTestEnabled: Bool = false,
    externalToolNames: [String] = []
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
      - Shell: bash for read-only probes; do not mutate tracked files or commit
      - History: plan_history
      - Sub-agent: \(delegateTool)
      - Assumptions: \(assumptionTools)
      """
    case .develop:
      toolList = """
      - Codemap: \(codemapTools)
      - Files: \(fileTools)
      - Mutation: write_file, edit_file, bash
      - Sub-agent: \(delegateTool)
      - Assumptions: \(assumptionTools)
      """
    case .critic:
      toolList = """
      - Codemap: \(codemapTools)
      - Files: \(fileTools)
      - Shell: bash for read-only probes; do not mutate tracked files or commit
      - Sub-agent: \(delegateTool)
      - Assumptions: \(assumptionTools)
      """
    }

    let visibleWorkingDirectory = Self.visibleWorkingDirectory(
      workingDirectoryPath,
      executionEnvironment: executionEnvironment
    )

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

    \(executionEnvironmentSection(
      executionEnvironment,
      hostXcodeBuildTestEnabled: hostXcodeBuildTestEnabled
    ))

    Tools available:
    \(toolList)

    Response protocol:
    - Emit exactly one JSON object per turn, with no prose or Markdown fences.
    - Request one Compass tool with `{"kind":"\(phaseContinuationKind(phase))","tool":"read_file","arguments":{"path":"package.json"},"reason":"Need current scripts.","note":"If scripts exist, choose the relevant verify command next."}`.
    - Finish the phase with `{"kind":"\(phaseSubmitKind(phase))","payload":{...}}`, where `payload` matches the phase schema in the user message.
    - Use `reason` for why the requested tool is needed now. Use optional `note` only for a short unverified next-step hint after the real tool observation.

    Use codemap tools before broad file reads when possible.
    """
  }

  static func compassOverviewSection() -> String {
    """
    Compass is a macOS host app that runs one Git repository as a local software factory.
    The loop is Brief -> decomposed queue -> immediate packet -> Develop -> Verify -> Critic.
    Compass uses an OpenAI-compatible cloud model for factory turns when configured, with
    optional local MLX assist for cheap work, and keeps the harness responsible for state,
    verification, files, history, assumptions, and retries.
    Generated output is Rust only: Cargo workspace with `crates/app-core` and
    `crates/app-cli`, no web UI. Verification uses `cargo fmt`, Clippy, and
    `cargo test`; coverage uses `cargo llvm-cov`.
    """
  }

  static func workLoopSection(phase: AgentPhase) -> String {
    switch phase {
    case .plan:
      return "Current role: Plan. Decompose or revise the queue, then select one immediate packet."
    case .develop:
      return "Current role: Develop. Implement the immediate packet and report a concrete result."
    case .critic:
      return "Current role: Critic. Review the diff and approve or request one focused repair."
    }
  }

  static func phaseContinuationKind(_ phase: AgentPhase) -> String {
    AgentContinuationPhase(agentPhase: phase).continueKind
  }

  static func phaseSubmitKind(_ phase: AgentPhase) -> String {
    AgentContinuationPhase(agentPhase: phase).submitKind
  }

  static func lessonEditsGuidance() -> String {
    """
    Persistent lessons:
    Use `lessonEdits` for durable technical facts future agents should not rediscover.
    Each edit is `{ "find": "...", "replace": "...", "replaceAll": false }`. Use
    `lessonEdits: []` when there is no durable lesson.
    """
  }

  static func assumptionGuidance() -> String {
    """
    Assumptions:
    Record consequential guesses about user intent, environment, or acceptance criteria with
    `record_assumption`. Remove stale assumptions with `remove_assumption`.
    """
  }

  static func executionEnvironmentSection(
    _ env: ExecutionEnvironmentDescriptor,
    hostXcodeBuildTestEnabled: Bool = false
  ) -> String {
    _ = hostXcodeBuildTestEnabled
    switch env {
    case .host:
      return """
      Execution environment: native macOS host.
      File tools and bash both operate on the host worktree. Probe tools before relying on them.
      """
    case .containerizedLinux:
      return """
      Execution environment: containerized Linux runtime.
      File tools read and write the host worktree through the virtual root `/workspace`.
      Bash commands run inside Linux with that same worktree mounted at `/workspace`.
      Use relative paths or `/workspace/...` for every tool. Expected shell tools include
      git and the Rust toolchain (cargo, rustc, rustfmt, clippy). Docker, Xcode,
      and Homebrew are unavailable.
      """
    }
  }

  static func visibleWorkingDirectory(
    _ workingDirectoryPath: String,
    executionEnvironment: ExecutionEnvironmentDescriptor
  ) -> String {
    switch executionEnvironment {
    case .containerizedLinux:
      return ContainerSandboxConfiguration.defaultWorkspacePath
    case .host:
      return workingDirectoryPath
    }
  }
}
