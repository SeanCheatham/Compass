import Foundation

enum AgentTextFile {
  static func decodeUTF8(_ data: Data, path: String) -> Result<String, AgentToolError> {
    guard !data.prefix(8192).contains(0),
      let text = String(data: data, encoding: .utf8)
    else {
      return .failure(.binaryFile(path))
    }
    return .success(text)
  }
}
