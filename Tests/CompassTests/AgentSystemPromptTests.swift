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
            workingDirectoryPath: "/opt/compass/workspaces/dev-XXXX/worktree"
        )
        XCTAssertTrue(prompt.contains("/opt/compass/workspaces/dev-XXXX/worktree"))
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
}
