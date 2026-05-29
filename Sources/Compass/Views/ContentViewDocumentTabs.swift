import AppKit
import SwiftUI

struct VisionTab: View {
  @ObservedObject var project: CompassProject
  @State private var mode = MarkdownDocumentMode.preview

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        SectionHeader("Project Vision", systemImage: "scope")
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
      MarkdownDocumentBody(text: $project.vision, mode: mode, empty: "No project vision.")
    }
  }
}


struct LessonsTab: View {
  @ObservedObject var project: CompassProject

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      SectionHeader("Lessons", systemImage: "book.closed")
      ScrollView {
        MarkdownBlock(project.lessons, empty: "No lessons captured.")
          .padding(12)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
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
}


struct MarkdownDocumentBody: View {
  @Binding var text: String
  var mode: MarkdownDocumentMode
  var empty: String

  var body: some View {
    Group {
      switch mode {
      case .preview:
        ScrollView {
          MarkdownBlock(text, empty: empty)
            .padding(12)
        }
      case .edit:
        TextEditor(text: $text)
          .font(.system(.body, design: .monospaced))
          .scrollContentBackground(.hidden)
          .padding(8)
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
