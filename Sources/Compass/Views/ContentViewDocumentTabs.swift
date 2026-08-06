import AppKit
import CompassCore
import SwiftUI

struct VisionTab: View {
  @ObservedObject var project: CompassProject

  var body: some View {
    let guide = ProjectVisionGuide(
      brief: project.brief,
      ledger: project.requirementLedger
    )
    let clipboardPayload = ProjectVisionClipboardPayload(guide: guide)

    VStack(alignment: .leading, spacing: 12) {
      HStack {
        SectionHeader("Project Brief", systemImage: "scope")
        Spacer()
        Button {
          Task {
            await project.saveBrief()
            await project.saveRequirementLedger()
          }
        } label: {
          Label("Save", systemImage: "square.and.arrow.down")
        }
      }
      ProjectVisionGuidePanel(
        guide: guide,
        clipboardPayload: clipboardPayload
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          BriefTextField(
            title: "Audience",
            placeholder: "Who does this software help?",
            text: $project.brief.audience
          )
          BriefTextField(
            title: "Problem",
            placeholder: "What pain or opportunity should Compass address?",
            text: $project.brief.problem
          )
          ProductRequirementsEditor(
            requirements: $project.brief.productRequirements,
            ledger: $project.requirementLedger
          )
        }
        .padding(.bottom, 8)
      }
    }
  }
}

private struct BriefTextField: View {
  var title: String
  var placeholder: String
  @Binding var text: String

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.subheadline.weight(.semibold))
      ZStack(alignment: .topLeading) {
        TextEditor(text: $text)
          .font(.body)
          .scrollContentBackground(.hidden)
          .frame(minHeight: 72, maxHeight: 120)
          .padding(8)

        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          Text(placeholder)
            .font(.body)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 13)
            .padding(.vertical, 16)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
      }
      .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
  }
}

private struct ProductRequirementsEditor: View {
  @Binding var requirements: [ProductRequirement]
  @Binding var ledger: RequirementLedger

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Product Requirements")
          .font(.subheadline.weight(.semibold))
        Spacer()
        Button {
          requirements.append(ProductRequirement(text: ""))
        } label: {
          Label("Add", systemImage: "plus")
        }
        .buttonStyle(.borderless)
      }

      if requirements.isEmpty {
        Text("Add the concrete outcomes this product must deliver.")
          .font(.callout)
          .foregroundStyle(.secondary)
          .padding(12)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
      } else {
        ForEach($requirements) { $requirement in
          VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
              TextField("Requirement", text: $requirement.text, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.plain)
                .padding(8)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))

              Button {
                let id = requirement.id
                requirements.removeAll { $0.id == id }
                ledger = RequirementLedger(
                  entries: ledger.entries.filter { $0.requirementID != id }
                )
              } label: {
                Image(systemName: "minus.circle.fill")
                  .foregroundStyle(.secondary)
              }
              .buttonStyle(.borderless)
              .help("Remove requirement")
              .accessibilityLabel("Remove requirement")
            }

            RequirementStatusRow(
              entry: ledger.entry(for: requirement.id)
            )

            RequirementCriteriaEditor(
              requirementID: requirement.id,
              ledger: $ledger
            )
          }
          .padding(10)
          .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
        }
      }
    }
  }
}

private struct RequirementStatusRow: View {
  var entry: RequirementLedgerEntry?

  var body: some View {
    let status = entry?.status ?? .unverified
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Label(statusLabel(status), systemImage: statusImage(status))
        .font(.caption.weight(.semibold))
        .foregroundStyle(statusColor(status))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(statusColor(status).opacity(0.12), in: Capsule())

      if let evidence = entry?.lastAudit?.evidence.prefix(2), !evidence.isEmpty {
        Text(evidence.joined(separator: " · "))
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
          .textSelection(.enabled)
      } else {
        Text("No audit evidence yet.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func statusLabel(_ status: RequirementVerificationStatus) -> String {
    switch status {
    case .unverified: return "Unverified"
    case .satisfied: return "Satisfied"
    case .unsatisfied: return "Unsatisfied"
    }
  }

  private func statusImage(_ status: RequirementVerificationStatus) -> String {
    switch status {
    case .unverified: return "questionmark.circle"
    case .satisfied: return "checkmark.seal.fill"
    case .unsatisfied: return "exclamationmark.triangle.fill"
    }
  }

  private func statusColor(_ status: RequirementVerificationStatus) -> Color {
    switch status {
    case .unverified: return .secondary
    case .satisfied: return .green
    case .unsatisfied: return .orange
    }
  }
}

private struct RequirementCriteriaEditor: View {
  var requirementID: String
  @Binding var ledger: RequirementLedger

  private var criteriaBinding: Binding<String> {
    Binding(
      get: {
        ledger.entry(for: requirementID)?.criteria.joined(separator: "\n") ?? ""
      },
      set: { newValue in
        let lines =
          newValue
          .components(separatedBy: .newlines)
          .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
          .filter { !$0.isEmpty }
        ledger = ledger.updatingCriteria(requirementID: requirementID, criteria: lines)
      }
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Verification criteria (one shell command per line)")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      TextEditor(text: criteriaBinding)
        .font(.system(.caption, design: .monospaced))
        .scrollContentBackground(.hidden)
        .frame(minHeight: 44, maxHeight: 88)
        .padding(6)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
    }
  }
}

private struct ProjectVisionGuidePanel: View {
  var guide: ProjectVisionGuide
  var clipboardPayload: ProjectVisionClipboardPayload

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Label(guide.title, systemImage: systemImage)
          .font(.callout.weight(.semibold))
          .foregroundStyle(color)

        Spacer(minLength: 8)

        CopyProjectVisionButton(payload: clipboardPayload)

        Text(guide.scoreLabel)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .padding(.horizontal, 7)
          .padding(.vertical, 2)
          .background(.quaternary.opacity(0.65), in: Capsule())
      }

      Text(guide.detail)
        .font(.callout)
        .foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 6) {
          ForEach(guide.cues) { cue in
            Label(cue.title, systemImage: cue.systemImage)
              .font(.caption.weight(.semibold))
              .foregroundStyle(cue.isSatisfied ? color : .secondary)
              .lineLimit(1)
              .padding(.horizontal, 7)
              .padding(.vertical, 3)
              .background((cue.isSatisfied ? color : Color.secondary).opacity(0.1), in: Capsule())
              .help(cue.detail)
          }
        }
      }

      Label(guide.nextAction.detail, systemImage: guide.nextAction.systemImage)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .help(guide.nextAction.title)
    }
    .padding(12)
    .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(color.opacity(0.18))
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "\(guide.title). \(guide.detail). \(guide.scoreLabel). Next action: \(guide.nextAction.title). \(guide.nextAction.detail)"
    )
  }

  private var color: Color {
    switch guide.status {
    case .empty:
      return .secondary
    case .needsFocus:
      return .orange
    case .ready:
      return .green
    }
  }

  private var systemImage: String {
    switch guide.status {
    case .empty:
      return "scope"
    case .needsFocus:
      return "questionmark.circle"
    case .ready:
      return "checkmark.seal"
    }
  }
}

private struct CopyProjectVisionButton: View {
  var payload: ProjectVisionClipboardPayload
  @State private var copied = false

  var body: some View {
    Button {
      copyTextToPasteboard(payload.text)
      copied = true
      Task { @MainActor in
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        copied = false
      }
    } label: {
      Image(systemName: copied ? "checkmark" : "doc.on.doc")
        .frame(width: 18, height: 18)
    }
    .buttonStyle(.borderless)
    .disabled(payload.isEmpty)
    .help(ClipboardHelpText.projectVision)
    .accessibilityLabel(copied ? "Copied project brief" : "Copy project brief")
  }
}

struct SectionHeader: View {
  var title: String
  var systemImage: String

  init(_ title: String, systemImage: String) {
    self.title = title
    self.systemImage = systemImage
  }

  var body: some View {
    Label(title, systemImage: systemImage)
      .font(.headline)
  }
}

enum MarkdownDocumentMode: String, CaseIterable, Identifiable {
  case preview = "Preview"
  case edit = "Edit"

  var id: Self { self }

  static func initial(for text: String) -> Self {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .edit : .preview
  }
}

struct MarkdownDocumentBody: View {
  @Binding var text: String
  var mode: MarkdownDocumentMode
  var empty: String
  var editPlaceholder: String

  var body: some View {
    Group {
      switch mode {
      case .preview:
        ScrollView {
          MarkdownBlock(text, empty: empty)
            .padding(12)
        }
      case .edit:
        ZStack(alignment: .topLeading) {
          TextEditor(text: $text)
            .font(.system(.body, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(8)

          if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(editPlaceholder)
              .font(.system(.body, design: .monospaced))
              .foregroundStyle(.secondary)
              .padding(.horizontal, 13)
              .padding(.vertical, 16)
              .allowsHitTesting(false)
              .accessibilityHidden(true)
          }
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
  }
}

struct MarkdownBlock: View {
  var text: String
  var empty: String

  init(_ text: String, empty: String) {
    self.text = text
    self.empty = empty
  }

  var body: some View {
    MarkdownContent(text, empty: empty)
  }
}

struct EmptyState: View {
  var text: String

  init(_ text: String) {
    self.text = text
  }

  var body: some View {
    Text(text)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 8)
  }
}

func phaseColor(_ phase: LoopPhase) -> Color {
  switch phase {
  case .idle: return .secondary
  case .planning: return .blue
  case .developing: return .orange
  case .verifying: return .purple
  case .reviewing: return .pink
  case .auditing: return .teal
  case .paused: return .yellow
  case .failed: return .red
  case .succeeded: return .green
  case .cancelled: return .yellow
  }
}
