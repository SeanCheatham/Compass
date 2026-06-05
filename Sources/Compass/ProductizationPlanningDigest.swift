import Foundation

enum ProductizationPlanningDigestFormatter {
  static func promptText(
    config: ProductizationConfig,
    evidenceIndex: ProductizationEvidenceIndex,
    maxPainHypotheses: Int = 3,
    maxSolutionHypotheses: Int = 5,
    maxExperiments: Int = 6,
    maxDecisions: Int = 4,
    maxEvidenceSignals: Int = 5
  ) -> String {
    var lines: [String] = [
      "Productization context starts from durable user pain; solution hypotheses and experiments are disposable product bets."
    ]

    if config.isEmpty {
      lines.append("No productization state is configured yet.")
      return boundedLines(lines, maxLines: 36, maxCharacters: 3_800)
    }

    lines += painLines(config: config, maxPainHypotheses: maxPainHypotheses)
    lines += solutionLines(config: config, maxSolutionHypotheses: maxSolutionHypotheses)
    lines += experimentLines(config: config, maxExperiments: maxExperiments)
    lines += decisionLines(config: config, maxDecisions: maxDecisions)
    lines += unknownLines(config: config)
    lines += evidenceSignalLines(index: evidenceIndex, maxEvidenceSignals: maxEvidenceSignals)

    return boundedLines(lines, maxLines: 44, maxCharacters: 4_200)
  }

  private static func painLines(
    config: ProductizationConfig,
    maxPainHypotheses: Int
  ) -> [String] {
    let active = config.painHypotheses
      .filter { $0.status == .active || $0.status == .draft }
      .sorted { lhs, rhs in
        if lhs.status == rhs.status { return lhs.updatedAt > rhs.updatedAt }
        return lhs.status == .active
      }
    guard !active.isEmpty else {
      let rawPain = bounded(config.rawPain, 240)
      return [
        "Pain model:",
        rawPain.isEmpty ? "- No active pain hypothesis is configured." : "- Raw pain: \(rawPain).",
      ]
    }

    var lines = ["Active pain hypotheses:"]
    for pain in active.prefix(maxPainHypotheses) {
      lines.append(
        "- \(bounded(pain.title, 180)): \(bounded(pain.rawPain, 220)); situation: \(bounded(pain.targetSituation, 180)); severity: \(bounded(pain.painSeverity, 120))."
      )
      if !pain.costOfInaction.isEmpty {
        lines.append("- Cost of inaction: \(bounded(pain.costOfInaction, 220)).")
      }
    }
    if active.count > maxPainHypotheses {
      lines.append("- \(active.count - maxPainHypotheses) more pain hypothesis/hypotheses omitted.")
    }
    return lines
  }

  private static func solutionLines(
    config: ProductizationConfig,
    maxSolutionHypotheses: Int
  ) -> [String] {
    let solutions = config.solutionHypotheses
      .filter { $0.status == .active || $0.status == .candidate || $0.status == .promoted }
      .sorted { lhs, rhs in
        if lhs.status == rhs.status { return lhs.title < rhs.title }
        return solutionStatusRank(lhs.status) < solutionStatusRank(rhs.status)
      }
    guard !solutions.isEmpty else {
      return [
        "Solution hypotheses:",
        "- No active or candidate solution hypothesis is configured.",
      ]
    }

    var lines = ["Solution hypotheses:"]
    for solution in solutions.prefix(maxSolutionHypotheses) {
      let segments =
        solution.targetSegmentIDs.isEmpty
        ? "no target segment"
        : solution.targetSegmentIDs.joined(separator: ", ")
      lines.append(
        "- \(bounded(solution.title, 160)) [\(solution.status.rawValue), pain \(solution.painID), segments \(segments)]: \(bounded(solution.promise, 220))."
      )
      if !solution.requiredProof.isEmpty {
        lines.append(
          "- Required proof: \(bounded(solution.requiredProof.joined(separator: "; "), 240)).")
      }
    }
    if solutions.count > maxSolutionHypotheses {
      lines.append(
        "- \(solutions.count - maxSolutionHypotheses) more solution hypothesis/hypotheses omitted.")
    }
    return lines
  }

  private static func experimentLines(
    config: ProductizationConfig,
    maxExperiments: Int
  ) -> [String] {
    let experiments = config.experiments.sorted { lhs, rhs in
      if lhs.decision == rhs.decision { return lhs.updatedAt > rhs.updatedAt }
      return experimentDecisionRank(lhs.decision) < experimentDecisionRank(rhs.decision)
    }
    guard !experiments.isEmpty else {
      return [
        "Experiments and branches:",
        "- No product experiments are configured yet.",
      ]
    }

    var lines = ["Experiments and branches:"]
    for experiment in experiments.prefix(maxExperiments) {
      let sha = experiment.currentSha ?? experiment.baseSha ?? "not-created"
      lines.append(
        "- \(bounded(experiment.title, 160)) [\(experiment.decision.rawValue)]: solution \(experiment.solutionID), branch \(bounded(experiment.branchName, 160)), worktree \(experiment.worktreeID), sha \(sha)."
      )
      lines.append("- Scope: \(bounded(experiment.prototypeScope, 220)).")
      if !experiment.evidenceSummary.isEmpty {
        lines.append("- Evidence summary: \(bounded(experiment.evidenceSummary, 220)).")
      }
    }
    if experiments.count > maxExperiments {
      lines.append("- \(experiments.count - maxExperiments) more experiment(s) omitted.")
    }
    return lines
  }

  private static func decisionLines(
    config: ProductizationConfig,
    maxDecisions: Int
  ) -> [String] {
    let decisions = config.decisions
      .sorted { lhs, rhs in
        if lhs.decidedAt == rhs.decidedAt { return lhs.id < rhs.id }
        return lhs.decidedAt > rhs.decidedAt
      }
      .prefix(maxDecisions)
    guard !decisions.isEmpty else { return [] }

    return ["Latest product decisions:"]
      + decisions.map { decision in
        let evidence =
          decision.evidenceRunIDs.isEmpty
          ? "no evidence runs"
          : "evidence \(decision.evidenceRunIDs.joined(separator: ", "))"
        return
          "- \(decision.experimentID): \(decision.decision.rawValue) by \(bounded(decision.decidedBy, 80)); \(evidence); \(bounded(decision.summary, 220))."
      }
  }

  private static func unknownLines(config: ProductizationConfig) -> [String] {
    let unknowns = config.painHypotheses
      .filter { $0.status == .active || $0.status == .draft }
      .flatMap(\.unknowns)
      .productizationUniquedPreservingOrder()
      .prefix(6)
    guard !unknowns.isEmpty else { return [] }
    return ["Unresolved product unknowns:"]
      + unknowns.map { "- \(bounded($0, 220))." }
  }

  private static func evidenceSignalLines(
    index: ProductizationEvidenceIndex,
    maxEvidenceSignals: Int
  ) -> [String] {
    var lines: [String] = []
    let summaries = index.summaries.prefix(maxEvidenceSignals)
    if !summaries.isEmpty {
      lines.append("Top evidence signals and objections:")
      for summary in summaries {
        var parts = [
          "run \(summary.runID)",
          "scenario \(summary.scenarioID)",
          "experiment \(summary.experimentID)",
          "status \(summary.status.rawValue)",
          "model \(bounded(summary.model, 80))",
          "mode \(summary.mode.rawValue)",
          "verdict \(summary.verdict.rawValue)",
        ]
        if summary.scores.hasScores {
          let scores = [
            summary.scores.painRecognition.map { "pain \($0)" },
            summary.scores.workflowImprovement.map { "workflow \($0)" },
            summary.scores.alternativeAdvantage.map { "alternative \($0)" },
            summary.scores.switchingReadiness.map { "switch \($0)" },
            summary.scores.continuedUsePull.map { "pull \($0)" },
          ].compactMap { $0 }.joined(separator: ", ")
          parts.append("scores \(scores)")
        }
        if let objection = summary.objections.first, !objection.isEmpty {
          parts.append("objection \(bounded(objection, 180))")
        }
        if !summary.missingCapabilities.isEmpty {
          parts.append(
            "missing \(bounded(summary.missingCapabilities.joined(separator: ", "), 180))")
        }
        if let hash = summary.traceHash {
          parts.append("trace \(bounded(hash, 80))")
        }
        lines.append("- \(parts.joined(separator: "; ")).")
      }
    }

    if !index.aggregate.repeatedObjections.isEmpty {
      let objections = index.aggregate.repeatedObjections.prefix(4)
        .map { "\(bounded($0.objection, 120)) (\($0.count)x)" }
        .joined(separator: "; ")
      lines.append("Repeated objections: \(objections).")
    }

    if !index.aggregate.pmfReadinessByExperiment.isEmpty {
      lines.append("Product-market-fit readiness:")
      for readiness in index.aggregate.pmfReadinessByExperiment.prefix(4) {
        let evidence =
          readiness.evidenceRunIDs.isEmpty
          ? "no evidence runs"
          : "evidence \(readiness.evidenceRunIDs.prefix(4).joined(separator: ", "))"
        let rationale = readiness.rationale.first.map { "; \(bounded($0, 180))" } ?? ""
        lines.append(
          "- \(readiness.experimentID): score \(readiness.scoreLabel)/100; recommend \(readiness.recommendation.rawValue); \(evidence)\(rationale)."
        )
      }
    }

    if !index.aggregate.missingCapabilityFrequency.isEmpty {
      let missing = index.aggregate.missingCapabilityFrequency.prefix(4)
        .map { "\(bounded($0.capabilityID, 120)) (\($0.count)x)" }
        .joined(separator: "; ")
      lines.append("Missing capabilities: \(missing).")
    }

    if !index.aggregate.currentAlternativeComparisons.isEmpty {
      lines.append("Current alternative comparisons:")
      for comparison in index.aggregate.currentAlternativeComparisons.prefix(3) {
        lines.append(
          "- \(comparison.experimentID) / \(comparison.runID): \(bounded(comparison.comparison, 220)) [\(comparison.verdict.rawValue)]."
        )
      }
    }

    if index.malformedRecordCount > 0 {
      lines.append("\(index.malformedRecordCount) malformed evidence record(s) were skipped.")
    }
    return lines
  }

  private static func solutionStatusRank(_ status: SolutionHypothesisStatus) -> Int {
    switch status {
    case .promoted: return 0
    case .active: return 1
    case .candidate: return 2
    case .parked: return 3
    case .rejected: return 4
    }
  }

  private static func experimentDecisionRank(_ decision: ProductExperimentDecision) -> Int {
    switch decision {
    case .promoted: return 0
    case .promote: return 0
    case .keepGoing: return 1
    case .narrow: return 2
    case .pivot: return 3
    case .notRun: return 4
    case .kill: return 5
    case .archived: return 6
    }
  }

  private static func boundedLines(
    _ lines: [String],
    maxLines: Int,
    maxCharacters: Int
  ) -> String {
    var selected: [String] = []
    var characterCount = 0
    for line in lines where selected.count < maxLines {
      let nextCount = characterCount + line.count + 1
      guard nextCount <= maxCharacters else { break }
      selected.append(line)
      characterCount = nextCount
    }
    return selected.joined(separator: "\n")
  }

  private static func bounded(_ value: String, _ limit: Int) -> String {
    StringUtils.boundedText(value, limit: limit)
  }
}

extension Array where Element == String {
  fileprivate func productizationUniquedPreservingOrder() -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    for value in self {
      guard seen.insert(value).inserted else { continue }
      out.append(value)
    }
    return out
  }
}
