import AppKit
import CompassCore
import Foundation

@MainActor
extension CompassProject {
  /// Commit the Develop iteration's changes onto the host's current
  /// branch (under the macOS VM route) and apply any lesson edits. Returns nil
  /// on success or a single human-readable issue string when the host
  /// commit fails. Lesson-edit failures are logged but not treated as
  /// blockers — they're durable guidance, not the iteration's product.
  func landDevelopChanges(
    workspace: CompassWorkspace,
    summary: DevelopSummary,
    launchPlan: AgentExecutionLaunchPlan,
    sessionIndex: Int
  ) async -> String? {
    if case .macOSVM = launchPlan.effectiveRoute {
      if let commitIssue = await commitAgentChangesOnHost(
        mainRepoURL: workspace.repoURL,
        summary: summary
      ) {
        return commitIssue
      }
    }
    do {
      logLessonEdits(try workspace.applyLessonEdits(summary.lessonEdits))
    } catch {
      let note = "Lesson edits were not applied: \(error.localizedDescription)"
      appendSessionNote(note, to: sessionIndex)
      log(note, level: .error)
    }
    return nil
  }

  /// Stages whatever the agent's host-side file tools left in the main
  /// repo and lands it as a single commit on the user's current branch.
  ///
  /// Returns nil on success, or a human-readable issue string on
  /// failure.
  func commitAgentChangesOnHost(
    mainRepoURL: URL,
    summary: DevelopSummary
  ) async -> String? {
    // Skip the commit entirely when there is nothing to commit. The
    // agent may have done a no-op iteration (or pulled an exact
    // duplicate of what's already on the branch); committing an
    // empty change would either fail or produce noise.
    let status: ProcessResult
    do {
      status = try await ProcessRunner.runEnv(
        "git",
        ["status", "--porcelain"],
        workingDirectory: mainRepoURL,
        timeout: 30
      )
    } catch {
      return "Host-side commit failed at git status: \(error.localizedDescription)"
    }
    if status.exitCode != 0 {
      return
        "Host-side commit failed at git status (exit \(status.exitCode)): \(tail(status.stderr + status.stdout, max: 2000))"
    }
    if status.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      log(
        "Host-side commit: pulled container workspace is identical to the host branch — nothing to commit.",
        level: .info)
      return nil
    }

    do {
      try await runGitOrThrow(
        ["add", "-A"],
        in: mainRepoURL,
        failurePrefix: "Failed to stage agent changes on host"
      )
    } catch {
      return error.localizedDescription
    }

    let message = commitMessage(for: summary)
    do {
      try await runGitOrThrow(
        ["commit", "-m", message],
        in: mainRepoURL,
        failurePrefix: "Failed to create host-side commit for agent changes"
      )
    } catch {
      return error.localizedDescription
    }
    log("Host-side commit landed: \(boundedFirstLine(message, limit: 72))", level: .success)
    return nil
  }

  /// Renders the host-side commit message Compass writes after pulling
  /// from the container workspace. Format mirrors the Develop submit payload:
  /// the summary becomes the subject (truncated), feedback the body.
  func commitMessage(for summary: DevelopSummary) -> String {
    let subject = boundedFirstLine(summary.summary, limit: 72)
    let feedback = summary.feedback.trimmingCharacters(in: .whitespacesAndNewlines)
    if feedback.isEmpty {
      return subject
    }
    return "\(subject)\n\n\(feedback)"
  }

  /// Helper: pick the first non-empty line of `text`, trimmed and
  /// truncated to `limit` chars. Used to keep commit-subject lines
  /// inside conventional 72-column limits regardless of what the agent
  /// returned.
  func boundedFirstLine(_ text: String, limit: Int) -> String {
    let firstLine =
      text
      .split(whereSeparator: \.isNewline)
      .first
      .map(String.init)?
      .trimmingCharacters(in: .whitespaces) ?? ""
    if firstLine.isEmpty { return "Develop iteration (no summary)" }
    if firstLine.count <= limit { return firstLine }
    return String(firstLine.prefix(limit)).trimmingCharacters(in: .whitespaces)
  }

  func runGitOrThrow(_ arguments: [String], in directory: URL, failurePrefix: String)
    async throws
  {
    let result = try await ProcessRunner.runEnv("git", arguments, workingDirectory: directory)
    guard result.exitCode == 0 else {
      throw AppModelError.gitCommandFailed(
        "\(failurePrefix): \(tail(result.stderr + result.stdout, max: 2000))"
      )
    }
  }

  func gitCurrentSha(at repoURL: URL) async -> String? {
    guard
      let result = try? await ProcessRunner.runEnv(
        "git",
        ["rev-parse", "HEAD"],
        workingDirectory: repoURL
      ), result.exitCode == 0
    else {
      return nil
    }
    return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Capture the unified diff from `since` (a SHA, may be nil for
  /// "initial commit") to the working tree's current state, including
  /// staged + unstaged + untracked files. Best-effort: returns an empty
  /// string when git fails so the Critic prompt always renders.
  ///
  /// `git diff <sha>` shows tracked changes; untracked files are
  /// appended separately via `git status --porcelain` + `git diff
  /// --no-index /dev/null <path>` so the Critic sees brand-new files
  /// instead of only modifications.
  func gitDiffSinceSha(_ since: String?, in repoURL: URL) async -> String {
    var sections: [String] = []
    let baseArguments: [String]
    if let since {
      baseArguments = ["diff", "--no-color", "\(since)..HEAD"]
    } else {
      baseArguments = ["diff", "--no-color", "HEAD"]
    }
    if let trackedDiff = try? await ProcessRunner.runEnv(
      "git", baseArguments, workingDirectory: repoURL),
      trackedDiff.exitCode == 0,
      !trackedDiff.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      sections.append(trackedDiff.stdout)
    }
    if let workingDiff = try? await ProcessRunner.runEnv(
      "git", ["diff", "--no-color", "HEAD"], workingDirectory: repoURL),
      workingDiff.exitCode == 0,
      !workingDiff.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      sections.append(workingDiff.stdout)
    }
    if let untrackedList = try? await ProcessRunner.runEnv(
      "git", ["ls-files", "--others", "--exclude-standard"], workingDirectory: repoURL),
      untrackedList.exitCode == 0
    {
      let paths = untrackedList.stdout
        .split(whereSeparator: \.isNewline)
        .map(String.init)
        .filter { !$0.isEmpty }
      for path in paths {
        if let added = try? await ProcessRunner.runEnv(
          "git",
          ["diff", "--no-color", "--no-index", "--", "/dev/null", path],
          workingDirectory: repoURL
        ),
          !added.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
          sections.append(added.stdout)
        }
      }
    }
    let combined = sections.joined(separator: "\n")
    return tail(combined, max: 32_000)
  }

  func gitCommits(in repoURL: URL, from before: String?, to after: String?) async
    -> [SessionCommit]
  {
    guard let after, before != after else { return [] }
    let range = before.map { "\($0)..\(after)" } ?? after
    guard
      let result = try? await ProcessRunner.runEnv(
        "git",
        ["log", "--reverse", "--format=%H%x09%h%x09%s", range],
        workingDirectory: repoURL
      ), result.exitCode == 0
    else {
      return []
    }

    return result.stdout
      .split(whereSeparator: \.isNewline)
      .compactMap { line in
        let parts = line.split(separator: "\t", maxSplits: 2).map(String.init)
        guard parts.count == 3 else { return nil }
        return SessionCommit(sha: parts[0], short: parts[1], subject: parts[2])
      }
  }
}
