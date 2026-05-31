import SwiftUI

struct PlanWorkflowOverviewView: View {
  var overview: PlanWorkflowOverview
  var selectedKind: PlanWorkflowOverview.Kind?
  var onSelect: (PlanWorkflowOverview.Kind) -> Void

  private let columns = [
    GridItem(.adaptive(minimum: 280), spacing: 12, alignment: .top)
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 3) {
          SectionHeader("Workflow Overview", systemImage: "rectangle.3.group")
          Text("Current work, queued direction, and the strategic arc stay visible together.")
            .font(.callout)
            .foregroundStyle(.secondary)
        }

        Spacer()

        Label("\(overview.completedCount) completed", systemImage: "checkmark.circle")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 9)
          .padding(.vertical, 5)
          .background(.quaternary.opacity(0.55), in: Capsule())
      }

      LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
        ForEach(overview.sections) { section in
          PlanWorkflowOverviewCard(
            section: section,
            isSelected: section.kind == selectedKind
          ) {
            onSelect(section.kind)
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct PlanWorkflowOverviewCard: View {
  var section: PlanWorkflowOverview.Section
  var isSelected: Bool
  var action: () -> Void

  @FocusState private var isFocused: Bool
  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      cardContent
    }
    .buttonStyle(.plain)
    .focused($isFocused)
    .onHover { isHovered = $0 }
    .help("Show \(section.title.lowercased())")
    .accessibilityLabel("\(section.label): \(section.title)")
    .accessibilityValue(section.excerpt ?? section.emptyMessage)
    .accessibilityHint("Shows this plan section in the focus panel.")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private var cardContent: some View {
    VStack(alignment: .leading, spacing: 10) {
      cardHeader

      Text(section.excerpt ?? section.emptyMessage)
        .font(.callout)
        .foregroundStyle(section.isEmpty ? .secondary : .primary)
        .lineLimit(5)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)

      PlanWorkflowMetadataRow(section: section, color: color)
    }
    .padding(12)
    .frame(maxWidth: .infinity, minHeight: 154, alignment: .topLeading)
    .contentShape(RoundedRectangle(cornerRadius: 8))
    .background(color.opacity(backgroundOpacity), in: RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(color.opacity(borderOpacity), lineWidth: isSelected ? 1.5 : 1)
    }
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(
          Color.primary.opacity(isFocused ? 0.38 : 0),
          style: StrokeStyle(lineWidth: 1, dash: [3, 2])
        )
        .padding(3)
    }
  }

  private var cardHeader: some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: section.systemImage)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(color)
        .frame(width: 24, height: 24)
        .background(color.opacity(isSelected ? 0.2 : 0.12), in: Circle())

      VStack(alignment: .leading, spacing: 2) {
        Text(section.title)
          .font(.headline)
          .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.92))
        Text(section.label)
          .font(.caption.weight(.semibold))
          .foregroundStyle(color)
      }

      Spacer(minLength: 8)

      statusIcon
    }
  }

  @ViewBuilder private var statusIcon: some View {
    ZStack {
      if isSelected {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(color)
      } else if isHovered || isFocused {
        Image(systemName: "chevron.right.circle")
          .foregroundStyle(color.opacity(0.72))
      }
    }
    .font(.system(size: 15, weight: .semibold))
    .frame(width: 18, height: 18)
  }

  private var color: Color {
    switch section.kind {
    case .immediate:
      return .blue
    case .midTerm:
      return .orange
    case .longTerm:
      return .purple
    }
  }

  private var backgroundOpacity: Double {
    if isSelected {
      return 0.15
    }

    return isHovered || isFocused ? 0.1 : 0.07
  }

  private var borderOpacity: Double {
    if isSelected {
      return 0.72
    }

    return isHovered || isFocused ? 0.38 : 0.2
  }
}

struct PlanWorkflowMetadataRow: View {
  var section: PlanWorkflowOverview.Section
  var color: Color

  var body: some View {
    HStack(spacing: 6) {
      if let verifyCommand = section.verifyCommand {
        metadataLabel(verifyCommand, systemImage: "checkmark.seal")
          .textSelection(.enabled)
      } else if section.kind == .immediate {
        metadataLabel("No verify command", systemImage: "checkmark.seal")
      }

      if let timeoutLabel = section.verifyTimeoutLabel {
        metadataLabel(timeoutLabel, systemImage: "timer")
      }

      if let difficulty = section.estimatedDifficultyLabel {
        metadataLabel(difficulty, systemImage: "gauge.with.dots.needle.bottom.50percent")
      } else if section.kind == .immediate {
        metadataLabel("No difficulty", systemImage: "gauge.with.dots.needle.bottom.50percent")
      }

      if section.kind != .immediate {
        metadataLabel("\(section.completedCount) completed", systemImage: "checkmark.circle")
      }
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .lineLimit(1)
  }

  private func metadataLabel(_ text: String, systemImage: String) -> some View {
    Label(text, systemImage: systemImage)
      .padding(.horizontal, 7)
      .padding(.vertical, 3)
      .background(color.opacity(0.1), in: Capsule())
  }
}

struct PlanReliabilityFeedbackView: View {
  var feedback: PlanReliabilityFeedback

  var body: some View {
    if !feedback.isEmpty {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .firstTextBaseline) {
          SectionHeader("Needs Attention", systemImage: "exclamationmark.triangle")

          Spacer()

          Label(
            "\(feedback.notices.count) \(feedback.notices.count == 1 ? "cue" : "cues")",
            systemImage: "waveform.path.ecg"
          )
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 9)
          .padding(.vertical, 5)
          .background(.quaternary.opacity(0.55), in: Capsule())
        }

        VStack(alignment: .leading, spacing: 8) {
          ForEach(feedback.notices) { notice in
            PlanReliabilityNoticeRow(notice: notice)
          }
        }
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(sectionColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .stroke(sectionColor.opacity(0.2))
      }
    }
  }

  private var sectionColor: Color {
    feedback.notices.first.map { reliabilityColor(for: $0.severity) } ?? .red
  }
}

struct PlanReliabilityNoticeRow: View {
  var notice: PlanReliabilityFeedback.Notice

  var body: some View {
    HStack(alignment: .top, spacing: 9) {
      Image(systemName: notice.systemImage)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(color)
        .frame(width: 20, height: 20)

      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text(notice.title)
            .font(.callout.weight(.semibold))

          Text(notice.actionLabel)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())

          if let metadata = notice.metadata {
            Text(metadata)
              .font(.caption.monospacedDigit())
              .foregroundStyle(.secondary)
          }
        }

        Text(notice.detail)
          .font(.callout)
          .foregroundStyle(.secondary)
          .lineLimit(3)
          .fixedSize(horizontal: false, vertical: true)
          .textSelection(.enabled)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var color: Color {
    reliabilityColor(for: notice.severity)
  }
}

struct PlanFocusPanel: View {
  var item: PlanTimelineItem

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Label(item.title, systemImage: item.kind.systemImage)
          .font(.headline)
          .foregroundStyle(item.kind.color)

        Text(item.kind.label)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 8)
          .padding(.vertical, 3)
          .background(.quaternary.opacity(0.7), in: Capsule())

        Spacer()

        if item.metadata != nil || item.verifyTimeoutLabel != nil {
          HStack(spacing: 6) {
            if let metadata = item.metadata {
              Text(metadata)
            }

            if let timeoutLabel = item.verifyTimeoutLabel {
              Label(timeoutLabel, systemImage: "timer")
            }
          }
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
        }
      }

      MarkdownContent(item.body, empty: item.emptyMessage)

      if let verify = item.verify {
        VerifyCommandView(command: verify)
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(item.kind.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(item.kind.color.opacity(0.22))
    }
  }
}

struct VerifyCommandView: View {
  var command: String

  var body: some View {
    Label(command, systemImage: "checkmark.seal")
      .font(.callout.monospaced())
      .foregroundStyle(.secondary)
      .textSelection(.enabled)
      .padding(.top, 2)
  }
}
