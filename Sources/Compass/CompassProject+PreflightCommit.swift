import Foundation
import CompassCore

@MainActor
extension CompassProject {
  func commitPendingHostChangesIfNeeded(
    workspace: CompassWorkspace,
    agentSettings: AgentRuntimeSettings,
    modelOverride: String,
    sessionIndex: Int
  ) async throws {
    let beforeStatus = try await gitPorcelainStatus(in: workspace.repoURL)
    guard !beforeStatus.isEmpty else { return }

    let beforeSha = await gitCurrentSha(at: workspace.repoURL)
    log(
      "Preflight commit: dirty host worktree detected; launching commit agent.",
      level: .warning
    )
    appendSessionNote(
      "Preflight commit agent started because the host worktree had pending changes.",
      to: sessionIndex
    )

    let summary = try await runHostPendingChangesCommitAgent(
      workspace: workspace,
      status: beforeStatus,
      agentSettings: agentSettings,
      modelOverride: modelOverride,
      sessionNumber: sessions.indices.contains(sessionIndex)
        ? sessions[sessionIndex].session
        : nil
    )

    let afterStatus = try await gitPorcelainStatus(in: workspace.repoURL)
    guard afterStatus.isEmpty else {
      throw AppModelError.gitCommandFailed(
        """
        Preflight commit agent finished but the host worktree is still dirty:
        \(tail(afterStatus, max: 2000))

        Agent feedback:
        \(summary.feedback)
        """
      )
    }

    let afterSha = await gitCurrentSha(at: workspace.repoURL)
    guard beforeSha != afterSha, let afterSha, !afterSha.isEmpty else {
      throw AppModelError.gitCommandFailed(
        """
        Preflight commit agent cleaned the worktree but did not create a new commit.

        Agent feedback:
        \(summary.feedback)
        """
      )
    }

    log(
      "Preflight commit landed: \(String(afterSha.prefix(12))) \(boundedFirstLine(summary.summary, limit: 96))",
      level: .success
    )
    appendSessionNote(
      "Preflight commit landed \(String(afterSha.prefix(12))): \(summary.summary)",
      to: sessionIndex
    )
  }

  func gitPorcelainStatus(in repoURL: URL) async throws -> String {
    let result = try await ProcessRunner.runEnv(
      "git",
      ["status", "--porcelain", "--untracked-files=all"],
      workingDirectory: repoURL,
      timeout: 30
    )
    guard result.exitCode == 0 else {
      throw AppModelError.gitCommandFailed(
        "Failed to inspect host git status: \(tail(result.stderr + result.stdout, max: 2000))"
      )
    }
    return result.stdout.trimmingCharacters(in: .newlines)
  }

  private func runHostPendingChangesCommitAgent(
    workspace: CompassWorkspace,
    status: String,
    agentSettings: AgentRuntimeSettings,
    modelOverride: String,
    sessionNumber: Int?
  ) async throws -> DevelopSummary {
    let configuration = AgentExecutionConfiguration(
      settings: agentSettings,
      phase: .develop,
      modelOverride: modelOverride,
      systemPrompt: Prompts.pendingChangesCommitSystemPrompt(
        workingDirectoryPath: workspace.repoURL.path
      ),
      userPrompt: Prompts.pendingChangesCommitPrompt(status: status),
      tools: [
        AgentReadFileTool(),
        AgentLsTool(),
        AgentGrepTool(),
        AgentGlobTool(),
        AgentBashTool(),
      ],
      submitResultSchema: AgentToolParametersSchema(json: Data(Prompts.developSchema.utf8)),
      workingDirectory: workspace.repoURL,
      filesystem: AgentHostFilesystem(),
      bashRunner: AgentHostBashRunner(),
      codemapStoreDirectory: CodemapStore.defaultDirectory(forWorkspace: workspace),
      planHistoryEntries: [],
      assumptionsURL: nil,
      sessionNumber: sessionNumber,
      validateSubmitResult: { args in
        _ = try JSONDecoder().decode(DevelopSummary.self, from: args)
      },
      maxIterations: 96,
      wallClockTimeout: 15 * 60
    )

    log("Preflight commit: starting host commit agent loop.", level: .info)
    let agent = AgentExecutor { [weak self] event in
      Task { @MainActor in self?.log(event) }
    }
    executor = agent
    defer {
      if executor === agent {
        executor = nil
      }
    }

    let result = try await agent.run(configuration)
    if let sessionNumber {
      do {
        let artifactURL = try workspace.writeSessionAuditArtifact(
          session: sessionNumber,
          name: "preflight-commit-submit-payload.json",
          kind: "phase_submit_payload",
          contents: String(decoding: result.submitResultArguments, as: UTF8.self),
          note: "Preflight commit submit payload."
        )
        recordSessionAuditArtifactEvent(
          session: sessionNumber,
          kind: "phase_submit_payload_saved",
          artifactURL: artifactURL,
          note: "Saved preflight commit submit payload.",
          metadata: [
            "phase": "preflight-commit",
            "iterations": "\(result.iterations)",
          ]
        )
      } catch {
        appendAuditEvent(
          kind: "phase_submit_payload_save_failed",
          status: "failed",
          text: error.localizedDescription,
          metadata: ["phase": "preflight-commit"]
        )
      }
    }

    return try JSONDecoder().decode(DevelopSummary.self, from: result.submitResultArguments)
  }
}
