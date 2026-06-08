import SwiftUI

struct ProductTestBuilderView<Details: View, RunControls: View, AuditContent: View>: View {
  var draft: ProductTestDraft
  @ViewBuilder var details: Details
  @ViewBuilder var runControls: RunControls
  @ViewBuilder var auditContent: AuditContent

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      questionHeader
      preview
      validationGrid
      VStack(alignment: .leading, spacing: 9) {
        details
      }
      runControls
      DisclosureGroup {
        VStack(alignment: .leading, spacing: 8) {
          auditContent
          if !draft.auditReferences.isEmpty {
            Divider()
            ForEach(draft.auditReferences, id: \.self) { reference in
              BuilderAuditFact(label: reference.label, value: reference.value)
            }
          }
        }
        .padding(.top, 6)
      } label: {
        Label("Audit / advanced", systemImage: ProductIconRole.audit.systemImage)
          .font(.caption.weight(.semibold))
      }
    }
  }

  private var questionHeader: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: ProductIconRole.useProof.systemImage)
        .font(.title3.weight(.semibold))
        .foregroundStyle(draft.canRun ? ProductSignalTone.strong.compassColor : ProductSignalTone.missing.compassColor)
        .frame(width: 24, height: 24)
      VStack(alignment: .leading, spacing: 5) {
        Text(draft.productQuestion)
          .font(.headline)
          .lineLimit(2)
        Text(draft.evidenceGap)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
        HStack(spacing: 7) {
          BuilderChip(text: draft.targetUser, role: .contender)
          BuilderChip(text: draft.expectedDecision, role: .advance)
          BuilderChip(text: draft.runSettingSummary, role: .evidence)
        }
      }
    }
  }

  private var preview: some View {
    VStack(alignment: .leading, spacing: 6) {
      ForEach(Array(draft.previewLines.enumerated()), id: \.offset) { _, line in
        Text(line)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
  }

  private var validationGrid: some View {
    LazyVGrid(
      columns: [GridItem(.adaptive(minimum: 128, maximum: 220), spacing: 8)],
      alignment: .leading,
      spacing: 8
    ) {
      ForEach(draft.validationItems) { item in
        HStack(spacing: 7) {
          Circle()
            .fill(item.state.tone.compassColor)
            .frame(width: 8, height: 8)
          VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
              .font(.caption.weight(.semibold))
              .lineLimit(1)
            Text(item.detail)
              .font(.caption2)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .help(item.detail)
      }
    }
  }
}

private struct BuilderAuditFact: View {
  var label: String
  var value: String

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Text(label)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
      Text(value)
        .font(.caption2.monospaced())
        .foregroundStyle(.secondary)
        .lineLimit(2)
    }
  }
}

private struct BuilderChip: View {
  var text: String
  var role: ProductIconRole

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: role.systemImage)
        .font(.caption2.weight(.semibold))
      Text(text)
        .font(.caption2.weight(.semibold))
        .lineLimit(1)
    }
    .padding(.horizontal, 7)
    .padding(.vertical, 4)
    .foregroundStyle(.secondary)
    .background(Color.secondary.opacity(0.08), in: Capsule())
  }
}
