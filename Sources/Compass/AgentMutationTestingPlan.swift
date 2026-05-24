import Foundation

enum AgentMutationTestingMetadataSanitizer {
  static func sanitizedCommand(
    _ command: String,
    launchPlan: AgentExecutionLaunchPlan,
    limit: Int
  ) -> String {
    sanitizedText(
      command,
      launchPlan: launchPlan,
      limit: limit,
      preservesNewlines: false,
      takesTail: false
    )
  }

  static func sanitizedOutputTail(
    _ output: String,
    launchPlan: AgentExecutionLaunchPlan,
    limit: Int
  ) -> String {
    sanitizedText(
      output,
      launchPlan: launchPlan,
      limit: limit,
      preservesNewlines: true,
      takesTail: true
    )
  }

  private static func sanitizedText(
    _ text: String,
    launchPlan: AgentExecutionLaunchPlan,
    limit: Int,
    preservesNewlines: Bool,
    takesTail: Bool
  ) -> String {
    guard limit > 0 else { return "" }
    let input: String
    if takesTail, text.count > limit {
      let truncationMarker = "...(truncated)...\n"
      let suffixLimit = max(0, limit - truncationMarker.count)
      input = truncationMarker + String(text.suffix(suffixLimit))
    } else {
      input = text
    }

    var sanitized =
      input
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: preservesNewlines ? "\n" : " ")

    if preservesNewlines {
      sanitized =
        sanitized
        .replacingOccurrences(of: #"[ \t\f\v]+"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"\n{4,}"#, with: "\n\n\n", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    } else {
      sanitized =
        sanitized
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    for value in sensitiveValues(from: launchPlan).sorted(by: { $0.count > $1.count })
    where !value.isEmpty {
      sanitized = sanitized.replacingOccurrences(of: value, with: "[redacted]")
    }

    let replacements: [(pattern: String, template: String)] = [
      (#"(^|[\s"'=:/])(?:\./)?\.devcontainer/[^\s"']+"#, "$1[devcontainer-path]"),
      (#"(^|[\s"'=:/])/[^\s"']+"#, "$1[path]"),
    ]

    for replacement in replacements {
      sanitized = sanitized.replacingOccurrences(
        of: replacement.pattern,
        with: replacement.template,
        options: .regularExpression
      )
    }

    return bounded(
      sanitized,
      limit: limit,
      preservesNewlines: preservesNewlines,
      usesSuffix: false
    )
  }

  private static func sensitiveValues(from launchPlan: AgentExecutionLaunchPlan) -> [String] {
    var values: [String] = []

    switch launchPlan.effectiveRoute {
    case .host:
      break
    case .sharedVM(let route):
      values += [
        route.sshDestination,
        route.hostWorktreeURL.path,
        route.guestWorkspacePath,
      ]
      if let identityFile = route.identityFile {
        values.append(identityFile)
      }
      if let knownHostsFile = route.knownHostsFile {
        values.append(knownHostsFile)
      }
      values += route.environmentVariables.values
    }

    return
      values
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  private static func bounded(
    _ text: String,
    limit: Int,
    preservesNewlines: Bool,
    usesSuffix: Bool
  ) -> String {
    guard limit > 0 else { return "" }
    let normalized: String
    if preservesNewlines {
      normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
    } else {
      normalized =
        text
        .replacingOccurrences(of: "\r", with: " ")
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    guard normalized.count > limit else { return normalized }
    let bounded = usesSuffix ? normalized.suffix(limit) : normalized.prefix(limit)
    return String(bounded).trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

struct AgentMutationTestingPlan: Equatable, Identifiable {
  static let identifierMaxCharacters = 260
  static let labelMaxCharacters = 34
  static let statusLabelMaxCharacters = 34
  static let routeLabelMaxCharacters = 34
  static let languageLabelMaxCharacters = 34
  static let commandMaxCharacters = 96
  static let detailMaxCharacters = 220
  static let copyTextMaxCharacters = 560

  enum ReadinessState: String, Equatable {
    case ready
    case missingImmediate = "missing-immediate"
    case missingVerify = "missing-verify"
    case missingMutationCommand = "missing-mutation-command"
    case unsupportedLanguage = "unsupported-language"
  }

  enum RouteState: String, Equatable {
    case nativeRoute = "native-route"
    case sharedVMRoute = "shared-vm-route"
    case nativeFallback = "native-fallback"
  }

  var id: String { identifier }

  var identifier: String
  var statusIdentifier: String
  var routeIdentifier: String
  var languageIdentifier: String
  var seedCommandIdentifier: String
  var isReady: Bool
  var statusLabel: String
  var routeLabel: String
  var languageLabel: String
  var badgeLabel: String
  var systemImage: String
  var seedCommand: String?
  var seedCommandLabel: String
  var mutationCommand: String?
  var mutationCommandLabel: String
  var detailText: String
  var copyText: String

  init(
    state: PlanState,
    languageProfile: RepositoryLanguageProfile,
    launchPlan: AgentExecutionLaunchPlan
  ) {
    self.init(
      immediate: state.immediate,
      languageProfile: languageProfile,
      launchPlan: launchPlan
    )
  }

  init(
    immediate: PlanNext?,
    languageProfile: RepositoryLanguageProfile,
    launchPlan: AgentExecutionLaunchPlan
  ) {
    let language = Self.languageDescriptor(for: languageProfile.primaryLanguage)
    let routeState = Self.routeState(for: launchPlan)
    let rawSeedCommand = immediate?.verify.trimmingCharacters(in: .whitespacesAndNewlines)
    let sanitizedSeedCommand = rawSeedCommand.flatMap {
      AgentMutationTestingMetadataSanitizer.sanitizedCommand(
        $0,
        launchPlan: launchPlan,
        limit: Self.commandMaxCharacters
      )
    }.flatMap(Self.nilIfEmpty)
    let rawMutationCommand = sanitizedSeedCommand.flatMap {
      MutationTestingCommandBuilder.build(
        language: languageProfile.primaryLanguage,
        verifyCommand: $0,
        manifestHints: languageProfile.manifestHints
      )
    }
    let sanitizedMutationCommand = rawMutationCommand.flatMap {
      AgentMutationTestingMetadataSanitizer.sanitizedCommand(
        $0,
        launchPlan: launchPlan,
        limit: Self.commandMaxCharacters
      )
    }.flatMap(Self.nilIfEmpty)

    let readinessState: ReadinessState
    if immediate == nil {
      readinessState = .missingImmediate
    } else if sanitizedSeedCommand == nil {
      readinessState = .missingVerify
    } else if !language.isSupported {
      readinessState = .unsupportedLanguage
    } else if sanitizedMutationCommand == nil {
      readinessState = .missingMutationCommand
    } else {
      readinessState = .ready
    }

    let statusLabel = Self.statusLabel(for: readinessState)
    let routeLabel = Self.routeLabel(for: routeState)
    let seedCommandLabel = sanitizedSeedCommand ?? "none"
    let mutationCommandLabel = sanitizedMutationCommand ?? "none"
    let seedCommandIdentifier = "seed-\(Self.fingerprint(seedCommandLabel))"
    let mutationCommandIdentifier = "mutation-\(Self.fingerprint(mutationCommandLabel))"
    let identifier = Self.bounded(
      [
        "compass-mutation-testing",
        "status:\(readinessState.rawValue)",
        "route:\(routeState.rawValue)",
        "language:\(language.identifier)",
        seedCommandIdentifier,
        mutationCommandIdentifier,
      ].joined(separator: "|"),
      limit: Self.identifierMaxCharacters
    )
    let detailText = Self.detailText(
      readinessState: readinessState,
      routeState: routeState,
      languageLabel: language.label,
      seedCommandLabel: seedCommandLabel,
      mutationCommandLabel: mutationCommandLabel
    )
    let copyText = Self.boundedMultiline(
      [
        "Mutation Testing Readiness",
        "id: \(identifier)",
        "status: \(readinessState.rawValue)",
        "route: \(routeState.rawValue)",
        "language: \(language.identifier)",
        "seed-command: \(seedCommandLabel)",
        "mutation-command: \(mutationCommandLabel)",
        "detail: \(detailText)",
      ].joined(separator: "\n"),
      limit: Self.copyTextMaxCharacters
    )

    self.identifier = identifier
    statusIdentifier = readinessState.rawValue
    routeIdentifier = routeState.rawValue
    languageIdentifier = language.identifier
    self.seedCommandIdentifier = seedCommandIdentifier
    isReady = readinessState == .ready
    self.statusLabel = Self.bounded(statusLabel, limit: Self.statusLabelMaxCharacters)
    self.routeLabel = Self.bounded(routeLabel, limit: Self.routeLabelMaxCharacters)
    languageLabel = Self.bounded(language.label, limit: Self.languageLabelMaxCharacters)
    badgeLabel = Self.bounded(
      readinessState == .ready ? "Mutation: \(routeLabel)" : "Mutation: \(statusLabel)",
      limit: Self.labelMaxCharacters
    )
    systemImage = "testtube.2"
    seedCommand = sanitizedSeedCommand
    self.seedCommandLabel = Self.bounded(seedCommandLabel, limit: Self.commandMaxCharacters)
    mutationCommand = sanitizedMutationCommand
    self.mutationCommandLabel = Self.bounded(
      mutationCommandLabel, limit: Self.commandMaxCharacters)
    self.detailText = detailText
    self.copyText = copyText
  }

  private static func routeState(for launchPlan: AgentExecutionLaunchPlan) -> RouteState {
    switch launchPlan.effectiveRoute {
    case .sharedVM:
      return .sharedVMRoute
    case .host:
      // Compass always targets the Shared VM; a host effective route
      // is an internal fallback (Plan/Reflect on the main repo, or VM
      // not yet ready). `.nativeRoute` is preserved for callers that
      // construct a bare `host()` plan with no fallback reason — used
      // by tests and tooling that want a stable "native execution"
      // label without surfacing fallback semantics.
      if launchPlan.fallbackReason != nil {
        return .nativeFallback
      }
      return .nativeRoute
    }
  }

  private static func languageDescriptor(
    for language: RepositoryLanguage
  ) -> (identifier: String, label: String, isSupported: Bool) {
    switch language {
    case .swift:
      return ("swift", "Swift", true)
    case .typeScriptJavaScript:
      return ("typescript-javascript", "TypeScript/JavaScript", true)
    case .python:
      return ("python", "Python", true)
    case .go:
      return ("go", "Go", true)
    case .rust:
      return ("rust", "Rust", true)
    case .markdown:
      return ("markdown", "Markdown", false)
    case .other:
      return ("other", "Other", false)
    case .unknown:
      return ("unknown", "Unknown", false)
    }
  }

  private static func statusLabel(for state: ReadinessState) -> String {
    switch state {
    case .ready:
      return "Ready"
    case .missingImmediate:
      return "Missing immediate"
    case .missingVerify:
      return "Missing verify"
    case .missingMutationCommand:
      return "Missing command"
    case .unsupportedLanguage:
      return "Unsupported language"
    }
  }

  private static func routeLabel(for state: RouteState) -> String {
    switch state {
    case .nativeRoute:
      return "Native"
    case .sharedVMRoute:
      return "Shared VM"
    case .nativeFallback:
      return "Native fallback"
    }
  }

  private static func detailText(
    readinessState: ReadinessState,
    routeState: RouteState,
    languageLabel: String,
    seedCommandLabel: String,
    mutationCommandLabel: String
  ) -> String {
    let routeDetail: String
    switch routeState {
    case .nativeRoute:
      routeDetail = "native macOS"
    case .sharedVMRoute:
      routeDetail = "Shared VM"
    case .nativeFallback:
      routeDetail = "native macOS fallback"
    }

    let detail: String
    switch readinessState {
    case .ready:
      detail =
        "Verify seed \(seedCommandLabel); mutation pass runs \(mutationCommandLabel) via \(routeDetail)."
    case .missingImmediate:
      detail = "No immediate plan is available for mutation test planning."
    case .missingVerify:
      detail = "Immediate plan has no verify command to seed mutation testing."
    case .missingMutationCommand:
      detail =
        "Could not derive a mutation command for \(languageLabel) from verify seed \(seedCommandLabel)."
    case .unsupportedLanguage:
      detail = "\(languageLabel) is outside the mutation readiness language set."
    }
    return bounded(detail, limit: detailMaxCharacters)
  }

  private static func bounded(_ text: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    let normalized =
      text
      .replacingOccurrences(of: "\r", with: " ")
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalized.count > limit else { return normalized }
    return String(normalized.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func boundedMultiline(_ text: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    let normalized =
      text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalized.count > limit else { return normalized }
    return String(normalized.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func nilIfEmpty(_ text: String) -> String? {
    text.isEmpty ? nil : text
  }

  private static func fingerprint(_ value: String) -> String {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in value.utf8 {
      hash ^= UInt64(byte)
      hash = hash &* 0x100_0000_01b3
    }
    return String(format: "%016llx", hash)
  }
}

struct AgentMutationTestingMenuAction: Equatable, Identifiable {
  static let actionIdentifier = "mutation-testing.run"
  static let titleLimit = 34
  static let descriptionLimit = 220
  static let helpLimit = 420
  static let fieldLimit = 120

  enum ExecutionState: String, Equatable {
    case idle
    case running
    case paused
  }

  var readinessIdentifier: String
  var readinessStatusIdentifier: String
  var routeIdentifier: String
  var languageIdentifier: String
  var seedCommandIdentifier: String
  var seedCommandLabel: String
  var executionStateIdentifier: String
  var availabilityIdentifier: String
  var isEnabled: Bool
  var title: String
  var systemImage: String
  var description: String
  var helpText: String

  var id: String { Self.actionIdentifier }

  init(
    readiness: AgentMutationTestingPlan,
    executionState: ExecutionState = .idle
  ) {
    readinessIdentifier = Self.bounded(readiness.identifier, limit: Self.fieldLimit)
    readinessStatusIdentifier = Self.bounded(readiness.statusIdentifier, limit: Self.fieldLimit)
    routeIdentifier = Self.bounded(readiness.routeIdentifier, limit: Self.fieldLimit)
    languageIdentifier = Self.bounded(readiness.languageIdentifier, limit: Self.fieldLimit)
    seedCommandIdentifier = Self.bounded(readiness.seedCommandIdentifier, limit: Self.fieldLimit)
    seedCommandLabel = Self.bounded(
      readiness.seedCommandLabel, limit: AgentMutationTestingPlan.commandMaxCharacters)
    executionStateIdentifier = executionState.rawValue
    title = Self.bounded("Run Mutation Test", limit: Self.titleLimit)
    systemImage = readiness.systemImage

    let availability: String
    let enabled: Bool
    let help: String
    switch executionState {
    case .running:
      availability = "running"
      enabled = false
      help =
        "Mutation testing is disabled while Compass is running another Plan, Develop, verify, or mutation command."
    case .paused:
      availability = "paused"
      enabled = false
      help =
        "Mutation testing is disabled while this project is paused; resume or stop before running the opt-in mutation command."
    case .idle:
      if readiness.isReady {
        if readiness.routeIdentifier == AgentMutationTestingPlan.RouteState.nativeFallback.rawValue
        {
          availability = "native-fallback"
          enabled = true
          help =
            "Run the current immediate verify command through native macOS fallback. Native execution remains available when the Shared VM is not ready."
        } else {
          availability = "ready"
          enabled = true
          help =
            "Run the current immediate verify command as an opt-in mutation test seed through \(readiness.routeLabel)."
        }
      } else {
        availability = readiness.statusIdentifier
        enabled = false
        switch readiness.statusIdentifier {
        case AgentMutationTestingPlan.ReadinessState.missingImmediate.rawValue:
          help = "Mutation testing needs a current immediate Plan item before it can run."
        case AgentMutationTestingPlan.ReadinessState.missingVerify.rawValue:
          help =
            "Mutation testing needs the current immediate Plan item to include a verify command."
        case AgentMutationTestingPlan.ReadinessState.missingMutationCommand.rawValue:
          help =
            "Mutation testing could not derive a mutation command from the current verify seed for \(readiness.languageLabel)."
        case AgentMutationTestingPlan.ReadinessState.unsupportedLanguage.rawValue:
          help =
            "Mutation testing is unavailable for \(readiness.languageLabel); supported seed languages are Swift, TypeScript/JavaScript, Python, Go, and Rust."
        default:
          help = readiness.detailText
        }
      }
    }

    availabilityIdentifier = Self.bounded(availability, limit: Self.fieldLimit)
    isEnabled = enabled
    description = Self.bounded(
      "Runs the derived mutation command after successful Develop when auto mode is enabled, or on demand here. Records bounded sanitized mutation metadata plus a runtime route snapshot.",
      limit: Self.descriptionLimit
    )
    helpText = Self.bounded(help, limit: Self.helpLimit)
  }

  private static func bounded(_ text: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    let normalized =
      text
      .replacingOccurrences(of: "\r", with: " ")
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalized.count > limit else { return normalized }
    return String(normalized.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
