import AppKit
import CompassCore
import Foundation

@MainActor
extension CompassProject {
  func activeStorageActivationPlan() -> CompassWorkspaceStorageActivationPlan {
    CompassWorkspaceStorageActivationPlan(
      repoURL: repoURL,
      activeStorage: activeStorage,
      applicationSupportRoots: storageApplicationSupportRoots
    )
  }

  func prepareActiveStorageActivationConfirmation() {
    guard isIdleForActiveStorageActivation else {
      activeStorageActivationConfirmation = nil
      activeStorageActivationState = .blockedWhileBusy()
      errorMessage = activeStorageActivationState.detail
      log(activeStorageActivationState.detail, level: .warning)
      return
    }

    let plan = activeStorageActivationPlan()
    guard plan.isAvailable else {
      activeStorageActivationConfirmation = nil
      activeStorageActivationState = .blocked(plan: plan)
      errorMessage = activeStorageActivationState.detail
      log(
        "Active storage activation blocked: \(activeStorageActivationState.detail)", level: .warning
      )
      return
    }

    let confirmation = CompassWorkspaceStorageActivationConfirmation(plan: plan)
    activeStorageActivationConfirmation = confirmation
    activeStorageActivationState = .awaitingConfirmation(confirmation)
    errorMessage = nil
  }

  func cancelActiveStorageActivationConfirmation() {
    activeStorageActivationConfirmation = nil
    if activeStorageActivationState.phase == .awaitingConfirmation {
      activeStorageActivationState = .idle
    }
  }

  func confirmActiveStorageActivation(
    _ confirmation: CompassWorkspaceStorageActivationConfirmation,
    persistProjectRegistry: () throws -> Void
  ) async {
    activeStorageActivationConfirmation = nil

    guard isIdleForActiveStorageActivation else {
      activeStorageActivationState = .blockedWhileBusy()
      errorMessage = activeStorageActivationState.detail
      log(activeStorageActivationState.detail, level: .warning)
      return
    }

    let plan = activeStorageActivationPlan()
    guard plan.isAvailable else {
      let error = CompassProjectActiveStorageActivationError.unavailable(plan.kind, plan.detail)
      activeStorageActivationState = .failed(error)
      errorMessage = activeStorageActivationState.detail
      log(activeStorageActivationState.detail, level: .error)
      return
    }

    activeStorageActivationState = .running(plan: plan)
    errorMessage = nil
    log(
      "Active storage activation: switching Compass state to \(plan.candidateURL.path).",
      level: .info)
    await Task.yield()

    let previousStorage = activeStorage
    do {
      activeStorage = .applicationSupport
      try persistProjectRegistry()
      try await refreshFromWorkspace(requireStorageRoot: true)

      activeStorageActivationState = .succeeded(plan: plan)
      errorMessage = nil
      log(activeStorageActivationState.detail, level: .success)
    } catch {
      let rollbackFailure = await rollbackActiveStorage(
        to: previousStorage,
        persistProjectRegistry: persistProjectRegistry
      )
      let rollbackError = CompassProjectActiveStorageActivationError.rolledBack(
        primary: error.localizedDescription,
        rollbackFailure: rollbackFailure
      )
      activeStorageActivationState = .failed(rollbackError)
      errorMessage = activeStorageActivationState.detail
      log(activeStorageActivationState.detail, level: .error)
    }
  }

  func storageMigrationPlan() -> CompassWorkspaceStorageMigrationPlan {
    CompassWorkspaceStorageMigrationPlan(
      repoURL: repoURL,
      applicationSupportRoots: storageApplicationSupportRoots
    )
  }

  func prepareStorageMigrationConfirmation() {
    guard !isRunning, !isAutoPlaying else {
      storageMigrationConfirmation = nil
      storageMigrationState = .blockedWhileRunning()
      errorMessage = storageMigrationState.detail
      log(storageMigrationState.detail, level: .warning)
      return
    }

    let plan = storageMigrationPlan()
    guard plan.isAvailable else {
      storageMigrationConfirmation = nil
      storageMigrationState = .blocked(plan: plan)
      errorMessage = storageMigrationState.detail
      log("Storage migration blocked: \(storageMigrationState.detail)", level: .warning)
      return
    }

    let confirmation = CompassWorkspaceStorageMigrationConfirmation(plan: plan)
    storageMigrationConfirmation = confirmation
    storageMigrationState = .awaitingConfirmation(confirmation)
    errorMessage = nil
  }

  func cancelStorageMigrationConfirmation() {
    storageMigrationConfirmation = nil
    if storageMigrationState.phase == .awaitingConfirmation {
      storageMigrationState = .idle
    }
  }

  func confirmStorageMigration(_ confirmation: CompassWorkspaceStorageMigrationConfirmation) async {
    storageMigrationConfirmation = nil

    guard !isRunning, !isAutoPlaying else {
      storageMigrationState = .blockedWhileRunning()
      errorMessage = storageMigrationState.detail
      log(storageMigrationState.detail, level: .warning)
      return
    }

    let plan = confirmation.plan
    guard plan.isAvailable else {
      storageMigrationState = .blocked(plan: plan)
      errorMessage = storageMigrationState.detail
      log("Storage migration blocked: \(storageMigrationState.detail)", level: .warning)
      return
    }

    storageMigrationState = .running(plan: plan)
    errorMessage = nil
    log(
      "Storage migration: preparing Application Support candidate at \(plan.destinationURL.path).",
      level: .info)
    await Task.yield()

    do {
      let result = try storageMigrationAction(plan)
      guard result.activeStorageDidChange == false else {
        throw CompassProjectStorageMigrationActionError.activeStorageChanged
      }
      guard FileManager.default.fileExists(atPath: plan.sourceCompassURL.path) else {
        throw CompassProjectStorageMigrationActionError.repoLocalSourceMissing(
          plan.sourceCompassURL.path)
      }

      storageMigrationState = .succeeded(result)
      log(storageMigrationState.detail, level: .success)
      await refresh()
    } catch {
      storageMigrationState = .failed(error)
      errorMessage = storageMigrationState.detail
      log(storageMigrationState.detail, level: .error)
    }
  }

  func rollbackActiveStorage(
    to previousStorage: KnownProjectActiveStorage,
    persistProjectRegistry: () throws -> Void
  ) async -> String? {
    activeStorage = previousStorage
    var rollbackFailure: String?
    do {
      try persistProjectRegistry()
    } catch {
      rollbackFailure = error.localizedDescription
    }
    await refresh()
    return rollbackFailure
  }
}
