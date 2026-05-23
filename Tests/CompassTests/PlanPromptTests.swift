import Foundation
import XCTest

@testable import Compass

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

  /// `.compass/` is supposed to be hidden from the agent — its
  /// contents are injected into the user message instead. The
  /// system prompt names the paths once (to teach the model the
  /// pattern), but every other agent-facing prompt should be
  /// silent about them. Otherwise the agent sees a breadcrumb like
  /// "edits for `.compass/lessons.md`" and feels compelled to
  /// `read_file` that path before producing edits.
  func testPlanPromptDoesNotMentionCompassDirectoryPaths() throws {
    let prompt = try Prompts.planPrompt(
      state: .empty,
      drafts: "",
      feedback: "",
      lessons: "",
      vision: ""
    )
    XCTAssertFalse(
      prompt.contains(".compass/"),
      "plan prompt must not name `.compass/` paths — the system prompt is the single point of truth for the directory's existence"
    )
    XCTAssertFalse(
      prompt.contains("lessons.md"),
      "plan prompt must not name `lessons.md` — reference the lessons content shown in the prompt instead"
    )
    XCTAssertFalse(
      prompt.contains("drafts.md"),
      "plan prompt must not name `drafts.md` — describe drafts as host-side storage instead"
    )
    XCTAssertFalse(
      prompt.contains("state.json"),
      "plan prompt must not name `state.json` — refer to `## Current state` instead"
    )
  }

  func testReflectPromptDoesNotMentionCompassDirectoryPaths() throws {
    let prompt = try Prompts.reflectPrompt(
      state: .empty,
      lessons: "",
      vision: "",
      recentSessions: [],
      iteration: 1
    )
    XCTAssertFalse(
      prompt.contains(".compass/"),
      "reflect prompt must not name `.compass/` paths"
    )
    XCTAssertFalse(
      prompt.contains("lessons.md"),
      "reflect prompt must not name `lessons.md`"
    )
    XCTAssertFalse(
      prompt.contains("state.json"),
      "reflect prompt must not name `state.json`"
    )
  }

  func testDevelopPromptDoesNotMentionCompassDirectoryPaths() {
    let prompt = Prompts.developPrompt(
      next: PlanNext(
        plan: "p", verify: "swift build", verifyTimeoutMs: nil, estimatedDifficulty: nil),
      lessons: "",
      vision: "",
      attempt: 1,
      priorIssues: []
    )
    XCTAssertFalse(
      prompt.contains(".compass/"),
      "develop prompt must not name `.compass/` paths"
    )
    XCTAssertFalse(
      prompt.contains("lessons.md"),
      "develop prompt must not name `lessons.md`"
    )
    XCTAssertFalse(
      prompt.contains("drafts.md"),
      "develop prompt must not name `drafts.md`"
    )
    XCTAssertFalse(
      prompt.contains("state.json"),
      "develop prompt must not name `state.json`"
    )
  }
}
