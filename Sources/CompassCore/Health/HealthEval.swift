import Foundation

/// Eval scoring against a fixture `bugs.toml` (icle-compatible subset).
public struct HealthBugSpec: Equatable, Sendable {
  public var id: String
  public var function: String
  public var control: Bool
  public var matchTokens: [String]

  public init(id: String, function: String, control: Bool, matchTokens: [String]) {
    self.id = id
    self.function = function
    self.control = control
    self.matchTokens = matchTokens
  }
}

public struct HealthEvalScore: Codable, Equatable, Sendable {
  public var recall: Double
  public var controlFalsePositives: Int
  public var unmatchedRealFindings: Int
  public var hits: [String]
  public var missed: [String]
  public var controlFPIds: [String]

  public init(
    recall: Double,
    controlFalsePositives: Int,
    unmatchedRealFindings: Int,
    hits: [String],
    missed: [String],
    controlFPIds: [String]
  ) {
    self.recall = recall
    self.controlFalsePositives = controlFalsePositives
    self.unmatchedRealFindings = unmatchedRealFindings
    self.hits = hits
    self.missed = missed
    self.controlFPIds = controlFPIds
  }
}

public enum HealthEval {
  public static func parseBugsTOML(_ text: String) -> [HealthBugSpec] {
    var bugs: [HealthBugSpec] = []
    var currentID: String?
    var currentFunction: String?
    var currentControl = false
    var currentMatch: [String] = []

    func flush() {
      guard let id = currentID, let function = currentFunction else { return }
      bugs.append(
        HealthBugSpec(
          id: id, function: function, control: currentControl, matchTokens: currentMatch))
      currentID = nil
      currentFunction = nil
      currentControl = false
      currentMatch = []
    }

    for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      if line.hasPrefix("#") || line.isEmpty { continue }
      if line == "[[bugs]]" {
        flush()
        continue
      }
      if line.hasPrefix("id") {
        currentID = tomlStringValue(line)
      } else if line.hasPrefix("function") {
        currentFunction = tomlStringValue(line)
      } else if line.hasPrefix("control") {
        currentControl = line.contains("true")
      } else if line.hasPrefix("match") {
        currentMatch = tomlStringArray(line)
      }
    }
    flush()
    return bugs
  }

  public static func score(bugs: [HealthBugSpec], snapshot: HealthSnapshot) -> HealthEvalScore {
    let seeded = bugs.filter { !$0.control }
    let controls = bugs.filter(\.control)
    var hits: [String] = []
    var missed: [String] = []

    for bug in seeded {
      if snapshotHasOracleHit(snapshot, tokens: bug.matchTokens) {
        hits.append(bug.id)
      } else {
        missed.append(bug.id)
      }
    }

    var controlFPIds: [String] = []
    for bug in controls {
      if snapshotHasConfirmedRealHit(snapshot, tokens: bug.matchTokens) {
        controlFPIds.append(bug.id)
      }
    }

    let recall = seeded.isEmpty ? 1.0 : Double(hits.count) / Double(seeded.count)
    let unmatched = snapshot.findings.filter(\.isConfirmedRealBug).filter { finding in
      let hay = findingHaystack(finding)
      return !bugs.contains { bug in
        bug.matchTokens.contains { hay.localizedCaseInsensitiveContains($0) }
      }
    }

    return HealthEvalScore(
      recall: recall,
      controlFalsePositives: controlFPIds.count,
      unmatchedRealFindings: unmatched.count,
      hits: hits,
      missed: missed,
      controlFPIds: controlFPIds
    )
  }

  /// Oracle evidence: failing generated test / baseline (not mutant-only).
  private static func snapshotHasOracleHit(_ snapshot: HealthSnapshot, tokens: [String]) -> Bool {
    for finding in snapshot.findings
    where finding.kind == .failingGeneratedTest || finding.kind == .baselineFailure {
      let hay = findingHaystack(finding)
      if tokens.contains(where: { hay.localizedCaseInsensitiveContains($0) }) {
        return true
      }
    }
    for test in snapshot.generatedTests where test.compiled && test.passed == false {
      let hay = (test.path + " " + test.targetHint + " " + (test.compileErrors ?? "")).lowercased()
      if tokens.contains(where: { hay.localizedCaseInsensitiveContains($0) }) {
        return true
      }
    }
    return false
  }

  private static func snapshotHasConfirmedRealHit(_ snapshot: HealthSnapshot, tokens: [String])
    -> Bool
  {
    for finding in snapshot.findings where finding.isConfirmedRealBug {
      let hay = findingHaystack(finding)
      if tokens.contains(where: { hay.localizedCaseInsensitiveContains($0) }) {
        return true
      }
    }
    return false
  }

  private static func findingHaystack(_ finding: HealthFinding) -> String {
    [
      finding.title, finding.description, finding.file, finding.testPath, finding.evidence,
      finding.triage?.rationale,
    ]
    .compactMap { $0 }
    .joined(separator: " ")
    .lowercased()
  }

  private static func tomlStringValue(_ line: String) -> String {
    if let range = line.range(of: "\"([^\"]*)\"", options: .regularExpression) {
      return String(line[range].dropFirst().dropLast())
    }
    if let eq = line.firstIndex(of: "=") {
      return
        line[line.index(after: eq)...]
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }
    return ""
  }

  private static func tomlStringArray(_ line: String) -> [String] {
    guard let start = line.firstIndex(of: "["), let end = line.lastIndex(of: "]") else {
      return []
    }
    let inner = line[line.index(after: start)..<end]
    return inner.split(separator: ",")
      .map {
        $0.trimmingCharacters(in: .whitespacesAndNewlines)
          .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
      }
      .filter { !$0.isEmpty }
  }
}
