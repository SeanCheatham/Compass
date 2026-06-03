import AppKit
import Darwin
import Foundation

struct RustFactorySmokeOptions: Equatable {
  static let flag = "--compass-rust-factory-smoke"
  static let projectDirFlag = "--compass-rust-factory-smoke-project"
  static let reportFlag = "--compass-rust-factory-smoke-report"
  static let timeoutFlag = "--compass-rust-factory-smoke-timeout"

  var projectURL: URL
  var reportURL: URL
  var timeoutSeconds: TimeInterval

  static func parse(
    arguments: [String] = CommandLine.arguments,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> RustFactorySmokeOptions? {
    guard arguments.contains(flag) else { return nil }

    let projectPath =
      value(after: projectDirFlag, in: arguments)
      ?? environment["COMPASS_RUST_FACTORY_SMOKE_PROJECT"]
    let reportPath =
      value(after: reportFlag, in: arguments)
      ?? environment["COMPASS_RUST_FACTORY_SMOKE_REPORT"]
    let timeoutText =
      value(after: timeoutFlag, in: arguments)
      ?? environment["COMPASS_RUST_FACTORY_SMOKE_TIMEOUT"]

    let projectURL =
      projectPath.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
      ?? FileManager.default.temporaryDirectory
        .appending(path: "CompassRustFactorySmoke-\(UUID().uuidString)", directoryHint: .isDirectory)
    let reportURL =
      reportPath.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
      ?? FileManager.default.temporaryDirectory
        .appending(path: "compass-rust-factory-smoke-\(UUID().uuidString).json")
    let timeoutSeconds = timeoutText.flatMap(TimeInterval.init) ?? 20 * 60

    return RustFactorySmokeOptions(
      projectURL: projectURL.standardizedFileURL,
      reportURL: reportURL.standardizedFileURL,
      timeoutSeconds: max(30, timeoutSeconds)
    )
  }

  private static func value(after flag: String, in arguments: [String]) -> String? {
    for index in arguments.indices where arguments[index] == flag {
      let next = arguments.index(after: index)
      guard arguments.indices.contains(next) else { return nil }
      return arguments[next]
    }
    return nil
  }
}

@MainActor
enum RustFactorySmokeBootstrap {
  private static var started = false

  static func startIfRequested() {
    guard RustFactorySmokeOptions.parse() != nil, !started else { return }
    started = true
    Task { @MainActor in
      let model = AppModel()
      await model.bootstrap()
      await RustFactorySmoke.runIfRequested(model: model)
    }
  }
}

@MainActor
enum RustFactorySmoke {
  private static var started = false

  static func runIfRequested(model: AppModel) async {
    guard let options = RustFactorySmokeOptions.parse(), !started else { return }
    started = true

    let exitCode: Int32
    do {
      try await run(options: options, model: model)
      exitCode = 0
    } catch {
      let report = RustFactorySmokeReport(
        status: .failed,
        projectPath: options.projectURL.path,
        guestWorkspacePath: nil,
        sshDestination: nil,
        reportPath: options.reportURL.path,
        screenshotPath: nil,
        commands: [],
        error: String(describing: error)
      )
      if !FileManager.default.fileExists(atPath: options.reportURL.path) {
        try? writeReport(report, to: options.reportURL)
      }
      log("Rust factory smoke failed: \(error)")
      exitCode = 1
    }

    await SharedCompassVM.shared.stop()
    Darwin.exit(exitCode)
  }

  private static func run(options: RustFactorySmokeOptions, model: AppModel) async throws {
    var reports: [RustFactorySmokeCommandReport] = []
    var guestWorkspacePath: String?
    var sshDestination: String?
    var screenshotURL: URL?

    do {
      try await runChecked(
        options: options,
        model: model,
        reports: &reports,
        guestWorkspacePath: &guestWorkspacePath,
        sshDestination: &sshDestination,
        screenshotURL: &screenshotURL
      )
    } catch {
      let report = RustFactorySmokeReport(
        status: .failed,
        projectPath: options.projectURL.path,
        guestWorkspacePath: guestWorkspacePath,
        sshDestination: sshDestination,
        reportPath: options.reportURL.path,
        screenshotPath: screenshotURL?.path,
        commands: reports,
        error: String(describing: error)
      )
      try? writeReport(report, to: options.reportURL)
      throw error
    }
  }

  private static func runChecked(
    options: RustFactorySmokeOptions,
    model: AppModel,
    reports: inout [RustFactorySmokeCommandReport],
    guestWorkspacePath: inout String?,
    sshDestination: inout String?,
    screenshotURL: inout URL?
  ) async throws {
    log("Rust factory smoke: preparing \(options.projectURL.path)")
    try await AppModel.initializeGeneratedRustProject(at: options.projectURL)

    log("Rust factory smoke: starting Shared VM")
    try await model.sharedVMHost.warmup()
    guard model.sharedVMHost.bundle.existsOnDisk() else {
      throw RustFactorySmokeError.sharedVMNotProvisioned
    }
    try await model.sharedVMHost.start()
    sshDestination = try await waitForReady(host: model.sharedVMHost, timeout: 5 * 60)

    let project = CompassProject(repoURL: options.projectURL)
    try await project.refreshFromWorkspace(requireStorageRoot: false)
    try await project.ensurePersistentGuestWorkspace(
      forHostRepo: options.projectURL,
      forceRefresh: true
    )
    let launchPlan = project.agentLaunchPlan(for: options.projectURL)
    guard case .sharedVM(let route) = launchPlan.effectiveRoute else {
      throw RustFactorySmokeError.sharedVMRouteUnavailable(launchPlan.routeDetail())
    }
    guestWorkspacePath = route.guestWorkspacePath

    var visualOutput = ""
    for command in [
      "cargo fmt --all --check",
      "cargo clippy --workspace --all-targets --all-features -- -D warnings",
      "cargo test --workspace --all-features",
      "cargo build --workspace",
      RustProjectScaffold.visualVerifyCommand,
    ] {
      let commandRun = try await runCommand(
        command,
        project: project,
        hostWorkingDirectory: options.projectURL,
        launchPlan: launchPlan,
        timeoutSeconds: options.timeoutSeconds
      )
      reports.append(commandRun.report)
      if command == RustProjectScaffold.visualVerifyCommand {
        visualOutput = commandRun.rawOutput
      }
      if commandRun.report.exitCode != 0 {
        throw RustFactorySmokeError.commandFailed(commandRun.report)
      }
    }

    screenshotURL = try writeScreenshotIfPresent(
      from: visualOutput,
      nextTo: options.reportURL
    )

    let report = RustFactorySmokeReport(
      status: .passed,
      projectPath: options.projectURL.path,
      guestWorkspacePath: guestWorkspacePath,
      sshDestination: sshDestination,
      reportPath: options.reportURL.path,
      screenshotPath: screenshotURL?.path,
      commands: reports,
      error: nil
    )
    try writeReport(report, to: options.reportURL)
    log("Rust factory smoke passed. Report: \(options.reportURL.path)")
  }

  private static func runCommand(
    _ command: String,
    project: CompassProject,
    hostWorkingDirectory: URL,
    launchPlan: AgentExecutionLaunchPlan,
    timeoutSeconds: TimeInterval
  ) async throws -> RustFactorySmokeCommandRun {
    log("Rust factory smoke: \(command)")
    let startedAt = Date()
    let result = try await project.runVerifyCommand(
      command: command,
      hostWorkingDirectory: hostWorkingDirectory,
      timeoutSeconds: timeoutSeconds,
      launchPlan: launchPlan
    )
    let shouldRedactVisualOutput = command == RustProjectScaffold.visualVerifyCommand
    let stdoutForReport =
      shouldRedactVisualOutput
      ? RustDesktopVisualVerification.redactedOutput(result.stdout)
      : result.stdout
    let stderrForReport =
      shouldRedactVisualOutput
      ? RustDesktopVisualVerification.redactedOutput(result.stderr)
      : result.stderr
    let report = RustFactorySmokeCommandReport(
      command: command,
      exitCode: result.exitCode,
      durationSeconds: Date().timeIntervalSince(startedAt),
      stdoutTail: tail(stdoutForReport, limit: 6000),
      stderrTail: tail(stderrForReport, limit: 6000)
    )
    return RustFactorySmokeCommandRun(
      report: report,
      rawOutput: "\(result.stdout)\n\(result.stderr)"
    )
  }

  private static func waitForReady(
    host: SharedCompassVM,
    timeout: TimeInterval
  ) async throws -> String {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      switch host.readiness {
      case .ready(let sshDestination):
        return sshDestination
      case .unavailable(let reason):
        throw RustFactorySmokeError.sharedVMUnavailable(reason)
      case .error(let detail):
        throw RustFactorySmokeError.sharedVMError(detail)
      default:
        try await Task.sleep(nanoseconds: 1_000_000_000)
      }
    }
    throw RustFactorySmokeError.sharedVMReadyTimeout(String(describing: host.readiness))
  }

  private static func writeScreenshotIfPresent(
    from output: String,
    nextTo reportURL: URL
  ) throws -> URL? {
    guard let data = RustDesktopVisualVerification.screenshotData(from: output) else {
      return nil
    }
    let screenshotURL = reportURL.deletingPathExtension().appendingPathExtension("png")
    try FileManager.default.createDirectory(
      at: screenshotURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try data.write(to: screenshotURL, options: .atomic)
    return screenshotURL
  }

  private static func writeReport(_ report: RustFactorySmokeReport, to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(report).write(to: url, options: .atomic)
  }

  private static func log(_ message: String) {
    FileHandle.standardError.write(Data("[compass-smoke] \(message)\n".utf8))
  }

  private static func tail(_ text: String, limit: Int) -> String {
    guard text.count > limit else { return text }
    return String(text.suffix(limit))
  }
}

struct RustFactorySmokeReport: Codable, Equatable {
  enum Status: String, Codable {
    case passed
    case failed
  }

  var status: Status
  var projectPath: String
  var guestWorkspacePath: String?
  var sshDestination: String?
  var reportPath: String
  var screenshotPath: String?
  var commands: [RustFactorySmokeCommandReport]
  var error: String?
}

struct RustFactorySmokeCommandReport: Codable, Equatable {
  var command: String
  var exitCode: Int32
  var durationSeconds: TimeInterval
  var stdoutTail: String
  var stderrTail: String
}

private struct RustFactorySmokeCommandRun {
  var report: RustFactorySmokeCommandReport
  var rawOutput: String
}

enum RustFactorySmokeError: Error, CustomStringConvertible {
  case sharedVMNotProvisioned
  case sharedVMUnavailable(String)
  case sharedVMError(String)
  case sharedVMReadyTimeout(String)
  case sharedVMRouteUnavailable(String)
  case commandFailed(RustFactorySmokeCommandReport)

  var description: String {
    switch self {
    case .sharedVMNotProvisioned:
      return "Shared VM bundle is not provisioned yet."
    case .sharedVMUnavailable(let reason):
      return "Shared VM unavailable: \(reason)"
    case .sharedVMError(let detail):
      return "Shared VM error: \(detail)"
    case .sharedVMReadyTimeout(let state):
      return "Shared VM did not become ready before timeout; last state: \(state)"
    case .sharedVMRouteUnavailable(let detail):
      return "Shared VM route unavailable for generated Rust project: \(detail)"
    case .commandFailed(let report):
      return "Command failed (\(report.exitCode)): \(report.command)\n\(report.stderrTail)\n\(report.stdoutTail)"
    }
  }
}
