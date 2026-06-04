import AppKit
import SwiftUI

struct PMFEvidenceTab: View {
  @ObservedObject var project: CompassProject
  @State private var selectedRunID: String?
  @State private var selectedRecord: PMFEvidenceRecord?
  @State private var recordError: String?

  private var summaries: [PMFEvidenceSummary] {
    project.pmfEvidenceIndex.summaries
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        SectionHeader("PMF Evidence", systemImage: "chart.bar.xaxis")
        Spacer()
        Button {
          Task { await project.reloadPMFEvidenceIndex() }
        } label: {
          Image(systemName: "arrow.clockwise")
            .frame(width: 18, height: 18)
        }
        .buttonStyle(.borderless)
        .help("Reload PMF evidence")
      }

      if summaries.isEmpty {
        ContentUnavailableView(
          "No PMF Evidence",
          systemImage: "chart.bar.xaxis",
          description: Text("Run PMF simulations to collect persona evidence.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        HStack(alignment: .top, spacing: 12) {
          runList
            .frame(width: 310)
          Divider()
          selectedRunDetail
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
      }
    }
    .task(id: summaries.map(\.runID).joined(separator: "|")) {
      if selectedRunID == nil || !summaries.contains(where: { $0.runID == selectedRunID }) {
        selectedRunID = summaries.first?.runID
      }
      loadSelectedRecord()
    }
    .onChange(of: selectedRunID) { _, _ in
      loadSelectedRecord()
    }
  }

  private var runList: some View {
    VStack(alignment: .leading, spacing: 8) {
      aggregateStrip
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 6) {
          ForEach(summaries) { summary in
            PMFEvidenceRunRow(
              summary: summary,
              personaLabel: personaLabel(summary.personaID),
              taskLabel: taskLabel(summary.taskID),
              isSelected: selectedRunID == summary.runID
            ) {
              selectedRunID = summary.runID
            }
          }
        }
      }
    }
  }

  private var aggregateStrip: some View {
    let aggregate = project.pmfEvidenceIndex.aggregate
    return VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        PMFEvidenceMetricPill(
          label: "Runs",
          value: "\(summaries.count)",
          systemImage: "number"
        )
        PMFEvidenceMetricPill(
          label: "Failures",
          value: "\(aggregate.failuresByKind.values.reduce(0, +))",
          systemImage: "exclamationmark.triangle"
        )
      }
      if let objection = aggregate.repeatedObjections.first {
        Text("Repeated objection: \(objection.objection) (\(objection.count))")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
      if project.pmfEvidenceIndex.malformedRecordCount > 0 {
        Label(
          "\(project.pmfEvidenceIndex.malformedRecordCount) malformed record(s) skipped",
          systemImage: "exclamationmark.triangle"
        )
        .font(.caption)
        .foregroundStyle(.orange)
      }
    }
    .padding(10)
    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
  }

  @ViewBuilder
  private var selectedRunDetail: some View {
    if let record = selectedRecord {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
              Text(personaLabel(record.personaID))
                .font(.headline)
              Text(taskLabel(record.taskID))
                .font(.subheadline)
                .foregroundStyle(.secondary)
              Text(hypothesisLabel(record.hypothesisID))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            PMFEvidenceSummaryExportButton(record: record, config: project.pmfConfig)
          }

          PMFEvidenceContextSection(record: record)

          if let feedback = record.feedback {
            PMFFeedbackSection(feedback: feedback)
          } else if let failure = record.failure {
            PMFFailureSection(failure: failure)
          }

          PMFTraceSummarySection(record: record)

          DisclosureGroup("Raw transcript") {
            VStack(alignment: .leading, spacing: 8) {
              ForEach(record.actionTranscript.turns.indices, id: \.self) { index in
                let turn = record.actionTranscript.turns[index]
                VStack(alignment: .leading, spacing: 3) {
                  Text("\(turn.turnIndex). \(turn.actionID)")
                    .font(.caption.weight(.semibold))
                  Text(turn.rationale.isEmpty ? "No rationale recorded." : turn.rationale)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
              }
            }
            .padding(.top, 6)
          }

          if !record.artifacts.isEmpty {
            PMFArtifactSection(artifacts: record.artifacts)
          }
        }
        .padding(.trailing, 8)
      }
    } else if let recordError {
      ContentUnavailableView(
        "Evidence Record Unavailable",
        systemImage: "exclamationmark.triangle",
        description: Text(recordError)
      )
    } else {
      ContentUnavailableView("Select a PMF Run", systemImage: "chart.bar.xaxis")
    }
  }

  private func loadSelectedRecord() {
    guard let selectedRunID else {
      selectedRecord = nil
      recordError = nil
      return
    }
    do {
      selectedRecord = try project.readPMFEvidenceRecord(id: selectedRunID)
      recordError = nil
    } catch {
      selectedRecord = nil
      recordError = error.localizedDescription
    }
  }

  private func hypothesisLabel(_ id: String) -> String {
    project.pmfConfig.hypotheses.first { $0.id == id }?.title ?? id
  }

  private func personaLabel(_ id: String) -> String {
    project.pmfConfig.personas.first { $0.id == id }?.name ?? id
  }

  private func taskLabel(_ id: String) -> String {
    project.pmfConfig.tasks.first { $0.id == id }?.title ?? id
  }
}

private struct PMFEvidenceRunRow: View {
  var summary: PMFEvidenceSummary
  var personaLabel: String
  var taskLabel: String
  var isSelected: Bool
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 5) {
        HStack(alignment: .firstTextBaseline) {
          Text(personaLabel)
            .font(.callout.weight(.semibold))
            .lineLimit(1)
          Spacer()
          Text(summary.status.rawValue)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(statusColor)
        }
        Text(taskLabel)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        if let verdict = summary.verdict {
          Text("\(verdict.rawValue) · value \(summary.valueScore ?? 0)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        } else if let failure = summary.failureKind {
          Text(failure)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        isSelected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08),
        in: RoundedRectangle(cornerRadius: 8)
      )
    }
    .buttonStyle(.plain)
  }

  private var statusColor: Color {
    summary.status == .completed ? .green : .orange
  }
}

private struct PMFEvidenceContextSection: View {
  var record: PMFEvidenceRecord

  var body: some View {
    PMFEvidenceSection("Run Context", systemImage: "info.circle") {
      VStack(alignment: .leading, spacing: 5) {
        PMFEvidenceFact(label: "Scenario", value: record.scenarioID)
        PMFEvidenceFact(label: "Route", value: record.route)
        PMFEvidenceFact(label: "Model", value: record.model.isEmpty ? "unspecified" : record.model)
        PMFEvidenceFact(
          label: "Prompt versions",
          value: record.promptVersions.isEmpty ? "none" : record.promptVersions.joined(separator: ", ")
        )
      }
    }
  }
}

private struct PMFFeedbackSection: View {
  var feedback: PMFFeedbackRecord

  var body: some View {
    PMFEvidenceSection("Feedback", systemImage: "person.crop.circle.badge.questionmark") {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 6) {
          PMFEvidenceMetricPill(label: "Value", value: "\(feedback.valueScore)", systemImage: "sparkles")
          PMFEvidenceMetricPill(label: "Clarity", value: "\(feedback.clarityScore)", systemImage: "eye")
          PMFEvidenceMetricPill(label: "Trust", value: "\(feedback.trustScore)", systemImage: "checkmark.seal")
          PMFEvidenceMetricPill(label: "Switch", value: "\(feedback.switchLikelihood)", systemImage: "arrow.triangle.2.circlepath")
          PMFEvidenceMetricPill(label: "Pay", value: "\(feedback.payLikelihood)", systemImage: "creditcard")
        }
        PMFEvidenceFact(label: "Verdict", value: feedback.verdict.rawValue)
        PMFEvidenceFact(label: "Task outcome", value: feedback.taskOutcome.rawValue)
        PMFEvidenceFact(label: "Top objection", value: feedback.topObjection)
        PMFEvidenceFact(label: "Missing capability", value: feedback.missingCapability)
        if let confusion = feedback.momentOfConfusion {
          PMFEvidenceFact(label: "Confusion", value: confusion)
        }
        Text(feedback.summary)
          .font(.callout)
          .textSelection(.enabled)
      }
    }
  }
}

private struct PMFFailureSection: View {
  var failure: PMFRunFailure

  var body: some View {
    PMFEvidenceSection("Failure", systemImage: "exclamationmark.triangle") {
      VStack(alignment: .leading, spacing: 6) {
        PMFEvidenceFact(label: "Kind", value: failure.status.rawValue)
        Text(failure.message)
          .font(.callout)
          .textSelection(.enabled)
      }
    }
  }
}

private struct PMFTraceSummarySection: View {
  var record: PMFEvidenceRecord

  var body: some View {
    PMFEvidenceSection("Trace Summary", systemImage: "point.3.connected.trianglepath.dotted") {
      VStack(alignment: .leading, spacing: 6) {
        PMFEvidenceFact(label: "Status", value: record.status.rawValue)
        PMFEvidenceFact(label: "Actions", value: "\(record.actionTranscript.turns.count)")
        if let hash = record.experienceTraceHash {
          PMFEvidenceFact(label: "Trace hash", value: hash)
        }
      }
    }
  }
}

private struct PMFArtifactSection: View {
  var artifacts: [PMFRunArtifact]

  var body: some View {
    PMFEvidenceSection("Artifacts", systemImage: "doc.text") {
      VStack(alignment: .leading, spacing: 5) {
        ForEach(artifacts) { artifact in
          PMFEvidenceFact(
            label: artifact.kind.rawValue,
            value: "\(artifact.path) · \(artifact.byteCount) bytes"
          )
        }
      }
    }
  }
}

private struct PMFEvidenceSection<Content: View>: View {
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

private struct PMFEvidenceFact: View {
  var label: String
  var value: String

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(label)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(width: 112, alignment: .leading)
      Text(value)
        .font(.caption)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct PMFEvidenceMetricPill: View {
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

private struct PMFEvidenceSummaryExportButton: View {
  var record: PMFEvidenceRecord
  var config: PMFConfig
  @State private var copied = false

  var body: some View {
    Button {
      copyTextToPasteboard(PMFEvidenceMarkdownExporter.markdown(record: record, config: config))
      copied = true
      Task { @MainActor in
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        copied = false
      }
    } label: {
      Label(copied ? "Copied" : "Copy Summary", systemImage: copied ? "checkmark" : "doc.on.doc")
    }
    .buttonStyle(.bordered)
    .help("Copy PMF evidence summary")
  }
}
