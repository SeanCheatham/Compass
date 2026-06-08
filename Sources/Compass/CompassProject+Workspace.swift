import AppKit
import Foundation

@MainActor
extension CompassProject {
  func initializeWorkspace() async {
    do {
      guard let workspace else {
        fail(AppModelError.noRepositorySelected)
        return
      }
      try workspace.initialize()
      log("Initialized \(workspace.compassURL.path)", level: .success)
      await refresh()
    } catch {
      fail(error)
    }
  }

  func refresh() async {
    do {
      try await refreshFromWorkspace(requireStorageRoot: false)
    } catch {
      fail(error)
    }
  }

  func refreshFromWorkspace(requireStorageRoot: Bool, includeDrafts: Bool = true) async throws {
    guard let workspace else {
      state = .empty
      drafts = ""
      lessons = ""
      assumptions = []
      vision = ""
      productTournamentConfig = .empty
      productTournamentEvidenceIndex = .empty
      sessions = []
      archivedSessions = []
      hasOlderArchivedSessions = false
      activitySourceSnapshot = RepositoryActivitySourceSnapshot.noRepository(
        activeStorage: activeStorage
      )
      languageProfile = .empty
      forgeProfile = nil
      if requireStorageRoot {
        throw AppModelError.noRepositorySelected
      }
      return
    }

    languageProfile = RepositoryLanguageProfileService.scan(repoURL: workspace.repoURL)
    forgeProfile = try? ForgeProfileService.detectAndPersist(
      repoURL: workspace.repoURL,
      workspace: workspace
    )
    activitySourceSnapshot = RepositoryActivitySourceSnapshot.snapshot(
      activeStorage: activeStorage,
      workspace: workspace
    )

    if !FileManager.default.fileExists(atPath: workspace.compassURL.path) {
      state = .empty
      drafts = ""
      lessons = ""
      assumptions = []
      vision = ""
      productTournamentConfig = .empty
      productTournamentEvidenceIndex = .empty
      sessions = []
      archivedSessions = []
      hasOlderArchivedSessions = false
      if requireStorageRoot {
        throw AppModelError.internalInvariant(
          "Active Compass storage root is missing at \(workspace.compassURL.path)."
        )
      }
      return
    }

    state = try workspace.readState()
    if includeDrafts {
      drafts = workspace.readDrafts()
    }
    lessons = workspace.readLessons()
    assumptions = try workspace.readAssumptionLedger().assumptions
    vision = workspace.readVision()
    let rawProductPain = [vision, includeDrafts ? drafts : workspace.readDrafts()]
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: "\n\n")
    productTournamentConfig = try workspace.readOrSeedProductTournamentConfig(
      projectTitle: workspace.repoURL.lastPathComponent,
      rawPain: rawProductPain.isEmpty ? vision : rawProductPain
    )
    productTournamentEvidenceIndex = workspace.readProductTournamentEvidenceIndex()
    sessions = workspace.readSessions()
    archivedSessions = []
    hasOlderArchivedSessions = workspace.hasArchivedSessions()
  }

  func saveProductTournamentConfig(_ config: ProductTournamentConfig? = nil) async {
    do {
      guard let workspace else {
        fail(AppModelError.noRepositorySelected)
        return
      }
      let value = config ?? productTournamentConfig
      try workspace.writeProductTournamentConfig(value)
      productTournamentConfig = value
    } catch {
      fail(error)
    }
  }

  func reloadProductTournamentEvidenceIndex() async {
    guard let workspace else {
      productTournamentEvidenceIndex = .empty
      return
    }
    productTournamentEvidenceIndex = workspace.readProductTournamentEvidenceIndex()
  }

  func readProductTournamentEvidenceRecord(id: String) throws -> ProductTournamentEvidenceRecord {
    guard let workspace else {
      throw AppModelError.noRepositorySelected
    }
    return try workspace.readProductTournamentEvidenceRecord(id: id)
  }

  func readProductTournamentPlanEvaluationRecord(
    id: String
  ) throws -> ProductTournamentPlanEvaluationRecord {
    guard let workspace else {
      throw AppModelError.noRepositorySelected
    }
    return try workspace.readProductTournamentPlanEvaluationRecord(id: id)
  }

  func readMarketPressureRecord(id: String) throws -> MarketPressureEvaluationRecord {
    guard let workspace else {
      throw AppModelError.noRepositorySelected
    }
    return try workspace.readMarketPressureRecord(id: id)
  }

  func initializeIfNeeded(_ workspace: CompassWorkspace) async throws {
    guard !FileManager.default.fileExists(atPath: workspace.compassURL.path) else { return }
    try workspace.initialize()
    // Load plan state and sessions, but leave `drafts`/`draftEntry` alone
    // until the caller finishes writing — refreshing drafts mid-queue was
    // racing the Pending Drafts TextEditor and blanking the split view.
    try await refreshFromWorkspace(requireStorageRoot: false, includeDrafts: false)
  }

  func resolveWorkspaceForRun() async throws -> CompassWorkspace {
    let resolvedURL = try await resolveGitRoot(from: repoURL)
    if repoURL.path != resolvedURL.path {
      repoURL = resolvedURL
      log("Resolved repo root: \(repoURL.path)", level: .info)
    }

    let workspace = makeWorkspace(repoURL: repoURL)
    log("Using Compass workspace: \(workspace.compassURL.path)", level: .info)
    return workspace
  }

  func makeWorkspace(repoURL: URL) -> CompassWorkspace {
    makeStorageResolver(repoURL: repoURL).workspace
  }

  func makeStorageResolver(repoURL: URL) -> CompassProjectStorageResolver {
    CompassProjectStorageResolver(
      repoURL: repoURL,
      activeStorage: activeStorage,
      applicationSupportRoots: storageApplicationSupportRoots
    )
  }

  func resolveGitRoot(from url: URL) async throws -> URL {
    let result: ProcessResult
    do {
      result = try await ProcessRunner.runEnv(
        "git",
        ["rev-parse", "--show-toplevel"],
        workingDirectory: url
      )
    } catch {
      throw AppModelError.notGitRepository(url.path)
    }

    guard result.exitCode == 0 else {
      throw AppModelError.notGitRepository(url.path)
    }

    let root = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !root.isEmpty else {
      throw AppModelError.notGitRepository(url.path)
    }
    return URL(fileURLWithPath: root).standardizedFileURL
  }

  /// Refresh the on-disk codemap (symbols + per-file summaries) once per
  /// session. The agent's read-only `outline` / `find_symbol` / `summary`
  /// tools all read from this cache, so this is what makes a brand-new
  /// session see up-to-date data without paying the cost on every tool
  /// call. Failures are non-fatal — a stale or partial codemap is better
  /// than refusing to launch the agent.
  func refreshCodemapIfNeeded(
    workspace: CompassWorkspace,
    sessionNumber: Int,
    agentSettings: AgentRuntimeSettings
  ) async {
    if codemapRefreshedForSession == sessionNumber { return }
    let refresher = CodemapRefresher.make(
      workspace: workspace,
      settings: agentSettings,
      rustCargoService: forgeProfile == .rustCargo
        ? RustEngineLocator.locateEngineBinary().map { RustCargoService(engineURL: $0) }
        : nil
    )
    do {
      let result = try await refresher.refresh()
      codemapRefreshedForSession = sessionNumber
      let parts = [
        "indexed \(result.indexed)",
        "unchanged \(result.unchanged)",
        "pruned \(result.pruned)",
        "summarized \(result.summariesGenerated)",
      ]
      log(
        "Codemap refresh: \(parts.joined(separator: ", ")).",
        level: .info
      )
      if result.indexerFailed > 0 || result.summariesFailed > 0 {
        log(
          "Codemap refresh had \(result.indexerFailed) parse failure(s) and \(result.summariesFailed) summary failure(s).",
          level: .warning
        )
      }
    } catch {
      log(
        "Codemap refresh failed: \(error.localizedDescription)",
        level: .warning
      )
    }
  }
}
