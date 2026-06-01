import Foundation

struct PlanHandoffRepairGuide: Equatable, Sendable {
  static let templateLimit = 720

  var status: Status
  var title: String
  var detail: String
  var scoreLabel: String
  var steps: [Step]
  var suggestedVerifyCommand: String?
  var planTemplate: String?

  var shouldShow: Bool {
    status != .ready
  }

  init(
    plan rawPlan: String?,
    verify rawVerify: String?,
    languageProfile: RepositoryLanguageProfile
  ) {
    let digest = PlanHandoffDigest(plan: rawPlan)
    let verifyCommand = PlanVerifyCommandPolicy.normalizedCommand(rawVerify)
    let hasUsableVerify = verifyCommand.map { !PlanVerifyCommandPolicy.isPlaceholder($0) } ?? false
    suggestedVerifyCommand = hasUsableVerify
      ? verifyCommand
      : Self.suggestedVerifyCommand(for: languageProfile)

    steps = [
      Step(
        kind: .outcome,
        isSatisfied: digest.outcome != nil,
        detail: digest.outcome ?? "Say what will be true after this slice."
      ),
      Step(
        kind: .acceptanceChecks,
        isSatisfied: !digest.acceptanceChecks.isEmpty,
        detail: digest.acceptanceChecks.isEmpty
          ? "List observable finish-line checks."
          : "\(digest.acceptanceChecks.count) check\(digest.acceptanceChecks.count == 1 ? "" : "s") listed."
      ),
      Step(
        kind: .verifyCommand,
        isSatisfied: hasUsableVerify,
        detail: hasUsableVerify
          ? "Compass can run \(verifyCommand ?? "the planned check")."
          : "Choose a real command Compass can run after Develop."
      ),
      Step(
        kind: .whyItMatters,
        isSatisfied: digest.whyItMatters != nil,
        detail: digest.whyItMatters ?? "Optional: say who benefits and why."
      ),
    ]

    let requiredSteps = steps.filter(\.isRequired)
    let satisfiedRequiredCount = requiredSteps.filter(\.isSatisfied).count
    scoreLabel = "\(satisfiedRequiredCount) of \(requiredSteps.count) required"

    if requiredSteps.allSatisfy(\.isSatisfied) {
      status = .ready
      title = "Ready for Develop"
      detail = "The handoff has an outcome, acceptance checks, and a runnable verification command."
      planTemplate = nil
    } else if digest.status == .missingPlan {
      status = .missingHandoff
      title = "Create the handoff"
      detail = "Plan needs one commit-sized slice plus a verification command before Develop can start."
      planTemplate = Self.template(
        outcome: nil,
        whyItMatters: nil,
        acceptanceChecks: [],
        suggestedVerifyCommand: suggestedVerifyCommand
      )
    } else {
      let missingLabels = steps
        .filter { $0.isRequired && !$0.isSatisfied }
        .map(\.title)
      status = .needsRepair
      title = "Make this executable"
      detail = "Add \(missingLabels.joined(separator: " and ")) before Develop has a clear finish line."
      planTemplate = Self.template(
        outcome: digest.outcome,
        whyItMatters: digest.whyItMatters,
        acceptanceChecks: digest.acceptanceChecks,
        suggestedVerifyCommand: suggestedVerifyCommand
      )
    }

    detail = StringUtils.boundedText(detail, limit: 220)
  }

  enum Status: Equatable, Sendable {
    case missingHandoff
    case needsRepair
    case ready
  }

  struct Step: Identifiable, Equatable, Sendable {
    var kind: Kind
    var isSatisfied: Bool
    var detail: String

    var id: Kind { kind }
    var title: String { kind.title }
    var systemImage: String { isSatisfied ? "checkmark.circle.fill" : kind.systemImage }
    var isRequired: Bool { kind.isRequired }
  }

  enum Kind: Equatable, Sendable {
    case outcome
    case acceptanceChecks
    case verifyCommand
    case whyItMatters

    var title: String {
      switch self {
      case .outcome:
        return "Outcome"
      case .acceptanceChecks:
        return "Acceptance checks"
      case .verifyCommand:
        return "Verify command"
      case .whyItMatters:
        return "Why"
      }
    }

    var systemImage: String {
      switch self {
      case .outcome:
        return "target"
      case .acceptanceChecks:
        return "checkmark.seal"
      case .verifyCommand:
        return "terminal"
      case .whyItMatters:
        return "person.crop.circle.badge.questionmark"
      }
    }

    var isRequired: Bool {
      switch self {
      case .outcome, .acceptanceChecks, .verifyCommand:
        return true
      case .whyItMatters:
        return false
      }
    }
  }

  private static func suggestedVerifyCommand(for profile: RepositoryLanguageProfile) -> String? {
    if let hint = profile.manifestHints.first {
      switch hint {
      case .packageJSON:
        return "npm test"
      case .goMod:
        return "go test ./..."
      case .cargoToml:
        return "cargo test"
      case .packageSwift:
        return "swift test"
      }
    }

    switch profile.primaryLanguage {
    case .swift:
      return "swift test"
    case .typeScriptJavaScript:
      return "npm test"
    case .go:
      return "go test ./..."
    case .rust:
      return "cargo test"
    case .markdown, .other, .unknown:
      return nil
    }
  }

  private static func template(
    outcome: String?,
    whyItMatters: String?,
    acceptanceChecks: [String],
    suggestedVerifyCommand: String?
  ) -> String {
    let checks: [String] =
      acceptanceChecks.isEmpty
      ? [
        "<observable behavior or UI state is present>",
        "<test, build, or manual check proves it works>",
      ]
      : acceptanceChecks

    let text = """
      ## Outcome
      \(outcome ?? "<one sentence about what changes>")

      ## Why it matters
      \(whyItMatters ?? "<who this helps and why>")

      ## Acceptance checks
      \(checks.map { "- \($0)" }.joined(separator: "\n"))

      Verify: \(suggestedVerifyCommand ?? "<project test command>")
      """

    return boundedTemplate(text)
  }

  private static func boundedTemplate(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count > templateLimit else { return trimmed }
    guard templateLimit > 3 else { return String(trimmed.prefix(templateLimit)) }
    return String(trimmed.prefix(templateLimit - 3))
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}
