import Foundation

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

  let indexer: CodemapIndexer
  let summarizer: RepoSummarizer
  let summariesEnabled: Bool

  static func make(
    workspace: CompassWorkspace,
    settings: AgentRuntimeSettings,
    filesystem: AgentFilesystem = AgentHostFilesystem(),
    bashRunner: AgentBashRunner = AgentHostBashRunner()
  ) -> CodemapRefresher {
    let store = CodemapStore(
      directory: CodemapStore.defaultDirectory(forWorkspace: workspace)
    )
    return CodemapRefresher(
      indexer: CodemapIndexer(
        workingDirectory: workspace.repoURL,
        store: store,
        filesystem: filesystem,
        bashRunner: bashRunner
      ),
      summarizer: RepoSummarizer(
        workingDirectory: workspace.repoURL,
        store: store,
        settings: settings,
        filesystem: filesystem
      ),
      summariesEnabled: true
    )
  }

  func refresh() async throws -> Result {
    let indexResult = try await indexer.indexAll()
    let summary =
      summariesEnabled
      ? await summarizer.summarizeMissing()
      : RepoSummarizer.Result(generated: 0, skipped: 0, failed: 0, unchanged: 0)
    return Result(
      indexed: indexResult.indexed,
      unchanged: indexResult.unchanged,
      pruned: indexResult.pruned,
      indexerSkipped: indexResult.skipped,
      indexerFailed: indexResult.failed,
      summariesGenerated: summary.generated,
      summariesSkipped: summary.skipped,
      summariesFailed: summary.failed
    )
  }
}
