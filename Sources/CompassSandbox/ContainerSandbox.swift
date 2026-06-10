import Containerization
import ContainerizationArchive
import ContainerizationExtras
import ContainerizationOCI
import Foundation
import Synchronization

public struct SandboxProcessResult: Sendable, Equatable {
  public var exitCode: Int32
  public var stdout: String
  public var stderr: String

  public init(exitCode: Int32, stdout: String, stderr: String) {
    self.exitCode = exitCode
    self.stdout = stdout
    self.stderr = stderr
  }
}

public struct ContainerSandboxConfiguration: Sendable, Equatable {
  public static let defaultRuntimeImage = "docker.io/library/node:22-bookworm"
  public static let defaultInitfsReference = "ghcr.io/apple/containerization/vminit:0.33.4"
  public static let defaultPnpmVersion = "9.15.4"
  public static let defaultKernelURL =
    "https://github.com/kata-containers/kata-containers/releases/download/3.26.0/kata-static-3.26.0-arm64.tar.zst"
  public static let defaultKernelPathInArchive =
    "opt/kata/share/kata-containers/vmlinux.container"
  public static let defaultWorkspacePath = "/workspace"

  public var runtimeImage: String
  public var initfsReference: String
  public var pnpmVersion: String
  public var containerWorkspacePath: String
  public var cpuCount: Int
  public var memorySizeBytes: UInt64
  public var rootfsSizeBytes: UInt64
  public var maxCapturedOutputBytes: Int
  public var stateRoot: URL
  public var explicitKernelURL: URL?
  public var defaultKernelURL: String
  public var defaultKernelPathInArchive: String

  public init(
    runtimeImage: String = Self.defaultRuntimeImage,
    initfsReference: String = Self.defaultInitfsReference,
    pnpmVersion: String = Self.defaultPnpmVersion,
    containerWorkspacePath: String = Self.defaultWorkspacePath,
    cpuCount: Int = 4,
    memorySizeBytes: UInt64 = 2 * 1024 * 1024 * 1024,
    rootfsSizeBytes: UInt64 = 8 * 1024 * 1024 * 1024,
    maxCapturedOutputBytes: Int = 1_000_000,
    stateRoot: URL = Self.defaultStateRoot(),
    explicitKernelURL: URL? = ProcessInfo.processInfo.environment["COMPASS_CONTAINER_KERNEL"].map {
      URL(fileURLWithPath: $0)
    },
    defaultKernelURL: String = Self.defaultKernelURL,
    defaultKernelPathInArchive: String = Self.defaultKernelPathInArchive
  ) {
    self.runtimeImage = runtimeImage
    self.initfsReference = initfsReference
    self.pnpmVersion = pnpmVersion
    self.containerWorkspacePath = containerWorkspacePath
    self.cpuCount = cpuCount
    self.memorySizeBytes = memorySizeBytes
    self.rootfsSizeBytes = rootfsSizeBytes
    self.maxCapturedOutputBytes = max(1, maxCapturedOutputBytes)
    self.stateRoot = stateRoot.standardizedFileURL
    self.explicitKernelURL = explicitKernelURL?.standardizedFileURL
    self.defaultKernelURL = defaultKernelURL
    self.defaultKernelPathInArchive = defaultKernelPathInArchive
  }

  public static func defaultStateRoot() -> URL {
    if let override = ProcessInfo.processInfo.environment["COMPASS_CONTAINER_STATE_ROOT"],
      !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return URL(fileURLWithPath: override).standardizedFileURL
    }
    let applicationSupport =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(
        "Library/Application Support",
        isDirectory: true
      )
    return applicationSupport
      .appendingPathComponent("Compass", isDirectory: true)
      .appendingPathComponent("ContainerSandbox", isDirectory: true)
      .standardizedFileURL
  }
}

public enum ContainerSandboxError: Error, LocalizedError, Equatable {
  case unsupportedHost
  case missingKernel(URL)
  case invalidKernelURL(String)
  case kernelDownloadFailed(String)
  case pathOutsideWorkspace(path: String, root: String)
  case infrastructure(String)

  public var errorDescription: String? {
    switch self {
    case .unsupportedHost:
      return "Apple Containerization requires Apple silicon and macOS 26 or newer."
    case .missingKernel(let url):
      return "COMPASS_CONTAINER_KERNEL points to a missing file: \(url.path)"
    case .invalidKernelURL(let url):
      return "Invalid container kernel download URL: \(url)"
    case .kernelDownloadFailed(let detail):
      return "Container kernel download failed: \(detail)"
    case .pathOutsideWorkspace(let path, let root):
      return "Working directory \(path) is outside the mounted repository \(root)."
    case .infrastructure(let detail):
      return detail
    }
  }
}

public struct ContainerWorkspacePathMapper: Sendable, Equatable {
  public var hostRoot: URL
  public var containerRoot: String

  public init(hostRoot: URL, containerRoot: String = ContainerSandboxConfiguration.defaultWorkspacePath) {
    self.hostRoot = hostRoot.standardizedFileURL
    self.containerRoot = containerRoot.hasSuffix("/")
      ? String(containerRoot.dropLast())
      : containerRoot
  }

  public func containerPath(for hostURL: URL) throws -> String {
    let standardizedHost = hostURL.standardizedFileURL.path
    let root = hostRoot.standardizedFileURL.path
    guard standardizedHost == root || standardizedHost.hasPrefix(root + "/") else {
      throw ContainerSandboxError.pathOutsideWorkspace(path: standardizedHost, root: root)
    }
    if standardizedHost == root {
      return containerRoot
    }
    let relative = String(standardizedHost.dropFirst(root.count + 1))
    return containerRoot + "/" + relative
  }
}

public struct ContainerSandboxRunRequest: Sendable, Equatable {
  public var command: String
  public var hostRepoRoot: URL
  public var hostWorkingDirectory: URL
  public var timeout: TimeInterval
  public var label: String

  public init(
    command: String,
    hostRepoRoot: URL,
    hostWorkingDirectory: URL,
    timeout: TimeInterval,
    label: String = "compass-command"
  ) {
    self.command = command
    self.hostRepoRoot = hostRepoRoot.standardizedFileURL
    self.hostWorkingDirectory = hostWorkingDirectory.standardizedFileURL
    self.timeout = timeout
    self.label = label
  }
}

public struct ContainerRuntimeStatus: Sendable, Equatable {
  public var ok: Bool
  public var message: String
  public var stateRoot: URL
  public var runtimeImage: String
  public var initfsReference: String
  public var kernelURL: URL?

  public init(
    ok: Bool,
    message: String,
    stateRoot: URL,
    runtimeImage: String,
    initfsReference: String,
    kernelURL: URL?
  ) {
    self.ok = ok
    self.message = message
    self.stateRoot = stateRoot
    self.runtimeImage = runtimeImage
    self.initfsReference = initfsReference
    self.kernelURL = kernelURL
  }
}

public struct ContainerizedLinuxSandbox: Sendable {
  public static let shared = ContainerizedLinuxSandbox()

  private let configuration: ContainerSandboxConfiguration

  public init(configuration: ContainerSandboxConfiguration = ContainerSandboxConfiguration()) {
    self.configuration = configuration
  }

  public var stateRoot: URL {
    configuration.stateRoot
  }

  public func smokeTest() async -> ContainerRuntimeStatus {
    do {
      try Self.checkHostSupport()
      let kernel = try await ensureKernel()
      let scratch = configuration.stateRoot.appendingPathComponent("smoke", isDirectory: true)
      let src = scratch.appendingPathComponent("src", isDirectory: true)
      try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
      try """
        {
          "name": "compass-container-smoke",
          "private": true,
          "type": "module",
          "scripts": {
            "verify": "node index.js"
          }
        }
        """.write(to: scratch.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
      try #"console.log("COMPASS_CONTAINER_SMOKE_OK");"#
        .write(to: scratch.appendingPathComponent("index.js"), atomically: true, encoding: .utf8)
      let result = try await run(
        ContainerSandboxRunRequest(
          command: "pnpm verify",
          hostRepoRoot: scratch,
          hostWorkingDirectory: scratch,
          timeout: 120,
          label: "smoke"
        )
      )
      let ok = result.exitCode == 0 && result.stdout.contains("COMPASS_CONTAINER_SMOKE_OK")
      return ContainerRuntimeStatus(
        ok: ok,
        message: ok ? "Containerized Linux runtime is ready." : result.stderr + result.stdout,
        stateRoot: configuration.stateRoot,
        runtimeImage: configuration.runtimeImage,
        initfsReference: configuration.initfsReference,
        kernelURL: kernel
      )
    } catch {
      let message = Self.runtimeFailureMessage(for: error)
      return ContainerRuntimeStatus(
        ok: false,
        message: message,
        stateRoot: configuration.stateRoot,
        runtimeImage: configuration.runtimeImage,
        initfsReference: configuration.initfsReference,
        kernelURL: nil
      )
    }
  }

  public func resetCache() throws {
    guard FileManager.default.fileExists(atPath: configuration.stateRoot.path) else { return }
    try FileManager.default.removeItem(at: configuration.stateRoot)
  }

  public func run(_ request: ContainerSandboxRunRequest) async throws -> SandboxProcessResult {
    try Self.checkHostSupport()
    let mapper = ContainerWorkspacePathMapper(
      hostRoot: request.hostRepoRoot,
      containerRoot: configuration.containerWorkspacePath
    )
    let containerWorkingDirectory = try mapper.containerPath(for: request.hostWorkingDirectory)
    let kernelURL = try await ensureKernel()
    let contentStore = try LocalContentStore(
      path: configuration.stateRoot.appendingPathComponent("content", isDirectory: true)
    )
    let imageStore = try ImageStore(path: configuration.stateRoot, contentStore: contentStore)
    let network = try VmnetNetwork()
    var manager = try await ContainerManager(
      kernel: Kernel(path: kernelURL, platform: .linuxArm),
      initfsReference: configuration.initfsReference,
      imageStore: imageStore,
      network: network
    )
    let containerID =
      "compass-\(request.label.sanitizedContainerIDComponent)-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)"
    let container = try await manager.create(
      containerID,
      reference: configuration.runtimeImage,
      rootfsSizeInBytes: configuration.rootfsSizeBytes,
      networking: true
    ) { config in
      config.cpus = configuration.cpuCount
      config.memoryInBytes = configuration.memorySizeBytes
      config.process.arguments = ["/bin/sleep", "infinity"]
      config.process.workingDirectory = "/"
      config.process.capabilities = .allCapabilities
      config.useInit = true
      config.mounts.append(
        Mount.share(
          source: request.hostRepoRoot.path,
          destination: configuration.containerWorkspacePath
        )
      )
    }

    do {
      try await container.create()
      try await container.start()
      let result = try await runCommand(
        request.command,
        containerWorkingDirectory: containerWorkingDirectory,
        timeout: request.timeout,
        in: container
      )
      try await container.stop()
      try manager.delete(containerID)
      return result
    } catch {
      try? await container.stop()
      try? manager.delete(containerID)
      throw error
    }
  }

  private func runCommand(
    _ command: String,
    containerWorkingDirectory: String,
    timeout: TimeInterval,
    in container: LinuxContainer
  ) async throws -> SandboxProcessResult {
    let stdout = CapturingWriter(
      label: "stdout",
      maxBytes: configuration.maxCapturedOutputBytes
    )
    let stderr = CapturingWriter(
      label: "stderr",
      maxBytes: configuration.maxCapturedOutputBytes
    )
    let script = bootstrapScript(
      userCommand: command,
      containerWorkingDirectory: containerWorkingDirectory
    )
    let process = try await container.exec("command-\(UUID().uuidString)") { config in
      config.arguments = ["/bin/bash", "-lc", script]
      config.environmentVariables = [
        "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
        "HOME=/root",
        "COREPACK_HOME=/tmp/corepack",
      ]
      config.workingDirectory = self.configuration.containerWorkspacePath
      config.stdout = stdout
      config.stderr = stderr
      config.capabilities = .allCapabilities
    }

    try await process.start()
    do {
      let status = try await process.wait(timeoutInSeconds: Int64(max(1, ceil(timeout))))
      try await process.delete()
      return SandboxProcessResult(
        exitCode: status.exitCode,
        stdout: stdout.string,
        stderr: stderr.string
      )
    } catch {
      try? await process.kill(.kill)
      try? await process.delete()
      var stderrText = stderr.string
      if !stderrText.isEmpty && !stderrText.hasSuffix("\n") {
        stderrText += "\n"
      }
      stderrText += "[timed out after \(Int(timeout * 1000)) ms]"
      return SandboxProcessResult(exitCode: 124, stdout: stdout.string, stderr: stderrText)
    }
  }

  private func bootstrapScript(userCommand: String, containerWorkingDirectory: String) -> String {
    """
    set -euo pipefail
    if ! grep -Eq '(^|[[:space:]])localhost([[:space:]]|$)' /etc/hosts 2>/dev/null; then
      printf '\\n127.0.0.1 localhost\\n::1 localhost ip6-localhost ip6-loopback\\n' >> /etc/hosts || true
    fi
    cd \(shellQuote(containerWorkingDirectory))
    command -v node >/dev/null
    command -v npm >/dev/null
    command -v git >/dev/null
    corepack enable
    corepack prepare pnpm@\(shellQuote(configuration.pnpmVersion)) --activate
    command -v pnpm >/dev/null
    \(userCommand)
    """
  }

  private func ensureKernel() async throws -> URL {
    if let explicit = configuration.explicitKernelURL {
      guard FileManager.default.fileExists(atPath: explicit.path) else {
        throw ContainerSandboxError.missingKernel(explicit)
      }
      return explicit
    }

    let installedKernelDir = URL(fileURLWithPath: NSHomeDirectory())
      .appendingPathComponent("Library/Application Support/com.apple.container/kernels")
    if let installedKernel = newestKernel(in: installedKernelDir) {
      return installedKernel
    }

    let kernelDir = configuration.stateRoot.appendingPathComponent("kernel", isDirectory: true)
    let kernelURL = kernelDir.appendingPathComponent("vmlinux")
    if FileManager.default.fileExists(atPath: kernelURL.path) {
      return kernelURL
    }

    try FileManager.default.createDirectory(at: kernelDir, withIntermediateDirectories: true)
    let archiveURL = kernelDir.appendingPathComponent("kata-static-arm64.tar.zst")
    try await downloadFile(from: configuration.defaultKernelURL, to: archiveURL)
    try extractKernel(from: archiveURL, to: kernelURL)
    try? FileManager.default.removeItem(at: archiveURL)
    return kernelURL
  }

  private func newestKernel(in directory: URL) -> URL? {
    guard
      let contents = try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return nil
    }
    return contents
      .filter { $0.lastPathComponent.hasPrefix("vmlinux") }
      .sorted { lhs, rhs in
        let lhsDate =
          (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?
          .contentModificationDate ?? .distantPast
        let rhsDate =
          (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?
          .contentModificationDate ?? .distantPast
        return lhsDate > rhsDate
      }
      .first
  }

  private func downloadFile(from urlString: String, to destination: URL) async throws {
    guard let url = URL(string: urlString) else {
      throw ContainerSandboxError.invalidKernelURL(urlString)
    }
    let (temporaryURL, response) = try await URLSession.shared.download(from: url)
    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
      throw ContainerSandboxError.kernelDownloadFailed("HTTP \(http.statusCode) for \(urlString)")
    }
    if FileManager.default.fileExists(atPath: destination.path) {
      try FileManager.default.removeItem(at: destination)
    }
    try FileManager.default.moveItem(at: temporaryURL, to: destination)
  }

  private func extractKernel(from archive: URL, to destination: URL) throws {
    var target = configuration.defaultKernelPathInArchive
    var reader = try ArchiveReader(file: archive)
    var (entry, data) = try reader.extractFile(path: target)
    if entry.fileType == .symbolicLink, let symlinkTarget = entry.symlinkTarget {
      reader = try ArchiveReader(file: archive)
      target =
        URL(filePath: target)
        .deletingLastPathComponent()
        .appending(path: symlinkTarget)
        .standardized
        .relativePath
      let (_, resolvedData) = try reader.extractFile(path: target)
      data = resolvedData
    }
    try data.write(to: destination, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
  }

  private static func checkHostSupport() throws {
    guard #available(macOS 26, *) else {
      throw ContainerSandboxError.unsupportedHost
    }
    #if arch(arm64)
    return
    #else
    throw ContainerSandboxError.unsupportedHost
    #endif
  }

  private static func runtimeFailureMessage(for error: Error) -> String {
    let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    let lowercased = message.lowercased()
    let looksLikeSigningFailure =
      lowercased.contains("entitlement")
      || lowercased.contains("not entitled")
      || lowercased.contains("operation not permitted")
      || lowercased.contains("permission")
      || lowercased.contains("virtualization")
    guard looksLikeSigningFailure else { return message }
    return """
      \(message)
      Ensure compass-cli is signed with App/CompassCLI.entitlements by running scripts/build-cli-local.sh. Apple Containerization requires the com.apple.security.virtualization entitlement.
      """
  }
}

final class CapturingWriter: Writer, Sendable {
  private struct State: Sendable {
    var data = Data()
    var truncatedBytes = 0
  }

  private let label: String
  private let maxBytes: Int
  private let storage = Mutex(State())

  init(label: String, maxBytes: Int) {
    self.label = label
    self.maxBytes = max(1, maxBytes)
  }

  var string: String {
    let state = storage.withLock { $0 }
    var text = String(data: state.data, encoding: .utf8) ?? String(decoding: state.data, as: UTF8.self)
    if state.truncatedBytes > 0 {
      if !text.isEmpty && !text.hasSuffix("\n") {
        text += "\n"
      }
      text += "... [\(label) truncated after \(maxBytes) bytes; dropped \(state.truncatedBytes) bytes]"
    }
    return text
  }

  func write(_ data: Data) throws {
    guard !data.isEmpty else { return }
    storage.withLock { state in
      let remaining = maxBytes - state.data.count
      if remaining > 0 {
        state.data.append(contentsOf: data.prefix(remaining))
      }
      if data.count > remaining {
        state.truncatedBytes += data.count - max(0, remaining)
      }
    }
  }

  func close() throws {}
}

private func shellQuote(_ value: String) -> String {
  "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

extension String {
  fileprivate var sanitizedContainerIDComponent: String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    var output = ""
    for scalar in unicodeScalars {
      if allowed.contains(scalar) {
        output.unicodeScalars.append(scalar)
      } else {
        output.append("-")
      }
    }
    let trimmed = output.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
    return trimmed.isEmpty ? "run" : String(trimmed.prefix(32))
  }
}
