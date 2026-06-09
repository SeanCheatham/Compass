import Foundation

struct ProjectRunControlGuide: Equatable {
  static let identifierLimit = 1_200
  static let previewDetailLimit = 180

  var primaryHelp: String
  var primaryKind: Kind
  var readiness: Readiness
  var decisionBadge: DecisionBadge
  var options: [Option]
  var previewSteps: [PreviewStep]
  var narrationIdentifier: String

  var allowsNarration: Bool {
    !narrationIdentifier.isEmpty && readiness.title != "Run in progress"
  }

  var primaryOption: Option {
    options.first { $0.kind == primaryKind } ?? options[0]
  }

  var alternativeOptions: [Option] {
    options.filter { $0.kind != primaryOption.kind }
  }

  init(
    state: PlanState,
    reliabilityStatus: ProjectReliabilityStatus,
    hasRepository: Bool,
    isRunning: Bool,
    isAutoPlaying: Bool,
    isPaused: Bool,
    languageProfile: RepositoryLanguageProfile = .empty,
    forgeProfile: ForgeProfile? = nil,
    drafts: String = "",
    vision: String? = nil
  ) {
    let canStart = hasRepository && !isRunning && !isAutoPlaying
    let draftIntakeGuide = DraftIntakeGuide(drafts: drafts)
    let visionGuide = vision.map(ProjectVisionGuide.init(vision:))
    let handoffReadiness = HandoffReadiness(
      state: state,
      languageProfile: languageProfile,
      forgeProfile: forgeProfile
    )
    let hasImmediate = handoffReadiness.hasImmediate
    let canDevelop = hasImmediate && handoffReadiness.canDevelop
    readiness = Self.readiness(
      handoffReadiness: handoffReadiness,
      reliabilityStatus: reliabilityStatus,
      hasRepository: hasRepository,
      isRunning: isRunning,
      isAutoPlaying: isAutoPlaying,
      isPaused: isPaused,
      draftIntakeGuide: draftIntakeGuide,
      visionGuide: visionGuide
    )
    decisionBadge = Self.decisionBadge(
      handoffReadiness: handoffReadiness,
      reliabilityStatus: reliabilityStatus,
      hasRepository: hasRepository,
      isRunning: isRunning,
      isAutoPlaying: isAutoPlaying,
      isPaused: isPaused,
      draftIntakeGuide: draftIntakeGuide,
      visionGuide: visionGuide
    )
    primaryKind = Self.primaryKind(
      reliabilityStatus: reliabilityStatus,
      hasImmediate: hasImmediate,
      canDevelop: canDevelop,
      isPaused: isPaused
    )
    let resumeCopy = isPaused ? "Resume the factory loop from its paused gate." : nil
    let recoveryCopy =
      reliabilityStatus.isEmpty
      ? nil
      : "\(reliabilityStatus.primaryCue): \(reliabilityStatus.actionLabel)."
    let loopDetail: String
    if let resumeCopy {
      loopDetail = resumeCopy
    } else if let recoveryCopy {
      loopDetail = recoveryCopy
    } else if hasImmediate && !handoffReadiness.canDevelop {
      loopDetail =
        "Ask Plan to repair Immediate Work, then continue only if the handoff becomes executable."
    } else if hasImmediate {
      loopDetail = "Let Compass plan, develop, verify, review, and keep going."
    } else if !draftIntakeGuide.isEmpty {
      loopDetail = Self.loopDetail(draftIntakeGuide: draftIntakeGuide)
    } else if Self.needsVisionBeforePlan(
      handoffReadiness: handoffReadiness,
      draftIntakeGuide: draftIntakeGuide,
      visionGuide: visionGuide
    ) {
      loopDetail =
        "Capture Project Vision first, or let Plan infer the next slice from the repository."
    } else {
      loopDetail = "Let Plan choose the next slice, then Develop it if one is found."
    }

    options = [
      Option(
        kind: .loop,
        title: isPaused ? "Resume Loop" : "Run Loop",
        detail: loopDetail,
        systemImage: "play.circle.fill",
        isEnabled: canStart
      ),
      Option(
        kind: .planOnly,
        title: Self.planOnlyTitle(for: reliabilityStatus),
        detail: Self.planOnlyDetail(
          reliabilityStatus: reliabilityStatus,
          handoffReadiness: handoffReadiness,
          draftIntakeGuide: draftIntakeGuide,
          visionGuide: visionGuide
        ),
        systemImage: "map",
        isEnabled: canStart
      ),
      Option(
        kind: .developOnly,
        title: Self.developOnlyTitle(for: reliabilityStatus),
        detail: Self.developOnlyDetail(
          reliabilityStatus: reliabilityStatus,
          handoffReadiness: handoffReadiness
        ),
        systemImage: "hammer.fill",
        isEnabled: canStart && canDevelop
      ),
    ]

    previewSteps = Self.previewSteps(
      state: state,
      primaryKind: primaryKind,
      reliabilityStatus: reliabilityStatus,
      handoffReadiness: handoffReadiness,
      hasRepository: hasRepository,
      isRunning: isRunning,
      isAutoPlaying: isAutoPlaying,
      isPaused: isPaused,
      draftIntakeGuide: draftIntakeGuide,
      visionGuide: visionGuide
    )

    primaryHelp = Self.primaryHelp(
      hasRepository: hasRepository,
      isRunning: isRunning,
      isAutoPlaying: isAutoPlaying,
      isPaused: isPaused,
      hasImmediate: hasImmediate,
      handoffReadiness: handoffReadiness,
      reliabilityStatus: reliabilityStatus,
      draftIntakeGuide: draftIntakeGuide,
      visionGuide: visionGuide
    )
    narrationIdentifier = Self.narrationIdentifier(
      primaryHelp: primaryHelp,
      primaryKind: primaryKind,
      readiness: readiness,
      decisionBadge: decisionBadge,
      options: options,
      previewSteps: previewSteps
    )
  }

  enum Kind: Hashable {
    case loop
    case planOnly
    case developOnly

    var narrationKey: String {
      switch self {
      case .loop:
        return "loop"
      case .planOnly:
        return "planOnly"
      case .developOnly:
        return "developOnly"
      }
    }
  }

  struct Readiness: Equatable {
    var title: String
    var detail: String
    var systemImage: String
  }

  struct DecisionBadge: Equatable {
    static let labelLimit = 32
    static let detailLimit = 150

    var label: String
    var detail: String
    var systemImage: String
    var tone: Tone

    enum Tone: String, Equatable {
      case ready
      case info
      case warning
      case failure
      case paused
    }
  }

  struct Option: Identifiable, Equatable {
    var kind: Kind
    var title: String
    var detail: String
    var systemImage: String
    var isEnabled: Bool

    var id: Kind { kind }
  }

  struct PreviewStep: Identifiable, Equatable {
    var id: String
    var title: String
    var detail: String
    var systemImage: String
  }

  private static func primaryKind(
    reliabilityStatus: ProjectReliabilityStatus,
    hasImmediate: Bool,
    canDevelop: Bool,
    isPaused: Bool
  ) -> Kind {
    if isPaused {
      return .loop
    }

    if hasImmediate && !canDevelop {
      switch reliabilityStatus.primaryKind {
      case .dirtyWorktree, .promotionFailed:
        return .loop
      case .rejectedPlan, .resumeDevelop, .developBlocked, .developFailed, .failedVerify, nil:
        return .planOnly
      }
    }

    switch reliabilityStatus.primaryKind {
    case .rejectedPlan:
      return .planOnly
    case .resumeDevelop:
      return hasImmediate ? .developOnly : .planOnly
    case .developBlocked, .developFailed, .failedVerify:
      return hasImmediate ? .developOnly : .planOnly
    case .dirtyWorktree, .promotionFailed, nil:
      return .loop
    }
  }

  private static func planOnlyTitle(for reliabilityStatus: ProjectReliabilityStatus) -> String {
    reliabilityStatus.primaryKind == .rejectedPlan ? "Retry Plan" : "Run Plan Only"
  }

  private static func planOnlyDetail(
    reliabilityStatus: ProjectReliabilityStatus,
    handoffReadiness: HandoffReadiness,
    draftIntakeGuide: DraftIntakeGuide,
    visionGuide: ProjectVisionGuide?
  ) -> String {
    if reliabilityStatus.primaryKind == .rejectedPlan {
      return "Ask Plan to repair the rejected handoff before Develop starts."
    }

    if handoffReadiness.hasImmediate && !handoffReadiness.canDevelop {
      return Self.withRepairDetail(
        "Ask Plan to add \(handoffReadiness.missingLabel) before Develop starts.",
        handoffReadiness: handoffReadiness
      )
    }

    if !handoffReadiness.hasImmediate, !draftIntakeGuide.isEmpty {
      return Self.planOnlyDetail(draftIntakeGuide: draftIntakeGuide)
    }

    if Self.needsVisionBeforePlan(
      handoffReadiness: handoffReadiness,
      draftIntakeGuide: draftIntakeGuide,
      visionGuide: visionGuide
    ) {
      return
        "Capture Project Vision first, or ask Plan to infer one executable next slice for review."
    }

    return handoffReadiness.hasImmediate
      ? "Ask Plan to refine or replace the next slice, then stop before Develop."
      : "Ask Plan to choose one executable next slice, then stop for review."
  }

  private static func previewSteps(
    state: PlanState,
    primaryKind: Kind,
    reliabilityStatus: ProjectReliabilityStatus,
    handoffReadiness: HandoffReadiness,
    hasRepository: Bool,
    isRunning: Bool,
    isAutoPlaying: Bool,
    isPaused: Bool,
    draftIntakeGuide: DraftIntakeGuide,
    visionGuide: ProjectVisionGuide?
  ) -> [PreviewStep] {
    if !hasRepository {
      return [
        PreviewStep(
          id: "repository",
          title: "Add a repository",
          detail: "Choose a Git repository before Compass can run the factory loop.",
          systemImage: "folder.badge.plus"
        )
      ]
    }

    if isRunning || isAutoPlaying {
      return [
        PreviewStep(
          id: "inProgress",
          title: "Finish the current run",
          detail: "Compass is already running this project.",
          systemImage: "play.circle"
        )
      ]
    }

    if isPaused {
      return [
        PreviewStep(
          id: "resume",
          title: "Resume from the gate",
          detail: "Compass will continue from the paused factory gate.",
          systemImage: "pause.circle"
        )
      ]
    }

    if !reliabilityStatus.isEmpty {
      return [
        PreviewStep(
          id: "attention",
          title: reliabilityStatus.actionLabel,
          detail: "\(reliabilityStatus.primaryCue): \(reliabilityStatus.detail)",
          systemImage: reliabilityStatus.systemImage
        ),
        PreviewStep(
          id: "continue",
          title: primaryKind == .planOnly ? "Repair before Develop" : "Keep the issue visible",
          detail: primaryKind == .planOnly
            ? "Plan runs first so the next handoff is executable before Develop starts."
            : "Develop retries the current slice with the captured issue still attached.",
          systemImage: primaryKind == .planOnly ? "map" : "hammer.fill"
        ),
      ]
    }

    switch primaryKind {
    case .planOnly:
      return planPreviewSteps(
        handoffReadiness: handoffReadiness,
        draftIntakeGuide: draftIntakeGuide,
        visionGuide: visionGuide
      )
    case .developOnly:
      return developPreviewSteps(state: state)
    case .loop:
      if handoffReadiness.canDevelop, state.immediate != nil {
        return developPreviewSteps(state: state)
          + [
            PreviewStep(
              id: "review",
              title: "Review and continue",
              detail: "Verify and Critic run after Develop, then Compass chooses the next gate.",
              systemImage: "checkmark.seal"
            )
          ]
      }
      return [
        PreviewStep(
          id: "plan",
          title: "Plan one slice",
          detail: planPreviewDetail(
            handoffReadiness: handoffReadiness,
            draftIntakeGuide: draftIntakeGuide,
            visionGuide: visionGuide
          ),
          systemImage: "map"
        ),
        PreviewStep(
          id: "develop",
          title: "Develop in the private workspace",
          detail: "Develop edits the selected slice inside your private workspace.",
          systemImage: "hammer.fill"
        ),
        PreviewStep(
          id: "verify",
          title: "Verify and review",
          detail:
            "Compass runs the saved check, records feedback, and decides whether to continue.",
          systemImage: "checkmark.seal"
        ),
      ]
    }
  }

  private static func planPreviewSteps(
    handoffReadiness: HandoffReadiness,
    draftIntakeGuide: DraftIntakeGuide,
    visionGuide: ProjectVisionGuide?
  ) -> [PreviewStep] {
    [
      PreviewStep(
        id: "plan",
        title: "Plan one slice",
        detail: planPreviewDetail(
          handoffReadiness: handoffReadiness,
          draftIntakeGuide: draftIntakeGuide,
          visionGuide: visionGuide
        ),
        systemImage: "map"
      ),
      PreviewStep(
        id: "stop",
        title: "Stop for review",
        detail: "Compass stops before Develop so you can inspect the handoff.",
        systemImage: "pause.circle"
      ),
    ]
  }

  private static func planPreviewDetail(
    handoffReadiness: HandoffReadiness,
    draftIntakeGuide: DraftIntakeGuide,
    visionGuide: ProjectVisionGuide?
  ) -> String {
    if handoffReadiness.hasImmediate && !handoffReadiness.canDevelop {
      return Self.withRepairDetail(
        "Plan will add \(handoffReadiness.missingLabel) so Develop has a clear finish line.",
        handoffReadiness: handoffReadiness
      )
    }

    if !draftIntakeGuide.isEmpty {
      return
        "\(draftIntakeGuide.planScope.summary) Plan will create one executable handoff.\(draftQueueScopeSuffix(draftIntakeGuide))"
    }

    if Self.needsVisionBeforePlan(
      handoffReadiness: handoffReadiness,
      draftIntakeGuide: draftIntakeGuide,
      visionGuide: visionGuide
    ) {
      return
        "Project Vision is empty; Plan will otherwise infer one executable next slice from the repository."
    }

    return "Plan will choose one executable next slice from the repository and strategic context."
  }

  private static func developPreviewSteps(state: PlanState) -> [PreviewStep] {
    guard let immediate = state.immediate else {
      return [
        PreviewStep(
          id: "plan",
          title: "Plan first",
          detail: "Develop is disabled until Plan selects Immediate Work.",
          systemImage: "map"
        )
      ]
    }

    let digest = PlanHandoffDigest(plan: immediate.plan)
    let outcome = digest.outcome ?? "Use the current Immediate Work."
    return [
      PreviewStep(
        id: "develop",
        title: "Develop current slice",
        detail: StringUtils.boundedText(outcome, limit: previewDetailLimit),
        systemImage: "hammer.fill"
      ),
      PreviewStep(
        id: "verify",
        title: "Run verification",
        detail:
          "Compass runs: \(StringUtils.boundedText(immediate.verify, limit: previewDetailLimit))",
        systemImage: "terminal"
      ),
    ]
  }

  private static func developOnlyTitle(for reliabilityStatus: ProjectReliabilityStatus) -> String {
    switch reliabilityStatus.primaryKind {
    case .resumeDevelop:
      return "Resume Develop"
    case .developBlocked, .developFailed, .failedVerify:
      return "Retry Develop"
    case .rejectedPlan, .dirtyWorktree, .promotionFailed, nil:
      return "Run Develop Only"
    }
  }

  private static func developOnlyDetail(
    reliabilityStatus: ProjectReliabilityStatus,
    handoffReadiness: HandoffReadiness
  ) -> String {
    guard handoffReadiness.hasImmediate else {
      return "Disabled until Plan selects Immediate Work."
    }

    guard handoffReadiness.canDevelop else {
      return Self.withRepairDetail(
        "Disabled until Immediate Work has \(handoffReadiness.missingLabel).",
        handoffReadiness: handoffReadiness
      )
    }

    switch reliabilityStatus.primaryKind {
    case .resumeDevelop:
      return "Start Develop from the saved Immediate Work."
    case .developBlocked, .developFailed, .failedVerify:
      return "Retry the current Immediate Work with the captured issue still visible."
    case .rejectedPlan, .dirtyWorktree, .promotionFailed, nil:
      return "Build the current Immediate Work now, using the saved verify command."
    }
  }

  private static func decisionBadge(
    handoffReadiness: HandoffReadiness,
    reliabilityStatus: ProjectReliabilityStatus,
    hasRepository: Bool,
    isRunning: Bool,
    isAutoPlaying: Bool,
    isPaused: Bool,
    draftIntakeGuide: DraftIntakeGuide,
    visionGuide: ProjectVisionGuide?
  ) -> DecisionBadge {
    if !hasRepository {
      return badge(
        label: "Needs repo",
        detail: "Add a Git repository before any factory run can start.",
        systemImage: "folder.badge.plus",
        tone: .warning
      )
    }

    if isRunning || isAutoPlaying {
      return badge(
        label: "Running",
        detail: "Compass is already working through this project.",
        systemImage: "play.circle",
        tone: .info
      )
    }

    if isPaused {
      return badge(
        label: "Paused",
        detail: "Resume from the current factory gate when you are ready.",
        systemImage: "pause.circle",
        tone: .paused
      )
    }

    if !reliabilityStatus.isEmpty {
      return badge(
        label: reliabilityStatus.primaryCue,
        detail: "\(reliabilityStatus.actionLabel). \(reliabilityStatus.detail)",
        systemImage: reliabilityStatus.systemImage,
        tone: tone(for: reliabilityStatus.severity)
      )
    }

    if handoffReadiness.hasImmediate && !handoffReadiness.canDevelop {
      return badge(
        label: "Repair first",
        detail: Self.withRepairDetail(
          "Plan should add \(handoffReadiness.missingLabel) before Develop.",
          handoffReadiness: handoffReadiness
        ),
        systemImage: "list.bullet.clipboard",
        tone: .warning
      )
    }

    if handoffReadiness.canDevelop {
      return badge(
        label: "Ready",
        detail: "Immediate Work has an outcome, acceptance checks, and a verify command.",
        systemImage: "checkmark.seal",
        tone: .ready
      )
    }

    if !draftIntakeGuide.isEmpty {
      switch draftIntakeGuide.status {
      case .ready:
        return badge(
          label: "Draft queue",
          detail: draftIntakeGuide.planScope.summary,
          systemImage: "text.badge.checkmark",
          tone: .info
        )
      case .needsDetail:
        return badge(
          label: "Draft details",
          detail: draftIntakeGuide.detail,
          systemImage: "list.bullet.clipboard",
          tone: .warning
        )
      case .empty:
        break
      }
    }

    if Self.needsVisionBeforePlan(
      handoffReadiness: handoffReadiness,
      draftIntakeGuide: draftIntakeGuide,
      visionGuide: visionGuide
    ) {
      return badge(
        label: "Vision first",
        detail:
          "Project Vision is empty. Add audience, problem, success, and guardrails before the first Plan when possible.",
        systemImage: "scope",
        tone: .warning
      )
    }

    return badge(
      label: "Plan first",
      detail: "Plan should choose one executable slice before Develop starts.",
      systemImage: "map",
      tone: .info
    )
  }

  private static func badge(
    label: String,
    detail: String,
    systemImage: String,
    tone: DecisionBadge.Tone
  ) -> DecisionBadge {
    DecisionBadge(
      label: StringUtils.boundedText(label, limit: DecisionBadge.labelLimit),
      detail: StringUtils.boundedText(detail, limit: DecisionBadge.detailLimit),
      systemImage: systemImage,
      tone: tone
    )
  }

  private static func tone(
    for severity: PlanReliabilityFeedback.Severity
  ) -> DecisionBadge.Tone {
    switch severity {
    case .warning:
      return .warning
    case .failure:
      return .failure
    case .paused:
      return .paused
    }
  }

  private static func readiness(
    handoffReadiness: HandoffReadiness,
    reliabilityStatus: ProjectReliabilityStatus,
    hasRepository: Bool,
    isRunning: Bool,
    isAutoPlaying: Bool,
    isPaused: Bool,
    draftIntakeGuide: DraftIntakeGuide,
    visionGuide: ProjectVisionGuide?
  ) -> Readiness {
    if !hasRepository {
      return Readiness(
        title: "Repository needed",
        detail: "Add a Git repository before running the factory loop.",
        systemImage: "folder.badge.plus"
      )
    }

    if isRunning || isAutoPlaying {
      return Readiness(
        title: "Run in progress",
        detail: "Compass is already running this project.",
        systemImage: "play.circle"
      )
    }

    if isPaused {
      return Readiness(
        title: "Paused at gate",
        detail: "Resume the loop or choose a different pause point.",
        systemImage: "pause.circle"
      )
    }

    if !reliabilityStatus.isEmpty {
      return Readiness(
        title: reliabilityStatus.primaryCue,
        detail: "\(reliabilityStatus.actionLabel). \(reliabilityStatus.detail)",
        systemImage: reliabilityStatus.systemImage
      )
    }

    if handoffReadiness.hasImmediate && !handoffReadiness.canDevelop {
      return Readiness(
        title: "Plan repair needed",
        detail: Self.withRepairDetail(
          "Immediate Work needs \(handoffReadiness.missingLabel) before Develop.",
          handoffReadiness: handoffReadiness
        ),
        systemImage: "list.bullet.clipboard"
      )
    }

    if handoffReadiness.canDevelop {
      return Readiness(
        title: "Ready for Develop",
        detail: "Immediate Work has an outcome, acceptance checks, and a runnable verify command.",
        systemImage: "checkmark.seal"
      )
    }

    if !draftIntakeGuide.isEmpty {
      return Readiness(
        title: draftIntakeGuide.status == .ready ? "Drafts ready for Plan" : "Drafts need detail",
        detail: draftIntakeGuide.detail,
        systemImage: draftIntakeGuide.status == .ready ? "checkmark.seal" : "list.bullet.clipboard"
      )
    }

    if Self.needsVisionBeforePlan(
      handoffReadiness: handoffReadiness,
      draftIntakeGuide: draftIntakeGuide,
      visionGuide: visionGuide
    ) {
      return Readiness(
        title: "Vision missing",
        detail:
          "Capture Project Vision before Plan so the first slice has audience, problem, success, and guardrails.",
        systemImage: "scope"
      )
    }

    return Readiness(
      title: "Plan needed",
      detail: "Plan should choose one executable next slice before Develop.",
      systemImage: "map"
    )
  }

  private static func primaryHelp(
    hasRepository: Bool,
    isRunning: Bool,
    isAutoPlaying: Bool,
    isPaused: Bool,
    hasImmediate: Bool,
    handoffReadiness: HandoffReadiness,
    reliabilityStatus: ProjectReliabilityStatus,
    draftIntakeGuide: DraftIntakeGuide,
    visionGuide: ProjectVisionGuide?
  ) -> String {
    if !hasRepository {
      return "Add a Git repository before running the factory loop."
    }
    if isRunning || isAutoPlaying {
      return "Compass is already running."
    }
    if isPaused {
      return "Choose how to resume the paused factory loop."
    }
    if !reliabilityStatus.isEmpty {
      return "\(reliabilityStatus.primaryCue): \(reliabilityStatus.actionLabel)"
    }
    if hasImmediate && !handoffReadiness.canDevelop {
      return Self.withRepairDetail(
        "Repair Immediate Work before Develop: add \(handoffReadiness.missingLabel).",
        handoffReadiness: handoffReadiness
      )
    }
    if hasImmediate {
      return "Choose whether to run the full loop, re-plan, or develop the current slice."
    }
    if !draftIntakeGuide.isEmpty {
      let scopePrefix = draftQueueScope(draftIntakeGuide).map { "\($0) " } ?? ""
      return
        "\(draftIntakeGuide.planScope.summary) \(scopePrefix)Plan will turn the queue into one executable slice."
    }
    if Self.needsVisionBeforePlan(
      handoffReadiness: handoffReadiness,
      draftIntakeGuide: draftIntakeGuide,
      visionGuide: visionGuide
    ) {
      return
        "Capture Project Vision first, or run Plan if you want Compass to infer a starting slice."
    }
    return "Run Plan first, or let the full loop choose and build the next slice."
  }

  private static func loopDetail(draftIntakeGuide: DraftIntakeGuide) -> String {
    switch draftIntakeGuide.status {
    case .empty:
      return "Let Plan choose the next slice, then Develop it if one is found."
    case .ready:
      return
        "\(draftIntakeGuide.planScope.summary) Plan will choose one executable slice, then Develop it.\(draftQueueScopeSuffix(draftIntakeGuide))"
    case .needsDetail:
      return
        "\(draftIntakeGuide.planScope.summary) Drafts shows missing signals before Develop starts.\(draftQueueScopeSuffix(draftIntakeGuide))"
    }
  }

  private static func planOnlyDetail(draftIntakeGuide: DraftIntakeGuide) -> String {
    switch draftIntakeGuide.status {
    case .empty:
      return "Ask Plan to choose one executable next slice, then stop for review."
    case .ready:
      return
        "\(draftIntakeGuide.planScope.summary) Ask Plan to create one executable handoff.\(draftQueueScopeSuffix(draftIntakeGuide))"
    case .needsDetail:
      return
        "\(draftIntakeGuide.planScope.summary) Ask Plan to use ready drafts and keep unclear drafts queued.\(draftQueueScopeSuffix(draftIntakeGuide))"
    }
  }

  private static func draftQueueScope(_ draftIntakeGuide: DraftIntakeGuide) -> String? {
    guard draftIntakeGuide.isCapped else { return nil }
    return
      "Drafts is checking the first \(draftIntakeGuide.entries.count); \(draftIntakeGuide.hiddenCountSentence) in the raw queue."
  }

  private static func draftQueueScopeSuffix(_ draftIntakeGuide: DraftIntakeGuide) -> String {
    guard let scope = draftQueueScope(draftIntakeGuide) else { return "" }
    return " \(scope)"
  }

  private static func needsVisionBeforePlan(
    handoffReadiness: HandoffReadiness,
    draftIntakeGuide: DraftIntakeGuide,
    visionGuide: ProjectVisionGuide?
  ) -> Bool {
    !handoffReadiness.hasImmediate
      && draftIntakeGuide.isEmpty
      && visionGuide?.isEmpty == true
  }

  private static func withRepairDetail(
    _ message: String,
    handoffReadiness: HandoffReadiness
  ) -> String {
    guard !handoffReadiness.repairDetail.isEmpty else {
      return message
    }
    return "\(message) \(handoffReadiness.repairDetail)"
  }

  private static func narrationIdentifier(
    primaryHelp: String,
    primaryKind: Kind,
    readiness: Readiness,
    decisionBadge: DecisionBadge,
    options: [Option],
    previewSteps: [PreviewStep]
  ) -> String {
    let optionFragment = options.map { option in
      "\(option.kind.narrationKey):\(option.title):\(option.detail):enabled:\(option.isEnabled)"
    }.joined(separator: "|")
    let previewFragment = previewSteps.map { step in
      "\(step.id):\(step.title):\(step.detail)"
    }.joined(separator: "|")

    return StringUtils.boundedText(
      [
        "primary:\(primaryKind.narrationKey)",
        "help:\(primaryHelp)",
        "readiness:\(readiness.title):\(readiness.detail)",
        "signal:\(decisionBadge.label):\(decisionBadge.detail):\(decisionBadge.tone.rawValue)",
        "options:\(optionFragment)",
        "preview:\(previewFragment)",
      ].joined(separator: "\n"),
      limit: Self.identifierLimit
    )
  }

  private struct HandoffReadiness: Equatable {
    var hasImmediate: Bool
    var canDevelop: Bool
    var missingLabel: String
    var repairDetail: String

    init(
      state: PlanState,
      languageProfile: RepositoryLanguageProfile,
      forgeProfile: ForgeProfile?
    ) {
      hasImmediate = state.immediate != nil
      let repairGuide = PlanHandoffRepairGuide(
        plan: state.immediate?.plan,
        verify: state.immediate?.verify,
        languageProfile: languageProfile,
        forgeProfile: forgeProfile
      )
      canDevelop = repairGuide.status == .ready
      let missingSteps = repairGuide.steps
        .filter { $0.isRequired && !$0.isSatisfied }
      let missing = missingSteps.map(\.title)
      missingLabel =
        missing.isEmpty
        ? "an executable handoff"
        : missing.joined(separator: " and ")
      repairDetail =
        missingSteps
        .map(\.detail)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }
  }
}

struct ProjectRunControlClipboardPayload: Equatable, Sendable {
  static let textLimit = 3_200

  var text: String

  init(guide: ProjectRunControlGuide) {
    var sections: [String] = [
      "Compass Run Controls Handoff",
      "",
      "Recipient instructions:",
      "- Treat this packet as bounded run-control context. Do not invent repository state, hidden run modes, completed work, verification results, or model output.",
      "- Use the Primary action as the safest default only when its option is enabled.",
      "- Disabled options stay disabled until the named readiness or repair detail changes.",
      "- Develop may start only when Readiness says Ready for Develop or an attention state explicitly says to retry or resume Develop.",
      "",
      "Primary: \(guide.primaryOption.title) (\(Self.kindLabel(guide.primaryOption.kind)), \(Self.enabledLabel(guide.primaryOption)))",
      "Primary help: \(guide.primaryHelp)",
      "Readiness: \(guide.readiness.title) - \(guide.readiness.detail)",
      "Run signal: \(guide.decisionBadge.label) - \(guide.decisionBadge.detail)",
      "",
      "Run modes:",
    ]

    for option in guide.options {
      sections.append(
        "- [\(Self.enabledLabel(option))] \(option.title) (\(Self.kindLabel(option.kind))): \(option.detail)"
      )
    }

    sections.append("")
    sections.append("Next run preview:")

    if guide.previewSteps.isEmpty {
      sections.append("- No preview steps are available.")
    } else {
      for step in guide.previewSteps {
        sections.append("- \(step.title): \(step.detail)")
      }
    }

    text = ProjectRunControlClipboardText.boundedMultilineText(
      sections.joined(separator: "\n"),
      limit: Self.textLimit
    )
  }

  var isEmpty: Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private static func kindLabel(_ kind: ProjectRunControlGuide.Kind) -> String {
    switch kind {
    case .loop:
      return "loop"
    case .planOnly:
      return "plan-only"
    case .developOnly:
      return "develop-only"
    }
  }

  private static func enabledLabel(_ option: ProjectRunControlGuide.Option) -> String {
    option.isEnabled ? "enabled" : "disabled"
  }
}

enum ProjectRunControlClipboardText {
  static func boundedMultilineText(_ text: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard text.count > limit else { return text }
    guard limit > 3 else { return String(text.prefix(limit)) }

    return String(text.prefix(limit - 3))
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}
