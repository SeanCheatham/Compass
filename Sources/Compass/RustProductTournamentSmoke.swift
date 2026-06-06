import AppKit
import Darwin
import Foundation

struct RustProductTournamentSmokeOptions: Equatable {
  static let flag = "--compass-rust-product-tournament-smoke"
  static let projectDirFlag = "--compass-rust-product-tournament-smoke-project"
  static let reportFlag = "--compass-rust-product-tournament-smoke-report"
  static let timeoutFlag = "--compass-rust-product-tournament-smoke-timeout"

  var projectURL: URL
  var reportURL: URL
  var timeoutSeconds: TimeInterval

  static func parse(
    arguments: [String] = CommandLine.arguments,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> RustProductTournamentSmokeOptions? {
    guard arguments.contains(flag) else { return nil }

    let projectPath =
      value(after: projectDirFlag, in: arguments)
      ?? environment["COMPASS_RUST_PRODUCT_TOURNAMENT_SMOKE_PROJECT"]
    let reportPath =
      value(after: reportFlag, in: arguments)
      ?? environment["COMPASS_RUST_PRODUCT_TOURNAMENT_SMOKE_REPORT"]
    let timeoutText =
      value(after: timeoutFlag, in: arguments)
      ?? environment["COMPASS_RUST_PRODUCT_TOURNAMENT_SMOKE_TIMEOUT"]

    let projectURL =
      projectPath.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
      ?? FileManager.default.temporaryDirectory
      .appending(path: "CompassRustProductTournamentSmoke-\(UUID().uuidString)", directoryHint: .isDirectory)
    let reportURL =
      reportPath.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
      ?? FileManager.default.temporaryDirectory
      .appending(path: "compass-rust-product-tournament-smoke-\(UUID().uuidString).json")
    let timeoutSeconds = timeoutText.flatMap(TimeInterval.init) ?? 20 * 60

    return RustProductTournamentSmokeOptions(
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
enum RustProductTournamentSmokeBootstrap {
  private static var started = false

  static func startIfRequested() {
    guard RustProductTournamentSmokeOptions.parse() != nil, !started else { return }
    started = true
    Task { @MainActor in
      let model = AppModel()
      await model.bootstrap()
      await RustProductTournamentSmoke.runIfRequested(model: model)
    }
  }
}

@MainActor
enum RustProductTournamentSmoke {
  private static var started = false

  static func runIfRequested(model: AppModel) async {
    guard let options = RustProductTournamentSmokeOptions.parse(), !started else { return }
    started = true

    let exitCode: Int32
    do {
      try await run(options: options, model: model)
      exitCode = 0
    } catch {
      let report = RustProductTournamentSmokeReport(
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
      log("Rust product tournament smoke failed: \(error)")
      exitCode = 1
    }

    await SharedCompassVM.shared.stop()
    Darwin.exit(exitCode)
  }

  private static func run(options: RustProductTournamentSmokeOptions, model: AppModel) async throws {
    var reports: [RustProductTournamentSmokeCommandReport] = []
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
      let report = RustProductTournamentSmokeReport(
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
    options: RustProductTournamentSmokeOptions,
    model: AppModel,
    reports: inout [RustProductTournamentSmokeCommandReport],
    guestWorkspacePath: inout String?,
    sshDestination: inout String?,
    screenshotURL: inout URL?
  ) async throws {
    log("Rust product tournament smoke: preparing \(options.projectURL.path)")
    try await AppModel.initializeGeneratedRustProject(at: options.projectURL)

    log("Rust product tournament smoke: starting Shared VM")
    try await model.sharedVMHost.warmup()
    guard model.sharedVMHost.bundle.existsOnDisk() else {
      throw RustProductTournamentSmokeError.sharedVMNotProvisioned
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
      throw RustProductTournamentSmokeError.sharedVMRouteUnavailable(launchPlan.routeDetail())
    }
    guestWorkspacePath = route.guestWorkspacePath

    var visualOutput = ""
    let commands =
      RustVerifyCommands.productTournamentSmokeCommands.map {
        RustProductTournamentSmokeCommandSpec(
          command: $0,
          category: $0 == RustProjectScaffold.productTournamentSmokeWithScreenshotCommand
            ? .productTournamentSmoke : .cargo
        )
      }
      + RustVerifyCommands.compassEngineSmokeCommands.map {
        RustProductTournamentSmokeCommandSpec(command: $0, category: .compassEngine)
      }

    for spec in commands {
      let commandRun = try await runCommand(
        spec,
        project: project,
        hostWorkingDirectory: options.projectURL,
        launchPlan: launchPlan,
        timeoutSeconds: options.timeoutSeconds
      )
      reports.append(commandRun.report)
      if spec.category == .productTournamentSmoke || spec.category == .visualVerification {
        visualOutput = commandRun.rawOutput
      }
      if commandRun.report.exitCode != 0 {
        throw RustProductTournamentSmokeError.commandFailed(commandRun.report)
      }
      if spec.category == .compassEngine {
        try validateEngineResponse(commandRun)
      }
    }

    screenshotURL = try writeScreenshotIfPresent(
      from: visualOutput,
      nextTo: options.reportURL
    )

    let report = RustProductTournamentSmokeReport(
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
    log("Rust product tournament smoke passed. Report: \(options.reportURL.path)")
  }

  private static func runCommand(
    _ spec: RustProductTournamentSmokeCommandSpec,
    project: CompassProject,
    hostWorkingDirectory: URL,
    launchPlan: AgentExecutionLaunchPlan,
    timeoutSeconds: TimeInterval
  ) async throws -> RustProductTournamentSmokeCommandRun {
    let command = spec.command
    log("Rust product tournament smoke: \(command)")
    let startedAt = Date()
    let result = try await project.runVerifyCommand(
      command: command,
      hostWorkingDirectory: hostWorkingDirectory,
      timeoutSeconds: timeoutSeconds,
      launchPlan: launchPlan
    )
    let shouldRedactVisualOutput =
      spec.category == .productTournamentSmoke || spec.category == .visualVerification
    let stdoutForReport =
      shouldRedactVisualOutput
      ? RustDesktopVisualVerification.redactedOutput(result.stdout)
      : result.stdout
    let stderrForReport =
      shouldRedactVisualOutput
      ? RustDesktopVisualVerification.redactedOutput(result.stderr)
      : result.stderr
    let report = RustProductTournamentSmokeCommandReport(
      command: command,
      category: spec.category,
      exitCode: result.exitCode,
      durationSeconds: Date().timeIntervalSince(startedAt),
      audit: decodeEngineAudit(from: result.stdout),
      stdoutTail: tail(stdoutForReport, limit: 6000),
      stderrTail: tail(stderrForReport, limit: 6000)
    )
    return RustProductTournamentSmokeCommandRun(
      report: report,
      rawOutput: "\(result.stdout)\n\(result.stderr)",
      stdout: result.stdout
    )
  }

  private static func validateEngineResponse(_ commandRun: RustProductTournamentSmokeCommandRun) throws {
    let data = Data(commandRun.stdout.utf8)
    let object = try JSONSerialization.jsonObject(with: data)
    guard let root = object as? [String: Any] else {
      throw RustProductTournamentSmokeError.invalidEngineResponse(
        commandRun.report,
        "compass-engine did not return a JSON object"
      )
    }
    guard root["ok"] as? Bool == true else {
      let errors = (root["errors"] as? [String])?.joined(separator: "\n") ?? "unknown engine error"
      throw RustProductTournamentSmokeError.invalidEngineResponse(commandRun.report, errors)
    }
    guard
      let data = root["data"] as? [String: Any],
      let exitCode = data["exit_code"] as? Int
    else {
      return
    }
    guard exitCode == 0 else {
      throw RustProductTournamentSmokeError.invalidEngineResponse(
        commandRun.report,
        "compass-engine payload reported Cargo exit_code \(exitCode)"
      )
    }
  }

  private static func decodeEngineAudit(from stdout: String) -> RustEngineAudit? {
    guard let data = stdout.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(RustEngineResponse<EmptyEngineData>.self, from: data).audit
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
        throw RustProductTournamentSmokeError.sharedVMUnavailable(reason)
      case .error(let detail):
        throw RustProductTournamentSmokeError.sharedVMError(detail)
      default:
        try await Task.sleep(nanoseconds: 1_000_000_000)
      }
    }
    throw RustProductTournamentSmokeError.sharedVMReadyTimeout(String(describing: host.readiness))
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

  private static func writeReport(_ report: RustProductTournamentSmokeReport, to url: URL) throws {
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

struct RustProductTournamentSmokeReport: Codable, Equatable {
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
  var commands: [RustProductTournamentSmokeCommandReport]
  var error: String?
}

struct RustProductTournamentSmokeCommandReport: Codable, Equatable {
  var command: String
  var category: RustProductTournamentSmokeCommandCategory
  var exitCode: Int32
  var durationSeconds: TimeInterval
  var audit: RustEngineAudit?
  var stdoutTail: String
  var stderrTail: String
}

private struct EmptyEngineData: Codable, Equatable {}

enum RustProductTournamentSmokeCommandCategory: String, Codable, Equatable {
  case cargo
  case productTournamentSmoke = "product-tournament-smoke"
  case visualVerification = "visual-verification"
  case compassEngine = "compass-engine"
}

private struct RustProductTournamentSmokeCommandSpec {
  var command: String
  var category: RustProductTournamentSmokeCommandCategory
}

private struct RustProductTournamentSmokeCommandRun {
  var report: RustProductTournamentSmokeCommandReport
  var rawOutput: String
  var stdout: String
}

enum RustProductTournamentSmokeError: Error, CustomStringConvertible {
  case sharedVMNotProvisioned
  case sharedVMUnavailable(String)
  case sharedVMError(String)
  case sharedVMReadyTimeout(String)
  case sharedVMRouteUnavailable(String)
  case commandFailed(RustProductTournamentSmokeCommandReport)
  case invalidEngineResponse(RustProductTournamentSmokeCommandReport, String)

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
      return
        "Command failed (\(report.exitCode)): \(report.command)\n\(report.stderrTail)\n\(report.stdoutTail)"
    case .invalidEngineResponse(let report, let detail):
      return
        "compass-engine smoke failed for \(report.command): \(detail)\n\(report.stderrTail)\n\(report.stdoutTail)"
    }
  }
}
