import Foundation

public struct AssumptionDraft: Codable, Equatable, Sendable {
  public var text: String
  public var rationale: String?
  public var evidence: [String]?
  public var impact: String?
  public var invalidation: String?
  public var scope: AssumptionRecord.Scope?
}

public struct AssumptionRecord: Codable, Identifiable, Equatable, Sendable {
  public static let textLimit = 420
  public static let detailLimit = 360
  public static let commentLimit = 520
  public static let evidenceLimit = 5

  public enum Status: String, Codable, CaseIterable, Sendable {
    case implicit
    case affirmed
    case denied
    case superseded

    public var displayName: String {
      switch self {
      case .implicit: return "Implicit"
      case .affirmed: return "Affirmed"
      case .denied: return "Denied"
      case .superseded: return "Superseded"
      }
    }
  }

  public enum Scope: String, Codable, CaseIterable, Sendable {
    case project
    case feature
    case session

    public var displayName: String {
      rawValue.capitalized
    }
  }

  public var id: String
  public var text: String
  public var rationale: String
  public var evidence: [String]
  public var impact: String
  public var invalidation: String
  public var scope: Scope
  public var status: Status
  public var createdByPhase: String
  public var createdInSession: Int?
  public var createdAt: Double
  public var updatedAt: Double
  public var userComment: String?
  public var supersededBy: String?

  public init(
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

  public init(draft: AssumptionDraft, phase: AgentPhase, sessionNumber: Int?, now: Date = Date())
    throws
  {
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

  public var normalizedTextKey: String {
    Self.normalizedKey(text)
  }

  public mutating func mergeNewObservation(
    from draft: AssumptionDraft, phase: AgentPhase, now: Date
  ) {
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

  public func reviewed(
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

  public func removed(
    comment: String?,
    now: Date = Date()
  ) -> AssumptionRecord {
    var copy = self
    copy.status = .superseded
    copy.userComment = Self.optionalSanitized(comment, limit: Self.commentLimit)
    copy.updatedAt = now.timeIntervalSince1970
    return copy
  }

  public static func normalizedKey(_ text: String) -> String {
    sanitized(text, limit: textLimit)
      .lowercased()
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public static func sanitized(_ value: String, limit: Int) -> String {
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

  public static func optionalSanitized(_ value: String?, limit: Int) -> String? {
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

public struct AssumptionLedger: Codable, Equatable, Sendable {
  public static let empty = AssumptionLedger()
  public static let emptyJSON = "{\n  \"assumptions\" : []\n}\n"
  public static let promptBucketLimit = 10

  public var assumptions: [AssumptionRecord]

  public init(assumptions: [AssumptionRecord] = []) {
    self.assumptions = assumptions
  }

  public var activeAssumptions: [AssumptionRecord] {
    assumptions.filter { $0.status != .superseded }
  }

  public mutating func record(
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

  public mutating func review(
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

  public mutating func remove(
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

  public func formattedForPrompt() -> String {
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

public struct AssumptionLedgerStore: Sendable {
  public var url: URL

  public func read() throws -> AssumptionLedger {
    guard FileManager.default.fileExists(atPath: url.path) else {
      return .empty
    }
    let data = try Data(contentsOf: url)
    guard !data.isEmpty else { return .empty }
    return try JSONDecoder().decode(AssumptionLedger.self, from: data)
  }

  public func write(_ ledger: AssumptionLedger) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(ledger)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try data.write(to: url, options: .atomic)
  }

  public func record(
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

  public func review(
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

  public func remove(
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

public enum AssumptionLedgerError: LocalizedError, Equatable {
  case emptyAssumption
  case emptyRationale
  case emptyImpact
  case assumptionNotFound(String)
  case unsupportedReviewStatus(String)

  public var errorDescription: String? {
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
  public func readAssumptionLedger() throws -> AssumptionLedger {
    try AssumptionLedgerStore(url: assumptionsURL).read()
  }

  public func writeAssumptionLedger(_ ledger: AssumptionLedger) throws {
    try AssumptionLedgerStore(url: assumptionsURL).write(ledger)
  }

  public func recordAssumption(
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

  public func reviewAssumption(
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

  public func removeAssumption(
    id: String,
    comment: String?
  ) throws -> AssumptionRecord {
    try AssumptionLedgerStore(url: assumptionsURL).remove(
      id: id,
      comment: comment
    )
  }
}
