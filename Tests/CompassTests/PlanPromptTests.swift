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
    let prompt = try makePlanPrompt()
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

  func testPlanPromptOmitsCompletedFromSubmitResultShape() throws {
    let prompt = try makePlanPrompt()
    XCTAssertTrue(
      prompt.contains("Completed plan history is managed by Compass, not by submit_result"),
      "plan prompt must say history is outside submit_result"
    )
    XCTAssertTrue(
      prompt.contains("plan_history` tool"),
      "plan prompt must direct the agent to plan_history for prior work"
    )
    XCTAssertFalse(
      prompt.contains("\"completed\""),
      "plan prompt submit_result shape must not include completed entries"
    )
  }

  func testPlanPromptForbidsCdPrefixInVerifyCommand() throws {
    let prompt = try makePlanPrompt()
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
    let prompt = try makePlanPrompt()
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
    let prompt = try makePlanPrompt()
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
      "plan prompt must not name `state.json` — refer to `## Current planning state` instead"
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

  /// The focus block is what biases the planner away from compounding
  /// feature work. Pin both the header and a representative line from
  /// the interaction rules so a future prompt edit that drops the
  /// focus injection surfaces here rather than silently regressing.
  func testPlanPromptIncludesFocusHeaderAndInteractionRules() throws {
    let prompt = try Prompts.planPrompt(
      state: .empty,
      completedCount: 0,
      drafts: "",
      feedback: "",
      lessons: "",
      vision: "",
      focus: .test
    )
    XCTAssertTrue(
      prompt.contains("## Focus for this iteration: tests"),
      "plan prompt must include the focus header for the chosen focus"
    )
    XCTAssertTrue(
      prompt.contains("Drafts always win"),
      "plan prompt must keep the drafts-win-over-focus rule"
    )
    XCTAssertTrue(
      prompt.contains("skipping the head of the queue"),
      "plan prompt must permit the focus to override midTerm order"
    )
  }

  /// Each PlanFocus variant carries its own detail block. If one is
  /// ever dropped from the prompt the planner silently loses the
  /// steer for that category, so pin every variant.
  func testPlanPromptIncludesDetailBlockForEachFocus() throws {
    for focus in PlanFocus.allCases {
      let prompt = try Prompts.planPrompt(
        state: .empty,
        completedCount: 0,
        drafts: "",
        feedback: "",
        lessons: "",
        vision: "",
        focus: focus
      )
      XCTAssertTrue(
        prompt.contains("## Focus for this iteration: \(focus.displayName)"),
        "plan prompt missing focus header for \(focus.displayName)"
      )
      XCTAssertTrue(
        prompt.contains("Focus details — \(focus.displayName):"),
        "plan prompt missing focus detail block for \(focus.displayName)"
      )
    }
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

  private func makePlanPrompt() throws -> String {
    try Prompts.planPrompt(
      state: .empty,
      completedCount: 0,
      drafts: "",
      feedback: "",
      lessons: "",
      vision: "",
      focus: .feature
    )
  }
}
