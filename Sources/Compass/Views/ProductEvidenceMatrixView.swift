import SwiftUI

struct ProductEvidenceMatrixView: View {
  var cockpit: ProductDecisionCockpit
  var selectedContenderID: String?
  var onSelectEvidence: (ContenderLane, EvidenceSignal) -> Void

  private var rows: [(lane: ContenderLane, row: EvidenceMatrixRow)] {
    cockpit.evidenceMatrix.rows.compactMap { row in
      guard let lane = cockpit.contenders.first(where: { $0.id == row.contenderID }) else {
        return nil
      }
      return (lane, row)
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      proofDebtSummary
      if cockpit.evidenceMatrix.isEmpty {
        MatrixEmptyLine(text: "No contender evidence is ready for comparison.")
      } else {
        ViewThatFits(in: .horizontal) {
          matrixGrid
          compactMatrix
        }
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .background(Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
    )
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Product evidence matrix")
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      Label("Evidence Matrix", systemImage: ProductIconRole.evidence.systemImage)
        .font(.headline)
      Spacer()
      if let latestMovement = cockpit.latestMovement {
        Label(latestMovement.detail, systemImage: "arrow.left.arrow.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
      }
    }
  }

  private var proofDebtSummary: some View {
    HStack(spacing: 8) {
      SummaryTile(
        title: "Most urgent proof",
        value: mostUrgentProof,
        tone: mostUrgentProofTone,
        role: .evidence
      )
      SummaryTile(
        title: "Decision-ready",
        value: "\(decisionReadyCount) contender(s)",
        tone: decisionReadyCount > 0 ? .strong : .neutral,
        role: .advance
      )
      SummaryTile(
        title: "Blocked evidence",
        value: "\(blockedEvidenceCount) blocked",
        tone: blockedEvidenceCount > 0 ? .blocked : .neutral,
        role: .audit
      )
      if let latestMovement = cockpit.latestMovement {
        SummaryTile(
          title: "Recent movement",
          value: "\(latestMovement.beforeCount) -> \(latestMovement.afterCount)",
          tone: latestMovement.delta < 0 ? .strong : latestMovement.delta > 0 ? .risk : .neutral,
          role: .useProof
        )
      }
    }
  }

  private var matrixGrid: some View {
    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
      GridRow {
        Text("Contender")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .frame(width: 168, alignment: .leading)
        ForEach(cockpit.evidenceMatrix.dimensions, id: \.rawValue) { dimension in
          Label(
            ProductPresentationLanguage.evidenceLabel(for: dimension),
            systemImage: ProductPresentationLanguage.iconRole(for: dimension).systemImage
          )
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.secondary)
          .frame(width: 104, alignment: .leading)
        }
      }

      ForEach(rows, id: \.lane.id) { lane, row in
        GridRow {
          Button {
            if let firstSignal = row.signals.first {
              onSelectEvidence(lane, firstSignal)
            }
          } label: {
            VStack(alignment: .leading, spacing: 3) {
              Text(lane.title)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
              Text(lane.proofDebt.readinessState)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .frame(width: 168, alignment: .leading)
          }
          .buttonStyle(.plain)

          ForEach(cockpit.evidenceMatrix.dimensions, id: \.rawValue) { dimension in
            let signal = row.signals.first { $0.dimension == dimension }
            EvidenceMatrixCell(
              signal: signal,
              isSelected: selectedContenderID == lane.id,
              action: {
                if let signal {
                  onSelectEvidence(lane, signal)
                }
              }
            )
          }
        }
      }
    }
  }

  private var compactMatrix: some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach(rows, id: \.lane.id) { lane, row in
        VStack(alignment: .leading, spacing: 8) {
          Text(lane.title)
            .font(.callout.weight(.semibold))
            .lineLimit(2)
          LazyVGrid(
            columns: [
              GridItem(.adaptive(minimum: 124, maximum: 180), spacing: 8)
            ],
            alignment: .leading,
            spacing: 8
          ) {
            ForEach(row.signals) { signal in
              EvidenceMatrixCell(
                signal: signal,
                isSelected: selectedContenderID == lane.id,
                action: { onSelectEvidence(lane, signal) }
              )
            }
          }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
      }
    }
  }

  private var mostUrgentLane: ContenderLane? {
    cockpit.contenders
      .filter { !$0.proofDebt.isClear }
      .sorted {
        if $0.proofDebt.blockingCount == $1.proofDebt.blockingCount {
          return $0.title < $1.title
        }
        return $0.proofDebt.blockingCount > $1.proofDebt.blockingCount
      }
      .first
  }

  private var mostUrgentProof: String {
    guard let lane = mostUrgentLane else { return "No urgent proof" }
    return lane.proofDebt.nextProofTarget
  }

  private var mostUrgentProofTone: ProductSignalTone {
    mostUrgentLane.map { ProductPresentationLanguage.tone(for: $0.proofDebt) } ?? .neutral
  }

  private var decisionReadyCount: Int {
    cockpit.contenders.filter(\.proofDebt.isClear).count
  }

  private var blockedEvidenceCount: Int {
    cockpit.contenders.filter {
      ProductPresentationLanguage.tone(for: $0.proofDebt) == .blocked
    }.count
  }
}

private struct SummaryTile: View {
  var title: String
  var value: String
  var tone: ProductSignalTone
  var role: ProductIconRole

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: role.systemImage)
        .font(.caption.weight(.semibold))
        .foregroundStyle(tone.compassColor)
        .frame(width: 16)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.secondary)
          .lineLimit(1)
        Text(value)
          .font(.caption.weight(.semibold))
          .lineLimit(1)
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 7)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
  }
}

private struct EvidenceMatrixCell: View {
  var signal: EvidenceSignal?
  var isSelected: Bool
  var action: () -> Void

  private var tone: ProductSignalTone {
    signal.map { ProductPresentationLanguage.tone(for: $0.strength) } ?? .neutral
  }

  var body: some View {
    Button(action: action) {
      HStack(alignment: .top, spacing: 7) {
        Circle()
          .fill(tone.compassColor)
          .frame(width: 8, height: 8)
          .padding(.top, 3)
        VStack(alignment: .leading, spacing: 3) {
          Text(signal?.countLabel ?? "n/a")
            .font(.caption.weight(.semibold))
            .lineLimit(1)
          Text(signal?.primaryPhrase ?? "No signal")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 7)
      .frame(width: 104, alignment: .topLeading)
      .frame(minHeight: 58, alignment: .topLeading)
      .background(
        isSelected ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.07),
        in: RoundedRectangle(cornerRadius: 6)
      )
    }
    .buttonStyle(.plain)
    .disabled(signal == nil)
    .help(signal?.supportingPhrase ?? "No signal recorded yet.")
    .accessibilityLabel(signal?.primaryPhrase ?? "No evidence signal")
  }
}

private struct MatrixEmptyLine: View {
  var text: String

  var body: some View {
    Text(text)
      .font(.caption)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 8)
  }
}
