import AppKit
import CompassCore
import SwiftUI

struct VisionTab: View {
  @ObservedObject var project: CompassProject
  @State private var mode: MarkdownDocumentMode

  init(project: CompassProject) {
    self.project = project
    _mode = State(initialValue: MarkdownDocumentMode.initial(for: project.vision))
  }

  var body: some View {
    let guide = ProjectVisionGuide(vision: project.vision)
    let clipboardPayload = ProjectVisionClipboardPayload(guide: guide)

    VStack(alignment: .leading, spacing: 12) {
      HStack {
        SectionHeader("Project Brief", systemImage: "scope")
        Spacer()
        Picker("Vision display mode", selection: $mode) {
          ForEach(MarkdownDocumentMode.allCases) { mode in
            Text(mode.rawValue).tag(mode)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 150)
        Button {
          Task { await project.saveVision() }
        } label: {
          Label("Save", systemImage: "square.and.arrow.down")
        }
      }
      ProjectVisionGuidePanel(
        guide: guide,
        clipboardPayload: clipboardPayload
      )
      MarkdownDocumentBody(
        text: $project.vision,
        mode: mode,
        empty: "No project brief.",
        editPlaceholder: "Sketch the software goal, target users, success signals, and constraints."
      )
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
    case .grounded:
      return .blue
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
    case .grounded:
      return "scope"
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
    .accessibilityLabel(copied ? "Copied project vision" : "Copy project vision")
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
  case .paused: return .yellow
  case .failed: return .red
  case .succeeded: return .green
  case .cancelled: return .yellow
  }
}
