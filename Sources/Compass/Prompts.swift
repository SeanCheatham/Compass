import Foundation

enum Prompts {
    static let planSchema = """
    {
      "type": "object",
      "additionalProperties": false,
      "required": ["state", "lessonEdits"],
      "properties": {
        "state": {
          "type": "object",
          "additionalProperties": false,
          "required": ["completed", "immediate", "midTerm", "longTerm"],
          "properties": {
            "completed": {
              "type": "array",
              "items": { "type": "string" }
            },
            "immediate": {
              "anyOf": [
                {
                  "type": "object",
                  "additionalProperties": false,
                  "required": ["plan", "verify", "verifyTimeoutMs", "estimatedDifficulty"],
                  "properties": {
                    "plan": { "type": "string" },
                    "verify": { "type": "string" },
                    "verifyTimeoutMs": {
                      "anyOf": [
                        { "type": "integer", "minimum": 1 },
                        { "type": "null" }
                      ]
                    },
                    "estimatedDifficulty": {
                      "anyOf": [
                        {
                          "type": "string",
                          "enum": ["low", "medium", "high"]
                        },
                        { "type": "null" }
                      ]
                    }
                  }
                },
                { "type": "null" }
              ]
            },
            "midTerm": { "type": "string" },
            "longTerm": { "type": "string" }
          }
        },
        "lessonEdits": {
          "type": "array",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": ["find", "replace", "replaceAll"],
            "properties": {
              "find": { "type": "string" },
              "replace": { "type": "string" },
              "replaceAll": {
                "anyOf": [
                  { "type": "boolean" },
                  { "type": "null" }
                ]
              }
            }
          }
        }
      }
    }
    """

    static let developSchema = """
    {
      "type": "object",
      "additionalProperties": false,
      "required": ["status", "summary", "feedback", "bypassVerify", "lessonEdits"],
      "properties": {
        "status": {
          "type": "string",
          "enum": ["succeeded", "blocked", "failed"]
        },
        "summary": { "type": "string" },
        "feedback": { "type": "string" },
        "bypassVerify": {
          "anyOf": [
            { "type": "boolean" },
            { "type": "null" }
          ]
        },
        "lessonEdits": {
          "type": "array",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": ["find", "replace", "replaceAll"],
            "properties": {
              "find": { "type": "string" },
              "replace": { "type": "string" },
              "replaceAll": {
                "anyOf": [
                  { "type": "boolean" },
                  { "type": "null" }
                ]
              }
            }
          }
        }
      }
    }
    """

    static let reflectSchema = """
    {
      "type": "object",
      "additionalProperties": false,
      "required": ["state", "summary", "lessonEdits"],
      "properties": {
        "state": {
          "anyOf": [
            {
              "type": "object",
              "additionalProperties": false,
              "required": ["completed", "immediate", "midTerm", "longTerm"],
              "properties": {
                "completed": {
                  "type": "array",
                  "items": { "type": "string" }
                },
                "immediate": {
                  "anyOf": [
                    {
                      "type": "object",
                      "additionalProperties": false,
                      "required": ["plan", "verify", "verifyTimeoutMs", "estimatedDifficulty"],
                      "properties": {
                        "plan": { "type": "string" },
                        "verify": { "type": "string" },
                        "verifyTimeoutMs": {
                          "anyOf": [
                            { "type": "integer", "minimum": 1 },
                            { "type": "null" }
                          ]
                        },
                        "estimatedDifficulty": {
                          "anyOf": [
                            {
                              "type": "string",
                              "enum": ["low", "medium", "high"]
                            },
                            { "type": "null" }
                          ]
                        }
                      }
                    },
                    { "type": "null" }
                  ]
                },
                "midTerm": { "type": "string" },
                "longTerm": { "type": "string" }
              }
            },
            { "type": "null" }
          ]
        },
        "summary": { "type": "string" },
        "lessonEdits": {
          "type": "array",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": ["find", "replace", "replaceAll"],
            "properties": {
              "find": { "type": "string" },
              "replace": { "type": "string" },
              "replaceAll": {
                "anyOf": [
                  { "type": "boolean" },
                  { "type": "null" }
                ]
              }
            }
          }
        }
      }
    }
    """

    static func planPrompt(
        state: PlanState,
        drafts: String,
        feedback: String,
        lessons: String,
        vision: String
    ) throws -> String {
        let stateJSON = try CompassWorkspace.encodeState(state)
        return """
        You are the Plan agent for Compass, a macOS-native agent iteration app.

        Compass talks to an OpenAI-compatible chat completions endpoint and
        dispatches tool calls you make. Treat the structured JSON you return as
        Compass's state and lesson update contract.

        Your job is to choose exactly one concrete next implementation increment
        for a separate Develop pass. You have read-only access to the repository.
        Do not edit files. End by calling the `submit_result` tool with the
        arguments described below.

        Planning rules:
        - Start from the current state exactly as given. Preserve existing
          `completed`, `midTerm`, and `longTerm` unless this iteration has a
          concrete reason to change them.
        - Never reset or drop completed history.
        - Ground the plan in the repository before choosing work.
        - Pick one commit-sized `immediate` with a real verify command that proves
          the important behavior. If there are no relevant tests, use build or
          typecheck as the fallback.
        - The verify command runs with the repo working tree already as its
          current directory. Write it as a plain command — e.g. `swift build`,
          `swift test`, `make check` — and never prepend a `cd` or include
          absolute paths to the working directory. Those paths get saved to
          state and rot the moment the working directory changes.
        - Use `immediate: null` only when the project is genuinely complete:
          every goal is shipped, `midTerm` and `longTerm` are exhausted, and you
          cannot identify a useful next increment.
        - Append to `completed` only when feedback says the previous immediate
          shipped.
        - If feedback reports a blocker, plan the next smallest step that resolves
          it or rescope so Develop can make progress.
        - If drafts are empty, promote a useful `midTerm` item or originate a plan
          from the repo, lessons, completed history, and long-term arc.
        - Keep `midTerm` to the next 3-7 useful increments.
        - Keep `longTerm` strategic and stable; revise it only when something
          material changes.
        - Never choose placeholder verify commands like `true`, `not-running-tests`,
          `none`, or `n/a`.
        - Never write code, run tests, or commit from Plan.

        Lesson edit rules:
        - `lessonEdits` is an array of exact find/replace edits for
          `.compass/lessons.md`. Use `[]` when you have no lesson change.
        - `find` must match the current lessons text exactly. If it appears more
          than once, include more surrounding context or set `replaceAll` to true.
        - To append a lesson, replace the final relevant block with that block
          plus the new bullet. If lessons.md is empty, use `find: ""` and
          `replace` set to the initial contents.
        - Lessons are durable gotchas and conventions, not routine status logs.

        submit_result arguments — call the tool with EXACTLY this shape.
        The top-level object has exactly two keys: `state` and
        `lessonEdits`. Do not wrap them in another object; do not nest
        the result under another `state` field.
        {
          "state": {
            "completed": ["one-line shipped summaries"],
            "immediate": {
              "plan": "markdown plan for one implementation increment",
              "verify": "shell command — no `cd` prefix, no absolute paths",
              "verifyTimeoutMs": 600000,
              "estimatedDifficulty": "low|medium|high"
            } | null,
            "midTerm": "markdown",
            "longTerm": "markdown"
          },
          "lessonEdits": [
            {
              "find": "exact current text",
              "replace": "replacement text",
              "replaceAll": false
            }
          ]
        }

        ## Current state.json
        ```json
        \(stateJSON)
        ```

        ## Drafts from the user
        The app snapshotted these drafts immediately before invoking you and
        cleared `.compass/drafts.md`. Drafts arriving during this run will be
        picked up next iteration.

        \(fencedOrEmpty(drafts, empty: "_(no new drafts)_"))

        ## Feedback from the previous Develop pass
        This is the latest non-empty Develop feedback from a prior completed
        session. Use it to decide whether to append to `completed`, fix a blocker,
        or continue from state alone.

        \(fencedOrEmpty(feedback, empty: "_(no feedback)_"))

        ## Lessons
        \(fencedOrEmpty(lessons, empty: "_(no lessons yet)_"))

        ## Vision
        \(fencedOrEmpty(vision, empty: "_(no vision set)_"))

        When you have decided the next increment, call submit_result with the
        arguments shape above.
        """
    }

    static func reflectPrompt(
        state: PlanState,
        lessons: String,
        vision: String,
        recentSessions: [SessionRecord],
        iteration: Int
    ) throws -> String {
        let stateJSON = try CompassWorkspace.encodeState(state)
        let sessionsJSON = try encodeSessions(recentSessions)
        return """
        You are the Reflect agent for Compass, a macOS-native agent iteration
        app. Compass talks to an OpenAI-compatible chat completions endpoint
        and dispatches tool calls you make.

        Run a course-correction pass for iteration \(iteration). You have
        read-only access to the repository. Decide whether the project is still
        on course toward the vision.

        Finish by calling the `submit_result` tool with these arguments:
        - `state`: null if everything is on course.
        - `state`: a full PlanState if `midTerm` and/or `longTerm` should be
          rewritten. Preserve existing `completed` and `immediate` unless there
          is a concrete reason to adjust them.
        - `summary`: a concise explanation of the reflection result.
        - `lessonEdits`: exact find/replace edits for `.compass/lessons.md`, or
          `[]` when nothing durable should be recorded.

        Lesson edit rules:
        - `find` must match the current lessons text exactly. If it appears more
          than once, include more surrounding context or set `replaceAll` to true.
        - To append a lesson, replace the final relevant block with that block
          plus the new bullet. If lessons.md is empty, use `find: ""` and
          `replace` set to the initial contents.
        - Lessons are durable process guidance, not routine status logs.

        Keep this tight. Do not rewrite state defensively.

        ## Current state.json
        ```json
        \(stateJSON)
        ```

        ## Recent sessions, most recent first
        ```json
        \(sessionsJSON)
        ```

        ## Lessons
        \(fencedOrEmpty(lessons, empty: "_(no lessons yet)_"))

        ## Vision
        \(fencedOrEmpty(vision, empty: "_(no vision set)_"))
        """
    }

    static func developPrompt(
        next: PlanNext,
        lessons: String,
        vision: String,
        attempt: Int,
        priorIssues: [String]
    ) -> String {
        """
        You are the Develop agent for Compass, a macOS-native agent iteration
        app. Compass talks to an OpenAI-compatible chat completions endpoint
        and dispatches tool calls you make.

        Implement exactly the plan below. You may read, edit, run shell commands,
        run tests, and commit using git. Keep the change scoped to the plan.

        Hard rules:
        - Do not edit `.compass/state.json` or `.compass/drafts.md`.
        - Do not edit `.compass/lessons.md` directly; pass `lessonEdits` in the
          submit_result arguments instead so the app can apply them to the
          main Compass workspace.
        - Do not push, rebase, or use destructive git operations.
        - Run the verify command before finishing.
        - Commit the finished change if there are code changes.
        - Leave the working tree clean, or explain why you are blocked.
        - End the phase by calling `submit_result` exactly once.

        Lesson edit rules:
        - `lessonEdits` is an array of exact find/replace edits for
          `.compass/lessons.md`. Use `[]` when you have no lesson change.
        - `find` must match the current lessons text exactly. If it appears more
          than once, include more surrounding context or set `replaceAll` to true.
        - To append a lesson, replace the final relevant block with that block
          plus the new bullet. If lessons.md is empty, use `find: ""` and
          `replace` set to the initial contents.
        - Lessons are durable gotchas and conventions, not routine status logs.

        Develop workspace:
        You are operating directly in the repository's working tree on the
        user's current branch. Commit your changes from this working
        directory once the work is complete; the app does not stage a
        separate branch on your behalf.

        \(developAttemptInstructions(attempt: attempt, priorIssues: priorIssues))

        ## Plan to implement
        \(next.plan)

        ## Verify command
        ```bash
        \(next.verify)
        ```

        ## Lessons
        \(fencedOrEmpty(lessons, empty: "_(no lessons yet)_"))

        ## Vision
        \(fencedOrEmpty(vision, empty: "_(no vision set)_"))

        submit_result arguments:
        - `status`: `succeeded`, `blocked`, or `failed`.
        - `summary`: concise human summary of what happened.
        - `feedback`: short handoff note for the next planning pass.
        - `bypassVerify`: true only if the verify command itself is wrong or out of scope.
        - `lessonEdits`: exact find/replace edits to lessons.md, or [].
        """
    }

    private static func developAttemptInstructions(attempt: Int, priorIssues: [String]) -> String {
        if attempt <= 1 {
            return """
            Workflow:
            1. Explore as needed to understand the surrounding code.
            2. Implement the plan and keep the change scoped.
            3. Run the verify command and fix failures.
            4. Commit the finished change.
            5. Call submit_result with a useful feedback handoff.
            """
        }

        let issues = priorIssues.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n\n")
        return """
        Retry \(attempt):
        Your previous attempt left these post-check failures unresolved:

        \(issues)

        Fix them now. Do not expand scope. Finish with verify passing, a clean
        working tree, committed changes if any, and a submit_result call
        carrying the feedback handoff.
        """
    }

    /// System message prepended to the per-phase user prompt. Tells the
    /// model which tools are on the table for this phase and how to end
    /// the turn via `submit_result`. The user prompt still carries the
    /// per-phase instructions and the output schema.
    /// Coarse description of where the agent's tools execute. Drives the
    /// "what tooling can I assume is installed?" section of the system
    /// prompt so the model doesn't burn iterations reaching for things
    /// the environment doesn't have.
    enum ExecutionEnvironmentDescriptor {
        case host
        case sharedVM
    }

    static func agentSystemPrompt(
        phase: AgentPhase,
        workingDirectoryPath: String,
        executionEnvironment: ExecutionEnvironmentDescriptor = .host
    ) -> String {
        let readOnlyTools = "read_file, ls, grep, glob"
        let writeTools = "write_file, edit_file, bash"
        let toolList: String
        switch phase {
        case .plan, .reflect:
            toolList = "- Inspection tools: \(readOnlyTools).\n- This phase is read-only. The Develop phase has the write tools — do not request them here."
        case .develop:
            toolList = "- Inspection tools: \(readOnlyTools).\n- Mutation tools: \(writeTools)."
        }
        return """
        You are operating inside the Compass agent runtime. Compass talks to
        an OpenAI-compatible chat completions endpoint and dispatches the
        tool calls you make.

        Working directory: \(workingDirectoryPath)
        All tool paths are resolved against this directory. Relative paths
        are recommended; if you use absolute paths they must resolve inside
        the working directory.

        Compass workspace state:
        The `.compass/` directory belongs to Compass and is gitignored, so
        it isn't present in your working tree. Everything you'd want from
        it — current state, lessons, drafts, prior feedback — is injected
        verbatim into the user message below. Treat that injected content
        as authoritative; do not try to `read_file` `.compass/lessons.md`,
        `.compass/state.json`, `.compass/drafts.md`, or any other
        `.compass/*` path. Pass lesson updates back through the
        `lessonEdits` field on `submit_result` and Compass applies them
        host-side.

        \(executionEnvironmentSection(executionEnvironment))

        Tools available to you this turn:
        \(toolList)

        End this phase by calling the `submit_result` tool exactly once. Its
        arguments object MUST match the output schema described in the user
        message. Do not put the structured payload in a regular assistant
        message — always call the tool. The phase ends the moment you call
        it; no further messages will be processed.
        """
    }

    /// Renders the "where am I running?" stanza for the agent system prompt.
    /// Kept separate so tests can lock down the wording byte-for-byte —
    /// changes to it directly affect tool-call efficiency.
    static func executionEnvironmentSection(_ env: ExecutionEnvironmentDescriptor) -> String {
        switch env {
        case .host:
            return """
            Execution environment: native macOS host. Whatever the user has
            installed on this machine is available — assume nothing specific
            and probe with `which` / `command -v` when you need to confirm a
            tool exists.
            """
        case .sharedVM:
            return """
            Execution environment: Compass Shared VM (headless macOS guest).
            Xcode Command Line Tools are installed — `swift`, `clang`, `git`,
            `make`, `llvm`, and the macOS SDK are available. The full Xcode
            IDE is NOT installed, so `xcodebuild`, Interface Builder, the
            iOS/watchOS/tvOS SDKs, and the Simulator are unavailable.
            For SwiftPM packages, build and test with `swift build` /
            `swift test`. For `.xcodeproj`-based projects there is no
            in-VM equivalent — those builds must happen on the host route
            (re-run with the Native macOS execution environment).
            Homebrew is NOT installed by default. Network egress to Apple's
            CDNs (softwareupdate, swift package fetch from github.com) works.
            """
        }
    }

    private static func encodeSessions(_ sessions: [SessionRecord]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(sessions)
        return String(decoding: data, as: UTF8.self)
    }

    private static func fencedOrEmpty(_ text: String, empty: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return empty }
        return """
        ```
        \(trimmed)
        ```
        """
    }
}
