import Foundation

struct RustEngineResponse<T: Codable>: Codable, Equatable where T: Equatable {
  var schemaVersion: Int
  var command: String
  var ok: Bool
  var data: T?
  var errors: [String]

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case command
    case ok
    case data
    case errors
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
