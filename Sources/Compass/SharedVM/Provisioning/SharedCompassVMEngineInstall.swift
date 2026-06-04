import Foundation

enum SharedCompassVMEngineInstall {
  static let binaryGuestPath = "/usr/local/bin/compass-engine"
  static let sentinelGuestPath = "/var/db/compass/engine-installed.version"

  enum InstallError: LocalizedError, CustomStringConvertible {
    case missingBinary([String])
    case copyFailed(exitCode: Int32, stderr: String)
    case installFailed(exitCode: Int32, stderr: String)

    var description: String {
      switch self {
      case .missingBinary(let candidates):
        return "Could not locate compass-engine. Searched: \(candidates.joined(separator: ", "))"
      case .copyFailed(let exitCode, let stderr):
        return "copying compass-engine to the guest failed (exit \(exitCode)): \(stderr)"
      case .installFailed(let exitCode, let stderr):
        return "installing compass-engine in the guest failed (exit \(exitCode)): \(stderr)"
      }
    }

    var errorDescription: String? { description }
  }

  static func locateBinary(
    bundle: Bundle = .main,
    fileManager: FileManager = .default
  ) throws -> URL {
    let candidates = RustEngineLocator.candidateURLs(bundle: bundle, fileManager: fileManager)
    for url in candidates where fileManager.isExecutableFile(atPath: url.path) {
      return url
    }
    throw InstallError.missingBinary(candidates.map(\.path))
  }

  static func sshInstallCommand(
    temporaryGuestPath: String,
    binaryPath: String = binaryGuestPath,
    sentinelPath: String = sentinelGuestPath
  ) -> String {
    let quotedTemporary = SharedCompassVMGuestBridge.posixQuote(temporaryGuestPath)
    let quotedBinary = SharedCompassVMGuestBridge.posixQuote(binaryPath)
    let quotedSentinel = SharedCompassVMGuestBridge.posixQuote(sentinelPath)
    return """
      set -euo pipefail
      sudo /bin/mkdir -p \(SharedCompassVMGuestBridge.posixQuote(binaryPath.compassDirectoryComponent))
      sudo /usr/bin/install -m 0755 -o root -g wheel \(quotedTemporary) \(quotedBinary)
      /bin/rm -f \(quotedTemporary)
      sudo /bin/mkdir -p \(SharedCompassVMGuestBridge.posixQuote(sentinelPath.compassDirectoryComponent))
      \(quotedBinary) ping --repo "$HOME" --format json >/tmp/compass-engine-ping.json
      /usr/bin/python3 - <<'PY' | sudo /usr/bin/tee \(quotedSentinel) >/dev/null
      import json
      with open("/tmp/compass-engine-ping.json", "r", encoding="utf-8") as f:
          data = json.load(f)
      print(data.get("data", {}).get("version", "unknown"))
      PY
      /bin/rm -f /tmp/compass-engine-ping.json
      """
  }

  static func repairOverSSH(
    destination: String,
    options: SharedCompassVMGuestBridge.ConnectionOptions,
    fileManager: FileManager = .default
  ) async throws {
    let binaryURL = try locateBinary(fileManager: fileManager)
    let temporaryGuestPath = "/tmp/compass-engine-\(UUID().uuidString)"
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
        remoteCommand: sshInstallCommand(temporaryGuestPath: temporaryGuestPath),
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
}

private extension String {
  var compassDirectoryComponent: String {
    (self as NSString).deletingLastPathComponent
  }
}
