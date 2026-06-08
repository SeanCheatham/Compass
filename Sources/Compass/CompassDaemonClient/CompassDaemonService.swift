import Foundation

final class CompassDaemonService {
  static let shared = CompassDaemonService()

  private(set) var diagnostics: CompassDaemonDiagnostics
  private var process: Process?

  init(
    socketURL: URL = CompassDaemonService.defaultSocketURL(),
    logURL: URL = CompassDaemonService.defaultLogURL()
  ) {
    diagnostics = CompassDaemonDiagnostics(
      isEnabled: CompassRuntimeFeatureFlags().rustDaemonEnabled,
      binaryURL: nil,
      socketURL: socketURL,
      logURL: logURL,
      version: nil,
      coreVersion: nil,
      schemaVersion: nil,
      lastError: nil
    )
  }

  var client: CompassDaemonClient {
    CompassDaemonClient(socketURL: diagnostics.socketURL)
  }

  func startIfEnabled() async {
    guard diagnostics.isEnabled else { return }

    do {
      let ping = try await ensureRunningAndPing()
      diagnostics.version = ping.compassdVersion
      diagnostics.coreVersion = ping.coreVersion
      diagnostics.schemaVersion = ping.schemaVersion
      diagnostics.lastError = nil
    } catch {
      diagnostics.lastError = error.localizedDescription
    }
  }

  func shutdown() async {
    guard diagnostics.isEnabled else { return }
    do {
      try await client.shutdown()
    } catch {
      diagnostics.lastError = error.localizedDescription
    }
    if let process, process.isRunning {
      try? await Task.sleep(nanoseconds: 2_000_000_000)
      if process.isRunning {
        process.terminate()
      }
    }
  }

  private func ensureRunningAndPing() async throws -> CompassDaemonPing {
    if let ping = try? await client.ping() {
      return ping
    }

    let binaryURL = try resolveBinary()
    diagnostics.binaryURL = binaryURL

    try FileManager.default.createDirectory(
      at: diagnostics.socketURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: diagnostics.logURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    let process = Process()
    process.executableURL = binaryURL
    process.arguments = [
      "--socket", diagnostics.socketURL.path,
      "--log", diagnostics.logURL.path,
    ]
    try process.run()
    self.process = process

    let deadline = Date().addingTimeInterval(5)
    var lastError: Error?
    while Date() < deadline {
      do {
        return try await client.ping()
      } catch {
        lastError = error
        try await Task.sleep(nanoseconds: 100_000_000)
      }
    }
    throw lastError ?? CompassDaemonClientError.connectFailed("daemon did not become ready")
  }

  private func resolveBinary() throws -> URL {
    if let url = CompassDaemonLocator.locateDaemonBinary() {
      return url
    }
    throw CompassDaemonClientError.connectFailed("Could not locate compassd binary")
  }

  static func defaultSocketURL() -> URL {
    applicationSupportDirectory()
      .appending(path: "compassd.sock", directoryHint: .notDirectory)
  }

  static func defaultLogURL() -> URL {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home
      .appending(path: "Library", directoryHint: .isDirectory)
      .appending(path: "Logs", directoryHint: .isDirectory)
      .appending(path: "Compass", directoryHint: .isDirectory)
      .appending(path: "compassd.log", directoryHint: .notDirectory)
  }

  private static func applicationSupportDirectory() -> URL {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home
      .appending(path: "Library", directoryHint: .isDirectory)
      .appending(path: "Application Support", directoryHint: .isDirectory)
      .appending(path: "Compass", directoryHint: .isDirectory)
  }
}
