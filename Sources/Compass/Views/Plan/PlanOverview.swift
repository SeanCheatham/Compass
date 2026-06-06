import SwiftUI

struct PlanTournamentBriefView: View {
  var brief: PlanTournamentBrief
  var narration: PlanTournamentBriefNarration?

  private let factColumns = [
    GridItem(.adaptive(minimum: 220), spacing: 8, alignment: .top)
  ]

  var body: some View {
    let clipboardPayload = PlanTournamentBriefClipboardPayload(brief: brief)

    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: systemImage)
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(color)
          .frame(width: 34, height: 34)
          .background(color.opacity(0.14), in: Circle())

        VStack(alignment: .leading, spacing: 6) {
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(brief.title)
              .font(.headline)

            Text(brief.primaryActionLabel)
              .font(.caption.weight(.semibold))
              .foregroundStyle(color)
              .padding(.horizontal, 8)
              .padding(.vertical, 3)
              .background(color.opacity(0.12), in: Capsule())

            if narration != nil {
              Label("On-device brief", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
          }

          Text(narration?.text ?? brief.detail)
            .font(.callout)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
        }

        Spacer(minLength: 8)

        CopyTournamentBriefButton(payload: clipboardPayload)
      }

      LazyVGrid(columns: factColumns, alignment: .leading, spacing: 8) {
        briefFact(
          title: brief.proofLabel,
          detail: brief.proofDetail,
          systemImage: "checkmark.seal",
          command: brief.proofCommand
        )

        briefFact(
          title: brief.routeLabel,
          detail: brief.routeDetail,
          systemImage: "macwindow.on.rectangle"
        )

        briefFact(
          title: brief.handoffDigest.title,
          detail: brief.handoffDigest.detail,
          systemImage: brief.handoffDigest.systemImage
        )
      }

      if !brief.chips.isEmpty {
        FlowChipRow(chips: brief.chips, color: color)
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(color.opacity(0.22))
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(brief.title). \(narration?.text ?? brief.detail)")
  }

  private func briefFact(
    title: String,
    detail: String,
    systemImage: String,
    command: String? = nil
  ) -> some View {
    HStack(alignment: .top, spacing: 7) {
      Image(systemName: systemImage)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(color)
        .frame(width: 18, height: 18)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
          .textSelection(.enabled)

        if let command {
          Text(command)
            .font(.caption.monospaced())
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }

  private var color: Color {
    switch brief.status {
    case .ready:
      return .blue
    case .paused:
      return .teal
    case .needsAttention:
      return .orange
    case .planning:
      return .purple
    case .idle:
      return .secondary
    }
  }

  private var systemImage: String {
    switch brief.status {
    case .ready:
      return "play.circle.fill"
    case .paused:
      return "pause.circle.fill"
    case .needsAttention:
      return "exclamationmark.triangle.fill"
    case .planning:
      return "map.fill"
    case .idle:
      return "tray"
    }
  }
}

struct CopyTournamentBriefButton: View {
  var payload: PlanTournamentBriefClipboardPayload
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
      Label(
        copied ? "Copied" : "Copy Brief",
        systemImage: copied ? "checkmark" : "doc.on.doc"
      )
      .lineLimit(1)
    }
    .controlSize(.small)
    .disabled(payload.isEmpty)
    .help(ClipboardHelpText.tournamentBrief)
  }
}

struct FlowChipRow: View {
  var chips: [PlanTournamentBrief.Chip]
  var color: Color

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 6) {
        ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
          Label(chip.label, systemImage: chip.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.1), in: Capsule())
        }
      }
    }
  }
}

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
          Text("Current work, candidate directions, and strategic context stay visible together.")
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
    case .candidates:
      return .orange
    case .strategicContext:
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
        metadataLabel(
          PlanVerifyCommandSummary(command: verifyCommand).title,
          systemImage: "checkmark.seal"
        )
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
  var languageProfile: RepositoryLanguageProfile
  var forgeProfile: ForgeProfile?

  var body: some View {
    let handoffPayload = PlanHandoffClipboardPayload(
      plan: item.body,
      verify: item.verify,
      languageProfile: languageProfile,
      forgeProfile: forgeProfile
    )

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

        if item.kind == .immediate {
          CopyHandoffButton(payload: handoffPayload)
        }

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

      if item.kind == .immediate {
        PlanHandoffDigestView(digest: PlanHandoffDigest(plan: item.body))

        let repairGuide = PlanHandoffRepairGuide(
          plan: item.body,
          verify: item.verify,
          languageProfile: languageProfile,
          forgeProfile: forgeProfile
        )
        if repairGuide.shouldShow {
          PlanHandoffRepairGuideView(guide: repairGuide)
        }
      }

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

struct CopyHandoffButton: View {
  var payload: PlanHandoffClipboardPayload
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
      Label(copied ? "Copied" : "Copy Work", systemImage: copied ? "checkmark" : "doc.on.doc")
        .lineLimit(1)
    }
    .controlSize(.small)
    .disabled(payload.isEmpty)
    .help(ClipboardHelpText.immediateWork)
  }
}

struct PlanHandoffRepairGuideView: View {
  var guide: PlanHandoffRepairGuide
  @State private var guideNarration: PlanHandoffRepairGuideNarration?

  var body: some View {
    let repairPayload = PlanHandoffRepairClipboardPayload(guide: guide)
    let repairNarration = matchingNarration(for: guide)

    VStack(alignment: .leading, spacing: 8) {
      Divider()
        .padding(.vertical, 2)

      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Label(guide.title, systemImage: systemImage)
          .font(.callout.weight(.semibold))
          .foregroundStyle(color)

        Text(guide.scoreLabel)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 7)
          .padding(.vertical, 2)
          .background(.quaternary.opacity(0.7), in: Capsule())

        Spacer(minLength: 8)

        CopyRepairHandoffButton(payload: repairPayload)
      }

      Text(guide.detail)
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)

      if let repairNarration {
        HStack(alignment: .top, spacing: 7) {
          Image(systemName: "sparkles")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 16)
            .padding(.top, 2)

          Text(repairNarration.text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
        }
      }

      VStack(alignment: .leading, spacing: 6) {
        ForEach(guide.steps) { step in
          HStack(alignment: .top, spacing: 7) {
            Image(systemName: step.systemImage)
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(step.isSatisfied ? color : .secondary)
              .frame(width: 16)
              .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
              HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(step.title)
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.primary)

                if !step.isRequired {
                  Text("optional")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary.opacity(0.55), in: Capsule())
                }
              }

              Text(step.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      }

      if let suggestedVerifyCommand = guide.suggestedVerifyCommand {
        Label("Suggested verify: \(suggestedVerifyCommand)", systemImage: "terminal")
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
      }

      if let planTemplate = guide.planTemplate {
        VStack(alignment: .leading, spacing: 4) {
          Text("Plan shape")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

          Text(planTemplate)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
        }
      }
    }
    .padding(.top, 2)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "\(guide.title). \(repairNarration?.text ?? guide.detail). \(guide.scoreLabel)."
    )
    .task(id: guide.narrationIdentifier) {
      guideNarration = nil
      guideNarration = await PlanHandoffRepairGuideNarrator.narrate(guide: guide)
    }
  }

  private var color: Color {
    switch guide.status {
    case .missingHandoff:
      return .secondary
    case .needsRepair:
      return .orange
    case .ready:
      return .green
    }
  }

  private var systemImage: String {
    switch guide.status {
    case .missingHandoff:
      return "square.and.pencil"
    case .needsRepair:
      return "wrench.and.screwdriver"
    case .ready:
      return "checkmark.seal"
    }
  }

  private func matchingNarration(
    for guide: PlanHandoffRepairGuide
  ) -> PlanHandoffRepairGuideNarration? {
    guard guideNarration?.guideIdentifier == guide.narrationIdentifier else {
      return nil
    }
    return guideNarration
  }
}

struct CopyRepairHandoffButton: View {
  var payload: PlanHandoffRepairClipboardPayload
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
      Label(
        copied ? "Copied" : "Copy Repair",
        systemImage: copied ? "checkmark" : "wrench.and.screwdriver"
      )
      .lineLimit(1)
    }
    .controlSize(.small)
    .disabled(payload.isEmpty)
    .help(ClipboardHelpText.planRepair)
  }
}

struct PlanHandoffDigestView: View {
  var digest: PlanHandoffDigest

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Divider()
        .padding(.vertical, 2)

      Label(digest.title, systemImage: digest.systemImage)
        .font(.callout.weight(.semibold))
        .foregroundStyle(color)

      Text(digest.detail)
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)

      if let outcome = digest.outcome {
        digestLine(title: "Outcome", text: outcome, systemImage: "target")
      }

      if let whyItMatters = digest.whyItMatters {
        digestLine(
          title: "Why", text: whyItMatters, systemImage: "person.crop.circle.badge.questionmark")
      }

      if !digest.acceptanceChecks.isEmpty {
        VStack(alignment: .leading, spacing: 5) {
          Text("Acceptance checks")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
          ForEach(Array(digest.acceptanceChecks.enumerated()), id: \.offset) { _, check in
            Label(check, systemImage: "checkmark.circle")
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
              .textSelection(.enabled)
          }
        }
      }

      if !digest.missingPieces.isEmpty {
        Text("Missing: \(digest.missingPieces.map(\.label).joined(separator: ", "))")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
      }
    }
    .padding(.top, 2)
  }

  private func digestLine(title: String, text: String, systemImage: String) -> some View {
    Label {
      Text("\(title): \(text)")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
    } icon: {
      Image(systemName: systemImage)
        .foregroundStyle(color)
    }
  }

  private var color: Color {
    switch digest.status {
    case .ready:
      return .green
    case .needsDetail:
      return .orange
    case .missingPlan:
      return .secondary
    }
  }
}

struct VerifyCommandView: View {
  var command: String

  var body: some View {
    let summary = PlanVerifyCommandSummary(command: command)

    VStack(alignment: .leading, spacing: 5) {
      Label(summary.title, systemImage: summary.systemImage)
        .font(.callout.weight(.semibold))
        .foregroundStyle(.secondary)

      Text(summary.detail)
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)

      if let command = summary.command {
        Text(command)
          .font(.callout.monospaced())
          .foregroundStyle(.tertiary)
          .textSelection(.enabled)
      }
    }
    .padding(.top, 2)
  }
}
