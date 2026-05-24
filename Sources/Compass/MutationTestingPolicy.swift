import Foundation

enum MutationTestingPolicy {
  enum Mode: String, Equatable {
    case off
    case manual
    case auto
  }

  static let modeEnvironmentKey = "COMPASS_MUTATION_MODE"
  static let cadenceEnvironmentKey = "COMPASS_MUTATION_EVERY"
  static let minDifficultyEnvironmentKey = "COMPASS_MUTATION_MIN_DIFFICULTY"

  static func mode(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> Mode {
    let raw = environment[modeEnvironmentKey]?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    switch raw {
    case "off", "disabled", "0", "false":
      return .off
    case "manual", "opt-in", "opt_in":
      return .manual
    case "auto", "on", "1", "true", nil, "":
      return .auto
    default:
      return .auto
    }
  }

  static func cadence(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> Int {
    let raw = environment[cadenceEnvironmentKey]?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let raw, !raw.isEmpty, let parsed = Int(raw), parsed >= 0 else {
      return 1
    }
    return parsed
  }

  static func minimumDifficulty(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> PlanNext.Difficulty? {
    let raw = environment[minDifficultyEnvironmentKey]?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    switch raw {
    case nil, "", "all", "any":
      return nil
    case "low":
      return .low
    case "medium":
      return .medium
    case "high":
      return .high
    default:
      return nil
    }
  }

  static func shouldRunAutomatically(
    sessionNumber: Int,
    estimatedDifficulty: PlanNext.Difficulty?,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> Bool {
    guard mode(environment: environment) == .auto else { return false }
    let every = cadence(environment: environment)
    guard every > 0, sessionNumber % every == 0 else { return false }
    guard meetsDifficultyThreshold(
      estimatedDifficulty,
      minimum: minimumDifficulty(environment: environment)
    ) else {
      return false
    }
    return true
  }

  static func meetsDifficultyThreshold(
    _ estimatedDifficulty: PlanNext.Difficulty?,
    minimum: PlanNext.Difficulty?
  ) -> Bool {
    guard let minimum else { return true }
    guard let estimatedDifficulty else { return minimum == .low }
    return difficultyRank(estimatedDifficulty) >= difficultyRank(minimum)
  }

  private static func difficultyRank(_ difficulty: PlanNext.Difficulty) -> Int {
    switch difficulty {
    case .low: return 0
    case .medium: return 1
    case .high: return 2
    }
  }
}
