import Foundation

struct TournamentWorkspaceStore {
  var workspace: CompassWorkspace

  var tournamentURL: URL {
    workspace.compassURL.appending(path: "tournament", directoryHint: .isDirectory)
  }

  var stateURL: URL {
    tournamentURL.appending(path: "state.json")
  }

  var evidenceIndexURL: URL {
    tournamentURL.appending(path: "evidence-index.json")
  }

  var evidenceURL: URL {
    tournamentURL.appending(path: "evidence", directoryHint: .isDirectory)
  }

  var scenarioRunsURL: URL {
    evidenceURL.appending(path: "scenario-runs", directoryHint: .isDirectory)
  }

  var planEvaluationsURL: URL {
    evidenceURL.appending(path: "plan-evaluations", directoryHint: .isDirectory)
  }

  var auditsURL: URL {
    tournamentURL.appending(path: "audits", directoryHint: .isDirectory)
  }

  func readState() throws -> ProductTournamentStateV2 {
    guard FileManager.default.fileExists(atPath: stateURL.path) else {
      return .empty
    }
    let data = try Data(contentsOf: stateURL)
    guard !data.isEmpty else { return .empty }
    do {
      return try JSONDecoder().decode(ProductTournamentStateV2.self, from: data)
    } catch {
      throw TournamentWorkspaceStoreError.malformedState(stateURL.path, error.localizedDescription)
    }
  }

  func writeState(_ state: ProductTournamentStateV2) throws {
    try FileManager.default.createDirectory(at: tournamentURL, withIntermediateDirectories: true)
    let data = try Self.encoder().encode(state)
    try data.write(to: stateURL, options: .atomic)
  }

  func readEvidenceIndex() throws -> ProductTournamentEvidenceIndex {
    guard FileManager.default.fileExists(atPath: evidenceIndexURL.path) else {
      return .empty
    }
    let data = try Data(contentsOf: evidenceIndexURL)
    guard !data.isEmpty else { return .empty }
    return try JSONDecoder().decode(ProductTournamentEvidenceIndex.self, from: data)
  }

  @discardableResult
  func writeEvidenceRecord(
    _ record: ProductTournamentEvidenceRecord,
    now: Date = Date()
  ) throws -> ProductTournamentEvidenceRecord {
    let runURL = scenarioRunsURL.appending(
      path: Self.safeRecordID(record.id),
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: runURL, withIntermediateDirectories: true)
    let data = try Self.encoder().encode(record)
    try data.write(to: runURL.appending(path: "record.json"), options: .atomic)
    _ = try rebuildEvidenceIndex(now: now)
    return record
  }

  @discardableResult
  func writePlanEvaluationRecord(
    _ record: ProductTournamentPlanEvaluationRecord,
    now: Date = Date()
  ) throws -> ProductTournamentPlanEvaluationRecord {
    let evaluationURL = planEvaluationsURL.appending(
      path: Self.safeRecordID(record.id),
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: evaluationURL, withIntermediateDirectories: true)
    let data = try Self.encoder().encode(record)
    try data.write(to: evaluationURL.appending(path: "record.json"), options: .atomic)
    _ = try rebuildEvidenceIndex(now: now)
    return record
  }

  @discardableResult
  func writeAuditRecord(_ audit: TournamentAutomationCycleAudit) throws -> TournamentAutomationCycleAudit {
    try FileManager.default.createDirectory(at: auditsURL, withIntermediateDirectories: true)
    let data = try Self.encoder().encode(audit)
    try data.write(
      to: auditsURL.appending(path: "\(Self.safeRecordID(audit.id)).json"),
      options: .atomic
    )
    return audit
  }

  func readAuditRecords() throws -> [TournamentAutomationCycleAudit] {
    guard FileManager.default.fileExists(atPath: auditsURL.path) else { return [] }
    return try FileManager.default.contentsOfDirectory(
      at: auditsURL,
      includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension == "json" }
    .compactMap { url in
      try? JSONDecoder().decode(TournamentAutomationCycleAudit.self, from: Data(contentsOf: url))
    }
    .sorted { lhs, rhs in
      if lhs.endedAt == rhs.endedAt { return lhs.id < rhs.id }
      return lhs.endedAt < rhs.endedAt
    }
  }

  @discardableResult
  func rebuildEvidenceIndex(now: Date = Date()) throws -> ProductTournamentEvidenceIndex {
    try FileManager.default.createDirectory(at: scenarioRunsURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: planEvaluationsURL,
      withIntermediateDirectories: true
    )
    let records = try readEvidenceRecords(from: scenarioRunsURL, as: ProductTournamentEvidenceRecord.self)
    let planEvaluationRecords = try readEvidenceRecords(
      from: planEvaluationsURL,
      as: ProductTournamentPlanEvaluationRecord.self
    )
    let index = ProductTournamentEvidenceIndex.build(
      records: records.values,
      planEvaluationRecords: planEvaluationRecords.values,
      malformedRecordCount: records.malformedCount + planEvaluationRecords.malformedCount,
      now: now
    )
    let data = try Self.encoder().encode(index)
    try FileManager.default.createDirectory(at: tournamentURL, withIntermediateDirectories: true)
    try data.write(to: evidenceIndexURL, options: .atomic)
    return index
  }

  private func readEvidenceRecords<Record: Decodable>(
    from rootURL: URL,
    as type: Record.Type
  ) throws -> (values: [Record], malformedCount: Int) {
    guard FileManager.default.fileExists(atPath: rootURL.path) else {
      return ([], 0)
    }
    let urls = try FileManager.default.contentsOfDirectory(
      at: rootURL,
      includingPropertiesForKeys: nil
    )
    var values: [Record] = []
    var malformedCount = 0
    for url in urls {
      var isDirectory: ObjCBool = false
      guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
        isDirectory.boolValue
      else { continue }
      do {
        let data = try Data(contentsOf: url.appending(path: "record.json"))
        values.append(try JSONDecoder().decode(Record.self, from: data))
      } catch {
        malformedCount += 1
      }
    }
    return (values, malformedCount)
  }

  private static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return encoder
  }

  private static func safeRecordID(_ id: String) -> String {
    ProductTournamentEvidenceRecord.cleanedIdentifier(id, fallback: "tournament-record")
  }
}

enum TournamentWorkspaceStoreError: LocalizedError, Equatable {
  case malformedState(String, String)

  var errorDescription: String? {
    switch self {
    case .malformedState(let path, let detail):
      return "Tournament state at \(path) is malformed: \(detail)"
    }
  }
}
