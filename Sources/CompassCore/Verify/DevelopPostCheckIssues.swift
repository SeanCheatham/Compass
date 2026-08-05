import Foundation

public enum DevelopPostCheckIssues {
  public static func developFailureIssue(_ develop: DevelopSummary) -> String {
    let summary = develop.summary.trimmingCharacters(in: .whitespacesAndNewlines)
    let feedback = develop.feedback.trimmingCharacters(in: .whitespacesAndNewlines)
    let detail = [summary, feedback].filter { !$0.isEmpty }.joined(separator: "\n\n")
    return """
      Develop did not produce a verifiable success.

      Status: \(develop.status.rawValue)
      bypassVerify: \(develop.bypassVerify == true ? "true" : "false")

      \(detail.isEmpty ? "_(no summary or feedback)_" : detail)
      """
  }

  public static func developBudgetExhaustionIssue(
    attempt: Int,
    error: AgentExecutionError
  ) -> String {
    """
    Develop attempt \(attempt) ended without a phase submit envelope: \(error.localizedDescription).

    The next attempt should make a smaller, more direct change. Reuse already discovered file paths and tool results, avoid repeating failed path guesses, and submit status=failed with concise feedback if the requested plan is not achievable within the iteration budget.
    """
  }

  public static func noDevelopChangesIssue(_ develop: DevelopSummary) -> String {
    let summary = develop.summary.trimmingCharacters(in: .whitespacesAndNewlines)
    let feedback = develop.feedback.trimmingCharacters(in: .whitespacesAndNewlines)
    return """
      Develop submitted status=succeeded, but Compass did not detect any Git-visible file changes or commits.

      A successful Develop pass must modify, create, delete, or commit files that implement the handoff before verification can prove anything. Do not submit success after only failed tool calls.

      Reported summary:
      \(summary.isEmpty ? "_(empty)_" : summary)

      Reported feedback:
      \(feedback.isEmpty ? "_(empty)_" : feedback)
      """
  }

  public static func verifyFailureIssue(command: String, result: ProcessResult) -> String {
    let combined = outputTail(result.stdout + result.stderr, max: 4000)
    let insight = VerifyFailureInsight(
      detail: combined,
      metadata: "command=\(command) exitCode=\(result.exitCode)"
    )
    return """
      Verify failed for `\(command)` with exit code \(result.exitCode).

      \(insight.inspectDetail)

      Repair guidance: \(insight.repairDetail)

      Verify output:
      \(combined.isEmpty ? "_(no output)_" : combined)
      """
  }

  public static func packageManagerBootstrapFailureIssue(from detail: String) -> String? {
    let insight = VerifyFailureInsight(detail: detail, metadata: nil)
    guard insight.kind == .packageManagerBootstrap else { return nil }
    return """
      Rust toolchain bootstrap failed before project verification could run.

      \(insight.inspectDetail)

      Repair guidance: \(insight.repairDetail)

      Compass will not retry Develop for this failure because application code changes cannot
      repair Cargo, rustup, or network availability in the execution environment.
      """
  }

  /// Interprets host `git status --porcelain` after Develop.
  ///
  /// Factory Develop edits the host worktree via file tools and cannot commit
  /// from guest bash (no `.git`). Dirty tracked/untracked files are therefore
  /// expected; the harness lands them with `landDevelopChanges` after Critic
  /// approves. This helper only fails when Git itself is broken or when
  /// Develop claimed success with no Git-visible changes at all.
  public static func hostWorkingTreeIssues(
    porcelain: String,
    changedPaths: [String],
    develop: DevelopSummary
  ) -> HostWorkingTreeAssessment {
    let trimmed = porcelain.trimmingCharacters(in: .whitespacesAndNewlines)
    if changedPaths.isEmpty {
      return HostWorkingTreeAssessment(
        issues: [noDevelopChangesIssue(develop)],
        dirtyPendingHarnessCommit: !trimmed.isEmpty
      )
    }
    return HostWorkingTreeAssessment(
      issues: [],
      dirtyPendingHarnessCommit: !trimmed.isEmpty
    )
  }

  public struct HostWorkingTreeAssessment: Equatable, Sendable {
    public var issues: [String]
    public var dirtyPendingHarnessCommit: Bool

    public init(issues: [String], dirtyPendingHarnessCommit: Bool) {
      self.issues = issues
      self.dirtyPendingHarnessCommit = dirtyPendingHarnessCommit
    }
  }

  private static func outputTail(_ text: String, max: Int) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count > max else { return trimmed }
    return String(trimmed.suffix(max))
  }
}
