import Foundation

/// Shared Plan-pass outcome used by UI auto-play and headless single-shot runs.
public enum FactoryPlanOutcome: Equatable, Sendable {
  case developed
  case noImmediateWork
  case requirementsComplete
  case requirementsNeedReplan(findingsDraft: String)
  case pausedBeforeDevelop
  case failed(String?)
  case cancelled
}

/// Result of post-Develop verify + working-tree checks.
public struct FactoryPostCheckResult: Equatable, Sendable {
  public var ok: Bool
  /// True when Develop found that the planned verify command itself needs a new Plan pass.
  public var requiresPlanRepair: Bool
  public var verifyIssues: [String]
  public var gitStatusIssues: [String]
  public var verifyOutput: VerifyOutput?

  public init(
    ok: Bool,
    requiresPlanRepair: Bool = false,
    verifyIssues: [String] = [],
    gitStatusIssues: [String] = [],
    verifyOutput: VerifyOutput? = nil
  ) {
    self.ok = ok
    self.requiresPlanRepair = requiresPlanRepair
    self.verifyIssues = verifyIssues
    self.gitStatusIssues = gitStatusIssues
    self.verifyOutput = verifyOutput
  }
}

/// Options that control shared factory pass behavior for UI and headless adapters.
public struct FactoryPassOptions: Equatable, Sendable {
  public var maxDevelopAttempts: Int
  public var maxCriticAttempts: Int
  public var maxVerifyRepairAttempts: Int
  /// Critic runs after green post-checks. Default `true` for both UI and headless.
  public var runCritic: Bool
  public var continueToDevelop: Bool
  public var commitOnSuccess: Bool
  /// When Critic infra fails, treat as approve so flaky review does not strand good work.
  public var failOpenCritic: Bool
  public var clearDraftsOnPlan: Bool
  public var markStaleOnShip: Bool
  /// How often to force headed macOS UI fidelity (every N successful ships). `0` disables cadence.
  public var macosFidelityCadence: Int
  /// Always run fidelity on the iteration before a full requirements audit.
  public var forceFidelityBeforeFullAudit: Bool

  public init(
    maxDevelopAttempts: Int = 3,
    maxCriticAttempts: Int = 3,
    maxVerifyRepairAttempts: Int = 0,
    runCritic: Bool = true,
    continueToDevelop: Bool = true,
    commitOnSuccess: Bool = true,
    failOpenCritic: Bool = true,
    clearDraftsOnPlan: Bool = true,
    markStaleOnShip: Bool = true,
    macosFidelityCadence: Int = MacOSFidelityCadence.defaultInterval,
    forceFidelityBeforeFullAudit: Bool = true
  ) {
    self.maxDevelopAttempts = max(1, maxDevelopAttempts)
    self.maxCriticAttempts = max(1, maxCriticAttempts)
    self.maxVerifyRepairAttempts = max(0, maxVerifyRepairAttempts)
    self.runCritic = runCritic
    self.continueToDevelop = continueToDevelop
    self.commitOnSuccess = commitOnSuccess
    self.failOpenCritic = failOpenCritic
    self.clearDraftsOnPlan = clearDraftsOnPlan
    self.markStaleOnShip = markStaleOnShip
    self.macosFidelityCadence = max(0, macosFidelityCadence)
    self.forceFidelityBeforeFullAudit = forceFidelityBeforeFullAudit
  }

  public static let uiDefaults = FactoryPassOptions()

  public static let headlessDefaults = FactoryPassOptions(
    maxDevelopAttempts: 2,
    maxCriticAttempts: 3,
    maxVerifyRepairAttempts: 1,
    runCritic: true,
    continueToDevelop: true,
    commitOnSuccess: false,
    failOpenCritic: true,
    clearDraftsOnPlan: false,
    markStaleOnShip: true
  )
}

/// Cadence policy for headed macOS UI fidelity runs.
public enum MacOSFidelityCadence {
  public static let defaultInterval = 5

  /// Whether this ship iteration should enable `COMPASS_MACOS_UI_FIDELITY=1`.
  ///
  /// Runs when the host env already opts in, when `force` is set (e.g. before a
  /// full requirements audit), or when `successfulShipCount` is a positive
  /// multiple of `cadence` (ships 5, 10, 15… when cadence is 5).
  public static func shouldEnableFidelity(
    successfulShipCount: Int,
    cadence: Int,
    force: Bool = false,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> Bool {
    if MacOSUISmokeSupport.isFidelityEnabled(environment: environment) {
      return true
    }
    if force { return true }
    guard cadence > 0, successfulShipCount > 0 else { return false }
    return successfulShipCount % cadence == 0
  }

  /// Environment overlay that enables fidelity for `MacOSVerifyGate`.
  public static func environmentEnablingFidelity(
    base: [String: String] = ProcessInfo.processInfo.environment
  ) -> [String: String] {
    var env = base
    env[MacOSUISmokeSupport.fidelityEnvironmentKey] = "1"
    env[GeneratedProjectQuality.macosUIFidelityEnvironmentKey] = "1"
    return env
  }
}

/// Lightweight progress events from shared pass helpers.
public struct FactoryPassEvent: Equatable, Sendable {
  public enum Kind: String, Sendable {
    case log
    case phase
    case verify
    case retry
    case fidelity
  }

  public var kind: Kind
  public var level: String
  public var message: String
  public var detail: String?

  public init(kind: Kind, level: String = "info", message: String, detail: String? = nil) {
    self.kind = kind
    self.level = level
    self.message = message
    self.detail = detail
  }
}
