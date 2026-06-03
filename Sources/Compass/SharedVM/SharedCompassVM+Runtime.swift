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
  func start() async throws {
    if fallbackUnavailableReason != nil { return }
    if let virtualMachine, virtualMachine.state == .running {
      return
    }
    if let existing = startInFlight {
      try await existing.value
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
    SharedCompassVMGitService.shared.install(on: machine)

    // Headless first-boot follow-up: if we just booted a freshly-planted
    // guest, the LaunchDaemon will spend ~30-60s creating the user,
    // authorising the SSH key, and enabling Remote Login. Kick off a
    // background poller that finalises readiness once SSH responds,
    // so the user never needs to click "Mark setup complete".
    //
    // For subsequent boots (state is already .ready on disk), `warmup()`
    // has held the in-memory readiness at `.guestPrepping`. Probe SSH
    // until the guest's sshd answers, then flip the in-memory state to
    // `.ready` — without touching the persisted state machine.
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
      Task { [weak self] in
        await self?.pollSSHAfterBootAndMarkReady()
      }
    default:
      break
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
    guard let ip = state.lastKnownGoodIP else {
      transition(
        to: .error(
          detail: "Resuming dev-tools install: guest IP is not cached. Reset and re-provision."))
      return
    }
    let destination = "\(state.guestUserName)@\(ip)"
    let options = SharedCompassVMGuestBridge.ConnectionOptions(
      identityFile: bundle.privateKeyURL.path,
      knownHostsFile: bundle.knownHostsURL.path,
      connectTimeoutSeconds: 5
    )
    let deadline = Date().addingTimeInterval(300)
    var attemptIntervalNanoseconds: UInt64 = 2_000_000_000
    var probeOK = false
    while Date() < deadline {
      probeOK = await SharedCompassVMGuestBridge.probeSSHAvailable(
        destination: destination,
        options: options,
        timeout: 5
      )
      if probeOK { break }
      try? await Task.sleep(nanoseconds: attemptIntervalNanoseconds)
      attemptIntervalNanoseconds = min(attemptIntervalNanoseconds * 2, 10_000_000_000)
    }
    guard probeOK else {
      transition(
        to: .error(
          detail: "Resuming dev-tools install: SSH probe to \(destination) timed out."))
      return
    }
    lastResolvedSSHDestination = destination
    transition(to: .provisioningDevTools(fractionCompleted: 0))
    await runDevToolsProvisioner(destination: destination)
  }

  /// Lightweight SSH probe used on subsequent boots when the bundle is
  /// already past first-boot setup. Unlike `pollUntilHeadlessGuestReady`,
  /// this does not mutate persisted state — it only flips the in-memory
  /// readiness to `.ready` once the guest's sshd answers, so the UI
  /// reflects "actually reachable" rather than "previously was reachable".
  private func pollSSHAfterBootAndMarkReady() async {
    let state =
      (try? bundle.loadState(fileManager: dependencies.fileManager))
      ?? SharedCompassVMBundle.State()
    guard let ip = state.lastKnownGoodIP else { return }
    let destination = "\(state.guestUserName)@\(ip)"
    let options = SharedCompassVMGuestBridge.ConnectionOptions(
      identityFile: bundle.privateKeyURL.path,
      knownHostsFile: bundle.knownHostsURL.path,
      connectTimeoutSeconds: 5
    )
    let deadline = Date().addingTimeInterval(300)  // 5 minutes
    var attemptIntervalNanoseconds: UInt64 = 2_000_000_000
    while Date() < deadline {
      let probeOK = await SharedCompassVMGuestBridge.probeSSHAvailable(
        destination: destination,
        options: options,
        timeout: 5
      )
      if probeOK {
        lastResolvedSSHDestination = destination
        guard await ensureGuestAgentReachableAfterBoot(destination: destination) else { return }
        transition(to: .ready(sshDestination: destination))
        Task { [weak self] in
          await self?.ensureDefaultToolchainsIfNeeded()
        }
        return
      }
      try? await Task.sleep(nanoseconds: attemptIntervalNanoseconds)
      // Backoff capped at 10s so the UI doesn't stall after a slow
      // first probe but we still avoid hammering sshd during the boot.
      attemptIntervalNanoseconds = min(attemptIntervalNanoseconds * 2, 10_000_000_000)
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
    let installedHelperWorks = await SharedCompassVMGuestAgentInstall.probeInstalledHelperOverSSH(
      destination: destination,
      options: options
    )
    if liveAgentReachable && installedHelperWorks {
      return true
    }

    do {
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
    return true
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
        workingDirectory: URL(fileURLWithPath: "/"),
        timeout: timeout
      )
      return result.exitCode == 0
    } catch {
      return false
    }
  }

  /// Pauses the live VM. No-op if no VM is running.
  func pause() {
    guard let machine = virtualMachine, machine.state == .running else { return }
    machine.pause { _ in
      // Result is intentionally ignored — failure to pause is logged at the
      // call site but does not block the host going to sleep.
    }
  }

  /// Resumes the paused VM. No-op if no VM is paused.
  func resume() {
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
  func stop() async {
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

    guard let machine = virtualMachine else { return }
    SharedCompassVMGitService.shared.remove(from: machine)
    if machine.state == .stopped {
      virtualMachine = nil
      tearDownConsolePipe()
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
  }

  /// Marks the user-driven first-boot Setup Assistant as complete.
  /// Transitions readiness to `.guestPrepping` and then to
  /// `.provisioningDevTools` once the SSH probe succeeds, kicking off
  /// the headless CLT install before finally flipping to `.ready`. The
  /// Sandbox view invokes this when the user taps "Mark setup complete";
  /// the headless first-boot driver calls it repeatedly until readiness
  /// leaves `.guestPrepping`.
  func markSetupComplete() async {
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
        "SSH probe to \(destination) failed. Confirm the bootstrap script ran successfully inside the guest (sshd enabled, key authorised)."
      return
    }
    lastResolvedSSHDestination = destination

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
  /// vsock-backed bash runner: CLT, Homebrew, ripgrep, then Rust.
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
            host.transition(to: .provisioningDevTools(fractionCompleted: 0.8 + fraction * 0.1))
          }
        }
      )
    } catch {
      transition(to: .error(detail: "Ripgrep install failed: \(error)"))
      return
    }

    let rustDefinition = SharedVMToolchainCatalog.definition(for: .rust)
    do {
      _ = try await SharedCompassVMToolchainProvisioner.provision(
        definition: rustDefinition,
        runner: client,
        progress: { fraction in
          await MainActor.run {
            host.transition(to: .provisioningDevTools(fractionCompleted: 0.9 + fraction * 0.1))
          }
        }
      )
    } catch {
      transition(to: .error(detail: "Rust toolchain install failed: \(error)"))
      return
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
  /// ripgrep, or Rust became default. This runs after readiness, so it
  /// deliberately avoids driving the readiness state machine; failures are
  /// non-fatal and the next launch can retry.
  private func ensureDefaultToolchainsIfNeeded() async {
    guard let machine = virtualMachine else { return }
    guard await SharedCompassVMVsock.waitUntilReachable(on: machine, timeout: 10) else { return }
    let client = Self.makeVsockClient(on: machine)
    let manager = makeToolchainService()

    let homebrewMissing: Bool
    do {
      homebrewMissing =
        try await SharedCompassVMToolchainProvisioner.probe(
          definition: SharedVMToolchainCatalog.definition(for: .homebrew),
          runner: client
        ) == false
    } catch {
      return
    }

    let ripgrepMissing: Bool
    do {
      ripgrepMissing =
        try await SharedCompassVMRipgrepProvisioner.probeAlreadyInstalled(
          runner: client
        ) == false
    } catch {
      return
    }

    let rustMissing: Bool
    do {
      rustMissing =
        try await SharedCompassVMToolchainProvisioner.probe(
          definition: SharedVMToolchainCatalog.definition(for: .rust),
          runner: client
        ) == false
    } catch {
      return
    }

    guard homebrewMissing || ripgrepMissing || rustMissing else { return }

    if homebrewMissing {
      do {
        _ = try await SharedCompassVMToolchainProvisioner.provision(
          definition: SharedVMToolchainCatalog.definition(for: .homebrew),
          runner: client,
          progress: { _ in }
        )
      } catch {
        return
      }
    }

    if ripgrepMissing {
      do {
        _ = try await SharedCompassVMRipgrepProvisioner.provision(
          runner: client,
          progress: { _ in }
        )
      } catch {
        return
      }
    }

    if rustMissing {
      do {
        _ = try await SharedCompassVMToolchainProvisioner.provision(
          definition: SharedVMToolchainCatalog.definition(for: .rust),
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
  static func makeVsockClient(on machine: VZVirtualMachine) -> AgentVsockClient {
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
