import Foundation
import Testing

@testable import Compass

struct ProductizationEvidenceStoreTests {
  @Test func storeWritesRunDirectoryArtifactsAndIndex() throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()

    let record = makeEvidenceRecord(id: "run-one")
    let stored = try workspace.writeProductizationEvidenceRecord(
      record,
      traceJSON: #"{"trace":true}"#,
      feedbackJSON: #"{"feedback":true}"#,
      transcriptJSONL: #"{"turn":0}"#,
      summaryMarkdown: "summary"
    )

    try #require(stored.traceArtifactPath == "productization/runs/run-one/trace.json")
    try #require(stored.feedbackArtifactPath == "productization/runs/run-one/feedback.json")
    try #require(stored.transcriptArtifactPath == "productization/runs/run-one/transcript.jsonl")
    try #require(stored.summaryArtifactPath == "productization/runs/run-one/summary.md")
    try #require(
      FileManager.default.fileExists(
        atPath: workspace.productizationURL.appending(path: "evidence-index.json").path))
    let read = try workspace.readProductizationEvidenceRecord(id: "run-one")
    try #require(read == stored)
    try #require(workspace.readProductizationEvidenceIndex().summaries.map(\.runID) == ["run-one"])
  }

  @Test func indexAggregatesExperimentEvidenceSignals() throws {
    let first = makeEvidenceRecord(
      id: "first",
      endedAt: 100,
      verdict: .weak,
      objections: ["Spreadsheet is already familiar", "Spreadsheet is already familiar"],
      missingCapabilities: ["import_csv"],
      comparison: "Lost to the current spreadsheet."
    )
    let second = makeEvidenceRecord(
      id: "second",
      endedAt: 200,
      verdict: .promising,
      objections: ["Spreadsheet is already familiar"],
      missingCapabilities: ["import_csv", "permissions"],
      comparison: "Beat the spreadsheet for review speed."
    )
    let failure = makeEvidenceRecord(
      id: "failure",
      experimentID: "experiment-two",
      status: .appCommandFailed,
      endedAt: 150,
      verdict: .rejected,
      missingCapabilities: ["runtime"],
      failure: ProductizationRunFailure(
        status: .appCommandFailed,
        message: "cargo failed"
      )
    )

    let index = ProductizationEvidenceIndex.build(records: [first, second, failure])

    try #require(index.aggregate.latestRunByExperiment["experiment-one"] == "second")
    try #require(index.aggregate.repeatedObjections.first?.objection == "spreadsheet is already familiar")
    try #require(index.aggregate.missingCapabilityFrequency.first?.capabilityID == "import_csv")
    try #require(index.aggregate.verdictCounts["promising"] == 1)
    try #require(index.aggregate.failuresByKind["appCommandFailed"] == 1)
    try #require(
      index.aggregate.currentAlternativeComparisons.contains {
        $0.comparison.contains("Beat the spreadsheet")
      })
  }

  @Test func planningDigestIncludesBoundedProductizationEvidence() throws {
    let config = ProductizationConfig.seedDefaults(
      projectTitle: "Reporting Helper",
      rawPain: "Weekly reporting takes too long.",
      now: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let record = makeEvidenceRecord(
      id: "digest-run",
      experimentID: config.experiments[0].id,
      solutionID: config.solutionHypotheses[0].id,
      painID: config.painHypotheses[0].id,
      branchName: config.experiments[0].branchName,
      verdict: .promising,
      objections: ["Still needs CSV import"],
      missingCapabilities: ["csv_import"],
      comparison: "Beat the spreadsheet on review speed."
    )
    let index = ProductizationEvidenceIndex.build(records: [record])

    let text = ProductizationPlanningDigestFormatter.promptText(
      config: config,
      evidenceIndex: index
    )

    try #require(text.contains("Top evidence signals and objections"))
    try #require(text.contains("digest-run"))
    try #require(text.contains("csv_import"))
    try #require(text.contains("Beat the spreadsheet"))
    try #require(!text.contains("transcript.jsonl"))
  }
}

private func makeEvidenceRecord(
  id: String,
  experimentID: String = "experiment-one",
  solutionID: String = "solution-one",
  painID: String = "pain-one",
  branchName: String = "codex/experiment-one",
  commitSha: String = "abc123",
  scenarioID: String = "scenario-one",
  personaID: String = "segment-one",
  mode: ProductizationSimulationMode = .modelFree,
  status: ProductizationRunStatus = .completed,
  startedAt: Double = 10,
  endedAt: Double = 20,
  verdict: ProductizationEvidenceVerdict = .promising,
  objections: [String] = [],
  missingCapabilities: [String] = [],
  comparison: String = "Compared with the current alternative.",
  failure: ProductizationRunFailure? = nil
) -> ProductizationEvidenceRecord {
  ProductizationEvidenceRecord(
    id: id,
    experimentID: experimentID,
    solutionID: solutionID,
    painID: painID,
    branchName: branchName,
    commitSha: commitSha,
    scenarioID: scenarioID,
    personaID: personaID,
    mode: mode,
    status: status,
    startedAt: startedAt,
    endedAt: endedAt,
    traceHash: "trace-\(id)",
    promptVersions: ["productization.persona_action.v1"],
    model: mode == .modelFree ? "model-free" : "gpt-test",
    scores: ProductizationEvidenceScores(
      painRecognition: 4,
      workflowImprovement: 3,
      alternativeAdvantage: 3,
      switchingReadiness: 2,
      continuedUsePull: 3
    ),
    objections: objections,
    missingCapabilities: missingCapabilities,
    currentAlternativeComparison: comparison,
    verdict: verdict,
    summary: "Evidence summary for \(id).",
    failure: failure
  )
}

private func makeTempDir() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appending(path: "ProductizationEvidenceStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url.standardizedFileURL
}
