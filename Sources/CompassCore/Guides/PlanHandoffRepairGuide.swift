import Foundation

public struct PlanHandoffRepairGuide: Equatable, Sendable {
  public static let templateLimit = 720

  public var status: Status
  public var title: String
  public var detail: String
  public var scoreLabel: String
  public var steps: [Step]
  public var suggestedVerifyCommand: String?
  public var planTemplate: String?

  public var shouldShow: Bool {
    status != .ready
  }

  public init(
    plan rawPlan: String?,
    verify rawVerify: String?,
    languageProfile: RepositoryLanguageProfile
  ) {
    let digest = PlanHandoffDigest(plan: rawPlan)
    let verifyCommand = PlanVerifyCommandPolicy.normalizedCommand(rawVerify)
    let hasFailureMask = verifyCommand.map(PlanVerifyCommandPolicy.masksFailures) ?? false
    let hasRealVerify =
      verifyCommand.map { !PlanVerifyCommandPolicy.isPlaceholder($0) && !hasFailureMask } ?? false
    let coverageViolation =
      hasRealVerify
      ? verifyCommand.flatMap { GeneratedVerifyValidator.coverageViolation(verify: $0) }
      : nil
    let hasUsableVerify = hasRealVerify && coverageViolation == nil
    suggestedVerifyCommand =
      hasUsableVerify
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
          ? Self.acceptanceChecksRepairDetail(digest: digest)
          : "\(digest.acceptanceChecks.count) check\(digest.acceptanceChecks.count == 1 ? "" : "s") listed."
      ),
      Step(
        kind: coverageViolation == nil ? .verifyCommand : .coverageReadyVerify,
        isSatisfied: hasUsableVerify,
        detail: hasUsableVerify
          ? "Compass can run \(verifyCommand ?? "the planned check")."
          : Self.verifyRepairDetail(
            coverageViolation: coverageViolation,
            hasFailureMask: hasFailureMask
          )
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
      detail =
        "Plan needs one commit-sized slice plus a verification command before Develop can start."
      planTemplate = Self.template(
        outcome: nil,
        whyItMatters: nil,
        acceptanceChecks: [],
        suggestedVerifyCommand: suggestedVerifyCommand
      )
    } else {
      let missingLabels =
        steps
        .filter { $0.isRequired && !$0.isSatisfied }
        .map(\.title)
      status = .needsRepair
      title = "Make this executable"
      detail =
        "Add \(missingLabels.joined(separator: " and ")) before Develop has a clear finish line."
      planTemplate = Self.template(
        outcome: digest.outcome,
        whyItMatters: digest.whyItMatters,
        acceptanceChecks: digest.acceptanceChecks,
        suggestedVerifyCommand: suggestedVerifyCommand
      )
    }

    detail = StringUtils.boundedText(detail, limit: 220)
  }

  public enum Status: Equatable, Sendable {
    case missingHandoff
    case needsRepair
    case ready
  }

  public struct Step: Identifiable, Equatable, Sendable {
    public var kind: Kind
    public var isSatisfied: Bool
    public var detail: String

    public var id: Kind { kind }
    public var title: String { kind.title }
    public var systemImage: String { isSatisfied ? "checkmark.circle.fill" : kind.systemImage }
    public var isRequired: Bool { kind.isRequired }
  }

  public enum Kind: Equatable, Sendable {
    case outcome
    case acceptanceChecks
    case verifyCommand
    case coverageReadyVerify
    case whyItMatters

    public var title: String {
      switch self {
      case .outcome:
        return "Outcome"
      case .acceptanceChecks:
        return "Acceptance checks"
      case .verifyCommand:
        return "Verify command"
      case .coverageReadyVerify:
        return "Coverage-ready verify"
      case .whyItMatters:
        return "Why"
      }
    }

    public var systemImage: String {
      switch self {
      case .outcome:
        return "target"
      case .acceptanceChecks:
        return "checkmark.seal"
      case .verifyCommand:
        return "terminal"
      case .coverageReadyVerify:
        return "chart.bar.doc.horizontal"
      case .whyItMatters:
        return "person.crop.circle.badge.questionmark"
      }
    }

    public var isRequired: Bool {
      switch self {
      case .outcome, .acceptanceChecks, .verifyCommand, .coverageReadyVerify:
        return true
      case .whyItMatters:
        return false
      }
    }
  }

  private static func verifyRepairDetail(
    coverageViolation: String?,
    hasFailureMask: Bool
  ) -> String {
    if coverageViolation != nil {
      return "Add coverage to the verify command for generated Rust projects."
    }
    if hasFailureMask {
      return "Remove fallback no-op clauses so failed checks still fail."
    }
    return "Choose a real command Compass can run after Develop."
  }

  private static func acceptanceChecksRepairDetail(digest: PlanHandoffDigest) -> String {
    if !digest.commandOnlyAcceptanceChecks.isEmpty {
      return "Replace command-only checks with observable finish-line behavior."
    }
    if !digest.vagueAcceptanceChecks.isEmpty {
      return "Replace vague checks with specific observable finish-line behavior."
    }
    return "List observable finish-line checks."
  }

  private static func suggestedVerifyCommand(
    for profile: RepositoryLanguageProfile
  ) -> String? {
    if let hint = profile.manifestHints.first {
      switch hint {
      case .cargoToml:
        return GeneratedProjectQuality.standardVerifyCommand
      case .packageSwift:
        return "swift test --enable-code-coverage"
      }
    }

    switch profile.primaryLanguage {
    case .swift:
      return "swift test --enable-code-coverage"
    case .rust, .markdown, .other, .unknown:
      return GeneratedProjectQuality.standardVerifyCommand
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
