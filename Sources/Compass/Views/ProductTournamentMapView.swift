import SwiftUI

struct ProductTournamentMapView: View {
  var cockpit: ProductDecisionCockpit
  var selectedContenderID: String?
  var onSelectContender: (ContenderLane) -> Void

  private var selectedLane: ContenderLane? {
    if let selectedContenderID,
      let lane = cockpit.contenders.first(where: { $0.id == selectedContenderID })
    {
      return lane
    }
    return cockpit.contenders.first
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      if cockpit.isEmpty {
        ContentUnavailableView(
          "No Product Tournament State",
          systemImage: ProductIconRole.winner.systemImage,
          description: Text("Enter a user pain or run Discover to seed product tournament state.")
        )
        .frame(maxWidth: .infinity, minHeight: 220)
      } else {
        painHeader
        ViewThatFits(in: .horizontal) {
          horizontalMap
          verticalMap
        }
        selectedDetail
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
    )
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Product tournament map")
  }

  private var painHeader: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: ProductIconRole.pain.systemImage)
        .font(.title3.weight(.semibold))
        .foregroundStyle(ProductSignalTone.risk.compassColor)
        .frame(width: 28, height: 28)
      VStack(alignment: .leading, spacing: 5) {
        Text(cockpit.activePain?.title ?? "Product pain")
          .font(.headline)
          .lineLimit(2)
        Text(cockpit.activeTournament?.premise ?? "No tournament premise captured yet.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
        HStack(spacing: 8) {
          if let pain = cockpit.activePain {
            MapChip(text: pain.audience, role: .contender)
            MapChip(text: pain.currentWorkaround, role: .alternative)
            MapChip(text: "\(pain.unresolvedUnknownCount) unknowns", role: .evidence)
          }
          if let round = cockpit.activeRound {
            MapChip(text: round.productTitle, role: .advance)
          }
        }
      }
      Spacer(minLength: 12)
      if let tournament = cockpit.activeTournament {
        VStack(alignment: .trailing, spacing: 5) {
          Text(tournament.statusLabel)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
          Text("\(tournament.contenderCount) contenders")
            .font(.caption)
            .foregroundStyle(.secondary)
          Text("\(tournament.roundCount) rounds")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  private var horizontalMap: some View {
    VStack(alignment: .leading, spacing: 10) {
      roundRail
      VStack(alignment: .leading, spacing: 8) {
        ForEach(cockpit.contenders) { lane in
          laneRow(lane, isVertical: false)
        }
      }
    }
  }

  private var verticalMap: some View {
    VStack(alignment: .leading, spacing: 10) {
      roundRail
      ForEach(cockpit.contenders) { lane in
        laneRow(lane, isVertical: true)
      }
    }
  }

  private var roundRail: some View {
    HStack(spacing: 8) {
      railNode("Pain", role: .pain, isActive: false)
      railConnector
      railNode("Plan proof", role: .evidence, isActive: cockpit.activeRound?.kind == .productPlans)
      railConnector
      railNode(
        "Core technology",
        role: .workflow,
        isActive: cockpit.activeRound?.kind == .coreTechnology
      )
      railConnector
      railNode(
        "Product use",
        role: .useProof,
        isActive: cockpit.activeRound?.kind == .productImplementation
      )
      railConnector
      railNode("Winner", role: .winner, isActive: cockpit.contenders.contains { $0.status == .winner })
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var railConnector: some View {
    Capsule()
      .fill(Color.secondary.opacity(0.22))
      .frame(width: 26, height: 2)
  }

  private func railNode(_ title: String, role: ProductIconRole, isActive: Bool) -> some View {
    HStack(spacing: 5) {
      Image(systemName: role.systemImage)
        .font(.caption.weight(.semibold))
      Text(title)
        .font(.caption.weight(.semibold))
        .lineLimit(1)
    }
    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .background(
      isActive ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08),
      in: Capsule()
    )
  }

  private func laneRow(_ lane: ContenderLane, isVertical: Bool) -> some View {
    Button {
      onSelectContender(lane)
    } label: {
      if isVertical {
        VStack(alignment: .leading, spacing: 8) {
          laneHeader(lane)
          VStack(alignment: .leading, spacing: 6) {
            roundCell(lane, ordinal: 1)
            roundCell(lane, ordinal: 2)
            roundCell(lane, ordinal: 3)
            winnerCell(lane)
          }
        }
      } else {
        HStack(alignment: .center, spacing: 8) {
          laneHeader(lane)
            .frame(width: 230, alignment: .leading)
          roundCell(lane, ordinal: 1)
          roundCell(lane, ordinal: 2)
          roundCell(lane, ordinal: 3)
          winnerCell(lane)
        }
      }
    }
    .buttonStyle(.plain)
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      selectedContenderID == lane.id ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.07),
      in: RoundedRectangle(cornerRadius: 8)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(
          selectedContenderID == lane.id ? Color.accentColor.opacity(0.35) : Color.clear,
          lineWidth: 1
        )
    )
    .accessibilityLabel("\(lane.title), \(lane.activeRoundState.title), \(lane.proofDebt.readinessState)")
    .help(lane.promise)
  }

  private func laneHeader(_ lane: ContenderLane) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Image(systemName: ProductIconRole.contender.systemImage)
          .font(.caption.weight(.semibold))
          .foregroundStyle(ProductPresentationLanguage.tone(for: lane.proofDebt).compassColor)
        Text(lane.title)
          .font(.callout.weight(.semibold))
          .lineLimit(1)
        Spacer(minLength: 4)
      }
      Text(lane.promise)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(2)
      HStack(spacing: 6) {
        MapStatusPill(text: lane.status.label)
        MapStatusPill(text: lane.proofDebt.readinessState)
      }
    }
  }

  private func roundCell(_ lane: ContenderLane, ordinal: Int) -> some View {
    let state = inferredRoundCellState(lane, ordinal: ordinal)
    return HStack(spacing: 6) {
      Circle()
        .fill(state.tone.compassColor)
        .frame(width: 8, height: 8)
      VStack(alignment: .leading, spacing: 2) {
        Text(state.title)
          .font(.caption.weight(.semibold))
          .lineLimit(1)
        Text(state.detail)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 7)
    .frame(minWidth: 138, maxWidth: .infinity, alignment: .leading)
    .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
  }

  private func winnerCell(_ lane: ContenderLane) -> some View {
    let isWinner = lane.status == .winner
    return HStack(spacing: 6) {
      Image(systemName: ProductIconRole.winner.systemImage)
        .font(.caption.weight(.semibold))
        .foregroundStyle(isWinner ? ProductSignalTone.strong.compassColor : Color.secondary)
      Text(isWinner ? "Winner" : "Pending")
        .font(.caption.weight(.semibold))
        .lineLimit(1)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 7)
    .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
    .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
  }

  private var selectedDetail: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let lane = selectedLane {
        HStack(alignment: .firstTextBaseline) {
          Text("Why this contender is here")
            .font(.callout.weight(.semibold))
          Spacer()
          MapChip(text: "\(lane.auditReferences.count) audit refs", role: .audit)
        }
        Text(lane.tournamentPosition)
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(lane.activeRoundState.detail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
        HStack(spacing: 8) {
          MapChip(
            text: ProductPresentationLanguage.proofDebtCopy(for: lane.proofDebt).shortLabel,
            role: .evidence
          )
          MapChip(text: lane.proofDebt.nextProofTarget, role: .advance)
          if let nextMove = cockpit.nextMove,
            nextMove.targetContender == lane.title || selectedContenderID == lane.id
          {
            MapChip(text: nextMove.actionTitle, role: .useProof)
          }
        }
      } else {
        Text("Select a contender to inspect product proof.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
  }

  private func inferredRoundCellState(
    _ lane: ContenderLane,
    ordinal: Int
  ) -> ProductTournamentMapRoundCellState {
    if lane.status == .eliminated || lane.status == .archived {
      return ProductTournamentMapRoundCellState(
        title: "Stopped",
        detail: lane.status.label,
        tone: .neutral
      )
    }
    guard let activeOrdinal = cockpit.activeRound?.ordinal else {
      return ProductTournamentMapRoundCellState(title: "Pending", detail: "No active round", tone: .neutral)
    }
    if ordinal < activeOrdinal {
      return ProductTournamentMapRoundCellState(title: "Cleared", detail: "Prior proof", tone: .strong)
    }
    if ordinal == activeOrdinal {
      return ProductTournamentMapRoundCellState(
        title: lane.activeRoundState.title,
        detail: lane.proofDebt.readinessState,
        tone: ProductPresentationLanguage.tone(for: lane.proofDebt)
      )
    }
    return ProductTournamentMapRoundCellState(title: "Pending", detail: "Future proof", tone: .neutral)
  }
}

private struct ProductTournamentMapRoundCellState {
  var title: String
  var detail: String
  var tone: ProductSignalTone
}

private struct MapChip: View {
  var text: String
  var role: ProductIconRole

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: role.systemImage)
        .font(.caption2.weight(.semibold))
      Text(text)
        .font(.caption2.weight(.semibold))
        .lineLimit(1)
    }
    .foregroundStyle(.secondary)
    .padding(.horizontal, 7)
    .padding(.vertical, 4)
    .background(Color.secondary.opacity(0.08), in: Capsule())
  }
}

private struct MapStatusPill: View {
  var text: String

  var body: some View {
    Text(text)
      .font(.caption2.weight(.semibold))
      .lineLimit(1)
      .padding(.horizontal, 6)
      .padding(.vertical, 3)
      .background(Color.secondary.opacity(0.08), in: Capsule())
      .foregroundStyle(.secondary)
  }
}
