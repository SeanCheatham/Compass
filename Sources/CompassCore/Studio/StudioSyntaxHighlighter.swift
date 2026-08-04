import AppKit
import Foundation
import SwiftTreeSitter
import TreeSitterRust
import TreeSitterSwift

/// Syntax-highlights Studio editor buffers. Uses tree-sitter `highlights.scm`
/// for Swift/Rust (bundled under Resources) and a lightweight regex tokenizer
/// for other common languages so unsupported files never look broken.
public final class StudioSyntaxHighlighter: @unchecked Sendable {
  public static let shared = StudioSyntaxHighlighter()

  public struct CacheKey: Hashable, Sendable {
    public let path: String
    public let contentHash: Int
    public let appearance: StudioHighlightTheme.Appearance
  }

  private struct Entry {
    let language: CodemapLanguage
    let tsLanguage: Language
    let highlightQuery: Query
  }

  private let entries: [CodemapLanguage: Entry]
  private let lock = NSLock()
  private var cache: [CacheKey: [AttributedString]] = [:]
  private var cacheOrder: [CacheKey] = []
  private let cacheLimit = 32

  public init() {
    var map: [CodemapLanguage: Entry] = [:]
    for language in CodemapLanguage.allCases {
      if let entry = Self.loadEntry(for: language) {
        map[language] = entry
      }
    }
    self.entries = map
  }

  /// Highlight `source` for `path`, returning one `AttributedString` per line
  /// (matching `source.components(separatedBy: "\n")` count).
  public func highlightLines(
    source: String,
    path: String,
    theme: StudioHighlightTheme
  ) -> [AttributedString] {
    let key = CacheKey(
      path: path,
      contentHash: Self.contentHash(source),
      appearance: theme.appearance
    )
    lock.lock()
    if let cached = cache[key] {
      lock.unlock()
      return cached
    }
    lock.unlock()

    let lines: [AttributedString]
    if let language = CodemapLanguage.forRelativePath(path),
      let entry = entries[language],
      let treeSitter = highlightWithTreeSitter(source: source, entry: entry, theme: theme)
    {
      lines = treeSitter
    } else {
      lines = highlightWithFallback(source: source, path: path, theme: theme)
    }

    lock.lock()
    cache[key] = lines
    cacheOrder.append(key)
    if cacheOrder.count > cacheLimit {
      let evicted = cacheOrder.removeFirst()
      cache.removeValue(forKey: evicted)
    }
    lock.unlock()
    return lines
  }

  /// Whether tree-sitter highlighting is available for this path.
  public func usesTreeSitter(for path: String) -> Bool {
    guard let language = CodemapLanguage.forRelativePath(path) else { return false }
    return entries[language] != nil
  }

  public func clearCache() {
    lock.lock()
    cache.removeAll()
    cacheOrder.removeAll()
    lock.unlock()
  }

  private static func contentHash(_ source: String) -> Int {
    var hasher = Hasher()
    hasher.combine(source)
    return hasher.finalize()
  }

  // MARK: - Tree-sitter

  private func highlightWithTreeSitter(
    source: String,
    entry: Entry,
    theme: StudioHighlightTheme
  ) -> [AttributedString]? {
    let parser = Parser()
    do {
      try parser.setLanguage(entry.tsLanguage)
    } catch {
      return nil
    }
    guard let tree = parser.parse(source), let root = tree.rootNode else { return nil }

    let attributed = NSMutableAttributedString(
      string: source,
      attributes: [
        .foregroundColor: theme.defaultForeground,
        .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
      ]
    )

    let context = Predicate.Context(string: source)
    let cursor = entry.highlightQuery.execute(node: root, in: tree)
    let highlights = cursor.resolve(with: context).highlights()
    for named in highlights {
      let range = named.range
      guard range.location >= 0,
        range.location + range.length <= attributed.length
      else { continue }
      attributed.addAttribute(
        .foregroundColor,
        value: theme.color(forCapture: named.name),
        range: range
      )
    }

    return Self.splitAttributedLines(attributed)
  }

  private static func loadEntry(for language: CodemapLanguage) -> Entry? {
    let tsLanguage: Language
    let resourceName: String
    switch language {
    case .swift:
      tsLanguage = Language(language: tree_sitter_swift())
      resourceName = "swift-highlights"
    case .rust:
      tsLanguage = Language(language: tree_sitter_rust())
      resourceName = "rust-highlights"
    }
    guard let url = resourceBundle().url(forResource: resourceName, withExtension: "scm")
    else { return nil }
    do {
      let query = try Query(language: tsLanguage, url: url)
      return Entry(language: language, tsLanguage: tsLanguage, highlightQuery: query)
    } catch {
      return nil
    }
  }

  private final class BundleToken {}

  private static func resourceBundle() -> Bundle {
    #if SWIFT_PACKAGE
      return Bundle.module
    #else
      return Bundle(for: BundleToken.self)
    #endif
  }

  // MARK: - Regex fallback

  private func highlightWithFallback(
    source: String,
    path: String,
    theme: StudioHighlightTheme
  ) -> [AttributedString] {
    let ext = (path as NSString).pathExtension.lowercased()
    let profile = FallbackProfile.profile(forExtension: ext)
    let attributed = NSMutableAttributedString(
      string: source,
      attributes: [
        .foregroundColor: theme.defaultForeground,
        .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
      ]
    )
    let ns = source as NSString
    let full = NSRange(location: 0, length: ns.length)

    for rule in profile.rules {
      guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: rule.options)
      else { continue }
      regex.enumerateMatches(in: source, options: [], range: full) { match, _, _ in
        guard let match else { return }
        let range = match.range(at: rule.captureGroup)
        guard range.location != NSNotFound, range.length > 0 else { return }
        attributed.addAttribute(
          .foregroundColor,
          value: theme.color(forCapture: rule.capture),
          range: range
        )
      }
    }

    return Self.splitAttributedLines(attributed)
  }

  // MARK: - Line split

  public static func splitAttributedLines(_ attributed: NSAttributedString) -> [AttributedString] {
    let string = attributed.string
    if string.isEmpty { return [AttributedString()] }
    var lines: [AttributedString] = []
    var location = 0
    let ns = string as NSString
    let parts = string.components(separatedBy: "\n")
    for (index, part) in parts.enumerated() {
      let length = (part as NSString).length
      let range = NSRange(location: location, length: length)
      if range.location + range.length <= attributed.length {
        lines.append(AttributedString(attributed.attributedSubstring(from: range)))
      } else {
        lines.append(AttributedString(part))
      }
      location += length
      if index < parts.count - 1 {
        location += 1  // newline
      }
    }
    // Silence unused warning when ns is only for clarity
    _ = ns
    return lines
  }
}

// MARK: - Fallback profiles

private struct FallbackRule {
  let pattern: String
  let options: NSRegularExpression.Options
  let capture: String
  let captureGroup: Int

  init(
    _ pattern: String,
    options: NSRegularExpression.Options = [],
    capture: String,
    group: Int = 0
  ) {
    self.pattern = pattern
    self.options = options
    self.capture = capture
    self.captureGroup = group
  }
}

private struct FallbackProfile {
  let rules: [FallbackRule]

  static func profile(forExtension ext: String) -> FallbackProfile {
    switch ext {
    case "py":
      return FallbackProfile(rules: commonRules(lineComment: "#", keywords: pythonKeywords))
    case "js", "jsx", "ts", "tsx", "mjs", "cjs":
      return FallbackProfile(rules: commonRules(lineComment: "//", keywords: jsKeywords))
    case "go":
      return FallbackProfile(rules: commonRules(lineComment: "//", keywords: goKeywords))
    case "sh", "bash", "zsh":
      return FallbackProfile(rules: commonRules(lineComment: "#", keywords: shellKeywords))
    case "json":
      return FallbackProfile(rules: [
        FallbackRule(#""(?:\\.|[^"\\])*""#, capture: "string"),
        FallbackRule(#"\b-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#, capture: "number"),
        FallbackRule(#"\b(?:true|false|null)\b"#, capture: "keyword"),
      ])
    case "md", "markdown":
      return FallbackProfile(rules: [
        FallbackRule(#"^#{1,6}\s.*$"#, options: .anchorsMatchLines, capture: "keyword"),
        FallbackRule(#"`[^`]+`"#, capture: "string"),
        FallbackRule(#"\*\*[^*]+\*\*"#, capture: "function"),
      ])
    case "yaml", "yml", "toml":
      return FallbackProfile(rules: commonRules(lineComment: "#", keywords: []))
    case "c", "cc", "cpp", "h", "hpp", "m", "mm":
      return FallbackProfile(rules: commonRules(lineComment: "//", keywords: cKeywords))
    default:
      return FallbackProfile(rules: [
        FallbackRule(#""(?:\\.|[^"\\])*""#, capture: "string"),
        FallbackRule(#"'(?:\\.|[^'\\])*'"#, capture: "string"),
        FallbackRule(#"\b-?\d+(?:\.\d+)?\b"#, capture: "number"),
      ])
    }
  }

  private static func commonRules(lineComment: String, keywords: [String]) -> [FallbackRule] {
    var rules: [FallbackRule] = []
    let escaped = NSRegularExpression.escapedPattern(for: lineComment)
    rules.append(
      FallbackRule(
        #"\#(escaped)[^\n]*"#,
        capture: "comment"
      ))
    rules.append(FallbackRule(#"/\*[\s\S]*?\*/"#, capture: "comment"))
    rules.append(FallbackRule(#""(?:\\.|[^"\\])*""#, capture: "string"))
    rules.append(FallbackRule(#"'(?:\\.|[^'\\])*'"#, capture: "string"))
    rules.append(FallbackRule(#"`(?:\\.|[^`\\])*`"#, capture: "string"))
    rules.append(FallbackRule(#"\b-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#, capture: "number"))
    if !keywords.isEmpty {
      let joined = keywords.map { NSRegularExpression.escapedPattern(for: $0) }.joined(
        separator: "|")
      rules.append(FallbackRule(#"\b(?:\#(joined))\b"#, capture: "keyword"))
    }
    return rules
  }

  private static let pythonKeywords = [
    "def", "class", "return", "if", "elif", "else", "for", "while", "import", "from", "as",
    "try", "except", "finally", "with", "yield", "async", "await", "pass", "None", "True",
    "False", "and", "or", "not", "in", "is", "lambda", "global", "nonlocal",
  ]
  private static let jsKeywords = [
    "function", "const", "let", "var", "return", "if", "else", "for", "while", "class",
    "import", "export", "from", "async", "await", "try", "catch", "finally", "new", "this",
    "typeof", "instanceof", "true", "false", "null", "undefined", "switch", "case", "break",
  ]
  private static let goKeywords = [
    "func", "package", "import", "return", "if", "else", "for", "range", "go", "defer",
    "struct", "interface", "type", "var", "const", "map", "chan", "select", "case", "switch",
    "true", "false", "nil",
  ]
  private static let shellKeywords = [
    "if", "then", "else", "fi", "for", "while", "do", "done", "case", "esac", "function",
    "return", "export", "local", "echo", "exit",
  ]
  private static let cKeywords = [
    "int", "void", "char", "float", "double", "return", "if", "else", "for", "while",
    "struct", "typedef", "enum", "const", "static", "extern", "sizeof", "switch", "case",
    "break", "continue", "true", "false", "nullptr", "class", "public", "private",
  ]
}
