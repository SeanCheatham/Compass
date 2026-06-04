import Foundation

struct RustEngineResponse<T: Decodable>: Decodable, Equatable where T: Equatable {
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

struct RustEnginePingData: Decodable, Equatable {
  var version: String
  var rustc: String?
  var repo: String
}
