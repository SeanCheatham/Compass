import Foundation

/// Runs bash commands inside the embedded macOS VM (Apple
/// Virtualization.framework) via the in-guest Compass agent over vsock.
///
/// Before the first command, the host repo is synced into the guest's
/// per-repo workspace (`SharedCompassVMRepoWorkspaceSync`); subsequent
/// runs re-push only when the host worktree has drifted. Commands then
/// execute against the guest worktree, which is where generated-app
/// builds (`swift build`, `swift test`, `cargo …`) run on a real macOS
/// toolchain without touching the host's.
public struct AgentMacOSVMBashRunner: AgentBashRunner {
  public enum VMRunnerError: LocalizedError {
    case vmNotReady(detail: String)
    case readinessTimeout(seconds: Int)
    case workingDirectoryOutsideRepo(URL)

    public var errorDescription: String? {
      switch self {
      case .vmNotReady(let detail):
        return "macOS VM is not ready: \(detail)"
      case .readinessTimeout(let seconds):
        return
          "macOS VM did not become ready within \(seconds)s. Open Compass Settings → macOS VM to inspect provisioning, or set COMPASS_MACOS_VM_READY_TIMEOUT."
      case .workingDirectoryOutsideRepo(let url):
        return "Working directory \(url.path) is outside the repo root synced into the macOS VM."
      }
    }
  }

  public var repoRoot: URL
  public var label: String
  public var forceRefresh: Bool

  public init(
    repoRoot: URL,
    label: String = "agent",
    forceRefresh: Bool = false
  ) {
    self.repoRoot = repoRoot.standardizedFileURL
    self.label = label
    self.forceRefresh = forceRefresh
  }

  public func run(
    command: String,
    workingDirectory: URL,
    timeout: TimeInterval
  ) async throws -> ProcessResult {
    let client = try await Self.ensureReadyClient()
    let sync = try await SharedCompassVMRepoWorkspaceSync.ensurePopulated(
      hostRepoURL: repoRoot,
      client: client,
      forceRefresh: forceRefresh
    )
    let guestWorkingDirectory = try guestWorkingDirectory(
      for: workingDirectory,
      guestWorktreePath: sync.guestPath
    )
    return try await client.run(
      command: command,
      workingDirectory: URL(fileURLWithPath: guestWorkingDirectory),
      timeout: timeout
    )
  }

  /// Boots the VM if needed and waits until the in-guest agent answers,
  /// then returns a vsock client bound to the live machine. First-time
  /// callers trigger full provisioning (IPSW download, macOS install,
  /// headless first boot, dev-tools install), which can take a while;
  /// the wait budget is configurable via `COMPASS_MACOS_VM_READY_TIMEOUT`.
  @MainActor
  public static func ensureReadyClient() async throws -> AgentVsockClient {
    let vm = SharedCompassVM.shared
    try await vm.warmup()
    if case .notProvisioned = vm.readiness {
      try await vm.provisionIfNeeded()
    }
    try await vm.start()

    let timeout = readinessTimeoutSeconds()
    let deadline = Date().addingTimeInterval(TimeInterval(timeout))
    while Date() < deadline {
      switch vm.readiness {
      case .ready:
        guard let machine = vm.virtualMachine else {
          throw VMRunnerError.vmNotReady(detail: "readiness reported ready but no VM is running")
        }
        return SharedCompassVM.makeVsockClient(on: machine)
      case .error(let detail):
        throw VMRunnerError.vmNotReady(detail: detail)
      case .unavailable(let reason):
        throw VMRunnerError.vmNotReady(detail: reason)
      case .notProvisioned, .downloadingIPSW, .installing, .guestPrepping,
        .provisioningDevTools:
        try? await Task.sleep(nanoseconds: 2_000_000_000)
      }
    }
    throw VMRunnerError.readinessTimeout(seconds: timeout)
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
}
