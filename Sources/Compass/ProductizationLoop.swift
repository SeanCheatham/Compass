import Foundation

struct ProductizationReflectDecisionUpdate: Codable, Equatable, Sendable {
  var experimentID: String
  var decision: ProductExperimentDecision
  var summary: String
  var evidenceRunIDs: [String]
  var decidedBy: String

  enum CodingKeys: String, CodingKey {
    case experimentID
    case experimentIDSnake = "experiment_id"
    case decision
    case summary
    case evidenceRunIDs
    case evidenceRunIDsSnake = "evidence_run_ids"
    case decidedBy
    case decidedBySnake = "decided_by"
  }

  init(
    experimentID: String,
    decision: ProductExperimentDecision,
    summary: String,
    evidenceRunIDs: [String] = [],
    decidedBy: String = "Reflect"
  ) {
    self.experimentID = ProductizationModelText.identifier(
      experimentID,
      fallback: "experiment"
    )
    self.decision = decision
    self.summary = StringUtils.boundedText(summary, limit: 1_000)
    self.evidenceRunIDs =
      ProductizationModelText.cleanedList(evidenceRunIDs, limit: 120)
      .map { ProductizationModelText.identifier($0, fallback: "evidence-run") }
    self.decidedBy = StringUtils.boundedText(decidedBy, limit: 120)
    if self.decidedBy.isEmpty {
      self.decidedBy = "Reflect"
    }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let experimentID = try Self.decodeString(
      from: container,
      preferredKey: .experimentID,
      aliases: [.experimentIDSnake],
      fallback: "experiment"
    )
    let decision = try container.decode(ProductExperimentDecision.self, forKey: .decision)
    let summary =
      try Self.decodeOptionalString(
        from: container,
        preferredKey: .summary,
        aliases: []
      ) ?? ""
    let evidenceRunIDs =
      try Self.decodeOptionalStringArray(
        from: container,
        preferredKey: .evidenceRunIDs,
        aliases: [.evidenceRunIDsSnake]
      ) ?? []
    let decidedBy =
      try Self.decodeOptionalString(
        from: container,
        preferredKey: .decidedBy,
        aliases: [.decidedBySnake]
      ) ?? "Reflect"
    self.init(
      experimentID: experimentID,
      decision: decision,
      summary: summary,
      evidenceRunIDs: evidenceRunIDs,
      decidedBy: decidedBy
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(experimentID, forKey: .experimentID)
    try container.encode(decision, forKey: .decision)
    try container.encode(summary, forKey: .summary)
    try container.encode(evidenceRunIDs, forKey: .evidenceRunIDs)
    try container.encode(decidedBy, forKey: .decidedBy)
  }

  private static func decodeString(
    from container: KeyedDecodingContainer<CodingKeys>,
    preferredKey: CodingKeys,
    aliases: [CodingKeys],
    fallback: String
  ) throws -> String {
    try decodeOptionalString(from: container, preferredKey: preferredKey, aliases: aliases)
      ?? fallback
  }

  private static func decodeOptionalString(
    from container: KeyedDecodingContainer<CodingKeys>,
    preferredKey: CodingKeys,
    aliases: [CodingKeys]
  ) throws -> String? {
    var firstTypeError: Error?
    for key in [preferredKey] + aliases where container.contains(key) {
      do {
        return try container.decodeIfPresent(String.self, forKey: key)
      } catch {
        firstTypeError = firstTypeError ?? error
      }
    }
    if let firstTypeError {
      throw firstTypeError
    }
    return nil
  }

  private static func decodeOptionalStringArray(
    from container: KeyedDecodingContainer<CodingKeys>,
    preferredKey: CodingKeys,
    aliases: [CodingKeys]
  ) throws -> [String]? {
    var firstTypeError: Error?
    for key in [preferredKey] + aliases where container.contains(key) {
      do {
        return try FlexibleModelDecoder.decodeStringArrayIfPresent(from: container, forKey: key)
      } catch {
        firstTypeError = firstTypeError ?? error
      }
    }
    if let firstTypeError {
      throw firstTypeError
    }
    return nil
  }
}

enum ProductizationDecisionTransitionError: LocalizedError, Equatable {
  case invalidTransition(
    experimentID: String,
    from: ProductExperimentDecision,
    to: ProductExperimentDecision
  )
  case missingSummary(experimentID: String, decision: ProductExperimentDecision)
  case unknownExperiment(String)

  var errorDescription: String? {
    switch self {
    case .invalidTransition(let experimentID, let from, let to):
      return
        "Reflect tried to move product experiment \(experimentID) from \(from.rawValue) to \(to.rawValue), which is not an allowed productization transition."
    case .missingSummary(let experimentID, let decision):
      return
        "Reflect tried to mark product experiment \(experimentID) as \(decision.rawValue) without a decision summary."
    case .unknownExperiment(let id):
      return "Reflect tried to update unknown product experiment \(id)."
    }
  }
}

enum ProductizationDecisionTransitionValidator {
  static func validate(
    experimentID: String,
    from current: ProductExperimentDecision,
    to proposed: ProductExperimentDecision,
    summary: String
  ) throws {
    if requiresSummary(proposed)
      && summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      throw ProductizationDecisionTransitionError.missingSummary(
        experimentID: experimentID,
        decision: proposed
      )
    }

    guard allowedNextDecisions(from: current).contains(proposed) else {
      throw ProductizationDecisionTransitionError.invalidTransition(
        experimentID: experimentID,
        from: current,
        to: proposed
      )
    }
  }

  static func allowedNextDecisions(
    from current: ProductExperimentDecision
  ) -> Set<ProductExperimentDecision> {
    switch current {
    case .notRun:
      return [.keepGoing]
    case .keepGoing:
      return [.keepGoing, .narrow, .pivot, .kill, .promote]
    case .narrow:
      return [.keepGoing, .pivot, .kill, .promote]
    case .pivot:
      return [.keepGoing, .kill]
    case .kill:
      return [.archived]
    case .promote:
      return [.promoted]
    case .archived, .promoted:
      return []
    }
  }

  private static func requiresSummary(_ decision: ProductExperimentDecision) -> Bool {
    switch decision {
    case .kill, .promote, .archived, .promoted:
      return true
    case .notRun, .keepGoing, .narrow, .pivot:
      return false
    }
  }
}

enum ProductizationReflectDecisionApplier {
  static func applying(
    _ updates: [ProductizationReflectDecisionUpdate],
    to config: ProductizationConfig,
    now: Date = Date()
  ) throws -> ProductizationConfig {
    guard !updates.isEmpty else { return config }

    var next = config
    let timestamp = now.timeIntervalSince1970
    var decisionSequence = next.decisions.count

    for update in updates {
      guard let experimentIndex = next.experiments.firstIndex(where: { $0.id == update.experimentID })
      else {
        throw ProductizationDecisionTransitionError.unknownExperiment(update.experimentID)
      }

      let currentDecision = next.experiments[experimentIndex].decision
      try ProductizationDecisionTransitionValidator.validate(
        experimentID: update.experimentID,
        from: currentDecision,
        to: update.decision,
        summary: update.summary
      )

      next.experiments[experimentIndex].decision = update.decision
      next.experiments[experimentIndex].evidenceSummary = update.summary.isEmpty
        ? next.experiments[experimentIndex].evidenceSummary
        : update.summary
      next.experiments[experimentIndex].updatedAt = timestamp

      decisionSequence += 1
      next.decisions.append(
        ProductDecision(
          id:
            "\(update.experimentID)-\(update.decision.rawValue)-\(Int(timestamp))-\(decisionSequence)",
          experimentID: update.experimentID,
          decision: update.decision,
          summary: update.summary,
          evidenceRunIDs: update.evidenceRunIDs,
          branchName: next.experiments[experimentIndex].branchName,
          beforeSha: next.experiments[experimentIndex].currentSha
            ?? next.experiments[experimentIndex].baseSha,
          afterSha: next.experiments[experimentIndex].currentSha
            ?? next.experiments[experimentIndex].baseSha,
          decidedAt: timestamp,
          decidedBy: update.decidedBy
        )
      )
    }

    return next
  }
}
