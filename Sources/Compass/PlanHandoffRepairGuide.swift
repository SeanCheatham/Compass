import Foundation

struct PlanHandoffRepairGuide: Equatable, Sendable {
  static let templateLimit = 720
  static let identifierLimit = 1_200

  var status: Status
  var title: String
  var detail: String
  var scoreLabel: String
  var steps: [Step]
  var suggestedVerifyCommand: String?
  var planTemplate: String?
  var narrationIdentifier: String

  var shouldShow: Bool {
    status != .ready
  }

  var allowsNarration: Bool {
    shouldShow && !narrationIdentifier.isEmpty
  }

  init(
    plan rawPlan: String?,
    verify rawVerify: String?,
    languageProfile: RepositoryLanguageProfile,
    forgeProfile: ForgeProfile? = nil
  ) {
    let digest = PlanHandoffDigest(plan: rawPlan)
    let verifyCommand = PlanVerifyCommandPolicy.normalizedCommand(rawVerify)
    let hasFailureMask = verifyCommand.map(PlanVerifyCommandPolicy.masksFailures) ?? false
    let hasRealVerify =
      verifyCommand.map { !PlanVerifyCommandPolicy.isPlaceholder($0) && !hasFailureMask } ?? false
    let coverageViolation =
      hasRealVerify
      ? verifyCommand.flatMap {
        ForgeVerifyValidator.coverageViolation(verify: $0, profile: forgeProfile)
      }
      : nil
    let hasUsableVerify = hasRealVerify && coverageViolation == nil
    suggestedVerifyCommand =
      hasUsableVerify
      ? verifyCommand
      : Self.suggestedVerifyCommand(for: languageProfile, forgeProfile: forgeProfile)

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
            hasFailureMask: hasFailureMask,
            forgeProfile: forgeProfile
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
    narrationIdentifier = Self.narrationIdentifier(
      status: status,
      title: title,
      detail: detail,
      scoreLabel: scoreLabel,
      steps: steps,
      suggestedVerifyCommand: suggestedVerifyCommand
    )
  }

  enum Status: Equatable, Sendable {
    case missingHandoff
    case needsRepair
    case ready

    var narrationKey: String {
      switch self {
      case .missingHandoff:
        return "missingHandoff"
      case .needsRepair:
        return "needsRepair"
      case .ready:
        return "ready"
      }
    }
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
    case coverageReadyVerify
    case whyItMatters

    var title: String {
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

    var systemImage: String {
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

    var isRequired: Bool {
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
    hasFailureMask: Bool,
    forgeProfile: ForgeProfile?
  ) -> String {
    if coverageViolation != nil, let forgeProfile {
      return "Add coverage to the verify command for \(forgeProfile.displayName)."
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
    for profile: RepositoryLanguageProfile,
    forgeProfile: ForgeProfile?
  ) -> String? {
    if let forgeProfile {
      return coverageReadyVerifyCommand(for: forgeProfile)
    }

    if let hint = profile.manifestHints.first {
      switch hint {
      case .packageJSON:
        return coverageReadyVerifyCommand(for: .typeScriptPnpmVite)
      case .packageSwift:
        return "swift test"
      }
    }

    switch profile.primaryLanguage {
    case .swift:
      return "swift test"
    case .typeScriptJavaScript:
      return coverageReadyVerifyCommand(for: .typeScriptPnpmVite)
    case .markdown, .other, .unknown:
      return coverageReadyVerifyCommand(for: ForgeProfile.generatedProjectDefault)
    }
  }

  private static func coverageReadyVerifyCommand(for forgeProfile: ForgeProfile) -> String {
    switch forgeProfile {
    case .swiftSPM:
      return "swift test --enable-code-coverage"
    case .typeScriptPnpmVite:
      return "pnpm verify"
    case .tesseraApp:
      return "tessera verify . --json"
    }
  }

  private static func narrationIdentifier(
    status: Status,
    title: String,
    detail: String,
    scoreLabel: String,
    steps: [Step],
    suggestedVerifyCommand: String?
  ) -> String {
    let stepFragment = steps.map { step in
      "\(step.kind.narrationKey):satisfied:\(step.isSatisfied):required:\(step.isRequired):\(step.detail)"
    }.joined(separator: "|")

    return StringUtils.boundedText(
      [
        "status:\(status.narrationKey)",
        "title:\(title)",
        "detail:\(detail)",
        "score:\(scoreLabel)",
        "steps:\(stepFragment)",
        "suggestedVerify:\(suggestedVerifyCommand ?? "")",
      ].joined(separator: "\n"),
      limit: Self.identifierLimit
    )
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

extension PlanHandoffRepairGuide.Kind {
  fileprivate var narrationKey: String {
    switch self {
    case .outcome:
      return "outcome"
    case .acceptanceChecks:
      return "acceptanceChecks"
    case .verifyCommand:
      return "verifyCommand"
    case .coverageReadyVerify:
      return "coverageReadyVerify"
    case .whyItMatters:
      return "whyItMatters"
    }
  }
}
