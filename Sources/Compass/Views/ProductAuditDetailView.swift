import SwiftUI

struct ProductAuditDetailView: View {
  var title: String
  var references: [AuditReference]

  private var groupedReferences: [(kind: AuditReferenceKind, references: [AuditReference])] {
    Dictionary(grouping: references, by: \.kind)
      .map { key, values in
        (
          key,
          values.sorted {
            if $0.label == $1.label { return $0.value < $1.value }
            return $0.label < $1.label
          }
        )
      }
      .sorted { lhs, rhs in lhs.kind.rawValue < rhs.kind.rawValue }
  }

  var body: some View {
    DisclosureGroup {
      if groupedReferences.isEmpty {
        Text("No audit references for this selection.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.top, 6)
      } else {
        VStack(alignment: .leading, spacing: 10) {
          ForEach(groupedReferences, id: \.kind) { group in
            VStack(alignment: .leading, spacing: 5) {
              Text(group.kind.displayLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
              ForEach(group.references, id: \.self) { reference in
                AuditReferenceRow(reference: reference)
              }
            }
          }
        }
        .padding(.top, 8)
      }
    } label: {
      Label(title, systemImage: ProductIconRole.audit.systemImage)
        .font(.caption.weight(.semibold))
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
    )
  }
}

private struct AuditReferenceRow: View {
  var reference: AuditReference

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(reference.label)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(width: 118, alignment: .leading)
      Text(reference.value)
        .font(.caption2.monospaced())
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        .lineLimit(2)
      Spacer(minLength: 0)
    }
  }
}

private extension AuditReferenceKind {
  var displayLabel: String {
    switch self {
    case .pain:
      return "Pain"
    case .tournament:
      return "Tournament"
    case .round:
      return "Round"
    case .contender:
      return "Contender"
    case .contenderPlan:
      return "Contender plan"
    case .experiment:
      return "Experiment"
    case .scenario:
      return "Scenario"
    case .cohort:
      return "Cohort"
    case .evidenceRun:
      return "Evidence run"
    case .planEvaluation:
      return "Plan evaluation"
    case .automationAudit:
      return "Automation audit"
    case .branch:
      return "Branch"
    case .commit:
      return "Commit"
    case .model:
      return "Model"
    case .promptVersion:
      return "Prompt version"
    }
  }
}
