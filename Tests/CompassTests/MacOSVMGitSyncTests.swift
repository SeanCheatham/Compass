import CompassCore
import Foundation
import Testing

struct MacOSVMGitSyncTests {

  // MARK: - Guest paths

  @Test
  func guestPathsDeriveExchangeAndWorktreeFromWorkspaceID() {
    let paths = SharedCompassVMGitSSHSync.guestPaths(workspaceID: "abc-123")
    #expect(paths.workspaceRoot == "/Users/compass/Compass/Repos/abc-123")
    #expect(paths.exchangePath == "/Users/compass/Compass/Repos/abc-123/exchange.git")
    #expect(paths.worktreePath == "/Users/compass/Compass/Repos/abc-123/worktree")
  }

  @Test
  func exchangeSSHURLCombinesDestinationAndPath() {
    #expect(
      SharedCompassVMGitSSHSync.exchangeSSHURL(
        sshDestination: "compass@192.168.64.2",
        exchangePath: "/Users/compass/Compass/Repos/abc/exchange.git"
      ) == "ssh://compass@192.168.64.2/Users/compass/Compass/Repos/abc/exchange.git")
  }

  // MARK: - GIT_SSH_COMMAND

  @Test
  func gitSSHCommandQuotesPathsWithSpaces() {
    let options = SharedCompassVMGuestBridge.ConnectionOptions(
      identityFile: "/Users/example/Library/Application Support/Compass/SharedVM/bundle.vmbundle/id_ed25519",
      knownHostsFile: "/Users/example/Library/Application Support/Compass/SharedVM/bundle.vmbundle/known_hosts",
      connectTimeoutSeconds: 10
    )
    let command = SharedCompassVMGitSSHSync.gitSSHCommand(options: options)
    #expect(command.hasPrefix("/usr/bin/ssh"))
    #expect(
      command.contains(
        "-i '/Users/example/Library/Application Support/Compass/SharedVM/bundle.vmbundle/id_ed25519'"
      ))
    #expect(command.contains("StrictHostKeyChecking=yes"))
    #expect(command.contains("BatchMode=yes"))
    #expect(command.contains("ConnectTimeout=10"))
  }

  // MARK: - Guest scripts

  @Test
  func guestBootstrapScriptIsIdempotentAndQuotesPaths() {
    let paths = SharedCompassVMGitSSHSync.guestPaths(workspaceID: "abc-123")
    let script = SharedCompassVMGitSSHSync.guestBootstrapScript(paths: paths)
    #expect(script.contains("git init --bare"))
    #expect(script.contains("rev-parse --is-bare-repository"))
    #expect(script.contains("remote add exchange"))
    #expect(script.contains("remote remove exchange"))
  }

  @Test
  func guestResetScriptUsesHardResetPreservingUntrackedBuildDirs() {
    let paths = SharedCompassVMGitSSHSync.guestPaths(workspaceID: "abc-123")
    let script = SharedCompassVMGitSSHSync.guestResetScript(paths: paths)
    #expect(script.contains("git -C /Users/compass/Compass/Repos/abc-123/worktree fetch exchange refs/compass/sync"))
    #expect(script.contains("reset --hard FETCH_HEAD"))
    // The wipe-and-replace tar behaviour must not regress into git mode.
    #expect(!script.contains("rm -rf"))
  }

  @Test
  func guestSyncBackScriptCommitsOnlyWhenDirty() {
    let paths = SharedCompassVMGitSSHSync.guestPaths(workspaceID: "abc-123")
    let script = SharedCompassVMGitSSHSync.guestSyncBackScript(paths: paths)
    #expect(script.contains("git diff --quiet"))
    #expect(script.contains("ls-files --others --exclude-standard"))
    #expect(script.contains("git push exchange HEAD:refs/compass/sync-back"))
  }

  // MARK: - Host-side sync commit (real git repos in /tmp)

  @Test
  func createSyncCommitReturnsHEADForCleanTree() async throws {
    let repo = try makeTempRepo()
    defer { try? FileManager.default.removeItem(at: repo) }
    let head = try git(repo, "rev-parse", "HEAD")
    let sha = try await SharedCompassVMGitSSHSync.createSyncCommit(hostRepoURL: repo)
    #expect(sha == head)
  }

  @Test
  func createSyncCommitCapturesUncommittedAndUntrackedChanges() async throws {
    let repo = try makeTempRepo()
    defer { try? FileManager.default.removeItem(at: repo) }
    try "tracked edit".write(to: repo.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
    try "new file".write(to: repo.appendingPathComponent("untracked.txt"), atomically: true, encoding: .utf8)
    try "build artifact".write(to: repo.appendingPathComponent("ignored.bin"), atomically: true, encoding: .utf8)

    let sha = try await SharedCompassVMGitSSHSync.createSyncCommit(hostRepoURL: repo)
    #expect(sha.count == 40)

    let tracked = try git(repo, "show", "\(sha):file.txt")
    #expect(tracked == "tracked edit")
    let untracked = try git(repo, "show", "\(sha):untracked.txt")
    #expect(untracked == "new file")
    // .gitignore'd paths must not travel into the guest.
    #expect(throws: (any Error).self) {
      _ = try git(repo, "show", "\(sha):ignored.bin")
    }
    // The user's index and HEAD are untouched.
    let head = try git(repo, "rev-parse", "HEAD")
    #expect(head != sha)
    let status = try git(repo, "status", "--porcelain")
    #expect(status.contains("file.txt"))
  }

  // MARK: - Watchdog scaling

  @Test
  func watchdogScalesToCommandTimeout() {
    let client = AgentVsockClient(
      transportFactory: { throw AgentRPCTransportError.guestReportedError(.init(kind: .internalError, detail: "stub")) },
      requestTimeout: 120
    )
    #expect(client.effectiveWatchdogTimeout(forCommandTimeout: 5) == 120)
    #expect(client.effectiveWatchdogTimeout(forCommandTimeout: 3600) == 3630)
  }

  // MARK: - Auto-provision gate

  @Test
  func autoProvisioningDefaultsOnAndParsesKillSwitch() {
    #expect(AgentMacOSVMBashRunner.autoProvisioningEnabled(environment: [:]))
    #expect(
      !AgentMacOSVMBashRunner.autoProvisioningEnabled(
        environment: ["COMPASS_MACOS_VM_AUTO_PROVISION": "0"]))
    #expect(
      !AgentMacOSVMBashRunner.autoProvisioningEnabled(
        environment: ["COMPASS_MACOS_VM_AUTO_PROVISION": "false"]))
    #expect(
      AgentMacOSVMBashRunner.autoProvisioningEnabled(
        environment: ["COMPASS_MACOS_VM_AUTO_PROVISION": "1"]))
  }

  // MARK: - Toolchain catalog

  @Test
  func rustIsDefaultProvisionedAndNodeIsOptional() {
    let rust = SharedVMToolchainCatalog.definition(for: .rust)
    #expect(rust.defaultProvisioned)
    #expect(rust.installableViaGenericProvisioner)
    let node = SharedVMToolchainCatalog.definition(for: .node)
    #expect(!node.defaultProvisioned)
    #expect(SharedVMToolchainCatalog.defaultProvisionedIDs.contains("rust"))
    #expect(!SharedVMToolchainCatalog.defaultProvisionedIDs.contains("node"))
  }

  @Test
  func rustInstallScriptUsesRustupAndExposesProxiesOnDefaultPATH() {
    let script = SharedVMToolchainCatalog.definition(for: .rust).renderInstallScript()
    #expect(script.contains("sh.rustup.rs"))
    #expect(script.contains("--component rustfmt --component clippy"))
    #expect(script.contains("/usr/local/bin/cargo"))
  }

  @Test
  func rustInstallScriptVerifiesAsGuestUserNotRoot() {
    let script = SharedVMToolchainCatalog.definition(for: .rust).renderInstallScript()
    // The install LaunchDaemon runs as root, but rustup proxies resolve
    // the toolchain from the invoking user's home — verification must
    // run as the guest user or it fails against /var/root/.rustup.
    #expect(
      script.contains(
        "su - \"$GUEST_USER\" -c '\(SharedVMToolchainDefinition.rustVerificationCommand)'"))
    #expect(!script.contains("if \(SharedVMToolchainDefinition.rustVerificationCommand) >"))
  }

  @Test
  func rustInstallScriptIncludesLlvmToolsForCoverage() {
    let script = SharedVMToolchainCatalog.definition(for: .rust).renderInstallScript()
    #expect(script.contains("llvm-tools-preview"))
  }

  @Test
  func cargoComponentInstallScriptsSymlinkBinariesOntoDefaultPATH() {
    for id in [SharedVMToolchainID.cargoLlvmCov, .cargoMutants] {
      let script = SharedVMToolchainCatalog.definition(for: id).renderInstallScript()
      // `cargo install` lands binaries in ~/.cargo/bin, which the agent's
      // PATH does not include — the script must link them into
      // /usr/local/bin or post-install verification (and the agent) can't
      // find them.
      #expect(script.contains("/usr/local/bin"), "toolchain \(id.rawValue) must expose binaries on the default PATH")
      #expect(script.contains("ln -sf \"$GUEST_HOME/.cargo/bin/$tool\" \"/usr/local/bin/$tool\""))
    }
  }

  // MARK: - Helpers

  private func makeTempRepo() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("compass-git-sync-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    _ = try git(url, "init")
    try "ignored.bin\n".write(to: url.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
    try "initial".write(to: url.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
    _ = try git(url, "add", "-A")
    _ = try git(url, "-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-m", "init")
    return url
  }

  @discardableResult
  private func git(_ repo: URL, _ args: String...) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = args
    process.currentDirectoryURL = repo
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()
    let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard process.terminationStatus == 0 else {
      let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
      throw NSError(
        domain: "MacOSVMGitSyncTests", code: Int(process.terminationStatus),
        userInfo: [NSLocalizedDescriptionKey: "git \(args.joined(separator: " ")) failed: \(err)"])
    }
    return out
  }
}
