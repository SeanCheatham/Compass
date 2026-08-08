import Foundation
import Virtualization

@MainActor
extension SharedCompassVM {
  /// Boots (or re-boots) the guest from the currently-installed bundle.
  /// Caller is responsible for first calling `provisionIfNeeded` if the
  /// bundle is empty. Idempotent if the VM is already running.
  ///
  /// Concurrent calls share a single in-flight start so two callers cannot
  /// race to construct two VZVirtualMachine instances.
  public func start() async throws {
    if fallbackUnavailableReason != nil { return }
    if let virtualMachine, virtualMachine.state == .running {
      // Guest is already up. If readiness was demoted to `.stopped` (or a
      // prior poll failed) without tearing the VM down, resume the post-boot
      // follow-up instead of returning while the UI still says Stopped.
      resumePostBootReadinessIfStalled()
      return
    }
    if let existing = startInFlight {
      try await existing.value
      resumePostBootReadinessIfStalled()
      return
    }

    let task = Task { [weak self] () -> Void in
      guard let self else { return }
      try await self.performStart()
    }
    startInFlight = task
    defer { startInFlight = nil }
    do {
      try await task.value
    } catch {
      transition(to: .error(detail: SharedCompassVMAvailabilityCheck.describeVerbose(error: error)))
      throw error
    }
  }

  private func performStart() async throws {
    if let virtualMachine, virtualMachine.state == .running {
      resumePostBootReadinessIfStalled()
      return
    }

    // Generate (or load) a stable MAC for the guest NIC so host-side
    // IP discovery can find this guest across host reboots.
    let macAddress = try? bundle.ensureGuestMACAddress(fileManager: dependencies.fileManager)

    // Compose configuration from on-disk artifacts.
    let inputs = SharedCompassVMConfiguration.Inputs.standard(
      bundle: bundle,
      guestMACAddress: macAddress
    )
    let configuration = try SharedCompassVMConfiguration.makeConfiguration(
      for: inputs,
      fileManager: dependencies.fileManager
    )

    // Attach a host-owned Pipe to the virtio console so first-boot guest
    // scripts can publish `COMPASS_GUEST_IP=<addr>` lines back to us.
    // The hook stays live for the full VM lifetime; the read task drops
    // anything that doesn't match the known prefix.
    attachConsolePipe(to: configuration)

    do {
      try configuration.validate()
    } catch {
      tearDownConsolePipe()
      throw error
    }

    let machine = VZVirtualMachine(configuration: configuration)
    self.virtualMachine = machine

    do {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        machine.start { result in
          switch result {
          case .success:
            continuation.resume(returning: ())
          case .failure(let error):
            continuation.resume(throwing: error)
          }
        }
      }
    } catch {
      self.virtualMachine = nil
      tearDownConsolePipe()
      throw error
    }

    // Headless first-boot follow-up: if we just booted a freshly-planted
    // guest, the LaunchDaemon will spend ~30-60s creating the user,
    // authorising the SSH key, and enabling Remote Login. Kick off a
    // background poller that finalises readiness once SSH responds,
    // so the user never needs to click "Mark setup complete".
    //
    // For subsequent boots (state is already .ready on disk), `warmup()`
    // has reported `.stopped`. Move to `.starting` and probe SSH until
    // the guest's sshd answers, then flip the in-memory state to `.ready`
    // — without touching the persisted state machine.
    beginPostBootFollowUpAfterSuccessfulStart()
  }

  /// Resumes post-boot readiness when the VZ guest is already running but
  /// in-memory readiness was left idle (`.stopped`) or failed. Does not
  /// re-kick first-boot / CLT follow-ups that are already underway.
  private func resumePostBootReadinessIfStalled() {
    switch readiness {
    case .ready:
      return
    case .starting where postBootReadinessTask != nil:
      return
    case .guestPrepping, .provisioningDevTools, .downloadingIPSW, .installing:
      return
    case .stopped, .error, .unavailable, .notProvisioned, .starting:
      beginPostBootFollowUpAfterSuccessfulStart()
    }
  }

  /// Schedules the post-boot readiness follow-up for the persisted provision
  /// step immediately after a successful VZ start (or when resuming a stalled
  /// already-running guest).
  private func beginPostBootFollowUpAfterSuccessfulStart() {
    let postStartStep = (try? bundle.loadState(fileManager: dependencies.fileManager))?
      .provisionStep
    switch postStartStep {
    case .guestPrepping:
      Task { [weak self] in
        await self?.pollUntilHeadlessGuestReady()
      }
    case .provisioningDevTools:
      // Host crashed (or VM was stopped) mid-CLT-install. Resume
      // where we left off — the provisioner's probe short-circuits
      // when CLT happens to have finished out-of-band, and otherwise
      // re-issues the plant + kickoff (which softwareupdate handles
      // idempotently).
      Task { [weak self] in
        await self?.resumeDevToolsProvisioningAfterBoot()
      }
    case .ready:
      scheduleSSHReadinessPollAfterBoot()
    default:
      break
    }
  }

  /// Moves readiness to `.starting` and runs the SSH/agent poll once.
  private func scheduleSSHReadinessPollAfterBoot() {
    if postBootReadinessTask != nil { return }
    transition(to: .starting)
    postBootReadinessTask = Task { [weak self] in
      await self?.pollSSHAfterBootAndMarkReady()
      await MainActor.run {
        self?.postBootReadinessTask = nil
      }
    }
  }

  /// Re-enters the dev-tools install path after a fresh boot of a bundle
  /// that was persisted at `.provisioningDevTools`. Mirrors the SSH-probe
  /// leg of `markSetupComplete` (so the live destination is re-resolved),
  /// then hands off to `runDevToolsProvisioner`.
  private func resumeDevToolsProvisioningAfterBoot() async {
    let state =
      (try? bundle.loadState(fileManager: dependencies.fileManager))
      ?? SharedCompassVMBundle.State()
    let options = SharedCompassVMGuestBridge.ConnectionOptions(
      identityFile: bundle.privateKeyURL.path,
      knownHostsFile: bundle.knownHostsURL.path,
      connectTimeoutSeconds: 5
    )
    guard
      let destination = await resolveGuestSSHDestination(state: state, options: options)
    else {
      transition(
        to: .error(
          detail:
            "Resuming dev-tools install: could not reach the guest over SSH (cached IP \(state.lastKnownGoodIP ?? "none") did not answer and rediscovery failed).\(Self.staleVMProcessNote()) Stop the VM and retry, or reset and re-provision."
        ))
      return
    }
    lastResolvedSSHDestination = destination
    transition(to: .provisioningDevTools(fractionCompleted: 0))
    await runDevToolsProvisioner(destination: destination)
  }

  /// Resolves a reachable `user@ip` SSH destination for the guest.
  ///
  /// The guest's DHCP lease is not guaranteed to survive reboots, so a
  /// persisted `lastKnownGoodIP` can go stale between sessions. Probes
  /// the cached address first; when it stops answering, re-runs
  /// MAC-keyed discovery (dhcpd_leases/arp via the pinned guest MAC),
  /// persists the fresh address, and TOFU-scans its host key before the
  /// strict probe. Returns nil when the overall budget expires.
  private func resolveGuestSSHDestination(
    state: SharedCompassVMBundle.State,
    options: SharedCompassVMGuestBridge.ConnectionOptions,
    probeTimeout: TimeInterval = 5,
    overallBudget: TimeInterval = 300
  ) async -> String? {
    let deadline = Date().addingTimeInterval(overallBudget)
    var candidateIP = state.lastKnownGoodIP
    var attemptIntervalNanoseconds: UInt64 = 2_000_000_000
    var attemptedRediscovery = false
    while Date() < deadline {
      if let ip = candidateIP {
        let destination = "\(state.guestUserName)@\(ip)"
        let probeOK = await SharedCompassVMGuestBridge.probeSSHAvailable(
          destination: destination,
          options: options,
          timeout: probeTimeout
        )
        if probeOK { return destination }
      }
      if !attemptedRediscovery, let mac = state.guestMACAddress {
        attemptedRediscovery = true
        if let discovered = await SharedCompassVMGuestIPDiscovery.waitForGuestIP(
          macAddress: mac,
          timeout: 60,
          pollInterval: 2
        ) {
          candidateIP = discovered.ip
          _ = try? bundle.mutateState(fileManager: dependencies.fileManager) {
            $0.lastKnownGoodIP = discovered.ip
          }
          // The fresh address needs its host key in known_hosts before
          // the strict probe will talk to it.
          _ = await SharedCompassVMGuestBridge.populateKnownHosts(
            host: discovered.ip,
            knownHostsFile: bundle.knownHostsURL.path,
            timeout: 5
          )
          continue
        }
      }
      try? await Task.sleep(nanoseconds: attemptIntervalNanoseconds)
      attemptIntervalNanoseconds = min(attemptIntervalNanoseconds * 2, 10_000_000_000)
    }
    return nil
  }

  /// Lightweight SSH probe used on subsequent boots when the bundle is
  /// already past first-boot setup. Unlike `pollUntilHeadlessGuestReady`,
  /// this does not mutate persisted state — it only flips the in-memory
  /// readiness to `.ready` once the guest's sshd answers, so the UI
  /// reflects "actually reachable" rather than "previously was reachable".
  private func pollSSHAfterBootAndMarkReady() async {
    if Task.isCancelled { return }
    let state =
      (try? bundle.loadState(fileManager: dependencies.fileManager))
      ?? SharedCompassVMBundle.State()
    let options = SharedCompassVMGuestBridge.ConnectionOptions(
      identityFile: bundle.privateKeyURL.path,
      knownHostsFile: bundle.knownHostsURL.path,
      connectTimeoutSeconds: 5
    )
    guard
      let destination = await resolveGuestSSHDestination(state: state, options: options)
    else {
      if Task.isCancelled { return }
      transition(
        to: .error(
          detail:
            "Guest did not become reachable over SSH after boot (cached IP \(state.lastKnownGoodIP ?? "none") did not answer and rediscovery failed).\(Self.staleVMProcessNote()) Stop the VM and retry."
        ))
      return
    }
    if Task.isCancelled { return }
    lastResolvedSSHDestination = destination
    await repairAutoLogin(destination: destination)
    if Task.isCancelled { return }
    startDiagnosticLogTail(destination: destination)
    guard await ensureGuestAgentReachableAfterBoot(destination: destination) else { return }
    if Task.isCancelled { return }
    transition(to: .ready(sshDestination: destination))
    Task { [weak self] in
      await self?.ensureDefaultToolchainsIfNeeded()
    }
  }

  /// Background driver that repeatedly invokes `markSetupComplete()` until
  /// the readiness probe lands on `.ready`, or the overall deadline
  /// expires. Used as the auto-finalisation step after a headless
  /// first-boot plant, where Compass owns the entire boot sequence and
  /// there is nothing for the user to click.
  private func pollUntilHeadlessGuestReady() async {
    let deadline = Date().addingTimeInterval(300)  // 5 minutes
    var attemptIntervalNanoseconds: UInt64 = 5_000_000_000
    while Date() < deadline {
      await markSetupComplete()
      // SSH-probe loop exits as soon as `markSetupComplete` has either
      // landed at .ready or advanced past SSH onto the dev-tools
      // install — beyond that point the provisioner owns the
      // readiness signal and we must not re-invoke setup or we'd
      // race ourselves into multiple concurrent installs.
      if case .ready = readiness { return }
      if case .provisioningDevTools = readiness { return }
      if case .error = readiness { return }
      try? await Task.sleep(nanoseconds: attemptIntervalNanoseconds)
      // Exponential backoff capped at 20s so we don't hammer ssh
      // during the long tail of slow first boots.
      attemptIntervalNanoseconds = min(attemptIntervalNanoseconds * 2, 20_000_000_000)
    }
  }

  /// Subsequent boots should not sit in the launch gate for the full vsock
  /// timeout when SSH is already alive. Probe both the live vsock agent and
  /// the on-disk helper, repair the planted guest agent over SSH if needed,
  /// then wait a short bounded window for vsock.
  private func ensureGuestAgentReachableAfterBoot(destination: String) async -> Bool {
    guard let machine = virtualMachine else {
      transition(to: .error(detail: "Shared VM is not running; cannot reach guest agent."))
      return false
    }

    let options = SharedCompassVMGuestBridge.ConnectionOptions(
      identityFile: bundle.privateKeyURL.path,
      knownHostsFile: bundle.knownHostsURL.path,
      connectTimeoutSeconds: 5
    )
    let liveAgentReachable = await probeGuestAgentOnce(on: machine, timeout: 3)
    appendDiagnostic(
      "Guest agent vsock probe: \(liveAgentReachable ? "ok" : "failed")",
      source: "host"
    )
    // The old agent still answers vsock probes after a Compass upgrade,
    // so reachability alone is not enough — compare the planted binary
    // against the bundled one and replant on mismatch.
    let agentCurrent = await SharedCompassVMGuestAgentInstall.installedAgentMatchesHost(
      destination: destination,
      options: options,
      fileManager: dependencies.fileManager
    )
    appendDiagnostic(
      "Guest agent binary matches host: \(agentCurrent ? "yes" : "no")",
      source: "host"
    )
    if liveAgentReachable && agentCurrent {
      if let hostSHA = try? SharedCompassVMGuestAgentInstall.hostBinarySHA256(
        fileManager: dependencies.fileManager
      ) {
        verifiedGuestAgentHostSHA = hostSHA
      }
      return true
    }

    do {
      appendDiagnostic("Repairing guest agent over SSH…", source: "host")
      try await SharedCompassVMGuestAgentInstall.repairOverSSH(
        destination: destination,
        options: options,
        fileManager: dependencies.fileManager
      )
    } catch {
      transition(
        to: .error(
          detail:
            "Guest agent repair failed after SSH became reachable: \(SharedCompassVMAvailabilityCheck.describeVerbose(error: error))"
        ))
      return false
    }

    guard
      await SharedCompassVMVsock.waitUntilReachable(
        on: machine,
        timeout: 45,
        probeTimeout: 5
      )
    else {
      transition(
        to: .error(
          detail:
            "Guest agent did not become reachable over vsock after SSH repair. Restart the Shared VM to retry."
        ))
      return false
    }
    appendDiagnostic("Guest agent reachable over vsock after repair.", source: "host")
    if let hostSHA = try? SharedCompassVMGuestAgentInstall.hostBinarySHA256(
      fileManager: dependencies.fileManager
    ) {
      verifiedGuestAgentHostSHA = hostSHA
    }
    return true
  }

  /// When the Shared VM is already `.ready`, boot-time agent repair never
  /// runs again. Call this before bash so a rebuilt Compass host still
  /// replants a mismatched guest agent (e.g. the EBADF stdin fix).
  public func ensureGuestAgentMatchesHost(destination: String) async throws {
    let hostSHA: String
    do {
      hostSHA = try SharedCompassVMGuestAgentInstall.hostBinarySHA256(
        fileManager: dependencies.fileManager
      )
    } catch {
      // No bundled agent beside this host binary — nothing to compare.
      return
    }
    if verifiedGuestAgentHostSHA == hostSHA { return }

    let options = SharedCompassVMGuestBridge.ConnectionOptions(
      identityFile: bundle.privateKeyURL.path,
      knownHostsFile: bundle.knownHostsURL.path,
      connectTimeoutSeconds: 5
    )
    let matches = await SharedCompassVMGuestAgentInstall.installedAgentMatchesHost(
      destination: destination,
      options: options,
      fileManager: dependencies.fileManager
    )
    if matches {
      verifiedGuestAgentHostSHA = hostSHA
      return
    }

    appendDiagnostic(
      "Guest agent binary stale while VM ready; repairing over SSH…",
      source: "host"
    )
    try await SharedCompassVMGuestAgentInstall.repairOverSSH(
      destination: destination,
      options: options,
      fileManager: dependencies.fileManager
    )
    guard let machine = virtualMachine else {
      throw SharedCompassVMGuestAgentInstall.InstallError.installFailed(
        exitCode: 1,
        stderr: "Shared VM is not running after guest agent repair."
      )
    }
    guard
      await SharedCompassVMVsock.waitUntilReachable(
        on: machine,
        timeout: 45,
        probeTimeout: 5
      )
    else {
      throw SharedCompassVMGuestAgentInstall.InstallError.installFailed(
        exitCode: 1,
        stderr: "Guest agent did not become reachable over vsock after repair."
      )
    }
    verifiedGuestAgentHostSHA = hostSHA
    appendDiagnostic("Guest agent repaired while VM was ready.", source: "host")
  }

  private func probeGuestAgentOnce(on machine: VZVirtualMachine, timeout: TimeInterval) async
    -> Bool
  {
    let client = AgentVsockClient(
      transportFactory: {
        let connection = try await SharedCompassVMVsock.connect(on: machine)
        return VZVirtioSocketTransport(connection: connection)
      },
      requestTimeout: timeout
    )
    do {
      let result = try await client.run(
        command: "true",
        workingDirectory: URL(fileURLWithPath: SharedCompassVMGuestLayout.current.homeDirectory),
        timeout: timeout
      )
      if result.exitCode != 0 {
        appendDiagnostic(
          "Guest agent probe exit \(result.exitCode): \(result.stderr)",
          source: "host"
        )
      }
      return result.exitCode == 0
    } catch {
      appendDiagnostic("Guest agent probe error: \(error.localizedDescription)", source: "host")
      return false
    }
  }

  /// Diagnostic suffix for SSH-resolution failures: a Compass instance
  /// that was force-quit leaves its `Virtualization.VirtualMachine` XPC
  /// process alive, and the orphaned guest keeps its DHCP lease — which
  /// makes MAC-keyed IP discovery resolve to the orphan instead of the
  /// real guest. Count live VZ VM processes so the error text can name
  /// that failure mode explicitly.
  static func staleVMProcessNote() -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    process.arguments = ["-f", "com.apple.Virtualization.VirtualMachine"]
    let stdout = Pipe()
    process.standardOutput = stdout
    process.standardError = Pipe()
    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      return ""
    }
    guard
      let data = try? stdout.fileHandleForReading.readToEnd(),
      let text = String(data: data, encoding: .utf8)
    else { return "" }
    let count =
      text
      .split(whereSeparator: { $0.isNewline || $0.isWhitespace })
      .compactMap { pid_t($0) }
      .count
    guard count > 0 else { return "" }
    return
      " \(count) Virtualization VM process(es) are alive on this host — if Compass was force-quit earlier, an orphaned guest may be holding this VM's IP lease; kill stale com.apple.Virtualization.VirtualMachine processes (or run scripts/reset-compass-state.sh) and retry."
  }

  /// Pauses the live VM. No-op if no VM is running.
  public func pause() {
    guard let machine = virtualMachine, machine.state == .running else { return }
    machine.pause { _ in
      // Result is intentionally ignored — failure to pause is logged at the
      // call site but does not block the host going to sleep.
    }
  }

  /// Resumes the paused VM. No-op if no VM is paused.
  public func resume() {
    guard let machine = virtualMachine, machine.state == .paused else { return }
    machine.resume { _ in
      // Ditto pause — wake propagation must not block.
    }
  }

  /// Stops the VM, preferring a graceful guest-driven shutdown over the
  /// forced VZ halt. `requestStop()` sends an ACPI/shutdown signal so macOS
  /// in the guest can flush APFS, terminate services, and halt cleanly;
  /// without it every quit pulls the power cord and the guest accumulates
  /// dirty-bit warnings on the next boot. If the guest does not power down
  /// within a bounded window, we fall back to the forced halt so the host
  /// app still terminates within the AppDelegate's 6s budget.
  public func stop() async {
    // Capture the live SSH destination (if any) before we tear the VM
    // down so we can ask any backgrounded SSH control master to exit.
    // Without this teardown, `ControlPersist` leaves the master alive
    // for minutes after the VM is gone, leaking a ssh process and
    // re-establishing dead connections on the next agent call.
    let liveSSHDestination: String?
    if case .ready(let destination) = readiness {
      liveSSHDestination = destination
    } else {
      liveSSHDestination = nil
    }

    postBootReadinessTask?.cancel()
    postBootReadinessTask = nil
    stopDiagnosticLogTail()

    defer {
      if let destination = liveSSHDestination {
        let options = SharedCompassVMGuestBridge.ConnectionOptions(
          identityFile: bundle.privateKeyURL.path,
          knownHostsFile: bundle.knownHostsURL.path
        )
        Task.detached {
          await SharedCompassVMGuestBridge.closeControlMaster(
            destination: destination,
            options: options
          )
        }
      }
    }

    guard let machine = virtualMachine else {
      // No VM is running. If readiness is still parked in a live state
      // (a `warmup()` placeholder no `start()` ever followed, or a
      // previous stop), fold it to `.stopped` so the UI doesn't claim
      // first-boot prep is in progress while nothing is happening.
      foldLiveReadinessToStopped()
      return
    }
    if machine.state == .stopped {
      virtualMachine = nil
      tearDownConsolePipe()
      foldLiveReadinessToStopped()
      return
    }

    // Phase 1: graceful shutdown. Only valid when the VM is actually
    // running — paused / stopping / starting states reject the request
    // and we'll fall through to the forced halt.
    if machine.state == .running {
      do {
        try machine.requestStop()
      } catch {
        // requestStop throws if VZ refuses the request. Not fatal —
        // we still try the forced halt below.
      }
      // Poll for up to ~4s. A macOS guest typically halts in 2-3s; the
      // 4s ceiling keeps total stop time within the AppDelegate's 6s
      // budget (4s graceful + ≤1s forced fallback + overhead).
      let deadline = Date().addingTimeInterval(4)
      while Date() < deadline, machine.state != .stopped {
        try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
      }
    }

    // Phase 2: forced halt. Reached when the graceful path was skipped
    // (wrong state), rejected by VZ, or the guest didn't power down in
    // time. Equivalent to pulling the power cord — use only as a last
    // resort.
    if machine.state != .stopped {
      do {
        try await withCheckedThrowingContinuation {
          (continuation: CheckedContinuation<Void, Error>) in
          machine.stop { error in
            if let error {
              continuation.resume(throwing: error)
            } else {
              continuation.resume(returning: ())
            }
          }
        }
      } catch {
        // Stop failures are non-fatal; the VM may already be halted.
      }
    }

    virtualMachine = nil
    tearDownConsolePipe()
    foldLiveReadinessToStopped()
  }

  /// Folds readiness to `.stopped` when no VM is running but the state
  /// machine is still parked in a live state. `.error`, `.unavailable`,
  /// and `.notProvisioned` are left untouched — the first two already
  /// describe a not-running VM (and carry a diagnostic the user still
  /// needs to see), and the last means there is nothing to stop.
  private func foldLiveReadinessToStopped() {
    switch readiness {
    case .ready, .guestPrepping, .provisioningDevTools, .downloadingIPSW, .installing,
      .starting:
      transition(to: .stopped)
    case .stopped, .notProvisioned, .unavailable, .error:
      break
    }
  }

  /// Marks the user-driven first-boot Setup Assistant as complete.
  /// Transitions readiness to `.guestPrepping` and then to
  /// `.provisioningDevTools` once the SSH probe succeeds, kicking off
  /// the headless CLT install before finally flipping to `.ready`. The
  /// Sandbox view invokes this when the user taps "Mark setup complete";
  /// the headless first-boot driver calls it repeatedly until readiness
  /// leaves `.guestPrepping`.
  public func markSetupComplete() async {
    // Clear any prior failure message so the UI shows a fresh attempt.
    setupFailureMessage = nil
    transition(to: .guestPrepping)
    _ = try? bundle.mutateState(fileManager: dependencies.fileManager) {
      $0.provisionStep = .guestPrepping
    }

    var state =
      (try? bundle.loadState(fileManager: dependencies.fileManager))
      ?? SharedCompassVMBundle.State()

    // Resolve guest IP via dhcpd_leases/arp using the pinned MAC if
    // we don't already have one cached. Without this, the readiness
    // pipeline would stall here permanently.
    if state.lastKnownGoodIP == nil, let mac = state.guestMACAddress {
      if let discovered = await SharedCompassVMGuestIPDiscovery.waitForGuestIP(
        macAddress: mac,
        timeout: 60,
        pollInterval: 2
      ) {
        state.lastKnownGoodIP = discovered.ip
        _ = try? bundle.mutateState(fileManager: dependencies.fileManager) {
          $0.lastKnownGoodIP = discovered.ip
        }
      }
    }

    guard let ip = state.lastKnownGoodIP else {
      setupFailureMessage =
        "Could not discover the guest IP. Make sure the VM has finished booting and that the guest has a DHCP lease, then try again."
      return
    }
    let destination = "\(state.guestUserName)@\(ip)"
    let options = SharedCompassVMGuestBridge.ConnectionOptions(
      identityFile: bundle.privateKeyURL.path,
      knownHostsFile: bundle.knownHostsURL.path,
      connectTimeoutSeconds: 5
    )

    // Bootstrap known_hosts via ssh-keyscan before the strict probe.
    // The probe runs with StrictHostKeyChecking=yes and refuses to
    // talk to a host whose key isn't in known_hosts; on a fresh
    // provision that's always the case and the probe would loop
    // forever even with sshd up and authorised. ssh-keyscan TOFU-
    // trusts the freshly-generated host key. Safe because the guest
    // is on a host-local NAT bridge.
    _ = await SharedCompassVMGuestBridge.populateKnownHosts(
      host: ip,
      knownHostsFile: bundle.knownHostsURL.path,
      timeout: 5
    )

    let probeOK = await SharedCompassVMGuestBridge.probeSSHAvailable(
      destination: destination,
      options: options,
      timeout: 5
    )
    guard probeOK else {
      setupFailureMessage =
        "SSH probe to \(destination) failed. Confirm the bootstrap script ran successfully inside the guest (sshd enabled, key authorised).\(Self.staleVMProcessNote())"
      return
    }
    lastResolvedSSHDestination = destination

    // SSH is up — nudge graphical auto-login before the (long) CLT install
    // so the headed Desktop is usable while tooling provisions.
    await repairAutoLogin(destination: destination)
    startDiagnosticLogTail(destination: destination)

    // SSH is up — promote to .provisioningDevTools and kick off the
    // in-guest CLT install. We persist this step too so a host crash
    // mid-install resumes here on the next launch rather than thinking
    // the bundle is ready when CLT was never finished.
    _ = try? bundle.mutateState(fileManager: dependencies.fileManager) {
      $0.provisionStep = .provisioningDevTools
    }
    transition(to: .provisioningDevTools(fractionCompleted: 0))

    await runDevToolsProvisioner(destination: destination)
  }

  /// Drives default toolchain provisioning against the live VM using a
  /// vsock-backed bash runner: CLT, Homebrew, ripgrep, OpenSSL+pkgconf, then Rust.
  private func runDevToolsProvisioner(destination: String) async {
    guard let machine = virtualMachine else {
      transition(to: .error(detail: "Shared VM is not running; cannot install developer tools."))
      return
    }
    guard await SharedCompassVMVsock.waitUntilReachable(on: machine) else {
      transition(
        to: .error(
          detail:
            "Guest agent did not become reachable over vsock within 5 minutes. The VM may still be booting — quit and reopen Compass to retry."
        ))
      return
    }
    let client = Self.makeVsockClient(on: machine)
    let host = self
    let toolchainManager = makeToolchainService()
    do {
      _ = try await SharedCompassVMDevToolsProvisioner.provision(
        runner: client,
        progress: { fraction in
          await MainActor.run {
            host.transition(to: .provisioningDevTools(fractionCompleted: fraction * 0.6))
          }
        }
      )
    } catch {
      transition(to: .error(detail: "Developer-tools install failed: \(error)"))
      return
    }

    let homebrewDefinition = SharedVMToolchainCatalog.definition(for: .homebrew)
    do {
      _ = try await SharedCompassVMToolchainProvisioner.provision(
        definition: homebrewDefinition,
        runner: client,
        progress: { fraction in
          await MainActor.run {
            host.transition(to: .provisioningDevTools(fractionCompleted: 0.6 + fraction * 0.2))
          }
        }
      )
    } catch {
      transition(to: .error(detail: "Homebrew install failed: \(error)"))
      return
    }

    do {
      _ = try await SharedCompassVMRipgrepProvisioner.provision(
        runner: client,
        progress: { fraction in
          await MainActor.run {
            host.transition(to: .provisioningDevTools(fractionCompleted: 0.8 + fraction * 0.05))
          }
        }
      )
    } catch {
      transition(to: .error(detail: "Ripgrep install failed: \(error)"))
      return
    }

    do {
      _ = try await SharedCompassVMToolchainProvisioner.provision(
        definition: SharedVMToolchainCatalog.definition(for: .openssl),
        runner: client,
        progress: { fraction in
          await MainActor.run {
            host.transition(to: .provisioningDevTools(fractionCompleted: 0.85 + fraction * 0.05))
          }
        }
      )
    } catch {
      transition(to: .error(detail: "OpenSSL + pkgconf install failed: \(error)"))
      return
    }

    // Rust first, then the cargo components the quality gates need
    // (coverage, mutation). The final 10% of progress is split across
    // the three installs.
    let cargoToolchainIDs: [SharedVMToolchainID] = [.rust, .cargoLlvmCov, .cargoMutants]
    for (index, id) in cargoToolchainIDs.enumerated() {
      let definition = SharedVMToolchainCatalog.definition(for: id)
      let base = 0.9 + (Double(index) / Double(cargoToolchainIDs.count)) * 0.1
      let span = 0.1 / Double(cargoToolchainIDs.count)
      do {
        _ = try await SharedCompassVMToolchainProvisioner.provision(
          definition: definition,
          runner: client,
          progress: { fraction in
            await MainActor.run {
              host.transition(
                to: .provisioningDevTools(fractionCompleted: base + fraction * span))
            }
          }
        )
      } catch {
        transition(
          to: .error(detail: "\(definition.displayName) toolchain install failed: \(error)"))
        return
      }
    }

    try? toolchainManager.seedDefaultProvisionedToolchains()
    _ = try? bundle.mutateState(fileManager: dependencies.fileManager) {
      $0.provisionStep = .ready
    }
    transition(to: .ready(sshDestination: destination))
  }

  /// Factory for the Shared VM toolchain service used by agent tools.
  func makeToolchainService() -> SharedCompassVMToolchainManager {
    SharedCompassVMToolchainManager(
      bundle: bundle,
      fileManager: dependencies.fileManager
    )
  }

  /// Backfills default toolchains on guests provisioned before Homebrew,
  /// ripgrep, OpenSSL, or Rust became default. This runs after readiness, so it
  /// deliberately avoids driving the readiness state machine; failures are
  /// non-fatal and the next launch can retry.
  private func ensureDefaultToolchainsIfNeeded() async {
    guard let machine = virtualMachine else { return }
    guard await SharedCompassVMVsock.waitUntilReachable(on: machine, timeout: 10) else { return }
    let client = Self.makeVsockClient(on: machine)
    let manager = makeToolchainService()

    let defaultIDs: [SharedVMToolchainID] = [
      .homebrew, .ripgrep, .openssl, .rust, .cargoLlvmCov, .cargoMutants,
    ]
    for id in defaultIDs {
      let definition = SharedVMToolchainCatalog.definition(for: id)
      let missing: Bool
      do {
        missing =
          try await SharedCompassVMToolchainProvisioner.probe(
            definition: definition,
            runner: client
          ) == false
      } catch {
        return
      }
      guard missing else { continue }
      do {
        _ = try await SharedCompassVMToolchainProvisioner.provision(
          definition: definition,
          runner: client,
          progress: { _ in }
        )
      } catch {
        return
      }
    }

    try? manager.seedDefaultProvisionedToolchains()
  }

  /// Builds a vsock-backed agent client that opens a fresh
  /// `VZVirtioSocketConnection` per RPC against the supplied VM.
  ///
  /// This is the canonical factory for the in-guest RPC client. Callers
  /// (Develop loops, worktree sync, dev-tools provisioner) go through
  /// it so the connect-and-write path stays in one place — anything
  /// outside SharedVM should treat the returned value as an
  /// `AgentFilesystem & AgentBashRunner` pair, not as a vsock-specific
  /// type.
  public static func makeVsockClient(on machine: VZVirtualMachine) -> AgentVsockClient {
    AgentVsockClient(
      transportFactory: {
        let connection = try await SharedCompassVMVsock.connect(on: machine)
        return VZVirtioSocketTransport(connection: connection)
      }
    )
  }

  /// Convenience facade for non-VM callers (AppModel, executor wiring)
  /// that need the host-or-guest filesystem + bash pair but don't want
  /// to know whether the run will route through the VM.
  ///
  /// - When `vmMachine` is nil, returns the host-direct implementations.
  /// - When `vmMachine` is non-nil, returns a single `AgentVsockClient`
  ///   that conforms to both protocols and shells every operation over
  ///   vsock to the in-guest agent.
  static func agentTransport(
    vmMachine: VZVirtualMachine?
  ) -> (filesystem: AgentFilesystem, bashRunner: AgentBashRunner) {
    if let machine = vmMachine {
      let client = makeVsockClient(on: machine)
      return (client, client)
    }
    return (AgentHostFilesystem(), AgentHostBashRunner())
  }
}
