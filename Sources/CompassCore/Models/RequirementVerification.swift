import Foundation

// MARK: - User-owned requirement taxonomy (lives on ProductRequirement)

public enum ProductRequirementKind: String, Codable, Equatable, Sendable, CaseIterable {
  case behavior
  case ux
  case constraint
  case nonfunctional
  case narrative

  public var title: String {
    switch self {
    case .behavior: return "Behavior"
    case .ux: return "UX"
    case .constraint: return "Constraint"
    case .nonfunctional: return "Non-functional"
    case .narrative: return "Narrative"
    }
  }

  public var defaultProofLevel: RequirementProofLevel {
    switch self {
    case .behavior, .ux: return .hybrid
    case .constraint, .nonfunctional: return .deterministic
    case .narrative: return .judgment
    }
  }
}

public enum RequirementProofLevel: String, Codable, Equatable, Sendable, CaseIterable {
  /// Shell/scenario commands alone decide satisfaction.
  case deterministic
  /// Commands plus evidence-cited agent judgment.
  case hybrid
  /// Agent (or human) judgment with citations; no hard command gate.
  case judgment

  public var title: String {
    switch self {
    case .deterministic: return "Deterministic"
    case .hybrid: return "Hybrid"
    case .judgment: return "Judgment"
    }
  }
}

// MARK: - Factory-owned verification

/// Factory-owned verification status for a user product requirement.
public enum RequirementVerificationStatus: String, Codable, Equatable, Sendable, CaseIterable {
  case unverified
  case satisfied
  case unsatisfied
  /// Was satisfied, but owned paths changed without revalidation.
  case stale

  public var countsAsComplete: Bool { self == .satisfied }
}

public struct RequirementAuditRecord: Codable, Equatable, Sendable {
  public var verdict: RequirementVerificationStatus
  public var evidence: [String]
  public var commit: String?
  public var timestamp: Double

  public init(
    verdict: RequirementVerificationStatus,
    evidence: [String] = [],
    commit: String? = nil,
    timestamp: Double = Date().timeIntervalSince1970 * 1000
  ) {
    switch verdict {
    case .unverified:
      self.verdict = .unsatisfied
    case .satisfied, .unsatisfied, .stale:
      self.verdict = verdict
    }
    self.evidence =
      evidence
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    let trimmedCommit = commit?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    self.commit = trimmedCommit.isEmpty ? nil : trimmedCommit
    self.timestamp = timestamp
  }
}

/// One shipped iteration that advanced a requirement.
public struct RequirementShipTrace: Codable, Equatable, Sendable {
  public var session: Int?
  public var commit: String?
  public var verify: String?
  public var planSummary: String?
  public var timestamp: Double

  public init(
    session: Int? = nil,
    commit: String? = nil,
    verify: String? = nil,
    planSummary: String? = nil,
    timestamp: Double = Date().timeIntervalSince1970 * 1000
  ) {
    self.session = session
    let trimmedCommit = commit?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    self.commit = trimmedCommit.isEmpty ? nil : trimmedCommit
    let trimmedVerify = verify?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    self.verify = trimmedVerify.isEmpty ? nil : trimmedVerify
    let trimmedPlan = planSummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    self.planSummary = trimmedPlan.isEmpty ? nil : String(trimmedPlan.prefix(240))
    self.timestamp = timestamp
  }
}

/// Structured acceptance scenario; optional `command` is the executable check.
public struct RequirementScenario: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var given: String
  public var whenAction: String
  public var thenExpectations: [String]
  public var command: String?

  public enum CodingKeys: String, CodingKey {
    case id
    case given
    case whenAction
    case when
    case whenActionSnake = "when_action"
    case thenExpectations
    case then
    case thenExpectationsSnake = "then_expectations"
    case command
  }

  public init(
    id: String = UUID().uuidString.lowercased(),
    given: String = "",
    whenAction: String = "",
    thenExpectations: [String] = [],
    command: String? = nil
  ) {
    self.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
    self.given = given.trimmingCharacters(in: .whitespacesAndNewlines)
    self.whenAction = whenAction.trimmingCharacters(in: .whitespacesAndNewlines)
    self.thenExpectations =
      thenExpectations
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    let trimmedCommand = command?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    self.command = trimmedCommand.isEmpty ? nil : trimmedCommand
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let rawID = try container.decodeIfPresent(String.self, forKey: .id)
    let id = (rawID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let given =
      (try container.decodeIfPresent(String.self, forKey: .given))?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    let whenPrimary = try container.decodeIfPresent(String.self, forKey: .whenAction)
    let whenAlias = try container.decodeIfPresent(String.self, forKey: .when)
    let whenSnake = try container.decodeIfPresent(String.self, forKey: .whenActionSnake)
    let whenAction =
      (whenPrimary ?? whenAlias ?? whenSnake)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    let thenPrimary = try container.decodeIfPresent([String].self, forKey: .thenExpectations)
    let thenAlias = try container.decodeIfPresent([String].self, forKey: .then)
    let thenSnake = try container.decodeIfPresent([String].self, forKey: .thenExpectationsSnake)
    let then = thenPrimary ?? thenAlias ?? thenSnake ?? []

    let command =
      (try container.decodeIfPresent(String.self, forKey: .command))?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    self.init(
      id: id.isEmpty ? UUID().uuidString.lowercased() : id,
      given: given,
      whenAction: whenAction,
      thenExpectations: then,
      command: command
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(given, forKey: .given)
    try container.encode(whenAction, forKey: .whenAction)
    try container.encode(thenExpectations, forKey: .thenExpectations)
    try container.encodeIfPresent(command, forKey: .command)
  }

  public var isEmpty: Bool {
    given.isEmpty && whenAction.isEmpty && thenExpectations.isEmpty && (command?.isEmpty ?? true)
  }

  public var renderedMarkdown: String {
    var lines: [String] = []
    if !given.isEmpty { lines.append("Given \(given)") }
    if !whenAction.isEmpty { lines.append("When \(whenAction)") }
    for expectation in thenExpectations {
      lines.append("Then \(expectation)")
    }
    if let command, !command.isEmpty {
      lines.append("Command: `\(command)`")
    }
    return lines.joined(separator: "\n")
  }
}

public struct RequirementLedgerEntry: Codable, Equatable, Identifiable, Sendable {
  public var requirementID: String
  /// Freeform shell checks (legacy + auditor-proposed).
  public var criteria: [String]
  /// Structured Given/When/Then scenarios with optional executable commands.
  public var scenarios: [RequirementScenario]
  /// Repo-relative path prefixes this requirement owns for staleness.
  public var ownedPaths: [String]
  public var status: RequirementVerificationStatus
  public var lastAudit: RequirementAuditRecord?
  public var shipTraces: [RequirementShipTrace]
  public var satisfiedAt: Double?
  public var satisfiedCommit: String?
  public var lastRevalidatedAt: Double?
  public var lastRevalidatedCommit: String?

  public var id: String { requirementID }

  public init(
    requirementID: String,
    criteria: [String] = [],
    scenarios: [RequirementScenario] = [],
    ownedPaths: [String] = [],
    status: RequirementVerificationStatus = .unverified,
    lastAudit: RequirementAuditRecord? = nil,
    shipTraces: [RequirementShipTrace] = [],
    satisfiedAt: Double? = nil,
    satisfiedCommit: String? = nil,
    lastRevalidatedAt: Double? = nil,
    lastRevalidatedCommit: String? = nil
  ) {
    self.requirementID = requirementID.trimmingCharacters(in: .whitespacesAndNewlines)
    self.criteria = Self.cleanedStrings(criteria)
    self.scenarios = scenarios.filter { !$0.isEmpty }
    self.ownedPaths = Self.cleanedStrings(ownedPaths)
    self.status = status
    self.lastAudit = lastAudit
    self.shipTraces = shipTraces
    self.satisfiedAt = satisfiedAt
    let trimmedSatisfied = satisfiedCommit?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    self.satisfiedCommit = trimmedSatisfied.isEmpty ? nil : trimmedSatisfied
    self.lastRevalidatedAt = lastRevalidatedAt
    let trimmedRevalidated =
      lastRevalidatedCommit?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    self.lastRevalidatedCommit = trimmedRevalidated.isEmpty ? nil : trimmedRevalidated
  }

  public var sanitized: RequirementLedgerEntry {
    RequirementLedgerEntry(
      requirementID: requirementID,
      criteria: criteria,
      scenarios: scenarios,
      ownedPaths: ownedPaths,
      status: status,
      lastAudit: lastAudit,
      shipTraces: shipTraces,
      satisfiedAt: satisfiedAt,
      satisfiedCommit: satisfiedCommit,
      lastRevalidatedAt: lastRevalidatedAt,
      lastRevalidatedCommit: lastRevalidatedCommit
    )
  }

  /// Shell commands to run for deterministic / hybrid proof.
  public var executableCommands: [String] {
    var seen = Set<String>()
    var commands: [String] = []
    for command in criteria + scenarios.compactMap(\.command) {
      if seen.insert(command).inserted {
        commands.append(command)
      }
    }
    return commands
  }

  private static func cleanedStrings(_ values: [String]) -> [String] {
    values
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }
}

/// Agent submit payload for one requirement under audit.
public struct RequirementAuditItemResult: Codable, Equatable, Sendable {
  public var requirementID: String
  public var verdict: RequirementVerificationStatus
  public var evidence: [String]
  public var proposedCriteria: [String]
  public var proposedOwnedPaths: [String]
  public var proposedScenarios: [RequirementScenario]

  public enum CodingKeys: String, CodingKey {
    case requirementID
    case requirementIDSnake = "requirement_id"
    case verdict
    case evidence
    case proposedCriteria
    case proposedCriteriaSnake = "proposed_criteria"
    case proposedOwnedPaths
    case proposedOwnedPathsSnake = "proposed_owned_paths"
    case proposedScenarios
    case proposedScenariosSnake = "proposed_scenarios"
  }

  public init(
    requirementID: String,
    verdict: RequirementVerificationStatus,
    evidence: [String] = [],
    proposedCriteria: [String] = [],
    proposedOwnedPaths: [String] = [],
    proposedScenarios: [RequirementScenario] = []
  ) {
    self.requirementID = requirementID.trimmingCharacters(in: .whitespacesAndNewlines)
    switch verdict {
    case .unverified:
      self.verdict = .unsatisfied
    case .satisfied, .unsatisfied, .stale:
      self.verdict = verdict == .stale ? .unsatisfied : verdict
    }
    self.evidence =
      evidence
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    self.proposedCriteria =
      proposedCriteria
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    self.proposedOwnedPaths =
      proposedOwnedPaths
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    self.proposedScenarios = proposedScenarios.filter { !$0.isEmpty }
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let id =
      try FlexibleModelDecoder.decodeStringIfPresent(
        from: container,
        preferredKey: .requirementID,
        aliases: [.requirementIDSnake]
      )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !id.isEmpty else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: decoder.codingPath,
          debugDescription: "Requirement audit item requires requirementID."
        )
      )
    }
    let rawVerdict =
      (try FlexibleModelDecoder.decodeStringIfPresent(
        from: container,
        preferredKey: .verdict,
        aliases: []
      ) ?? "unsatisfied")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    let verdict: RequirementVerificationStatus =
      switch rawVerdict {
      case "satisfied", "pass", "passed", "ok":
        .satisfied
      case "stale":
        .stale
      case "unverified":
        .unverified
      default:
        .unsatisfied
      }
    let evidence =
      (try? container.decodeIfPresent([String].self, forKey: .evidence))
      ?? []
    let proposed =
      (try? container.decodeIfPresent([String].self, forKey: .proposedCriteria))
      ?? (try? container.decodeIfPresent([String].self, forKey: .proposedCriteriaSnake))
      ?? []
    let owned =
      (try? container.decodeIfPresent([String].self, forKey: .proposedOwnedPaths))
      ?? (try? container.decodeIfPresent([String].self, forKey: .proposedOwnedPathsSnake))
      ?? []
    let scenarios =
      (try? container.decodeIfPresent([RequirementScenario].self, forKey: .proposedScenarios))
      ?? (try? container.decodeIfPresent(
        [RequirementScenario].self, forKey: .proposedScenariosSnake))
      ?? []
    self.init(
      requirementID: id,
      verdict: verdict,
      evidence: evidence,
      proposedCriteria: proposed,
      proposedOwnedPaths: owned,
      proposedScenarios: scenarios
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(requirementID, forKey: .requirementID)
    try container.encode(verdict.rawValue, forKey: .verdict)
    try container.encode(evidence, forKey: .evidence)
    try container.encode(proposedCriteria, forKey: .proposedCriteria)
    try container.encode(proposedOwnedPaths, forKey: .proposedOwnedPaths)
    try container.encode(proposedScenarios, forKey: .proposedScenarios)
  }
}

public struct RequirementsAuditResult: Codable, Equatable, Sendable {
  public var results: [RequirementAuditItemResult]
  public var summary: String

  public init(results: [RequirementAuditItemResult] = [], summary: String = "") {
    self.results = results
    self.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

/// Deterministic criterion run outcome used as a hard override on agent verdicts.
public struct RequirementCriterionResult: Equatable, Sendable {
  public var requirementID: String
  public var command: String
  public var exitCode: Int
  public var output: String

  public var passed: Bool { exitCode == 0 }

  public init(requirementID: String, command: String, exitCode: Int, output: String) {
    self.requirementID = requirementID
    self.command = command
    self.exitCode = exitCode
    self.output = output
  }
}

public struct RequirementLedger: Codable, Equatable, Sendable {
  public var entries: [RequirementLedgerEntry]

  public static let empty = RequirementLedger(entries: [])

  public static let emptyJSON = """
    {
      "entries" : [

      ]
    }
    """

  public init(entries: [RequirementLedgerEntry] = []) {
    self.entries = entries.map(\.sanitized).filter { !$0.requirementID.isEmpty }
  }

  public var isEmpty: Bool { entries.isEmpty }

  public func entry(for requirementID: String) -> RequirementLedgerEntry? {
    entries.first { $0.requirementID == requirementID }
  }

  public var allSatisfied: Bool {
    !entries.isEmpty && entries.allSatisfy(\.status.countsAsComplete)
  }

  public var unsatisfiedEntries: [RequirementLedgerEntry] {
    entries.filter { !$0.status.countsAsComplete }
  }

  public var hasUnsatisfied: Bool {
    entries.contains { !$0.status.countsAsComplete }
  }

  /// Align ledger entries with the current brief: create missing, drop deleted.
  public func reconciled(with brief: ProjectBrief) -> RequirementLedger {
    var byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.requirementID, $0) })
    var next: [RequirementLedgerEntry] = []
    for requirement in brief.nonEmptyRequirements {
      if let existing = byID.removeValue(forKey: requirement.id) {
        next.append(existing.sanitized)
      } else {
        next.append(RequirementLedgerEntry(requirementID: requirement.id))
      }
    }
    return RequirementLedger(entries: next)
  }

  public func updating(
    requirementID: String,
    status: RequirementVerificationStatus,
    audit: RequirementAuditRecord,
    proposedCriteria: [String] = [],
    proposedOwnedPaths: [String] = [],
    proposedScenarios: [RequirementScenario] = []
  ) -> RequirementLedger {
    var next = entries
    if let index = next.firstIndex(where: { $0.requirementID == requirementID }) {
      var entry = next[index]
      entry.status = status
      entry.lastAudit = audit
      if !proposedCriteria.isEmpty {
        var merged = entry.criteria
        for criterion in proposedCriteria where !merged.contains(criterion) {
          merged.append(criterion)
        }
        entry.criteria = merged
      }
      if !proposedOwnedPaths.isEmpty {
        var merged = entry.ownedPaths
        for path in proposedOwnedPaths where !merged.contains(path) {
          merged.append(path)
        }
        entry.ownedPaths = merged
      }
      if !proposedScenarios.isEmpty {
        var merged = entry.scenarios
        for scenario in proposedScenarios {
          if let existing = merged.firstIndex(where: { $0.id == scenario.id }) {
            merged[existing] = scenario
          } else if !merged.contains(where: {
            $0.whenAction == scenario.whenAction && $0.command == scenario.command
          }) {
            merged.append(scenario)
          }
        }
        entry.scenarios = merged
      }
      if status == .satisfied {
        if entry.satisfiedAt == nil {
          entry.satisfiedAt = audit.timestamp
          entry.satisfiedCommit = audit.commit
        }
        entry.lastRevalidatedAt = audit.timestamp
        entry.lastRevalidatedCommit = audit.commit
      } else if status == .unsatisfied || status == .stale {
        // Keep satisfiedAt history; clear only on unsatisfied reset of "current" satisfaction.
        if status == .unsatisfied {
          // Do not wipe satisfiedAt — it is first-green history.
        }
      }
      next[index] = entry.sanitized
    } else {
      var entry = RequirementLedgerEntry(
        requirementID: requirementID,
        criteria: proposedCriteria,
        scenarios: proposedScenarios,
        ownedPaths: proposedOwnedPaths,
        status: status,
        lastAudit: audit
      )
      if status == .satisfied {
        entry.satisfiedAt = audit.timestamp
        entry.satisfiedCommit = audit.commit
        entry.lastRevalidatedAt = audit.timestamp
        entry.lastRevalidatedCommit = audit.commit
      }
      next.append(entry)
    }
    return RequirementLedger(entries: next)
  }

  public func updatingCriteria(requirementID: String, criteria: [String]) -> RequirementLedger {
    mutatingEntry(requirementID: requirementID) { entry in
      entry.criteria =
        criteria
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }
  }

  public func updatingOwnedPaths(requirementID: String, ownedPaths: [String]) -> RequirementLedger {
    mutatingEntry(requirementID: requirementID) { entry in
      entry.ownedPaths =
        ownedPaths
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }
  }

  public func updatingScenarios(requirementID: String, scenarios: [RequirementScenario])
    -> RequirementLedger
  {
    mutatingEntry(requirementID: requirementID) { entry in
      entry.scenarios = scenarios.filter { !$0.isEmpty }
    }
  }

  public func recordingShip(
    requirementIDs: [String],
    session: Int?,
    commit: String?,
    verify: String?,
    planSummary: String?,
    timestamp: Double = Date().timeIntervalSince1970 * 1000
  ) -> RequirementLedger {
    let ids = Set(
      requirementIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter {
        !$0.isEmpty
      }
    )
    guard !ids.isEmpty else { return self }
    let trace = RequirementShipTrace(
      session: session,
      commit: commit,
      verify: verify,
      planSummary: planSummary,
      timestamp: timestamp
    )
    var next = entries
    for index in next.indices where ids.contains(next[index].requirementID) {
      next[index].shipTraces.append(trace)
      // Cap history.
      if next[index].shipTraces.count > 20 {
        next[index].shipTraces = Array(next[index].shipTraces.suffix(20))
      }
    }
    // Create entries for targeted ids missing from ledger.
    for id in ids where !next.contains(where: { $0.requirementID == id }) {
      next.append(
        RequirementLedgerEntry(requirementID: id, shipTraces: [trace])
      )
    }
    return RequirementLedger(entries: next)
  }

  /// Mark previously satisfied requirements stale when changed paths hit owned paths.
  public func markingStale(
    changedPaths: [String],
    excludingRequirementIDs: Set<String> = []
  ) -> RequirementLedger {
    guard !changedPaths.isEmpty else { return self }
    var next = entries
    for index in next.indices {
      let entry = next[index]
      guard entry.status == .satisfied,
        !excludingRequirementIDs.contains(entry.requirementID),
        !entry.ownedPaths.isEmpty
      else { continue }
      if Self.pathsIntersect(owned: entry.ownedPaths, changed: changedPaths) {
        next[index].status = .stale
        var evidence = entry.lastAudit?.evidence ?? []
        evidence.append(
          "Marked stale: owned paths intersected changed files (\(changedPaths.prefix(5).joined(separator: ", ")))."
        )
        next[index].lastAudit = RequirementAuditRecord(
          verdict: .stale,
          evidence: evidence,
          commit: entry.lastRevalidatedCommit,
          timestamp: Date().timeIntervalSince1970 * 1000
        )
      }
    }
    return RequirementLedger(entries: next)
  }

  /// Markdown projection for Plan / audit prompts.
  public func renderedStatusMarkdown(
    brief: ProjectBrief,
    maxCharacters: Int = 4_000
  ) -> String {
    let requirements = brief.nonEmptyRequirements
    guard !requirements.isEmpty else {
      return "_(no product requirements)_"
    }
    let reconciled = reconciled(with: brief)
    var lines: [String] = []
    for requirement in requirements {
      let entry = reconciled.entry(for: requirement.id)
      let status = entry?.status.rawValue ?? RequirementVerificationStatus.unverified.rawValue
      lines.append(
        "- [\(status)] (\(requirement.kind.rawValue)/\(requirement.proofLevel.rawValue)) \(requirement.text) `(id: \(requirement.id))`"
      )
      if let owned = entry?.ownedPaths, !owned.isEmpty {
        lines.append("  Owned paths: \(owned.map { "`\($0)`" }.joined(separator: ", "))")
      }
      if let scenarios = entry?.scenarios, !scenarios.isEmpty {
        lines.append("  Scenarios:")
        for scenario in scenarios.prefix(3) {
          lines.append("  - \(scenario.whenAction.isEmpty ? "(scenario)" : scenario.whenAction)")
          if let command = scenario.command {
            lines.append("    cmd: `\(command)`")
          }
        }
      }
      let commands = entry?.executableCommands ?? []
      if !commands.isEmpty {
        lines.append("  Criteria:")
        for criterion in commands.prefix(5) {
          lines.append("  - `\(criterion)`")
        }
      } else if (entry?.scenarios.isEmpty ?? true) {
        lines.append("  Criteria: _(none — auditor should propose)_")
      }
      if let traces = entry?.shipTraces, let latest = traces.last {
        var shipBits: [String] = []
        if let session = latest.session { shipBits.append("session \(session)") }
        if let commit = latest.commit { shipBits.append("commit \(commit.prefix(8))") }
        if let verify = latest.verify { shipBits.append("verify `\(verify)`") }
        lines.append("  Latest ship: \(shipBits.joined(separator: ", "))")
      }
      if let audit = entry?.lastAudit {
        let evidence =
          audit.evidence.isEmpty
          ? "_(no evidence)_"
          : audit.evidence.prefix(3).joined(separator: "; ")
        lines.append("  Last audit: \(audit.verdict.rawValue) — \(evidence)")
      }
      if let satisfiedAt = entry?.satisfiedAt {
        lines.append(
          "  Satisfied-at: \(Int(satisfiedAt))"
            + (entry?.satisfiedCommit.map { " @ \($0.prefix(8))" } ?? "")
        )
      }
      if let revalidated = entry?.lastRevalidatedAt {
        lines.append(
          "  Last-revalidated-at: \(Int(revalidated))"
            + (entry?.lastRevalidatedCommit.map { " @ \($0.prefix(8))" } ?? "")
        )
      }
    }
    let joined = lines.joined(separator: "\n")
    guard joined.count > maxCharacters else { return joined }
    guard maxCharacters > 3 else { return String(joined.prefix(maxCharacters)) }
    return String(joined.prefix(maxCharacters - 3))
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }

  public func findingsDraft(brief: ProjectBrief) -> String {
    let reconciled = reconciled(with: brief)
    var lines: [String] = [
      "Requirements audit found incomplete product requirements. Plan the next slice to address them:"
    ]
    for requirement in brief.nonEmptyRequirements {
      guard let entry = reconciled.entry(for: requirement.id), !entry.status.countsAsComplete else {
        continue
      }
      let evidence =
        entry.lastAudit?.evidence.prefix(2).joined(separator: "; ")
        ?? "no evidence yet"
      lines.append(
        "- [\(entry.status.rawValue)] \(requirement.text) (id: \(requirement.id), \(requirement.kind.rawValue)/\(requirement.proofLevel.rawValue)): \(evidence)"
      )
    }
    return lines.joined(separator: "\n")
  }

  private func mutatingEntry(
    requirementID: String,
    mutate: (inout RequirementLedgerEntry) -> Void
  ) -> RequirementLedger {
    var next = entries
    if let index = next.firstIndex(where: { $0.requirementID == requirementID }) {
      mutate(&next[index])
    } else {
      var entry = RequirementLedgerEntry(requirementID: requirementID)
      mutate(&entry)
      next.append(entry)
    }
    return RequirementLedger(entries: next)
  }

  private static func pathsIntersect(owned: [String], changed: [String]) -> Bool {
    for path in changed {
      for prefix in owned {
        if path == prefix || path.hasPrefix(prefix.hasSuffix("/") ? prefix : prefix + "/")
          || path.hasPrefix(prefix)
        {
          return true
        }
      }
    }
    return false
  }
}

/// Applies agent audit results with deterministic criterion overrides.
public enum RequirementAuditEvaluator {
  public static func apply(
    agentResult: RequirementsAuditResult,
    criterionResults: [RequirementCriterionResult],
    into ledger: RequirementLedger,
    brief: ProjectBrief = .empty,
    commit: String? = nil,
    timestamp: Double = Date().timeIntervalSince1970 * 1000
  ) -> RequirementLedger {
    var next = ledger
    let failedByRequirement = Dictionary(
      grouping: criterionResults.filter { !$0.passed },
      by: \.requirementID
    )
    let proofByID = Dictionary(
      uniqueKeysWithValues: brief.nonEmptyRequirements.map { ($0.id, $0.proofLevel) }
    )

    for item in agentResult.results {
      var evidence = item.evidence
      var verdict = item.verdict
      if verdict == .unverified || verdict == .stale {
        verdict = .unsatisfied
      }
      let proof = proofByID[item.requirementID] ?? .hybrid
      let failures = failedByRequirement[item.requirementID] ?? []

      switch proof {
      case .deterministic:
        if !failures.isEmpty {
          verdict = .unsatisfied
        } else if !criterionResults.contains(where: { $0.requirementID == item.requirementID }) {
          // No runnable commands — cannot claim deterministic satisfaction.
          if verdict == .satisfied {
            verdict = .unsatisfied
            evidence.append(
              "Deterministic proof requires executable criteria/scenarios; none passed.")
          }
        } else if failures.isEmpty {
          // All host criteria passed — force satisfied regardless of soft agent doubt.
          verdict = .satisfied
        }
      case .hybrid:
        if !failures.isEmpty {
          verdict = .unsatisfied
        }
      case .judgment:
        // Command failures are evidence but do not hard-override judgment.
        break
      }

      for failure in failures {
        evidence.append(
          "Criterion failed (exit \(failure.exitCode)): `\(failure.command)` — \(compactOutput(failure.output))"
        )
      }
      for passed in criterionResults where passed.requirementID == item.requirementID
        && passed.passed
      {
        let line =
          "Criterion passed: `\(passed.command)` — \(compactOutput(passed.output))"
        if !evidence.contains(where: { $0.contains(passed.command) }) {
          evidence.append(line)
        }
      }

      next = next.updating(
        requirementID: item.requirementID,
        status: verdict,
        audit: RequirementAuditRecord(
          verdict: verdict,
          evidence: evidence,
          commit: commit,
          timestamp: timestamp
        ),
        proposedCriteria: item.proposedCriteria,
        proposedOwnedPaths: item.proposedOwnedPaths,
        proposedScenarios: item.proposedScenarios
      )
    }

    for (requirementID, failures) in failedByRequirement {
      guard agentResult.results.contains(where: { $0.requirementID == requirementID }) == false
      else { continue }
      let proof = proofByID[requirementID] ?? .hybrid
      guard proof != .judgment else { continue }
      let evidence = failures.map {
        "Criterion failed (exit \($0.exitCode)): `\($0.command)` — \(compactOutput($0.output))"
      }
      next = next.updating(
        requirementID: requirementID,
        status: .unsatisfied,
        audit: RequirementAuditRecord(
          verdict: .unsatisfied,
          evidence: evidence,
          commit: commit,
          timestamp: timestamp
        )
      )
    }

    return next
  }

  private static func compactOutput(_ output: String, limit: Int = 240) -> String {
    let compact =
      output
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    guard compact.count > limit else { return compact.isEmpty ? "(no output)" : compact }
    return String(compact.prefix(limit - 3)) + "..."
  }
}

/// Host-side runner that executes ledger criteria and scenario commands.
public enum RequirementCriteriaRunner {
  public static func collect(
    ledger: RequirementLedger,
    requirementIDs: [String],
    brief: ProjectBrief = .empty,
    run: (String) async throws -> (exitCode: Int, output: String)
  ) async -> [RequirementCriterionResult] {
    var results: [RequirementCriterionResult] = []
    let ids = Set(requirementIDs)
    let proofByID = Dictionary(
      uniqueKeysWithValues: brief.nonEmptyRequirements.map { ($0.id, $0.proofLevel) }
    )
    for entry in ledger.entries where ids.contains(entry.requirementID) {
      let proof = proofByID[entry.requirementID] ?? .hybrid
      // Judgment requirements still may have optional probes, but we only
      // hard-run commands for deterministic/hybrid.
      guard proof != .judgment else { continue }
      for command in entry.executableCommands {
        do {
          let outcome = try await run(command)
          results.append(
            RequirementCriterionResult(
              requirementID: entry.requirementID,
              command: command,
              exitCode: outcome.exitCode,
              output: outcome.output
            )
          )
        } catch {
          results.append(
            RequirementCriterionResult(
              requirementID: entry.requirementID,
              command: command,
              exitCode: 1,
              output: error.localizedDescription
            )
          )
        }
      }
    }
    return results
  }
}

/// Loop completion decision after Plan returns no immediate work.
public enum RequirementsLoopCompletion {
  public enum Decision: Equatable, Sendable {
    case complete
    case replan(findingsDraft: String)
    case stopUnverified(findingsDraft: String)
  }

  public static func decide(
    brief: ProjectBrief,
    ledger: RequirementLedger,
    alreadyReplannedAfterUnsatisfiedAudit: Bool
  ) -> Decision {
    guard brief.hasRequirements else { return .complete }
    let reconciled = ledger.reconciled(with: brief)
    if reconciled.entries.allSatisfy(\.status.countsAsComplete) {
      return .complete
    }
    let draft = reconciled.findingsDraft(brief: brief)
    if alreadyReplannedAfterUnsatisfiedAudit {
      return .stopUnverified(findingsDraft: draft)
    }
    return .replan(findingsDraft: draft)
  }
}

/// Validates Plan targeting of product requirements.
public enum RequirementTargetingValidator {
  public static func validate(
    immediate: PlanNext?,
    brief: ProjectBrief,
    ledger: RequirementLedger
  ) throws {
    guard let immediate else { return }
    guard brief.hasRequirements else { return }
    let reconciled = ledger.reconciled(with: brief)
    let incompleteIDs = Set(
      reconciled.entries.filter { !$0.status.countsAsComplete }.map(\.requirementID)
    )
    guard !incompleteIDs.isEmpty else { return }

    let validIDs = Set(brief.nonEmptyRequirements.map(\.id))
    let targeted = immediate.targetedRequirementIDs ?? []
    let unknown = targeted.filter { !validIDs.contains($0) }
    if !unknown.isEmpty {
      throw PlanTransitionValidationError(
        message:
          "Plan set `targetedRequirementIDs` to unknown requirement id(s): \(unknown.joined(separator: ", ")). Use ids from the Requirements status section.",
        reason: .weakHandoff,
        missingLabels: ["targetedRequirementIDs"]
      )
    }
    if targeted.isEmpty {
      throw PlanTransitionValidationError(
        message:
          "Plan selected Immediate Work while product requirements remain incomplete (\(incompleteIDs.count)). Set `targetedRequirementIDs` to the requirement id(s) this slice advances.",
        reason: .weakHandoff,
        missingLabels: ["targetedRequirementIDs"]
      )
    }
  }
}
