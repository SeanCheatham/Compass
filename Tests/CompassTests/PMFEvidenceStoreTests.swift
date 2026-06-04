import Foundation
import Testing

@testable import Compass

struct PMFEvidenceStoreTests {
  @Test func evidenceStoreWritesRecordArtifactsAndQuickIndex() throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()

    let record = makeEvidenceRecord(id: "run-one", feedback: makeFeedback(topObjection: "Spreadsheet still wins"))
    let stored = try workspace.writePMFEvidenceRecord(
      record,
      experienceTraceJSON: #"{"trace":"ok"}"#,
      rawTranscriptJSON: #"{"raw":"persona transcript"}"#
    )

    try #require(stored.artifacts.map(\.kind) == [.experienceTrace, .rawTranscript])
    try #require(
      FileManager.default.fileExists(
        atPath: workspace.compassURL.appending(path: "pmf/runs/run-one-trace.json").path
      ))
    try #require(
      FileManager.default.fileExists(
        atPath: workspace.compassURL.appending(path: "pmf/runs/run-one-raw-transcript.json").path
      ))

    let index = workspace.readPMFEvidenceIndex()
    try #require(index.summaries.count == 1)
    try #require(index.summaries[0].runID == "run-one")
    try #require(index.summaries[0].topObjection == "Spreadsheet still wins")
    try #require(index.summaries[0].artifactCount == 2)

    let read = try workspace.readPMFEvidenceRecord(id: "run-one")
    try #require(read == stored)
  }

  @Test func indexRebuildSkipsMalformedIndividualRecords() throws {
    let root = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = CompassWorkspace(repoURL: root)
    try workspace.initialize()
    _ = try workspace.writePMFEvidenceRecord(makeEvidenceRecord(id: "valid-run"))

    let badURL = workspace.compassURL.appending(path: "pmf/runs/bad-run.json")
    try "{ nope".write(to: badURL, atomically: true, encoding: .utf8)

    let rebuilt = try workspace.pmfEvidenceStore.rebuildIndex(
      now: Date(timeIntervalSince1970: 1_700_000_050)
    )

    try #require(rebuilt.summaries.map(\.runID) == ["valid-run"])
    try #require(rebuilt.malformedRecordCount == 1)
    try #require(workspace.readPMFEvidenceIndex() == rebuilt)
  }

  @Test func aggregateSummaryComputesRepeatedObjectionsAveragesLatestAndFailures() throws {
    let first = makeEvidenceRecord(
      id: "run-a",
      scenarioID: "scenario-a",
      endedAt: 100,
      feedback: makeFeedback(
        valueScore: 3,
        clarityScore: 2,
        trustScore: 3,
        switchLikelihood: 2,
        payLikelihood: 1,
        topObjection: "Spreadsheet still wins",
        verdict: .notYet
      )
    )
    let second = makeEvidenceRecord(
      id: "run-b",
      scenarioID: "scenario-a",
      endedAt: 200,
      feedback: makeFeedback(
        valueScore: 5,
        clarityScore: 4,
        trustScore: 4,
        switchLikelihood: 3,
        payLikelihood: 2,
        topObjection: "spreadsheet   still wins",
        verdict: .somePull
      )
    )
    let failure = makeEvidenceRecord(
      id: "run-c",
      scenarioID: "scenario-b",
      status: .appOutputNotJSON,
      endedAt: 150,
      feedback: nil,
      failure: PMFRunFailure(status: .appOutputNotJSON, message: "bad json")
    )

    let index = PMFEvidenceIndex.build(records: [first, second, failure])

    try #require(index.aggregate.repeatedObjections == [
      PMFRepeatedObjection(objection: "spreadsheet still wins", count: 2)
    ])
    try #require(index.aggregate.verdictCounts == ["not_yet": 1, "some_pull": 1])
    try #require(index.aggregate.latestRunByScenario["scenario-a"] == "run-b")
    try #require(index.aggregate.failuresByKind == ["appOutputNotJSON": 1])
    let average = try #require(index.aggregate.averageScoresByPersonaTask.first)
    try #require(average.runCount == 2)
    try #require(average.valueScore == 4.0)
    try #require(average.payLikelihood == 1.5)
  }

  @Test func markdownExportIncludesScoresContextActionsAndArtifacts() throws {
    let config = PMFConfig.seedDefaults(
      projectTitle: "Compass PMF",
      vision: "A product fit simulator.",
      now: Date(timeIntervalSince1970: 1_700_000_000)
    )
    var record = makeEvidenceRecord(
      id: "run-export",
      hypothesisID: config.hypotheses[0].id,
      personaID: config.personas[0].id,
      taskID: config.tasks[0].id,
      feedback: makeFeedback(topObjection: "Needs an import example")
    )
    record.artifacts = [
      PMFRunArtifact(
        kind: .experienceTrace,
        path: "pmf/runs/run-export-trace.json",
        byteCount: 12
      )
    ]

    let markdown = PMFEvidenceMarkdownExporter.markdown(record: record, config: config)

    try #require(markdown.contains(config.personas[0].name))
    try #require(markdown.contains("Scores: value 3"))
    try #require(markdown.contains("Needs an import example"))
    try #require(markdown.contains("inspect_value_prop"))
    try #require(markdown.contains("pmf/runs/run-export-trace.json"))
  }
}

private func makeEvidenceRecord(
  id: String,
  hypothesisID: String = "hypothesis",
  personaID: String = "persona",
  taskID: String = "task",
  scenarioID: String = "scenario",
  status: PMFRunStatus = .completed,
  endedAt: Double = 20,
  feedback: PMFFeedbackRecord? = makeFeedback(),
  failure: PMFRunFailure? = nil
) -> PMFEvidenceRecord {
  PMFEvidenceRecord(
    id: id,
    projectID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")?.uuidString,
    commitSHA: "abc123",
    hypothesisID: hypothesisID,
    personaID: personaID,
    taskID: taskID,
    scenarioID: scenarioID,
    startedAt: 10,
    endedAt: endedAt,
    status: status,
    route: "native-macos",
    model: "test-model",
    promptVersions: [Prompts.pmfPersonaActionPromptVersionID, Prompts.pmfFeedbackPromptVersionID],
    experienceTraceHash: "trace-hash",
    actionTranscript: PMFRunTranscript(
      turns: [
        PMFActionTurnRecord(
          turnIndex: 0,
          phase: .choose,
          promptVersionID: Prompts.pmfPersonaActionPromptVersionID,
          actionID: "inspect_value_prop",
          params: .object([:]),
          wasValid: true,
          allowedActionIDs: ["inspect_value_prop"],
          rationale: "I need to inspect the claim.",
          rawResponse: #"{"actionId":"inspect_value_prop"}"#
        )
      ]
    ),
    feedback: feedback,
    failure: failure
  )
}

private func makeFeedback(
  valueScore: Int = 3,
  clarityScore: Int = 2,
  trustScore: Int = 3,
  switchLikelihood: Int = 2,
  payLikelihood: Int = 1,
  topObjection: String = "I still cannot tell how this replaces my current spreadsheet.",
  verdict: PMFPersonaVerdict = .notYet
) -> PMFFeedbackRecord {
  PMFFeedbackRecord(
    promptVersionID: Prompts.pmfFeedbackPromptVersionID,
    valueScore: valueScore,
    clarityScore: clarityScore,
    trustScore: trustScore,
    switchLikelihood: switchLikelihood,
    payLikelihood: payLikelihood,
    taskOutcome: .partial,
    topObjection: topObjection,
    missingCapability: "A concrete import or reporting example.",
    momentOfConfusion: "The first screen is vague.",
    verdict: verdict,
    summary: "The promise is plausible, but the experience does not prove value quickly."
  )
}

private func makeTempDir() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appending(path: "PMFEvidenceStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url.standardizedFileURL
}
