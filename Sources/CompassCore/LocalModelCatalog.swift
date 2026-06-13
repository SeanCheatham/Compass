import AppKit
import Combine
import Foundation

#if canImport(HuggingFace)
  import HuggingFace
#endif

package enum LocalModelStatus: String, Equatable, Sendable {
  case missing
  case downloading
  case ready
  case loaded
  case unloading
  case error
}

package struct LocalModelSnapshot: Equatable, Sendable {
  package var runtimeName: String
  package var modelID: String
  package var status: LocalModelStatus
  package var progressFraction: Double?
  package var errorMessage: String?
  package var directory: URL

  package var isRunnable: Bool {
    switch status {
    case .ready, .loaded:
      return true
    case .missing, .downloading, .unloading, .error:
      return false
    }
  }

  package var statusLabel: String {
    switch status {
    case .missing:
      return "Missing"
    case .downloading:
      if let progressFraction {
        return "Downloading \(Int((progressFraction * 100).rounded()))%"
      }
      return "Downloading"
    case .ready:
      return "Ready"
    case .loaded:
      return "Loaded"
    case .unloading:
      return "Unloading"
    case .error:
      return "Error"
    }
  }
}

package enum LocalModelCatalog {
  package static let runtimeName = "MLX"
  package static let blessedModelID = "mlx-community/Qwen2.5-Coder-7B-Instruct-4bit"
  package static let defaultContextWindowTokens = 32_768
  package static let idleUnloadDelaySeconds: TimeInterval = 5 * 60

  #if DEBUG
    nonisolated(unsafe) private static var testingModelDirectoryOverride: URL?

    static func withTestingModelDirectory<T>(
      _ directory: URL,
      operation: () throws -> T
    ) rethrows -> T {
      let oldValue = testingModelDirectoryOverride
      testingModelDirectoryOverride = directory
      defer { testingModelDirectoryOverride = oldValue }
      return try operation()
    }
  #endif

  package static var applicationSupportDirectory: URL {
    let base =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
    return base.appending(path: "Compass", directoryHint: .isDirectory)
  }

  package static var modelsDirectory: URL {
    applicationSupportDirectory.appending(path: "Models", directoryHint: .isDirectory)
  }

  package static var blessedModelDirectory: URL {
    #if DEBUG
      if let testingModelDirectoryOverride {
        return testingModelDirectoryOverride
      }
    #endif
    return modelsDirectory
      .appending(path: "mlx-community", directoryHint: .isDirectory)
      .appending(path: "Qwen2.5-Coder-7B-Instruct-4bit", directoryHint: .isDirectory)
  }

  package static var hubCacheDirectory: URL {
    applicationSupportDirectory
      .appending(path: "HuggingFaceHub", directoryHint: .isDirectory)
  }

  package static func snapshot() -> LocalModelSnapshot {
    LocalModelSnapshot(
      runtimeName: runtimeName,
      modelID: blessedModelID,
      status: isBlessedModelReady() ? .ready : .missing,
      progressFraction: nil,
      errorMessage: nil,
      directory: blessedModelDirectory
    )
  }

  package static func isBlessedModelReady(fileManager: FileManager = .default) -> Bool {
    let directory = blessedModelDirectory
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      return false
    }

    let required = ["config.json", "tokenizer.json"]
    for file in required {
      guard fileManager.fileExists(atPath: directory.appending(path: file).path) else {
        return false
      }
    }

    guard
      let enumerator = fileManager.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return false
    }

    for case let url as URL in enumerator {
      if url.pathExtension == "safetensors" {
        return true
      }
    }
    return false
  }

  package static func ensureStorageRootExists() throws {
    try FileManager.default.createDirectory(
      at: modelsDirectory,
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: hubCacheDirectory,
      withIntermediateDirectories: true
    )
  }
}

@MainActor
package final class LocalModelManager: ObservableObject {
  package static let shared = LocalModelManager()

  @Published package private(set) var snapshot: LocalModelSnapshot
  @Published package private(set) var isDownloadActive = false

  private var downloadTask: Task<Void, Never>?

  package init(snapshot: LocalModelSnapshot = LocalModelCatalog.snapshot()) {
    self.snapshot = snapshot
  }

  package func refresh() {
    guard snapshot.status != .downloading else { return }
    snapshot = LocalModelCatalog.snapshot()
  }

  package func markLoaded() {
    snapshot = LocalModelSnapshot(
      runtimeName: LocalModelCatalog.runtimeName,
      modelID: LocalModelCatalog.blessedModelID,
      status: .loaded,
      progressFraction: nil,
      errorMessage: nil,
      directory: LocalModelCatalog.blessedModelDirectory
    )
  }

  package func markUnloading() {
    snapshot = LocalModelSnapshot(
      runtimeName: LocalModelCatalog.runtimeName,
      modelID: LocalModelCatalog.blessedModelID,
      status: .unloading,
      progressFraction: nil,
      errorMessage: nil,
      directory: LocalModelCatalog.blessedModelDirectory
    )
  }

  package func markUnloaded() {
    snapshot = LocalModelCatalog.snapshot()
  }

  package func downloadBlessedModel() {
    guard downloadTask == nil else { return }
    isDownloadActive = true
    snapshot = LocalModelSnapshot(
      runtimeName: LocalModelCatalog.runtimeName,
      modelID: LocalModelCatalog.blessedModelID,
      status: .downloading,
      progressFraction: 0,
      errorMessage: nil,
      directory: LocalModelCatalog.blessedModelDirectory
    )

    downloadTask = Task { [weak self] in
      do {
        try await Self.downloadModel()
        await MainActor.run {
          guard let self else { return }
          self.downloadTask = nil
          self.isDownloadActive = false
          self.snapshot = LocalModelCatalog.snapshot()
        }
      } catch is CancellationError {
        await MainActor.run {
          guard let self else { return }
          self.downloadTask = nil
          self.isDownloadActive = false
          self.snapshot = LocalModelCatalog.snapshot()
        }
      } catch {
        await MainActor.run {
          guard let self else { return }
          self.downloadTask = nil
          self.isDownloadActive = false
          self.snapshot = LocalModelSnapshot(
            runtimeName: LocalModelCatalog.runtimeName,
            modelID: LocalModelCatalog.blessedModelID,
            status: .error,
            progressFraction: nil,
            errorMessage: error.localizedDescription,
            directory: LocalModelCatalog.blessedModelDirectory
          )
        }
      }
    }
  }

  package func cancelDownload() {
    downloadTask?.cancel()
    downloadTask = nil
    isDownloadActive = false
    snapshot = LocalModelCatalog.snapshot()
  }

  package func deleteBlessedModel() {
    cancelDownload()
    snapshot = LocalModelSnapshot(
      runtimeName: LocalModelCatalog.runtimeName,
      modelID: LocalModelCatalog.blessedModelID,
      status: .unloading,
      progressFraction: nil,
      errorMessage: nil,
      directory: LocalModelCatalog.blessedModelDirectory
    )
    Task {
      await LocalModelLease.shared.unloadNow()
      try? FileManager.default.removeItem(at: LocalModelCatalog.blessedModelDirectory)
      await MainActor.run {
        self.snapshot = LocalModelCatalog.snapshot()
      }
    }
  }

  package func openModelFolder() {
    try? LocalModelCatalog.ensureStorageRootExists()
    NSWorkspace.shared.open(LocalModelCatalog.blessedModelDirectory)
  }

  private func updateDownloadProgress(_ progress: Progress) {
    let fraction = progress.totalUnitCount > 0
      ? min(1, max(0, progress.fractionCompleted))
      : nil
    snapshot = LocalModelSnapshot(
      runtimeName: LocalModelCatalog.runtimeName,
      modelID: LocalModelCatalog.blessedModelID,
      status: .downloading,
      progressFraction: fraction,
      errorMessage: nil,
      directory: LocalModelCatalog.blessedModelDirectory
    )
  }

  private static func downloadModel() async throws {
    try LocalModelCatalog.ensureStorageRootExists()

    #if canImport(HuggingFace)
      let cache = HubCache(cacheDirectory: LocalModelCatalog.hubCacheDirectory)
      let client = HubClient(cache: cache)
      let repoID = Repo.ID(namespace: "mlx-community", name: "Qwen2.5-Coder-7B-Instruct-4bit")
      _ = try await client.downloadSnapshot(
        of: repoID,
        kind: .model,
        to: LocalModelCatalog.blessedModelDirectory,
        revision: "main",
        progressHandler: { progress in
          Task { @MainActor in
            LocalModelManager.shared.updateDownloadProgress(progress)
          }
        }
      )
    #else
      throw LocalModelRuntimeError.unavailable(
        "Hugging Face download support is not linked in this build."
      )
    #endif

    if Task.isCancelled {
      throw CancellationError()
    }
    guard LocalModelCatalog.isBlessedModelReady() else {
      throw LocalModelRuntimeError.modelMissing(
        "Downloaded files are incomplete for \(LocalModelCatalog.blessedModelID)."
      )
    }
  }
}
