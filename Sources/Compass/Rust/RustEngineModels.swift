import Foundation

struct RustEngineResponse<T: Codable>: Codable, Equatable where T: Equatable {
  var schemaVersion: Int
  var command: String
  var ok: Bool
  var audit: RustEngineAudit?
  var repairHints: [RustRepairHint]
  var data: T?
  var errors: [String]

  init(
    schemaVersion: Int,
    command: String,
    ok: Bool,
    audit: RustEngineAudit? = nil,
    repairHints: [RustRepairHint] = [],
    data: T?,
    errors: [String]
  ) {
    self.schemaVersion = schemaVersion
    self.command = command
    self.ok = ok
    self.audit = audit
    self.repairHints = repairHints
    self.data = data
    self.errors = errors
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
    command = try container.decode(String.self, forKey: .command)
    ok = try container.decode(Bool.self, forKey: .ok)
    audit = try container.decodeIfPresent(RustEngineAudit.self, forKey: .audit)
    repairHints = try container.decodeIfPresent([RustRepairHint].self, forKey: .repairHints) ?? []
    data = try container.decodeIfPresent(T.self, forKey: .data)
    errors = try container.decode([String].self, forKey: .errors)
  }

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case command
    case ok
    case audit
    case repairHints = "repair_hints"
    case data
    case errors
  }
}

struct RustEngineAudit: Codable, Equatable, Sendable {
  var repo: String
  var argv: [String]?
  var durationMs: Int
  var toolchain: RustEngineToolchain

  enum CodingKeys: String, CodingKey {
    case repo
    case argv
    case durationMs = "duration_ms"
    case toolchain
  }
}

struct RustEngineToolchain: Codable, Equatable, Sendable {
  var rustc: String?
  var cargo: String?
}

struct RustRepairHint: Codable, Equatable, Sendable {
  var id: String
  var severity: String
  var message: String
  var suggestedCommand: String?

  enum CodingKeys: String, CodingKey {
    case id
    case severity
    case message
    case suggestedCommand = "suggested_command"
  }
}

struct RustEnginePingData: Codable, Equatable {
  var version: String
  var rustc: String?
  var repo: String
}

struct CargoGraphData: Codable, Equatable, Sendable {
  var workspaceRoot: String
  var members: [CargoGraphMember]
  var edges: [CargoGraphEdge]

  enum CodingKeys: String, CodingKey {
    case workspaceRoot = "workspace_root"
    case members
    case edges
  }
}

struct CargoGraphMember: Codable, Equatable, Sendable {
  var name: String
  var manifestPath: String
  var kind: String
  var packageDir: String
  var srcRoot: String
  var dependencies: [CargoGraphDependency]
  var features: CargoGraphFeatures

  enum CodingKeys: String, CodingKey {
    case name
    case manifestPath = "manifest_path"
    case kind
    case packageDir = "package_dir"
    case srcRoot = "src_root"
    case dependencies
    case features
  }
}

struct CargoGraphDependency: Codable, Equatable, Sendable {
  var name: String
  var kind: String
  var version: String?
  var path: String?
  var features: [String]
}

struct CargoGraphFeatures: Codable, Equatable, Sendable {
  var `default`: [String]
  var named: [String: [String]]
}

struct CargoGraphEdge: Codable, Equatable, Sendable {
  var from: String
  var to: String
  var dev: Bool
  var optional: Bool
}

struct RustDiagnostic: Codable, Equatable, Sendable {
  var level: String
  var code: String?
  var message: String
  var package: String?
  var file: String?
  var line: Int?
  var column: Int?
  var label: String?
  var rendered: String?
}

struct RustDiagnosticSummary: Codable, Equatable, Sendable {
  var errors: Int
  var warnings: Int
  var cratesAffected: [String]

  enum CodingKeys: String, CodingKey {
    case errors
    case warnings
    case cratesAffected = "crates_affected"
  }
}

struct CargoCheckData: Codable, Equatable, Sendable {
  var exitCode: Int
  var diagnostics: [RustDiagnostic]
  var summary: RustDiagnosticSummary

  enum CodingKeys: String, CodingKey {
    case exitCode = "exit_code"
    case diagnostics
    case summary
  }
}

typealias ClippyLintData = CargoCheckData

struct CargoTestFailure: Codable, Equatable, Sendable {
  var testName: String
  var message: String
  var file: String?
  var line: Int?

  enum CodingKeys: String, CodingKey {
    case testName = "test_name"
    case message
    case file
    case line
  }
}

struct CargoTestData: Codable, Equatable, Sendable {
  var exitCode: Int
  var passed: Int
  var failed: Int
  var failures: [CargoTestFailure]

  enum CodingKeys: String, CodingKey {
    case exitCode = "exit_code"
    case passed
    case failed
    case failures
  }
}

struct RustIndexData: Codable, Equatable, Sendable {
  var moduleIndex: RustModuleIndex
  var traitIndex: RustTraitIndex
  var warnings: [String]

  enum CodingKeys: String, CodingKey {
    case moduleIndex = "module_index"
    case traitIndex = "trait_index"
    case warnings
  }
}

struct RustModuleIndex: Codable, Equatable, Sendable {
  var schemaVersion: Int
  var files: [String: RustModuleFile]

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case files
  }
}

struct RustModuleFile: Codable, Equatable, Sendable {
  var modulePath: String
  var outgoing: [RustModuleEdge]
  var incoming: [RustModuleEdge]

  enum CodingKeys: String, CodingKey {
    case modulePath = "module_path"
    case outgoing
    case incoming
  }
}

struct RustModuleEdge: Codable, Equatable, Sendable {
  var toFile: String?
  var fromFile: String?
  var raw: String
  var line: Int

  enum CodingKeys: String, CodingKey {
    case toFile = "to_file"
    case fromFile = "from_file"
    case raw
    case line
  }
}

struct RustTraitIndex: Codable, Equatable, Sendable {
  var schemaVersion: Int
  var impls: [RustTraitImpl]
  var byTrait: [String: [String]]
  var byType: [String: [String]]

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case impls
    case byTrait = "by_trait"
    case byType = "by_type"
  }
}

struct RustTraitImpl: Codable, Equatable, Sendable {
  var traitName: String
  var typeName: String
  var file: String
  var line: Int
  var implStartLine: Int

  enum CodingKeys: String, CodingKey {
    case traitName = "trait_name"
    case typeName = "type_name"
    case file
    case line
    case implStartLine = "impl_start_line"
  }
}

struct SchemaContractsData: Codable, Equatable, Sendable {
  var schemaVersion: Int
  var contracts: [SchemaContract]

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case contracts
  }
}

struct SchemaContract: Codable, Equatable, Sendable {
  var schemaPath: String
  var schemaTitle: String
  var rustType: String?
  var rustFile: String?
  var line: Int?
  var confidence: String
  var fieldMapping: [SchemaFieldMapping]

  enum CodingKeys: String, CodingKey {
    case schemaPath = "schema_path"
    case schemaTitle = "schema_title"
    case rustType = "rust_type"
    case rustFile = "rust_file"
    case line
    case confidence
    case fieldMapping = "field_mapping"
  }
}

struct SchemaFieldMapping: Codable, Equatable, Sendable {
  var schemaField: String
  var rustField: String

  enum CodingKeys: String, CodingKey {
    case schemaField = "schema_field"
    case rustField = "rust_field"
  }
}

struct ScaffoldCheckData: Codable, Equatable, Sendable {
  var status: String
  var scaffoldVersion: Int?
  var capabilities: ScaffoldCapabilities
  var checks: [ScaffoldCheck]

  enum CodingKeys: String, CodingKey {
    case status
    case scaffoldVersion = "scaffold_version"
    case capabilities
    case checks
  }
}

struct ScaffoldCapabilities: Codable, Equatable, Sendable {
  var xtaskVerify: Bool
  var visualVerify: Bool
  var schemaContracts: Bool
  var desktopHandshake: Bool

  enum CodingKeys: String, CodingKey {
    case xtaskVerify = "xtask_verify"
    case visualVerify = "visual_verify"
    case schemaContracts = "schema_contracts"
    case desktopHandshake = "desktop_handshake"
  }
}

struct ScaffoldCheck: Codable, Equatable, Sendable {
  var id: String
  var status: String
  var message: String
  var path: String?
}

struct CoverageGapsData: Codable, Equatable, Sendable {
  var overallLinePercent: Double
  var files: [CoverageGapFile]
  var logTail: String

  enum CodingKeys: String, CodingKey {
    case overallLinePercent = "overall_line_percent"
    case files
    case logTail = "log_tail"
  }
}

struct CoverageGapFile: Codable, Equatable, Sendable {
  var path: String
  var linePercent: Double
  var uncoveredLines: [Int]

  enum CodingKeys: String, CodingKey {
    case path
    case linePercent = "line_percent"
    case uncoveredLines = "uncovered_lines"
  }
}

struct VisualVerifyData: Codable, Equatable, Sendable {
  var ok: Bool
  var screenshotPath: String?
  var logTail: String

  enum CodingKeys: String, CodingKey {
    case ok
    case screenshotPath = "screenshot_path"
    case logTail = "log_tail"
  }
}
