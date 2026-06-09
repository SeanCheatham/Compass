import Foundation

enum PMFProofPromptContextFormatter {
  static func promptText(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex
  ) -> String {
    promptText(
      ledger: PMFProofLedger.build(config: config, evidenceIndex: evidenceIndex),
      fallback: nil
    )
  }

  static func promptText(
    ledger: PMFProofLedger?,
    fallback: String?
  ) -> String {
    if let ledger, !ledger.isEmpty {
      return ledger.promptDigest
    }

    var lines = [
      "PMF Proof Ledger",
      "No active PMF proof ledger was provided to this phase.",
    ]
    if let fallback = bounded(fallback, limit: 700), !fallback.isEmpty {
      lines.append("Fallback proof-action source:")
      lines.append(fallback)
    }
    return StringUtils.boundedText(lines.joined(separator: "\n"), limit: 1_200)
  }

  private static func bounded(_ value: String?, limit: Int) -> String? {
    let bounded = StringUtils.boundedText(value ?? "", limit: limit)
    return bounded.isEmpty ? nil : bounded
  }
}
