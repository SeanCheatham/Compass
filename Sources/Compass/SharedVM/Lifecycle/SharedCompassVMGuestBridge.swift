import Foundation

/// SSH helpers for the Compass shared VM guest.
///
/// Most helpers only build the argument vectors that the existing Compass
/// process plumbing feeds to `/usr/bin/ssh`. The readiness, control-master,
/// and known-hosts bootstrap helpers use tiny bounded `Process` wrappers
/// because they are called before the normal agent transport is available.
struct SharedCompassVMGuestBridge {
  /// Where Compass-managed `ssh` binaries / config live by default.
  static let defaultSSHExecutablePath = "/usr/bin/ssh"

  /// Where the multiplexed SSH control socket lives. Includes the host,
  /// port, and remote user so concurrent destinations don't share a socket.
  /// Kept under `/tmp` rather than `$TMPDIR` because macOS `$TMPDIR` paths
  /// (`/var/folders/...`) push the resulting path close to the 104-char
  /// `sockaddr_un` limit, and ssh silently disables multiplexing once it
  /// trips that ceiling.
  static let controlPathTemplate = "/tmp/compass-ssh-%h-%p-%r"

  /// Tuneable options that affect every ssh invocation Compass makes.
  struct ConnectionOptions: Equatable {
    var executablePath: String
    var identityFile: String?
    var knownHostsFile: String?
    var strictHostKeyChecking: Bool
    var batchMode: Bool
    /// Disables PTY allocation (-T). Always set for non-interactive agent tool calls.
    var disablePseudoTerminal: Bool
    /// Optional ConnectTimeout (seconds). Used for probes.
    var connectTimeoutSeconds: Int?
    /// Multiplex SSH connections to the same destination. The first call
    /// becomes (or finds) the master; subsequent calls open a new channel
    /// over the existing TCP/SSH session, dropping per-call overhead from
    /// ~100ms+ to ~5ms. Must stay true for the agent's filesystem and bash
    /// tools — they fire dozens of SSH commands per run. Probes typically
    /// keep this true too so the master is warm by the time tools start.
    var useControlMaster: Bool
    /// Seconds the master stays alive after the last client disconnects.
    /// Applied only when `useControlMaster` is true.
    var controlPersistSeconds: Int

    init(
      executablePath: String = SharedCompassVMGuestBridge.defaultSSHExecutablePath,
      identityFile: String? = nil,
      knownHostsFile: String? = nil,
      strictHostKeyChecking: Bool = true,
      batchMode: Bool = true,
      disablePseudoTerminal: Bool = true,
      connectTimeoutSeconds: Int? = nil,
      useControlMaster: Bool = true,
      controlPersistSeconds: Int = 600
    ) {
      self.executablePath = executablePath
      self.identityFile = identityFile
      self.knownHostsFile = knownHostsFile
      self.strictHostKeyChecking = strictHostKeyChecking
      self.batchMode = batchMode
      self.disablePseudoTerminal = disablePseudoTerminal
      self.connectTimeoutSeconds = connectTimeoutSeconds
      self.useControlMaster = useControlMaster
      self.controlPersistSeconds = controlPersistSeconds
    }
  }

  /// Builds the `[String]` argv to invoke a remote command on the guest.
  ///
  /// Result is the argument vector NOT including the executable. The
  /// `Process.executableURL` should be set to `options.executablePath`.
  ///
  /// Layout:
  ///   `[-i <identity>] [-o UserKnownHostsFile=<...>] [-o StrictHostKeyChecking=yes]`
  ///   `[-o BatchMode=yes] [-o ConnectTimeout=N] [-T] <destination> <remoteCommand>`
  static func sshArguments(
    destination: String,
    remoteCommand: String,
    options: ConnectionOptions = ConnectionOptions()
  ) -> [String] {
    var arguments: [String] = []
    if let identity = options.identityFile, !identity.isEmpty {
      arguments.append(contentsOf: ["-i", identity])
    }
    if let knownHosts = options.knownHostsFile, !knownHosts.isEmpty {
      // ssh's UserKnownHostsFile option treats unquoted whitespace
      // in the value as a separator between multiple files — see
      // `man ssh_config`. Compass's bundle path lives under
      // `~/Library/Application Support/...` which contains a
      // space; the unquoted form gets parsed as TWO bogus files
      // (`.../Library/Application` and `Support/.../known_hosts`)
      // and the strict host-key check fails with "Host key
      // verification failed" even when known_hosts is correctly
      // populated. Wrap the path in inner double quotes so ssh's
      // parser sees it as a single token.
      arguments.append(contentsOf: ["-o", #"UserKnownHostsFile="\#(knownHosts)""#])
    }
    arguments.append(contentsOf: [
      "-o", "StrictHostKeyChecking=\(options.strictHostKeyChecking ? "yes" : "no")",
    ])
    if options.batchMode {
      arguments.append(contentsOf: ["-o", "BatchMode=yes"])
    }
    if let timeout = options.connectTimeoutSeconds {
      arguments.append(contentsOf: ["-o", "ConnectTimeout=\(timeout)"])
    }
    if options.useControlMaster {
      arguments.append(
        contentsOf: controlMasterOptions(persistSeconds: options.controlPersistSeconds))
    }
    if options.disablePseudoTerminal {
      arguments.append("-T")
    }
    arguments.append(destination)
    arguments.append(remoteCommand)
    return arguments
  }

  /// Returns the `-o ControlMaster=auto -o ControlPath=... -o ControlPersist=...`
  /// triplet that wires SSH connection multiplexing. Factored out so the
  /// `closeControlMaster` shutdown path can reuse the exact same ControlPath
  /// and target the live socket.
  static func controlMasterOptions(persistSeconds: Int) -> [String] {
    [
      "-o", "ControlMaster=auto",
      "-o", "ControlPath=\(controlPathTemplate)",
      "-o", "ControlPersist=\(persistSeconds)",
    ]
  }

  /// Argv for `ssh -O exit` against the multiplexed master socket for
  /// `destination`. Used at app quit so we don't leave a backgrounded ssh
  /// master alive after the Shared VM is gone.
  ///
  /// Mirrors `sshArguments` for the auth/strict-host flags so the master
  /// can be addressed even if BatchMode/StrictHostKeyChecking would
  /// otherwise complain. `-O exit` is a local control op — it does not
  /// require the remote side to be reachable.
  static func closeControlMasterArguments(
    destination: String,
    options: ConnectionOptions = ConnectionOptions()
  ) -> [String] {
    var arguments: [String] = []
    if let identity = options.identityFile, !identity.isEmpty {
      arguments.append(contentsOf: ["-i", identity])
    }
    if let knownHosts = options.knownHostsFile, !knownHosts.isEmpty {
      arguments.append(contentsOf: ["-o", #"UserKnownHostsFile="\#(knownHosts)""#])
    }
    arguments.append(contentsOf: [
      "-o", "StrictHostKeyChecking=\(options.strictHostKeyChecking ? "yes" : "no")",
    ])
    if options.batchMode {
      arguments.append(contentsOf: ["-o", "BatchMode=yes"])
    }
    arguments.append(contentsOf: ["-o", "ControlPath=\(controlPathTemplate)"])
    arguments.append(contentsOf: ["-O", "exit"])
    arguments.append(destination)
    return arguments
  }

  /// Builds the `[String]` argv to upload one local file to the guest via
  /// `scp`. Mirrors `sshArguments` for auth, known_hosts, and multiplexing
  /// so repair paths don't accidentally use a different trust boundary.
  static func scpUploadArguments(
    sourcePath: String,
    destination: String,
    remotePath: String,
    options: ConnectionOptions = ConnectionOptions()
  ) -> [String] {
    var arguments: [String] = []
    if let identity = options.identityFile, !identity.isEmpty {
      arguments.append(contentsOf: ["-i", identity])
    }
    if let knownHosts = options.knownHostsFile, !knownHosts.isEmpty {
      arguments.append(contentsOf: ["-o", #"UserKnownHostsFile="\#(knownHosts)""#])
    }
    arguments.append(contentsOf: [
      "-o", "StrictHostKeyChecking=\(options.strictHostKeyChecking ? "yes" : "no")",
    ])
    if options.batchMode {
      arguments.append(contentsOf: ["-o", "BatchMode=yes"])
    }
    if let timeout = options.connectTimeoutSeconds {
      arguments.append(contentsOf: ["-o", "ConnectTimeout=\(timeout)"])
    }
    if options.useControlMaster {
      arguments.append(
        contentsOf: controlMasterOptions(persistSeconds: options.controlPersistSeconds))
    }
    arguments.append(sourcePath)
    arguments.append("\(destination):\(remotePath)")
    return arguments
  }

  /// Fire-and-forget tear-down of the multiplexed SSH master for
  /// `destination`. Safe to call when no master exists — ssh prints a
  /// diagnostic on stderr and exits non-zero, which we deliberately
  /// swallow. Bounded by `timeout` so a stuck `ssh -O exit` (rare, but
  /// possible if the control socket is in an odd state) cannot block app
  /// shutdown.
  @discardableResult
  static func closeControlMaster(
    destination: String,
    options: ConnectionOptions = ConnectionOptions(),
    timeout: TimeInterval = 3
  ) async -> Bool {
    let arguments = closeControlMasterArguments(destination: destination, options: options)
    return await Task.detached { () -> Bool in
      let process = Process()
      process.executableURL = URL(fileURLWithPath: options.executablePath)
      process.arguments = arguments
      let devNull = ProcessNullDeviceHandles(output: true, error: true, input: true)
      devNull.assign(to: process)
      defer { devNull.close() }
      do {
        try process.run()
      } catch {
        return false
      }
      let deadline = Date().addingTimeInterval(timeout + 1)
      while process.isRunning && Date() < deadline {
        try? await Task.sleep(nanoseconds: 100_000_000)
      }
      if process.isRunning {
        process.terminate()
        return false
      }
      return process.terminationStatus == 0
    }.value
  }

  /// POSIX-safe single-quote escaping. Wraps any string in single quotes and
  /// emits the well-known `'\''` escape for embedded single quotes.
  static func posixQuote(_ value: String) -> String {
    if value.isEmpty { return "''" }
    // Fast path: safe identifier characters need no quoting.
    let safeCharacters = CharacterSet.alphanumerics
      .union(CharacterSet(charactersIn: "._-/=@:%+,"))
    if value.unicodeScalars.allSatisfy({ safeCharacters.contains($0) }) {
      return value
    }
    var escaped = "'"
    for ch in value {
      if ch == "'" {
        escaped.append("'\\''")
      } else {
        escaped.append(ch)
      }
    }
    escaped.append("'")
    return escaped
  }

  // MARK: - SSH probe

  /// Lightweight readiness probe. Returns `true` if `ssh <host> true` exits 0
  /// within `timeout` seconds; otherwise returns `false`. Never throws.
  ///
  /// Used by the first-boot gate. The probe is deliberately bounded — it does
  /// not retry internally; callers wrap it in a loop with their own budget.
  static func probeSSHAvailable(
    destination: String,
    options: ConnectionOptions,
    timeout: TimeInterval = 5
  ) async -> Bool {
    var probeOptions = options
    probeOptions.connectTimeoutSeconds = max(1, Int(timeout.rounded(.up)))
    let arguments = sshArguments(
      destination: destination,
      remoteCommand: "true",
      options: probeOptions
    )
    return await Task.detached { () -> Bool in
      let process = Process()
      process.executableURL = URL(fileURLWithPath: probeOptions.executablePath)
      process.arguments = arguments
      let devNull = ProcessNullDeviceHandles(output: true, error: true, input: true)
      devNull.assign(to: process)
      defer { devNull.close() }
      do {
        try process.run()
      } catch {
        return false
      }
      // Bound the wait to the supplied timeout.
      let deadline = Date().addingTimeInterval(timeout + 1)
      while process.isRunning && Date() < deadline {
        try? await Task.sleep(nanoseconds: 100_000_000)
      }
      if process.isRunning {
        process.terminate()
        return false
      }
      return process.terminationStatus == 0
    }.value
  }

  // MARK: - Known-hosts bootstrap

  /// Result of an `ssh-keyscan` invocation against a guest host.
  struct KnownHostsBootstrap: Equatable {
    /// True if at least one host key was successfully fetched and written.
    var succeeded: Bool
    /// Number of host-key lines appended (zero if no entries were added —
    /// e.g. the destination was already represented in the file).
    var entriesAppended: Int
  }

  /// Populates `knownHostsFile` with the host keys advertised by `host`
  /// via `ssh-keyscan`. Idempotent — host entries already present in the
  /// file are not duplicated.
  ///
  /// Why this exists: the readiness probe runs with
  /// `StrictHostKeyChecking=yes`, which refuses to connect to a host
  /// whose key is not already in `known_hosts`. On a fresh provision the
  /// host has never seen the guest's key and the probe fails with
  /// "Host key verification failed." We TOFU-trust the freshly-generated
  /// host key here. This is safe because the guest lives on a host-local
  /// virbr/NAT network with no realistic MITM surface.
  ///
  /// Pure on filesystem: writes only to `knownHostsFile` (creates the
  /// parent directory if missing). No network state other than the
  /// subprocess `ssh-keyscan` makes.
  static func populateKnownHosts(
    host: String,
    knownHostsFile: String,
    timeout: TimeInterval = 5,
    sshKeyscanPath: String = "/usr/bin/ssh-keyscan",
    fileManager: FileManager = .default
  ) async -> KnownHostsBootstrap {
    let scanned = await runKeyscan(
      host: host,
      timeout: timeout,
      sshKeyscanPath: sshKeyscanPath
    )
    guard let scanned, !scanned.isEmpty else {
      return KnownHostsBootstrap(succeeded: false, entriesAppended: 0)
    }

    let knownHostsURL = URL(fileURLWithPath: knownHostsFile)
    let parent = knownHostsURL.deletingLastPathComponent()
    try? fileManager.createDirectory(at: parent, withIntermediateDirectories: true)

    // Read existing contents (if any) so we can dedupe.
    let existing = (try? String(contentsOf: knownHostsURL, encoding: .utf8)) ?? ""
    let existingLines = Set(
      existing.split(separator: "\n", omittingEmptySubsequences: true).map(String.init))

    var toAppend: [String] = []
    for line in scanned.split(separator: "\n", omittingEmptySubsequences: true) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      // ssh-keyscan emits `# comment` lines on stderr but also some
      // on stdout for non-fatal warnings. Drop them.
      if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
      if existingLines.contains(trimmed) { continue }
      toAppend.append(trimmed)
    }

    if toAppend.isEmpty {
      // Already fully represented — treat as success so the caller
      // proceeds straight to the probe.
      return KnownHostsBootstrap(succeeded: true, entriesAppended: 0)
    }

    var merged = existing
    if !merged.isEmpty && !merged.hasSuffix("\n") {
      merged.append("\n")
    }
    merged.append(toAppend.joined(separator: "\n"))
    merged.append("\n")
    do {
      try merged.write(to: knownHostsURL, atomically: true, encoding: .utf8)
      return KnownHostsBootstrap(succeeded: true, entriesAppended: toAppend.count)
    } catch {
      return KnownHostsBootstrap(succeeded: false, entriesAppended: 0)
    }
  }

  private static func runKeyscan(
    host: String,
    timeout: TimeInterval,
    sshKeyscanPath: String
  ) async -> String? {
    do {
      let result = try await ProcessRunner.run(
        executable: sshKeyscanPath,
        arguments: [
          "-T", String(max(1, Int(timeout.rounded(.up)))),
          "-t", "ed25519,rsa,ecdsa",
          host,
        ],
        timeout: max(timeout + 5, 10)
      )
      guard result.exitCode == 0, !result.stdout.isEmpty else { return nil }
      return result.stdout
    } catch {
      return nil
    }
  }

  private struct ProcessNullDeviceHandles {
    private let outputHandle: FileHandle?
    private let errorHandle: FileHandle?
    private let inputHandle: FileHandle?

    init(output: Bool, error: Bool, input: Bool) {
      outputHandle = output ? FileHandle(forWritingAtPath: "/dev/null") : nil
      errorHandle = error ? FileHandle(forWritingAtPath: "/dev/null") : nil
      inputHandle = input ? FileHandle(forReadingAtPath: "/dev/null") : nil
    }

    func assign(to process: Process) {
      if let outputHandle {
        process.standardOutput = outputHandle
      }
      if let errorHandle {
        process.standardError = errorHandle
      }
      if let inputHandle {
        process.standardInput = inputHandle
      }
    }

    func close() {
      try? outputHandle?.close()
      try? errorHandle?.close()
      try? inputHandle?.close()
    }
  }
}
