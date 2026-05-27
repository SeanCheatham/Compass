import Foundation
import Testing

@testable import Compass

/// The agent system prompt has to carry the working directory the agent
/// is operating in, otherwise the model invents paths from `pwd`/`find`
/// output and trips `AgentToolContext.resolvePath`'s sandbox guard when
/// the guest and host paths diverge. Lock that in.
struct AgentSystemPromptTests {

  @Test func testSystemPromptEmbedsHostWorkingDirectory() {
    let prompt = Prompts.agentSystemPrompt(
      phase: .develop,
      workingDirectoryPath: "/Users/dev/projects/widget"
    )
    #require(
      prompt.contains("Working directory: /Users/dev/projects/widget"),
      "prompt should pin the cwd: \(prompt)"
    )
  }

  @Test func testSystemPromptEmbedsGuestWorkingDirectoryForSharedVMRuns() {
    // When the Shared VM is the active backend, Compass passes the
    // guest workspace path here. Verify it gets rendered verbatim so
    // the model orients itself in the guest namespace, not the host.
    let prompt = Prompts.agentSystemPrompt(
      phase: .develop,
      workingDirectoryPath: "/Users/compass/Compass/Repos/AAAA-BBBB-CCCC-DDDD/worktree"
    )
    #require(prompt.contains("/Users/compass/Compass/Repos/AAAA-BBBB-CCCC-DDDD/worktree"))
  }

  @Test func testPlanPhaseAdvertisesBashWithoutMutationTools() {
    let prompt = Prompts.agentSystemPrompt(phase: .plan, workingDirectoryPath: "/x")
    #require(prompt.contains("File tools"))
    #require(prompt.contains("Codemap tools"))
    #require(
      prompt.contains("bash"),
      "Plan must see `bash` so it can ground decisions in real build/test output")
    #require(
      prompt.contains("do not mutate tracked files"),
      "Plan prompt must state read-only intent for bash")
    #require(!prompt.contains("Mutation tools"))
    #require(
      !prompt.contains("write_file"),
      "Plan must not be told about write_file")
    #require(
      prompt.contains("plan_history"),
      "Plan must see plan_history for Compass-managed completed iterations")
  }

  @Test func testReflectPhaseAdvertisesBashWithoutMutationTools() {
    let prompt = Prompts.agentSystemPrompt(phase: .reflect, workingDirectoryPath: "/x")
    #require(
      prompt.contains("bash"),
      "Reflect must see `bash` so it can probe the project during course-correction")
    #require(
      prompt.contains("do not mutate tracked files"),
      "Reflect prompt must state read-only intent for bash")
    #require(!prompt.contains("Mutation tools"))
    #require(
      !prompt.contains("write_file"),
      "Reflect must not be told about write_file")
  }

  @Test func testDevelopPhaseAdvertisesWriteTools() {
    let prompt = Prompts.agentSystemPrompt(phase: .develop, workingDirectoryPath: "/x")
    #require(prompt.contains("Write tools"))
    #require(prompt.contains("write_file"))
    #require(prompt.contains("bash"))
  }

  @Test func testCriticPhaseAdvertisesBashButNotWriteTools() {
    let prompt = Prompts.agentSystemPrompt(phase: .critic, workingDirectoryPath: "/x")
    #require(
      prompt.contains("bash"),
      "Critic must see `bash` for re-running tests / linters")
    #require(
      !prompt.contains("Write tools"),
      "Critic must not be told about write/edit tools")
    #require(
      !prompt.contains("write_file"),
      "Critic must not be told about write_file")
    #require(
      prompt.contains("do not mutate the working tree"),
      "Critic prompt must state read-only intent for bash")
  }

  @Test func testDelegateToolIsAdvertisedInEveryPhase() {
    // The `delegate` tool is on every phase's registry; the system
    // prompt has to name it or the model won't reach for it.
    for phase in AgentPhase.allCases {
      let prompt = Prompts.agentSystemPrompt(phase: phase, workingDirectoryPath: "/x")
      #require(
        prompt.contains("delegate"),
        "phase \(phase) should name `delegate` so the model uses sub-agents")
    }
  }

  /// Tools registered in the schema but absent from the system prompt
  /// rarely get called — chat models heavily prefer tools the prompt
  /// acknowledges, so the codemap tools have to be mentioned in every
  /// phase that has access to them.
  @Test func testCodemapToolsAreAdvertisedInEveryPhase() {
    for phase in AgentPhase.allCases {
      let prompt = Prompts.agentSystemPrompt(phase: phase, workingDirectoryPath: "/x")
      #require(
        prompt.contains("find_symbol"),
        "phase \(phase) should name find_symbol so the model uses it instead of grepping for declarations"
      )
      #require(prompt.contains("outline"), "phase \(phase) should name outline")
      #require(prompt.contains("summary"), "phase \(phase) should name summary")
      #require(prompt.contains("list_files"), "phase \(phase) should name list_files")
      #require(prompt.contains("importers_of"), "phase \(phase) should name importers_of")
    }
  }

  // MARK: - Compass product and factory loop

  @Test func testSystemPromptExplainsCompassAndSoftwareFactory() {
    let prompt = Prompts.agentSystemPrompt(phase: .plan, workingDirectoryPath: "/x")
    #require(prompt.contains("About Compass:"))
    #require(prompt.contains("software factory"))
    #require(prompt.contains("COMPASS.md"))
    #require(prompt.contains("Software factory loop"))
    #require(prompt.contains("Plan — pick the next"))
    #require(prompt.contains("Your role this turn: Plan"))
    #require(
      prompt.contains("until Plan sets `immediate` to null"),
      "should explain project-complete stop condition"
    )
  }

  @Test func testSoftwareFactorySectionVariesByPhase() {
    let develop = Prompts.softwareFactorySection(phase: .develop, role: .phaseAgent)
    #require(develop.contains("Your role this turn: Develop"))
    #require(develop.contains("verify command"))

    let critic = Prompts.softwareFactorySection(phase: .critic, role: .phaseAgent)
    #require(critic.contains("Your role this turn: Critic"))

    let sub = Prompts.softwareFactorySection(phase: .plan, role: .subAgent)
    #require(sub.contains("sub-agent"))
    #require(sub.contains("does not see your tool calls"))
  }

  @Test func testSystemPromptTreatsLessonsAsPersistentMemory() {
    let prompt = Prompts.agentSystemPrompt(phase: .develop, workingDirectoryPath: "/x")
    #require(prompt.contains("Persistent memory (lessons.md)"))
    #require(prompt.contains("long-term memory"))
    #require(
      prompt.contains("Prefer adding a lesson over leaving `[]`"),
      "should encourage writing lessons when insights apply again"
    )
  }

  @Test func testLessonEditsGuidanceIsSharedAcrossPhases() throws {
    let plan = try Prompts.planPrompt(
      state: PlanProposal(immediate: nil, midTerm: "", longTerm: ""),
      completedCount: 0,
      drafts: "",
      feedback: "",
      lessons: "",
      vision: "",
      focus: .feature
    )
    #require(plan.contains("Persistent memory (lessons.md)"))
    #require(
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
      state: PlanProposal(immediate: nil, midTerm: "", longTerm: ""),
      completedCount: 0,
      drafts: "",
      feedback: "",
      lessons: "",
      vision: "",
      focus: .feature
    )
    #require(prompt.contains("do not plan bare `swift test`"))
    #require(prompt.contains("swift build --target CompassTests"))
  }

  @Test func testSubAgentSystemPromptIncludesFactoryContext() {
    let prompt = Prompts.subAgentSystemPrompt(
      parentPhase: .develop,
      workingDirectoryPath: "/x",
      toolNames: ["bash"]
    )
    #require(prompt.contains("About Compass:"))
    #require(prompt.contains("software factory"))
    #require(prompt.contains("sub-agent"))
  }

  // MARK: - Execution environment

  @Test func testSharedVMEnvironmentIsTheDefault() {
    let prompt = Prompts.agentSystemPrompt(phase: .develop, workingDirectoryPath: "/x")
    #require(prompt.contains("Compass Shared VM"))
    #require(!prompt.contains("native macOS host"))
  }

  @Test func testSharedVMEnvironmentTellsModelXcodebuildIsUnavailable() {
    // The whole point of this stanza: stop the model from burning
    // iterations on `xcodebuild`/Xcode-only utilities when only CLT
    // is installed. Asserted on the user-visible phrasing the model
    // will pattern-match against.
    let prompt = Prompts.agentSystemPrompt(
      phase: .develop,
      workingDirectoryPath: "/Users/compass/Compass/Repos/AAAA-BBBB-CCCC-DDDD/worktree",
      executionEnvironment: .sharedVM
    )
    #require(prompt.contains("Compass Shared VM"))
    #require(prompt.contains("Command Line Tools"))
    #require(
      prompt.contains("`xcodebuild`"),
      "Must name the unavailable tool so the model recognises its own failed calls")
    #require(
      prompt.contains("swift build"),
      "Must point at the SwiftPM-native alternative")
    #require(
      prompt.contains(".xcodeproj"),
      "Must call out the failure mode for Xcode-project builds")
  }

  @Test func testExecutionEnvironmentSectionsAreRoutedByDescriptor() {
    #require(Prompts.executionEnvironmentSection(.host).contains("native macOS host"))
    #require(Prompts.executionEnvironmentSection(.sharedVM).contains("Shared VM"))
  }

  @Test func testSharedVMEnvironmentMentionsToolchainToolsAndDockerLimitation() {
    let section = Prompts.executionEnvironmentSection(.sharedVM)
    #require(section.contains("list_toolchains"))
    #require(section.contains("install_toolchain"))
    #require(section.contains("Homebrew"))
    #require(section.contains("Docker is unavailable"))
  }

  @Test func testSharedVMEnvironmentListsInstalledToolchainsWhenProvided() {
    let section = Prompts.executionEnvironmentSection(
      .sharedVM,
      installedToolchainIDs: ["rust", "go"]
    )
    #require(section.contains("rust, go"))
  }

  // MARK: - `.compass/` workspace clarification

  /// Under `.sharedVM` the guest workspace is populated from
  /// `git ls-files`, which omits `.compass/` (gitignored). The agent
  /// was burning iterations calling `read_file` on
  /// `.compass/lessons.md` even though the lessons content is
  /// injected into the user message. Lock down the system-prompt
  /// stanza that tells the model to stop doing that.
  @Test func testSystemPromptTellsAgentNotToReadCompassDirectory() {
    let prompt = Prompts.agentSystemPrompt(
      phase: .develop,
      workingDirectoryPath: "/Users/compass/Compass/Repos/AAAA/worktree",
      executionEnvironment: .sharedVM
    )
    #require(
      prompt.contains("`.compass/` directory belongs to Compass"),
      "system prompt should explain that .compass/ isn't in the workspace"
    )
    #require(
      prompt.contains(".compass/lessons.md"),
      "system prompt should name the lessons file explicitly so the model recognises the pattern"
    )
  }
}