import AppKit
import SwiftUI

struct LiveTab: View {
  @ObservedObject var project: CompassProject
  @State private var liveActivitySummaryCache: [String: LiveActivitySummary] = [:]
  @State private var liveActivitySummaryInFlightKeys: Set<String> = []
  @State private var expandedLiveActivityClusterKeys: Set<String> = []
  @State private var liveActivityPlanningNow = Date()
  private static let thinkingRowID = "live-thinking-row"

  var body: some View {
    let reliabilityStatus = project.reliabilityStatus
    let liveActivityInputIdentifier = LiveActivitySummaryPlanner.inputIdentifier(
      for: project.liveLog)
    let liveActivityPlan = LiveActivitySummaryPlanner.plan(
      lines: project.liveLog,
      now: liveActivityPlanningNow
    )
    let liveActivitySummaryIdentifier = liveActivityPlan.frozenClusters
      .map(\.key)
      .joined(separator: "|")

    VStack(alignment: .leading, spacing: 10) {
      if !reliabilityStatus.isEmpty {
        ProjectReliabilityBanner(status: reliabilityStatus)
      }

      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 4) {
            ForEach(liveActivityPlan.items) { item in
              switch item {
              case .frozenCluster(let cluster):
                LiveActivityClusterRow(
                  cluster: cluster,
                  summary: liveActivitySummaryCache[cluster.key]
                    ?? LiveActivitySummaryService.deterministicSummary(for: cluster),
                  isGenerating: liveActivitySummaryInFlightKeys.contains(cluster.key),
                  isExpanded: expansionBinding(for: cluster.key)
                )
                .id(item.id)
              case .line(let line):
                LiveRow(line: line)
                  .id(item.id)
              }
            }
            if showsThinkingIndicator {
              ThinkingLiveRow(phase: project.phase)
                .id(Self.thinkingRowID)
            }
          }
          .padding(10)
        }
        .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .onChange(of: project.liveLog.count) {
          scrollToLiveEnd(proxy, liveActivityPlan: liveActivityPlan)
        }
        .onChange(of: liveActivitySummaryIdentifier) {
          scrollToLiveEnd(proxy, liveActivityPlan: liveActivityPlan)
        }
        .onChange(of: project.isRunning) {
          scrollToLiveEnd(proxy, liveActivityPlan: liveActivityPlan)
        }
        .onChange(of: showsThinkingIndicator) {
          scrollToLiveEnd(proxy, liveActivityPlan: liveActivityPlan)
        }
        .task(id: liveActivityInputIdentifier) {
          await refreshLiveActivityPlanningClock()
        }
        .task(id: liveActivitySummaryIdentifier) {
          refreshLiveActivitySummaries(for: liveActivityPlan.frozenClusters)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var showsThinkingIndicator: Bool {
    project.isRunning
      && !project.liveLog.contains {
        $0.status == .running && ($0.kind == .command || $0.kind == .fileChange)
      }
  }

  @MainActor
  private func refreshLiveActivityPlanningClock() async {
    liveActivityPlanningNow = Date()
    let delay = LiveActivitySummaryPlanner.quietGap + 0.25
    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    guard !Task.isCancelled else { return }
    liveActivityPlanningNow = Date()
  }

  @MainActor
  private func refreshLiveActivitySummaries(for clusters: [LiveActivityCluster]) {
    let cachePlan = LiveActivitySummaryCachePlanner.plan(
      clusters: clusters,
      cachedKeys: Set(liveActivitySummaryCache.keys),
      inFlightKeys: liveActivitySummaryInFlightKeys
    )

    for staleKey in cachePlan.staleCacheKeys {
      liveActivitySummaryCache.removeValue(forKey: staleKey)
    }
    liveActivitySummaryInFlightKeys.subtract(cachePlan.staleInFlightKeys)

    for cluster in cachePlan.requestedClusters {
      liveActivitySummaryInFlightKeys.insert(cluster.key)
      Task { [cluster] in
        let summary = await LiveActivitySummaryService.makeSummary(for: cluster)
        await MainActor.run {
          guard liveActivitySummaryInFlightKeys.contains(cluster.key) else { return }
          liveActivitySummaryCache[cluster.key] = summary
          liveActivitySummaryInFlightKeys.remove(cluster.key)
        }
      }
    }
  }

  private func expansionBinding(for key: String) -> Binding<Bool> {
    Binding {
      expandedLiveActivityClusterKeys.contains(key)
    } set: { isExpanded in
      if isExpanded {
        expandedLiveActivityClusterKeys.insert(key)
      } else {
        expandedLiveActivityClusterKeys.remove(key)
      }
    }
  }

  private func scrollToLiveEnd(
    _ proxy: ScrollViewProxy,
    liveActivityPlan: LiveActivitySummaryPlan
  ) {
    if showsThinkingIndicator {
      proxy.scrollTo(Self.thinkingRowID, anchor: .bottom)
    } else if let last = liveActivityPlan.items.last {
      proxy.scrollTo(last.id, anchor: .bottom)
    }
  }
}


struct LiveActivityClusterRow: View {
  var cluster: LiveActivityCluster
  var summary: LiveActivitySummary
  var isGenerating: Bool
  @Binding var isExpanded: Bool

  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      VStack(alignment: .leading, spacing: 4) {
        ForEach(cluster.lines) { line in
          LiveRow(line: line)
            .id(line.id)
        }
      }
      .padding(.top, 5)
      .padding(.leading, 10)
    } label: {
      HStack(alignment: .top, spacing: 10) {
        Text(timestamp(cluster.startDate))
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
          .frame(width: 74, alignment: .leading)

        Image(systemName: iconName)
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(iconColor)
          .frame(width: 18, height: 18)
          .padding(.top, 1)

        VStack(alignment: .leading, spacing: 4) {
          HStack(alignment: .top, spacing: 7) {
            Text(summary.text)
              .font(.callout)
              .foregroundStyle(.primary)
              .fixedSize(horizontal: false, vertical: true)
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)

            if isGenerating {
              ProgressView()
                .controlSize(.small)
                .scaleEffect(0.72)
                .padding(.top, 2)
            }
          }

          HStack(spacing: 6) {
            Text(countLabel)
            if let durationLabel {
              Text(durationLabel)
            }
          }
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.vertical, 2)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .background(.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 6))
    .overlay {
      RoundedRectangle(cornerRadius: 6)
        .stroke(.secondary.opacity(0.12))
    }
  }

  private var countLabel: String {
    let count = cluster.lines.count
    return count == 1 ? "1 event" : "\(count) events"
  }

  private var durationLabel: String? {
    guard let startDate = cluster.startDate,
      let endDate = cluster.endDate
    else {
      return nil
    }
    let seconds = max(0, endDate.timeIntervalSince(startDate))
    if seconds < 1 {
      return "\(Int((seconds * 1000).rounded()))ms"
    }
    return String(format: "%.1fs", seconds)
  }

  private var iconName: String {
    switch cluster.freezeReason {
    case .lifecycleBoundary:
      return "flag.checkered"
    case .quietGap, .elapsedSinceStart:
      return "rectangle.stack.fill"
    }
  }

  private var iconColor: Color {
    if cluster.lines.contains(where: { $0.status == .failed || $0.level == .error }) {
      return .red
    }
    if cluster.lines.contains(where: { $0.level == .warning }) {
      return .orange
    }
    return .blue
  }

  private func timestamp(_ date: Date?) -> String {
    guard let date else { return "batch" }
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter.string(from: date)
  }
}


struct ProjectReliabilityBanner: View {
  var status: ProjectReliabilityStatus

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: status.systemImage)
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(color)
        .frame(width: 22, height: 22)

      VStack(alignment: .leading, spacing: 5) {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
          Text(status.primaryCue)
            .font(.callout.weight(.semibold))

          Text(status.actionLabel)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())

          if let metadata = status.metadata {
            Text(metadata)
              .font(.caption.monospacedDigit())
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }

          Spacer(minLength: 8)

          Text(status.countLabel)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }

        Text(status.detail)
          .font(.callout)
          .foregroundStyle(.secondary)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
          .textSelection(.enabled)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(11)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(color.opacity(0.22))
    }
    .help(helpText)
  }

  private var color: Color {
    reliabilityColor(for: status.severity)
  }

  private var helpText: String {
    [
      status.primaryCue,
      status.actionLabel,
      status.metadata,
      status.detail,
    ]
    .compactMap { $0?.isEmpty == false ? $0 : nil }
    .joined(separator: " · ")
  }
}


struct LiveRow: View {
  var line: LiveLine

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Text(timestamp(line.date))
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(width: 74, alignment: .leading)

      LiveStatusIcon(line: line)
        .frame(width: 18, height: 18)
        .padding(.top, 1)

      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(line.text)
            .font(.callout.weight(titleWeight))
            .foregroundStyle(titleColor)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)

          if let duration {
            Text(duration)
              .font(.caption.monospacedDigit())
              .foregroundStyle(.secondary)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(.quaternary.opacity(0.7), in: Capsule())
          }
        }

        if let detail = line.detail, !detail.isEmpty {
          LiveDetail(line: line, detail: detail)
        }
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .background(rowBackground, in: RoundedRectangle(cornerRadius: 6))
  }

  private var titleWeight: Font.Weight {
    switch line.status {
    case .running:
      return .semibold
    default:
      return line.kind == .lifecycle ? .regular : .medium
    }
  }

  private var titleColor: Color {
    switch line.level {
    case .success:
      return .green
    case .warning:
      return .orange
    case .error:
      return .red
    case .raw:
      return .primary.opacity(0.82)
    case .info:
      return .primary
    }
  }

  private var rowBackground: Color {
    switch line.status {
    case .running:
      return .blue.opacity(0.07)
    case .failed:
      return .red.opacity(0.08)
    default:
      return .clear
    }
  }

  private var duration: String? {
    guard let completedAt = line.completedAt else { return nil }
    let seconds = completedAt.timeIntervalSince(line.date)
    if seconds < 1 {
      return "\(Int((seconds * 1000).rounded()))ms"
    }
    return String(format: "%.1fs", seconds)
  }

  private func timestamp(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter.string(from: date)
  }
}


struct ThinkingLiveRow: View {
  var phase: LoopPhase
  @State private var isAnimating = false

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Text("live")
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(width: 74, alignment: .leading)

      Image(systemName: "brain.head.profile")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(.blue)
        .scaleEffect(isAnimating ? 1.12 : 0.92)
        .opacity(isAnimating ? 1 : 0.55)
        .frame(width: 18, height: 18)
        .padding(.top, 1)

      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 3) {
          Text(title)
            .font(.callout.weight(.semibold))
          ThinkingDots()
        }
        .foregroundStyle(.primary)

        Text(detail)
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 7)
    .background(.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
    .onAppear {
      isAnimating = true
    }
    .animation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true), value: isAnimating)
  }

  private var title: String {
    switch phase {
    case .planning:
      return "Agent is planning"
    case .developing:
      return "Agent is thinking"
    case .verifying:
      return "Compass is checking"
    default:
      return "Agent is working"
    }
  }

  private var detail: String {
    switch phase {
    case .planning:
      return "Waiting for the next planning event."
    case .developing:
      return "Waiting for the next development event."
    case .verifying:
      return "Running post-checks for this project."
    default:
      return "Waiting for the next live event."
    }
  }
}


struct ThinkingDots: View {
  @State private var isAnimating = false

  var body: some View {
    HStack(spacing: 2) {
      ForEach(0..<3, id: \.self) { index in
        Circle()
          .frame(width: 3.5, height: 3.5)
          .opacity(isAnimating ? 1 : 0.28)
          .animation(
            .easeInOut(duration: 0.65)
              .repeatForever(autoreverses: true)
              .delay(Double(index) * 0.16),
            value: isAnimating
          )
      }
    }
    .padding(.top, 8)
    .onAppear {
      isAnimating = true
    }
  }
}


struct LiveStatusIcon: View {
  var line: LiveLine

  var body: some View {
    switch line.status {
    case .running:
      ProgressView()
        .controlSize(.small)
    case .completed:
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.green)
    case .failed:
      Image(systemName: "xmark.octagon.fill")
        .foregroundStyle(.red)
    case .none:
      Image(systemName: iconName)
        .foregroundStyle(iconColor)
    }
  }

  private var iconName: String {
    switch line.level {
    case .success:
      return "checkmark.circle.fill"
    case .warning:
      return "exclamationmark.triangle.fill"
    case .error:
      return "xmark.octagon.fill"
    case .info, .raw:
      switch line.kind {
      case .command:
        return "terminal"
      case .agentMessage:
        return "sparkles"
      case .fileChange:
        return "doc.badge.gearshape"
      case .lifecycle:
        return "circle"
      case .message:
        return "info.circle"
      }
    }
  }

  private var iconColor: Color {
    switch line.level {
    case .success:
      return .green
    case .warning:
      return .orange
    case .error:
      return .red
    case .raw:
      return .secondary
    case .info:
      return .blue
    }
  }
}


struct LiveDetail: View {
  var line: LiveLine
  var detail: String

  var body: some View {
    switch line.kind {
    case .command:
      Text(detail)
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        .lineLimit(nil)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 5))
    case .agentMessage:
      MarkdownContent(detail, compact: true)
        .foregroundStyle(.secondary)
    default:
      Text(detail)
        .font(.callout)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
