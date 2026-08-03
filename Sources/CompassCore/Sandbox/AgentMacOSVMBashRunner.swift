import Foundation

/// Runs bash commands inside the embedded macOS VM (Apple
/// Virtualization.framework) via the in-guest Compass agent over vsock.
///
/// Before the first command, the host repo is synced into the guest's
/// per-repo workspace — git-over-SSH (`SharedCompassVMGitSSHSync`) when the
/// guest's git toolchain is healthy, the tar push
/// (`SharedCompassVMRepoWorkspaceSync`) as fallback. Commands then execute
/// against the guest worktree, which is where generated-app builds
/// (`swift build`, `swift test`, `cargo …`) run on a real macOS toolchain
/// without touching the host's.
public struct AgentMacOSVMBashRunner: AgentBashRunner {
  public enum VMRunnerError: LocalizedError {
    case vmNotReady(detail: String)
    case provisioningDisabled
    case readinessTimeout(seconds: Int)
    case workingDirectoryOutsideRepo(URL)

    public var errorDescription: String? {
      switch self {
      case .vmNotReady(let detail):
        return "macOS VM is not ready: \(detail)"
      case .provisioningDisabled:
        return
          "macOS VM is not provisioned and auto-provisioning is disabled (COMPASS_MACOS_VM_AUTO_PROVISION=0). Provision it from Compass Settings → macOS VM, or re-enable auto-provisioning."
      case .readinessTimeout(let seconds):
        return
          "macOS VM made no readiness progress for \(seconds)s. Open Compass Settings → macOS VM to inspect provisioning, or set COMPASS_MACOS_VM_READY_TIMEOUT."
      case .workingDirectoryOutsideRepo(let url):
        return "Working directory \(url.path) is outside the repo root synced into the macOS VM."
      }
    }
  }

  /// How the host repo reached the guest on the last `run` — useful for
  /// diagnostics and tests.
  public enum SyncTransport: Sendable, Equatable {
    case gitSSH
    case tar
  }

  public var repoRoot: URL
  public var label: String
  public var forceRefresh: Bool
  /// When true, guest-side worktree changes are committed and merged back
  /// into the host repo after each command. Off by default: the verify
  /// gate is read-only, and pulling build noise back is wasted work.
  public var pullAfterRun: Bool
  /// The agent-visible workspace root ("/workspace"). Command strings
  /// referencing it are rewritten to the guest worktree path so agents
  /// can use the same paths for file tools (host) and bash (guest).
  public var visibleWorkspacePath: String

  public init(
    repoRoot: URL,
    label: String = "agent",
    forceRefresh: Bool = false,
    pullAfterRun: Bool = false,
    visibleWorkspacePath: String = "/workspace"
  ) {
    self.repoRoot = repoRoot.standardizedFileURL
    self.label = label
    self.forceRefresh = forceRefresh
    self.pullAfterRun = pullAfterRun
    self.visibleWorkspacePath = visibleWorkspacePath
  }

  public func run(
    command: String,
    workingDirectory: URL,
    timeout: TimeInterval
  ) async throws -> ProcessResult {
    let ready = try await Self.ensureReady()
    let sync = try await syncToGuest(
      client: ready.client,
      sshDestination: ready.sshDestination,
      sshOptions: ready.sshOptions
    )
    let guestWorkingDirectory = try guestWorkingDirectory(
      for: workingDirectory,
      guestWorktreePath: sync.guestPath
    )
    let guestCommand = rewriteVisibleWorkspacePaths(
      in: command,
      guestWorktreePath: sync.guestPath
    )
    let result = try await ready.client.run(
      command: guestCommand,
      workingDirectory: URL(fileURLWithPath: guestWorkingDirectory),
      timeout: timeout
    )
    if pullAfterRun {
      try await SharedCompassVMGitSSHSync.pullFromGuest(
        hostRepoURL: repoRoot,
        client: ready.client,
        sshDestination: ready.sshDestination,
        sshOptions: ready.sshOptions
      )
    }
    return result
  }

  /// Git-over-SSH first; the tar push remains as the fallback for guests
  /// whose git install is broken mid-provisioning.
  func syncToGuest(
    client: AgentVsockClient,
    sshDestination: String,
    sshOptions: SharedCompassVMGuestBridge.ConnectionOptions
  ) async throws -> (guestPath: String, transport: SyncTransport) {
    if !forceRefresh {
      do {
        let guestPath = try await SharedCompassVMGitSSHSync.syncToGuest(
          hostRepoURL: repoRoot,
          client: client,
          sshDestination: sshDestination,
          sshOptions: sshOptions
        )
        return (guestPath, .gitSSH)
      } catch {
        // Fall through to the tar transport — a broken guest git must not
        // block the build/verify gate.
      }
    }
    let sync = try await SharedCompassVMRepoWorkspaceSync.ensurePopulated(
      hostRepoURL: repoRoot,
      client: client,
      forceRefresh: forceRefresh
    )
    return (sync.guestPath, .tar)
  }

  public struct ReadyVM {
    public var client: AgentVsockClient
    public var sshDestination: String
    public var sshOptions: SharedCompassVMGuestBridge.ConnectionOptions
  }

  /// Boots the VM if needed and waits until the in-guest agent answers,
  /// then returns a vsock client plus the SSH coordinates of the live
  /// guest. First-time callers trigger full provisioning (IPSW download,
  /// macOS install, headless first boot, dev-tools install), which can
  /// take a while; the wait budget is a *no-progress* window — long
  /// phases that keep moving the readiness state (IPSW download, CLT
  /// install) never trip it. Configurable via
  /// `COMPASS_MACOS_VM_READY_TIMEOUT`.
  @MainActor
  public static func ensureReady() async throws -> ReadyVM {
    let vm = SharedCompassVM.shared
    try await vm.warmup()
    if case .notProvisioned = vm.readiness {
      guard autoProvisioningEnabled() else {
        throw VMRunnerError.provisioningDisabled
      }
      try await vm.provisionIfNeeded()
    }
    try await vm.start()

    let timeout = readinessTimeoutSeconds()
    var lastReadiness = vm.readiness
    var lastProgress = Date()
    while true {
      switch vm.readiness {
      case .ready(let sshDestination):
        guard vm.virtualMachine != nil else {
          throw VMRunnerError.vmNotReady(detail: "readiness reported ready but no VM is running")
        }
        return ReadyVM(
          client: SharedCompassVM.makeVsockClient(on: vm.virtualMachine!),
          sshDestination: sshDestination,
          sshOptions: sshOptions()
        )
      case .error(let detail):
        throw VMRunnerError.vmNotReady(detail: detail)
      case .unavailable(let reason):
        throw VMRunnerError.vmNotReady(detail: reason)
      case .notProvisioned, .downloadingIPSW, .installing, .guestPrepping,
        .provisioningDevTools:
        if vm.readiness != lastReadiness {
          lastReadiness = vm.readiness
          lastProgress = Date()
        }
        guard Date().timeIntervalSince(lastProgress) < TimeInterval(timeout) else {
          throw VMRunnerError.readinessTimeout(seconds: timeout)
        }
        try? await Task.sleep(nanoseconds: 2_000_000_000)
      }
    }
  }

  /// Kept for source compatibility with earlier call sites; prefer
  /// `ensureReady()` when SSH coordinates are also needed.
  @MainActor
  public static func ensureReadyClient() async throws -> AgentVsockClient {
    try await ensureReady().client
  }

  @MainActor
  static func sshOptions() -> SharedCompassVMGuestBridge.ConnectionOptions {
    let bundle = SharedCompassVM.shared.bundle
    return SharedCompassVMGuestBridge.ConnectionOptions(
      identityFile: bundle.privateKeyURL.path,
      knownHostsFile: bundle.knownHostsURL.path,
      connectTimeoutSeconds: 10
    )
  }

  public static func autoProvisioningEnabled(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> Bool {
    guard
      let raw = environment["COMPASS_MACOS_VM_AUTO_PROVISION"]?
        .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    else { return true }
    return raw != "0" && raw != "false" && raw != "no"
  }

  public static func readinessTimeoutSeconds(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> Int {
    guard
      let raw = environment["COMPASS_MACOS_VM_READY_TIMEOUT"]?
        .trimmingCharacters(in: .whitespacesAndNewlines),
      let value = Int(raw), value > 0
    else { return 1_800 }
    return value
  }

  /// Maps a host-side working directory inside the repo to the matching
  /// path inside the guest worktree.
  public func guestWorkingDirectory(
    for hostWorkingDirectory: URL,
    guestWorktreePath: String
  ) throws -> String {
    let rootPath = repoRoot.path
    let hostPath = hostWorkingDirectory.standardizedFileURL.path
    guard hostPath == rootPath || hostPath.hasPrefix(rootPath + "/") else {
      throw VMRunnerError.workingDirectoryOutsideRepo(hostWorkingDirectory)
    }
    let relative = String(hostPath.dropFirst(rootPath.count))
    return guestWorktreePath + relative
  }

  /// Rewrites references to the agent-visible workspace root (e.g.
  /// `/workspace/crates/core`) in a command string to the guest worktree
  /// path. Only path-boundary occurrences are touched, so words like
  /// `/workspaceless` are left alone.
  public func rewriteVisibleWorkspacePaths(
    in command: String,
    guestWorktreePath: String
  ) -> String {
    let root = visibleWorkspacePath
    guard !root.isEmpty, command.contains(root) else { return command }
    var result = ""
    var index = command.startIndex
    while index < command.endIndex {
      guard let range = command.range(of: root, range: index..<command.endIndex) else {
        result += command[index...]
        break
      }
      let after = range.upperBound
      let isBoundary =
        after == command.endIndex
        || command[after] == "/"
        || command[after].isWhitespace
        || "\"'`);|&".contains(command[after])
      result += command[index..<range.lowerBound]
      if isBoundary {
        result += guestWorktreePath
      } else {
        result += command[range]
      }
      index = range.upperBound
    }
    return result
  }
}
