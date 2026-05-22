import Foundation
@testable import Compass
import XCTest

/// The Plan prompt has two failure modes worth pinning byte-for-byte:
///
///   * The agent wraps its `submit_result` payload in an extra `state:`
///     layer, which causes `PlanRunResult.init(from:)` to fail with a
///     "data couldn't be read because it is missing" decode error. The
///     prompt's `submit_result arguments` stanza spells out the
///     top-level shape and explicitly tells the model not to nest.
///
///   * The agent bakes an absolute `cd <workspace>` into the verify
///     command, which gets persisted to state.json and rots the moment
///     the workspace path changes. The planning rules say verify runs
///     with the workspace already as its cwd and no `cd` prefix is
///     allowed.
///
/// These tests assert on the wording the model pattern-matches against
/// so a future prompt edit that softens or drops them surfaces here.
final class PlanPromptTests: XCTestCase {

    func testPlanPromptForbidsWrappingSubmitResultInExtraState() throws {
        let prompt = try Prompts.planPrompt(
            state: .empty,
            drafts: "",
            feedback: "",
            lessons: "",
            vision: ""
        )
        XCTAssertTrue(
            prompt.contains("Do not wrap them in another object"),
            "plan prompt must warn against wrapping in an extra object"
        )
        // The phrase wraps across a line break in the triple-quoted
        // prompt, so check the two halves separately.
        XCTAssertTrue(
            prompt.contains("do not nest"),
            "plan prompt must call out nesting as the failure mode"
        )
        XCTAssertTrue(
            prompt.contains("another `state` field"),
            "plan prompt must name the `state` field as the trap"
        )
    }

    func testPlanPromptForbidsCdPrefixInVerifyCommand() throws {
        let prompt = try Prompts.planPrompt(
            state: .empty,
            drafts: "",
            feedback: "",
            lessons: "",
            vision: ""
        )
        XCTAssertTrue(
            prompt.contains("never prepend a `cd`"),
            "plan prompt must forbid prepending `cd` to the verify command"
        )
        XCTAssertTrue(
            prompt.contains("absolute paths to the working directory"),
            "plan prompt must call out absolute-path injection as the failure mode"
        )
    }

    /// The "submit_result arguments" stanza is the model's primary
    /// reference for the output shape. We previously duplicated it as
    /// a separate "State shape" section, and the redundancy caused the
    /// model to wrap its output in an extra `state:` layer. Pin the
    /// consolidation so the duplicate section doesn't sneak back in.
    func testPlanPromptDoesNotIncludeRedundantStateShapeSection() throws {
        let prompt = try Prompts.planPrompt(
            state: .empty,
            drafts: "",
            feedback: "",
            lessons: "",
            vision: ""
        )
        XCTAssertFalse(
            prompt.contains("State shape:"),
            "plan prompt previously duplicated the schema as a `State shape:` section; consolidated into submit_result arguments"
        )
    }
}
