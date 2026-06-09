import Foundation
import Testing

@testable import Compass

/// The agent system prompt has to carry the working directory the agent
/// is operating in, otherwise the model invents paths from `pwd`/`find`
/// output and trips `AgentToolContext.resolvePath`'s sandbox guard when
/// the guest and host paths diverge. Lock that in.
struct AgentSystemPromptTests {

  @Test func testSystemPromptEmbedsHostWorkingDirectory() throws {
    let prompt = Prompts.agentSystemPrompt(
      phase: .develop,
      workingDirectoryPath: "/Users/dev/projects/widget"
    )
    try #require(
      prompt.contains("Working directory: /Users/dev/projects/widget"),
      "prompt should pin the cwd: \(prompt)"
    )
  }

  @Test func testSystemPromptEmbedsGuestWorkingDirectoryForSharedVMRuns() throws {
    // When the Shared VM is the active backend, Compass passes the
    // guest workspace path here. Verify it gets rendered verbatim so
    // the model orients itself in the guest namespace, not the host.
    let prompt = Prompts.agentSystemPrompt(
      phase: .develop,
      workingDirectoryPath: "/Users/compass/Compass/Repos/AAAA-BBBB-CCCC-DDDD/worktree"
    )
    try #require(prompt.contains("/Users/compass/Compass/Repos/AAAA-BBBB-CCCC-DDDD/worktree"))
  }

  @Test func testPlanPhaseAdvertisesBashWithoutMutationTools() throws {
    let prompt = Prompts.agentSystemPrompt(phase: .plan, workingDirectoryPath: "/x")
    try #require(prompt.contains("File tools"))
    try #require(prompt.contains("Codemap tools"))
    try #require(
      prompt.contains("bash"),
      "Plan must see `bash` so it can ground decisions in real build/test output")
    try #require(
      prompt.contains("do not mutate tracked files"),
      "Plan prompt must state read-only intent for bash")
    try #require(!prompt.contains("Mutation tools"))
    try #require(
      !prompt.contains("write_file"),
      "Plan must not be told about write_file")
    try #require(
      prompt.contains("plan_history"),
      "Plan must see plan_history for Compass-managed completed iterations")
  }

  @Test func testReflectPhaseAdvertisesBashWithoutMutationTools() throws {
    let prompt = Prompts.agentSystemPrompt(phase: .reflect, workingDirectoryPath: "/x")
    try #require(
      prompt.contains("bash"),
      "Reflect must see `bash` so it can probe the project during course-correction")
    try #require(
      prompt.contains("do not mutate tracked files"),
      "Reflect prompt must state read-only intent for bash")
    try #require(!prompt.contains("Mutation tools"))
    try #require(
      !prompt.contains("write_file"),
      "Reflect must not be told about write_file")
  }

  @Test func testDevelopPhaseAdvertisesWriteTools() throws {
    let prompt = Prompts.agentSystemPrompt(phase: .develop, workingDirectoryPath: "/x")
    try #require(prompt.contains("Write tools"))
    try #require(prompt.contains("write_file"))
    try #require(prompt.contains("bash"))
  }

  @Test func testCriticPhaseAdvertisesBashButNotWriteTools() throws {
    let prompt = Prompts.agentSystemPrompt(phase: .critic, workingDirectoryPath: "/x")
    try #require(
      prompt.contains("bash"),
      "Critic must see `bash` for re-running tests / linters")
    try #require(
      !prompt.contains("Write tools"),
      "Critic must not be told about write/edit tools")
    try #require(
      !prompt.contains("write_file"),
      "Critic must not be told about write_file")
    try #require(
      prompt.contains("do not mutate the working tree"),
      "Critic prompt must state read-only intent for bash")
  }

  @Test func testDelegateToolIsAdvertisedInEveryPhase() throws {
    // The `delegate` tool is on every phase's registry; the system
    // prompt has to name it or the model won't reach for it.
    for phase in AgentPhase.allCases {
      let prompt = Prompts.agentSystemPrompt(phase: phase, workingDirectoryPath: "/x")
      try #require(
        prompt.contains("delegate"),
        "phase \(phase) should name `delegate` so the model uses sub-agents")
    }
  }

  @Test func testAssumptionToolIsAdvertisedInEveryPhase() throws {
    for phase in AgentPhase.allCases {
      let prompt = Prompts.agentSystemPrompt(phase: phase, workingDirectoryPath: "/x")
      try #require(prompt.contains("record_assumption"))
      try #require(prompt.contains("remove_assumption"))
      try #require(prompt.contains("Implicit assumptions are treated as true"))
      try #require(prompt.contains("User-denied"))
    }
  }

  /// Tools registered in the schema but absent from the system prompt
  /// rarely get called — chat models heavily prefer tools the prompt
  /// acknowledges, so the codemap tools have to be mentioned in every
  /// phase that has access to them.
  @Test func testCodemapToolsAreAdvertisedInEveryPhase() throws {
    for phase in AgentPhase.allCases {
      let prompt = Prompts.agentSystemPrompt(phase: phase, workingDirectoryPath: "/x")
      try #require(
        prompt.contains("find_symbol"),
        "phase \(phase) should name find_symbol so the model uses it instead of grepping for declarations"
      )
      try #require(prompt.contains("outline"), "phase \(phase) should name outline")
      try #require(prompt.contains("summary"), "phase \(phase) should name summary")
      try #require(prompt.contains("list_files"), "phase \(phase) should name list_files")
      try #require(prompt.contains("importers_of"), "phase \(phase) should name importers_of")
    }
  }

  @Test func testRustCargoToolsAreAdvertisedWhenEnabled() throws {
    let develop = Prompts.agentSystemPrompt(
      phase: .develop,
      workingDirectoryPath: "/x",
      rustCargoToolsEnabled: true
    )
    try #require(develop.contains("workspace_outline"))
    try #require(develop.contains("find_impls"))
    try #require(develop.contains("trait_users"))
    try #require(develop.contains("schema_contracts"))
    try #require(develop.contains("cargo_check"))
    try #require(develop.contains("clippy_lint"))
    try #require(develop.contains("cargo_test"))
    try #require(develop.contains("coverage_gaps"))
    try #require(develop.contains("scaffold_check"))
    try #require(develop.contains("visual_verify"))

    let critic = Prompts.agentSystemPrompt(
      phase: .critic,
      workingDirectoryPath: "/x",
      rustCargoToolsEnabled: true
    )
    try #require(critic.contains("workspace_outline"))
    try #require(critic.contains("schema_contracts"))
    try #require(critic.contains("coverage_gaps"))
    try #require(critic.contains("scaffold_check"))
    try #require(!critic.contains("visual_verify"))
    try #require(!critic.contains("write_file"))
    try #require(!critic.contains("edit_file"))
  }

  // MARK: - Compass product and PMF Proof Loop

  @Test func testSystemPromptExplainsCompassAndPMFProofLoop() throws {
    let prompt = Prompts.agentSystemPrompt(phase: .plan, workingDirectoryPath: "/x")
    try #require(prompt.contains("About Compass:"))
    try #require(prompt.contains("PMF Proof Loop"))
    try #require(prompt.contains("COMPASS.md"))
    try #require(prompt.contains("Plan — pick the next"))
    try #require(prompt.contains("PMF Proof Context"))
    try #require(prompt.contains("Product Tournament Context"))
    try #require(prompt.contains("Your role this turn: Plan"))
    try #require(
      prompt.contains("until paused or until Plan sets") && prompt.contains("`immediate` to null"),
      "should explain project-complete stop condition"
    )
  }

  @Test func testSystemPromptIncludesHumanCenteredProductRules() throws {
    for phase in AgentPhase.allCases {
      let prompt = Prompts.agentSystemPrompt(phase: phase, workingDirectoryPath: "/x")
      try #require(prompt.contains("Human-centered product rules"))
      try #require(prompt.contains("non-engineer owner"))
      try #require(prompt.contains("less-capable next model"))
      try #require(prompt.contains("Foundation Models"))
      try #require(prompt.contains("deterministic fallback"))
      try #require(prompt.contains("record it in the assumption"))
    }
  }

  @Test func testProductTournamentWorkLoopSectionVariesByPhase() throws {
    let develop = Prompts.productTournamentWorkLoopSection(phase: .develop, role: .phaseAgent)
    try #require(develop.contains("Your role this turn: Develop"))
    try #require(develop.contains("verify command"))
    try #require(develop.contains("generated artifact"))

    let critic = Prompts.productTournamentWorkLoopSection(phase: .critic, role: .phaseAgent)
    try #require(critic.contains("Your role this turn: Critic"))

    let sub = Prompts.productTournamentWorkLoopSection(phase: .plan, role: .subAgent)
    try #require(sub.contains("sub-agent"))
    try #require(sub.contains("does not see your tool calls"))
  }

  @Test func testSystemPromptTreatsLessonsAsPersistentMemory() throws {
    let prompt = Prompts.agentSystemPrompt(phase: .develop, workingDirectoryPath: "/x")
    try #require(prompt.contains("Persistent memory (lessons.md)"))
    try #require(prompt.contains("long-term memory"))
    try #require(
      prompt.contains("Prefer adding a lesson over") && prompt.contains("leaving `[]`"),
      "should encourage writing lessons when insights apply again"
    )
  }

  @Test func testLessonEditsGuidanceIsSharedAcrossPhases() throws {
    let plan = try Prompts.planPrompt(
      state: PlanProposal(immediate: nil, candidates: "", strategicContext: ""),
      completedCount: 0,
      drafts: "",
      feedback: "",
      lessons: "",
      vision: "",
      focus: .feature
    )
    try #require(plan.contains("Persistent memory (lessons.md)"))
    try #require(
      Prompts.developPrompt(
        next: PlanNext(plan: "x", verify: "true", verifyTimeoutMs: nil, estimatedDifficulty: .low),
        lessons: "",
        vision: "",
        attempt: 1,
        priorIssues: []
      ).contains("Persistent memory (lessons.md)")
    )
  }

  @Test func testPlanPromptDiscouragesBareSwiftTestDuringXCTestMigration() throws {
    let prompt = try Prompts.planPrompt(
      state: PlanProposal(immediate: nil, candidates: "", strategicContext: ""),
      completedCount: 0,
      drafts: "",
      feedback: "",
      lessons: "",
      vision: "",
      focus: .feature
    )
    try #require(prompt.contains("guest `swift test`"))
    try #require(prompt.contains("swift build --target CompassTests"))
  }

  @Test func testSubAgentSystemPromptIncludesProductTournamentContext() throws {
    let prompt = Prompts.subAgentSystemPrompt(
      parentPhase: .develop,
      workingDirectoryPath: "/x",
      toolNames: ["bash"]
    )
    try #require(prompt.contains("About Compass:"))
    try #require(prompt.contains("PMF Proof Loop"))
    try #require(prompt.contains("sub-agent"))
    try #require(prompt.contains("Human-centered product rules"))
  }

  // MARK: - Execution environment

  @Test func testSharedVMEnvironmentIsTheDefault() throws {
    let prompt = Prompts.agentSystemPrompt(phase: .develop, workingDirectoryPath: "/x")
    try #require(prompt.contains("Compass Shared VM"))
    try #require(!prompt.contains("native macOS host"))
  }

  @Test func testSharedVMEnvironmentTellsModelXcodebuildIsUnavailable() throws {
    // The whole point of this stanza: stop the model from burning
    // iterations on `xcodebuild`/Xcode-only utilities when only CLT
    // is installed. Asserted on the user-visible phrasing the model
    // will pattern-match against.
    let prompt = Prompts.agentSystemPrompt(
      phase: .develop,
      workingDirectoryPath: "/Users/compass/Compass/Repos/AAAA-BBBB-CCCC-DDDD/worktree",
      executionEnvironment: .sharedVM
    )
    try #require(prompt.contains("Compass Shared VM"))
    try #require(prompt.contains("Command Line Tools"))
    try #require(
      prompt.contains("`xcodebuild`"),
      "Must name the unavailable tool so the model recognises its own failed calls")
    try #require(
      prompt.contains("swift build"),
      "Must point at the SwiftPM-native alternative")
    try #require(
      prompt.contains(".xcodeproj"),
      "Must call out the failure mode for Xcode-project builds")
  }

  @Test func testHostXcodeToolIsAbsentFromSystemPromptByDefault() throws {
    let prompt = Prompts.agentSystemPrompt(phase: .develop, workingDirectoryPath: "/x")
    #expect(!prompt.contains("host_xcode"))
    #expect(!prompt.contains("Host Xcode"))
  }

  @Test func testHostXcodeToolStaysAbsentWhenFlagIsPassed() throws {
    let prompt = Prompts.agentSystemPrompt(
      phase: .develop,
      workingDirectoryPath: "/x",
      executionEnvironment: .sharedVM,
      hostXcodeBuildTestEnabled: true
    )
    #expect(!prompt.contains("host_xcode"))
    #expect(!prompt.contains("build/test only"))
    #expect(!prompt.contains("simctl"))
    #expect(!prompt.contains("`open`"))
  }

  @Test func testDevelopPromptDoesNotExplainHostXcodeForVerify() throws {
    let prompt = Prompts.developPrompt(
      next: PlanNext(
        plan: "Run host-only FoundationModels tests.",
        verify:
          "xcodebuild -project Compass.xcodeproj -scheme Compass -only-testing:CompassTests/FoundationModelsAvailabilityTests test",
        requiresHostXcode: true
      ),
      lessons: "",
      vision: "",
      attempt: 1,
      priorIssues: [],
      hostXcodeBuildTestEnabled: true
    )

    try #require(!prompt.contains("Host Apple platform workflow"))
    try #require(!prompt.contains("do not use `bash` for Xcode-only commands"))
    try #require(!prompt.contains("host_xcode"))
    try #require(!prompt.contains("pass only the xcodebuild flags"))
  }

  @Test func testPlanPromptIgnoresHostXcodeFlag() throws {
    let prompt = try Prompts.planPrompt(
      state: PlanProposal(immediate: nil, candidates: "", strategicContext: ""),
      completedCount: 0,
      drafts: "",
      feedback: "",
      lessons: "",
      vision: "",
      focus: .feature,
      hostXcodeBuildTestEnabled: true
    )

    try #require(!prompt.contains("requiresHostXcode"))
    try #require(!prompt.contains("host_xcode"))
  }

  @Test func testExecutionEnvironmentSectionsAreRoutedByDescriptor() throws {
    try #require(Prompts.executionEnvironmentSection(.host).contains("native macOS host"))
    try #require(Prompts.executionEnvironmentSection(.sharedVM).contains("Shared VM"))
  }

  @Test func testSharedVMEnvironmentMentionsToolchainToolsAndDockerLimitation() throws {
    let section = Prompts.executionEnvironmentSection(.sharedVM)
    try #require(section.contains("list_toolchains"))
    try #require(section.contains("install_toolchain"))
    try #require(section.contains("Today's provisioner uses"))
    try #require(section.contains("tool- and"))
    try #require(section.contains("macOS-specific paths"))
    try #require(section.contains("Homebrew"))
    try #require(section.contains("rustc"))
    try #require(section.contains("cargo-llvm-cov"))
    try #require(section.contains("Rust builds/tests"))
    try #require(section.contains("platform-neutral visual verification"))
    try #require(section.contains("Docker is unavailable"))
    try #require(section.contains("Apple platform legacy limitation"))
    try #require(section.contains("Generated Compass output is Rust/Cargo only"))
    try #require(!section.contains("Shared VM (macOS"))
    try #require(!section.contains("For SwiftPM packages, build and test with `swift build`"))
  }

  @Test func testSharedVMEnvironmentWithHostXcodeFlagStillOmitsHostBridge() throws {
    let section = Prompts.executionEnvironmentSection(
      .sharedVM,
      hostXcodeBuildTestEnabled: true
    )
    try #require(section.contains("Apple platform legacy limitation"))
    try #require(!section.contains("host_xcode"))
    try #require(section.contains("avoid guest `swift test`"))
  }

  @Test func testPlanPromptOmitsHostXcodeToolWhenFlagIsPassed() throws {
    let prompt = Prompts.agentSystemPrompt(
      phase: .plan,
      workingDirectoryPath: "/tmp/worktree",
      executionEnvironment: .sharedVM,
      hostXcodeBuildTestEnabled: true
    )
    try #require(!prompt.contains("host_xcode"))
  }

  @Test func testDevelopPromptOmitsHostAppleWorkflowWhenLegacyFlagIsEnabled() throws {
    let prompt = Prompts.developPrompt(
      next: PlanNext(plan: "Compile only", verify: "swift build"),
      lessons: "",
      vision: "",
      attempt: 1,
      priorIssues: [],
      hostXcodeBuildTestEnabled: true
    )
    try #require(!prompt.contains("Host Apple platform workflow"))
    try #require(!prompt.contains("host_xcode"))
  }

  @Test func testSharedVMEnvironmentListsInstalledToolchainsWhenProvided() throws {
    let section = Prompts.executionEnvironmentSection(
      .sharedVM,
      installedToolchainIDs: ["rust", "node"]
    )
    try #require(section.contains("rust, node"))
  }

  // MARK: - `.compass/` workspace clarification

  /// Under `.sharedVM` the guest workspace is populated from
  /// `git ls-files`, which omits `.compass/` (gitignored). The agent
  /// was burning iterations calling `read_file` on
  /// `.compass/lessons.md` even though the lessons content is
  /// injected into the user message. Lock down the system-prompt
  /// stanza that tells the model to stop doing that.
  @Test func testSystemPromptTellsAgentNotToReadCompassDirectory() throws {
    let prompt = Prompts.agentSystemPrompt(
      phase: .develop,
      workingDirectoryPath: "/Users/compass/Compass/Repos/AAAA/worktree",
      executionEnvironment: .sharedVM
    )
    try #require(
      prompt.contains("`.compass/` directory belongs to Compass"),
      "system prompt should explain that .compass/ isn't in the workspace"
    )
    try #require(
      prompt.contains(".compass/lessons.md"),
      "system prompt should name the lessons file explicitly so the model recognises the pattern"
    )
  }
}
