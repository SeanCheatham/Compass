import Foundation

/// Deterministic acceptance thresholds persisted in factory state. When set,
/// a green verify is not enough — collected coverage/mutation evidence must
/// also satisfy the gates before an iteration is accepted.
public struct AcceptanceGates: Codable, Equatable, Sendable {
  public var minLineCoveragePercent: Double?
  public var minMutationScorePercent: Double?
  public var maxMissedMutants: Int?

  public init(
    minLineCoveragePercent: Double? = nil,
    minMutationScorePercent: Double? = nil,
    maxMissedMutants: Int? = nil
  ) {
    self.minLineCoveragePercent = minLineCoveragePercent
    self.minMutationScorePercent = minMutationScorePercent
    self.maxMissedMutants = maxMissedMutants
  }

  public var isEmpty: Bool {
    minLineCoveragePercent == nil && minMutationScorePercent == nil && maxMissedMutants == nil
  }

  /// Gates seeded from the process environment when state.json does not set any.
  public static func defaultFromEnvironment(
    _ environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> AcceptanceGates? {
    func double(_ key: String) -> Double? {
      guard let raw = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
        !raw.isEmpty
      else { return nil }
      return Double(raw)
    }
    func int(_ key: String) -> Int? {
      guard let raw = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
        !raw.isEmpty
      else { return nil }
      return Int(raw)
    }
    let gates = AcceptanceGates(
      minLineCoveragePercent: double("COMPASS_GATE_MIN_COVERAGE"),
      minMutationScorePercent: double("COMPASS_GATE_MIN_MUTATION_SCORE"),
      maxMissedMutants: int("COMPASS_GATE_MAX_MISSED_MUTANTS")
    )
    return gates.isEmpty ? nil : gates
  }

  /// Human/agent-readable violations given the latest collected evidence.
  /// Missing evidence for a configured gate is itself a violation.
  public func violations(
    coverage: CoverageSnapshot?,
    mutation: MutationSnapshot?
  ) -> [String] {
    var issues: [String] = []
    if let minimum = minLineCoveragePercent {
      if let overall = coverage?.overallLineCoveragePercent {
        if overall < minimum {
          issues.append(
            String(
              format: "coverage gate: overall line coverage %.1f%% is below the required %.1f%%.",
              overall, minimum))
        }
      } else {
        issues.append(
          String(
            format: "coverage gate requires >= %.1f%% line coverage, but no coverage snapshot was collected.",
            minimum))
      }
    }
    if let minimum = minMutationScorePercent {
      if let score = mutation?.mutationScorePercent {
        if score < minimum {
          issues.append(
            String(
              format: "mutation gate: mutation score %.1f%% is below the required %.1f%%.",
              score, minimum))
        }
      } else {
        issues.append(
          String(
            format: "mutation gate requires >= %.1f%% mutation score, but no mutation snapshot was collected.",
            minimum))
      }
    }
    if let maximum = maxMissedMutants {
      if let mutation {
        if mutation.missed > maximum {
          issues.append(
            "mutation gate: \(mutation.missed) surviving mutants exceed the allowed maximum of \(maximum).")
        }
      } else {
        issues.append(
          "mutation gate allows at most \(maximum) surviving mutants, but no mutation snapshot was collected.")
      }
    }
    return issues
  }
}

public extension AcceptanceGates {
  /// Resolves the active gates: explicit state gates win, environment defaults
  /// apply otherwise, and no gates means no post-verify acceptance checks.
  static func active(
    from state: PlanState,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> AcceptanceGates? {
    if let gates = state.acceptanceGates, !gates.isEmpty { return gates }
    return defaultFromEnvironment(environment)
  }
}
