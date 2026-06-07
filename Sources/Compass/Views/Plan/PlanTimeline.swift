import SwiftUI

struct PlanTimelineHeader: View {
  var items: [PlanTimelineItem]
  @Binding var selectedItemID: String
  var completedCount: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 3) {
          SectionHeader("Immediate Work", systemImage: "map")
          Text("Completed work fades into the rail; upcoming tournament intent stays prominent.")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Label("\(completedCount) completed", systemImage: "checkmark.circle")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 9)
          .padding(.vertical, 5)
          .background(.quaternary.opacity(0.55), in: Capsule())
      }

      ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(alignment: .center, spacing: 0) {
            ForEach(items) { item in
              PlanTimelineTickButton(
                item: item,
                isSelected: item.id == selectedItemID
              ) {
                selectedItemID = item.id
              }
              .id(item.id)
            }
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 8)
          .background(alignment: .top) {
            Capsule()
              .fill(.secondary.opacity(0.16))
              .frame(height: 3)
              .padding(.horizontal, 16)
              .padding(.top, 26)
          }
        }
        .onChange(of: selectedItemID) {
          withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(selectedItemID, anchor: .center)
          }
        }
        .onAppear {
          proxy.scrollTo(selectedItemID, anchor: .center)
        }
      }
    }
    .padding(14)
    .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: 8))
  }
}

struct PlanTimelineTickButton: View {
  var item: PlanTimelineItem
  var isSelected: Bool
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 7) {
        ZStack {
          Circle()
            .fill(item.kind.color.opacity(isSelected ? 0.18 : item.kind.backgroundOpacity))
            .frame(width: item.kind.hitSize, height: item.kind.hitSize)

          Image(systemName: item.kind.systemImage)
            .font(.system(size: item.kind.iconSize, weight: .semibold))
            .foregroundStyle(item.kind.color.opacity(isSelected ? 1 : item.kind.idleOpacity))
            .frame(width: item.kind.hitSize, height: item.kind.hitSize)
        }
        .frame(height: 36)
        .overlay {
          Circle()
            .stroke(item.kind.color.opacity(isSelected ? 0.95 : 0), lineWidth: 2)
        }

        if item.kind.showsLabel {
          Text(item.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(isSelected ? .primary : .secondary)
            .lineLimit(1)
            .frame(width: item.kind.width)
        } else {
          Text(" ")
            .font(.caption)
            .hidden()
        }
      }
      .frame(width: item.kind.width, height: 54, alignment: .top)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(item.helpText)
    .accessibilityLabel(item.helpText)
  }
}

struct PlanTimelineItem: Identifiable, Equatable {
  static let immediateID = PlanWorkflowOverview.TimelineDestination.immediate.itemID
  private static let candidatesID = PlanWorkflowOverview.TimelineDestination.candidates.itemID
  private static let strategicContextID =
    PlanWorkflowOverview.TimelineDestination.strategicContext.itemID

  var id: String
  var kind: Kind
  var title: String
  var body: String
  var verify: String?
  var verifyTimeoutLabel: String?
  var metadata: String?
  var emptyMessage: String

  var helpText: String {
    switch kind {
    case .history:
      return "\(title): \(body)"
    default:
      return title
    }
  }

  static func items(for state: PlanState) -> [PlanTimelineItem] {
    let history = state.completed.enumerated().map { index, item in
      PlanTimelineItem(
        id: "plan-history-\(index)",
        kind: .history,
        title: "Iteration \(index + 1)",
        body: item,
        metadata: "#\(index + 1)",
        emptyMessage: "No detail recorded for this iteration."
      )
    }

    let immediate = PlanTimelineItem(
      id: immediateID,
      kind: .immediate,
      title: "Immediate",
      body: state.immediate?.plan ?? "",
      verify: state.immediate?.verify,
      verifyTimeoutLabel: state.immediate.map {
        PlanVerifyMetadata(timeoutMs: $0.verifyTimeoutMs).label
      },
      metadata: state.immediate?.estimatedDifficulty?.rawValue.capitalized,
      emptyMessage: "No immediate plan."
    )

    let candidates = PlanTimelineItem(
      id: candidatesID,
      kind: .candidates,
      title: "Candidates",
      body: state.candidatesMarkdown,
      emptyMessage: "No candidate directions."
    )

    let strategicContext = PlanTimelineItem(
      id: strategicContextID,
      kind: .strategicContext,
      title: "Strategy",
      body: state.strategicContextMarkdown,
      emptyMessage: "No strategic context."
    )

    return history + [immediate, candidates, strategicContext]
  }

  enum Kind: Equatable {
    case history
    case immediate
    case candidates
    case strategicContext

    var label: String {
      switch self {
      case .history: return "History"
      case .immediate: return "Next"
      case .candidates: return "Candidates"
      case .strategicContext: return "Context"
      }
    }

    var systemImage: String {
      switch self {
      case .history: return "circle.fill"
      case .immediate: return "target"
      case .candidates: return "point.3.connected.trianglepath.dotted"
      case .strategicContext: return "mountain.2.fill"
      }
    }

    var color: Color {
      switch self {
      case .history: return .secondary
      case .immediate: return .blue
      case .candidates: return .orange
      case .strategicContext: return .purple
      }
    }

    var width: CGFloat {
      switch self {
      case .history: return 18
      case .immediate, .candidates, .strategicContext: return 112
      }
    }

    var hitSize: CGFloat {
      switch self {
      case .history: return 14
      case .immediate, .candidates, .strategicContext: return 34
      }
    }

    var iconSize: CGFloat {
      switch self {
      case .history: return 5
      case .immediate, .candidates, .strategicContext: return 16
      }
    }

    var backgroundOpacity: Double {
      switch self {
      case .history: return 0.05
      case .immediate, .candidates, .strategicContext: return 0.13
      }
    }

    var idleOpacity: Double {
      switch self {
      case .history: return 0.36
      case .immediate, .candidates, .strategicContext: return 0.85
      }
    }

    var showsLabel: Bool {
      self != .history
    }
  }
}
