import Foundation

public func agentToolDecodingErrorDescription(_ error: Error) -> String {
  guard let decodingError = error as? DecodingError else {
    return error.localizedDescription
  }

  func path(_ codingPath: [CodingKey]) -> String {
    let value = codingPath.map(\.stringValue).joined(separator: ".")
    return value.isEmpty ? "root" : value
  }

  switch decodingError {
  case .dataCorrupted(let context):
    return context.debugDescription
  case .keyNotFound(let key, let context):
    return "Missing required field `\(key.stringValue)` at \(path(context.codingPath))."
  case .typeMismatch(let type, let context):
    return "Expected \(type) at \(path(context.codingPath)): \(context.debugDescription)"
  case .valueNotFound(let type, let context):
    return "Expected \(type) value at \(path(context.codingPath)): \(context.debugDescription)"
  @unknown default:
    return error.localizedDescription
  }
}
