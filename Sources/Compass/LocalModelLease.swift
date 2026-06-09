import Foundation

struct LocalModelLeaseSnapshot: Equatable, Sendable {
  var loadedModelID: String?
  var activeRunCount: Int
  var isUnloading: Bool
}

enum LocalModelRuntimeError: LocalizedError, Equatable {
  case modelMissing(String)
  case unavailable(String)
  case incompatibleModel(active: String, requested: String)
  case generationFailed(String)

  var errorDescription: String? {
    switch self {
    case .modelMissing(let detail):
      return detail
    case .unavailable(let detail):
      return detail
    case .incompatibleModel(let active, let requested):
      return "Local model \(active) is already loaded; cannot load \(requested) concurrently."
    case .generationFailed(let detail):
      return detail
    }
  }
}

actor LocalModelLease {
  static let shared = LocalModelLease()
  static let defaultIdleTimeoutNanoseconds: UInt64 =
    UInt64(LocalModelCatalog.idleUnloadDelaySeconds * 1_000_000_000)

  private var loadedModelID: String?
  private var activeRunCount = 0
  private var idleTask: Task<Void, Never>?
  private var idleTimeoutNanoseconds = defaultIdleTimeoutNanoseconds
  private var unloading = false

  func beginRun(modelID: String) throws {
    if let loadedModelID, loadedModelID != modelID {
      throw LocalModelRuntimeError.incompatibleModel(active: loadedModelID, requested: modelID)
    }
    idleTask?.cancel()
    idleTask = nil
    unloading = false
    loadedModelID = modelID
    activeRunCount += 1
  }

  func endRun(modelID: String) {
    guard loadedModelID == modelID else { return }
    activeRunCount = max(0, activeRunCount - 1)
    guard activeRunCount == 0 else { return }
    scheduleIdleUnload(modelID: modelID)
  }

  func unloadNow() {
    idleTask?.cancel()
    idleTask = nil
    loadedModelID = nil
    activeRunCount = 0
    unloading = false
    Task { @MainActor in
      LocalModelManager.shared.markUnloaded()
    }
  }

  func snapshot() -> LocalModelLeaseSnapshot {
    LocalModelLeaseSnapshot(
      loadedModelID: loadedModelID,
      activeRunCount: activeRunCount,
      isUnloading: unloading
    )
  }

  func idleTimeoutForRuntime() -> UInt64 {
    idleTimeoutNanoseconds
  }

  func setIdleTimeoutForTesting(seconds: TimeInterval) {
    idleTimeoutNanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
  }

  func resetForTesting() {
    idleTask?.cancel()
    idleTask = nil
    loadedModelID = nil
    activeRunCount = 0
    unloading = false
    idleTimeoutNanoseconds = Self.defaultIdleTimeoutNanoseconds
  }

  private func scheduleIdleUnload(modelID: String) {
    idleTask?.cancel()
    let timeout = idleTimeoutNanoseconds
    idleTask = Task { [weak self] in
      if timeout > 0 {
        try? await Task.sleep(nanoseconds: timeout)
      }
      await self?.finishIdleUnload(modelID: modelID)
    }
  }

  private func finishIdleUnload(modelID: String) {
    guard loadedModelID == modelID, activeRunCount == 0 else { return }
    unloading = true
    Task { @MainActor in
      LocalModelManager.shared.markUnloading()
    }
    loadedModelID = nil
    unloading = false
    idleTask = nil
    Task { @MainActor in
      LocalModelManager.shared.markUnloaded()
    }
  }
}
