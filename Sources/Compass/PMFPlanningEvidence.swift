import Foundation

enum PMFPlanningEvidenceFormatter {
  static func promptText(
    config: PMFConfig,
    index: PMFEvidenceIndex,
    maxActiveScenarios: Int = 6,
    maxRepeatedObjections: Int = 5,
    maxLowScoreClusters: Int = 5,
    maxGaps: Int = 5
  ) -> String {
    var lines: [String] = [
      "PMF evidence is advisory product evidence, not an engineering verify gate."
    ]

    lines += hypothesisLines(config: config, index: index)
    lines += latestScenarioLines(
      config: config,
      index: index,
      maxActiveScenarios: maxActiveScenarios
    )
    lines += repeatedObjectionLines(
      index: index,
      maxRepeatedObjections: maxRepeatedObjections
    )
    lines += lowScoreClusterLines(
      config: config,
      index: index,
      maxLowScoreClusters: maxLowScoreClusters
    )
    lines += verdictDistributionLines(index: index)
    lines += failureLines(index: index)
    lines += evidenceGapLines(
      config: config,
      index: index,
      maxGaps: maxGaps
    )

    return boundedLines(lines, maxLines: 42, maxCharacters: 3_800)
  }

  private static func hypothesisLines(
    config: PMFConfig,
    index: PMFEvidenceIndex
  ) -> [String] {
    guard let hypothesis = currentHypothesis(config: config, index: index) else {
      return ["Current hypothesis:", "- No PMF hypothesis is configured yet."]
    }

    var details = [
      "target: \(bounded(hypothesis.targetUser, 160))",
      "promise: \(bounded(hypothesis.promise, 180))",
    ]
    if let risk = hypothesis.knownRisks.first {
      details.append("risk: \(bounded(risk, 160))")
    }
    return [
      "Current hypothesis:",
      "- \(bounded(hypothesis.title, 180)) (\(details.joined(separator: "; "))).",
    ]
  }

  private static func latestScenarioLines(
    config: PMFConfig,
    index: PMFEvidenceIndex,
    maxActiveScenarios: Int
  ) -> [String] {
    let activeScenarios = sortedActiveScenarios(config.scenarios)
    guard !activeScenarios.isEmpty else {
      return [
        "Latest evidence per active scenario:",
        "- No enabled PMF scenarios are configured.",
      ]
    }

    let summaryByRunID = index.summaries.reduce(into: [String: PMFEvidenceSummary]()) {
      summariesByRunID,
      summary in
      summariesByRunID[summary.runID] = summary
    }
    var lines = ["Latest evidence per active scenario:"]
    for scenario in activeScenarios.prefix(maxActiveScenarios) {
      let scenarioName = scenarioLabel(scenario, config: config)
      guard
        let runID = index.aggregate.latestRunByScenario[scenario.id],
        let summary = summaryByRunID[runID]
      else {
        lines.append("- \(scenarioName): no run yet.")
        continue
      }
      lines.append("- \(scenarioName): \(summaryLine(summary, config: config)).")
    }
    if activeScenarios.count > maxActiveScenarios {
      lines.append("- \(activeScenarios.count - maxActiveScenarios) more active scenario(s) omitted.")
    }
    return lines
  }

  private static func repeatedObjectionLines(
    index: PMFEvidenceIndex,
    maxRepeatedObjections: Int
  ) -> [String] {
    let objections = index.aggregate.repeatedObjections.prefix(maxRepeatedObjections)
    guard !objections.isEmpty else { return [] }
    return ["Repeated objections:"]
      + objections.map { "- \(bounded($0.objection, 220)) (\($0.count)x)." }
  }

  private static func lowScoreClusterLines(
    config: PMFConfig,
    index: PMFEvidenceIndex,
    maxLowScoreClusters: Int
  ) -> [String] {
    let clusters = index.aggregate.averageScoresByPersonaTask
      .filter { average in
        [
          average.valueScore,
          average.clarityScore,
          average.trustScore,
          average.switchLikelihood,
          average.payLikelihood,
        ].contains { $0 > 0 && $0 <= 2.5 }
      }
      .sorted { lhs, rhs in
        let lhsMin = min(
          lhs.valueScore,
          lhs.clarityScore,
          lhs.trustScore,
          lhs.switchLikelihood,
          lhs.payLikelihood
        )
        let rhsMin = min(
          rhs.valueScore,
          rhs.clarityScore,
          rhs.trustScore,
          rhs.switchLikelihood,
          rhs.payLikelihood
        )
        if lhsMin == rhsMin {
          let lhsKey = "\(lhs.personaID)|\(lhs.taskID)"
          let rhsKey = "\(rhs.personaID)|\(rhs.taskID)"
          return lhsKey < rhsKey
        }
        return lhsMin < rhsMin
      }
      .prefix(maxLowScoreClusters)

    guard !clusters.isEmpty else { return [] }
    return ["Low-score clusters:"]
      + clusters.map { average in
        let persona = personaLabel(average.personaID, config: config)
        let task = taskLabel(average.taskID, config: config)
        return
          "- \(persona) / \(task): value \(score(average.valueScore)), clarity \(score(average.clarityScore)), trust \(score(average.trustScore)), switch \(score(average.switchLikelihood)), pay \(score(average.payLikelihood)) across \(average.runCount) run(s)."
      }
  }

  private static func verdictDistributionLines(index: PMFEvidenceIndex) -> [String] {
    guard !index.aggregate.verdictCounts.isEmpty else { return [] }
    let counts = index.aggregate.verdictCounts
      .sorted { lhs, rhs in
        if lhs.value == rhs.value { return lhs.key < rhs.key }
        return lhs.value > rhs.value
      }
      .map { "\($0.key): \($0.value)" }
      .joined(separator: ", ")
    return ["Recent verdict distribution:", "- \(counts)."]
  }

  private static func failureLines(index: PMFEvidenceIndex) -> [String] {
    guard !index.aggregate.failuresByKind.isEmpty else { return [] }
    let failures = index.aggregate.failuresByKind
      .sorted { lhs, rhs in
        if lhs.value == rhs.value { return lhs.key < rhs.key }
        return lhs.value > rhs.value
      }
      .map { "\($0.key): \($0.value)" }
      .joined(separator: ", ")
    return ["PMF run failures:", "- \(failures)."]
  }

  private static func evidenceGapLines(
    config: PMFConfig,
    index: PMFEvidenceIndex,
    maxGaps: Int
  ) -> [String] {
    var gaps: [String] = []
    let activeScenarios = sortedActiveScenarios(config.scenarios)
    if config.hypotheses.isEmpty {
      gaps.append("No PMF hypothesis is configured.")
    }
    if activeScenarios.isEmpty {
      gaps.append("No enabled PMF scenarios are configured.")
    }
    if index.summaries.isEmpty {
      gaps.append("No PMF runs have been recorded yet.")
    }
    for scenario in activeScenarios {
      guard gaps.count < maxGaps else { break }
      guard index.aggregate.latestRunByScenario[scenario.id] == nil else { continue }
      gaps.append("Active scenario without evidence: \(scenarioLabel(scenario, config: config)).")
    }
    if index.malformedRecordCount > 0 {
      gaps.append("\(index.malformedRecordCount) malformed PMF evidence record(s) were skipped.")
    }
    guard !gaps.isEmpty else { return [] }
    return ["Evidence gaps:"] + gaps.prefix(maxGaps).map { "- \(bounded($0, 240))" }
  }

  private static func summaryLine(_ summary: PMFEvidenceSummary, config: PMFConfig) -> String {
    var parts = [
      "run \(summary.runID)",
      "status \(summary.status.rawValue)",
      "persona \(personaLabel(summary.personaID, config: config))",
      "task \(taskLabel(summary.taskID, config: config))",
    ]
    if let verdict = summary.verdict {
      parts.append("verdict \(verdict.rawValue)")
    }
    if let value = summary.valueScore,
      let clarity = summary.clarityScore,
      let trust = summary.trustScore,
      let switchLikelihood = summary.switchLikelihood,
      let payLikelihood = summary.payLikelihood
    {
      parts.append(
        "scores value \(value), clarity \(clarity), trust \(trust), switch \(switchLikelihood), pay \(payLikelihood)"
      )
    }
    if let objection = summary.topObjection, !objection.isEmpty {
      parts.append("objection: \(bounded(objection, 180))")
    }
    if let failure = summary.failureKind {
      parts.append("failure \(failure)")
    }
    return parts.joined(separator: "; ")
  }

  private static func currentHypothesis(
    config: PMFConfig,
    index: PMFEvidenceIndex
  ) -> ProductHypothesis? {
    if let latest = index.summaries.first,
      let matched = config.hypotheses.first(where: { $0.id == latest.hypothesisID })
    {
      return matched
    }
    if let scenario = sortedActiveScenarios(config.scenarios).first,
      let matched = config.hypotheses.first(where: { $0.id == scenario.hypothesisID })
    {
      return matched
    }
    return config.hypotheses.first
  }

  private static func sortedActiveScenarios(_ scenarios: [PMFScenario]) -> [PMFScenario] {
    scenarios.filter(\.enabled).sorted { lhs, rhs in
      if lhs.title == rhs.title { return lhs.id < rhs.id }
      return lhs.title < rhs.title
    }
  }

  private static func scenarioLabel(_ scenario: PMFScenario, config: PMFConfig) -> String {
    let persona = personaLabel(scenario.personaID, config: config)
    let task = taskLabel(scenario.taskID, config: config)
    return "\(bounded(scenario.title, 140)) [\(persona) / \(task)]"
  }

  private static func personaLabel(_ id: String, config: PMFConfig) -> String {
    bounded(config.personas.first { $0.id == id }?.name ?? id, 120)
  }

  private static func taskLabel(_ id: String, config: PMFConfig) -> String {
    bounded(config.tasks.first { $0.id == id }?.title ?? id, 120)
  }

  private static func bounded(_ text: String, _ limit: Int) -> String {
    StringUtils.boundedText(text, limit: limit)
      .replacingOccurrences(of: "\n", with: " ")
  }

  private static func score(_ value: Double) -> String {
    String(format: "%.2g", value)
  }

  private static func boundedLines(
    _ lines: [String],
    maxLines: Int,
    maxCharacters: Int
  ) -> String {
    let joined = lines.prefix(maxLines).joined(separator: "\n")
    guard joined.count > maxCharacters else { return joined }
    return String(joined.prefix(max(0, maxCharacters - 3)))
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}
