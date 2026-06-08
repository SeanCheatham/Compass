import Foundation

struct CompassDaemonRequest: Encodable {
  var schemaVersion = 1
  var id: String
  var method: String
  var params: [String: String] = [:]

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case id
    case method
    case params
  }
}

struct CompassDaemonResponse<Result: Decodable>: Decodable {
  var schemaVersion: Int
  var id: String
  var ok: Bool
  var result: Result?
  var errors: [String]

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case id
    case ok
    case result
    case errors
  }
}

struct CompassDaemonPing: Decodable, Equatable {
  var compassdVersion: String
  var coreVersion: String
  var schemaVersion: Int
}

struct CompassDaemonCapabilities: Decodable, Equatable {
  var compassdVersion: String
  var coreVersion: String
  var schemaVersion: Int
  var methods: [String]
  var capabilities: [String]
}

struct CompassDaemonEmptyResult: Decodable, Equatable {}

struct CompassDaemonDiagnostics: Equatable {
  var isEnabled: Bool
  var binaryURL: URL?
  var socketURL: URL
  var logURL: URL
  var version: String?
  var coreVersion: String?
  var schemaVersion: Int?
  var lastError: String?

  var copyText: String {
    [
      "compassd-enabled: \(isEnabled)",
      "compassd-binary: \(binaryURL?.path ?? "unresolved")",
      "compassd-socket: \(socketURL.path)",
      "compassd-log: \(logURL.path)",
      "compassd-version: \(version ?? "unknown")",
      "compass-core-version: \(coreVersion ?? "unknown")",
      "compassd-schema-version: \(schemaVersion.map(String.init) ?? "unknown")",
      "compassd-last-error: \(lastError ?? "none")",
    ].joined(separator: "\n")
  }
}
