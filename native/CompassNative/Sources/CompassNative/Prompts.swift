import Foundation

enum Prompts {
    static let planSchema = """
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
    }
    """

    static let developSchema = """
    {
      "type": "object",
      "additionalProperties": false,
      "required": ["status", "summary", "feedback", "bypassVerify"],
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
        You are the Plan agent for CompassNative, a macOS-native prototype of Compass.

        CompassNative is Codex-only. There is no Claude runtime, no Claude Agent SDK,
        and no embedded Codex SDK. This app shells out to `codex exec` for each
        agent turn.

        Your job is to choose exactly one concrete next implementation increment
        for a separate Develop pass. You have read-only access to the repository.
        Do not edit files. Return only the structured PlanState requested by the
        output schema.

        Planning rules:
        - Ground the plan in the repository before choosing work.
        - Pick one commit-sized `immediate` with a real verify command.
        - Use `immediate: null` only when the project is genuinely complete.
        - Append to `completed` only when feedback says the previous immediate
          shipped.
        - Keep `midTerm` to the next 3-7 useful increments.
        - Keep `longTerm` strategic and stable.
        - Never choose `true` as the verify command.

        State shape:
        {
          "completed": ["one-line shipped summaries"],
          "immediate": {
            "plan": "markdown plan for one implementation increment",
            "verify": "shell command run from the repo root",
            "verifyTimeoutMs": 600000,
            "estimatedDifficulty": "low|medium|high"
          } | null,
          "midTerm": "markdown",
          "longTerm": "markdown"
        }

        ## Current state.json
        ```json
        \(stateJSON)
        ```

        ## Drafts from the user
        \(fencedOrEmpty(drafts, empty: "_(no new drafts)_"))

        ## Feedback from the previous Develop pass
        \(fencedOrEmpty(feedback, empty: "_(no feedback)_"))

        ## Lessons
        \(fencedOrEmpty(lessons, empty: "_(no lessons yet)_"))

        ## Vision
        \(fencedOrEmpty(vision, empty: "_(no vision set)_"))

        Return the full updated PlanState as JSON matching the output schema.
        """
    }

    static func developPrompt(next: PlanNext, lessons: String, vision: String) -> String {
        """
        You are the Develop agent for CompassNative, a macOS-native prototype of
        Compass. CompassNative is Codex-only and invokes you through `codex exec`.

        Implement exactly the plan below. You may read, edit, run shell commands,
        run tests, and commit using git. Keep the change scoped to the plan.

        Hard rules:
        - Do not edit `.compass/state.json` or `.compass/drafts.md`.
        - Do not push, rebase, or use destructive git operations.
        - Run the verify command before finishing.
        - Commit the finished change if there are code changes.
        - Leave the working tree clean, or explain why you are blocked.
        - Return only the structured JSON requested by the output schema.

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

        Final response fields:
        - `status`: `succeeded`, `blocked`, or `failed`.
        - `summary`: concise human summary of what happened.
        - `feedback`: short handoff note for the next planning pass.
        - `bypassVerify`: true only if the verify command itself is wrong or out of scope.
        """
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
