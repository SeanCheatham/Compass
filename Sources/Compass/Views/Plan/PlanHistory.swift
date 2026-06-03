import SwiftUI

struct PlanSessionHistorySection: View {
  var display: PlanSessionHistoryDisplay
  @Binding var showAllRuns: Bool
  @Binding var selectedFilter: PlanSessionHistoryFilter
  var runCues: [Int: PlanReliabilityFeedback.RunCue] = [:]
  var repoURL: URL
  var hasOlderArchivedSessions = false
  var isLoadingArchivedSessions = false
  var onLoadArchivedSessions: () async -> Void = {}

  @State private var guideNarration: PlanSessionHistoryGuideNarration?

  var body: some View {
    let guide = PlanSessionHistoryGuide(display: display, runCues: runCues)

    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 3) {
          SectionHeader("Run History", systemImage: "clock.arrow.circlepath")
          Text("Recent plan runs, checks, notes, and commits.")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        Spacer()
        HStack(spacing: 8) {
          if display.unfilteredTotalCount > 0 {
            Picker("Status filter", selection: $selectedFilter) {
              ForEach(display.filterOptions) { option in
                Label(
                  "\(option.filter.title) (\(option.count))",
                  systemImage: option.filter.systemImage
                )
                .tag(option.filter)
              }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
          }

          Label(display.countSummary, systemImage: "number")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.55), in: Capsule())

          if display.shouldOfferModeToggle || hasOlderArchivedSessions {
            Button {
              if !showAllRuns {
                Task {
                  await onLoadArchivedSessions()
                  showAllRuns = true
                }
              } else {
                showAllRuns = false
              }
            } label: {
              Label(
                display.mode == .all ? "Show Recent" : "Show All",
                systemImage: display.mode == .all ? "clock.arrow.circlepath" : "list.bullet"
              )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isLoadingArchivedSessions)
          }
        }
      }

      if let hiddenStatusSummary = display.hiddenStatusSummary {
        Label(
          hiddenSummaryText(hiddenStatusSummary),
          systemImage: "archivebox"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      PlanSessionHistoryGuidePanel(
        guide: guide,
        narration: matchingNarration(for: guide)
      )

      if display.unfilteredTotalCount == 0 {
        EmptyState("No run history recorded.")
      } else if display.totalCount == 0 {
        EmptyState("No \(display.filter.emptyStateName) match this filter.")
      } else {
        VStack(alignment: .leading, spacing: 10) {
          ForEach(display.visibleItems) { item in
            PlanSessionHistoryCard(
              item: item,
              reliabilityCue: runCues[item.sessionNumber],
              repoURL: repoURL
            )
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .task(id: guide.narrationIdentifier) {
      guideNarration = nil
      guideNarration = await PlanSessionHistoryGuideNarrator.narrate(guide: guide)
    }
  }

  private func hiddenSummaryText(_ statusSummary: String) -> String {
    let matchingText = display.filter == .all ? "" : " matching"
    return
      "\(display.hiddenCount) older\(matchingText) \(PlanSessionHistoryDisplay.runWord(for: display.hiddenCount)) hidden: \(statusSummary)"
  }

  private func matchingNarration(
    for guide: PlanSessionHistoryGuide
  ) -> PlanSessionHistoryGuideNarration? {
    guard guideNarration?.guideIdentifier == guide.narrationIdentifier else {
      return nil
    }
    return guideNarration
  }
}

struct PlanSessionHistoryGuidePanel: View {
  var guide: PlanSessionHistoryGuide
  var narration: PlanSessionHistoryGuideNarration?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Label(guide.title, systemImage: guide.systemImageName)
          .font(.callout.weight(.semibold))
          .foregroundStyle(color)

        Spacer(minLength: 8)

        Text(guide.statusLabel)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .padding(.horizontal, 7)
          .padding(.vertical, 2)
          .background(.quaternary.opacity(0.65), in: Capsule())
      }

      Text(narration?.text ?? guide.detail)
        .font(.callout)
        .foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)

      PlanSessionHistoryAuditCoverageRow(coverage: guide.auditCoverage, color: color)

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 6) {
          ForEach(guide.facts) { fact in
            Label(fact.label, systemImage: fact.systemImageName)
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .padding(.horizontal, 7)
              .padding(.vertical, 3)
              .background(color.opacity(0.1), in: Capsule())
              .help(fact.detail)
          }

          if narration != nil {
            Label("On-device history note", systemImage: "sparkles")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .padding(.horizontal, 7)
              .padding(.vertical, 3)
              .background(.quaternary.opacity(0.55), in: Capsule())
          }
        }
      }
    }
    .padding(11)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(color.opacity(0.2))
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "\(guide.title). \(narration?.text ?? guide.detail). Audit coverage: \(guide.auditCoverage.label). \(guide.auditCoverage.detail)"
    )
  }

  private var color: Color {
    switch guide.tone {
    case .empty:
      return .secondary
    case .steady:
      return .green
    case .active:
      return .blue
    case .attention:
      return .orange
    }
  }
}

struct PlanSessionHistoryAuditCoverageRow: View {
  var coverage: PlanSessionHistoryGuide.AuditCoverage
  var color: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .center, spacing: 8) {
        Label(coverage.label, systemImage: "gauge.medium")
          .font(.caption.weight(.semibold))
          .foregroundStyle(color)
          .lineLimit(1)

        ProgressView(value: coverage.fraction)
          .tint(color)
          .frame(width: 110)

        Text("\(coverage.coveredCount)/\(coverage.totalCount)")
          .font(.caption2.monospacedDigit().weight(.semibold))
          .foregroundStyle(.secondary)
      }

      Text(coverage.detail)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "Audit coverage: \(coverage.label). \(coverage.detail). \(coverage.coveredCount) of \(coverage.totalCount)."
    )
  }
}

struct PlanSessionHistoryCard: View {
  var item: PlanSessionHistoryItem
  var reliabilityCue: PlanReliabilityFeedback.RunCue?
  var repoURL: URL

  var body: some View {
    let runPayload = PlanSessionHistoryClipboardPayload(
      item: item,
      reliabilityCue: reliabilityCue
    )

    VStack(alignment: .leading, spacing: 9) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text("#\(item.sessionNumber)")
          .font(.headline.monospacedDigit())

        Text(item.statusText)
          .font(.caption.weight(.semibold))
          .foregroundStyle(statusColor)
          .padding(.horizontal, 8)
          .padding(.vertical, 3)
          .background(statusColor.opacity(0.12), in: Capsule())

        if let reliabilityCue {
          Label(reliabilityCue.label, systemImage: reliabilityCue.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(reliabilityColor(for: reliabilityCue.severity))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(reliabilityColor(for: reliabilityCue.severity).opacity(0.12), in: Capsule())
            .help(reliabilityCue.detail)
        }

        Spacer()

        CopyHistoryRunButton(payload: runPayload)

        Text(dateString(item.startedAt))
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      HistoryHandoffSummary(item: item)

      if let verifyCommand = item.verifyCommand {
        HistoryVerifySummary(command: verifyCommand)
      } else {
        Label("No verify command recorded.", systemImage: "checkmark.seal")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if item.runtimeRouteDescriptor.isSnapshotAvailable {
        RuntimeRouteBadge(descriptor: item.runtimeRouteDescriptor)
      }

      if !item.auditArtifacts.isEmpty {
        LabeledHistoryBlock(title: "Audit Artifacts", systemImage: "archivebox") {
          VStack(alignment: .leading, spacing: 7) {
            ForEach(item.auditArtifacts) { artifact in
              VStack(alignment: .leading, spacing: 2) {
                Label(artifact.label, systemImage: artifact.systemImageName)
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.secondary)
                  .lineLimit(1)

                Text(artifact.detail)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .fixedSize(horizontal: false, vertical: true)
                  .textSelection(.enabled)
              }
            }
          }
        }
      }

      if let feedback = item.feedback {
        LabeledHistoryBlock(title: "Feedback", systemImage: "text.bubble") {
          MarkdownContent(feedback, compact: true)
            .foregroundStyle(.secondary)
        }
      }

      if !item.notes.isEmpty {
        LabeledHistoryBlock(title: "Notes", systemImage: "note.text") {
          VStack(alignment: .leading, spacing: 6) {
            ForEach(item.notes, id: \.self) { note in
              MarkdownContent(note, compact: true)
                .foregroundStyle(.secondary)
            }
          }
        }
      }

      if !item.commits.isEmpty {
        LabeledHistoryBlock(title: "Commits", systemImage: "arrow.triangle.branch") {
          VStack(alignment: .leading, spacing: 5) {
            ForEach(item.commits) { commit in
              Label("\(commit.short) \(commit.subject)", systemImage: "arrow.triangle.branch")
                .font(.caption)
                .textSelection(.enabled)
            }
          }
        }
      }

      if item.canExplore {
        CommitTourRow(item: item, repoURL: repoURL)
        HStack(spacing: 8) {
          ExplainChangesButton(item: item, repoURL: repoURL)
          PerCommitNarrativesButton(item: item, repoURL: repoURL)
          ExploreFilesButton(item: item, repoURL: repoURL)
          ArchitectureGraphButton(item: item, repoURL: repoURL)
          QnAButton(item: item, repoURL: repoURL)
        }
      }

      if let failedVerify = item.failedVerify {
        DisclosureGroup("Verify failed (\(failedVerify.exitCodeText))") {
          VStack(alignment: .leading, spacing: 6) {
            Text(failedVerify.command)
              .font(.caption.monospaced())
              .foregroundStyle(.secondary)
              .textSelection(.enabled)

            Text(failedVerify.tail)
              .font(.caption.monospaced())
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(8)
              .background(.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 6))
          }
          .padding(.top, 4)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.red)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.38), in: RoundedRectangle(cornerRadius: 8))
  }

  private var statusColor: Color {
    switch item.status {
    case .planning:
      return .blue
    case .awaitingApproval:
      return .purple
    case .developing:
      return .orange
    case .succeeded:
      return .green
    case .failed, .rejectedByPlan:
      return .red
    case .cancelled, .skipped:
      return .secondary
    }
  }

  private func dateString(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .shortened)
  }
}

struct CopyHistoryRunButton: View {
  var payload: PlanSessionHistoryClipboardPayload
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
        copied ? "Copied" : "Copy Run",
        systemImage: copied ? "checkmark" : "doc.on.doc"
      )
      .lineLimit(1)
    }
    .controlSize(.small)
    .disabled(payload.isEmpty)
    .help(ClipboardHelpText.runHistory)
  }
}

/// Shared explore-button wrapper for buttons that guard on `condition`,
/// show a bordered small button, and attach a popover.

struct RuntimeRouteBadge: View {
  var descriptor: PlanSessionHistoryItem.RuntimeRouteDescriptor

  var body: some View {
    Label(descriptor.badgeText, systemImage: descriptor.systemImage)
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)
      .lineLimit(2)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(.quaternary.opacity(0.5), in: Capsule())
      .help(descriptor.helpText)
  }
}

struct HistoryHandoffSummary: View {
  var item: PlanSessionHistoryItem

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if item.handoffDigest.status == .missingPlan {
        Text("No plan recorded.")
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      } else {
        Label(item.handoffDigest.title, systemImage: item.handoffDigest.systemImage)
          .font(.caption.weight(.semibold))
          .foregroundStyle(color)

        Text(primarySummary)
          .font(.callout)
          .foregroundStyle(.primary)
          .fixedSize(horizontal: false, vertical: true)
          .textSelection(.enabled)

        if !item.handoffDigest.acceptanceChecks.isEmpty {
          VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(item.handoffDigest.acceptanceChecks.enumerated()), id: \.offset) {
              _, check in
              Label(check, systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            }
          }
        } else if !item.handoffDigest.missingPieces.isEmpty {
          Text(
            "Missing handoff detail: \(item.handoffDigest.missingPieces.map(\.label).joined(separator: ", "))"
          )
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
        }
      }
    }
  }

  private var primarySummary: String {
    item.handoffDigest.outcome
      ?? item.planExcerpt
      ?? item.handoffDigest.detail
  }

  private var color: Color {
    switch item.handoffDigest.status {
    case .ready:
      return .green
    case .needsDetail:
      return .orange
    case .missingPlan:
      return .secondary
    }
  }
}

struct HistoryVerifySummary: View {
  var command: String

  var body: some View {
    let summary = PlanVerifyCommandSummary(command: command)

    VStack(alignment: .leading, spacing: 4) {
      Label(summary.title, systemImage: summary.systemImage)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)

      Text(summary.detail)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)

      if let command = summary.command {
        Text(command)
          .font(.caption.monospaced())
          .foregroundStyle(.tertiary)
          .lineLimit(1)
          .truncationMode(.middle)
          .textSelection(.enabled)
      }
    }
  }
}

struct LabeledHistoryBlock<Content: View>: View {
  var title: String
  var systemImage: String
  var content: Content

  init(
    title: String,
    systemImage: String,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.systemImage = systemImage
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Label(title, systemImage: systemImage)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)

      content
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
