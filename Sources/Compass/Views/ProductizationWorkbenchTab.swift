import AppKit
import SwiftUI

struct ProductizationWorkbenchTab: View {
  @ObservedObject var project: CompassProject
  @State private var selectedExperimentID: String?
  @State private var selectedRunID: String?
  @State private var selectedRecord: ProductizationEvidenceRecord?
  @State private var recordError: String?

  private var config: ProductizationConfig { project.productizationConfig }
  private var evidenceIndex: ProductizationEvidenceIndex { project.productizationEvidenceIndex }

  private var selectedExperiment: ProductExperiment? {
    guard let selectedExperimentID else { return config.experiments.first }
    return config.experiments.first { $0.id == selectedExperimentID } ?? config.experiments.first
  }

  private var runsForSelectedExperiment: [ProductizationEvidenceSummary] {
    guard let experimentID = selectedExperiment?.id else { return [] }
    return evidenceIndex.summaries.filter { $0.experimentID == experimentID }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      if config.isEmpty {
        ContentUnavailableView(
          "No Productization State",
          systemImage: "scope",
          description: Text("Enter raw pain or run Discover to seed productization state.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        HStack(alignment: .top, spacing: 12) {
          painMap
            .frame(width: 300)
          Divider()
          solutionAndExperimentBoard
            .frame(minWidth: 360, idealWidth: 460, maxWidth: 560)
          Divider()
          evidenceAndDecisionPane
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
      }
    }
    .task(id: config.experiments.map(\.id).joined(separator: "|")) {
      if selectedExperimentID == nil || !config.experiments.contains(where: { $0.id == selectedExperimentID }) {
        selectedExperimentID = config.experiments.first?.id
      }
      if selectedRunID == nil || !runsForSelectedExperiment.contains(where: { $0.runID == selectedRunID }) {
        selectedRunID = runsForSelectedExperiment.first?.runID
      }
      loadSelectedRecord()
    }
    .onChange(of: selectedExperimentID) { _, _ in
      selectedRunID = runsForSelectedExperiment.first?.runID
      loadSelectedRecord()
    }
    .onChange(of: selectedRunID) { _, _ in
      loadSelectedRecord()
    }
  }

  private var header: some View {
    HStack {
      SectionHeader("Productization", systemImage: "scope")
      Spacer()
      Button {
        Task { await project.reloadProductizationEvidenceIndex() }
      } label: {
        Image(systemName: "arrow.clockwise")
          .frame(width: 18, height: 18)
      }
      .buttonStyle(.borderless)
      .help("Reload productization evidence")
    }
  }

  private var painMap: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 10) {
        WorkbenchSection("Pain Map", systemImage: "person.crop.circle.badge.exclamationmark") {
          VStack(alignment: .leading, spacing: 8) {
            if config.painHypotheses.isEmpty {
              WorkbenchEmptyLine("No pain hypotheses yet.")
            } else {
              ForEach(config.painHypotheses) { pain in
                WorkbenchValueBlock(
                  title: pain.title,
                  subtitle: pain.status.rawValue,
                  detail: pain.rawPain
                )
                if !pain.unknowns.isEmpty {
                  WorkbenchFact(label: "Unknowns", value: pain.unknowns.prefix(3).joined(separator: "; "))
                }
              }
            }
          }
        }

        WorkbenchSection("Segments", systemImage: "person.2") {
          VStack(alignment: .leading, spacing: 8) {
            if config.userSegments.isEmpty {
              WorkbenchEmptyLine("No target segments yet.")
            } else {
              ForEach(config.userSegments) { segment in
                WorkbenchValueBlock(
                  title: segment.name,
                  subtitle: segment.role,
                  detail: segment.skepticism
                )
              }
            }
          }
        }

        WorkbenchSection("Current Workflow", systemImage: "arrow.triangle.branch") {
          VStack(alignment: .leading, spacing: 8) {
            if config.currentWorkflows.isEmpty {
              WorkbenchEmptyLine("No current workflow mapped.")
            } else {
              ForEach(config.currentWorkflows) { workflow in
                WorkbenchValueBlock(
                  title: workflow.title,
                  subtitle: workflow.estimatedCost,
                  detail: workflow.failureModes.prefix(2).joined(separator: "; ")
                )
              }
            }
          }
        }

        WorkbenchSection("Alternatives", systemImage: "arrow.left.arrow.right") {
          VStack(alignment: .leading, spacing: 8) {
            if config.alternatives.isEmpty {
              WorkbenchEmptyLine("No current alternatives captured.")
            } else {
              ForEach(config.alternatives) { alternative in
                WorkbenchValueBlock(
                  title: alternative.title,
                  subtitle: alternative.kind.rawValue,
                  detail: alternative.switchingCost
                )
              }
            }
          }
        }
      }
      .padding(.trailing, 4)
    }
  }

  private var solutionAndExperimentBoard: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 10) {
        WorkbenchSection("Solution Board", systemImage: "rectangle.3.group") {
          VStack(alignment: .leading, spacing: 8) {
            if config.solutionHypotheses.isEmpty {
              WorkbenchEmptyLine("No solution hypotheses yet.")
            } else {
              ForEach(SolutionHypothesisStatus.allCases, id: \.rawValue) { status in
                let solutions = config.solutionHypotheses.filter { $0.status == status }
                if !solutions.isEmpty {
                  VStack(alignment: .leading, spacing: 6) {
                    Text(status.rawValue)
                      .font(.caption.weight(.semibold))
                      .foregroundStyle(.secondary)
                    ForEach(solutions) { solution in
                      WorkbenchValueBlock(
                        title: solution.title,
                        subtitle: "pain \(solution.painID)",
                        detail: solution.promise
                      )
                    }
                  }
                }
              }
            }
          }
        }

        WorkbenchSection("Experiment Board", systemImage: "point.3.connected.trianglepath.dotted") {
          VStack(alignment: .leading, spacing: 8) {
            if config.experiments.isEmpty {
              WorkbenchEmptyLine("No experiment branches yet.")
            } else {
              ForEach(config.experiments) { experiment in
                experimentRow(experiment)
              }
            }
          }
        }
      }
      .padding(.trailing, 4)
    }
  }

  private func experimentRow(_ experiment: ProductExperiment) -> some View {
    Button {
      selectedExperimentID = experiment.id
    } label: {
      VStack(alignment: .leading, spacing: 7) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(experiment.title)
            .font(.callout.weight(.semibold))
            .lineLimit(1)
          Spacer()
          WorkbenchStatusPill(text: experiment.decision.rawValue)
        }
        WorkbenchFact(label: "Branch", value: experiment.branchName)
        WorkbenchFact(label: "Worktree", value: experiment.worktreeID)
        WorkbenchFact(label: "Commit", value: experiment.currentSha ?? experiment.baseSha ?? "not created")
        Text(experiment.prototypeScope)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        selectedExperimentID == experiment.id ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08),
        in: RoundedRectangle(cornerRadius: 8)
      )
    }
    .buttonStyle(.plain)
  }

  private var evidenceAndDecisionPane: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 10) {
        aggregateEvidence
        selectedExperimentActions
        evidenceRuns
        selectedEvidenceDetail
        decisionTimeline
      }
      .padding(.trailing, 8)
    }
  }

  private var aggregateEvidence: some View {
    WorkbenchSection("Evidence View", systemImage: "chart.bar.xaxis") {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 6) {
          WorkbenchMetric(label: "Runs", value: "\(evidenceIndex.summaries.count)", systemImage: "number")
          WorkbenchMetric(
            label: "Failures",
            value: "\(evidenceIndex.aggregate.failuresByKind.values.reduce(0, +))",
            systemImage: "exclamationmark.triangle"
          )
          WorkbenchMetric(
            label: "Verdicts",
            value: "\(evidenceIndex.aggregate.verdictCounts.count)",
            systemImage: "checklist"
          )
        }
        if let objection = evidenceIndex.aggregate.repeatedObjections.first {
          WorkbenchFact(label: "Repeated objection", value: "\(objection.objection) (\(objection.count)x)")
        }
        if let missing = evidenceIndex.aggregate.missingCapabilityFrequency.first {
          WorkbenchFact(label: "Missing capability", value: "\(missing.capabilityID) (\(missing.count)x)")
        }
        if let comparison = evidenceIndex.aggregate.currentAlternativeComparisons.first {
          WorkbenchFact(label: "Alternative", value: "\(comparison.comparison) [\(comparison.verdict.rawValue)]")
        }
        if evidenceIndex.malformedRecordCount > 0 {
          Label("\(evidenceIndex.malformedRecordCount) malformed record(s) skipped", systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
        }
      }
    }
  }

  @ViewBuilder
  private var selectedExperimentActions: some View {
    if let experiment = selectedExperiment {
      WorkbenchSection("Promotion And Archive", systemImage: "arrow.up.forward.circle") {
        VStack(alignment: .leading, spacing: 8) {
          Text(experiment.evidenceSummary)
            .font(.caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
          HStack(spacing: 8) {
            rolloutButton(.promoteOrConfirm, experiment: experiment)
            rolloutButton(.killOrArchive, experiment: experiment)
          }
        }
      }
    }
  }

  private func rolloutButton(
    _ action: ProductExperimentRolloutAction,
    experiment: ProductExperiment
  ) -> some View {
    Button {
      Task { await project.applyProductExperimentRolloutAction(action, experimentID: experiment.id) }
    } label: {
      Label(action.title(from: experiment.decision), systemImage: action == .promoteOrConfirm ? "arrow.up.forward" : "archivebox")
    }
    .buttonStyle(.bordered)
    .disabled(!ProductExperimentRolloutWorkflow.canApply(action, to: experiment))
  }

  private var evidenceRuns: some View {
    WorkbenchSection("Scenario Runs", systemImage: "list.bullet.rectangle") {
      VStack(alignment: .leading, spacing: 8) {
        if runsForSelectedExperiment.isEmpty {
          WorkbenchEmptyLine("No evidence runs for this experiment commit.")
        } else {
          ForEach(runsForSelectedExperiment) { summary in
            Button {
              selectedRunID = summary.runID
            } label: {
              VStack(alignment: .leading, spacing: 5) {
                HStack {
                  Text(summary.runID)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                  Spacer()
                  WorkbenchStatusPill(text: summary.verdict.rawValue)
                }
                Text("\(summary.scenarioID) / \(summary.personaID)")
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
                Text(summary.summary)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(2)
              }
              .padding(10)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(
                selectedRunID == summary.runID ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 8)
              )
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  }

  @ViewBuilder
  private var selectedEvidenceDetail: some View {
    if let record = selectedRecord {
      WorkbenchSection("Selected Run", systemImage: "doc.text.magnifyingglass") {
        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 6) {
            WorkbenchMetric(label: "Pain", value: score(record.scores.painRecognition), systemImage: "scope")
            WorkbenchMetric(label: "Workflow", value: score(record.scores.workflowImprovement), systemImage: "flowchart")
            WorkbenchMetric(label: "Switch", value: score(record.scores.switchingReadiness), systemImage: "arrow.triangle.2.circlepath")
          }
          WorkbenchFact(label: "Scenario", value: record.scenarioID)
          WorkbenchFact(label: "Persona", value: record.personaID)
          WorkbenchFact(label: "Mode", value: record.mode.rawValue)
          WorkbenchFact(label: "Trace", value: record.traceHash ?? "none")
          if !record.objections.isEmpty {
            WorkbenchFact(label: "Objections", value: record.objections.prefix(3).joined(separator: "; "))
          }
          if !record.missingCapabilities.isEmpty {
            WorkbenchFact(label: "Missing", value: record.missingCapabilities.prefix(4).joined(separator: ", "))
          }
          if !record.currentAlternativeComparison.isEmpty {
            WorkbenchFact(label: "Alternative", value: record.currentAlternativeComparison)
          }
          Text(record.summary)
            .font(.callout)
            .textSelection(.enabled)
          ProductizationEvidenceCopyButton(record: record)
        }
      }
    } else if let recordError {
      ContentUnavailableView(
        "Evidence Record Unavailable",
        systemImage: "exclamationmark.triangle",
        description: Text(recordError)
      )
    }
  }

  private var decisionTimeline: some View {
    WorkbenchSection("Decision Timeline", systemImage: "timeline.selection") {
      VStack(alignment: .leading, spacing: 8) {
        let decisions = config.decisions.sorted { lhs, rhs in
          if lhs.decidedAt == rhs.decidedAt { return lhs.id < rhs.id }
          return lhs.decidedAt > rhs.decidedAt
        }
        if decisions.isEmpty {
          WorkbenchEmptyLine("No product decisions recorded yet.")
        } else {
          ForEach(decisions.prefix(8)) { decision in
            VStack(alignment: .leading, spacing: 5) {
              HStack(alignment: .firstTextBaseline) {
                Text(decision.experimentID)
                  .font(.callout.weight(.semibold))
                  .lineLimit(1)
                Spacer()
                WorkbenchStatusPill(text: decision.decision.rawValue)
              }
              Text(decision.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
              if !decision.evidenceRunIDs.isEmpty {
                WorkbenchFact(label: "Evidence", value: decision.evidenceRunIDs.joined(separator: ", "))
              }
              if let branch = decision.branchName {
                WorkbenchFact(label: "Branch", value: branch)
              }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
          }
        }
      }
    }
  }

  private func loadSelectedRecord() {
    guard let selectedRunID else {
      selectedRecord = nil
      recordError = nil
      return
    }
    do {
      selectedRecord = try project.readProductizationEvidenceRecord(id: selectedRunID)
      recordError = nil
    } catch {
      selectedRecord = nil
      recordError = error.localizedDescription
    }
  }

  private func score(_ value: Int?) -> String {
    value.map(String.init) ?? "n/a"
  }
}

private struct WorkbenchSection<Content: View>: View {
  var title: String
  var systemImage: String
  let content: Content

  init(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.systemImage = systemImage
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      Label(title, systemImage: systemImage)
        .font(.callout.weight(.semibold))
      content
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
  }
}

private struct WorkbenchValueBlock: View {
  var title: String
  var subtitle: String
  var detail: String

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline) {
        Text(title)
          .font(.callout.weight(.semibold))
          .lineLimit(1)
        Spacer()
        if !subtitle.isEmpty {
          Text(subtitle)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      if !detail.isEmpty {
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
  }
}

private struct WorkbenchFact: View {
  var label: String
  var value: String

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(label)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(width: 86, alignment: .leading)
      Text(value.isEmpty ? "none" : value)
        .font(.caption)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct WorkbenchMetric: View {
  var label: String
  var value: String
  var systemImage: String

  var body: some View {
    HStack(spacing: 5) {
      Image(systemName: systemImage)
      Text(label)
      Text(value)
        .fontWeight(.bold)
    }
    .font(.caption.weight(.semibold))
    .foregroundStyle(.secondary)
    .lineLimit(1)
    .padding(.horizontal, 7)
    .padding(.vertical, 4)
    .background(.quaternary.opacity(0.55), in: Capsule())
  }
}

private struct WorkbenchStatusPill: View {
  var text: String

  var body: some View {
    Text(text)
      .font(.caption2.weight(.semibold))
      .foregroundStyle(.secondary)
      .lineLimit(1)
      .padding(.horizontal, 6)
      .padding(.vertical, 3)
      .background(.quaternary.opacity(0.55), in: Capsule())
  }
}

private struct WorkbenchEmptyLine: View {
  var text: String

  init(_ text: String) {
    self.text = text
  }

  var body: some View {
    Text(text)
      .font(.caption)
      .foregroundStyle(.secondary)
  }
}

private struct ProductizationEvidenceCopyButton: View {
  var record: ProductizationEvidenceRecord
  @State private var copied = false

  var body: some View {
    Button {
      copyTextToPasteboard(ProductizationEvidenceMarkdownExporter.markdown(record: record))
      copied = true
      Task { @MainActor in
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        copied = false
      }
    } label: {
      Label(copied ? "Copied" : "Copy Summary", systemImage: copied ? "checkmark" : "doc.on.doc")
    }
    .buttonStyle(.bordered)
    .help("Copy productization evidence summary")
  }
}
