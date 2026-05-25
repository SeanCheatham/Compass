import Foundation

/// Derives a language-specific mutation-testing shell command from the
/// Plan verify seed and repository profile. The verify command proves
/// the increment; the mutation command stress-tests whether the tests
/// would catch small defects.
enum MutationTestingCommandBuilder {
  static let environmentCommandKey = "COMPASS_MUTATION_COMMAND"

  static func build(
    language: RepositoryLanguage,
    verifyCommand: String,
    manifestHints: [RepositoryManifestHint] = [],
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> String? {
    if let override = environment[environmentCommandKey]?
      .trimmingCharacters(in: .whitespacesAndNewlines),
      !override.isEmpty
    {
      return override
    }

    let verify = verifyCommand.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !verify.isEmpty else { return nil }

    guard verifySupportsMutationTesting(language: language, verifyCommand: verify) else {
      return nil
    }

    switch language {
    case .swift:
      return swiftMutationCommand(from: verify)
    case .python:
      return pythonMutationCommand(from: verify)
    case .rust:
      return rustMutationCommand(from: verify)
    case .go:
      return goMutationCommand(from: verify)
    case .typeScriptJavaScript:
      return javascriptMutationCommand(from: verify, manifestHints: manifestHints)
    case .markdown, .other, .unknown:
      return nil
    }
  }

  /// Whether the verify seed exercises a test suite mutation tools can
  /// stress. Build-only commands like `swift build` are valid verify
  /// gates but cannot seed mutation testing.
  static func verifySupportsMutationTesting(
    language: RepositoryLanguage,
    verifyCommand: String
  ) -> Bool {
    let verify = verifyCommand.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !verify.isEmpty else { return false }
    let lower = verify.lowercased()

    switch language {
    case .swift:
      if lower.contains("swift test") { return true }
      if lower.contains("xcodebuild"), lower.contains("test") { return true }
      return false
    case .python:
      return lower.contains("pytest") || lower.contains("unittest")
    case .rust:
      return lower.contains("cargo test")
    case .go:
      return lower.hasPrefix("go test") || lower.contains(" go test ")
    case .typeScriptJavaScript:
      return lower.contains("test") || lower.contains("jest") || lower.contains("vitest")
    case .markdown, .other, .unknown:
      return false
    }
  }

  private static func swiftMutationCommand(from verify: String) -> String {
    let muterRun: String
    if let filter = extractFlagValue(from: verify, flags: ["--filter", "-F"]) {
      muterRun = "muter run --skip-update-check -- -F \(shellQuote(filter))"
    } else {
      muterRun = "muter run --skip-update-check"
    }
    return "test -f muter.conf.json || muter init; \(muterRun)"
  }

  private static func pythonMutationCommand(from verify: String) -> String {
    let lower = verify.lowercased()
    if lower.hasPrefix("pytest") {
      return "mutmut run --runner=\(shellQuote(verify))"
    }
    return "mutmut run"
  }

  private static func rustMutationCommand(from verify: String) -> String {
    if let filter = extractFlagValue(from: verify, flags: ["--filter", "--test"]) {
      return "cargo mutants --no-shuffle -j 1 -- \(shellQuote(filter))"
    }
    return "cargo mutants --no-shuffle -j 1"
  }

  private static func goMutationCommand(from verify: String) -> String {
    let packages = extractGoTestPackages(from: verify) ?? "./..."
    return "go-mutesting -test.timeout=30s \(packages)"
  }

  private static func javascriptMutationCommand(
    from verify: String,
    manifestHints: [RepositoryManifestHint]
  ) -> String? {
    guard manifestHints.contains(.packageJSON) else { return nil }
    _ = verify
    return "npx stryker run --force"
  }

  /// Exit code 127 from `/bin/zsh -lc` means the mutation runner binary
  /// was not found on the execution `PATH`.
  static let runnerNotFoundExitCode: Int32 = 127

  static func extractFlagValue(from command: String, flags: [String]) -> String? {
    let tokens = tokenize(command)
    var index = tokens.startIndex
    while index < tokens.endIndex {
      let token = tokens[index]
      for flag in flags {
        if token == flag {
          let next = tokens.index(after: index)
          guard next < tokens.endIndex else { return nil }
          let value = tokens[next]
          guard !value.hasPrefix("-") else { return nil }
          return value
        }
        if token.hasPrefix("\(flag)=") {
          let value = String(token.dropFirst(flag.count + 1))
          return value.isEmpty ? nil : value
        }
      }
      index = tokens.index(after: index)
    }
    return nil
  }

  static func extractGoTestPackages(from command: String) -> String? {
    let tokens = tokenize(command)
    guard tokens.first?.lowercased() == "go",
      tokens.dropFirst().first?.lowercased() == "test"
    else {
      return nil
    }

    let packageTokens = tokens.dropFirst(2).filter { token in
      !token.hasPrefix("-")
    }
    guard !packageTokens.isEmpty else { return nil }
    return packageTokens.joined(separator: " ")
  }

  private static func tokenize(_ command: String) -> [String] {
    var tokens: [String] = []
    var current = ""
    var inSingleQuote = false
    var inDoubleQuote = false

    for character in command {
      switch character {
      case "'":
        if !inDoubleQuote {
          inSingleQuote.toggle()
          continue
        }
        current.append(character)
      case "\"":
        if !inSingleQuote {
          inDoubleQuote.toggle()
          continue
        }
        current.append(character)
      case " ", "\t", "\n", "\r":
        if inSingleQuote || inDoubleQuote {
          current.append(character)
        } else if !current.isEmpty {
          tokens.append(current)
          current = ""
        }
      default:
        current.append(character)
      }
    }

    if !current.isEmpty {
      tokens.append(current)
    }
    return tokens
  }

  private static func shellQuote(_ value: String) -> String {
    guard !value.isEmpty else { return "''" }
    if value.range(of: #"[^A-Za-z0-9._:/=-]"#, options: .regularExpression) == nil {
      return value
    }
    return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
  }
}
