import Foundation
import Testing

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
struct PlanPromptTests {

  @Test func testPlanPromptForbidsWrappingSubmitResultInExtraState() throws {
    let prompt = try makePlanPrompt()
    #require(
      prompt.contains("Do not wrap them in another object"),
      "plan prompt must warn against wrapping in an extra object"
    )
    // The phrase wraps across a line break in the triple-quoted
    // prompt, so check the two halves separately.
    #require(
      prompt.contains("do not nest"),
      "plan prompt must call out nesting as the failure mode"
    )
    #require(
      prompt.contains("another `state` field"),
      "plan prompt must name the `state` field as the trap"
    )
  }

  @Test func testPlanPromptOmitsCompletedFromSubmitResultShape() throws {
    let prompt = try makePlanPrompt()
    #require(
      prompt.contains("Completed plan history is managed by Compass, not by submit_result"),
      "plan prompt must say history is outside submit_result"
    )
    #require(
      prompt.contains("plan_history` tool"),
      "plan prompt must direct the agent to plan_history for prior work"
    )
    #require(
      !prompt.contains("\"completed\""),
      "plan prompt submit_result shape must not include completed entries"
    )
  }

  @Test func testPlanPromptForbidsCdPrefixInVerifyCommand() throws {
    let prompt = try makePlanPrompt()
    #require(
      prompt.contains("never prepend a `cd`"),
      "plan prompt must forbid prepending `cd` to the verify command"
    )
    #require(
      prompt.contains("absolute paths to the working directory"),
      "plan prompt must call out absolute-path injection as the failure mode"
    )
  }

  /// The "submit_result arguments" stanza is the model's primary
  /// reference for the output shape. We previously duplicated it as
  /// a separate "State shape" section, and the redundancy caused the
  /// model to wrap its output in an extra `state:` layer. Pin the
  /// consolidation so the duplicate section doesn't sneak back in.
  @Test func testPlanPromptDoesNotIncludeRedundantStateShapeSection() throws {
    let prompt = try makePlanPrompt()
    #require(
      !prompt.contains("State shape:"),
      "plan prompt previously duplicated the schema as a `State shape:` section; consolidated into submit_result arguments"
    )
  }

  @Test func testHostXcodePlanningIsAbsentUnlessProjectOptInIsEnabled() throws {
    let state = PlanProposal(
      immediate: PlanNext(
        plan: "Build the app",
        verify: "xcodebuild -scheme App build",
        requiresHostXcode: true
      ),
      midTerm: "",
      longTerm: ""
    )

    let prompt = try Prompts.planPrompt(
      state: state,
      completedCount: 0,
      drafts: "",
      feedback: "",
      lessons: "",
      vision: "",
      focus: .feature
    )

    #expect(!prompt.contains("requiresHostXcode"))
    #expect(!prompt.contains("Host Xcode"))
  }

  @Test func testHostXcodePlanningAppearsWhenProjectOptInIsEnabled() throws {
    let prompt = try Prompts.planPrompt(
      state: .empty,
      completedCount: 0,
      drafts: "",
      feedback: "",
      lessons: "",
      vision: "",
      focus: .feature,
      hostXcodeBuildTestEnabled: true
    )

    #expect(prompt.contains("requiresHostXcode"))
    #expect(prompt.contains("host Xcode build/test support"))
    #expect(!prompt.contains("simctl"))
    #expect(!prompt.contains("`open`"))
  }

  /// `.compass/` is supposed to be hidden from the agent — its
  /// contents are injected into the user message instead. The
  /// system prompt names the paths once (to teach the model the
  /// pattern), but every other agent-facing prompt should be
  /// silent about them. Otherwise the agent sees a breadcrumb like
  /// "edits for `.compass/lessons.md`" and feels compelled to
  /// `read_file` that path before producing edits.
  @Test func testPlanPromptDoesNotMentionCompassDirectoryPaths() throws {
    let prompt = try makePlanPrompt()
    #require(
      !prompt.contains(".compass/"),
      "plan prompt must not name `.compass/` paths — the system prompt is the single point of truth for the directory's existence"
    )
    #require(
      !prompt.contains("lessons.md"),
      "plan prompt must not name `lessons.md` — reference the lessons content shown in the prompt instead"
    )
    #require(
      !prompt.contains("drafts.md"),
      "plan prompt must not name `drafts.md` — describe drafts as host-side storage instead"
    )
    #require(
      !prompt.contains("state.json"),
      "plan prompt must not name `state.json` — refer to `## Current planning state` instead"
    )
  }

  @Test func testReflectPromptDoesNotMentionCompassDirectoryPaths() throws {
    let prompt = try Prompts.reflectPrompt(
      state: .empty,
      lessons: "",
      vision: "",
      recentSessions: [],
      iteration: 1
    )
    #require(
      !prompt.contains(".compass/"),
      "reflect prompt must not name `.compass/` paths"
    )
    #require(
      !prompt.contains("lessons.md"),
      "reflect prompt must not name `lessons.md`"
    )
    #require(
      !prompt.contains("state.json"),
      "reflect prompt must not name `state.json`"
    )
  }

  /// The focus block is what biases the planner away from compounding
  /// feature work. Pin both the header and a representative line from
  /// the interaction rules so a future prompt edit that drops the
  /// focus injection surfaces here rather than silently regressing.
  @Test func testPlanPromptIncludesFocusHeaderAndInteractionRules() throws {
    let prompt = try Prompts.planPrompt(
      state: .empty,
      completedCount: 0,
      drafts: "",
      feedback: "",
      lessons: "",
      vision: "",
      focus: .test
    )
    #require(
      prompt.contains("## Focus for this iteration: tests"),
      "plan prompt must include the focus header for the chosen focus"
    )
    #require(
      prompt.contains("Drafts always win"),
      "plan prompt must keep the drafts-win-over-focus rule"
    )
    #require(
      prompt.contains("skipping the head of the queue"),
      "plan prompt must permit the focus to override midTerm order"
    )
  }

  /// Each PlanFocus variant carries its own detail block. If one is
  /// ever dropped from the prompt the planner silently loses the
  /// steer for that category, so pin every variant.
  @Test func testPlanPromptIncludesDetailBlockForEachFocus() throws {
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
      #require(
        prompt.contains("## Focus for this iteration: \(focus.displayName)"),
        "plan prompt missing focus header for \(focus.displayName)"
      )
      #require(
        prompt.contains("Focus details — \(focus.displayName):"),
        "plan prompt missing focus detail block for \(focus.displayName)"
      )
    }
  }

  @Test func testDevelopPromptDoesNotMentionCompassDirectoryPaths() {
    let prompt = Prompts.developPrompt(
      next: PlanNext(
        plan: "p", verify: "swift build", verifyTimeoutMs: nil, estimatedDifficulty: nil),
      lessons: "",
      vision: "",
      attempt: 1,
      priorIssues: []
    )
    #require(
      !prompt.contains(".compass/"),
      "develop prompt must not name `.compass/` paths"
    )
    #require(
      !prompt.contains("lessons.md"),
      "develop prompt must not name `lessons.md`"
    )
    #require(
      !prompt.contains("drafts.md"),
      "develop prompt must not name `drafts.md`"
    )
    #require(
      !prompt.contains("state.json"),
      "develop prompt must not name `state.json`"
    )
  }

  @Test func testDevelopPromptMentionsHostXcodeOnlyWhenEnabledAndRequired() {
    let next = PlanNext(
      plan: "Build the app",
      verify: "xcodebuild -scheme App build",
      requiresHostXcode: true
    )

    let disabled = Prompts.developPrompt(
      next: next,
      lessons: "",
      vision: "",
      attempt: 1,
      priorIssues: []
    )
    let enabled = Prompts.developPrompt(
      next: next,
      lessons: "",
      vision: "",
      attempt: 1,
      priorIssues: [],
      hostXcodeBuildTestEnabled: true
    )

    #expect(!disabled.contains("host_xcode"))
    #expect(enabled.contains("host_xcode"))
    #expect(enabled.contains("build/test checks only"))
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
