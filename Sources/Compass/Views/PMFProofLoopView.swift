import SwiftUI

struct PMFProofLoopView: View {
  var project: CompassProject
  var ledger: PMFProofLedger
  @State private var copied = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Label("PMF Proof Loop", systemImage: ProductIconRole.evidence.systemImage)
          .font(.headline)
        Spacer()
        Button {
          copyTextToPasteboard(proofBriefText)
          copied = true
          Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            copied = false
          }
        } label: {
          Label(copied ? "Copied" : "Copy PMF Proof Brief", systemImage: copied ? "checkmark" : "doc.on.doc")
        }
        .buttonStyle(.bordered)
        .disabled(ledger.isEmpty)
        .help("Copy PMF Proof Brief")
      }

      if ledger.isEmpty {
        ContentUnavailableView(
          "No PMF Proof Loop State",
          systemImage: ProductIconRole.evidence.systemImage,
          description: Text("Enter a user pain or run Discover to seed proof-loop state.")
        )
        .frame(maxWidth: .infinity, minHeight: 220)
      } else {
        hypothesisStrip
        ViewThatFits(in: .horizontal) {
          HStack(alignment: .top, spacing: 12) {
            riskiestUnknownPanel
              .frame(minWidth: 260, maxWidth: .infinity, alignment: .topLeading)
            nextActionPanel
              .frame(minWidth: 260, maxWidth: .infinity, alignment: .topLeading)
          }
          VStack(alignment: .leading, spacing: 12) {
            riskiestUnknownPanel
            nextActionPanel
          }
        }
        evidenceLedger
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
    .accessibilityLabel("PMF Proof Loop")
  }

  private var hypothesisStrip: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("Hypothesis", systemImage: ProductIconRole.pain.systemImage)
        .font(.callout.weight(.semibold))
      LazyVGrid(
        columns: [
          GridItem(.adaptive(minimum: 190), alignment: .topLeading)
        ],
        alignment: .leading,
        spacing: 8
      ) {
        PMFProofFact(label: "Pain", value: ledger.hypothesis.pain)
        PMFProofFact(label: "Target user", value: ledger.hypothesis.targetUser)
        PMFProofFact(label: "Buyer", value: ledger.hypothesis.buyer)
        PMFProofFact(label: "Current alternative", value: ledger.hypothesis.currentAlternative)
        PMFProofFact(label: "Promised outcome", value: ledger.hypothesis.promisedOutcome)
        PMFProofFact(label: "Value claim", value: ledger.hypothesis.pricingOrValueClaim)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
  }

  private var riskiestUnknownPanel: some View {
    PMFProofPanel(
      title: "Riskiest Unknown",
      systemImage: ProductIconRole.audit.systemImage
    ) {
      if let unknown = ledger.riskiestUnknown {
        VStack(alignment: .leading, spacing: 8) {
          HStack(alignment: .firstTextBaseline) {
            Text(unknown.title)
              .font(.callout.weight(.semibold))
              .fixedSize(horizontal: false, vertical: true)
            Spacer()
            PMFProofPill(text: unknown.severity.rawValue)
          }
          PMFProofFact(label: "Current signal", value: unknown.currentSignal)
          PMFProofFact(label: "Proof debt", value: "\(unknown.proofDebt)")
          PMFProofFact(label: "Kind", value: unknown.kind.rawValue)
          PMFProofReferencesView(references: unknown.sourceReferences)
        }
      } else {
        PMFProofEmptyLine("No unresolved proof debt.")
      }
    }
  }

  private var nextActionPanel: some View {
    PMFProofPanel(
      title: "Cheapest Next Proof",
      systemImage: ProductIconRole.advance.systemImage
    ) {
      if let action = ledger.nextAction {
        VStack(alignment: .leading, spacing: 8) {
          HStack(alignment: .firstTextBaseline) {
            Text(action.title)
              .font(.callout.weight(.semibold))
              .fixedSize(horizontal: false, vertical: true)
            Spacer()
            PMFProofPill(text: "\(action.expectedTokenCostClass.rawValue) tokens")
          }
          PMFProofFact(label: "Action", value: action.kind.rawValue)
          PMFProofFact(label: "Rationale", value: action.rationale)
          PMFProofFact(
            label: "Context",
            value: action.requiredContext.map(\.rawValue).joined(separator: ", ")
          )
          PMFProofReferencesView(references: action.legacyReferences)
        }
      } else {
        PMFProofEmptyLine("No proof action queued.")
      }
    }
  }

  private var evidenceLedger: some View {
    PMFProofPanel(
      title: "Proof Ledger",
      systemImage: ProductIconRole.evidence.systemImage
    ) {
      if ledger.evidence.isEmpty {
        PMFProofEmptyLine("No proof evidence recorded yet.")
      } else {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(ledger.evidence.prefix(5)) { evidence in
            HStack(alignment: .top, spacing: 9) {
              Image(systemName: icon(for: evidence.kind))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color(for: evidence.confidence))
                .frame(width: 18, height: 18)
              VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                  Text(evidence.kind.rawValue)
                    .font(.caption.weight(.semibold))
                  Spacer()
                  Text(evidence.confidence.rawValue)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
                Text(evidence.summary)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .fixedSize(horizontal: false, vertical: true)
                PMFProofReferencesView(references: evidence.sourceReferences)
              }
            }
            .padding(9)
            .background(Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
          }
        }
      }
    }
  }

  private var proofBriefText: String {
    var lines = [
      "PMF Proof Brief",
      "",
      "Project: \(project.displayName)",
      ledger.promptDigest,
    ]
    if let tokenPosture = ledger.tokenPosture {
      lines += [
        "",
        "Token posture: \(tokenPosture.summary)",
        "Expected cost: \(tokenPosture.expectedCostClass.rawValue)",
        "Context budget: \(tokenPosture.contextBudgetHint)",
      ]
    }
    return StringUtils.boundedText(lines.joined(separator: "\n"), limit: 2_800)
  }

  private func icon(for kind: PMFProofEvidenceKind) -> String {
    switch kind {
    case .planEvaluation:
      return ProductIconRole.evidence.systemImage
    case .scenarioRun:
      return ProductIconRole.workflow.systemImage
    case .implementationUse:
      return ProductIconRole.useProof.systemImage
    case .currentAlternative:
      return ProductIconRole.alternative.systemImage
    case .payIntent:
      return ProductIconRole.payIntent.systemImage
    case .technicalProof:
      return ProductIconRole.workflow.systemImage
    case .decision:
      return ProductIconRole.advance.systemImage
    }
  }

  private func color(for confidence: PMFProofConfidence) -> Color {
    switch confidence {
    case .high:
      return ProductSignalTone.strong.compassColor
    case .medium:
      return ProductSignalTone.progressing.compassColor
    case .low:
      return ProductSignalTone.risk.compassColor
    }
  }
}

private struct PMFProofPanel<Content: View>: View {
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
    VStack(alignment: .leading, spacing: 10) {
      Label(title, systemImage: systemImage)
        .font(.callout.weight(.semibold))
      content
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
  }
}

private struct PMFProofFact: View {
  var label: String
  var value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(label)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
      Text(value.isEmpty ? "none" : value)
        .font(.caption)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct PMFProofPill: View {
  var text: String

  var body: some View {
    Text(text)
      .font(.caption2.weight(.semibold))
      .foregroundStyle(.secondary)
      .lineLimit(1)
      .padding(.horizontal, 7)
      .padding(.vertical, 3)
      .background(.quaternary.opacity(0.55), in: Capsule())
  }
}

private struct PMFProofReferencesView: View {
  var references: [PMFProofSourceReference]

  var body: some View {
    if !references.isEmpty {
      Text(references.prefix(4).map { "\($0.kind.rawValue): \($0.value)" }.joined(separator: " · "))
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .lineLimit(2)
        .textSelection(.enabled)
    }
  }
}

private struct PMFProofEmptyLine: View {
  var text: String

  init(_ text: String) {
    self.text = text
  }

  var body: some View {
    Text(text)
      .font(.caption)
      .foregroundStyle(.secondary)
  }
}
