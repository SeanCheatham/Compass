import CompassCore
import SwiftUI

struct ChamberResultsTab: View {
  @ObservedObject var project: CompassProject

  var body: some View {
    Group {
      if let snapshot = project.chamberSnapshot {
        ChamberResultsContent(snapshot: snapshot, projectKind: project.projectKind)
      } else {
        ChamberResultsEmptyPlaceholder(projectKind: project.projectKind)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

private struct ChamberResultsEmptyPlaceholder: View {
  var projectKind: ProjectKind

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      SectionHeader("Chamber Results", systemImage: "flame")
      VStack(alignment: .leading, spacing: 8) {
        Text("No chamber snapshot yet.")
          .font(.callout.weight(.semibold))
        Text(emptyDetail)
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(16)
      .frame(maxWidth: 560, alignment: .leading)
      .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var emptyDetail: String {
    switch projectKind {
    case .factory:
      return "After a successful Critic/ship, Compass runs a chamber pass. Findings and generated tests will show up here as Plan pressure."
    case .chamber:
      return "Run a chamber hunt to populate findings, generated tests, and recon summary."
    }
  }
}

private struct ChamberResultsContent: View {
  var snapshot: ChamberSnapshot
  var projectKind: ProjectKind

  private var confirmed: [ChamberFinding] {
    snapshot.findings.filter(\.isConfirmedRealBug)
  }

  private var mutants: [ChamberFinding] {
    snapshot.findings.filter { $0.kind == .survivingMutant }
  }

  private var otherFindings: [ChamberFinding] {
    snapshot.findings.filter { !$0.isConfirmedRealBug && $0.kind != .survivingMutant }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        header
        summaryStrip
        if !confirmed.isEmpty {
          findingsSection(
            title: "Confirmed Bugs",
            systemImage: "exclamationmark.triangle.fill",
            findings: confirmed
          )
        }
        if !otherFindings.isEmpty {
          findingsSection(
            title: "Other Findings",
            systemImage: "questionmark.circle",
            findings: otherFindings
          )
        }
        if !mutants.isEmpty {
          findingsSection(
            title: "Surviving Mutants",
            systemImage: "circle.dotted",
            findings: mutants
          )
        }
        if snapshot.findings.isEmpty {
          emptyFindingsNote
        }
        generatedTestsSection
        reconSection
        if !snapshot.plan.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          proseSection(title: "Hunt Plan", systemImage: "list.bullet.rectangle", text: snapshot.plan)
        }
        if !snapshot.notes.isEmpty {
          notesSection
        }
      }
      .frame(maxWidth: 1060, alignment: .leading)
      .padding(.bottom, 8)
    }
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      SectionHeader("Chamber Results", systemImage: "flame")
      if snapshot.partial {
        Text("Partial")
          .font(.caption.weight(.semibold))
          .padding(.horizontal, 8)
          .padding(.vertical, 3)
          .background(.orange.opacity(0.2), in: Capsule())
          .foregroundStyle(.orange)
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 2) {
        Text(collectedLabel)
          .font(.caption)
          .foregroundStyle(.secondary)
        if let session = snapshot.sessionNumber {
          Text("Session \(session)")
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
      }
    }
  }

  private var collectedLabel: String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return "Updated \(formatter.localizedString(for: snapshot.collectedAt, relativeTo: Date()))"
  }

  private var summaryStrip: some View {
    HStack(spacing: 10) {
      summaryChip(title: "Confirmed", value: "\(confirmed.count)", tint: .red)
      summaryChip(title: "Other", value: "\(otherFindings.count)", tint: .orange)
      summaryChip(title: "Mutants", value: "\(mutants.count)", tint: .secondary)
      summaryChip(title: "Gen tests", value: "\(snapshot.generatedTests.count)", tint: .indigo)
      Spacer(minLength: 0)
    }
  }

  private func summaryChip(title: String, value: String, tint: Color) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(value)
        .font(.title3.monospacedDigit().weight(.semibold))
        .foregroundStyle(tint)
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
  }

  private var emptyFindingsNote: some View {
    Text(
      projectKind == .chamber
        ? "This hunt recorded no findings."
        : "Last chamber pass recorded no findings."
    )
    .font(.callout)
    .foregroundStyle(.secondary)
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
  }

  private func findingsSection(
    title: String,
    systemImage: String,
    findings: [ChamberFinding]
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(title, systemImage: systemImage)
        .font(.subheadline.weight(.semibold))
      VStack(alignment: .leading, spacing: 8) {
        ForEach(findings) { finding in
          ChamberFindingRow(finding: finding)
        }
      }
    }
  }

  private var generatedTestsSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("Generated Tests", systemImage: "doc.text")
        .font(.subheadline.weight(.semibold))
      if snapshot.generatedTests.isEmpty {
        Text("No compass_gen tests in this snapshot.")
          .font(.callout)
          .foregroundStyle(.secondary)
          .padding(12)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
      } else {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(Array(snapshot.generatedTests.enumerated()), id: \.offset) { _, test in
            ChamberGeneratedTestRow(test: test)
          }
        }
      }
    }
  }

  private var reconSection: some View {
    let recon = snapshot.recon
    let baseline = recon.baselineTests
    return VStack(alignment: .leading, spacing: 10) {
      Label("Recon", systemImage: "magnifyingglass")
        .font(.subheadline.weight(.semibold))
      VStack(alignment: .leading, spacing: 8) {
        if !recon.packageNames.isEmpty {
          Text("Packages: \(recon.packageNames.joined(separator: ", "))")
            .font(.callout)
        }
        Text(
          "Baseline tests: \(baseline.success ? "ok" : "failed") · \(baseline.passed) passed · \(baseline.failed) failed · \(baseline.ignored) ignored"
        )
        .font(.callout)
        .foregroundStyle(baseline.success ? Color.secondary : Color.orange)
        if !recon.rankedTargets.isEmpty {
          Text("Ranked targets")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
          ForEach(Array(recon.rankedTargets.prefix(8).enumerated()), id: \.offset) { _, target in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
              Text(target.path)
                .font(.caption.monospaced())
              if let hint = target.functionHint, !hint.isEmpty {
                Text(hint)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer(minLength: 0)
              Text(target.reason)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }
          }
        }
        if !recon.notes.isEmpty {
          ForEach(recon.notes, id: \.self) { note in
            Text(note)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
    }
  }

  private func proseSection(title: String, systemImage: String, text: String) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(title, systemImage: systemImage)
        .font(.subheadline.weight(.semibold))
      Text(text)
        .font(.callout)
        .textSelection(.enabled)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
    }
  }

  private var notesSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("Notes", systemImage: "note.text")
        .font(.subheadline.weight(.semibold))
      VStack(alignment: .leading, spacing: 6) {
        ForEach(snapshot.notes, id: \.self) { note in
          Text("• \(note)")
            .font(.callout)
            .textSelection(.enabled)
        }
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
    }
  }
}

private struct ChamberFindingRow: View {
  var finding: ChamberFinding
  @State private var expanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(finding.title.isEmpty ? finding.kindLabel : finding.title)
          .font(.callout.weight(.semibold))
          .textSelection(.enabled)
        Spacer(minLength: 8)
        Text(finding.kindLabel)
          .font(.caption2.weight(.medium))
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(.quaternary.opacity(0.5), in: Capsule())
        Text(confidenceLabel)
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.secondary)
        if finding.triage != nil || !finding.evidence.isEmpty || !finding.description.isEmpty {
          Button {
            expanded.toggle()
          } label: {
            Image(systemName: expanded ? "chevron.down" : "chevron.right")
              .font(.caption.weight(.semibold))
          }
          .buttonStyle(.borderless)
          .accessibilityLabel(expanded ? "Collapse finding" : "Expand finding")
        }
      }

      if let file = finding.file {
        Text(file)
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
      }
      if let testPath = finding.testPath {
        Text(testPath)
          .font(.caption.monospaced())
          .foregroundStyle(.tertiary)
          .textSelection(.enabled)
      }

      if expanded {
        if !finding.description.isEmpty {
          Text(finding.description)
            .font(.callout)
            .textSelection(.enabled)
        }
        if let triage = finding.triage {
          Text(triage.isRealBug ? "Triage: real bug" : "Triage: likely false positive")
            .font(.caption.weight(.semibold))
            .foregroundStyle(triage.isRealBug ? .red : .secondary)
          if !triage.rationale.isEmpty {
            Text(triage.rationale)
              .font(.caption)
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
          }
        }
        if !finding.evidence.isEmpty {
          Text(finding.evidence)
            .font(.caption.monospaced())
            .textSelection(.enabled)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        }
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
  }

  private var confidenceLabel: String {
    "\(Int((finding.confidence * 100).rounded()))%"
  }
}

private struct ChamberGeneratedTestRow: View {
  var test: ChamberGeneratedTest

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Image(systemName: statusSymbol)
        .foregroundStyle(statusColor)
        .frame(width: 14)
      VStack(alignment: .leading, spacing: 2) {
        Text(test.path)
          .font(.callout.monospaced())
          .textSelection(.enabled)
        if !test.targetHint.isEmpty {
          Text(test.targetHint)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if let errors = test.compileErrors, !errors.isEmpty {
          Text(errors)
            .font(.caption2)
            .foregroundStyle(.orange)
            .lineLimit(3)
            .textSelection(.enabled)
        }
      }
      Spacer(minLength: 0)
      Text(statusLabel)
        .font(.caption.weight(.medium))
        .foregroundStyle(statusColor)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
  }

  private var statusLabel: String {
    if !test.compiled { return "Compile failed" }
    if let passed = test.passed {
      return passed ? "Passed" : "Failed"
    }
    return "Compiled"
  }

  private var statusSymbol: String {
    if !test.compiled { return "xmark.octagon.fill" }
    if let passed = test.passed {
      return passed ? "checkmark.circle.fill" : "xmark.circle.fill"
    }
    return "checkmark.circle"
  }

  private var statusColor: Color {
    if !test.compiled { return .orange }
    if let passed = test.passed {
      return passed ? .green : .red
    }
    return .secondary
  }
}

extension ChamberFinding {
  fileprivate var kindLabel: String {
    switch kind {
    case .failingGeneratedTest: return "Failing test"
    case .baselineFailure: return "Baseline"
    case .survivingMutant: return "Mutant"
    }
  }
}
