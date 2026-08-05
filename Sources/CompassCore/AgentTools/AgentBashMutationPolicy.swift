import Foundation

/// Detects shell commands that would mutate the worktree or git state.
/// Used to hard-enforce Plan/Critic (and other non-Develop) bash as read-only.
///
/// This is a defense-in-depth denylist on the command string — not a true
/// sandbox. Prefer guest path jails and VM isolation for real containment;
/// treat escapes here as bugs to close, not as an absolute boundary.
public enum AgentBashMutationPolicy {
  /// When `true`, Plan and Critic (and any non-`.develop` phase) may only
  /// run probing commands. Develop always allows mutation.
  public static func allowsMutation(for phase: AgentPhase) -> Bool {
    phase == .develop
  }

  /// Returns a human-readable rejection reason when `command` looks mutating,
  /// or `nil` when the command appears safe for read-only phases.
  public static func mutationRejectionReason(for command: String) -> String? {
    let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    if let redirect = firstRedirectMutation(in: trimmed) {
      return
        "Command appears to write via shell redirect (`\(redirect)`). Plan/Critic bash is read-only; use Develop to mutate files."
    }

    let lowered = trimmed.lowercased()
    for pattern in mutatingGitPatterns {
      if lowered.range(of: pattern, options: .regularExpression) != nil {
        return
          "Command appears to mutate git state (`\(pattern)`). Plan/Critic bash is read-only."
      }
    }
    for pattern in mutatingShellPatterns {
      if lowered.range(of: pattern, options: .regularExpression) != nil {
        return
          "Command appears to mutate the filesystem (`\(pattern)`). Plan/Critic bash is read-only; probe with read-only tools or git status/diff/log instead."
      }
    }
    for pattern in mutatingInterpreterPatterns {
      if lowered.range(of: pattern, options: .regularExpression) != nil {
        return
          "Command appears to mutate via an interpreter (`\(pattern)`). Plan/Critic bash is read-only; use Develop to mutate files."
      }
    }
    if looksLikeUncheckedFormatter(lowered) {
      return
        "Command appears to rewrite sources in place (formatter without `--check` / `--dry-run`). Plan/Critic bash is read-only; use `--check` or Develop."
    }
    return nil
  }

  // MARK: - Patterns

  /// File-clobbering redirects, excluding stderr-only `2>` / `2>>`.
  private static func firstRedirectMutation(in command: String) -> String? {
    // Match standalone >, >>, >| not preceded by a digit (stderr) and not >>& / >&
    // Comparison operators inside `[` / `[[` / `test` are a false-positive risk;
    // require whitespace or start before `>` and a non-`&` after.
    let pattern = #"(?:^|[\s;|&])(\d*)(>>?\|?|>\|)(?!&)"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let ns = command as NSString
    let range = NSRange(location: 0, length: ns.length)
    let matches = regex.matches(in: command, range: range)
    for match in matches {
      let digits = match.range(at: 1)
      let op = match.range(at: 2)
      // Allow 2> / 2>> (stderr redirect); keep scanning for later stdout redirects.
      if digits.location != NSNotFound, digits.length > 0 {
        let fd = ns.substring(with: digits)
        if fd == "2" { continue }
      }
      guard op.location != NSNotFound else { continue }
      return ns.substring(with: op)
    }
    return nil
  }

  private static let mutatingGitPatterns: [String] = [
    #"\bgit\s+add\b"#,
    #"\bgit\s+commit\b"#,
    #"\bgit\s+push\b"#,
    #"\bgit\s+pull\b"#,
    #"\bgit\s+fetch\b"#,
    #"\bgit\s+merge\b"#,
    #"\bgit\s+rebase\b"#,
    #"\bgit\s+cherry-pick\b"#,
    #"\bgit\s+reset\b"#,
    #"\bgit\s+revert\b"#,
    #"\bgit\s+stash\b"#,
    #"\bgit\s+checkout\b"#,
    #"\bgit\s+switch\b"#,
    #"\bgit\s+branch\s+(-d|-D|-m|-M)\b"#,
    #"\bgit\s+tag\s+(-d)\b"#,
    #"\bgit\s+clean\b"#,
    #"\bgit\s+rm\b"#,
    #"\bgit\s+mv\b"#,
    #"\bgit\s+update-ref\b"#,
    #"\bgit\s+symbolic-ref\b"#,
    #"\bgit\s+notes\b"#,
    #"\bgit\s+am\b"#,
    #"\bgit\s+apply\b"#,
  ]

  private static let mutatingShellPatterns: [String] = [
    #"(?:^|[\s;|&])rm\b"#,
    #"(?:^|[\s;|&])rmdir\b"#,
    #"(?:^|[\s;|&])mv\b"#,
    #"(?:^|[\s;|&])cp\b"#,
    #"(?:^|[\s;|&])mkdir\b"#,
    #"(?:^|[\s;|&])touch\b"#,
    #"(?:^|[\s;|&])chmod\b"#,
    #"(?:^|[\s;|&])chown\b"#,
    #"(?:^|[\s;|&])ln\b"#,
    #"(?:^|[\s;|&])tee\b"#,
    #"(?:^|[\s;|&])install\b"#,
    #"(?:^|[\s;|&])truncate\b"#,
    #"(?:^|[\s;|&])dd\b"#,
    #"(?:^|[\s;|&])patch\b"#,
    #"\bsed\s+[^\n]*-i\b"#,
    #"\bperl\s+[^\n]*-i\b"#,
    #"\bruby\s+[^\n]*-i\b"#,
    #"\bnpm\s+(install|i|ci|uninstall|update|link)\b"#,
    #"\byarn\s+(add|remove|install)\b"#,
    #"\bpnpm\s+(add|remove|install)\b"#,
    #"\bcargo\s+(install|uninstall|publish|init|new)\b"#,
    #"\bpip3?\s+install\b"#,
    #"\bswift\s+package\s+(update|resolve|reset)\b"#,
  ]

  /// Interpreters that can open files for write without shell redirects.
  private static let mutatingInterpreterPatterns: [String] = [
    #"\bpython3?\s+-c\b"#,
    #"\bruby\s+-e\b"#,
    #"\bperl\s+-e\b"#,
    #"\bnode\s+(-e|--eval)\b"#,
    #"\bosascript\b"#,
    #"\bphp\s+-r\b"#,
  ]

  /// Formatters that rewrite sources unless given a check/dry-run flag.
  private static func looksLikeUncheckedFormatter(_ lowered: String) -> Bool {
    if lowered.range(of: #"\bcargo\s+fmt\b"#, options: .regularExpression) != nil,
      !lowered.contains("--check")
    {
      return true
    }
    if lowered.range(of: #"\brustfmt\b"#, options: .regularExpression) != nil,
      !lowered.contains("--check"), !lowered.contains("--dry-run")
    {
      return true
    }
    if lowered.range(of: #"\bswift-format\b"#, options: .regularExpression) != nil,
      !lowered.contains("dry-run"), !lowered.contains(" -n"), !lowered.hasSuffix(" -n")
    {
      return true
    }
    if lowered.range(of: #"\bclang-format\b"#, options: .regularExpression) != nil,
      !lowered.contains("--dry-run"), !lowered.contains(" -n"), !lowered.hasSuffix(" -n")
    {
      return true
    }
    return false
  }
}
