import Foundation

public extension AgentExecutor {
  struct InvalidToolArgumentsNudge: Equatable {
    public var eventText: String
    public var eventDetail: String
    public var userMessage: String
  }

  static func submitResultValidationNudge(
    for error: Error,
    phase: AgentPhase? = nil
  ) -> InvalidToolArgumentsNudge {
    if let error = error as? PlanTransitionValidationError {
      if error.reason == .coverageRequirement {
        return InvalidToolArgumentsNudge(
          eventText: "plan_submit rejected",
          eventDetail: error.message,
          userMessage: """
            Your previous Plan payload used a verify command that Compass rejected:
            `\(error.rejectedVerify ?? "unknown")`

            Return `plan_submit` again with the same small work packet if it is still useful, but set
            `state.immediate.verify` to `\(GeneratedProjectQuality.standardVerifyCommand)`. For a test-only slice, `cargo test --workspace` or `\(GeneratedProjectQuality.coverageCollectCommand)` is also valid.

            \(submitResultDecodeRetryShape(for: .plan))
            """
        )
      }
      if error.reason == .invalidStateMutation,
        !error.missingLabels.isEmpty,
        error.missingLabels.allSatisfy({ $0.hasPrefix("brief.") })
      {
        return InvalidToolArgumentsNudge(
          eventText: "plan_submit rejected",
          eventDetail: error.message,
          userMessage: """
            Your previous Plan payload dropped required project brief fields:
            \(error.message)

            Do not call another tool to repair this. Return `plan_submit` again with the same
            immediate work if it is still useful, and copy the current `state.brief` exactly from
            the rejection message.

            \(submitResultDecodeRetryShape(for: .plan))
            """
        )
      }
      if error.reason == .weakVerifyCoverage {
        return InvalidToolArgumentsNudge(
          eventText: "plan_submit rejected",
          eventDetail: error.message,
          userMessage: """
            Your previous Plan payload claimed new CLI behavior without proof:
            \(error.message)

            Do not call another tool to repair this. Return `plan_submit` again and choose
            exactly one repair:
            - Keep the CLI behavior and add an acceptance check that Develop updates
              `crates/cli/tests/cli.rs` to execute the new CLI path.
              If the rejection message includes "Required acceptance check to append",
              copy that bullet into `state.immediate.plan` under Acceptance checks.
              For flag parsing work, name the exact split argv shape in that check; for
              repeated flags include the flag token each time, for example:
              `crates/cli/tests/cli.rs` runs the CLI with
              `["--signal", "api:green", "--signal", "db:red"]` and asserts the
              formatted output.
              For `--format json` work, include a concrete check like:
              `crates/cli/tests/cli.rs` runs the CLI with `["--format", "json", "Ship", "it"]`
              and asserts the parsed JSON title is `Ship it`.
            - Or narrow the Outcome to core-only work and remove CLI/list/status-count claims
              from the Outcome and Acceptance checks.

            Do not resubmit the same Acceptance checks unchanged; add the missing
            `crates/cli/tests/cli.rs` proof line or remove the CLI behavior claim.

            Keep `state.immediate.verify` as `\(GeneratedProjectQuality.standardVerifyCommand)` after adding the CLI test proof.

            \(submitResultDecodeRetryShape(for: .plan))
            """
        )
      }
      if error.reason == .ungroundedPaths {
        return InvalidToolArgumentsNudge(
          eventText: "plan_submit rejected",
          eventDetail: error.message,
          userMessage: """
            Your previous Plan payload named file paths Compass could not find:
            \(error.message)

            Do not call another tool to repair this rejected submit. Return `plan_submit`
            again and choose exactly one repair:
            - Replace the missing path with a concrete existing path listed in the rejection
              message, such as a same-filename match or existing package entry point.
            - Or, if the path is intentionally new, say `create new file <path>` in the
              Outcome or Acceptance checks.
            - Or remove the unproved path from the handoff and keep only paths you already
              proved with earlier read-only tool output.

            Keep the same small work packet and verify command if they are still useful.

            \(submitResultDecodeRetryShape(for: .plan))
            """
        )
      }
      return InvalidToolArgumentsNudge(
        eventText: "plan_submit rejected",
        eventDetail: error.message,
        userMessage: """
          Your previous Plan payload did not select valid immediate work: \(error.message)

          Return `plan_submit` again with one commit-sized Rust work packet and a real verify command.

          \(submitResultDecodeRetryShape(for: .plan))
          """
      )
    }
    if let error = error as? DevelopFeedbackValidationError {
      if error.reason == .unfinishedSuccess {
        let unfinished = error.feedback.map { "`\($0)`" } ?? "planned work"
        let verificationRepair = unfinishedVerificationCommandRepair(for: error.feedback)
        return InvalidToolArgumentsNudge(
          eventText: "develop_submit feedback rejected",
          eventDetail: error.message,
          userMessage: """
            Your previous `develop_submit` claimed success, but its feedback still says work remains:
            \(unfinished)

            Do not resubmit that success packet. Choose exactly one next action:
            - Return `develop_continue` to do the missing edit or run the missing verification command.
            - Return `develop_submit` with status=failed or status=blocked if you cannot finish in budget.
            - Return status=succeeded only after the packet is complete and `feedback` summarizes the
              verified result without future work.

            \(verificationRepair)

            \(submitResultDecodeRetryShape(for: .develop))
            """
        )
      }
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
    let repairHint = submitResultDecodeRepairHint(errorMessage: errorMessage, phase: phase)
    return InvalidToolArgumentsNudge(
      eventText: "phase payload contract rejected",
      eventDetail: errorMessage,
      userMessage: """
        Your previous phase payload did not match this phase's required shape:
        \(errorMessage)

        \(repairHint)

        Return the phase submit envelope again with valid JSON only. Do not call another tool
        to repair a payload-shape error; the required data is already in the rejected JSON and
        the shape below. Do not answer in prose.

        \(submitResultDecodeRetryShape(for: phase))
        """
    )
  }

  private static func submitResultDecodeRepairHint(
    errorMessage: String,
    phase: AgentPhase?
  ) -> String {
    guard phase == .plan else { return "" }
    let normalized = errorMessage.lowercased()
    if normalized.contains("state.queue") {
      return """
        Plan queue repair:
        - If this packet does not need queued follow-up work, set `"queue": []`.
        - If you keep any queue item, every item must include `id`, `title`, `outcome`,
          `why`, `category`, `origin`, `priority`, `status`, `evidence`, and `blockedBy`.
        - Do not call a tool just to repair queue JSON.
        """
    }
    if normalized.contains("plancandidate.category")
      || normalized.contains("plancandidate.origin")
      || normalized.contains("plancandidate.priority")
      || normalized.contains("plancandidate.status")
      || normalized.contains("cannot initialize category")
      || normalized.contains("cannot initialize origin")
      || normalized.contains("cannot initialize priority")
      || normalized.contains("cannot initialize status")
    {
      return """
        Plan enum repair:
        - If this packet does not need queued follow-up work, set `"queue": []`.
        - If you keep queue items, use only lowercase enum values:
          `category`: feature, test, cleanup, docs, bugHunt, reliability, exploration.
          `origin`: draft, feedback, repository, plan, lesson, user.
          `priority`: low, medium, high.
          `status`: available, active, blocked, deferred, done, stale.
        - Do not call a tool just to repair queue JSON.
        """
    }
    return ""
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

  static func submitResultDecodeRetryShape(for phase: AgentPhase?) -> String {
    switch phase {
    case .plan:
      return """
        Plan shape:
        {
          "state": {
            "immediate": {
              "plan": "## Outcome\\n<what changes>\\n\\n## Acceptance checks\\n- <observable result>",
              "verify": "\(GeneratedProjectQuality.standardVerifyCommand)",
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

  private static func unfinishedVerificationCommandRepair(for feedback: String?) -> String {
    guard let command = unfinishedVerificationCommand(from: feedback) else { return "" }
    return """
      Detected missing verification command:
      Return this exact continuation next instead of reading files or resubmitting success:
      ```json
      {
        "kind": "develop_continue",
        "tool": "bash",
        "arguments": { "command": \(jsonStringLiteral(command)) },
        "reason": "Run the missing verification command before submitting success."
      }
      ```
      Do not call `read_file`, `list_files`, or reread `Cargo.toml` just to rediscover this command.
      """
  }

  private static func unfinishedVerificationCommand(from feedback: String?) -> String? {
    guard let feedback, !feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return nil
    }
    let normalized = feedback
      .replacingOccurrences(of: "`", with: " ")
      .replacingOccurrences(of: "\"", with: "")
    let patterns = [
      #"(?i)\bcargo\s+fmt\b.*\bcargo\s+clippy\b.*\bcargo\s+test\b"#,
      #"(?i)\bcargo\s+test\s+--workspace\b"#,
      #"(?i)\bcargo\s+llvm-cov\b"#,
      #"(?i)\bcargo\s+clippy\b"#,
      #"(?i)\bcargo\s+test\b"#,
      #"(?i)\bswift\s+test\b"#,
    ]
    for pattern in patterns {
      if let range = normalized.range(of: pattern, options: .regularExpression) {
        return normalized[range].trimmingCharacters(in: .whitespacesAndNewlines)
      }
    }
    return nil
  }

  private static func jsonStringLiteral(_ value: String) -> String {
    guard
      let data = try? JSONEncoder().encode(value),
      let literal = String(data: data, encoding: .utf8)
    else {
      return #""""#
    }
    return literal
  }
}
