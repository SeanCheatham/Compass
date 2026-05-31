import Foundation

struct CompassWorkspaceStorageBoundary: Equatable {
  static let labelLimit = 34
  static let detailLimit = 180
  static let recommendationLimit = 140

  var repoURL: URL
  var applicationSupportRoots: KnownProjectStore.ApplicationSupportRoots
  var projectStorageIdentifier: String
  var currentApplicationSupportCandidateURL: URL
  var assessmentKind: CompassWorkspaceStorageAssessment.Kind
  var preflightKind: CompassWorkspaceStoragePreflight.Kind
  var migrationCouldBeTechnicallyEligible: Bool
  var status: Status

  var kind: Kind { status.kind }
  var severity: CompassWorkspaceStorageAssessment.Severity { status.severity }
  var label: String { status.label }
  var detail: String { status.detail }
  var recommendation: String { status.recommendation }
  var systemImage: String { status.systemImage }

  init(
    assessment: CompassWorkspaceStorageAssessment,
    preflight: CompassWorkspaceStoragePreflight
  ) {
    repoURL = assessment.repoURL
    applicationSupportRoots = assessment.applicationSupportRoots
    projectStorageIdentifier = assessment.projectStorageIdentifier
    currentApplicationSupportCandidateURL = assessment.currentApplicationSupportCandidateURL
    assessmentKind = assessment.kind
    preflightKind = preflight.kind
    migrationCouldBeTechnicallyEligible = preflight.migrationWouldBeSafe
    status = Self.status(assessment: assessment, preflight: preflight)
  }

  enum Kind: String, Equatable {
    case repoLocalRecommended
    case repoLocalRepairFirst
    case applicationSupportInspectOnlyConflict
  }

  struct Status: Equatable {
    var kind: Kind
    var severity: CompassWorkspaceStorageAssessment.Severity
    var label: String
    var detail: String
    var recommendation: String
    var systemImage: String
  }

  private static func status(
    assessment: CompassWorkspaceStorageAssessment,
    preflight: CompassWorkspaceStoragePreflight
  ) -> Status {
    if assessment.issues.contains(where: isRepoLocalRepairIssue) {
      return status(
        kind: .repoLocalRepairFirst,
        severity: assessment.severity,
        label: "Repair repo-local",
        detail: repairFirstDetail(for: assessment),
        recommendation:
          "Use repo-local repair first; leave Application Support as inspect-only future-candidate storage.",
        systemImage: assessment.systemImage
      )
    }

    if !preflight.occupiedApplicationSupportCandidates.isEmpty {
      let occupied = preflight.occupiedApplicationSupportCandidates
        .map { boundedPath($0.url.path, limit: 72) }
        .joined(separator: ", ")
      return status(
        kind: .applicationSupportInspectOnlyConflict,
        severity: .warning,
        label: "Inspect support data",
        detail:
          "Active state remains in repo-local .compass/; inspect-only conflict at \(occupied).",
        recommendation:
          "No migration or mirroring by default; inspect support directories before any future opt-in storage change.",
        systemImage: "externaldrive.badge.exclamationmark"
      )
    }

    return status(
      kind: .repoLocalRecommended,
      severity: .healthy,
      label: "Repo-local boundary",
      detail:
        "Active project state stays in repo-local .compass/; Application Support remains the project registry and future-candidate area.",
      recommendation:
        "No migration or mirroring needed by default; preflight only preserves future opt-in eligibility.",
      systemImage: "checkmark.seal.fill"
    )
  }

  private static func isRepoLocalRepairIssue(
    _ issue: CompassWorkspaceStorageAssessment.Issue
  ) -> Bool {
    switch issue.kind {
    case .missingWorkspace,
      .incompleteCoreFiles,
      .unignoredCompass:
      return true
    case .repoLocalHealthy,
      .currentApplicationSupportCandidateExists:
      return false
    }
  }

  private static func repairFirstDetail(
    for assessment: CompassWorkspaceStorageAssessment
  ) -> String {
    switch assessment.kind {
    case .missingWorkspace:
      return
        "Repo-local .compass/ is missing; repair the workspace before considering migration or mirroring."
    case .incompleteCoreFiles:
      return
        ".compass/ is incomplete; restore the repo-local skeleton before considering migration or mirroring."
    case .unignoredCompass:
      return
        ".compass/ is complete but not ignored; repair .gitignore coverage before storage changes."
    case .repoLocalHealthy,
      .currentApplicationSupportCandidateExists:
      return assessment.detail
    }
  }

  private static func status(
    kind: Kind,
    severity: CompassWorkspaceStorageAssessment.Severity,
    label: String,
    detail: String,
    recommendation: String,
    systemImage: String
  ) -> Status {
    Status(
      kind: kind,
      severity: severity,
      label: boundedText(label, limit: labelLimit),
      detail: boundedText(detail, limit: detailLimit),
      recommendation: boundedText(recommendation, limit: recommendationLimit),
      systemImage: systemImage
    )
  }

  private static func boundedPath(_ value: String, limit: Int) -> String {
    guard value.count > limit else { return value }
    guard limit > 1 else { return String(value.prefix(max(0, limit))) }
    return "..." + value.suffix(max(0, limit - 3))
  }

  private static func boundedText(_ value: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard value.count > limit else { return value }
    guard limit > 3 else { return String(value.prefix(limit)) }
    return value.prefix(limit - 3)
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}

struct CompassWorkspaceStorageDisplayStatus: Equatable {
  static let labelLimit = 38
  static let detailLimit = 220
  static let recommendationLimit = 160
  static let repairActionLabelLimit = 24
  static let repairActionHelpLimit = 150
  static let compatibilityDetailLimit = 180
  static let compatibilityRecommendationLimit = 160
  static let compatibilityHelpLimit = 180

  var repoURL: URL
  var activeStorage: KnownProjectActiveStorage
  var applicationSupportRoots: KnownProjectStore.ApplicationSupportRoots
  var activeStorageRootURL: URL
  var projectStorageIdentifier: String
  var currentApplicationSupportCandidateURL: URL
  var assessmentKind: CompassWorkspaceStorageAssessment.Kind
  var preflightKind: CompassWorkspaceStoragePreflight.Kind
  var repoLocalReadiness: CompassWorkspaceStoragePreflight.RepoLocalReadiness
  var migrationCouldBeTechnicallyEligible: Bool
  var activeRootFacts: ActiveRootFacts
  var applicationSupportCompatibility: ApplicationSupportCompatibility?
  var status: Status
  var supportRepairAction: RepairAction?

  var kind: Kind { status.kind }
  var severity: CompassWorkspaceStorageAssessment.Severity { status.severity }
  var label: String { status.label }
  var detail: String { status.detail }
  var recommendation: String { status.recommendation }
  var systemImage: String { status.systemImage }
  var activeRootHealth: ActiveRootHealth { activeRootFacts.health }

  var activeStorageDisplayName: String {
    switch activeStorage {
    case .repoLocal:
      return "repo-local .compass/"
    case .applicationSupport:
      return "Application Support"
    }
  }

  init(
    repoURL: URL,
    activeStorage: KnownProjectActiveStorage,
    applicationSupportRoots: KnownProjectStore.ApplicationSupportRoots =
      KnownProjectStore.productionApplicationSupportRoots(),
    fileManager: FileManager = .default
  ) {
    let standardizedRepoURL = repoURL.standardizedFileURL
    let assessment = CompassWorkspaceStorageAssessment(
      repoURL: standardizedRepoURL,
      applicationSupportRoots: applicationSupportRoots,
      fileManager: fileManager
    )
    let preflight = CompassWorkspaceStoragePreflight(assessment: assessment)
    let activeStorageRootURL = CompassProjectStorageResolver.storageRootURL(
      for: standardizedRepoURL,
      activeStorage: activeStorage,
      applicationSupportRoots: applicationSupportRoots
    )
    self.init(
      repoURL: standardizedRepoURL,
      activeStorage: activeStorage,
      applicationSupportRoots: applicationSupportRoots,
      activeStorageRootURL: activeStorageRootURL,
      assessment: assessment,
      preflight: preflight,
      fileManager: fileManager
    )
  }

  init(
    repoURL: URL,
    activeStorage: KnownProjectActiveStorage,
    applicationSupportRoots: KnownProjectStore.ApplicationSupportRoots,
    activeStorageRootURL: URL,
    assessment: CompassWorkspaceStorageAssessment,
    preflight: CompassWorkspaceStoragePreflight,
    fileManager: FileManager = .default
  ) {
    let facts: ActiveRootFacts
    switch activeStorage {
    case .repoLocal:
      facts = ActiveRootFacts(assessmentFacts: assessment.facts)
    case .applicationSupport:
      facts = Self.collectActiveRootFacts(
        repoURL: assessment.repoURL,
        activeStorageRootURL: activeStorageRootURL,
        fileManager: fileManager
      )
    }
    self.init(
      repoURL: repoURL,
      activeStorage: activeStorage,
      applicationSupportRoots: applicationSupportRoots,
      activeStorageRootURL: activeStorageRootURL,
      assessment: assessment,
      preflight: preflight,
      activeRootFacts: facts
    )
  }

  init(
    repoURL: URL,
    activeStorage: KnownProjectActiveStorage,
    applicationSupportRoots: KnownProjectStore.ApplicationSupportRoots,
    activeStorageRootURL: URL,
    assessment: CompassWorkspaceStorageAssessment,
    preflight: CompassWorkspaceStoragePreflight,
    activeRootFacts: ActiveRootFacts
  ) {
    let standardizedRepoURL = repoURL.standardizedFileURL
    let standardizedActiveRootURL = activeStorageRootURL.standardizedFileURL
    let boundary = CompassWorkspaceStorageBoundary(assessment: assessment, preflight: preflight)

    self.repoURL = standardizedRepoURL
    self.activeStorage = activeStorage
    self.applicationSupportRoots = applicationSupportRoots
    self.activeStorageRootURL = standardizedActiveRootURL
    projectStorageIdentifier = assessment.projectStorageIdentifier
    currentApplicationSupportCandidateURL = assessment.currentApplicationSupportCandidateURL
    assessmentKind = assessment.kind
    preflightKind = preflight.kind
    repoLocalReadiness = preflight.repoLocalReadiness
    migrationCouldBeTechnicallyEligible = preflight.migrationWouldBeSafe
    self.activeRootFacts = activeRootFacts
    let supportCompatibility =
      activeStorage == .applicationSupport
      ? Self.makeApplicationSupportCompatibility(
        activeStorageRootURL: standardizedActiveRootURL,
        preflight: preflight
      )
      : nil
    applicationSupportCompatibility = supportCompatibility
    let derivedStatus = Self.status(
      repoURL: standardizedRepoURL,
      activeStorage: activeStorage,
      activeStorageRootURL: standardizedActiveRootURL,
      activeRootFacts: activeRootFacts,
      preflight: preflight,
      boundary: boundary,
      applicationSupportCompatibility: supportCompatibility
    )
    status = derivedStatus
    supportRepairAction = Self.supportRepairAction(for: derivedStatus.kind)
  }

  enum Kind: String, Equatable {
    case repoLocalRecommended
    case repoLocalRepairFirst
    case applicationSupportInspectOnlyConflict
    case applicationSupportActive
    case applicationSupportActiveMissing
    case applicationSupportActiveIncomplete
  }

  enum ActiveRootHealth: String, Equatable {
    case healthy
    case missing
    case incomplete

    var displayName: String {
      switch self {
      case .healthy:
        return "healthy"
      case .missing:
        return "missing"
      case .incomplete:
        return "incomplete"
      }
    }
  }

  enum RepoLocalCompatibilityKind: String, Equatable {
    case retainedStale
    case missing
    case incomplete

    var displayName: String {
      switch self {
      case .retainedStale:
        return "retained stale"
      case .missing:
        return "missing"
      case .incomplete:
        return "incomplete"
      }
    }
  }

  struct ActiveRootFacts: Equatable {
    var directoryExists: Bool
    var presentCoreFiles: Set<CompassWorkspaceStorageAssessment.CoreFile>
    var sessionsDirectoryExists: Bool

    var missingCoreFiles: [CompassWorkspaceStorageAssessment.CoreFile] {
      CompassWorkspaceStorageAssessment.CoreFile.allCases.filter { !presentCoreFiles.contains($0) }
    }

    var missingItems: [String] {
      missingCoreFiles.map(\.relativePath) + (sessionsDirectoryExists ? [] : ["sessions/"])
    }

    var health: ActiveRootHealth {
      guard directoryExists else { return .missing }
      return missingItems.isEmpty ? .healthy : .incomplete
    }

    init(
      directoryExists: Bool,
      presentCoreFiles: Set<CompassWorkspaceStorageAssessment.CoreFile>,
      sessionsDirectoryExists: Bool
    ) {
      self.directoryExists = directoryExists
      self.presentCoreFiles = presentCoreFiles
      self.sessionsDirectoryExists = sessionsDirectoryExists
    }

    init(assessmentFacts: CompassWorkspaceStorageAssessment.Facts) {
      self.init(
        directoryExists: assessmentFacts.compassDirectoryExists,
        presentCoreFiles: assessmentFacts.presentCoreFiles,
        sessionsDirectoryExists: assessmentFacts.sessionsDirectoryExists
      )
    }
  }

  struct RepoLocalCompatibilityContext: Equatable {
    var kind: RepoLocalCompatibilityKind
    var missingItems: [String]
    var detail: String
    var recommendation: String
    var helpText: String
  }

  struct ApplicationSupportCompatibility: Equatable {
    var repoLocalContext: RepoLocalCompatibilityContext
    var inspectOnlyApplicationSupportDrift:
      [CompassWorkspaceStoragePreflight.ApplicationSupportCandidate]
    var detail: String
    var recommendation: String
    var helpText: String

    var hasInspectOnlyDrift: Bool {
      !inspectOnlyApplicationSupportDrift.isEmpty
    }
  }

  struct Status: Equatable {
    var kind: Kind
    var severity: CompassWorkspaceStorageAssessment.Severity
    var label: String
    var detail: String
    var recommendation: String
    var systemImage: String
  }

  enum RepairKind: String, Equatable {
    case initializeApplicationSupportWorkspace
  }

  struct RepairAction: Identifiable, Equatable {
    var kind: RepairKind
    var issueKind: Kind
    var label: String
    var helpText: String
    var systemImage: String

    var id: String { "\(kind.rawValue)-\(issueKind.rawValue)" }
  }

  private static func collectActiveRootFacts(
    repoURL: URL,
    activeStorageRootURL: URL,
    fileManager: FileManager
  ) -> ActiveRootFacts {
    let workspace = CompassWorkspace(repoURL: repoURL, storageRootURL: activeStorageRootURL)
    let rootDirectoryExists = directoryExists(activeStorageRootURL, fileManager: fileManager)
    let presentCoreFiles = Set(
      CompassWorkspaceStorageAssessment.CoreFile.allCases.filter { coreFile in
        fileExists(url(for: coreFile, in: workspace), fileManager: fileManager)
      })

    return ActiveRootFacts(
      directoryExists: rootDirectoryExists,
      presentCoreFiles: presentCoreFiles,
      sessionsDirectoryExists: directoryExists(workspace.sessionsURL, fileManager: fileManager)
    )
  }

  private static func status(
    repoURL: URL,
    activeStorage: KnownProjectActiveStorage,
    activeStorageRootURL: URL,
    activeRootFacts: ActiveRootFacts,
    preflight: CompassWorkspaceStoragePreflight,
    boundary: CompassWorkspaceStorageBoundary,
    applicationSupportCompatibility: ApplicationSupportCompatibility?
  ) -> Status {
    switch activeStorage {
    case .repoLocal:
      return status(
        kind: displayKind(for: boundary.kind),
        severity: boundary.severity,
        label: boundary.label,
        detail: boundary.detail,
        recommendation: boundary.recommendation,
        systemImage: boundary.systemImage
      )
    case .applicationSupport:
      return applicationSupportStatus(
        repoURL: repoURL,
        activeStorageRootURL: activeStorageRootURL,
        activeRootFacts: activeRootFacts,
        compatibility: applicationSupportCompatibility
          ?? makeApplicationSupportCompatibility(
            activeStorageRootURL: activeStorageRootURL,
            preflight: preflight
          )
      )
    }
  }

  private static func applicationSupportStatus(
    repoURL: URL,
    activeStorageRootURL: URL,
    activeRootFacts: ActiveRootFacts,
    compatibility: ApplicationSupportCompatibility
  ) -> Status {
    switch activeRootFacts.health {
    case .healthy:
      return status(
        kind: .applicationSupportActive,
        severity: compatibility.hasInspectOnlyDrift ? .info : .healthy,
        label: compatibility.hasInspectOnlyDrift ? "Support drift noted" : "Support storage active",
        detail: applicationSupportActiveDetail(
          activeStorageRootURL: activeStorageRootURL,
          repoURL: repoURL,
          compatibility: compatibility
        ),
        recommendation: compatibility.recommendation,
        systemImage: compatibility.hasInspectOnlyDrift
          ? "externaldrive.badge.exclamationmark"
          : "externaldrive.fill.badge.checkmark"
      )
    case .missing:
      return status(
        kind: .applicationSupportActiveMissing,
        severity: .warning,
        label: "Support storage missing",
        detail:
          "Active Application Support state root is missing at \(boundedPath(activeStorageRootURL.path, limit: 144)).",
        recommendation: "Restore or initialize the active support root before running Compass.",
        systemImage: "folder.badge.questionmark"
      )
    case .incomplete:
      return status(
        kind: .applicationSupportActiveIncomplete,
        severity: .failure,
        label: "Support storage incomplete",
        detail:
          "Active Application Support state root is missing \(activeRootFacts.missingItems.joined(separator: ", ")) at \(boundedPath(activeStorageRootURL.path, limit: 112)).",
        recommendation: "Restore the active support storage skeleton before running Compass.",
        systemImage: "exclamationmark.triangle.fill"
      )
    }
  }

  private static func makeApplicationSupportCompatibility(
    activeStorageRootURL: URL,
    preflight: CompassWorkspaceStoragePreflight
  ) -> ApplicationSupportCompatibility {
    let repoLocalContext = repoLocalCompatibilityContext(from: preflight)
    let inspectOnlyDrift = inspectOnlyApplicationSupportDrift(
      activeStorageRootURL: activeStorageRootURL,
      preflight: preflight
    )
    return ApplicationSupportCompatibility(
      repoLocalContext: repoLocalContext,
      inspectOnlyApplicationSupportDrift: inspectOnlyDrift,
      detail: applicationSupportCompatibilityDetail(
        repoLocalContext: repoLocalContext,
        inspectOnlyDrift: inspectOnlyDrift
      ),
      recommendation: applicationSupportCompatibilityRecommendation(
        repoLocalContext: repoLocalContext,
        inspectOnlyDrift: inspectOnlyDrift
      ),
      helpText: applicationSupportCompatibilityHelpText(
        activeStorageRootURL: activeStorageRootURL,
        repoLocalContext: repoLocalContext,
        inspectOnlyDrift: inspectOnlyDrift
      )
    )
  }

  private static func repoLocalCompatibilityContext(
    from preflight: CompassWorkspaceStoragePreflight
  ) -> RepoLocalCompatibilityContext {
    let missingItems =
      preflight.missingCoreFiles.map(\.relativePath)
      + (preflight.sessionsDirectoryExists ? [] : ["sessions/"])

    let kind: RepoLocalCompatibilityKind
    let detail: String
    let recommendation: String
    let helpText: String

    switch preflight.repoLocalReadiness {
    case .ready:
      kind = .retainedStale
      detail = "Repo-local .compass/ is retained stale compatibility context."
      recommendation =
        "Leave repo-local state unchanged unless explicitly reverting to repo-local storage."
      helpText =
        "Repo-local .compass/ is not active while Application Support is selected; treat it as stale compatibility context."
    case .missingWorkspace:
      kind = .missing
      detail = "Repo-local .compass/ is absent; Application Support has the active state."
      recommendation = "No repo-local storage action is needed by default."
      helpText =
        "Missing repo-local .compass/ does not block an Application Support-active project."
    case .incompleteWorkspace:
      kind = .incomplete
      detail =
        ".compass/ is incomplete stale compatibility context: \(missingItems.joined(separator: ", "))."
      recommendation =
        "Leave incomplete repo-local state unchanged unless explicitly reverting storage."
      helpText =
        "Incomplete repo-local .compass/ is compatibility context only while Application Support is active."
    }

    return RepoLocalCompatibilityContext(
      kind: kind,
      missingItems: missingItems,
      detail: boundedText(detail, limit: compatibilityDetailLimit),
      recommendation: boundedText(recommendation, limit: compatibilityRecommendationLimit),
      helpText: boundedText(helpText, limit: compatibilityHelpLimit)
    )
  }

  private static func inspectOnlyApplicationSupportDrift(
    activeStorageRootURL: URL,
    preflight: CompassWorkspaceStoragePreflight
  ) -> [CompassWorkspaceStoragePreflight.ApplicationSupportCandidate] {
    let activeRootPath = activeStorageRootURL.standardizedFileURL.path
    return [preflight.currentApplicationSupportCandidate].filter { candidate in
      candidate.isOccupied && candidate.url.standardizedFileURL.path != activeRootPath
    }
  }

  private static func applicationSupportActiveDetail(
    activeStorageRootURL: URL,
    repoURL: URL,
    compatibility: ApplicationSupportCompatibility
  ) -> String {
    let rootText =
      "Active Compass state root: \(boundedPath(activeStorageRootURL.path, limit: 76)); repoURL: \(boundedPath(repoURL.path, limit: 44))."
    return boundedText(
      "\(compatibility.detail) \(rootText)",
      limit: detailLimit
    )
  }

  private static func applicationSupportCompatibilityDetail(
    repoLocalContext: RepoLocalCompatibilityContext,
    inspectOnlyDrift: [CompassWorkspaceStoragePreflight.ApplicationSupportCandidate]
  ) -> String {
    let drift = inspectOnlyDriftText(inspectOnlyDrift, pathLimit: 64)
    let detail =
      drift.isEmpty
      ? repoLocalContext.detail
      : "\(repoLocalContext.detail) Inspect-only support drift: \(drift)."
    return boundedText(detail, limit: compatibilityDetailLimit)
  }

  private static func applicationSupportCompatibilityRecommendation(
    repoLocalContext: RepoLocalCompatibilityContext,
    inspectOnlyDrift: [CompassWorkspaceStoragePreflight.ApplicationSupportCandidate]
  ) -> String {
    let recommendation =
      inspectOnlyDrift.isEmpty
      ? repoLocalContext.recommendation
      : "\(repoLocalContext.recommendation) Inspect occupied support data separately; keep Application Support active."
    return boundedText(recommendation, limit: compatibilityRecommendationLimit)
  }

  private static func applicationSupportCompatibilityHelpText(
    activeStorageRootURL: URL,
    repoLocalContext: RepoLocalCompatibilityContext,
    inspectOnlyDrift: [CompassWorkspaceStoragePreflight.ApplicationSupportCandidate]
  ) -> String {
    let drift = inspectOnlyDriftText(inspectOnlyDrift, pathLimit: 72)
    let supportText =
      drift.isEmpty
      ? "Active root: \(boundedPath(activeStorageRootURL.path, limit: 84))."
      : "Inspect-only drift: \(drift); active root remains \(boundedPath(activeStorageRootURL.path, limit: 64))."
    return boundedText(
      "\(repoLocalContext.helpText) \(supportText)",
      limit: compatibilityHelpLimit
    )
  }

  private static func inspectOnlyDriftText(
    _ candidates: [CompassWorkspaceStoragePreflight.ApplicationSupportCandidate],
    pathLimit: Int
  ) -> String {
    candidates
      .map { boundedPath($0.url.path, limit: pathLimit) }
      .joined(separator: "; ")
  }

  private static func displayKind(for boundaryKind: CompassWorkspaceStorageBoundary.Kind) -> Kind {
    switch boundaryKind {
    case .repoLocalRecommended:
      return .repoLocalRecommended
    case .repoLocalRepairFirst:
      return .repoLocalRepairFirst
    case .applicationSupportInspectOnlyConflict:
      return .applicationSupportInspectOnlyConflict
    }
  }

  private static func status(
    kind: Kind,
    severity: CompassWorkspaceStorageAssessment.Severity,
    label: String,
    detail: String,
    recommendation: String,
    systemImage: String
  ) -> Status {
    Status(
      kind: kind,
      severity: severity,
      label: boundedText(label, limit: labelLimit),
      detail: boundedText(detail, limit: detailLimit),
      recommendation: boundedText(recommendation, limit: recommendationLimit),
      systemImage: systemImage
    )
  }

  private static func supportRepairAction(for kind: Kind) -> RepairAction? {
    switch kind {
    case .applicationSupportActiveMissing:
      return supportRepairAction(
        issueKind: kind,
        helpText:
          "Create the active Application Support Compass root and core files without touching repo-local .compass/ or .gitignore."
      )
    case .applicationSupportActiveIncomplete:
      return supportRepairAction(
        issueKind: kind,
        helpText:
          "Restore missing active Application Support Compass files and sessions without touching repo-local .compass/ or .gitignore."
      )
    case .repoLocalRecommended,
      .repoLocalRepairFirst,
      .applicationSupportInspectOnlyConflict,
      .applicationSupportActive:
      return nil
    }
  }

  private static func supportRepairAction(issueKind: Kind, helpText: String) -> RepairAction {
    RepairAction(
      kind: .initializeApplicationSupportWorkspace,
      issueKind: issueKind,
      label: boundedText("Repair support storage", limit: repairActionLabelLimit),
      helpText: boundedText(helpText, limit: repairActionHelpLimit),
      systemImage: "externaldrive.badge.plus"
    )
  }

  private static func url(
    for coreFile: CompassWorkspaceStorageAssessment.CoreFile,
    in workspace: CompassWorkspace
  ) -> URL {
    switch coreFile {
    case .state:
      return workspace.stateURL
    case .drafts:
      return workspace.draftsURL
    case .lessons:
      return workspace.lessonsURL
    case .vision:
      return workspace.visionURL
    case .sessionsRecord:
      return workspace.sessionsRecordURL
    }
  }

  private static func directoryExists(_ url: URL, fileManager: FileManager) -> Bool {
    var isDirectory = ObjCBool(false)
    return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
      && isDirectory.boolValue
  }

  private static func fileExists(_ url: URL, fileManager: FileManager) -> Bool {
    var isDirectory = ObjCBool(false)
    return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
      && !isDirectory.boolValue
  }

  private static func boundedPath(_ value: String, limit: Int) -> String {
    guard value.count > limit else { return value }
    guard limit > 1 else { return String(value.prefix(max(0, limit))) }
    return "..." + value.suffix(max(0, limit - 3))
  }

  private static func boundedText(_ value: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard value.count > limit else { return value }
    guard limit > 3 else { return String(value.prefix(limit)) }
    return value.prefix(limit - 3)
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}

struct CompassWorkspaceStorageHeaderActions: Equatable {
  var showsCandidatePreparation: Bool
  var showsActivation: Bool
  var showsRepoLocalRepair: Bool
  var showsApplicationSupportRepair: Bool

  init(
    activeStorage: KnownProjectActiveStorage,
    candidatePreparationIsAvailable: Bool,
    candidatePreparationShouldShowFeedback: Bool,
    activationIsAvailable: Bool,
    activationShouldShowFeedback: Bool,
    activationIsIdle: Bool,
    repoLocalRepairActionIsAvailable: Bool,
    applicationSupportRepairActionIsAvailable: Bool = false
  ) {
    showsCandidatePreparation =
      candidatePreparationShouldShowFeedback
      || (activeStorage == .repoLocal && candidatePreparationIsAvailable)
    showsActivation =
      activationShouldShowFeedback
      || (activeStorage == .repoLocal && activationIsAvailable && activationIsIdle)
    showsRepoLocalRepair = activeStorage == .repoLocal && repoLocalRepairActionIsAvailable
    showsApplicationSupportRepair =
      activeStorage == .applicationSupport
      && applicationSupportRepairActionIsAvailable
  }
}
