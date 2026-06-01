import Foundation

struct AssumptionDraft: Codable, Equatable, Sendable {
  var text: String
  var rationale: String?
  var evidence: [String]?
  var impact: String?
  var invalidation: String?
  var scope: AssumptionRecord.Scope?
}

struct AssumptionRecord: Codable, Identifiable, Equatable, Sendable {
  static let textLimit = 420
  static let detailLimit = 360
  static let commentLimit = 520
  static let evidenceLimit = 5

  enum Status: String, Codable, CaseIterable, Sendable {
    case implicit
    case affirmed
    case denied
    case superseded

    var displayName: String {
      switch self {
      case .implicit: return "Implicit"
      case .affirmed: return "Affirmed"
      case .denied: return "Denied"
      case .superseded: return "Superseded"
      }
    }

    var promptLabel: String {
      switch self {
      case .implicit:
        return "Implicit assumption, treated as true with lower confidence"
      case .affirmed:
        return "User-affirmed assumption, strong guidance"
      case .denied:
        return "User-denied assumption, correction"
      case .superseded:
        return "Superseded assumption"
      }
    }
  }

  enum Scope: String, Codable, CaseIterable, Sendable {
    case project
    case feature
    case session

    var displayName: String {
      rawValue.capitalized
    }
  }

  var id: String
  var text: String
  var rationale: String
  var evidence: [String]
  var impact: String
  var invalidation: String
  var scope: Scope
  var status: Status
  var createdByPhase: String
  var createdInSession: Int?
  var createdAt: Double
  var updatedAt: Double
  var userComment: String?
  var supersededBy: String?

  init(
    id: String = UUID().uuidString,
    text: String,
    rationale: String = "",
    evidence: [String] = [],
    impact: String = "",
    invalidation: String = "",
    scope: Scope = .project,
    status: Status = .implicit,
    createdByPhase: String,
    createdInSession: Int? = nil,
    createdAt: Double = Date().timeIntervalSince1970,
    updatedAt: Double? = nil,
    userComment: String? = nil,
    supersededBy: String? = nil
  ) {
    self.id = id
    self.text = Self.sanitized(text, limit: Self.textLimit)
    self.rationale = Self.sanitized(rationale, limit: Self.detailLimit)
    self.evidence = Self.sanitizedEvidence(evidence)
    self.impact = Self.sanitized(impact, limit: Self.detailLimit)
    self.invalidation = Self.sanitized(invalidation, limit: Self.detailLimit)
    self.scope = scope
    self.status = status
    self.createdByPhase = Self.sanitized(createdByPhase, limit: 32)
    self.createdInSession = createdInSession.flatMap { $0 > 0 ? $0 : nil }
    self.createdAt = createdAt
    self.updatedAt = updatedAt ?? createdAt
    self.userComment = Self.optionalSanitized(userComment, limit: Self.commentLimit)
    self.supersededBy = Self.optionalSanitized(supersededBy, limit: 80)
  }

  init(draft: AssumptionDraft, phase: AgentPhase, sessionNumber: Int?, now: Date = Date()) throws {
    let text = Self.sanitized(draft.text, limit: Self.textLimit)
    guard !text.isEmpty else {
      throw AssumptionLedgerError.emptyAssumption
    }
    let rationale = Self.sanitized(draft.rationale ?? "", limit: Self.detailLimit)
    guard !rationale.isEmpty else {
      throw AssumptionLedgerError.emptyRationale
    }
    let impact = Self.sanitized(draft.impact ?? "", limit: Self.detailLimit)
    guard !impact.isEmpty else {
      throw AssumptionLedgerError.emptyImpact
    }
    let timestamp = now.timeIntervalSince1970
    self.init(
      text: text,
      rationale: rationale,
      evidence: draft.evidence ?? [],
      impact: impact,
      invalidation: draft.invalidation ?? "",
      scope: draft.scope ?? .project,
      status: .implicit,
      createdByPhase: phase.rawValue,
      createdInSession: sessionNumber,
      createdAt: timestamp,
      updatedAt: timestamp
    )
  }

  var normalizedTextKey: String {
    Self.normalizedKey(text)
  }

  var createdAtDate: Date {
    Date(timeIntervalSince1970: createdAt)
  }

  var updatedAtDate: Date {
    Date(timeIntervalSince1970: updatedAt)
  }

  mutating func mergeNewObservation(from draft: AssumptionDraft, phase: AgentPhase, now: Date) {
    let incoming = try? AssumptionRecord(
      draft: draft,
      phase: phase,
      sessionNumber: createdInSession,
      now: now
    )
    guard let incoming else { return }
    if rationale.isEmpty {
      rationale = incoming.rationale
    }
    if impact.isEmpty {
      impact = incoming.impact
    }
    if invalidation.isEmpty {
      invalidation = incoming.invalidation
    }
    evidence = Self.sanitizedEvidence(evidence + incoming.evidence)
    updatedAt = now.timeIntervalSince1970
  }

  func reviewed(
    status: Status,
    comment: String?,
    now: Date = Date()
  ) throws -> AssumptionRecord {
    guard status == .affirmed || status == .denied || status == .implicit else {
      throw AssumptionLedgerError.unsupportedReviewStatus(status.rawValue)
    }
    var copy = self
    copy.status = status
    copy.userComment = Self.optionalSanitized(comment, limit: Self.commentLimit)
    copy.updatedAt = now.timeIntervalSince1970
    return copy
  }

  func removed(
    comment: String?,
    now: Date = Date()
  ) -> AssumptionRecord {
    var copy = self
    copy.status = .superseded
    copy.userComment = Self.optionalSanitized(comment, limit: Self.commentLimit)
    copy.updatedAt = now.timeIntervalSince1970
    return copy
  }

  static func normalizedKey(_ text: String) -> String {
    sanitized(text, limit: textLimit)
      .lowercased()
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func sanitized(_ value: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    let normalized =
      value
      .replacingOccurrences(of: "\r", with: "\n")
      .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalized.count > limit else { return normalized }
    return normalized.prefix(limit)
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }

  static func optionalSanitized(_ value: String?, limit: Int) -> String? {
    let sanitized = sanitized(value ?? "", limit: limit)
    return sanitized.isEmpty ? nil : sanitized
  }

  private static func sanitizedEvidence(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    for value in values {
      let item = sanitized(value, limit: detailLimit)
      guard !item.isEmpty else { continue }
      let key = normalizedKey(item)
      guard seen.insert(key).inserted else { continue }
      out.append(item)
      if out.count >= evidenceLimit { break }
    }
    return out
  }
}

struct AssumptionLedger: Codable, Equatable, Sendable {
  static let empty = AssumptionLedger()
  static let emptyJSON = "{\n  \"assumptions\" : []\n}\n"
  static let promptBucketLimit = 10

  var assumptions: [AssumptionRecord]

  init(assumptions: [AssumptionRecord] = []) {
    self.assumptions = assumptions
  }

  var activeAssumptions: [AssumptionRecord] {
    assumptions.filter { $0.status != .superseded }
  }

  var archivedCount: Int {
    assumptions.filter { $0.status == .superseded }.count
  }

  var implicitCount: Int {
    activeAssumptions.filter { $0.status == .implicit }.count
  }

  var affirmedCount: Int {
    activeAssumptions.filter { $0.status == .affirmed }.count
  }

  var deniedCount: Int {
    activeAssumptions.filter { $0.status == .denied }.count
  }

  mutating func record(
    draft: AssumptionDraft,
    phase: AgentPhase,
    sessionNumber: Int?,
    now: Date = Date()
  ) throws -> AssumptionRecord {
    let candidate = try AssumptionRecord(
      draft: draft,
      phase: phase,
      sessionNumber: sessionNumber,
      now: now
    )
    if let index = assumptions.firstIndex(where: {
      $0.status != .superseded && $0.normalizedTextKey == candidate.normalizedTextKey
    }) {
      assumptions[index].mergeNewObservation(from: draft, phase: phase, now: now)
      return assumptions[index]
    }
    assumptions.append(candidate)
    return candidate
  }

  mutating func review(
    id: String,
    status: AssumptionRecord.Status,
    comment: String?,
    now: Date = Date()
  ) throws -> AssumptionRecord {
    guard let index = assumptions.firstIndex(where: { $0.id == id }) else {
      throw AssumptionLedgerError.assumptionNotFound(id)
    }
    let reviewed = try assumptions[index].reviewed(status: status, comment: comment, now: now)
    assumptions[index] = reviewed
    return reviewed
  }

  mutating func remove(
    id: String,
    comment: String?,
    now: Date = Date()
  ) throws -> AssumptionRecord {
    guard let index = assumptions.firstIndex(where: { $0.id == id }) else {
      throw AssumptionLedgerError.assumptionNotFound(id)
    }
    let removed = assumptions[index].removed(comment: comment, now: now)
    assumptions[index] = removed
    return removed
  }

  func formattedForPrompt() -> String {
    let affirmed = promptRecords(status: .affirmed)
    let implicit = promptRecords(status: .implicit)
    let denied = promptRecords(status: .denied)
    guard !affirmed.isEmpty || !implicit.isEmpty || !denied.isEmpty else { return "" }

    var sections: [String] = []
    appendPromptSection(
      title: "User-affirmed assumptions (strong guidance)",
      records: affirmed,
      to: &sections
    )
    appendPromptSection(
      title: "Implicit assumptions (treated as true with lower confidence)",
      records: implicit,
      to: &sections
    )
    appendPromptSection(
      title: "Denied assumptions (user corrections; do not rely on these)",
      records: denied,
      to: &sections
    )
    return sections.joined(separator: "\n\n")
  }

  private func promptRecords(status: AssumptionRecord.Status) -> [AssumptionRecord] {
    activeAssumptions
      .filter { $0.status == status }
      .sorted { $0.updatedAt > $1.updatedAt }
      .prefix(Self.promptBucketLimit)
      .map { $0 }
  }

  private func appendPromptSection(
    title: String,
    records: [AssumptionRecord],
    to sections: inout [String]
  ) {
    guard !records.isEmpty else { return }
    let lines = records.map { record in
      var parts = [
        "- [\(record.id)] \(record.text)",
        "Scope: \(record.scope.displayName)",
      ]
      if let session = record.createdInSession {
        parts.append("Session: #\(session)")
      }
      if !record.impact.isEmpty {
        parts.append("Impact: \(record.impact)")
      }
      if !record.rationale.isEmpty {
        parts.append("Why: \(record.rationale)")
      }
      if !record.evidence.isEmpty {
        parts.append("Evidence: \(record.evidence.joined(separator: "; "))")
      }
      if !record.invalidation.isEmpty {
        parts.append("Invalidated by: \(record.invalidation)")
      }
      if let comment = record.userComment, !comment.isEmpty {
        parts.append("User comment: \(comment)")
      }
      return parts.joined(separator: " ")
    }
    sections.append(([title] + lines).joined(separator: "\n"))
  }
}

struct AssumptionLedgerStore: Sendable {
  var url: URL

  func read() throws -> AssumptionLedger {
    guard FileManager.default.fileExists(atPath: url.path) else {
      return .empty
    }
    let data = try Data(contentsOf: url)
    guard !data.isEmpty else { return .empty }
    let decoder = JSONDecoder()
    if let ledger = try? decoder.decode(AssumptionLedger.self, from: data) {
      return ledger
    }
    let legacyRecords = try decoder.decode([AssumptionRecord].self, from: data)
    return AssumptionLedger(assumptions: legacyRecords)
  }

  func write(_ ledger: AssumptionLedger) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(ledger)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try data.write(to: url, options: .atomic)
  }

  func record(
    draft: AssumptionDraft,
    phase: AgentPhase,
    sessionNumber: Int?,
    now: Date = Date()
  ) throws -> AssumptionRecord {
    var ledger = try read()
    let record = try ledger.record(
      draft: draft,
      phase: phase,
      sessionNumber: sessionNumber,
      now: now
    )
    try write(ledger)
    return record
  }

  func review(
    id: String,
    status: AssumptionRecord.Status,
    comment: String?,
    now: Date = Date()
  ) throws -> AssumptionRecord {
    var ledger = try read()
    let record = try ledger.review(id: id, status: status, comment: comment, now: now)
    try write(ledger)
    return record
  }

  func remove(
    id: String,
    comment: String?,
    now: Date = Date()
  ) throws -> AssumptionRecord {
    var ledger = try read()
    let record = try ledger.remove(id: id, comment: comment, now: now)
    try write(ledger)
    return record
  }
}

enum AssumptionLedgerError: LocalizedError, Equatable {
  case emptyAssumption
  case emptyRationale
  case emptyImpact
  case assumptionNotFound(String)
  case unsupportedReviewStatus(String)

  var errorDescription: String? {
    switch self {
    case .emptyAssumption:
      return "Assumption text cannot be empty."
    case .emptyRationale:
      return "Assumption rationale cannot be empty; explain why this guess seems reasonable."
    case .emptyImpact:
      return "Assumption impact cannot be empty; describe what decision depends on this assumption."
    case .assumptionNotFound(let id):
      return "Assumption not found: \(id)."
    case .unsupportedReviewStatus(let status):
      return "Unsupported assumption review status: \(status)."
    }
  }
}

extension CompassWorkspace {
  func readAssumptionLedger() throws -> AssumptionLedger {
    try AssumptionLedgerStore(url: assumptionsURL).read()
  }

  func writeAssumptionLedger(_ ledger: AssumptionLedger) throws {
    try AssumptionLedgerStore(url: assumptionsURL).write(ledger)
  }

  func recordAssumption(
    _ draft: AssumptionDraft,
    phase: AgentPhase,
    sessionNumber: Int?
  ) throws -> AssumptionRecord {
    try AssumptionLedgerStore(url: assumptionsURL).record(
      draft: draft,
      phase: phase,
      sessionNumber: sessionNumber
    )
  }

  func reviewAssumption(
    id: String,
    status: AssumptionRecord.Status,
    comment: String?
  ) throws -> AssumptionRecord {
    try AssumptionLedgerStore(url: assumptionsURL).review(
      id: id,
      status: status,
      comment: comment
    )
  }

  func removeAssumption(
    id: String,
    comment: String?
  ) throws -> AssumptionRecord {
    try AssumptionLedgerStore(url: assumptionsURL).remove(
      id: id,
      comment: comment
    )
  }
}
