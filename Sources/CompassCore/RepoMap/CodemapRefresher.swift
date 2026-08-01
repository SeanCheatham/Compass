import Foundation

public struct CodemapRefresher: Sendable {
  public struct Result: Sendable, Equatable {
    public var indexed: Int
    public var unchanged: Int
    public var pruned: Int
    public var indexerSkipped: Int
    public var indexerFailed: Int
    public var summariesGenerated: Int
    public var summariesSkipped: Int
    public var summariesFailed: Int
  }

  public let indexer: CodemapIndexer
  public let summarizer: RepoSummarizer
  public let summariesEnabled: Bool

  public static func make(
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

  public func refresh() async throws -> Result {
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
