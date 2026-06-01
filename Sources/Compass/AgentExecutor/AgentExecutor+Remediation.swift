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
  static func submitResultValidationNudge(for error: Error) -> InvalidToolArgumentsNudge {
    if let error = error as? PlanTransitionValidationError {
      return invalidPlanTransitionNudge(errorMessage: error.message)
    }
    if error is DecodingError {
      return invalidSubmitResultDecodeNudge(errorMessage: decodingErrorMessage(error))
    }
    return invalidLessonEditsNudge(errorMessage: error.localizedDescription)
  }

  static func decodingErrorMessage(_ error: Error) -> String {
    guard let decoding = error as? DecodingError else {
      return error.localizedDescription
    }
    switch decoding {
    case .keyNotFound(let key, _):
      return "Missing required field `\(key.stringValue)`."
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

  static func invalidSubmitResultDecodeNudge(errorMessage: String) -> InvalidToolArgumentsNudge {
    InvalidToolArgumentsNudge(
      eventText: "submit_result contract rejected",
      eventDetail: errorMessage,
      userMessage: """
        Your previous `submit_result` did not match this phase's required shape: \
        \(errorMessage)

        Call `submit_result` again with arguments that decode to the schema shown in \
        your original task — include every required top-level field and, when `state` is \
        an object rather than null, all of its required nested fields (`immediate`, \
        `midTerm`, `longTerm` for planning phases). Use `lessonEdits: []` when you have \
        no lesson change. Do not wrap the payload in an extra object.
        """
    )
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
        """
    )
  }

  static func invalidPlanTransitionNudge(errorMessage: String) -> InvalidToolArgumentsNudge {
    InvalidToolArgumentsNudge(
      eventText: "submit_result plan rejected",
      eventDetail: errorMessage,
      userMessage: """
        Your previous `submit_result` would stop the Compass loop instead of selecting valid immediate work: \
        \(errorMessage)

        Call `submit_result` again with a concrete `state.immediate` object containing one commit-sized \
        Immediate Plan and a real verify command. Write `state.immediate.plan` with short Markdown \
        sections named `Outcome`, `Why it matters`, and `Acceptance checks`; make the acceptance checks \
        observable enough for Develop to know when it is done. Preserve `midTerm` and `longTerm` unless \
        you have a specific revision. Use `immediate: null` only when there was already no mid-term or \
        long-term runway before this Plan pass and there is still none.
        """
    )
  }

  static func invalidSubmitResultNudge(
    finishReason: String?,
    argumentsPreview: String,
    maxCompletionTokens: Int
  ) -> InvalidToolArgumentsNudge {
    if finishReason == "length" {
      return InvalidToolArgumentsNudge(
        eventText: "submit_result truncated",
        eventDetail:
          "Output hit the max-tokens cap (\(maxCompletionTokens)); asking the model to retry with shorter fields.",
        userMessage:
          "Your previous `submit_result` was truncated by the output-token limit. Retry with the same structure but shorter free-form text — trim `summary`, keep plan fields concise, and avoid restating context. The tool args must be complete, valid JSON."
      )
    }
    return InvalidToolArgumentsNudge(
      eventText: "submit_result rejected",
      eventDetail: "submit_result args are not valid JSON: \(argumentsPreview)",
      userMessage:
        "Your previous `submit_result` arguments could not be parsed as JSON — the upstream often truncates mid-token without flagging it. Retry with the same structure but noticeably shorter free-form text: trim `summary`, keep plan fields concise, and avoid restating prior context. The tool args must be complete, valid JSON."
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
    if finishReason == "length" {
      return InvalidToolArgumentsNudge(
        eventText: "\(toolName) truncated",
        eventDetail:
          "Output hit the max-tokens cap (\(maxCompletionTokens)); asking the model to retry with a smaller payload.",
        userMessage:
          "Your previous `\(toolName)` call was truncated by the output-token limit, so its arguments were not valid JSON. Retry with a smaller payload — for file edits, break the change into multiple smaller `edit_file` calls instead of one large one. The tool args must be complete, valid JSON."
      )
    }
    return InvalidToolArgumentsNudge(
      eventText: "\(toolName) rejected",
      eventDetail: "\(toolName) args are not valid JSON: \(argumentsPreview)",
      userMessage:
        "Your previous `\(toolName)` arguments could not be parsed as JSON. The upstream rejects the next request when any tool call's arguments are malformed, so the call was dropped without invoking the tool. Retry with valid JSON — pay attention to escaping (`\\n` for newlines, `\\\"` for quotes inside strings) and to closing all braces/brackets. If the payload is very large, split it into multiple smaller calls."
    )
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
