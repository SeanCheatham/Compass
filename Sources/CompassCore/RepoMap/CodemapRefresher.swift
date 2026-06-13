import Foundation

package struct CodemapRefresher: Sendable {
  package struct Result: Sendable, Equatable {
    package var indexed: Int
    package var unchanged: Int
    package var pruned: Int
    package var indexerSkipped: Int
    package var indexerFailed: Int
    package var summariesGenerated: Int
    package var summariesSkipped: Int
    package var summariesFailed: Int
  }

  package let indexer: CodemapIndexer
  package let summarizer: RepoSummarizer
  package let summariesEnabled: Bool

  package static func make(
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

  package func refresh() async throws -> Result {
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
