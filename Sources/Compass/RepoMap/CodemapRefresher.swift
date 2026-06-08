import Foundation

/// One-shot helper that AppModel calls when a Plan or Develop session
/// starts. Brings the on-disk codemap up to date (symbols re-extracted for
/// changed files, stale entries pruned) and then refreshes per-file
/// summaries for whatever still needs one. Runs once per session start —
/// never per tool call — so the cost is paid up front.
struct CodemapRefresher: Sendable {
  struct Result: Sendable, Equatable {
    var indexed: Int
    var unchanged: Int
    var pruned: Int
    var indexerSkipped: Int
    var indexerFailed: Int
    var summariesGenerated: Int
    var summariesSkipped: Int
    var summariesFailed: Int
  }

  let workingDirectory: URL
  let store: CodemapStore
  let indexer: CodemapIndexer
  let summarizer: RepoSummarizer
  let rustCargoService: (any RustCargoServicing)?
  let workspace: CompassWorkspace?
  /// When false, the summarizer is skipped entirely (no LLM calls).
  /// Set this off in unit tests, or in setups where the user has not
  /// configured an API key and a noisy "0 generated / N failed" status
  /// line would just be cruft.
  let summariesEnabled: Bool

  /// Construct a refresher for the supplied workspace. Wires the
  /// indexer + summarizer to the codemap subdir under the workspace's
  /// `.compass` root so non-repo-local storage layouts (a custom
  /// `storageRootURL`) still find the cache.
  static func make(
    workspace: CompassWorkspace,
    settings: AgentRuntimeSettings,
    filesystem: AgentFilesystem = AgentHostFilesystem(),
    bashRunner: AgentBashRunner = AgentHostBashRunner(),
    rustCargoService: (any RustCargoServicing)? = nil
  ) -> CodemapRefresher {
    let store = CodemapStore(
      directory: CodemapStore.defaultDirectory(forWorkspace: workspace)
    )
    let indexer = CodemapIndexer(
      workingDirectory: workspace.repoURL,
      store: store,
      filesystem: filesystem,
      bashRunner: bashRunner
    )
    let summarizer = RepoSummarizer(
      workingDirectory: workspace.repoURL,
      store: store,
      settings: settings,
      filesystem: filesystem
    )
    let hasKey =
      !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    return CodemapRefresher(
      workingDirectory: workspace.repoURL,
      store: store,
      indexer: indexer,
      summarizer: summarizer,
      rustCargoService: rustCargoService,
      workspace: workspace,
      summariesEnabled: hasKey
    )
  }

  init(
    workingDirectory: URL,
    store: CodemapStore,
    indexer: CodemapIndexer,
    summarizer: RepoSummarizer,
    rustCargoService: (any RustCargoServicing)? = nil,
    workspace: CompassWorkspace? = nil,
    summariesEnabled: Bool
  ) {
    self.workingDirectory = workingDirectory
    self.store = store
    self.indexer = indexer
    self.summarizer = summarizer
    self.rustCargoService = rustCargoService
    self.workspace = workspace
    self.summariesEnabled = summariesEnabled
  }

  /// Index, then summarize. Returns combined counts; the caller decides
  /// whether to surface them in the log. Throws only on hard indexer
  /// failures (filesystem I/O, store-write errors); a per-file parse
  /// error doesn't bubble up here — it counts toward `indexerFailed`.
  func refresh() async throws -> Result {
    let indexResult = try await indexer.indexAll()
    try await refreshCargoGraphIfNeeded()
    let summary =
      summariesEnabled
      ? await summarizer.summarizeMissing()
      : RepoSummarizer.Result(generated: 0, skipped: 0, failed: 0, unchanged: 0)
    let indexerSkipped: Int = indexResult.skipped
    return Result(
      indexed: indexResult.indexed,
      unchanged: indexResult.unchanged,
      pruned: indexResult.pruned,
      indexerSkipped: indexerSkipped,
      indexerFailed: indexResult.failed,
      summariesGenerated: summary.generated,
      summariesSkipped: summary.skipped,
      summariesFailed: summary.failed
    )
  }

  private func refreshCargoGraphIfNeeded() async throws {
    guard let rustCargoService, let workspace else { return }
    do {
      let data = try await rustCargoService.run(
        command: .workspaceOutline,
        repoURL: workingDirectory,
        arguments: [],
        timeout: 30
      )
      let response = try JSONDecoder().decode(RustEngineResponse<CargoGraphData>.self, from: data)
      guard response.ok, let graph = response.data else { return }
      let store = CargoGraphStore()
      let snapshot = store.makeSnapshot(graph: graph, workspace: workspace)
      if store.load(from: workspace)?.contentFingerprint == snapshot.contentFingerprint {
        return
      }
      try store.save(snapshot, workspace: workspace)
    } catch {
      return
    }
    do {
      let data = try await rustCargoService.run(
        command: .indexRust,
        repoURL: workingDirectory,
        arguments: [],
        timeout: 30
      )
      let response = try JSONDecoder().decode(RustEngineResponse<RustIndexData>.self, from: data)
      guard response.ok, let index = response.data else { return }
      try RustCodemapEnricher.save(index, workspace: workspace)
    } catch {
      return
    }
    let schemasURL = workingDirectory.appending(path: "schemas", directoryHint: .isDirectory)
    guard FileManager.default.fileExists(atPath: schemasURL.path) else { return }
    do {
      let data = try await rustCargoService.run(
        command: .schemaContracts,
        repoURL: workingDirectory,
        arguments: [],
        timeout: 30
      )
      let response = try JSONDecoder().decode(
        RustEngineResponse<SchemaContractsData>.self, from: data)
      guard response.ok, let contracts = response.data else { return }
      try SchemaContractsStore().save(contracts, workspace: workspace)
    } catch {
      return
    }
  }
}
