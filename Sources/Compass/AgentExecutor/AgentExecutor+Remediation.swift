import Foundation
import OpenAI

extension AgentExecutor {
  // MARK: - Invalid-tool-arguments remediation

  /// Wording for the user-visible event and the user-side nudge
  /// appended to `messages` when a tool call arrived with invalid JSON
  /// arguments. Split out so the wording stays unit-testable without
  /// needing to drive the full streaming loop.
  struct InvalidToolArgumentsNudge: Equatable {
    var eventText: String
    var eventDetail: String
    var userMessage: String
  }

  /// Build the remediation copy for a malformed `submit_result` turn.
  /// `finishReason == "length"` is the canonical truncation signal;
  /// providers that omit it still produce invalid JSON the same way
  /// (mid-token cutoff), so we fall back to a generic "args wouldn't
  /// parse" nudge that nudges the model toward shorter output.
  static func submitResultValidationNudge(
    for error: Error,
    phase: AgentPhase? = nil
  ) -> InvalidToolArgumentsNudge {
    if let error = error as? PlanTransitionValidationError {
      return invalidPlanTransitionNudge(error: error)
    }
    if let error = error as? DevelopFeedbackValidationError {
      return invalidDevelopFeedbackNudge(error: error)
    }
    if let error = error as? DevelopVerifyBypassValidationError {
      return invalidDevelopVerifyBypassNudge(error: error)
    }
    if let error = error as? CriticFeedbackValidationError {
      return invalidCriticFeedbackNudge(error: error)
    }
    if error is DecodingError {
      return invalidSubmitResultDecodeNudge(
        errorMessage: decodingErrorMessage(error),
        phase: phase
      )
    }
    return invalidLessonEditsNudge(errorMessage: error.localizedDescription)
  }

  static func decodingErrorMessage(_ error: Error) -> String {
    guard let decoding = error as? DecodingError else {
      return error.localizedDescription
    }
    switch decoding {
    case .keyNotFound(let key, let context):
      let path = (context.codingPath.map(\.stringValue) + [key.stringValue])
        .filter { !$0.isEmpty }
        .joined(separator: ".")
      return "Missing required field `\(path.isEmpty ? key.stringValue : path)`."
    case .valueNotFound(let type, let context):
      let path = context.codingPath.map(\.stringValue).joined(separator: ".")
      let label = path.isEmpty ? String(describing: type) : path
      return "Missing value for `\(label)`."
    case .typeMismatch(let type, let context):
      let path = context.codingPath.map(\.stringValue).joined(separator: ".")
      return "Wrong type at `\(path)`: expected \(type)."
    case .dataCorrupted(let context):
      return context.debugDescription
    @unknown default:
      return decoding.localizedDescription
    }
  }

  static func invalidSubmitResultDecodeNudge(
    errorMessage: String,
    phase: AgentPhase? = nil
  ) -> InvalidToolArgumentsNudge {
    let retryShape = submitResultDecodeRetryShape(for: phase)
    return InvalidToolArgumentsNudge(
      eventText: "submit_result contract rejected",
      eventDetail: errorMessage,
      userMessage: """
        Your previous `submit_result` did not match this phase's required shape: \
        \(errorMessage)

        Call `submit_result` again with arguments that decode to this phase's schema. \
        Include every required top-level field and, when `state` is an object rather than \
        null, all of its required nested fields. Use the canonical keys shown below; \
        aliases are only a recovery fallback. Do not wrap the payload in an extra object.

        \(retryShape)
        """
    )
  }

  private static func submitResultDecodeRetryShape(for phase: AgentPhase?) -> String {
    switch phase {
    case .plan:
      return """
        Use this exact retry shape for Plan. Keep shell commands only in `state.immediate.verify`:
        Important Plan shape repairs:
        - `state.immediate` must be either a JSON object with `plan`, `verify`, and its metadata fields, or the literal `null`; never a Markdown string, array, or prose object. Put Markdown only inside `state.immediate.plan`.
        - `state.strategicContext` must be a JSON object. Its `principles`, `constraints`, `nonGoals`, and `risks` fields must be JSON arrays of strings such as `[]`, not Markdown or comma-separated strings.
        {
          "state": {
            "immediate": {
              "plan": "## Outcome\\n<one sentence: what will change>\\n\\n## Why it matters\\n<who this helps and why>\\n\\n## Acceptance checks\\n- <observable finish-line behavior>\\n- <another observable result; state.immediate.verify proves it>",
              "verify": "<real shell command, no cd prefix>",
              "verifyTimeoutMs": 600000,
              "estimatedDifficulty": "low",
              "selectedBecause": "<why this slice is the right next step>",
              "source": "candidate",
              "candidateID": null
            },
            "candidates": [],
            "strategicContext": {
              "thesis": "<durable product intent>",
              "principles": [],
              "constraints": [],
              "nonGoals": [],
              "risks": []
            },
            "openQuestions": []
          },
          "lessonEdits": []
        }

        Do not answer in prose.
        """
    case .develop:
      return """
        Pick exactly one status value. Do not write `succeeded|blocked|failed`.

        Use this exact retry shape when the implementation is complete:
        {
          "status": "succeeded",
          "summary": "<what changed or what stopped the attempt>",
          "feedback": "<concrete handoff for the next Plan pass>",
          "bypassVerify": false,
          "lessonEdits": []
        }

        If the work is blocked or failed, keep the same shape but set `"status"` to \
        `"blocked"` or `"failed"` and make `feedback` name the smallest Plan recovery action.

        Do not answer in prose.
        """
    case .reflect:
      return """
        Use this exact retry shape for Reflect when no planning update is needed:
        {
          "state": null,
          "summary": "<why the current plan is still on course>",
          "lessonEdits": []
        }

        If planning needs revision, replace `state: null` with an object containing \
        all required planning keys: `immediate`, `candidates`, `strategicContext`, \
        and `openQuestions`. Do not include completed history. Do not answer in prose.
        """
    case .critic:
      return """
        Use this exact retry shape when approving:
        {
          "verdict": "approve",
          "summary": "<concise review summary>",
          "feedback": ""
        }

        If there is a concrete blocking issue, use this request-changes shape instead:
        {
          "verdict": "request_changes",
          "summary": "<concise review summary>",
          "feedback": "- <specific failing behavior or file>\\n- <smallest Develop recovery action>"
        }

        Do not answer in prose.
        """
    case nil:
      return """
        Use the submit_result shape from your original task. Include `lessonEdits: []` when \
        that field is required, and use `state: null` only in phases whose schema allows it.

        Do not answer in prose.
        """
    }
  }

  static func invalidLessonEditsNudge(errorMessage: String) -> InvalidToolArgumentsNudge {
    InvalidToolArgumentsNudge(
      eventText: "submit_result lesson edits rejected",
      eventDetail: errorMessage,
      userMessage: """
        Your previous `submit_result` included `lessonEdits` that could not be applied: \
        \(errorMessage)

        Call `submit_result` again. Keep the same `state` (or status/summary fields) unless \
        you have a concrete reason to change them, but fix `lessonEdits` so each `find` \
        matches the current lessons content exactly — re-read the Lessons section in your \
        original task. Use `[]` when you have no lesson change. If `find` would match more \
        than once, include more surrounding context or set `replaceAll` to true.

        Use this exact `lessonEdits` field when there is no durable lesson to update:
        "lessonEdits": []

        Use this exact item shape only after copying an exact current lesson into `find`:
        "lessonEdits": [
          {
            "find": "<exact current lesson text>",
            "replace": "<replacement lesson text>",
            "replaceAll": false
          }
        ]
        """
    )
  }

  static func invalidDevelopFeedbackNudge(error: DevelopFeedbackValidationError)
    -> InvalidToolArgumentsNudge
  {
    InvalidToolArgumentsNudge(
      eventText: "submit_result feedback rejected",
      eventDetail: error.message,
      userMessage: """
        Your previous `submit_result.feedback` was too weak to hand to the next Plan pass: \
        \(error.message)

        Call `submit_result` again. Keep the same `status`, `summary`, `bypassVerify`, and \
        `lessonEdits` unless the facts changed, but replace `feedback` with one or two concrete \
        sentences. For `succeeded`, name what changed and whether there is a next follow-up or \
        no follow-up after verification. For `blocked` or `failed`, name the blocker/failure and \
        the smallest recovery action Plan should choose next.

        Use this exact retry shape, keeping facts unchanged except for the stronger `feedback`:
        {
          "status": "<same status>",
          "summary": "<same factual summary>",
          "feedback": "<changed surface plus verification/follow-up, or blocker/failure plus smallest Plan recovery action>",
          "bypassVerify": false,
          "lessonEdits": []
        }

        Do not answer in prose.
        """
    )
  }

  static func invalidDevelopVerifyBypassNudge(error: DevelopVerifyBypassValidationError)
    -> InvalidToolArgumentsNudge
  {
    InvalidToolArgumentsNudge(
      eventText: "submit_result verify bypass rejected",
      eventDetail: error.message,
      userMessage: """
        Your previous Develop `submit_result` set `bypassVerify: true`, but Compass needs a \
        concrete reason before it can skip Verify: \(error.message)

        Call `submit_result` again. If the verify command can run, set `bypassVerify` to false \
        or null and let Compass run it. Use `bypassVerify: true` only when the verify command \
        itself is wrong or out of scope, and then make `feedback` name the exact verify-command \
        problem and the smallest Plan recovery action.

        Use this exact retry shape when verify can run:
        {
          "status": "<same status>",
          "summary": "<same factual summary>",
          "feedback": "<concrete Develop handoff for the next Plan pass>",
          "bypassVerify": false,
          "lessonEdits": []
        }

        If the verify command itself is wrong or out of scope, keep the same shape but set \
        `"bypassVerify": true` and make `feedback` name the exact verify-command problem plus \
        the smallest Plan recovery action. Do not answer in prose.
        """
    )
  }

  static func invalidCriticFeedbackNudge(error: CriticFeedbackValidationError)
    -> InvalidToolArgumentsNudge
  {
    InvalidToolArgumentsNudge(
      eventText: "submit_result critic feedback rejected",
      eventDetail: error.message,
      userMessage: """
        Your previous Critic `submit_result` requested changes without an actionable punch list: \
        \(error.message)

        Call `submit_result` again. If there is a real, fixable problem, keep \
        `verdict: "request_changes"` and replace `feedback` with one or two concrete bullets or \
        sentences that name the failure and the smallest recovery action. Include file paths or \
        line numbers from the diff when possible. If you cannot name a concrete fix, approve with \
        `feedback: ""`.

        Use this exact retry shape for real requested changes:
        {
          "verdict": "request_changes",
          "summary": "<same or corrected review summary>",
          "feedback": "- <specific failing behavior or file>\\n- <smallest Develop recovery action>"
        }

        If you cannot name a concrete fix, use this approve shape:
        {
          "verdict": "approve",
          "summary": "<why no blocking issue remains>",
          "feedback": ""
        }

        Do not answer in prose.
        """
    )
  }

  static func invalidPlanTransitionNudge(error: PlanTransitionValidationError)
    -> InvalidToolArgumentsNudge
  {
    let repairChecklist = planTransitionRepairChecklist(for: error)
    return InvalidToolArgumentsNudge(
      eventText: "submit_result plan rejected",
      eventDetail: error.message,
      userMessage: """
        Your previous `submit_result` would stop the Compass loop instead of selecting valid immediate work: \
        \(error.message)

        Repair checklist:
        \(repairChecklist)

        Call `submit_result` again with a concrete `state.immediate` object containing one commit-sized \
        Immediate Plan and a real verify command. Write `state.immediate.plan` with short Markdown \
        sections named `Outcome` and `Acceptance checks`; add `Why it matters` when it helps the \
        non-engineer owner. Make the acceptance checks observable enough for Develop to know when it is \
        done, keep shell commands only in `state.immediate.verify`, and explain the selection with \
        `state.immediate.selectedBecause` plus `state.immediate.source`. Preserve existing candidates \
        and strategic context unless you have a specific revision. Keep `state.strategicContext` as \
        an object whose `principles`, `constraints`, `nonGoals`, and `risks` fields are arrays. Use \
        `immediate: null` only when \
        there are no actionable candidates and no useful repo-originated slice.

        Use this exact retry shape. Replace the bracketed text, keep the top-level keys exactly as shown, \
        and do not answer in prose:
        {
          "state": {
            "immediate": {
              "plan": "## Outcome\\n<one sentence: what will change>\\n\\n## Why it matters\\n<who this helps and why>\\n\\n## Acceptance checks\\n- <observable finish-line behavior>\\n- <another observable result; state.immediate.verify proves it>",
              "verify": "<real shell command, no cd prefix>",
              "verifyTimeoutMs": 600000,
              "estimatedDifficulty": "low",
              "selectedBecause": "<why this slice is the right next step>",
              "source": "candidate",
              "candidateID": null
            },
            "candidates": [],
            "strategicContext": {
              "thesis": "<durable product intent>",
              "principles": [],
              "constraints": [],
              "nonGoals": [],
              "risks": []
            },
            "openQuestions": []
          },
          "lessonEdits": []
        }
        """
    )
  }

  static func planTransitionRepairChecklist(for error: PlanTransitionValidationError) -> String {
    switch error.reason {
    case .noImmediateWork:
      return """
        - Replace `state.immediate: null` with one concrete Immediate Plan.
        - Choose the next smallest slice from the remaining actionable candidates or repo state.
        - Preserve `candidates`, `strategicContext`, and `openQuestions` unless you are intentionally refining them.
        """
    case .placeholderVerify:
      let rejected = error.rejectedVerify.map { " Rejected verify: `\($0)`." } ?? ""
      return """
        - Replace the placeholder or failure-masking verify command with a real shell command Compass can run.\(rejected)
        - Do not use no-op commands such as \(PlanVerifyCommandPolicy.placeholderExamples).
        - Do not hide failures behind fallback clauses such as \(PlanVerifyCommandPolicy.failureMaskingExamples).
        - Keep the plan text if its Outcome and Acceptance checks are still correct.
        """
    case .coverageRequirement:
      return """
        - Revise `state.immediate.verify` to satisfy the forge profile coverage requirement.
        - Keep the same Immediate Plan if the planned slice is still correct.
        - Do not bypass coverage by switching to a placeholder or build-only command for test work.
        """
    case .weakHandoff:
      let missing =
        error.missingLabels.isEmpty
        ? "Outcome and Acceptance checks"
        : error.missingLabels.joined(separator: " and ")
      if !error.rejectedAcceptanceChecks.isEmpty || !error.vagueAcceptanceChecks.isEmpty {
        var repairs: [String] = []
        if !error.rejectedAcceptanceChecks.isEmpty {
          repairs.append(
            "- Replace command-only acceptance checks (\(formattedRejectedAcceptanceChecks(error.rejectedAcceptanceChecks))) with observable finish-line behavior."
          )
          repairs.append(
            "- Keep shell commands in `state.immediate.verify`; do not repeat them as acceptance checks."
          )
        }
        if !error.vagueAcceptanceChecks.isEmpty {
          repairs.append(
            "- Replace vague acceptance checks (\(formattedRejectedAcceptanceChecks(error.vagueAcceptanceChecks))) with specific behavior, UI state, or test-proven signals."
          )
        }
        repairs.append(
          "- Add \(missing) to `state.immediate.plan` while keeping the slice commit-sized."
        )
        return repairs.joined(separator: "\n")
      }
      return """
        - Add \(missing) to `state.immediate.plan`.
        - Keep the slice commit-sized; do not broaden scope to compensate for the rejection.
        - Make every acceptance check observable by the verify command or the UI state.
        """
    case .invalidStateMutation:
      return """
        - Preserve existing actionable candidates unless you record a completed slice or mark stale work explicitly.
        - Do not clear candidates, strategic context, open questions, or completed context as a side effect of selecting Immediate Work.
        - Return the smallest valid state change that keeps the factory moving.
        """
    case .multiExperimentImmediate:
      return """
        - Choose one product experiment for `state.immediate`.
        - Preserve experiment branch isolation; do not implement several product bets in one handoff.
        - If the work truly serves multiple experiments, explicitly scope it as shared experiment infrastructure and explain why.
        """
    case .unknown:
      return """
        - Choose one concrete Immediate Plan unless the project truly has no actionable candidates or useful repo-originated work.
        - Include a real verify command and observable Acceptance checks.
        - Preserve existing `candidates`, `strategicContext`, and `openQuestions` unless you have a specific revision.
        """
    }
  }

  private static func formattedRejectedAcceptanceChecks(_ checks: [String]) -> String {
    checks.prefix(3).map { "`\($0)`" }.joined(separator: ", ")
  }

  static func invalidSubmitResultNudge(
    finishReason: String?,
    argumentsPreview: String,
    maxCompletionTokens: Int,
    phase: AgentPhase? = nil
  ) -> InvalidToolArgumentsNudge {
    let retryShape = submitResultDecodeRetryShape(for: phase)
    if finishReason == "length" {
      return InvalidToolArgumentsNudge(
        eventText: "submit_result truncated",
        eventDetail:
          "Output hit the max-tokens cap (\(maxCompletionTokens)); asking the model to retry with shorter fields.",
        userMessage: """
          Your previous `submit_result` was truncated by the output-token limit. Retry with the same \
          structure but shorter free-form text — trim `summary`, keep plan fields concise, and avoid \
          restating context. The tool args must be complete, valid JSON.

          \(retryShape)
          """
      )
    }
    return InvalidToolArgumentsNudge(
      eventText: "submit_result rejected",
      eventDetail: "submit_result args are not valid JSON: \(argumentsPreview)",
      userMessage: """
        Your previous `submit_result` arguments could not be parsed as JSON — the upstream often \
        truncates mid-token without flagging it. Retry with the same structure but noticeably shorter \
        free-form text: trim `summary`, keep plan fields concise, and avoid restating prior context. \
        The tool args must be complete, valid JSON.

        \(retryShape)
        """
    )
  }

  static func missingSubmitResultNudge(
    finishReason: String?,
    maxCompletionTokens: Int,
    phase: AgentPhase? = nil
  ) -> InvalidToolArgumentsNudge {
    let retryShape = submitResultDecodeRetryShape(for: phase)
    if finishReason == "length" {
      return InvalidToolArgumentsNudge(
        eventText: "submit_result missing after truncation",
        eventDetail:
          "Output hit the max-tokens cap (\(maxCompletionTokens)) before a submit_result call.",
        userMessage: """
          Your previous turn was truncated by the output-token limit before Compass received \
          a `submit_result` tool call. Do not continue prose. Call `submit_result` now with \
          the required phase payload, using shorter free-form fields if needed.

          \(retryShape)
          """
      )
    }

    let reason = finishReason?.trimmingCharacters(in: .whitespacesAndNewlines)
    let detail: String
    if let reason, !reason.isEmpty {
      detail = "Model ended with finish_reason=\(reason) without calling submit_result."
    } else {
      detail = "Model ended without calling submit_result."
    }
    return InvalidToolArgumentsNudge(
      eventText: "submit_result missing",
      eventDetail: detail,
      userMessage: """
        Your previous turn ended without a `submit_result` tool call. Compass cannot finish \
        this phase from prose, partial notes, or analysis text. Call `submit_result` now with \
        the required phase payload.

        \(retryShape)
        """
    )
  }

  /// Build the remediation copy for any non-`submit_result` tool call
  /// whose `arguments` field isn't valid JSON. Two common causes: the
  /// model emitted unescaped control characters or unbalanced strings
  /// inside a large `edit_file` / `write_file` payload, or the upstream
  /// silently truncated mid-token (MiniMax has been observed doing this
  /// without setting `finishReason == "length"`). The `length` branch
  /// owns the truncation-specific wording; the fallthrough handles both
  /// silent-truncation and model-side escape errors with a generic
  /// "retry with valid JSON" nudge.
  static func invalidToolArgumentsNudge(
    toolName: String,
    finishReason: String?,
    argumentsPreview: String,
    maxCompletionTokens: Int
  ) -> InvalidToolArgumentsNudge {
    let retryHint = toolArgumentsRetryHint(for: toolName)
    if finishReason == "length" {
      return InvalidToolArgumentsNudge(
        eventText: "\(toolName) truncated",
        eventDetail:
          "Output hit the max-tokens cap (\(maxCompletionTokens)); asking the model to retry with a smaller payload.",
        userMessage: """
          Your previous `\(toolName)` call was truncated by the output-token limit, so its arguments \
          were not valid JSON. Retry with a smaller payload — for file edits, break the change into \
          multiple smaller `edit_file` calls instead of one large one. The tool args must be complete, \
          valid JSON.

          \(retryHint)
          """
      )
    }
    return InvalidToolArgumentsNudge(
      eventText: "\(toolName) rejected",
      eventDetail: "\(toolName) args are not valid JSON: \(argumentsPreview)",
      userMessage: """
        Your previous `\(toolName)` arguments could not be parsed as JSON. The upstream rejects the \
        next request when any tool call's arguments are malformed, so the call was dropped without \
        invoking the tool. Retry with valid JSON — pay attention to escaping (`\\n` for newlines, \
        `\\\"` for quotes inside strings) and to closing all braces/brackets. If the payload is very \
        large, split it into multiple smaller calls.

        \(retryHint)
        """
    )
  }

  private static func toolArgumentsRetryHint(for toolName: String) -> String {
    switch toolName {
    case AgentEditFileTool.toolName:
      return """
        Use this compact `edit_file` retry shape:
        {
          "path": "relative/path.ext",
          "edits": [
            {
              "oldString": "<exact text copied from a prior read_file result>",
              "newString": "<replacement text>",
              "replaceAll": false
            }
          ]
        }

        Keep `oldString` exact and small. Use JSON escapes for embedded newlines. Do not answer in prose.
        """
    case AgentWriteFileTool.toolName:
      return """
        Use this compact `write_file` retry shape:
        {
          "path": "relative/path.ext",
          "content": "<complete UTF-8 file contents>"
        }

        Use JSON escapes for embedded newlines. Do not answer in prose.
        """
    case AgentReadFileTool.toolName:
      return """
        Use this compact `read_file` retry shape:
        {
          "path": "relative/path.ext",
          "offset": 1,
          "limit": 200
        }

        Omit `offset` and `limit` when you want the default slice. Do not answer in prose.
        """
    default:
      return """
        Retry with one valid JSON object matching the `\(toolName)` tool schema. Do not answer in prose.
        """
    }
  }

  /// Drop everything from `messages` from `targetCount` onward. Used when
  /// an iteration's `submit_result` arrived malformed: we need to peel
  /// back the assistant turn *and* any `.tool` responses we appended for
  /// sibling tool calls in the same turn (those responses would orphan
  /// without the assistant turn that declared the matching tool_call
  /// IDs). Also drops any nudge-index entries that referred to messages
  /// we just removed, so the index set stays consistent with the
  /// truncated array.
  static func rollback(
    messages: inout [ChatQuery.ChatCompletionMessageParam],
    nudgeIndices: inout Set<Int>,
    to targetCount: Int
  ) {
    guard targetCount >= 0, targetCount < messages.count else { return }
    messages.removeLast(messages.count - targetCount)
    nudgeIndices = nudgeIndices.filter { $0 < targetCount }
  }

  /// Append a `.user` remediation message and track its index. If the
  /// last message is itself a tracked remediation nudge, replace it
  /// instead of appending — two consecutive `.user` messages from
  /// back-to-back failed iterations is a malformed role sequence and
  /// strict providers (MiniMax has been observed doing this) reject the
  /// next request with a 400.
  static func appendRemediationNudge(
    _ text: String,
    messages: inout [ChatQuery.ChatCompletionMessageParam],
    nudgeIndices: inout Set<Int>
  ) {
    let lastIndex = messages.count - 1
    if lastIndex >= 0, nudgeIndices.contains(lastIndex) {
      messages.removeLast()
      nudgeIndices.remove(lastIndex)
    }
    messages.append(.user(.init(content: .string(text))))
    nudgeIndices.insert(messages.count - 1)
  }
}
