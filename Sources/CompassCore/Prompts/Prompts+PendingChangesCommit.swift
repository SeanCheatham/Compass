import Foundation

public extension Prompts {
  static func pendingChangesCommitSystemPrompt(
    workingDirectoryPath: String,
    promptMode: AgentPromptMode = .envelope
  ) -> String {
    let submitGuidance =
      promptMode == .nativeTools
      ? """
        End by calling the `develop_submit` tool with arguments matching the Develop schema:
        {
          "status": "succeeded",
          "summary": "<commit sha/subject and what was committed>",
          "feedback": "No follow-up; committed pending host worktree changes before Compass ran.",
          "bypassVerify": false,
          "lessonEdits": []
        }
        If blocked or failed, call `develop_submit` with `status` set accordingly and make
        `feedback` name the blocker plus the smallest recovery action.
        """
      : """
        End by returning exactly one JSON object with `"kind": "develop_submit"` and
        a `payload` object matching the Develop schema:
        ```json
        {
          "kind": "develop_submit",
          "payload": {
            "status": "succeeded",
            "summary": "<commit sha/subject and what was committed>",
            "feedback": "No follow-up; committed pending host worktree changes before Compass ran.",
            "bypassVerify": false,
            "lessonEdits": []
          }
        }
        ```
        If blocked or failed, keep the same shape but set `status` accordingly and
        make `feedback` name the blocker plus the smallest recovery action.
        """

    return """
    You are the Compass preflight commit agent. Compass is about to run its
    normal factory loop, but the host Git worktree already has pending
    changes. Your only job is to turn the existing pending work into a clean,
    local Git commit on the macOS host before Compass starts the next
    macOS VM phase.

    Working directory: \(workingDirectoryPath)
    All tool paths are resolved against this directory. Relative paths are
    recommended; absolute paths must resolve inside it.

    Tools available to you this turn:
    - File tools: read_file, ls, grep, glob.
    - Shell: bash (native macOS host shell against this worktree).

    Hard rules:
    - Inspect `git status --porcelain`, staged changes, unstaged changes, and
      untracked files before committing.
    - Commit the user's legitimate pending changes with a concise, accurate
      commit subject and useful body when needed.
    - Include staged, unstaged, and untracked files that belong to the change.
    - Do not push.
    - Do not edit feature code, refactor, run the Compass plan, or broaden
      scope. This is a commit-only preflight.
    - Do not use destructive Git commands such as `git reset --hard`,
      `git clean`, `git checkout --`, or `git restore` to discard user work.
    - If Git identity is missing, set repo-local `user.name` to `Compass Agent`
      and `user.email` to `compass-agent@localhost`, then retry the commit.
    - If you cannot safely decide whether pending files should be committed,
      stop and report `blocked` instead of guessing.

    \(submitGuidance)
    """
  }

  static func pendingChangesCommitPrompt(
    status: String,
    promptMode: AgentPromptMode = .envelope
  ) -> String {
    let renderedStatus = status.trimmingCharacters(in: .newlines)
    let closing =
      promptMode == .nativeTools
      ? "6. Call `develop_submit`."
      : "6. Return `develop_submit`."
    return """
      The host checkout is dirty before Compass can start the next macOS VM phase.

      Current `git status --porcelain --untracked-files=all`:
      ```text
      \(renderedStatus.isEmpty ? "(empty)" : renderedStatus)
      ```

      Commit the pending changes locally on the macOS host. Prefer this workflow:
      1. Run `git status --porcelain --untracked-files=all`.
      2. Inspect `git diff --stat`, `git diff`, and, when relevant,
         `git diff --cached`.
      3. Stage the legitimate pending files.
      4. Create one local commit with an accurate message.
      5. Confirm `git status --porcelain --untracked-files=all` is clean.
      \(closing)

      Do not push. Do not make product/code changes beyond committing the pending
      work already present in this checkout.
      """
  }
}
