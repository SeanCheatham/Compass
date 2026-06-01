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

  var body: some View {
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
  }

  private func hiddenSummaryText(_ statusSummary: String) -> String {
    let matchingText = display.filter == .all ? "" : " matching"
    return
      "\(display.hiddenCount) older\(matchingText) \(PlanSessionHistoryDisplay.runWord(for: display.hiddenCount)) hidden: \(statusSummary)"
  }
}

struct PlanSessionHistoryCard: View {
  var item: PlanSessionHistoryItem
  var reliabilityCue: PlanReliabilityFeedback.RunCue?
  var repoURL: URL

  var body: some View {
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
