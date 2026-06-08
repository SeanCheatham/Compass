import Foundation

struct RustProductTournamentHealth: Codable, Equatable, Sendable {
  static let detailLimit = 220

  enum Status: String, Codable, Equatable, Sendable {
    case healthy
    case warning
    case failed
    case unknown
  }

  struct Check: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var label: String
    var status: Status
    var detail: String
    var nextAction: String?
  }

  struct Inputs: Equatable, Sendable {
    var engineBinaryURL: URL?
    var ping: RustEngineResponse<RustEnginePingData>?
    var scaffold: RustEngineResponse<ScaffoldCheckData>?
    var cargoGraph: CargoGraphData?
    var cargoDiagnostics: RustEngineResponse<CargoCheckData>?
    var clippy: RustEngineResponse<ClippyLintData>?
    var coverage: RustEngineResponse<CoverageGapsData>?
    var visual: RustEngineResponse<VisualVerifyData>?
    var smokeReport: RustProductTournamentSmokeReport?
    var smokeReportURL: URL?
    var generatedAt: Date

    init(
      engineBinaryURL: URL? = nil,
      ping: RustEngineResponse<RustEnginePingData>? = nil,
      scaffold: RustEngineResponse<ScaffoldCheckData>? = nil,
      cargoGraph: CargoGraphData? = nil,
      cargoDiagnostics: RustEngineResponse<CargoCheckData>? = nil,
      clippy: RustEngineResponse<ClippyLintData>? = nil,
      coverage: RustEngineResponse<CoverageGapsData>? = nil,
      visual: RustEngineResponse<VisualVerifyData>? = nil,
      smokeReport: RustProductTournamentSmokeReport? = nil,
      smokeReportURL: URL? = nil,
      generatedAt: Date = Date()
    ) {
      self.engineBinaryURL = engineBinaryURL
      self.ping = ping
      self.scaffold = scaffold
      self.cargoGraph = cargoGraph
      self.cargoDiagnostics = cargoDiagnostics
      self.clippy = clippy
      self.coverage = coverage
      self.visual = visual
      self.smokeReport = smokeReport
      self.smokeReportURL = smokeReportURL
      self.generatedAt = generatedAt
    }
  }

  var status: Status
  var title: String
  var detail: String
  var nextAction: String
  var systemImage: String
  var generatedAt: Date
  var latestSmokeReportPath: String?
  var checks: [Check]

  init(inputs: Inputs) {
    generatedAt = inputs.generatedAt
    latestSmokeReportPath = inputs.smokeReportURL?.path ?? inputs.smokeReport?.reportPath
    checks = Self.makeChecks(inputs: inputs)
    status = Self.aggregate(checks)
    let presentation = Self.presentation(status: status, checks: checks)
    title = presentation.title
    detail = StringUtils.boundedText(presentation.detail, limit: Self.detailLimit)
    nextAction = presentation.nextAction
    systemImage = presentation.systemImage
  }

  static func local(repoURL: URL, workspace: CompassWorkspace?) -> RustProductTournamentHealth {
    let engineURL = RustEngineLocator.locateEngineBinary()
    let scaffold: RustEngineResponse<ScaffoldCheckData>? =
      RustProjectScaffold.isBlessedDesktopWorkspace(at: repoURL)
      ? RustEngineResponse(
        schemaVersion: 1,
        command: RustEngineCommand.scaffoldCheck.rawValue,
        ok: true,
        data: ScaffoldCheckData(
          status: "pass",
          scaffoldVersion: nil,
          capabilities: ScaffoldCapabilities(
            xtaskVerify: true,
            visualVerify: true,
            schemaContracts: true,
            desktopHandshake: true,
            simulationFixtures: true,
            guiReplay: true,
            productTournamentExperience: true
          ),
          checks: []
        ),
        errors: []
      )
      : nil
    let cargoGraph = workspace.flatMap { CargoGraphStore().load(from: $0)?.graph }
    return RustProductTournamentHealth(
      inputs: Inputs(
        engineBinaryURL: engineURL,
        scaffold: scaffold,
        cargoGraph: cargoGraph,
        generatedAt: Date()
      )
    )
  }

  private static func makeChecks(inputs: Inputs) -> [Check] {
    [
      engineBinaryCheck(inputs.engineBinaryURL),
      pingCheck(inputs.ping),
      scaffoldCheck(inputs.scaffold),
      cargoGraphCheck(inputs.cargoGraph),
      cargoDiagnosticsCheck(inputs.cargoDiagnostics),
      clippyCheck(inputs.clippy),
      coverageCheck(inputs.coverage),
      visualCheck(inputs.visual, scaffold: inputs.scaffold),
      smokeReportCheck(inputs.smokeReport, url: inputs.smokeReportURL, now: inputs.generatedAt),
    ]
  }

  private static func engineBinaryCheck(_ url: URL?) -> Check {
    if let url {
      return Check(
        id: "engine-binary",
        label: "Engine binary",
        status: .healthy,
        detail: "Found \(boundedPath(url.path)).",
        nextAction: nil
      )
    }
    return Check(
      id: "engine-binary",
      label: "Engine binary",
      status: .failed,
      detail: "compass-engine was not found.",
      nextAction: "./scripts/build-compass-engine.sh"
    )
  }

  private static func pingCheck(_ response: RustEngineResponse<RustEnginePingData>?) -> Check {
    guard let response else {
      return Check(
        id: "engine-ping",
        label: "Engine ping",
        status: .unknown,
        detail: "No recent ping result is cached.",
        nextAction: "compass-engine ping --repo . --format json"
      )
    }
    return Check(
      id: "engine-ping",
      label: "Engine ping",
      status: response.ok ? .healthy : .failed,
      detail: response.ok
        ? "Ping responded for \(boundedPath(response.data?.repo ?? "."))"
        : response.errors.joined(separator: " "),
      nextAction: response.ok ? nil : "Build or reinstall compass-engine."
    )
  }

  private static func scaffoldCheck(_ response: RustEngineResponse<ScaffoldCheckData>?) -> Check {
    guard let response, let data = response.data else {
      return Check(
        id: "scaffold",
        label: "Scaffold contract",
        status: .unknown,
        detail: "No scaffold-check result is cached.",
        nextAction: "scaffold_check"
      )
    }
    let failed = data.checks.first { $0.status == "fail" }
    if data.status == "pass" {
      return Check(
        id: "scaffold",
        label: "Scaffold contract",
        status: .healthy,
        detail: "Generated Rust scaffold matches the Compass contract.",
        nextAction: nil
      )
    }
    return Check(
      id: "scaffold",
      label: "Scaffold contract",
      status: .failed,
      detail: failed?.message ?? "scaffold-check reported \(data.status).",
      nextAction: response.repairHints.first?.suggestedCommand ?? "scaffold_check"
    )
  }

  private static func cargoGraphCheck(_ graph: CargoGraphData?) -> Check {
    guard let graph else {
      return Check(
        id: "cargo-graph",
        label: "Cargo graph",
        status: .unknown,
        detail: "No cached Cargo graph is available.",
        nextAction: "workspace_outline"
      )
    }
    return Check(
      id: "cargo-graph",
      label: "Cargo graph",
      status: graph.members.isEmpty ? .warning : .healthy,
      detail: graph.members.isEmpty
        ? "Cargo graph has no members." : "\(graph.members.count) Cargo member(s) cached.",
      nextAction: graph.members.isEmpty ? "workspace_outline" : nil
    )
  }

  private static func cargoDiagnosticsCheck(_ response: RustEngineResponse<CargoCheckData>?)
    -> Check
  {
    diagnosticCheck(
      id: "cargo-diagnostics",
      label: "Cargo diagnostics",
      response: response,
      action: "cargo_check"
    )
  }

  private static func clippyCheck(_ response: RustEngineResponse<ClippyLintData>?) -> Check {
    diagnosticCheck(id: "clippy", label: "Clippy", response: response, action: "clippy_lint")
  }

  private static func diagnosticCheck(
    id: String,
    label: String,
    response: RustEngineResponse<CargoCheckData>?,
    action: String
  ) -> Check {
    guard let response, let data = response.data else {
      return Check(
        id: id,
        label: label,
        status: .unknown,
        detail: "No recent \(label.lowercased()) result is cached.",
        nextAction: action
      )
    }
    let status: Status = data.exitCode == 0 ? .healthy : .failed
    return Check(
      id: id,
      label: label,
      status: status,
      detail:
        "Exit \(data.exitCode); \(data.summary.errors) error(s), \(data.summary.warnings) warning(s).",
      nextAction: status == .healthy ? nil : action
    )
  }

  private static func coverageCheck(_ response: RustEngineResponse<CoverageGapsData>?) -> Check {
    guard let response, let data = response.data else {
      let hint = response?.repairHints.first
      return Check(
        id: "coverage",
        label: "Coverage tooling",
        status: hint?.id == "missing-cargo-llvm-cov" ? .failed : .unknown,
        detail: hint?.message ?? "No recent coverage result is cached.",
        nextAction: hint?.suggestedCommand ?? "coverage_gaps"
      )
    }
    return Check(
      id: "coverage",
      label: "Coverage tooling",
      status: .healthy,
      detail: String(format: "Line coverage summary %.1f%%.", data.overallLinePercent),
      nextAction: nil
    )
  }

  private static func visualCheck(
    _ response: RustEngineResponse<VisualVerifyData>?,
    scaffold: RustEngineResponse<ScaffoldCheckData>?
  ) -> Check {
    guard let response, let data = response.data else {
      let advertised = scaffold?.data?.capabilities.visualVerify == true
      return Check(
        id: "visual",
        label: "Visual verification",
        status: advertised ? .unknown : .warning,
        detail: advertised
          ? "Visual verification is advertised but no recent result is cached."
          : "Visual verification is not advertised for this project.",
        nextAction: advertised ? "visual_verify" : nil
      )
    }
    return Check(
      id: "visual",
      label: "Visual verification",
      status: data.ok ? .healthy : .failed,
      detail: data.ok
        ? "Latest visual verification passed."
        : response.repairHints.first?.message ?? "Latest visual verification failed.",
      nextAction: data.ok ? nil : response.repairHints.first?.suggestedCommand ?? "visual_verify"
    )
  }

  private static func smokeReportCheck(
    _ report: RustProductTournamentSmokeReport?,
    url: URL?,
    now _: Date
  ) -> Check {
    guard let report else {
      return Check(
        id: "smoke-report",
        label: "Product Tournament smoke",
        status: .unknown,
        detail: "No latest product tournament smoke report is cached.",
        nextAction: "cargo run -p xtask -- product-tournament-smoke"
      )
    }
    let reportPath = boundedPath(url?.path ?? report.reportPath)
    return Check(
      id: "smoke-report",
      label: "Product Tournament smoke",
      status: report.status == .passed ? .healthy : .failed,
      detail: "\(report.status.rawValue) report at \(reportPath).",
      nextAction: report.status == .passed
        ? nil : "Open the smoke report and rerun product-tournament-smoke."
    )
  }

  private static func aggregate(_ checks: [Check]) -> Status {
    if checks.contains(where: { $0.status == .failed }) { return .failed }
    if checks.contains(where: { $0.status == .warning }) { return .warning }
    if checks.contains(where: { $0.status == .unknown }) { return .unknown }
    return .healthy
  }

  private static func presentation(status: Status, checks: [Check]) -> (
    title: String, detail: String, nextAction: String, systemImage: String
  ) {
    switch status {
    case .healthy:
      return (
        "Rust Product Tournament Healthy",
        "Engine, scaffold, Cargo probes, coverage, visual verification, and smoke report are ready.",
        "No action needed",
        "checkmark.seal.fill"
      )
    case .failed:
      let failed = checks.first { $0.status == .failed }
      return (
        "Rust Product Tournament Needs Repair",
        failed?.detail ?? "One or more Rust Product Tournament checks failed.",
        failed?.nextAction ?? "Run structured Rust probes.",
        "exclamationmark.triangle.fill"
      )
    case .warning:
      let warning = checks.first { $0.status == .warning }
      return (
        "Rust Product Tournament Partly Ready",
        warning?.detail ?? "The Rust Product Tournament path is degraded but usable.",
        warning?.nextAction ?? "Review Rust Product Tournament checks.",
        "exclamationmark.circle"
      )
    case .unknown:
      let unknownCount = checks.filter { $0.status == .unknown }.count
      return (
        "Rust Product Tournament Status Partial",
        "\(unknownCount) Rust Product Tournament check(s) need cached probe results; no expensive checks were launched for this summary.",
        checks.first { $0.status == .unknown }?.nextAction ?? "Run structured Rust probes.",
        "questionmark.circle"
      )
    }
  }

  private static func boundedPath(_ path: String) -> String {
    StringUtils.boundedText(path, limit: 96)
  }
}

struct RustProductTournamentHealthStore {
  static let filename = "rust-product-tournament-health.json"

  func url(for workspace: CompassWorkspace) -> URL {
    workspace.compassURL.appending(path: Self.filename)
  }

  func load(from workspace: CompassWorkspace) -> RustProductTournamentHealth? {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    guard let data = try? Data(contentsOf: url(for: workspace)), !data.isEmpty else { return nil }
    return try? decoder.decode(RustProductTournamentHealth.self, from: data)
  }

  func save(_ health: RustProductTournamentHealth, workspace: CompassWorkspace) throws {
    try FileManager.default.createDirectory(
      at: workspace.compassURL, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(health).write(to: url(for: workspace), options: .atomic)
  }
}
