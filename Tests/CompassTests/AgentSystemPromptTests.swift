import Foundation
import XCTest

@testable import Compass

/// The agent system prompt has to carry the working directory the agent
/// is operating in, otherwise the model invents paths from `pwd`/`find`
/// output and trips `AgentToolContext.resolvePath`'s sandbox guard when
/// the guest and host paths diverge. Lock that in.
final class AgentSystemPromptTests: XCTestCase {

  func testSystemPromptEmbedsHostWorkingDirectory() {
    let prompt = Prompts.agentSystemPrompt(
      phase: .develop,
      workingDirectoryPath: "/Users/dev/projects/widget"
    )
    XCTAssertTrue(
      prompt.contains("Working directory: /Users/dev/projects/widget"),
      "prompt should pin the cwd: \(prompt)"
    )
  }

  func testSystemPromptEmbedsGuestWorkingDirectoryForSharedVMRuns() {
    // When the Shared VM is the active backend, Compass passes the
    // guest workspace path here. Verify it gets rendered verbatim so
    // the model orients itself in the guest namespace, not the host.
    let prompt = Prompts.agentSystemPrompt(
      phase: .develop,
      workingDirectoryPath: "/Users/compass/Compass/Repos/AAAA-BBBB-CCCC-DDDD/worktree"
    )
    XCTAssertTrue(prompt.contains("/Users/compass/Compass/Repos/AAAA-BBBB-CCCC-DDDD/worktree"))
  }

  func testPlanPhaseAdvertisesBashWithoutMutationTools() {
    let prompt = Prompts.agentSystemPrompt(phase: .plan, workingDirectoryPath: "/x")
    XCTAssertTrue(prompt.contains("File tools"))
    XCTAssertTrue(prompt.contains("Codemap tools"))
    XCTAssertTrue(
      prompt.contains("bash"),
      "Plan must see `bash` so it can ground decisions in real build/test output")
    XCTAssertTrue(
      prompt.contains("do not mutate tracked files"),
      "Plan prompt must state read-only intent for bash")
    XCTAssertFalse(prompt.contains("Mutation tools"))
    XCTAssertFalse(
      prompt.contains("write_file"),
      "Plan must not be told about write_file")
    XCTAssertTrue(
      prompt.contains("plan_history"),
      "Plan must see plan_history for Compass-managed completed iterations")
  }

  func testReflectPhaseAdvertisesBashWithoutMutationTools() {
    let prompt = Prompts.agentSystemPrompt(phase: .reflect, workingDirectoryPath: "/x")
    XCTAssertTrue(
      prompt.contains("bash"),
      "Reflect must see `bash` so it can probe the project during course-correction")
    XCTAssertTrue(
      prompt.contains("do not mutate tracked files"),
      "Reflect prompt must state read-only intent for bash")
    XCTAssertFalse(prompt.contains("Mutation tools"))
    XCTAssertFalse(
      prompt.contains("write_file"),
      "Reflect must not be told about write_file")
  }

  func testDevelopPhaseAdvertisesWriteTools() {
    let prompt = Prompts.agentSystemPrompt(phase: .develop, workingDirectoryPath: "/x")
    XCTAssertTrue(prompt.contains("Write tools"))
    XCTAssertTrue(prompt.contains("write_file"))
    XCTAssertTrue(prompt.contains("bash"))
  }

  func testCriticPhaseAdvertisesBashButNotWriteTools() {
    let prompt = Prompts.agentSystemPrompt(phase: .critic, workingDirectoryPath: "/x")
    XCTAssertTrue(
      prompt.contains("bash"),
      "Critic must see `bash` for re-running tests / linters")
    XCTAssertFalse(
      prompt.contains("Write tools"),
      "Critic must not be told about write/edit tools")
    XCTAssertFalse(
      prompt.contains("write_file"),
      "Critic must not be told about write_file")
    XCTAssertTrue(
      prompt.contains("do not mutate the working tree"),
      "Critic prompt must state read-only intent for bash")
  }

  func testDelegateToolIsAdvertisedInEveryPhase() {
    // The `delegate` tool is on every phase's registry; the system
    // prompt has to name it or the model won't reach for it.
    for phase in AgentPhase.allCases {
      let prompt = Prompts.agentSystemPrompt(phase: phase, workingDirectoryPath: "/x")
      XCTAssertTrue(
        prompt.contains("delegate"),
        "phase \(phase) should name `delegate` so the model uses sub-agents")
    }
  }

  /// Tools registered in the schema but absent from the system prompt
  /// rarely get called — chat models heavily prefer tools the prompt
  /// acknowledges, so the codemap tools have to be mentioned in every
  /// phase that has access to them.
  func testCodemapToolsAreAdvertisedInEveryPhase() {
    for phase in AgentPhase.allCases {
      let prompt = Prompts.agentSystemPrompt(phase: phase, workingDirectoryPath: "/x")
      XCTAssertTrue(
        prompt.contains("find_symbol"),
        "phase \(phase) should name find_symbol so the model uses it instead of grepping for declarations"
      )
      XCTAssertTrue(prompt.contains("outline"), "phase \(phase) should name outline")
      XCTAssertTrue(prompt.contains("summary"), "phase \(phase) should name summary")
      XCTAssertTrue(prompt.contains("list_files"), "phase \(phase) should name list_files")
      XCTAssertTrue(prompt.contains("importers_of"), "phase \(phase) should name importers_of")
    }
  }

  // MARK: - Execution environment

  func testSharedVMEnvironmentIsTheDefault() {
    let prompt = Prompts.agentSystemPrompt(phase: .develop, workingDirectoryPath: "/x")
    XCTAssertTrue(prompt.contains("Compass Shared VM"))
    XCTAssertFalse(prompt.contains("native macOS host"))
  }

  func testSharedVMEnvironmentTellsModelXcodebuildIsUnavailable() {
    // The whole point of this stanza: stop the model from burning
    // iterations on `xcodebuild`/Xcode-only utilities when only CLT
    // is installed. Asserted on the user-visible phrasing the model
    // will pattern-match against.
    let prompt = Prompts.agentSystemPrompt(
      phase: .develop,
      workingDirectoryPath: "/Users/compass/Compass/Repos/AAAA-BBBB-CCCC-DDDD/worktree",
      executionEnvironment: .sharedVM
    )
    XCTAssertTrue(prompt.contains("Compass Shared VM"))
    XCTAssertTrue(prompt.contains("Command Line Tools"))
    XCTAssertTrue(
      prompt.contains("`xcodebuild`"),
      "Must name the unavailable tool so the model recognises its own failed calls")
    XCTAssertTrue(
      prompt.contains("swift build"),
      "Must point at the SwiftPM-native alternative")
    XCTAssertTrue(
      prompt.contains(".xcodeproj"),
      "Must call out the failure mode for Xcode-project builds")
  }

  func testExecutionEnvironmentSectionsAreRoutedByDescriptor() {
    XCTAssertTrue(Prompts.executionEnvironmentSection(.host).contains("native macOS host"))
    XCTAssertTrue(Prompts.executionEnvironmentSection(.sharedVM).contains("Shared VM"))
  }

  func testSharedVMEnvironmentMentionsToolchainToolsAndDockerLimitation() {
    let section = Prompts.executionEnvironmentSection(.sharedVM)
    XCTAssertTrue(section.contains("list_toolchains"))
    XCTAssertTrue(section.contains("install_toolchain"))
    XCTAssertTrue(section.contains("Homebrew"))
    XCTAssertTrue(section.contains("Docker is unavailable"))
  }

  func testSharedVMEnvironmentListsInstalledToolchainsWhenProvided() {
    let section = Prompts.executionEnvironmentSection(
      .sharedVM,
      installedToolchainIDs: ["rust", "go"]
    )
    XCTAssertTrue(section.contains("rust, go"))
  }

  // MARK: - `.compass/` workspace clarification

  /// Under `.sharedVM` the guest workspace is populated from
  /// `git ls-files`, which omits `.compass/` (gitignored). The agent
  /// was burning iterations calling `read_file` on
  /// `.compass/lessons.md` even though the lessons content is
  /// injected into the user message. Lock down the system-prompt
  /// stanza that tells the model to stop doing that.
  func testSystemPromptTellsAgentNotToReadCompassDirectory() {
    let prompt = Prompts.agentSystemPrompt(
      phase: .develop,
      workingDirectoryPath: "/Users/compass/Compass/Repos/AAAA/worktree",
      executionEnvironment: .sharedVM
    )
    XCTAssertTrue(
      prompt.contains("`.compass/` directory belongs to Compass"),
      "system prompt should explain that .compass/ isn't in the workspace"
    )
    XCTAssertTrue(
      prompt.contains(".compass/lessons.md"),
      "system prompt should name the lessons file explicitly so the model recognises the pattern"
    )
  }
}
