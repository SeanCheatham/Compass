import Foundation

struct PlanHandoffClipboardPayload: Equatable, Sendable {
  static let textLimit = 4_000

  var text: String

  init(
    plan rawPlan: String,
    verify rawVerify: String?,
    languageProfile: RepositoryLanguageProfile,
    forgeProfile: ForgeProfile? = nil
  ) {
    let plan = Self.normalized(rawPlan)
    let normalizedVerify = Self.normalized(rawVerify ?? "")
    let verify = normalizedVerify.isEmpty ? nil : normalizedVerify
    let digest = PlanHandoffDigest(plan: plan)
    let repairGuide = PlanHandoffRepairGuide(
      plan: plan,
      verify: verify,
      languageProfile: languageProfile,
      forgeProfile: forgeProfile
    )
    let verifySummary = PlanVerifyCommandSummary(command: verify)

    var sections: [String] = [
      "Compass Immediate Work Handoff",
      "",
      "Status: \(digest.title)",
      "Readiness: \(repairGuide.title) (\(repairGuide.scoreLabel))",
    ]

    if let outcome = digest.outcome {
      sections.append(contentsOf: ["", "Outcome:", outcome])
    }

    if let whyItMatters = digest.whyItMatters {
      sections.append(contentsOf: ["", "Why it matters:", whyItMatters])
    }

    if !digest.acceptanceChecks.isEmpty {
      sections.append("")
      sections.append("Acceptance checks:")
      sections.append(contentsOf: digest.acceptanceChecks.map { "- \($0)" })
    }

    if !digest.missingPieces.isEmpty {
      sections.append("")
      sections.append("Missing handoff detail:")
      sections.append(contentsOf: digest.missingPieces.map { "- \($0.label)" })
    }

    sections.append("")
    sections.append("Verify:")
    sections.append(verify ?? "No verify command selected.")
    sections.append("Verify meaning: \(verifySummary.title). \(verifySummary.detail)")

    if repairGuide.shouldShow {
      sections.append("")
      sections.append("Repair before Develop:")
      sections.append(repairGuide.detail)
      sections.append(
        contentsOf: repairGuide.steps.map { step in
          "- \(step.title): \(step.detail)"
        })

      if let suggestedVerifyCommand = repairGuide.suggestedVerifyCommand {
        sections.append("Suggested verify: \(suggestedVerifyCommand)")
      }

      if let planTemplate = repairGuide.planTemplate {
        sections.append("")
        sections.append("Suggested plan shape:")
        sections.append(planTemplate)
      }
    }

    sections.append("")
    sections.append("Original plan:")
    sections.append(plan.isEmpty ? "No immediate plan text selected." : plan)

    text = PlanClipboardText.boundedMultilineText(
      sections.joined(separator: "\n"),
      limit: Self.textLimit
    )
  }

  var isEmpty: Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private static func normalized(_ text: String) -> String {
    text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

struct PlanHandoffRepairClipboardPayload: Equatable, Sendable {
  static let textLimit = 3_000

  var text: String

  init(guide: PlanHandoffRepairGuide) {
    var sections: [String] = [
      "Compass Plan Repair Handoff",
      "",
      "Status: \(guide.title)",
      "Readiness: \(guide.scoreLabel)",
      "",
      "Repair goal:",
      guide.detail,
      "",
      "Instruction for Plan:",
      "Return one commit-sized Immediate Work handoff. Keep scope narrow. Include Outcome, Why it matters, Acceptance checks, and a runnable verify command.",
      "",
      "Repair checklist:",
    ]

    sections.append(
      contentsOf: guide.steps.map { step in
        let state = step.isSatisfied ? "Done" : "Needed"
        let required = step.isRequired ? "required" : "optional"
        return "- \(state) \(step.title) (\(required)): \(step.detail)"
      }
    )

    if let suggestedVerifyCommand = guide.suggestedVerifyCommand {
      sections.append("")
      sections.append("Suggested verify:")
      sections.append(suggestedVerifyCommand)
    }

    if let planTemplate = guide.planTemplate {
      sections.append("")
      sections.append("Suggested plan shape:")
      sections.append(planTemplate)
    }

    text = PlanClipboardText.boundedMultilineText(
      sections.joined(separator: "\n"),
      limit: Self.textLimit
    )
  }

  var isEmpty: Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

private enum PlanClipboardText {
  static func boundedMultilineText(_ text: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard text.count > limit else { return text }
    guard limit > 3 else { return String(text.prefix(limit)) }

    return String(text.prefix(limit - 3))
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}
