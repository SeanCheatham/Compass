import AppKit
import SwiftUI

struct AssumptionsTab: View {
  @ObservedObject var project: CompassProject
  @State private var filter = AssumptionFilter.active
  @State private var guideNarration: AssumptionReviewGuideNarration?

  private var ledger: AssumptionLedger {
    AssumptionLedger(assumptions: project.assumptions)
  }

  private var guide: AssumptionReviewGuide {
    AssumptionReviewGuide(ledger: ledger)
  }

  private var visibleAssumptions: [AssumptionRecord] {
    project.assumptions
      .filter(filter.includes)
      .sorted { $0.updatedAt > $1.updatedAt }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 3) {
          SectionHeader("Assumptions", systemImage: "checklist.checked")
          Text("User-affirmed, denied, and implicit signals for the factory loop.")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Picker("Assumption filter", selection: $filter) {
          ForEach(AssumptionFilter.allCases) { option in
            Label(option.title, systemImage: option.systemImage).tag(option)
          }
        }
        .pickerStyle(.menu)
        .controlSize(.small)
      }

      AssumptionSummaryStrip(ledger: ledger)
      AssumptionReviewGuidePanel(
        guide: guide,
        narration: matchingNarration(for: guide)
      )

      if visibleAssumptions.isEmpty {
        EmptyState(filter.emptyStateText)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(visibleAssumptions) { assumption in
              AssumptionReviewRow(project: project, assumption: assumption)
            }
          }
          .padding(.vertical, 2)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .task(id: guide.narrationIdentifier) {
      let guide = guide
      guideNarration = nil
      guideNarration = await AssumptionReviewGuideNarrator.narrate(guide: guide)
    }
  }

  private func matchingNarration(
    for guide: AssumptionReviewGuide
  ) -> AssumptionReviewGuideNarration? {
    guard guideNarration?.guideIdentifier == guide.narrationIdentifier else {
      return nil
    }
    return guideNarration
  }
}

enum AssumptionFilter: String, CaseIterable, Identifiable {
  case active
  case implicit
  case affirmed
  case denied
  case all

  var id: Self { self }

  var title: String {
    switch self {
    case .active: return "Active"
    case .implicit: return "Implicit"
    case .affirmed: return "Affirmed"
    case .denied: return "Denied"
    case .all: return "All"
    }
  }

  var systemImage: String {
    switch self {
    case .active: return "line.3.horizontal.decrease.circle"
    case .implicit: return "questionmark.circle"
    case .affirmed: return "checkmark.circle"
    case .denied: return "xmark.circle"
    case .all: return "list.bullet"
    }
  }

  var emptyStateText: String {
    switch self {
    case .active: return "No active assumptions recorded."
    case .implicit: return "No implicit assumptions awaiting review."
    case .affirmed: return "No assumptions affirmed."
    case .denied: return "No assumptions denied."
    case .all: return "No assumptions recorded."
    }
  }

  func includes(_ assumption: AssumptionRecord) -> Bool {
    switch self {
    case .active:
      return assumption.status != .superseded
    case .implicit:
      return assumption.status == .implicit
    case .affirmed:
      return assumption.status == .affirmed
    case .denied:
      return assumption.status == .denied
    case .all:
      return true
    }
  }
}

struct AssumptionSummaryStrip: View {
  var ledger: AssumptionLedger

  var body: some View {
    HStack(spacing: 8) {
      summaryLabel(
        "\(ledger.implicitCount) implicit",
        systemImage: "questionmark.circle",
        color: .blue
      )
      summaryLabel(
        "\(ledger.affirmedCount) affirmed",
        systemImage: "checkmark.circle",
        color: .green
      )
      summaryLabel(
        "\(ledger.deniedCount) denied",
        systemImage: "xmark.circle",
        color: .red
      )
      Spacer()
    }
  }

  private func summaryLabel(_ text: String, systemImage: String, color: Color) -> some View {
    Label(text, systemImage: systemImage)
      .font(.caption.weight(.semibold))
      .foregroundStyle(color)
      .padding(.horizontal, 9)
      .padding(.vertical, 5)
      .background(color.opacity(0.12), in: Capsule())
  }
}

struct AssumptionReviewGuidePanel: View {
  var guide: AssumptionReviewGuide
  var narration: AssumptionReviewGuideNarration?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Label(guide.title, systemImage: iconName(for: guide.tone))
          .font(.callout.weight(.semibold))
          .foregroundStyle(color(for: guide.tone))

        Spacer(minLength: 8)

        Text(guide.promptEffect)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }

      Text(guide.detail)
        .font(.callout)
        .foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)

      if let narration {
        HStack(alignment: .top, spacing: 8) {
          Image(systemName: "text.bubble")
            .frame(width: 16)
            .foregroundStyle(.secondary)
          Text(narration.text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
      }

      VStack(alignment: .leading, spacing: 7) {
        ForEach(guide.steps) { step in
          HStack(alignment: .top, spacing: 8) {
            Image(systemName: step.systemImageName)
              .frame(width: 16)
              .foregroundStyle(color(for: step.tone))
            VStack(alignment: .leading, spacing: 2) {
              Text(step.label)
                .font(.caption.weight(.semibold))
              Text(step.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
      }

      if !guide.queue.isEmpty {
        Divider()
        VStack(alignment: .leading, spacing: 6) {
          Text("Needs Review")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
          ForEach(guide.queue) { item in
            VStack(alignment: .leading, spacing: 2) {
              Text(item.label)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
              Text(item.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }
          }
        }
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(color(for: guide.tone).opacity(0.18))
    }
  }

  private func iconName(for tone: AssumptionReviewGuide.Tone) -> String {
    switch tone {
    case .empty: return "sparkle.magnifyingglass"
    case .review: return "questionmark.circle"
    case .steady: return "checkmark.circle"
    case .correction: return "xmark.circle"
    }
  }

  private func color(for tone: AssumptionReviewGuide.Tone) -> Color {
    switch tone {
    case .empty: return .secondary
    case .review: return .blue
    case .steady: return .green
    case .correction: return .red
    }
  }
}

struct AssumptionReviewRow: View {
  @ObservedObject var project: CompassProject
  var assumption: AssumptionRecord

  @State private var comment = ""

  private var trimmedComment: String {
    comment.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Label(assumption.status.displayName, systemImage: statusSystemImage)
          .font(.caption.weight(.semibold))
          .foregroundStyle(statusColor)
          .padding(.horizontal, 8)
          .padding(.vertical, 3)
          .background(statusColor.opacity(0.12), in: Capsule())

        Text(assumption.scope.displayName)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)

        if let session = assumption.createdInSession {
          Text("#\(session)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }

        Spacer()

        Text(assumption.updatedAtDate.formatted(date: .abbreviated, time: .shortened))
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Text(assumption.text)
        .font(.callout.weight(.semibold))
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)

      if !assumption.impact.isEmpty {
        AssumptionDetailLine(title: "Impact", text: assumption.impact, systemImage: "target")
      }
      if !assumption.rationale.isEmpty {
        AssumptionDetailLine(
          title: "Rationale",
          text: assumption.rationale,
          systemImage: "text.magnifyingglass"
        )
      }
      if !assumption.invalidation.isEmpty {
        AssumptionDetailLine(
          title: "Invalidated by",
          text: assumption.invalidation,
          systemImage: "exclamationmark.triangle"
        )
      }
      if let userComment = assumption.userComment, !userComment.isEmpty {
        AssumptionDetailLine(
          title: "User comment",
          text: userComment,
          systemImage: "person.crop.circle.badge.checkmark"
        )
      }
      if !assumption.evidence.isEmpty {
        VStack(alignment: .leading, spacing: 5) {
          Label("Evidence", systemImage: "paperclip")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
          ForEach(assumption.evidence, id: \.self) { item in
            Text("- \(item)")
              .font(.caption)
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
          }
        }
      }

      HStack(alignment: .top, spacing: 8) {
        TextField("Comment", text: $comment, axis: .vertical)
          .lineLimit(1...3)
          .textFieldStyle(.roundedBorder)

        Button {
          Task {
            await project.affirmAssumption(id: assumption.id, comment: trimmedComment)
            comment = ""
          }
        } label: {
          Label("Affirm", systemImage: "checkmark.circle")
        }
        .disabled(assumption.status == .affirmed)

        Button {
          Task {
            await project.denyAssumption(id: assumption.id, comment: trimmedComment)
            comment = ""
          }
        } label: {
          Label("Deny", systemImage: "xmark.circle")
        }
        .disabled(trimmedComment.isEmpty || assumption.status == .denied)
        .help("Deny requires a comment.")

        if assumption.status != .implicit {
          Button {
            Task {
              await project.markAssumptionImplicit(id: assumption.id, comment: trimmedComment)
              comment = ""
            }
          } label: {
            Label("Implicit", systemImage: "arrow.uturn.backward.circle")
          }
        }
      }
      .controlSize(.small)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.34), in: RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(statusColor.opacity(0.18))
    }
  }

  private var statusColor: Color {
    switch assumption.status {
    case .implicit: return .blue
    case .affirmed: return .green
    case .denied: return .red
    case .superseded: return .secondary
    }
  }

  private var statusSystemImage: String {
    switch assumption.status {
    case .implicit: return "questionmark.circle"
    case .affirmed: return "checkmark.circle"
    case .denied: return "xmark.circle"
    case .superseded: return "archivebox"
    }
  }
}

struct AssumptionDetailLine: View {
  var title: String
  var text: String
  var systemImage: String

  var body: some View {
    HStack(alignment: .top, spacing: 6) {
      Label(title, systemImage: systemImage)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(width: 96, alignment: .leading)

      Text(text)
        .font(.caption)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
