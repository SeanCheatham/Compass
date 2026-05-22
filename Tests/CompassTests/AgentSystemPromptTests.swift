import Foundation
@testable import Compass
import XCTest

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

    func testPlanPhaseAdvertisesReadOnlyToolsOnly() {
        let prompt = Prompts.agentSystemPrompt(phase: .plan, workingDirectoryPath: "/x")
        XCTAssertTrue(prompt.contains("Inspection tools"))
        XCTAssertFalse(prompt.contains("Mutation tools"))
    }

    func testDevelopPhaseAdvertisesMutationTools() {
        let prompt = Prompts.agentSystemPrompt(phase: .develop, workingDirectoryPath: "/x")
        XCTAssertTrue(prompt.contains("Mutation tools"))
        XCTAssertTrue(prompt.contains("write_file"))
        XCTAssertTrue(prompt.contains("bash"))
    }

    // MARK: - Execution environment

    func testHostEnvironmentIsTheDefault() {
        let prompt = Prompts.agentSystemPrompt(phase: .develop, workingDirectoryPath: "/x")
        XCTAssertTrue(prompt.contains("native macOS host"))
        XCTAssertFalse(prompt.contains("Shared VM"))
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
        XCTAssertTrue(prompt.contains("`xcodebuild`"),
                      "Must name the unavailable tool so the model recognises its own failed calls")
        XCTAssertTrue(prompt.contains("swift build"),
                      "Must point at the SwiftPM-native alternative")
        XCTAssertTrue(prompt.contains(".xcodeproj"),
                      "Must call out the failure mode for Xcode-project builds")
    }

    func testExecutionEnvironmentSectionsAreRoutedByDescriptor() {
        XCTAssertTrue(Prompts.executionEnvironmentSection(.host).contains("native macOS host"))
        XCTAssertTrue(Prompts.executionEnvironmentSection(.sharedVM).contains("Shared VM"))
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
