import AppKit
import Foundation
import Virtualization

@MainActor
extension CompassProject {
  func agentLaunchPlan(for nativeExecutionURL: URL) -> AgentExecutionLaunchPlan {
    // Compass always routes the agent through the Shared VM; the
    // onboarding gate prevents launches until the VM is ready. The
    // planner still falls back to host when the guest workspace catalog
    // cannot map this repo or the live VM is unavailable.
    let host = SharedCompassVM.shared
    let readiness = host.readiness
    return AgentExecutionLaunchPlan.plan(
      repoURL: nativeExecutionURL,
      vmReadiness: readiness,
      sharedVMRouteFactory: { hostURL in
        Self.makeSharedVMRoute(
          hostRepoURL: hostURL,
          readiness: readiness,
          bundle: host.bundle
        )
      }
    )
  }

  /// Builds a `SharedVMRoute` for a host repo URL by mapping it to
  /// the guest-local path where Compass keeps its Git-backed copy
  /// (`/Users/compass/Compass/Repos/<UUID>/worktree`). Returns nil if
  /// the VM is not ready, or if the catalog lookup fails (planner
  /// falls back to host).
  ///
  /// The mapping no longer references VirtioFS: macOS guests TCC-block
  /// `AppleVirtIOFS` reads from every process (even LaunchAgents inside
  /// the GUI session, even root via LaunchDaemon), so Compass keeps a
  /// real guest clone in sync through the vsock Git exchange instead.
  ///
  /// Callers must pass the user's main repo URL — never a derived
  /// per-iteration path — so every Compass phase (Plan / Reflect /
  /// Develop / Verify) keys off the same catalog entry and sees the
  /// same guest workspace.
  private static func makeSharedVMRoute(
    hostRepoURL: URL,
    readiness: SharedCompassVMReadiness,
    bundle: SharedCompassVMBundle
  ) -> SharedVMRoute? {
    guard case .ready(let sshDestination) = readiness else { return nil }

    let catalogEntry: SharedCompassVMGuestWorkspaceCatalog.CatalogEntry
    do {
      catalogEntry = try SharedCompassVMGuestWorkspaceCatalog.ensureEntry(
        forRepoURL: hostRepoURL
      )
    } catch {
      // Bookkeeping failure shouldn't strand the agent — fall back
      // to host execution rather than throwing inside the launch
      // planner.
      return nil
    }
    let guestWorkspacePath = SharedCompassVMGuestWorkspaceCatalog.guestWorktreePath(
      forEntry: catalogEntry
    )
    let exchangeRepoURL = SharedCompassVMGitExchange.exchangeRepoURL(forHostRepoURL: hostRepoURL)
    let gitRemoteURL = SharedCompassVMGitExchange.remoteURL(repoID: catalogEntry.id)
    let hostBranch = SharedCompassVMGitStateStore.context(forHostRepoURL: hostRepoURL)?.branchName
    SharedCompassVMGitService.shared.register(
      repoID: catalogEntry.id,
      exchangeRepoURL: exchangeRepoURL
    )

    return SharedVMRoute(
      sshDestination: sshDestination,
      hostWorktreeURL: hostRepoURL,
      guestWorkspacePath: guestWorkspacePath,
      environmentVariables: [:],
      identityFile: bundle.privateKeyURL.path,
      knownHostsFile: bundle.knownHostsURL.path,
      catalogID: catalogEntry.id,
      hostBranch: hostBranch,
      exchangeRepoURL: exchangeRepoURL,
      gitRemoteURL: gitRemoteURL
    )
  }

  func logExecutionEnvironmentPreflight(
    phase: String,
    nativeExecutionURL: URL,
    launchPlan: AgentExecutionLaunchPlan? = nil,
    sessionIndex: Int? = nil,
    attempt: Int? = nil
  ) {
    let environment = AgentExecutionEnvironment.discover(
      vmReadiness: SharedCompassVM.shared.readiness
    )
    let effectiveLaunchPlan = launchPlan ?? environment.launchPlan(repoURL: nativeExecutionURL)
    log(
      effectiveLaunchPlan.preflightSummary(phase: phase),
      level: .info
    )
    if let sessionIndex {
      recordSessionExecutionEnvironmentSnapshot(
        phase: phase,
        attempt: attempt,
        launchPlan: effectiveLaunchPlan,
        sessionIndex: sessionIndex
      )
    }
    let presentation = environment.presentation(launchPlan: effectiveLaunchPlan)
    let detail = [presentation.status, presentation.detail, effectiveLaunchPlan.routeDetail()]
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    log(detail, level: presentation.isWarning ? .warning : .info)
  }

  func recordSessionExecutionEnvironmentSnapshot(
    phase: String,
    attempt: Int?,
    launchPlan: AgentExecutionLaunchPlan,
    sessionIndex: Int
  ) {
    guard sessions.indices.contains(sessionIndex) else { return }
    let snapshot = SessionExecutionEnvironmentSnapshot(
      phase: phase,
      attempt: attempt,
      launchPlan: launchPlan
    )
    sessions[sessionIndex].recordExecutionEnvironmentSnapshot(snapshot)
    try? persistSessions()
  }

  /// Build an AgentExecutionConfiguration, run it, and decode the
  /// `submit_result` arguments into the phase result model. Assigns the
  /// executor to `self.executor` so `stopRun()` can cancel mid-stream.
  func runAgent<T: Decodable>(
    phase: AgentPhase,
    agentSettings: AgentRuntimeSettings,
    modelOverride: String,
    workingDirectory: URL,
    userPrompt: String,
    submitResultSchema: String,
    codemapStoreDirectory: URL,
    planHistoryEntries: [String] = [],
    sessionNumber: Int? = nil,
    requiresHostXcode: Bool = false,
    hostXcodeBuildTestEnabled: Bool = false,
    decode: T.Type
  ) async throws -> T {
    let schema = AgentToolParametersSchema(json: Data(submitResultSchema.utf8))
    let environment = resolveAgentEnvironment(forHostURL: workingDirectory)
    if environment.kind == .sharedVM {
      // Ensure the persistent guest workspace has current host Git
      // history before the agent's first read_file. The git-backed path
      // fetches/rebases in place; the legacy tar path remains as an
      // explicit migration fallback.
      log("Guest workspace sync: checking Shared VM copy…", level: .info)
      try await ensurePersistentGuestWorkspace(forHostRepo: workingDirectory)
    }
    let toolchainService: (any SharedVMToolchainService)? =
      environment.kind == .sharedVM
      ? SharedCompassVM.shared.makeToolchainService()
      : nil
    let hostXcodeService =
      try await checkedHostXcodeService(
        for: phase,
        hostRepoURL: workingDirectory,
        launchPlan: environment.launchPlan,
        requiresHostXcode: requiresHostXcode,
        hostXcodeBuildTestEnabled: hostXcodeBuildTestEnabled
      )
    let rustCargoService =
      makeRustCargoService(
        forgeProfile: forgeProfile,
        environmentKind: environment.kind
      )
    var installedToolchainIDs: [String] = []
    if environment.kind == .sharedVM {
      installedToolchainIDs =
        SharedCompassVMToolchainManager(
          bundle: SharedCompassVM.shared.bundle
        ).installedToolchainIDsFromState()
    }
    let validateSubmitResult = submitResultValidation(
      for: phase,
      hostRepoURL: workingDirectory,
      decode: T.self
    )
    let tools = ToolRegistry.tools(
      for: phase,
      settings: agentSettings,
      toolchainService: toolchainService,
      hostXcodeService: hostXcodeService,
      rustCargoService: rustCargoService
    )
    let externalToolNames = tools.compactMap { tool -> String? in
      switch tool.spec.name {
      case AgentWebSearchTool.toolName, AgentUnderstandImageTool.toolName:
        return tool.spec.name
      default:
        return nil
      }
    }
    let configuration = AgentExecutionConfiguration(
      settings: agentSettings,
      phase: phase,
      modelOverride: modelOverride,
      systemPrompt: Prompts.agentSystemPrompt(
        phase: phase,
        workingDirectoryPath: environment.workingDirectory.path,
        executionEnvironment: environment.kind == .sharedVM ? .sharedVM : .host,
        installedToolchainIDs: installedToolchainIDs,
        hostXcodeBuildTestEnabled: hostXcodeService != nil,
        rustCargoToolsEnabled: rustCargoService != nil,
        externalToolNames: externalToolNames
      ),
      userPrompt: userPrompt,
      tools: tools,
      submitResultSchema: schema,
      workingDirectory: environment.workingDirectory,
      filesystem: environment.filesystem,
      bashRunner: environment.bashRunner,
      codemapStoreDirectory: codemapStoreDirectory,
      planHistoryEntries: planHistoryEntries,
      assumptionsURL: makeWorkspace(repoURL: workingDirectory).assumptionsURL,
      sessionNumber: sessionNumber,
      toolchainService: toolchainService,
      hostXcodeService: hostXcodeService,
      rustCargoService: rustCargoService,
      validateSubmitResult: validateSubmitResult
    )
    log("\(phase.rawValue.capitalized): starting agent loop.", level: .info)
    let agent = AgentExecutor { [weak self] event in
      Task { @MainActor in self?.log(event) }
    }
    executor = agent
    let result = try await agent.run(configuration)
    if let sessionNumber {
      do {
        let artifactURL = try makeWorkspace(repoURL: workingDirectory).writeSessionAuditArtifact(
          session: sessionNumber,
          name: "\(phase.rawValue)-submit-result.json",
          kind: "submit_result",
          contents: String(decoding: result.submitResultArguments, as: UTF8.self),
          note: "\(phase.rawValue) submit_result payload."
        )
        recordSessionAuditArtifactEvent(
          session: sessionNumber,
          kind: "submit_result_saved",
          artifactURL: artifactURL,
          note: "Saved \(phase.rawValue) submit_result payload.",
          metadata: [
            "phase": phase.rawValue,
            "iterations": "\(result.iterations)",
          ]
        )
      } catch {
        appendAuditEvent(
          kind: "submit_result_save_failed",
          status: "failed",
          text: error.localizedDescription,
          metadata: ["phase": phase.rawValue]
        )
      }
    }
    do {
      return try JSONDecoder().decode(T.self, from: result.submitResultArguments)
    } catch {
      let body = String(decoding: result.submitResultArguments, as: UTF8.self)
      throw AppModelError.internalInvariant(
        "Could not decode \(T.self) from submit_result: \(error.localizedDescription)\n\(body)"
      )
    }
  }

  /// Reject `submit_result` in-flight when lesson edits don't match
  /// lessons.md or the payload can't decode into the phase result model.
  func submitResultValidation<T: Decodable>(
    for phase: AgentPhase,
    hostRepoURL: URL,
    decode: T.Type
  ) -> (@Sendable (Data) throws -> Void) {
    let hostWorkspace = makeWorkspace(repoURL: hostRepoURL)
    let validatesLessonEdits = phase == .plan || phase == .develop || phase == .reflect
    let activeForgeProfile = forgeProfile
    return { args in
      if validatesLessonEdits {
        try hostWorkspace.validateSubmitResultLessonEdits(args)
      }
      let decoded = try JSONDecoder().decode(T.self, from: args)
      if phase == .develop, let developResult = decoded as? DevelopSummary {
        try DevelopFeedbackValidator.validate(developResult)
        try DevelopVerifyBypassValidator.validate(developResult)
      }
      if phase == .critic, let criticResult = decoded as? CriticVerdict {
        try CriticFeedbackValidator.validate(criticResult)
      }
      guard phase == .plan, let planResult = decoded as? PlanRunResult else { return }
      let currentState = try hostWorkspace.readState()
      let nextState = currentState.applying(proposal: planResult.state)
      try PlanTransitionValidator.validate(
        from: currentState,
        to: nextState,
        forgeProfile: activeForgeProfile,
        productTournamentConfig: try? hostWorkspace.readProductTournamentConfig()
      )
    }
  }

  /// Resolved working directory + tool backends for an agent run.
  /// When the project's execution preference is `.sharedVM` and the
  /// VM resolves to a ready route for `hostURL`, the agent operates
  /// entirely inside the persistent per-repo guest workspace via the
  /// vsock-served Compass guest agent. `SharedCompassVMRepoWorkspaceSync`
  /// populates that workspace lazily on first use; under the host
  /// route the agent stays native and works against `hostURL`
  /// directly.
  struct AgentEnvironment {
    /// Coarse descriptor for the agent's runtime environment. Used by
    /// the system-prompt builder to teach the model what tooling it
    /// can expect — e.g. the Shared VM has Command Line Tools only,
    /// not full Xcode, so reaching for `xcodebuild` is wasted work.
    enum Kind {
      case host
      case sharedVM
    }
    var kind: Kind
    var workingDirectory: URL
    var filesystem: AgentFilesystem
    var bashRunner: AgentBashRunner
    var launchPlan: AgentExecutionLaunchPlan
  }

  func resolveAgentEnvironment(forHostURL hostURL: URL) -> AgentEnvironment {
    let launchPlan = agentLaunchPlan(for: hostURL)
    switch launchPlan.effectiveRoute {
    case .host:
      if let reason = launchPlan.fallbackReason {
        log("Agent route falling back to host: \(reason)", level: .info)
      }
      return AgentEnvironment(
        kind: .host,
        workingDirectory: hostURL,
        filesystem: AgentHostFilesystem(),
        bashRunner: AgentHostBashRunner(),
        launchPlan: launchPlan
      )
    case .sharedVM(let route):
      guard let machine = SharedCompassVM.shared.virtualMachine else {
        log(
          "Agent route via Shared VM requested but no live VZVirtualMachine; falling back to host.",
          level: .warning)
        return AgentEnvironment(
          kind: .host,
          workingDirectory: hostURL,
          filesystem: AgentHostFilesystem(),
          bashRunner: AgentHostBashRunner(),
          launchPlan: AgentExecutionLaunchPlan.host(
            vmReadiness: launchPlan.vmReadiness,
            fallbackReason: "Shared VM route requested but no live virtual machine was available."
          )
        )
      }
      // `route.guestWorkspacePath` is the persistent per-repo
      // guest workspace (from `SharedCompassVMGuestWorkspaceCatalog`)
      // — the same directory for every Plan / Reflect / Develop /
      // Verify run against this repo.
      let guestWorkingDirectory = URL(fileURLWithPath: route.guestWorkspacePath)
      log(
        "Agent route via Shared VM (vsock) at workspace \(guestWorkingDirectory.path)", level: .info
      )
      let client = Self.makeVsockClient(on: machine)
      return AgentEnvironment(
        kind: .sharedVM,
        workingDirectory: guestWorkingDirectory,
        filesystem: client,
        bashRunner: client,
        launchPlan: launchPlan
      )
    }
  }

  func checkedHostXcodeService(
    for phase: AgentPhase,
    hostRepoURL: URL,
    launchPlan: AgentExecutionLaunchPlan,
    requiresHostXcode: Bool,
    hostXcodeBuildTestEnabled: Bool
  ) async throws -> HostXcodeService? {
    guard phase == .develop,
      hostXcodeBuildTestEnabled,
      requiresHostXcode
    else {
      return nil
    }
    let service = try makeHostXcodeService(hostRepoURL: hostRepoURL, launchPlan: launchPlan)
    let status = await service.status()
    guard status.isReady else {
      throw AppModelError.internalInvariant(
        "Host Xcode build/test is enabled for this project and the active plan requires it, but host Xcode is not ready. \(status.unavailableReason ?? "Open Xcode once and complete first-launch/license setup.")"
      )
    }
    log(
      "Host Xcode build/test bridge ready: \(status.version ?? "xcodebuild")",
      level: .info
    )
    return service
  }

  func makeHostXcodeService(
    hostRepoURL: URL,
    launchPlan: AgentExecutionLaunchPlan,
    mirrorRootURL: URL? = nil,
    runner: ProcessRunner.InvocationRunner? = nil
  ) throws -> HostXcodeService {
    let root = mirrorRootURL ?? HostXcodeService.defaultMirrorRootURL()
    switch launchPlan.effectiveRoute {
    case .host:
      return HostXcodeService(hostRepoURL: hostRepoURL, mirrorRootURL: root, runner: runner)
    case .sharedVM(let route):
      guard let machine = SharedCompassVM.shared.virtualMachine else {
        throw AppModelError.internalInvariant(
          "Host Xcode build/test requires the live Shared VM workspace, but no virtual machine is connected."
        )
      }
      return HostXcodeService(
        hostRepoURL: hostRepoURL,
        guestWorkspacePath: route.guestWorkspacePath,
        client: Self.makeVsockClient(on: machine),
        mirrorRootURL: root,
        runner: runner
      )
    }
  }

  func makeRustCargoService(
    forgeProfile: ForgeProfile?,
    environmentKind: AgentEnvironment.Kind
  ) -> RustCargoService? {
    guard forgeProfile == .rustCargo else { return nil }
    guard environmentKind == .host else {
      // The Shared VM route will use the guest-installed engine once
      // the RPC handoff lands; until then avoid handing a host process
      // a guest-only workspace path.
      return nil
    }
    guard let engineURL = RustEngineLocator.locateEngineBinary() else { return nil }
    return RustCargoService(
      engineURL: engineURL,
      pathPrefix: "\(NSHomeDirectory())/.cargo/bin"
    )
  }

  /// Runs the Verify shell command in the same place the agent just
  /// operated. For `.sharedVM` routes this goes through the guest's
  /// bash RPC against the persistent guest workspace; everything else
  /// falls through to the existing host-side `ProcessRunner.runShell`
  /// path.
  ///
  /// The host workingDirectory parameter is only used by the host
  /// fallback. Under .sharedVM the guest path is resolved via the
  /// catalog so the command runs against the same `<UUID>/worktree`
  /// the agent's `bash` tool calls land in.
  func runVerifyCommand(
    command: String,
    hostWorkingDirectory: URL,
    timeoutSeconds: TimeInterval,
    launchPlan: AgentExecutionLaunchPlan,
    requiresHostXcode: Bool = false,
    hostXcodeBuildTestEnabled: Bool = false,
    hostXcodeMirrorRoot: URL? = nil,
    hostRunner: ProcessRunner.InvocationRunner? = nil
  ) async throws -> ProcessResult {
    if hostXcodeBuildTestEnabled && requiresHostXcode {
      do {
        let service = try makeHostXcodeService(
          hostRepoURL: hostWorkingDirectory,
          launchPlan: launchPlan,
          mirrorRootURL: hostXcodeMirrorRoot,
          runner: hostRunner
        )
        let mirrorRoot = hostXcodeMirrorRoot ?? HostXcodeService.defaultMirrorRootURL()
        let workingDirectoryDescription: String
        switch launchPlan.effectiveRoute {
        case .host:
          workingDirectoryDescription = hostWorkingDirectory.path
        case .sharedVM:
          workingDirectoryDescription =
            HostXcodeService.mirrorDirectory(
              forRepoURL: hostWorkingDirectory,
              rootURL: mirrorRoot
            ).path
        }
        log(
          "Verify: running through host Xcode build/test bridge at \(workingDirectoryDescription) (timeout \(Int(timeoutSeconds * 1000))ms).",
          level: .info
        )
        return try await service.runVerifyCommand(command, timeout: timeoutSeconds)
      } catch let error as HostXcodeError {
        return ProcessResult(exitCode: 72, stdout: "", stderr: error.localizedDescription)
      } catch {
        return ProcessResult(
          exitCode: 72,
          stdout: "",
          stderr: "Host Xcode verify failed: \(error.localizedDescription)"
        )
      }
    }
    if case .sharedVM(let route) = launchPlan.effectiveRoute,
      let machine = SharedCompassVM.shared.virtualMachine
    {
      let client = Self.makeVsockClient(on: machine)
      let guestWorkingDirectory = URL(fileURLWithPath: route.guestWorkspacePath)
      log(
        "Verify: running inside Shared VM at \(route.guestWorkspacePath) (timeout \(Int(timeoutSeconds * 1000))ms).",
        level: .info
      )
      return try await client.run(
        command: command,
        workingDirectory: guestWorkingDirectory,
        timeout: timeoutSeconds
      )
    }
    if case .sharedVM(let route) = launchPlan.effectiveRoute {
      let message =
        "Shared VM route selected for Verify at \(route.guestWorkspacePath), but no live virtual machine was connected. Refusing to run the guest-local command on the host."
      log(message, level: .error)
      return ProcessResult(exitCode: 73, stdout: "", stderr: message)
    }
    return try await ProcessRunner.runShell(
      command,
      workingDirectory: hostWorkingDirectory,
      timeout: timeoutSeconds,
      launchPlan: launchPlan,
      runner: hostRunner
    )
  }

  /// Ensures the persistent guest workspace for `hostRepoURL` exists and
  /// has the host repo's contents. No-op if the guest workspace already
  /// exists (the agent's prior state is preserved). Callers can force
  /// a re-sync by passing `forceRefresh: true`.
  ///
  /// Called from `runAgent` for `.sharedVM` routes so the agent's first
  /// `read_file` always finds something. For session-level operations
  /// (e.g. an explicit user-driven refresh in the future) this can be
  /// invoked directly without going through runAgent.
  @discardableResult
  func ensurePersistentGuestWorkspace(
    forHostRepo hostRepoURL: URL,
    forceRefresh: Bool = false
  ) async throws -> SharedCompassVMRepoWorkspaceSync.Outcome? {
    guard let machine = SharedCompassVM.shared.virtualMachine else {
      return nil
    }
    let client = Self.makeVsockClient(on: machine)
    if ProcessInfo.processInfo.environment["COMPASS_DISABLE_GUEST_GIT_SYNC"] != "1" {
      do {
        let result = try await SharedCompassVMGitWorkspaceSync.ensurePopulated(
          hostRepoURL: hostRepoURL,
          client: client
        )
        switch result.outcome {
        case .cloned:
          log(
            "Guest git workspace cloned at \(result.guestPath) from Compass exchange \(result.context.remoteURL).",
            level: .info)
          return .freshlyPopulated
        case .alreadyCurrent:
          log(
            "Guest git workspace already matches host branch \(result.context.branchName) at \(result.guestPath).",
            level: .info)
          return .reused
        case .resetToHost:
          log(
            "Guest git workspace reset to host branch \(result.context.branchName) at \(result.guestPath).",
            level: .info)
          return .refreshedDueToHostDrift
        case .preservedLocalCommits:
          log(
            "Guest git workspace at \(result.guestPath) is ahead of host branch \(result.context.branchName); preserving local agent commits.",
            level: .info)
          return .reused
        case .preservedUncommittedChanges:
          log(
            "Guest git workspace at \(result.guestPath) has uncommitted agent changes; preserving them for the retry attempt.",
            level: .warning)
          return .reused
        case .rebasedLocalCommits:
          log(
            "Guest git workspace at \(result.guestPath) rebased local agent commits onto host branch \(result.context.branchName).",
            level: .info)
          return .refreshedDueToHostDrift
        }
      } catch let error as SharedCompassVMGitExchange.ExchangeError {
        log("Guest git workspace setup blocked: \(error.description)", level: .error)
        throw error
      } catch let error as SharedCompassVMGitWorkspaceSync.SyncError {
        log("Guest git workspace setup failed: \(error.description)", level: .error)
        throw error
      }
    }

    let syncFileCount: Int
    do {
      syncFileCount = try SharedCompassVMWorktreeSync.syncableRelativePaths(in: hostRepoURL).count
    } catch {
      syncFileCount = 0
    }
    if syncFileCount > 0 {
      log(
        "Guest workspace sync: \(syncFileCount) host file(s) eligible for Shared VM copy.",
        level: .info)
    }
    let result: (guestPath: String, outcome: SharedCompassVMRepoWorkspaceSync.Outcome)
    do {
      result = try await SharedCompassVMRepoWorkspaceSync.ensurePopulated(
        hostRepoURL: hostRepoURL,
        client: client,
        forceRefresh: forceRefresh
      )
    } catch let error as SharedCompassVMRepoWorkspaceSync.SyncError {
      // Log the *readable* description before rethrowing — without
      // this the activity batch only shows
      // "The operation couldn't be completed.
      //  (Compass.SharedCompassVMRepoWorkspaceSync.SyncError error N.)"
      // because the failure ascends through callers that surface
      // `localizedDescription` from the raw error chain.
      log("Guest workspace sync failed: \(error.description)", level: .error)
      throw error
    }
    switch result.outcome {
    case .reused:
      log(
        "Guest workspace at \(result.guestPath) already populated — preserving prior agent state.",
        level: .info)
    case .freshlyPopulated:
      log(
        "Guest workspace at \(result.guestPath) populated for the first time from \(hostRepoURL.path).",
        level: .info)
    case .refreshed:
      log(
        "Guest workspace at \(result.guestPath) force-refreshed from \(hostRepoURL.path).",
        level: .info)
    case .refreshedDueToHostDrift:
      log(
        "Guest workspace at \(result.guestPath) re-populated: host repo changed since last sync (out-of-band edits while Compass was closed).",
        level: .info)
    }
    return result.outcome
  }

  /// Routes through `SharedCompassVM.makeVsockClient` — kept as a thin
  /// shim so AppModel sites can stay terse. The transport details
  /// (vsock framing, port, factory closure) all live behind that
  /// method now; AppModel doesn't import the transport types.
  private static func makeVsockClient(on machine: VZVirtualMachine) -> AgentVsockClient {
    SharedCompassVM.makeVsockClient(on: machine)
  }

  /// Pulls the guest workspace's current state (filtered against the
  /// well-known build-output dirs) back onto the host's main repo.
  /// Called after Verify passes under the `.sharedVM` route so the
  /// follow-up host-side commit captures whatever the in-guest agent
  /// produced.
  ///
  /// Pull failures are logged but not thrown: the subsequent
  /// `git status` will surface "nothing to commit" or partial state
  /// instead of dropping the entire iteration on a transient
  /// transport hiccup.
  func pullDevelopChangesIfNeeded(
    mainRepoURL: URL,
    plan: AgentExecutionLaunchPlan
  ) async {
    // The guest path is resolved inside pullAndRecord via the
    // catalog, so we only need the route to decide whether this is a
    // .sharedVM run at all.
    guard case .sharedVM = plan.effectiveRoute,
      let machine = SharedCompassVM.shared.virtualMachine
    else {
      return
    }
    let client = Self.makeVsockClient(on: machine)
    do {
      // Routes through SharedCompassVMRepoWorkspaceSync so the pull's
      // deletion step is scoped to the last-pushed fileset (preserving
      // user-added files between sessions) and the catalog gets
      // re-stamped with the post-pull fingerprint for the next
      // session's drift check.
      try await SharedCompassVMRepoWorkspaceSync.pullAndRecord(
        hostRepoURL: mainRepoURL,
        client: client
      )
    } catch {
      log(
        "Develop: vsock pull from guest failed — host commit may see stale state: \(error.localizedDescription)",
        level: .warning
      )
    }
  }

  /// Pushes the committed guest HEAD to the Compass exchange repo and
  /// fast-forwards the host checkout from that staging ref. Returns a
  /// human-readable issue on failure so the Develop loop can stop
  /// cleanly instead of silently losing agent commits.
  func promoteDevelopChangesIfNeeded(
    mainRepoURL: URL,
    plan: AgentExecutionLaunchPlan,
    sessionNumber: Int,
    verifyPassed: Bool
  ) async -> String? {
    guard case .sharedVM(let route) = plan.effectiveRoute,
      let repoID = route.catalogID,
      let machine = SharedCompassVM.shared.virtualMachine
    else {
      return nil
    }
    guard let context = SharedCompassVMGitStateStore.context(forHostRepoURL: mainRepoURL) else {
      return nil
    }

    let stagingRef: String
    do {
      stagingRef = try SharedCompassVMGitExchange.stagingRef(
        repoID: repoID,
        sessionNumber: sessionNumber,
        branchName: context.branchName
      )
    } catch {
      return "Guest git promotion failed: \(error.localizedDescription)"
    }

    let client = Self.makeVsockClient(on: machine)
    let guestWorkingDirectory = URL(fileURLWithPath: route.guestWorkspacePath)
    let status: ProcessResult
    do {
      status = try await client.run(
        command: "git status --porcelain",
        workingDirectory: guestWorkingDirectory,
        timeout: 30
      )
    } catch {
      return "Guest git promotion failed at git status: \(error.localizedDescription)"
    }
    if status.exitCode != 0 {
      return
        "Guest git promotion failed at git status (exit \(status.exitCode)): \(tail(status.stderr + status.stdout, max: 2000))"
    }
    let dirty = status.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    if !dirty.isEmpty {
      return """
        Guest git promotion refused because the guest working tree is not clean:
        ```
        \(dirty)
        ```
        """
    }

    let quotedStaging = SharedCompassVMGuestBridge.posixQuote(stagingRef)
    let push = try? await client.run(
      command: "git push origin HEAD:\(quotedStaging)",
      workingDirectory: guestWorkingDirectory,
      timeout: 180
    )
    guard let push else {
      return "Guest git promotion failed: could not run git push in guest."
    }
    if push.exitCode != 0 {
      return
        "Guest git promotion failed at git push (exit \(push.exitCode)): \(tail(push.stderr + push.stdout, max: 4000))"
    }

    do {
      try await SharedCompassVMGitExchange.promote(
        stagingRef: stagingRef,
        context: context,
        hostRepoURL: mainRepoURL
      )
    } catch {
      return
        "Guest git promotion failed while fast-forwarding host branch: \(error.localizedDescription)"
    }

    let suffix = verifyPassed ? "." : " despite failed Verify."
    log(
      "Guest git promotion: pushed \(stagingRef) and fast-forwarded host branch \(context.branchName)\(suffix)",
      level: verifyPassed ? .success : .warning
    )
    return nil
  }
}
