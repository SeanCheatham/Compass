import SwiftUI

struct ProductNextMovePanel: View {
  var nextMove: NextMoveSummary?
  var latestMovement: ProofMovementSummary?
  var canRunPrimaryAction: Bool
  var isRunningPrimaryAction: Bool
  var primaryDisabledReason: String?
  var onRunPrimaryAction: () -> Void
  var onViewAudit: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Label("Next Move", systemImage: ProductIconRole.advance.systemImage)
          .font(.headline)
        Spacer()
        if let nextMove {
          Label(
            ProductPresentationLanguage.expectedDecisionLabel(
              actionKind: nextMove.actionKind,
              targetDecision: nil
            ),
            systemImage: ProductIconRole.evidence.systemImage
          )
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .lineLimit(1)
        }
      }

      if let nextMove {
        HStack(alignment: .top, spacing: 14) {
          VStack(alignment: .leading, spacing: 8) {
            Text(nextMove.actionTitle)
              .font(.title3.weight(.semibold))
              .lineLimit(2)
            Text(nextMove.why)
              .font(.callout)
              .foregroundStyle(.secondary)
              .lineLimit(3)
            HStack(spacing: 8) {
              if let targetContender = nextMove.targetContender {
                NextMoveChip(text: targetContender, role: .contender)
              }
              if let targetPersona = nextMove.targetPersona {
                NextMoveChip(text: targetPersona, role: .pain)
              }
              NextMoveChip(text: nextMove.expectedDecision, role: .advance)
            }
          }
          Spacer(minLength: 16)
          VStack(alignment: .trailing, spacing: 8) {
            Button {
              onRunPrimaryAction()
            } label: {
              Label(
                isRunningPrimaryAction ? "Running" : nextMove.actionTitle,
                systemImage: ProductIconRole.useProof.systemImage
              )
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canRunPrimaryAction || isRunningPrimaryAction)
            .help(primaryDisabledReason ?? nextMove.disabledReason ?? nextMove.why)

            Button {
              onViewAudit()
            } label: {
              Label("Audit", systemImage: ProductIconRole.audit.systemImage)
            }
            .buttonStyle(.bordered)
            .help("Show the evidence and audit context for this next move.")
          }
        }

        if let disabledReason = primaryDisabledReason ?? nextMove.disabledReason,
          !canRunPrimaryAction
        {
          Label(disabledReason, systemImage: ProductIconRole.audit.systemImage)
            .font(.caption)
            .foregroundStyle(ProductSignalTone.blocked.compassColor)
        }
      } else {
        Label("No queued product move", systemImage: "checkmark.seal")
          .font(.callout.weight(.semibold))
          .foregroundStyle(.secondary)
        Text("The tournament has no executable decision or proof action right now.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if let latestMovement {
        HStack(spacing: 10) {
          Label("Latest proof movement", systemImage: ProductIconRole.useProof.systemImage)
            .font(.caption.weight(.semibold))
          Text("\(latestMovement.beforeCount) -> \(latestMovement.afterCount)")
            .font(.caption.monospacedDigit().weight(.semibold))
          Text(latestMovement.detail)
            .font(.caption)
            .foregroundStyle(.secondary)
          Spacer()
        }
        .padding(9)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
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
    .accessibilityLabel(nextMove.map { "Next move, \($0.actionTitle)" } ?? "No queued next move")
  }
}

private struct NextMoveChip: View {
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
    .padding(.horizontal, 7)
    .padding(.vertical, 4)
    .foregroundStyle(.secondary)
    .background(Color.secondary.opacity(0.08), in: Capsule())
  }
}
