import Foundation

enum ProductTournamentJSONValue: Codable, Equatable, Sendable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([ProductTournamentJSONValue])
  case object([String: ProductTournamentJSONValue])

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let object = try? container.decode([String: ProductTournamentJSONValue].self) {
      self = .object(object)
    } else if let array = try? container.decode([ProductTournamentJSONValue].self) {
      self = .array(array)
    } else if let bool = try? container.decode(Bool.self) {
      self = .bool(bool)
    } else if let number = try? container.decode(Double.self) {
      self = .number(number)
    } else if let string = try? container.decode(String.self) {
      self = .string(string)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Unsupported JSON value."
      )
    }
  }

  func encode(to encoder: Encoder) throws {
    switch self {
    case .null:
      var container = encoder.singleValueContainer()
      try container.encodeNil()
    case .bool(let value):
      var container = encoder.singleValueContainer()
      try container.encode(value)
    case .number(let value):
      var container = encoder.singleValueContainer()
      try container.encode(value)
    case .string(let value):
      var container = encoder.singleValueContainer()
      try container.encode(value)
    case .array(let values):
      var container = encoder.unkeyedContainer()
      for value in values {
        try container.encode(value)
      }
    case .object(let values):
      var container = encoder.container(keyedBy: ProductTournamentJSONCodingKey.self)
      for key in values.keys.sorted() {
        if let value = values[key] {
          try container.encode(value, forKey: ProductTournamentJSONCodingKey(stringValue: key))
        }
      }
    }
  }
}

private struct ProductTournamentJSONCodingKey: CodingKey {
  var stringValue: String
  var intValue: Int?

  init(stringValue: String) {
    self.stringValue = stringValue
  }

  init(intValue: Int) {
    self.stringValue = String(intValue)
    self.intValue = intValue
  }
}

enum ProductTournamentJSONCanonicalizer {
  static func canonicalJSON(_ json: String) throws -> String {
    guard let data = json.data(using: .utf8) else {
      throw ProductTournamentJSONCanonicalizerError.notUTF8
    }
    let value = try JSONDecoder().decode(ProductTournamentJSONValue.self, from: data)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let encoded = try encoder.encode(value)
    return String(decoding: encoded, as: UTF8.self)
  }
}

private enum ProductTournamentJSONCanonicalizerError: LocalizedError {
  case notUTF8

  var errorDescription: String? {
    switch self {
    case .notUTF8:
      return "JSON string was not UTF-8."
    }
  }
}
