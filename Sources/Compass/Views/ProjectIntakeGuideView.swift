import CompassCore
import SwiftUI

struct ProjectIntakeGuideCard: View {
  var guide: ProjectIntakeGuide
  var compact = false
  var addProject: () -> Void
  @State private var guideNarration: ProjectIntakeGuideNarration?

  var body: some View {
    let payload = ProjectIntakeClipboardPayload(guide: guide)

    VStack(alignment: .leading, spacing: compact ? 10 : 14) {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: guide.systemImageName)
          .font(.system(size: compact ? 22 : 34, weight: .regular))
          .foregroundStyle(.secondary)
          .frame(width: compact ? 26 : 42, height: compact ? 26 : 42)

        VStack(alignment: .leading, spacing: 3) {
          Text(guide.title)
            .font(compact ? .headline : .title2.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
          Text(matchingNarration?.text ?? guide.detail)
            .font(compact ? .caption : .callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

          if matchingNarration != nil {
            Label("On-device intake note", systemImage: "sparkles")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .padding(.horizontal, 7)
              .padding(.vertical, 3)
              .background(.quaternary.opacity(0.55), in: Capsule())
          }
        }

        Spacer(minLength: 8)
      }

      VStack(alignment: .leading, spacing: 7) {
        ForEach(visibleSteps) { step in
          ProjectIntakeStepRow(step: step, compact: compact)
        }
      }

      if !compact {
        Divider()
          .opacity(0.6)

        VStack(alignment: .leading, spacing: 7) {
          Text("Good fit")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
          ForEach(guide.signals) { signal in
            ProjectIntakeSignalRow(signal: signal)
          }
        }
      }

      HStack(spacing: 8) {
        Button(action: addProject) {
          Label(guide.actionLabel, systemImage: "folder.badge.plus")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(compact ? .small : .regular)

        CopyProjectIntakeButton(payload: payload, compact: compact)
      }
    }
    .padding(compact ? 12 : 16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    .task(id: guide.narrationIdentifier) {
      guideNarration = nil
      guard guide.allowsNarration else { return }
      try? await Task.sleep(nanoseconds: 700_000_000)
      guard !Task.isCancelled else { return }
      guideNarration = await ProjectIntakeGuideNarrator.narrate(guide: guide)
    }
  }

  private var visibleSteps: [ProjectIntakeGuide.Step] {
    compact ? Array(guide.steps.prefix(2)) : guide.steps
  }

  private var matchingNarration: ProjectIntakeGuideNarration? {
    guard guideNarration?.guideIdentifier == guide.narrationIdentifier else {
      return nil
    }
    return guideNarration
  }
}

private struct ProjectIntakeStepRow: View {
  var step: ProjectIntakeGuide.Step
  var compact: Bool

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: step.systemImage)
        .font(.caption.weight(step.isPrimary ? .semibold : .regular))
        .foregroundStyle(step.isPrimary ? Color.accentColor : .secondary)
        .frame(width: 16, height: 16)
        .padding(.top, 1)

      VStack(alignment: .leading, spacing: 1) {
        Text(step.title)
          .font(.caption.weight(.semibold))
        Text(step.detail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(compact ? 3 : nil)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

private struct ProjectIntakeSignalRow: View {
  var signal: ProjectIntakeGuide.Signal

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: signal.systemImage)
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(width: 16, height: 16)
        .padding(.top, 1)

      VStack(alignment: .leading, spacing: 1) {
        Text(signal.label)
          .font(.caption.weight(.semibold))
        Text(signal.detail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

private struct CopyProjectIntakeButton: View {
  var payload: ProjectIntakeClipboardPayload
  var compact: Bool
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
      Label(copied ? "Copied" : "Copy Intake", systemImage: copied ? "checkmark" : "doc.on.doc")
        .lineLimit(1)
    }
    .buttonStyle(.bordered)
    .controlSize(compact ? .small : .regular)
    .help(ClipboardHelpText.projectIntake)
  }
}
