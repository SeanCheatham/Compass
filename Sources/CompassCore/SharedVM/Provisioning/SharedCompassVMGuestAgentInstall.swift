import Foundation

enum SharedCompassVMGuestAgentInstall {
  static let binaryGuestPath = "/usr/local/libexec/compass-guest-agent"
  static let remoteHelperGuestPath = "/usr/local/bin/git-remote-compass"
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

  static func remoteHelperInstallCommand(
    guestAgentBinaryPath: String = SharedCompassVMGuestAgentInstall.binaryGuestPath,
    remoteHelperPath: String = SharedCompassVMGuestAgentInstall.remoteHelperGuestPath
  ) -> String {
    let wrapperExecLine =
      "exec \(SharedCompassVMGuestBridge.posixQuote(guestAgentBinaryPath)) --git-remote-helper \"$@\""
    return """
      set -euo pipefail
      sudo /bin/mkdir -p \(SharedCompassVMGuestBridge.posixQuote(remoteHelperPath.directoryComponent))
      sudo /bin/rm -f \(SharedCompassVMGuestBridge.posixQuote(remoteHelperPath))
      /usr/bin/printf '%s\\n' '#!/bin/sh' \(SharedCompassVMGuestBridge.posixQuote(wrapperExecLine)) | sudo /usr/bin/tee \(SharedCompassVMGuestBridge.posixQuote(remoteHelperPath)) >/dev/null
      sudo /bin/chmod 0755 \(SharedCompassVMGuestBridge.posixQuote(remoteHelperPath))
      \(SharedCompassVMGuestBridge.posixQuote(remoteHelperPath)) --version >/dev/null
      """
  }

  static func sshRepairCommand(
    temporaryGuestPath: String,
    guestAgentBinaryPath: String = SharedCompassVMGuestAgentInstall.binaryGuestPath,
    remoteHelperPath: String = SharedCompassVMGuestAgentInstall.remoteHelperGuestPath,
    launchDaemonGuestPath: String = SharedCompassVMGuestAgentInstall.launchDaemonGuestPath,
    launchDaemonLabel: String = SharedCompassVMGuestAgentInstall.launchDaemonLabel
  ) -> String {
    let quotedTemporaryPath = SharedCompassVMGuestBridge.posixQuote(temporaryGuestPath)
    let quotedBinaryPath = SharedCompassVMGuestBridge.posixQuote(guestAgentBinaryPath)
    let quotedLaunchDaemonPath = SharedCompassVMGuestBridge.posixQuote(launchDaemonGuestPath)
    let quotedLaunchDaemonLabel = SharedCompassVMGuestBridge.posixQuote(launchDaemonLabel)
    return """
      set -euo pipefail
      sudo /bin/mkdir -p \(SharedCompassVMGuestBridge.posixQuote(guestAgentBinaryPath.directoryComponent))
      sudo /usr/bin/install -m 0755 -o root -g wheel \(quotedTemporaryPath) \(quotedBinaryPath)
      /bin/rm -f \(quotedTemporaryPath)
      \(remoteHelperInstallCommand(guestAgentBinaryPath: guestAgentBinaryPath, remoteHelperPath: remoteHelperPath))
      if [ -f \(quotedLaunchDaemonPath) ]; then
        sudo /bin/launchctl bootout system \(quotedLaunchDaemonPath) 2>/dev/null || true
        sudo /bin/launchctl bootstrap system \(quotedLaunchDaemonPath) 2>/dev/null || true
        sudo /bin/launchctl kickstart -k system/\(quotedLaunchDaemonLabel) 2>/dev/null || true
      fi
      """
  }

  static func repairOverSSH(
    destination: String,
    options: SharedCompassVMGuestBridge.ConnectionOptions,
    fileManager: FileManager = .default
  ) async throws {
    let binaryURL = try locateBundledBinary(fileManager: fileManager)
    let temporaryGuestPath = "/tmp/compass-guest-agent-\(UUID().uuidString)"
    let copy = try await ProcessRunner.run(
      executable: "/usr/bin/scp",
      arguments: SharedCompassVMGuestBridge.scpUploadArguments(
        sourcePath: binaryURL.path,
        destination: destination,
        remotePath: temporaryGuestPath,
        options: options
      ),
      timeout: 20
    )
    guard copy.exitCode == 0 else {
      throw InstallError.copyFailed(
        exitCode: copy.exitCode,
        stderr: (copy.stderr + copy.stdout).trimmingCharacters(in: .whitespacesAndNewlines)
      )
    }

    let install = try await ProcessRunner.run(
      executable: options.executablePath,
      arguments: SharedCompassVMGuestBridge.sshArguments(
        destination: destination,
        remoteCommand: sshRepairCommand(temporaryGuestPath: temporaryGuestPath),
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

  static func probeInstalledHelperOverSSH(
    destination: String,
    options: SharedCompassVMGuestBridge.ConnectionOptions,
    remoteHelperPath: String = SharedCompassVMGuestAgentInstall.remoteHelperGuestPath
  ) async -> Bool {
    let result = try? await ProcessRunner.run(
      executable: options.executablePath,
      arguments: SharedCompassVMGuestBridge.sshArguments(
        destination: destination,
        remoteCommand:
          "\(SharedCompassVMGuestBridge.posixQuote(remoteHelperPath)) --version >/dev/null",
        options: options
      ),
      timeout: 8
    )
    return result?.exitCode == 0
  }
}

extension String {
  fileprivate var directoryComponent: String {
    (self as NSString).deletingLastPathComponent
  }
}
