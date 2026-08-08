import Foundation

public enum HealthSnapshotStore {
  public static func snapshotURL(in workspace: CompassWorkspace) -> URL {
    workspace.compassURL.appending(path: HealthPaths.snapshotFileName)
  }

  public static func findingsURL(in workspace: CompassWorkspace) -> URL {
    workspace.compassURL.appending(path: HealthPaths.findingsFileName)
  }

  public static func readSnapshot(from workspace: CompassWorkspace) -> HealthSnapshot? {
    let url = snapshotURL(in: workspace)
    guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(HealthSnapshot.self, from: data)
  }

  public static func writeSnapshot(_ snapshot: HealthSnapshot, workspace: CompassWorkspace) throws {
    let url = snapshotURL(in: workspace)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(snapshot).write(to: url, options: .atomic)
  }

  public static func writeFindingsReport(
    _ snapshot: HealthSnapshot, workspace: CompassWorkspace
  ) throws {
    let url = findingsURL(in: workspace)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(snapshot).write(to: url, options: .atomic)
  }
}

/// Deterministic demotion of invented-literal false positives.
public enum HealthFPGuards {
  public static func apply(to findings: [HealthFinding]) -> [HealthFinding] {
    findings.map { finding in
      var updated = finding
      guard finding.kind == .failingGeneratedTest,
        let triage = finding.triage, triage.isRealBug
      else { return finding }
      if inventedLiteralExpectation(in: finding.evidence + "\n" + finding.description) {
        updated.triage = HealthTriageResult(
          isRealBug: false,
          rationale: triage.rationale
            + " [demoted: invented numeric literal expectation without documented contract]"
        )
      }
      return updated
    }
  }

  /// Heuristic: failing assert_eq with naked numeric literals often invents contracts.
  public static func inventedLiteralExpectation(in text: String) -> Bool {
    let lowered = text.lowercased()
    guard lowered.contains("assert_eq") || lowered.contains("assert_ne") else { return false }
    let hasNumericLiteral =
      text.range(of: #"\b\d{2,}\b"#, options: .regularExpression) != nil
    let mentionsDocs =
      lowered.contains("rustdoc") || lowered.contains("documented") || lowered.contains("/// ")
      || lowered.contains("# ")
    return hasNumericLiteral && !mentionsDocs
  }
}
