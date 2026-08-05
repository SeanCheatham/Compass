import Foundation

public enum AcceptanceGateEvaluator {
  /// Returns a single multi-line retry issue, or nil if no gates / all pass.
  public static func issue(state: PlanState, workspace: CompassWorkspace) -> String? {
    guard let gates = AcceptanceGates.active(from: state) else { return nil }
    let violations = gates.violations(
      coverage: CoverageSnapshotStore.readCoverageSnapshot(from: workspace),
      mutation: MutationSnapshotStore.readMutationSnapshot(from: workspace)
    )
    guard !violations.isEmpty else { return nil }
    return """
      Verify passed, but the acceptance gates rejected this iteration:
      \(violations.map { "- \($0)" }.joined(separator: "\n"))

      Gates are deterministic quality thresholds (see `acceptanceGates` in .compass/state.json). \
      Strengthen tests until the collected coverage/mutation evidence satisfies them; do not \
      weaken or delete the gates to make the iteration pass.
      """
  }

  /// Returns zero or one formatted issue strings (for UI arrays).
  public static func issues(state: PlanState, workspace: CompassWorkspace) -> [String] {
    guard let issue = issue(state: state, workspace: workspace) else { return [] }
    return ["[acceptance-gate] \(issue)"]
  }
}
