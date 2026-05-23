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
    bashRunner: AgentBashRunner = AgentHostBashRunner()
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
      summariesEnabled: hasKey
    )
  }

  /// Index, then summarize. Returns combined counts; the caller decides
  /// whether to surface them in the log. Throws only on hard indexer
  /// failures (filesystem I/O, store-write errors); a per-file parse
  /// error doesn't bubble up here — it counts toward `indexerFailed`.
  func refresh() async throws -> Result {
    let indexResult = try await indexer.indexAll()
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
}
