import Foundation

extension AgentExecutor {
  struct InvalidToolArgumentsNudge: Equatable {
    var eventText: String
    var eventDetail: String
    var userMessage: String
  }

  static func submitResultValidationNudge(
    for error: Error,
    phase: AgentPhase? = nil
  ) -> InvalidToolArgumentsNudge {
    if let error = error as? PlanTransitionValidationError {
      return InvalidToolArgumentsNudge(
        eventText: "plan_submit rejected",
        eventDetail: error.message,
        userMessage: """
          Your previous Plan payload did not select valid immediate work: \(error.message)

          Return `plan_submit` again with one commit-sized TypeScript work packet and a real verify command.

          \(submitResultDecodeRetryShape(for: .plan))
          """
      )
    }
    if let error = error as? DevelopFeedbackValidationError {
      return InvalidToolArgumentsNudge(
        eventText: "develop_submit feedback rejected",
        eventDetail: error.message,
        userMessage: """
          Your previous Develop feedback was too weak: \(error.message)

          Return `develop_submit` again with the same factual status and summary, but make `feedback`
          name the smallest next action.

          \(submitResultDecodeRetryShape(for: .develop))
          """
      )
    }
    if let error = error as? DevelopVerifyBypassValidationError {
      return InvalidToolArgumentsNudge(
        eventText: "develop_submit verify bypass rejected",
        eventDetail: error.message,
        userMessage: """
          Compass needs a concrete reason before skipping Verify: \(error.message)

          Return `develop_submit` again. Set `bypassVerify` to false unless the verify command itself
          is wrong or out of scope.

          \(submitResultDecodeRetryShape(for: .develop))
          """
      )
    }
    if let error = error as? CriticFeedbackValidationError {
      return InvalidToolArgumentsNudge(
        eventText: "critic_submit feedback rejected",
        eventDetail: error.message,
        userMessage: """
          Your Critic payload requested changes without actionable feedback: \(error.message)

          Return `critic_submit` again with concrete fix instructions, or approve if no blocker remains.

          \(submitResultDecodeRetryShape(for: .critic))
          """
      )
    }
    if error is DecodingError {
      return invalidSubmitResultDecodeNudge(
        errorMessage: decodingErrorMessage(error),
        phase: phase
      )
    }
    return InvalidToolArgumentsNudge(
      eventText: "phase payload lesson edits rejected",
      eventDetail: error.localizedDescription,
      userMessage: """
        Your previous phase payload included lesson edits Compass could not apply:
        \(error.localizedDescription)

        Return the phase submit envelope again. Keep facts unchanged and use `"lessonEdits": []` if there is
        no exact lesson replacement.
        """
    )
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
    InvalidToolArgumentsNudge(
      eventText: "phase payload contract rejected",
      eventDetail: errorMessage,
      userMessage: """
        Your previous phase payload did not match this phase's required shape:
        \(errorMessage)

        Return the phase submit envelope again with valid JSON only. Do not answer in prose.

        \(submitResultDecodeRetryShape(for: phase))
        """
    )
  }

  static func missingSubmitResultNudge(
    finishReason: String?,
    maxCompletionTokens: Int,
    phase: AgentPhase? = nil
  ) -> InvalidToolArgumentsNudge {
    _ = maxCompletionTokens
    let detail: String
    if let finishReason, !finishReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      detail = "Model ended with finish_reason=\(finishReason) without returning a phase submit envelope."
    } else {
      detail = "Model ended without returning a phase submit envelope."
    }
    return InvalidToolArgumentsNudge(
      eventText: "phase submit missing",
      eventDetail: detail,
      userMessage: """
        Your previous turn ended without a submit envelope. Compass cannot finish this
        phase from prose. Return the required phase submit envelope now.

        \(submitResultDecodeRetryShape(for: phase))
        """
    )
  }

  private static func submitResultDecodeRetryShape(for phase: AgentPhase?) -> String {
    switch phase {
    case .plan:
      return """
        Plan shape:
        {
          "state": {
            "immediate": {
              "plan": "## Outcome\\n<what changes>\\n\\n## Acceptance checks\\n- <observable result>",
              "verify": "pnpm verify",
              "verifyTimeoutMs": 600000,
              "estimatedDifficulty": "low",
              "selectedBecause": "<why this is the next slice>",
              "source": "candidate",
              "candidateID": null
            },
            "queue": [],
            "brief": {
              "summary": "<short task context>",
              "targetUsers": [],
              "desiredOutcomes": [],
              "constraints": [],
              "acceptanceSignals": []
            },
            "openQuestions": []
          },
          "lessonEdits": []
        }
        """
    case .develop:
      return """
        Develop shape:
        {
          "status": "succeeded",
          "summary": "<what changed or what blocked the work>",
          "feedback": "<smallest next action or no follow-up>",
          "bypassVerify": false,
          "lessonEdits": []
        }
        """
    case .critic:
      return """
        Critic shape:
        {
          "verdict": "approve",
          "summary": "<review summary>",
          "feedback": ""
        }
        """
    case nil:
      return "Use the JSON schema for the current phase and include every required field."
    }
  }
}
