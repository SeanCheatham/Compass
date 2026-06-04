import Foundation

enum RustDocCommentScanner {
  static func blurb(for symbols: [CodemapSymbol], source: String) -> String? {
    let lines = source.components(separatedBy: .newlines)
    var blurbs: [String] = []
    for symbol in symbols {
      let index = max(0, symbol.line - 2)
      var docs: [String] = []
      var cursor = index
      while cursor >= 0 {
        let trimmed = lines[cursor].trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("///") else {
          if trimmed.isEmpty {
            cursor -= 1
            continue
          }
          break
        }
        docs.append(
          trimmed
            .dropFirst(3)
            .trimmingCharacters(in: .whitespaces)
        )
        if cursor == 0 { break }
        cursor -= 1
      }
      let text = docs.reversed().joined(separator: " ")
      if !text.isEmpty {
        blurbs.append("\(symbol.name): \(text)")
      }
    }
    guard !blurbs.isEmpty else { return nil }
    let joined = blurbs.joined(separator: " ")
    if joined.count <= 240 { return joined }
    return String(joined.prefix(237)) + "..."
  }
}
