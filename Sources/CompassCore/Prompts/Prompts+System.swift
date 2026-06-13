import Foundation

package extension Prompts {
  static func subAgentSystemPrompt(
    parentPhase: AgentPhase,
    workingDirectoryPath: String,
    toolNames: [String],
    executionEnvironment: ExecutionEnvironmentDescriptor = .containerizedLinux,
    hostXcodeBuildTestEnabled: Bool = false
  ) -> String {
    """
    You are a focused sub-agent inside Compass's local software factory. Investigate the
    delegated task and return a self-contained `findings` string through `delegate_submit`.

    \(compassOverviewSection())

    Working directory: \(workingDirectoryPath)
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
    let tesseraTool =
      "tessera for embedded Tessera verify, project inspection, source checks, tests, and entrypoint execution"
    let assumptionTools = "record_assumption, remove_assumption"
    let delegateTool = "delegate"
    let toolList: String
    switch phase {
    case .plan:
      toolList = """
      - Codemap: \(codemapTools)
      - Files: \(fileTools)
      - Tessera: \(tesseraTool)
      - Shell: bash for read-only probes; do not mutate tracked files or commit
      - History: plan_history
      - Sub-agent: \(delegateTool)
      - Assumptions: \(assumptionTools)
      """
    case .develop:
      toolList = """
      - Codemap: \(codemapTools)
      - Files: \(fileTools)
      - Tessera: \(tesseraTool)
      - Mutation: write_file, edit_file, bash
      - Sub-agent: \(delegateTool)
      - Assumptions: \(assumptionTools)
      """
    case .critic:
      toolList = """
      - Codemap: \(codemapTools)
      - Files: \(fileTools)
      - Tessera: \(tesseraTool)
      - Shell: bash for read-only probes; do not mutate tracked files or commit
      - Sub-agent: \(delegateTool)
      - Assumptions: \(assumptionTools)
      """
    }

    return """
    You are operating inside Compass's local MLX software factory.

    \(compassOverviewSection())

    \(workLoopSection(phase: phase))

    Working directory: \(workingDirectoryPath)
    All paths are resolved against this directory. Prefer relative paths.

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
    Compass relies on one local MLX model for narrow non-deterministic work and keeps the
    harness responsible for state, verification, files, history, assumptions, and retries.
    Generated output is Tessera by default: `tessera.json`, `src/*.tes`, JSON contexts,
    JSON tests, and a `web-json` entrypoint until Tessera has a full UI runtime.
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
      return "Execution environment: native macOS host. Probe tools before relying on them."
    case .containerizedLinux:
      return """
      Execution environment: containerized Linux runtime.
      File tools read and write repo-relative paths on the Compass-owned host worktree.
      Bash commands run inside Linux with the repo mounted at `/workspace`; use relative
      paths or `/workspace/...` in shell commands. Use the Compass `tessera` tool for
      generated Tessera verification, project inspection, source checks, focused test
      runs, and entrypoint probes; the Tessera CLI does not need to be on PATH for
      Compass-owned Tessera workflows. Expected shell tools include git, Node.js, and
      npm/Corepack with pinned pnpm for legacy TypeScript repos.
      Docker, Xcode, and Homebrew are unavailable.
      """
    }
  }
}
