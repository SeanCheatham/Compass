import CryptoKit
import Foundation

struct PMFEvidenceRecord: Codable, Equatable, Identifiable, Sendable {
  static let supportedSchemaVersion = 1

  var id: String
  var schemaVersion: Int
  var projectID: String?
  var commitSHA: String?
  var hypothesisID: String
  var personaID: String
  var taskID: String
  var scenarioID: String
  var startedAt: Double
  var endedAt: Double
  var status: PMFRunStatus
  var route: String
  var model: String
  var promptVersions: [String]
  var experienceTraceHash: String?
  var actionTranscript: PMFRunTranscript
  var feedback: PMFFeedbackRecord?
  var artifacts: [PMFRunArtifact]
  var failure: PMFRunFailure?

  init(
    id: String,
    schemaVersion: Int = Self.supportedSchemaVersion,
    projectID: String? = nil,
    commitSHA: String? = nil,
    hypothesisID: String,
    personaID: String,
    taskID: String,
    scenarioID: String,
    startedAt: Double,
    endedAt: Double,
    status: PMFRunStatus,
    route: String,
    model: String,
    promptVersions: [String],
    experienceTraceHash: String? = nil,
    actionTranscript: PMFRunTranscript,
    feedback: PMFFeedbackRecord? = nil,
    artifacts: [PMFRunArtifact] = [],
    failure: PMFRunFailure? = nil
  ) {
    self.id = Self.cleanedIdentifier(id, fallback: "pmf-run")
    self.schemaVersion = schemaVersion
    self.projectID = projectID
    self.commitSHA = Self.optionalBounded(commitSHA, limit: 80)
    self.hypothesisID = Self.cleanedIdentifier(hypothesisID, fallback: "hypothesis")
    self.personaID = Self.cleanedIdentifier(personaID, fallback: "persona")
    self.taskID = Self.cleanedIdentifier(taskID, fallback: "task")
    self.scenarioID = Self.cleanedIdentifier(scenarioID, fallback: "scenario")
    self.startedAt = startedAt
    self.endedAt = max(startedAt, endedAt)
    self.status = status
    self.route = StringUtils.boundedText(route, limit: 120)
    self.model = StringUtils.boundedText(model, limit: 160)
    self.promptVersions = Self.cleanedList(promptVersions)
    self.experienceTraceHash = Self.optionalBounded(experienceTraceHash, limit: 128)
    self.actionTranscript = actionTranscript
    self.feedback = feedback
    self.artifacts = artifacts
    self.failure = failure
  }

  init(
    runResult: PMFRunResult,
    id: String = UUID().uuidString,
    commitSHA: String? = nil,
    startedAt: Double,
    endedAt: Double,
    feedback: PMFFeedbackRecord? = nil
  ) {
    let transcript = PMFRunTranscript(runResult: runResult)
    self.init(
      id: id,
      projectID: runResult.projectID?.uuidString,
      commitSHA: commitSHA,
      hypothesisID: runResult.hypothesisID,
      personaID: runResult.personaID,
      taskID: runResult.taskID,
      scenarioID: runResult.scenarioID,
      startedAt: startedAt,
      endedAt: endedAt,
      status: runResult.status,
      route: runResult.routeIdentifier,
      model: runResult.model,
      promptVersions: transcript.promptVersions + (feedback.map { [$0.promptVersionID] } ?? []),
      experienceTraceHash: runResult.experienceTraceHash,
      actionTranscript: transcript,
      feedback: feedback,
      failure: runResult.failure
    )
  }

  var summary: PMFEvidenceSummary {
    PMFEvidenceSummary(record: self)
  }

  private static func cleanedIdentifier(_ value: String, fallback: String) -> String {
    let cleaned =
      value
      .lowercased()
      .replacingOccurrences(of: #"[^a-z0-9_.-]+"#, with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return String((cleaned.isEmpty ? fallback : cleaned).prefix(96))
  }

  private static func cleanedList(_ values: [String]) -> [String] {
    values
      .map { StringUtils.boundedText($0, limit: 160) }
      .filter { !$0.isEmpty }
      .uniquedPreservingOrder()
  }

  private static func optionalBounded(_ value: String?, limit: Int) -> String? {
    let bounded = StringUtils.boundedText(value ?? "", limit: limit)
    return bounded.isEmpty ? nil : bounded
  }
}

struct PMFRunTranscript: Codable, Equatable, Sendable {
  var turns: [PMFActionTurnRecord]
  var rawEntryCount: Int

  init(turns: [PMFActionTurnRecord], rawEntryCount: Int? = nil) {
    self.turns = turns
    self.rawEntryCount = rawEntryCount ?? turns.count
  }

  init(runResult: PMFRunResult) {
    let entries = runResult.rawPersonaActionTranscript
    let turns = entries.enumerated().map { offset, entry in
      let action = runResult.actions.indices.contains(offset) ? runResult.actions[offset] : nil
      return PMFActionTurnRecord(
        turnIndex: entry.turnIndex,
        phase: entry.phase,
        promptVersionID: entry.promptVersionID,
        actionID: entry.chosenActionID,
        params: action?.params ?? .object([:]),
        wasValid: entry.wasValid,
        allowedActionIDs: entry.allowedActionIDs,
        rationale: entry.rationale,
        rawResponse: entry.rawResponse
      )
    }
    self.init(turns: turns, rawEntryCount: entries.count)
  }

  var promptVersions: [String] {
    turns.map(\.promptVersionID).uniquedPreservingOrder()
  }
}

struct PMFActionTurnRecord: Codable, Equatable, Sendable {
  var turnIndex: Int
  var phase: PMFPersonaActionTranscriptEntry.Phase
  var promptVersionID: String
  var actionID: String
  var params: PMFJSONValue
  var wasValid: Bool
  var allowedActionIDs: [String]
  var rationale: String
  var rawResponse: String
}

struct PMFFeedbackRecord: Codable, Equatable, Sendable {
  var promptVersionID: String
  var valueScore: Int
  var clarityScore: Int
  var trustScore: Int
  var switchLikelihood: Int
  var payLikelihood: Int
  var taskOutcome: PMFTaskOutcome
  var topObjection: String
  var missingCapability: String
  var momentOfDelight: String?
  var momentOfConfusion: String?
  var verdict: PMFPersonaVerdict
  var summary: String
  var rawResponseArtifactPath: String?

  init(
    promptVersionID: String,
    valueScore: Int,
    clarityScore: Int,
    trustScore: Int,
    switchLikelihood: Int,
    payLikelihood: Int,
    taskOutcome: PMFTaskOutcome,
    topObjection: String,
    missingCapability: String,
    momentOfDelight: String? = nil,
    momentOfConfusion: String? = nil,
    verdict: PMFPersonaVerdict,
    summary: String,
    rawResponseArtifactPath: String? = nil
  ) {
    self.promptVersionID = promptVersionID
    self.valueScore = Self.clampedScore(valueScore)
    self.clarityScore = Self.clampedScore(clarityScore)
    self.trustScore = Self.clampedScore(trustScore)
    self.switchLikelihood = Self.clampedScore(switchLikelihood)
    self.payLikelihood = Self.clampedScore(payLikelihood)
    self.taskOutcome = taskOutcome
    self.topObjection = StringUtils.boundedText(topObjection, limit: 1_000)
    self.missingCapability = StringUtils.boundedText(missingCapability, limit: 1_000)
    self.momentOfDelight = Self.optionalBounded(momentOfDelight, limit: 1_000)
    self.momentOfConfusion = Self.optionalBounded(momentOfConfusion, limit: 1_000)
    self.verdict = verdict
    self.summary = StringUtils.boundedText(summary, limit: 1_200)
    self.rawResponseArtifactPath = Self.optionalBounded(rawResponseArtifactPath, limit: 500)
  }

  init(output: PMFFeedbackPromptOutput, rawResponseArtifactPath: String? = nil) {
    self.init(
      promptVersionID: output.promptVersionID,
      valueScore: output.valueScore,
      clarityScore: output.clarityScore,
      trustScore: output.trustScore,
      switchLikelihood: output.switchLikelihood,
      payLikelihood: output.payLikelihood,
      taskOutcome: output.taskOutcome,
      topObjection: output.topObjection,
      missingCapability: output.missingCapability,
      momentOfDelight: output.momentOfDelight,
      momentOfConfusion: output.momentOfConfusion,
      verdict: output.verdict,
      summary: output.summary,
      rawResponseArtifactPath: rawResponseArtifactPath
    )
  }

  private static func clampedScore(_ value: Int) -> Int {
    min(5, max(1, value))
  }

  private static func optionalBounded(_ value: String?, limit: Int) -> String? {
    let bounded = StringUtils.boundedText(value ?? "", limit: limit)
    return bounded.isEmpty ? nil : bounded
  }
}

struct PMFRunArtifact: Codable, Equatable, Identifiable, Sendable {
  enum Kind: String, Codable, Equatable, Sendable {
    case primaryRecord
    case experienceTrace
    case rawTranscript
    case feedbackRawResponse
    case other
  }

  var id: String
  var kind: Kind
  var path: String
  var byteCount: UInt64
  var sha256: String?

  init(
    id: String = UUID().uuidString,
    kind: Kind,
    path: String,
    byteCount: UInt64,
    sha256: String? = nil
  ) {
    self.id = id
    self.kind = kind
    self.path = StringUtils.boundedText(path, limit: 500)
    self.byteCount = byteCount
    self.sha256 = sha256
  }
}

struct PMFEvidenceSummary: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var runID: String
  var hypothesisID: String
  var personaID: String
  var taskID: String
  var scenarioID: String
  var startedAt: Double
  var endedAt: Double
  var status: PMFRunStatus
  var route: String
  var model: String
  var verdict: PMFPersonaVerdict?
  var valueScore: Int?
  var clarityScore: Int?
  var trustScore: Int?
  var switchLikelihood: Int?
  var payLikelihood: Int?
  var topObjection: String?
  var taskOutcome: PMFTaskOutcome?
  var failureKind: String?
  var experienceTraceHash: String?
  var artifactCount: Int

  init(record: PMFEvidenceRecord) {
    id = record.id
    runID = record.id
    hypothesisID = record.hypothesisID
    personaID = record.personaID
    taskID = record.taskID
    scenarioID = record.scenarioID
    startedAt = record.startedAt
    endedAt = record.endedAt
    status = record.status
    route = record.route
    model = record.model
    verdict = record.feedback?.verdict
    valueScore = record.feedback?.valueScore
    clarityScore = record.feedback?.clarityScore
    trustScore = record.feedback?.trustScore
    switchLikelihood = record.feedback?.switchLikelihood
    payLikelihood = record.feedback?.payLikelihood
    topObjection = record.feedback?.topObjection
    taskOutcome = record.feedback?.taskOutcome
    failureKind = record.failure?.status.rawValue
    experienceTraceHash = record.experienceTraceHash
    artifactCount = record.artifacts.count
  }

  var isCompleted: Bool {
    status == .completed
  }
}

struct PMFEvidenceIndex: Codable, Equatable, Sendable {
  static let supportedSchemaVersion = 1
  static let empty = PMFEvidenceIndex()

  var schemaVersion: Int
  var updatedAt: Double
  var summaries: [PMFEvidenceSummary]
  var aggregate: PMFEvidenceAggregateSummary
  var malformedRecordCount: Int

  init(
    schemaVersion: Int = Self.supportedSchemaVersion,
    updatedAt: Double = 0,
    summaries: [PMFEvidenceSummary] = [],
    aggregate: PMFEvidenceAggregateSummary = .empty,
    malformedRecordCount: Int = 0
  ) {
    self.schemaVersion = schemaVersion
    self.updatedAt = updatedAt
    self.summaries = summaries.sorted { lhs, rhs in
      if lhs.endedAt == rhs.endedAt { return lhs.runID < rhs.runID }
      return lhs.endedAt > rhs.endedAt
    }
    self.aggregate = aggregate
    self.malformedRecordCount = malformedRecordCount
  }

  static func build(
    records: [PMFEvidenceRecord],
    malformedRecordCount: Int = 0,
    now: Date = Date()
  ) -> PMFEvidenceIndex {
    let summaries = records.map(\.summary)
    return PMFEvidenceIndex(
      updatedAt: now.timeIntervalSince1970,
      summaries: summaries,
      aggregate: PMFEvidenceAggregateSummary(summaries: summaries),
      malformedRecordCount: malformedRecordCount
    )
  }
}

struct PMFEvidenceAggregateSummary: Codable, Equatable, Sendable {
  static let empty = PMFEvidenceAggregateSummary(
    repeatedObjections: [],
    averageScoresByPersonaTask: [],
    verdictCounts: [:],
    latestRunByScenario: [:],
    failuresByKind: [:]
  )

  var repeatedObjections: [PMFRepeatedObjection]
  var averageScoresByPersonaTask: [PMFScoreAverage]
  var verdictCounts: [String: Int]
  var latestRunByScenario: [String: String]
  var failuresByKind: [String: Int]

  init(
    repeatedObjections: [PMFRepeatedObjection],
    averageScoresByPersonaTask: [PMFScoreAverage],
    verdictCounts: [String: Int],
    latestRunByScenario: [String: String],
    failuresByKind: [String: Int]
  ) {
    self.repeatedObjections = repeatedObjections
    self.averageScoresByPersonaTask = averageScoresByPersonaTask
    self.verdictCounts = verdictCounts
    self.latestRunByScenario = latestRunByScenario
    self.failuresByKind = failuresByKind
  }

  init(summaries: [PMFEvidenceSummary]) {
    let objectionCounts = Dictionary(
      grouping: summaries.compactMap { summary -> String? in
        guard let objection = summary.topObjection?.normalizedPMFEvidenceText,
          !objection.isEmpty
        else { return nil }
        return objection
      },
      by: { $0 }
    ).mapValues(\.count)

    repeatedObjections = objectionCounts
      .filter { $0.value > 1 }
      .map { PMFRepeatedObjection(objection: $0.key, count: $0.value) }
      .sorted { lhs, rhs in
        if lhs.count == rhs.count { return lhs.objection < rhs.objection }
        return lhs.count > rhs.count
      }

    let scoreGroups = Dictionary(grouping: summaries.filter { $0.valueScore != nil }) {
      "\($0.personaID)|\($0.taskID)"
    }
    averageScoresByPersonaTask = scoreGroups.map { _, group in
      PMFScoreAverage(summaries: group)
    }
    .sorted { lhs, rhs in
      if lhs.personaID == rhs.personaID { return lhs.taskID < rhs.taskID }
      return lhs.personaID < rhs.personaID
    }

    verdictCounts = Dictionary(
      grouping: summaries.compactMap { $0.verdict?.rawValue },
      by: { $0 }
    ).mapValues(\.count)

    var latest: [String: PMFEvidenceSummary] = [:]
    for summary in summaries {
      if let current = latest[summary.scenarioID] {
        if summary.endedAt > current.endedAt
          || (summary.endedAt == current.endedAt && summary.runID < current.runID)
        {
          latest[summary.scenarioID] = summary
        }
      } else {
        latest[summary.scenarioID] = summary
      }
    }
    latestRunByScenario = latest.mapValues(\.runID)

    failuresByKind = Dictionary(
      grouping: summaries.compactMap { summary -> String? in
        guard !summary.isCompleted else { return nil }
        return summary.failureKind ?? summary.status.rawValue
      },
      by: { $0 }
    ).mapValues(\.count)
  }
}

struct PMFRepeatedObjection: Codable, Equatable, Sendable {
  var objection: String
  var count: Int
}

struct PMFScoreAverage: Codable, Equatable, Sendable {
  var personaID: String
  var taskID: String
  var runCount: Int
  var valueScore: Double
  var clarityScore: Double
  var trustScore: Double
  var switchLikelihood: Double
  var payLikelihood: Double

  init(summaries: [PMFEvidenceSummary]) {
    let first = summaries.first
    personaID = first?.personaID ?? ""
    taskID = first?.taskID ?? ""
    runCount = summaries.count
    valueScore = Self.average(summaries.compactMap(\.valueScore))
    clarityScore = Self.average(summaries.compactMap(\.clarityScore))
    trustScore = Self.average(summaries.compactMap(\.trustScore))
    switchLikelihood = Self.average(summaries.compactMap(\.switchLikelihood))
    payLikelihood = Self.average(summaries.compactMap(\.payLikelihood))
  }

  private static func average(_ values: [Int]) -> Double {
    guard !values.isEmpty else { return 0 }
    let raw = Double(values.reduce(0, +)) / Double(values.count)
    return (raw * 100).rounded() / 100
  }
}

struct PMFEvidenceStore {
  var compassURL: URL

  init(workspace: CompassWorkspace) {
    self.compassURL = workspace.compassURL
  }

  var pmfURL: URL { compassURL.appending(path: "pmf", directoryHint: .isDirectory) }
  var runsURL: URL { pmfURL.appending(path: "runs", directoryHint: .isDirectory) }
  var indexURL: URL { pmfURL.appending(path: "evidence-index.json") }

  func readIndex() throws -> PMFEvidenceIndex {
    guard FileManager.default.fileExists(atPath: indexURL.path) else {
      return .empty
    }
    let data = try Data(contentsOf: indexURL)
    guard !data.isEmpty else { return .empty }
    return try JSONDecoder().decode(PMFEvidenceIndex.self, from: data)
  }

  func readRecord(id: String) throws -> PMFEvidenceRecord {
    let data = try Data(contentsOf: recordURL(id: id))
    return try JSONDecoder().decode(PMFEvidenceRecord.self, from: data)
  }

  @discardableResult
  func writeRecord(
    _ record: PMFEvidenceRecord,
    experienceTraceJSON: String? = nil,
    rawTranscriptJSON: String? = nil,
    now: Date = Date()
  ) throws -> PMFEvidenceRecord {
    try FileManager.default.createDirectory(at: runsURL, withIntermediateDirectories: true)
    var stored = record
    var artifacts = stored.artifacts
    if let experienceTraceJSON, !experienceTraceJSON.isEmpty {
      artifacts.append(
        try writeArtifact(
          runID: stored.id,
          suffix: "trace",
          kind: .experienceTrace,
          contents: experienceTraceJSON
        ))
    }
    if let rawTranscriptJSON, !rawTranscriptJSON.isEmpty {
      artifacts.append(
        try writeArtifact(
          runID: stored.id,
          suffix: "raw-transcript",
          kind: .rawTranscript,
          contents: rawTranscriptJSON
        ))
    }
    stored.artifacts = artifacts.uniquedArtifacts()
    let data = try Self.encoder().encode(stored)
    try data.write(to: recordURL(id: stored.id), options: .atomic)
    _ = try rebuildIndex(now: now)
    return stored
  }

  @discardableResult
  func rebuildIndex(now: Date = Date()) throws -> PMFEvidenceIndex {
    try FileManager.default.createDirectory(at: runsURL, withIntermediateDirectories: true)
    let urls = try FileManager.default.contentsOfDirectory(
      at: runsURL,
      includingPropertiesForKeys: nil
    )
    var records: [PMFEvidenceRecord] = []
    var malformed = 0
    for url in urls where isPrimaryRecordURL(url) {
      do {
        records.append(try JSONDecoder().decode(PMFEvidenceRecord.self, from: Data(contentsOf: url)))
      } catch {
        malformed += 1
      }
    }
    let index = PMFEvidenceIndex.build(records: records, malformedRecordCount: malformed, now: now)
    let data = try Self.encoder().encode(index)
    try FileManager.default.createDirectory(at: pmfURL, withIntermediateDirectories: true)
    try data.write(to: indexURL, options: .atomic)
    return index
  }

  func recordURL(id: String) -> URL {
    runsURL.appending(path: "\(Self.safeRunID(id)).json")
  }

  private func writeArtifact(
    runID: String,
    suffix: String,
    kind: PMFRunArtifact.Kind,
    contents: String
  ) throws -> PMFRunArtifact {
    let safeID = Self.safeRunID(runID)
    let fileName = "\(safeID)-\(suffix).json"
    let url = runsURL.appending(path: fileName)
    let data = Data(contents.utf8)
    try data.write(to: url, options: .atomic)
    return PMFRunArtifact(
      kind: kind,
      path: "pmf/runs/\(fileName)",
      byteCount: UInt64(data.count),
      sha256: Self.sha256Hex(data)
    )
  }

  private func isPrimaryRecordURL(_ url: URL) -> Bool {
    guard url.pathExtension == "json" else { return false }
    let name = url.deletingPathExtension().lastPathComponent
    return !name.hasSuffix("-trace")
      && !name.hasSuffix("-raw-transcript")
      && !name.hasSuffix("-feedback-raw")
  }

  private static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return encoder
  }

  static func safeRunID(_ id: String) -> String {
    let cleaned =
      id
      .lowercased()
      .replacingOccurrences(of: #"[^a-z0-9_.-]+"#, with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return String((cleaned.isEmpty ? "pmf-run" : cleaned).prefix(96))
  }

  private static func sha256Hex(_ data: Data) -> String {
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
  }
}

enum PMFEvidenceMarkdownExporter {
  static func markdown(
    record: PMFEvidenceRecord,
    config: PMFConfig = .empty
  ) -> String {
    let summary = record.summary
    let persona = config.personas.first { $0.id == record.personaID }?.name ?? record.personaID
    let task = config.tasks.first { $0.id == record.taskID }?.title ?? record.taskID
    let hypothesis =
      config.hypotheses.first { $0.id == record.hypothesisID }?.title ?? record.hypothesisID
    var lines = [
      "# PMF Evidence: \(record.id)",
      "",
      "- Hypothesis: \(hypothesis)",
      "- Persona: \(persona)",
      "- Task: \(task)",
      "- Scenario: \(record.scenarioID)",
      "- Status: \(record.status.rawValue)",
      "- Route: \(record.route)",
      "- Model: \(record.model.isEmpty ? "unspecified" : record.model)",
    ]
    if let hash = record.experienceTraceHash {
      lines.append("- Trace hash: \(hash)")
    }
    if let feedback = record.feedback {
      lines += [
        "",
        "## Feedback",
        "",
        "- Verdict: \(feedback.verdict.rawValue)",
        "- Task outcome: \(feedback.taskOutcome.rawValue)",
        "- Scores: value \(feedback.valueScore), clarity \(feedback.clarityScore), trust \(feedback.trustScore), switch \(feedback.switchLikelihood), pay \(feedback.payLikelihood)",
        "- Top objection: \(feedback.topObjection)",
        "- Missing capability: \(feedback.missingCapability)",
        "- Summary: \(feedback.summary)",
      ]
    } else if let failure = record.failure {
      lines += ["", "## Failure", "", "\(failure.message)"]
    }
    if !record.actionTranscript.turns.isEmpty {
      lines += ["", "## Actions", ""]
      for turn in record.actionTranscript.turns {
        lines.append("- \(turn.turnIndex): \(turn.actionID) - \(turn.rationale)")
      }
    }
    if !record.artifacts.isEmpty {
      lines += ["", "## Artifacts", ""]
      for artifact in record.artifacts {
        lines.append("- \(artifact.kind.rawValue): \(artifact.path)")
      }
    }
    if let objection = summary.topObjection, !objection.isEmpty {
      lines += ["", "Primary objection: \(objection)"]
    }
    return lines.joined(separator: "\n") + "\n"
  }
}

private extension Array where Element == String {
  func uniquedPreservingOrder() -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    for value in self where !seen.contains(value) {
      seen.insert(value)
      out.append(value)
    }
    return out
  }
}

private extension Array where Element == PMFRunArtifact {
  func uniquedArtifacts() -> [PMFRunArtifact] {
    var seen = Set<String>()
    var out: [PMFRunArtifact] = []
    for artifact in self {
      let key = "\(artifact.kind.rawValue)|\(artifact.path)"
      guard !seen.contains(key) else { continue }
      seen.insert(key)
      out.append(artifact)
    }
    return out
  }
}

private extension String {
  var normalizedPMFEvidenceText: String {
    lowercased()
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
