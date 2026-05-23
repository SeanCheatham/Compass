import Foundation

enum MutationTestingPresentationSanitizer {
  static func field(
    _ text: String,
    limit: Int,
    fallback: String = "none"
  ) -> String {
    let sanitized = bounded(
      redactSensitiveText(
        normalizedSingleLine(text)
      ),
      limit: limit,
      preservesNewlines: false
    )
    return sanitized.isEmpty ? fallback : sanitized
  }

  static func identifier(
    _ text: String,
    fallback: String,
    limit: Int
  ) -> String {
    let normalized = field(text, limit: limit, fallback: fallback)
      .lowercased()
    let filtered = String(
      normalized.unicodeScalars.map { scalar in
        if isASCIILetter(scalar)
          || isASCIIDigit(scalar)
          || scalar == "-"
          || scalar == "_"
          || scalar == "."
        {
          return Character(scalar)
        }
        return "-"
      }
    )
    .replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
    .trimmingCharacters(in: CharacterSet(charactersIn: "-_."))
    return filtered.isEmpty ? fallback : filtered
  }

  static func outputTail(
    _ text: String,
    limit: Int,
    lineLimit: Int = 6
  ) -> String {
    guard limit > 0, lineLimit > 0 else { return "" }

    let normalized =
      text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    let tailInput: String
    if normalized.count > limit {
      let marker = "...(truncated)...\n"
      let suffixLimit = max(0, limit - marker.count)
      tailInput = marker + String(normalized.suffix(suffixLimit))
    } else {
      tailInput = normalized
    }

    let redacted = redactSensitiveText(tailInput)
      .replacingOccurrences(of: #"[ \t\f\v]+"#, with: " ", options: .regularExpression)
      .replacingOccurrences(of: #"\n{4,}"#, with: "\n\n\n", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let lines =
      redacted
      .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    let boundedLines = Array(lines.suffix(lineLimit))
    return bounded(
      boundedLines.joined(separator: "\n"),
      limit: limit,
      preservesNewlines: true
    )
  }

  static func statusIdentifier(_ text: String) -> String {
    let identifier = identifier(
      text, fallback: "unknown", limit: SessionMutationTestingExecution.fieldLimit)
    switch identifier {
    case "succeeded", "failed":
      return identifier
    default:
      return "unknown"
    }
  }

  static func statusLabel(_ identifier: String) -> String {
    switch identifier {
    case "succeeded":
      return "Succeeded"
    case "failed":
      return "Failed"
    default:
      return "Unknown"
    }
  }

  static func routeIdentifier(_ text: String) -> String {
    let identifier = identifier(
      text, fallback: "unknown", limit: SessionMutationTestingExecution.fieldLimit)
    switch identifier {
    case AgentMutationTestingPlan.RouteState.nativeRoute.rawValue,
      AgentMutationTestingPlan.RouteState.sharedVMRoute.rawValue,
      AgentMutationTestingPlan.RouteState.nativeFallback.rawValue:
      return identifier
    default:
      return "unknown"
    }
  }

  static func routeLabel(_ identifier: String) -> String {
    switch identifier {
    case AgentMutationTestingPlan.RouteState.nativeRoute.rawValue:
      return "Native"
    case AgentMutationTestingPlan.RouteState.sharedVMRoute.rawValue:
      return "Shared VM"
    case AgentMutationTestingPlan.RouteState.nativeFallback.rawValue:
      return "Native fallback"
    default:
      return "Unknown route"
    }
  }

  static func languageIdentifier(_ text: String) -> String {
    let identifier = identifier(
      text, fallback: "unknown", limit: SessionMutationTestingExecution.fieldLimit)
    switch identifier {
    case "swift",
      "typescript-javascript",
      "python",
      "go",
      "rust",
      "markdown",
      "other",
      "unknown":
      return identifier
    default:
      return "unknown"
    }
  }

  static func languageLabel(_ identifier: String) -> String {
    switch identifier {
    case "swift":
      return "Swift"
    case "typescript-javascript":
      return "TypeScript/JavaScript"
    case "python":
      return "Python"
    case "go":
      return "Go"
    case "rust":
      return "Rust"
    case "markdown":
      return "Markdown"
    case "other":
      return "Other"
    default:
      return "Unknown"
    }
  }

  static func exitCodeLabel(_ exitCode: Int?) -> String {
    exitCode.map { "exit \($0)" } ?? "exit unknown"
  }

  static func durationLabel(startedAt: Double, endedAt: Double) -> String {
    let milliseconds = max(0, endedAt - startedAt)
    if milliseconds < 1_000 {
      return "\(Int(milliseconds.rounded())) ms"
    }
    if milliseconds < 60_000 {
      return String(format: "%.1f s", milliseconds / 1_000)
    }
    let minutes = Int(milliseconds / 60_000)
    let seconds = Int((milliseconds.truncatingRemainder(dividingBy: 60_000)) / 1_000)
    return "\(minutes)m \(seconds)s"
  }

  static func bounded(
    _ text: String,
    limit: Int,
    preservesNewlines: Bool = false
  ) -> String {
    guard limit > 0 else { return "" }
    let normalized: String
    if preservesNewlines {
      normalized =
        text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    } else {
      normalized = normalizedSingleLine(text)
    }
    guard normalized.count <= limit else {
      let prefixLimit = max(1, limit - 3)
      return normalized.prefix(prefixLimit)
        .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
    return normalized
  }

  static func markdownSection(_ text: String, limit: Int) -> String {
    bounded(text, limit: limit, preservesNewlines: true)
  }

  static func fingerprint(_ value: String) -> String {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in value.utf8 {
      hash ^= UInt64(byte)
      hash = hash &* 0x100_0000_01b3
    }
    return String(format: "%016llx", hash)
  }

  private static func normalizedSingleLine(_ text: String) -> String {
    text
      .replacingOccurrences(of: "\r", with: " ")
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func redactSensitiveText(_ text: String) -> String {
    var sanitized = text

    let replacements: [(pattern: String, template: String)] = [
      (
        #"(?:(?:file://)?/(?:Users|private|var|tmp|opt|usr|bin|sbin|Library|Applications|Volumes)/[^\s,;)`"']+)"#,
        "[path]"
      ),
      (#"(^|[\s"'=:/])(?:\./)?\.devcontainer/[^\s"']+"#, "$1[devcontainer-path]"),
      (#"(^|[\s"'=:/])\.\./[^\s"']+"#, "$1[path]"),
      (#"ghcr\.io/devcontainers/features/[^\s,;)`"']+"#, "[feature]"),
      (#"(?i)(^|[\s"'=:/])(?:\.\./|\./)?(?:docker-)?compose[^\s"']*\.ya?ml"#, "$1[compose-path]"),
      (
        #"(?i)\b(containerEnv|container_env|buildArg|build-arg|build_arg|feature-option|featureOption|token|secret|password|passwd|api[_-]?key)\b\s*[:=]\s*[^\s,;)`"']+"#,
        "$1=[redacted]"
      ),
      (
        #"(?i)\b[A-Za-z0-9_.-]*(?:secret|token|password|passwd|apikey|api-key)[A-Za-z0-9_.-]*\b"#,
        "[redacted]"
      ),
    ]

    for replacement in replacements {
      sanitized = sanitized.replacingOccurrences(
        of: replacement.pattern,
        with: replacement.template,
        options: .regularExpression
      )
    }

    return sanitized
  }

  private static func isASCIILetter(_ scalar: UnicodeScalar) -> Bool {
    (65...90).contains(Int(scalar.value)) || (97...122).contains(Int(scalar.value))
  }

  private static func isASCIIDigit(_ scalar: UnicodeScalar) -> Bool {
    (48...57).contains(Int(scalar.value))
  }
}
