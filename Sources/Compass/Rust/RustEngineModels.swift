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
