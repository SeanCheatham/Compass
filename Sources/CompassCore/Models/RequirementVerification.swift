import Foundation

/// Factory-owned verification status for a user product requirement.
/// Intent lives in `brief.json`; verdicts and criteria live here.
public enum RequirementVerificationStatus: String, Codable, Equatable, Sendable, CaseIterable {
  case unverified
  case satisfied
  case unsatisfied
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
    self.verdict = verdict == .unverified ? .unsatisfied : verdict
    self.evidence =
      evidence
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    let trimmedCommit = commit?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    self.commit = trimmedCommit.isEmpty ? nil : trimmedCommit
    self.timestamp = timestamp
  }
}

public struct RequirementLedgerEntry: Codable, Equatable, Identifiable, Sendable {
  public var requirementID: String
  public var criteria: [String]
  public var status: RequirementVerificationStatus
  public var lastAudit: RequirementAuditRecord?

  public var id: String { requirementID }

  public init(
    requirementID: String,
    criteria: [String] = [],
    status: RequirementVerificationStatus = .unverified,
    lastAudit: RequirementAuditRecord? = nil
  ) {
    self.requirementID = requirementID.trimmingCharacters(in: .whitespacesAndNewlines)
    self.criteria =
      criteria
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    self.status = status
    self.lastAudit = lastAudit
  }

  public var sanitized: RequirementLedgerEntry {
    RequirementLedgerEntry(
      requirementID: requirementID,
      criteria: criteria,
      status: status,
      lastAudit: lastAudit
    )
  }
}

/// Agent submit payload for one requirement under audit.
public struct RequirementAuditItemResult: Codable, Equatable, Sendable {
  public var requirementID: String
  public var verdict: RequirementVerificationStatus
  public var evidence: [String]
  public var proposedCriteria: [String]

  public enum CodingKeys: String, CodingKey {
    case requirementID
    case requirementIDSnake = "requirement_id"
    case verdict
    case evidence
    case proposedCriteria
    case proposedCriteriaSnake = "proposed_criteria"
  }

  public init(
    requirementID: String,
    verdict: RequirementVerificationStatus,
    evidence: [String] = [],
    proposedCriteria: [String] = []
  ) {
    self.requirementID = requirementID.trimmingCharacters(in: .whitespacesAndNewlines)
    self.verdict = verdict == .unverified ? .unsatisfied : verdict
    self.evidence =
      evidence
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    self.proposedCriteria =
      proposedCriteria
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
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
    self.init(
      requirementID: id,
      verdict: verdict == .unverified ? .unsatisfied : verdict,
      evidence: evidence,
      proposedCriteria: proposed
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(requirementID, forKey: .requirementID)
    try container.encode(verdict.rawValue, forKey: .verdict)
    try container.encode(evidence, forKey: .evidence)
    try container.encode(proposedCriteria, forKey: .proposedCriteria)
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
    !entries.isEmpty && entries.allSatisfy { $0.status == .satisfied }
  }

  public var unsatisfiedEntries: [RequirementLedgerEntry] {
    entries.filter { $0.status != .satisfied }
  }

  public var hasUnsatisfied: Bool {
    entries.contains { $0.status != .satisfied }
  }

  /// Align ledger entries with the current brief: create missing, drop deleted.
  public func reconciled(with brief: ProjectBrief) -> RequirementLedger {
    let requirements = brief.nonEmptyRequirements
    let ids = Set(requirements.map(\.id))
    var byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.requirementID, $0) })
    var next: [RequirementLedgerEntry] = []
    for requirement in requirements {
      if let existing = byID.removeValue(forKey: requirement.id) {
        next.append(existing.sanitized)
      } else {
        next.append(RequirementLedgerEntry(requirementID: requirement.id))
      }
    }
    _ = byID.filter { ids.contains($0.key) }
    return RequirementLedger(entries: next)
  }

  public func updating(
    requirementID: String,
    status: RequirementVerificationStatus,
    audit: RequirementAuditRecord,
    proposedCriteria: [String] = []
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
      next[index] = entry.sanitized
    } else {
      next.append(
        RequirementLedgerEntry(
          requirementID: requirementID,
          criteria: proposedCriteria,
          status: status,
          lastAudit: audit
        )
      )
    }
    return RequirementLedger(entries: next)
  }

  public func updatingCriteria(requirementID: String, criteria: [String]) -> RequirementLedger {
    var next = entries
    if let index = next.firstIndex(where: { $0.requirementID == requirementID }) {
      next[index].criteria =
        criteria
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    } else {
      next.append(
        RequirementLedgerEntry(
          requirementID: requirementID,
          criteria: criteria
        )
      )
    }
    return RequirementLedger(entries: next)
  }

  /// Markdown projection for Plan / audit prompts.
  public func renderedStatusMarkdown(
    brief: ProjectBrief,
    maxCharacters: Int = 3_000
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
      lines.append("- [\(status)] \(requirement.text) `(id: \(requirement.id))`")
      if let criteria = entry?.criteria, !criteria.isEmpty {
        lines.append("  Criteria:")
        for criterion in criteria {
          lines.append("  - `\(criterion)`")
        }
      } else {
        lines.append("  Criteria: _(none — auditor should propose)_")
      }
      if let audit = entry?.lastAudit {
        let evidence =
          audit.evidence.isEmpty
          ? "_(no evidence)_"
          : audit.evidence.prefix(3).joined(separator: "; ")
        lines.append("  Last audit: \(audit.verdict.rawValue) — \(evidence)")
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
      "Requirements audit found unsatisfied product requirements. Plan the next slice to address them:"
    ]
    for requirement in brief.nonEmptyRequirements {
      guard let entry = reconciled.entry(for: requirement.id), entry.status != .satisfied else {
        continue
      }
      let evidence =
        entry.lastAudit?.evidence.prefix(2).joined(separator: "; ")
        ?? "no evidence yet"
      lines.append(
        "- [\(entry.status.rawValue)] \(requirement.text) (id: \(requirement.id)): \(evidence)"
      )
    }
    return lines.joined(separator: "\n")
  }
}

/// Applies agent audit results with deterministic criterion overrides.
public enum RequirementAuditEvaluator {
  public static func apply(
    agentResult: RequirementsAuditResult,
    criterionResults: [RequirementCriterionResult],
    into ledger: RequirementLedger,
    commit: String? = nil,
    timestamp: Double = Date().timeIntervalSince1970 * 1000
  ) -> RequirementLedger {
    var next = ledger
    let failedByRequirement = Dictionary(
      grouping: criterionResults.filter { !$0.passed },
      by: \.requirementID
    )

    for item in agentResult.results {
      var evidence = item.evidence
      var verdict = item.verdict == .unverified ? .unsatisfied : item.verdict

      if let failures = failedByRequirement[item.requirementID], !failures.isEmpty {
        verdict = .unsatisfied
        for failure in failures {
          evidence.append(
            "Criterion failed (exit \(failure.exitCode)): `\(failure.command)` — \(compactOutput(failure.output))"
          )
        }
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
        proposedCriteria: item.proposedCriteria
      )
    }

    // Requirements with failed criteria but no agent item still mark unsatisfied.
    for (requirementID, failures) in failedByRequirement {
      guard agentResult.results.contains(where: { $0.requirementID == requirementID }) == false
      else { continue }
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

/// Host-side runner that executes ledger criteria as shell commands.
public enum RequirementCriteriaRunner {
  public static func collect(
    ledger: RequirementLedger,
    requirementIDs: [String],
    run: (String) async throws -> (exitCode: Int, output: String)
  ) async -> [RequirementCriterionResult] {
    var results: [RequirementCriterionResult] = []
    let ids = Set(requirementIDs)
    for entry in ledger.entries where ids.contains(entry.requirementID) {
      for command in entry.criteria {
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
    /// No requirements, or all satisfied — factory can stop.
    case complete
    /// Unsatisfied findings should be fed back to Plan and auto-play should continue.
    case replan(findingsDraft: String)
    /// Findings were already fed back once and Plan still returned nil — stop with warning.
    case stopUnverified(findingsDraft: String)
  }

  public static func decide(
    brief: ProjectBrief,
    ledger: RequirementLedger,
    alreadyReplannedAfterUnsatisfiedAudit: Bool
  ) -> Decision {
    guard brief.hasRequirements else { return .complete }
    let reconciled = ledger.reconciled(with: brief)
    if reconciled.entries.allSatisfy({ $0.status == .satisfied }) {
      return .complete
    }
    let draft = reconciled.findingsDraft(brief: brief)
    if alreadyReplannedAfterUnsatisfiedAudit {
      return .stopUnverified(findingsDraft: draft)
    }
    return .replan(findingsDraft: draft)
  }
}
