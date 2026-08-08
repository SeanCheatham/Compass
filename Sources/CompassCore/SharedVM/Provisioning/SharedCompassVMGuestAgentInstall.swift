import CryptoKit
import Foundation

enum SharedCompassVMGuestAgentInstall {
  static let binaryGuestPath = "/usr/local/libexec/compass-guest-agent"
  static let launchDaemonGuestPath =
    "/Library/LaunchDaemons/com.seancheatham.Compass.guest-agent.plist"
  static let launchDaemonLabel = "com.seancheatham.Compass.guest-agent"

  enum InstallError: LocalizedError, CustomStringConvertible {
    case missingBundledBinary([String])
    case copyFailed(exitCode: Int32, stderr: String)
    case installFailed(exitCode: Int32, stderr: String)

    var description: String {
      switch self {
      case .missingBundledBinary(let candidates):
        return
          "Could not locate CompassGuestAgent binary. Searched: \(candidates.joined(separator: ", "))"
      case .copyFailed(let exitCode, let stderr):
        return "copying CompassGuestAgent to the guest failed (exit \(exitCode)): \(stderr)"
      case .installFailed(let exitCode, let stderr):
        return "installing CompassGuestAgent in the guest failed (exit \(exitCode)): \(stderr)"
      }
    }

    var errorDescription: String? { description }
  }

  static func locateBundledBinary(
    bundle: Bundle = .main,
    fileManager: FileManager = .default
  ) throws -> URL {
    let executableName = "CompassGuestAgent"
    var candidates: [URL] = []
    if let executable = bundle.executableURL {
      candidates.append(
        executable.deletingLastPathComponent().appendingPathComponent(executableName)
      )
    }
    candidates.append(bundle.bundleURL.appendingPathComponent(executableName))
    candidates.append(bundle.bundleURL.appendingPathComponent("Contents/MacOS/\(executableName)"))
    for url in candidates where fileManager.isExecutableFile(atPath: url.path) {
      return url
    }
    throw InstallError.missingBundledBinary(candidates.map(\.path))
  }

  /// LaunchDaemon plist planted/repaired into the guest. Kept in sync with
  /// `SharedCompassVMHeadlessFirstBoot.renderGuestAgentLaunchDaemonPlist`.
  static func launchDaemonPlistContents(
    binaryGuestPath: String = SharedCompassVMGuestAgentInstall.binaryGuestPath,
    launchDaemonLabel: String = SharedCompassVMGuestAgentInstall.launchDaemonLabel,
    guestUserName: String = SharedCompassVMBundle.State.defaultGuestUserName
  ) -> String {
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTD/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Label</key>
        <string>\(launchDaemonLabel)</string>
        <key>ProgramArguments</key>
        <array>
            <string>\(binaryGuestPath)</string>
        </array>
        <key>UserName</key>
        <string>\(guestUserName)</string>
        <key>RunAtLoad</key>
        <true/>
        <key>KeepAlive</key>
        <true/>
        <key>StandardInPath</key>
        <string>/dev/null</string>
        <key>StandardOutPath</key>
        <string>/tmp/compass-guest-agent.log</string>
        <key>StandardErrorPath</key>
        <string>/tmp/compass-guest-agent.log</string>
    </dict>
    </plist>
    """
  }

  static func sshRepairCommand(
    temporaryGuestBinaryPath: String,
    temporaryGuestPlistPath: String,
    guestAgentBinaryPath: String = SharedCompassVMGuestAgentInstall.binaryGuestPath,
    launchDaemonGuestPath: String = SharedCompassVMGuestAgentInstall.launchDaemonGuestPath,
    launchDaemonLabel: String = SharedCompassVMGuestAgentInstall.launchDaemonLabel
  ) -> String {
    let quotedTemporaryBinary = SharedCompassVMGuestBridge.posixQuote(temporaryGuestBinaryPath)
    let quotedTemporaryPlist = SharedCompassVMGuestBridge.posixQuote(temporaryGuestPlistPath)
    let quotedBinaryPath = SharedCompassVMGuestBridge.posixQuote(guestAgentBinaryPath)
    let quotedLaunchDaemonPath = SharedCompassVMGuestBridge.posixQuote(launchDaemonGuestPath)
    let quotedLaunchDaemonLabel = SharedCompassVMGuestBridge.posixQuote(launchDaemonLabel)
    return """
      set -euo pipefail
      sudo /bin/mkdir -p \(SharedCompassVMGuestBridge.posixQuote(guestAgentBinaryPath.directoryComponent))
      sudo /usr/bin/install -m 0755 -o root -g wheel \(quotedTemporaryBinary) \(quotedBinaryPath)
      /bin/rm -f \(quotedTemporaryBinary)
      sudo /bin/mkdir -p \(SharedCompassVMGuestBridge.posixQuote(launchDaemonGuestPath.directoryComponent))
      sudo /usr/bin/install -m 0644 -o root -g wheel \(quotedTemporaryPlist) \(quotedLaunchDaemonPath)
      /bin/rm -f \(quotedTemporaryPlist)
      sudo /bin/launchctl bootout system \(quotedLaunchDaemonPath) 2>/dev/null || true
      sudo /bin/launchctl bootstrap system \(quotedLaunchDaemonPath) 2>/dev/null || true
      sudo /bin/launchctl kickstart -k system/\(quotedLaunchDaemonLabel) 2>/dev/null || true
      """
  }

  static func repairOverSSH(
    destination: String,
    options: SharedCompassVMGuestBridge.ConnectionOptions,
    fileManager: FileManager = .default
  ) async throws {
    let binaryURL = try locateBundledBinary(fileManager: fileManager)
    let temporaryGuestBinaryPath = "/tmp/compass-guest-agent-\(UUID().uuidString)"
    let temporaryGuestPlistPath = "/tmp/compass-guest-agent-plist-\(UUID().uuidString)"
    let copyBinary = try await ProcessRunner.run(
      executable: "/usr/bin/scp",
      arguments: SharedCompassVMGuestBridge.scpUploadArguments(
        sourcePath: binaryURL.path,
        destination: destination,
        remotePath: temporaryGuestBinaryPath,
        options: options
      ),
      timeout: 20
    )
    guard copyBinary.exitCode == 0 else {
      throw InstallError.copyFailed(
        exitCode: copyBinary.exitCode,
        stderr: (copyBinary.stderr + copyBinary.stdout).trimmingCharacters(
          in: .whitespacesAndNewlines)
      )
    }

    let plistURL = fileManager.temporaryDirectory
      .appendingPathComponent("compass-guest-agent-\(UUID().uuidString).plist")
    try launchDaemonPlistContents().write(to: plistURL, atomically: true, encoding: .utf8)
    defer { try? fileManager.removeItem(at: plistURL) }

    let copyPlist = try await ProcessRunner.run(
      executable: "/usr/bin/scp",
      arguments: SharedCompassVMGuestBridge.scpUploadArguments(
        sourcePath: plistURL.path,
        destination: destination,
        remotePath: temporaryGuestPlistPath,
        options: options
      ),
      timeout: 20
    )
    guard copyPlist.exitCode == 0 else {
      throw InstallError.copyFailed(
        exitCode: copyPlist.exitCode,
        stderr: (copyPlist.stderr + copyPlist.stdout).trimmingCharacters(
          in: .whitespacesAndNewlines)
      )
    }

    let install = try await ProcessRunner.run(
      executable: options.executablePath,
      arguments: SharedCompassVMGuestBridge.sshArguments(
        destination: destination,
        remoteCommand: sshRepairCommand(
          temporaryGuestBinaryPath: temporaryGuestBinaryPath,
          temporaryGuestPlistPath: temporaryGuestPlistPath
        ),
        options: options
      ),
      timeout: 30
    )
    guard install.exitCode == 0 else {
      throw InstallError.installFailed(
        exitCode: install.exitCode,
        stderr: (install.stderr + install.stdout).trimmingCharacters(in: .whitespacesAndNewlines)
      )
    }
  }

  /// SHA-256 of the bundled agent binary the host would plant.
  static func hostBinarySHA256(fileManager: FileManager = .default) throws -> String {
    let data = try Data(contentsOf: locateBundledBinary(fileManager: fileManager))
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  /// True when the guest's planted agent binary is byte-identical to the
  /// host's bundled one. The guest agent answers vsock probes even when
  /// it's an older build, so readiness alone can't drive updates — the
  /// hash comparison is what triggers a replant after a Compass upgrade
  /// changes the agent.
  static func installedAgentMatchesHost(
    destination: String,
    options: SharedCompassVMGuestBridge.ConnectionOptions,
    fileManager: FileManager = .default
  ) async -> Bool {
    guard let hostHash = try? hostBinarySHA256(fileManager: fileManager) else { return false }
    let result = try? await ProcessRunner.run(
      executable: options.executablePath,
      arguments: SharedCompassVMGuestBridge.sshArguments(
        destination: destination,
        remoteCommand:
          "shasum -a 256 \(SharedCompassVMGuestBridge.posixQuote(binaryGuestPath)) | awk '{print $1}'",
        options: options
      ),
      timeout: 8
    )
    guard let result, result.exitCode == 0 else { return false }
    return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == hostHash
  }
}

extension String {
  fileprivate var directoryComponent: String {
    (self as NSString).deletingLastPathComponent
  }
}
