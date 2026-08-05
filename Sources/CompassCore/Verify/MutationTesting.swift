import Foundation

/// Mutation testing evidence collected from `cargo mutants` after a green verify.
public struct MutationSnapshot: Codable, Equatable, Sendable {
  public var collectedAt: Date
  public var sessionNumber: Int?
  public var command: String
  public var exitCode: Int
  public var caught: Int
  public var missed: Int
  public var timeout: Int
  public var unviable: Int
  public var missedMutants: [String]
  public var rawSummary: String?

  public var tested: Int { caught + missed + timeout }

  /// Kill rate over viable mutants (unviable mutants are excluded).
  public var mutationScorePercent: Double? {
    guard tested > 0 else { return nil }
    return Double(caught) / Double(tested) * 100
  }

  public func formattedForPrompt(maxMissed: Int = 10) -> String {
    guard tested > 0 || !missedMutants.isEmpty else {
      return "_(no mutation data collected yet)_"
    }
    var lines: [String] = []
    if let score = mutationScorePercent {
      lines.append(
        String(
          format: "Mutation score: %.1f%% (%d caught, %d missed, %d timeout, %d unviable)",
          score, caught, missed, timeout, unviable))
    } else {
      lines.append("Mutation run: \(caught) caught, \(missed) missed, \(timeout) timeout.")
    }
    for mutant in missedMutants.prefix(maxMissed) {
      lines.append("- SURVIVED: \(mutant)")
    }
    if missedMutants.count > maxMissed {
      lines.append("_(+\(missedMutants.count - maxMissed) more surviving mutants)_")
    }
    return lines.joined(separator: "\n")
  }
}

public enum MutationSnapshotStore {
  public static func mutationSnapshotURL(in workspace: CompassWorkspace) -> URL {
    workspace.compassURL.appending(path: "mutation-snapshot.json")
  }

  public static func readMutationSnapshot(from workspace: CompassWorkspace) -> MutationSnapshot? {
    let url = mutationSnapshotURL(in: workspace)
    guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(MutationSnapshot.self, from: data)
  }

  public static func writeMutationSnapshot(_ snapshot: MutationSnapshot, workspace: CompassWorkspace)
    throws
  {
    let url = mutationSnapshotURL(in: workspace)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(snapshot).write(to: url, options: .atomic)
  }
}

/// Tolerant parser for `cargo mutants` console output.
///
/// Recognizes the final tally line (`N mutants tested: X caught, Y missed, ...`)
/// and surviving mutant lines (`<file>.rs:<line>: <description> ... missed` or
/// listed under a `Missed mutants:` section).
public enum MutationReportParser {
  public static func parse(output: String, exitCode: Int, command: String) -> MutationSnapshot {
    var snapshot = MutationSnapshot(
      collectedAt: Date(),
      sessionNumber: nil,
      command: command,
      exitCode: exitCode,
      caught: trailingCount(#"(\d+)\s+caught"#, in: output) ?? 0,
      missed: trailingCount(#"(\d+)\s+missed"#, in: output) ?? 0,
      timeout: trailingCount(#"(\d+)\s+timeouts?"#, in: output) ?? 0,
      unviable: trailingCount(#"(\d+)\s+unviable"#, in: output) ?? 0,
      missedMutants: missedMutantDescriptions(in: output),
      rawSummary: String(output.suffix(4000))
    )
    if snapshot.missed == 0, !snapshot.missedMutants.isEmpty {
      snapshot.missed = snapshot.missedMutants.count
    }
    return snapshot
  }

  private static func trailingCount(_ pattern: String, in output: String) -> Int? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(output.startIndex..<output.endIndex, in: output)
    let matches = regex.matches(in: output, range: range)
    guard let last = matches.last, last.numberOfRanges > 1,
      let valueRange = Range(last.range(at: 1), in: output)
    else { return nil }
    return Int(output[valueRange])
  }

  private static func missedMutantDescriptions(in output: String) -> [String] {
    var descriptions: [String] = []
    var inMissedSection = false
    for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      if line.lowercased().hasPrefix("missed mutants") {
        inMissedSection = true
        continue
      }
      if inMissedSection {
        if line.isEmpty || !line.contains(".rs") {
          inMissedSection = false
        } else {
          if !descriptions.contains(line) {
            descriptions.append(line)
          }
          continue
        }
      }
      let lowered = line.lowercased()
      guard line.contains(".rs") else { continue }
      let cleaned: String
      if let prefixed = stripStatusPrefix(["missed", "not caught", "not_caught"], from: lowered, original: line) {
        cleaned = strippingTimingSuffix(from: prefixed)
      } else if lowered.hasSuffix("missed") || lowered.hasSuffix("not caught")
        || lowered.contains("... missed") || lowered.contains("... not caught")
      {
        cleaned =
          line
          .replacingOccurrences(of: #"\s*\.\.\.\s*(missed|not caught).*$"#, with: "", options: .regularExpression)
      } else {
        continue
      }
      if !cleaned.isEmpty, !descriptions.contains(cleaned) {
        descriptions.append(cleaned)
      }
    }
    return descriptions
  }

  /// Matches lines like `MISSED   crates/app.rs:1:1: replace ...` emitted by
  /// `cargo mutants`, returning the description with the status prefix removed.
  private static func stripStatusPrefix(
    _ prefixes: [String], from lowered: String, original: String
  ) -> String? {
    for prefix in prefixes {
      guard lowered.hasPrefix(prefix) else { continue }
      let rest = original.dropFirst(prefix.count)
      guard rest.first?.isWhitespace == true else { continue }
      return rest.trimmingCharacters(in: .whitespaces)
    }
    return nil
  }

  /// Removes the trailing ` in <t> build + <t> test` timing cargo-mutants appends.
  private static func strippingTimingSuffix(from text: String) -> String {
    text.replacingOccurrences(
      of: #"\s+in\s+[\d.]+[a-z]*\s+build\s*\+\s*[\d.]+[a-z]*\s+test\s*$"#,
      with: "",
      options: [.regularExpression, .caseInsensitive]
    )
  }
}

public extension GeneratedProjectQuality {
  /// Builds a mutation command scoped to the Rust source files changed in the
  /// current iteration, so post-verify mutation runs stay fast and relevant.
  static func mutationTestCommand(forChangedFiles changedFiles: [String]) -> String {
    let sources = changedFiles.filter {
      $0.hasSuffix(".rs") && !$0.contains("/tests/") && !$0.hasSuffix("_tests.rs")
    }
    guard !sources.isEmpty else { return mutationTestCommand }
    let scope = sources.map { "-f '\($0)'" }.joined(separator: " ")
    return "\(mutationTestCommand) \(scope)"
  }
}
