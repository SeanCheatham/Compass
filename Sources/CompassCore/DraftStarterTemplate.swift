import Foundation

public struct DraftStarterTemplate: Equatable, Sendable {
  public static let textLimit = 1_100

  public var title: String
  public var text: String
  public var systemImage: String
  public var isEnabled: Bool
  public var helpText: String

  public init(draft: String) {
    let normalizedDraft = DraftRefinementService.normalizeDraft(draft)
    let guide = DraftReadinessGuide(draft: normalizedDraft)

    switch guide.status {
    case .empty:
      title = "Starter"
      text = "Change: \nBecause: \nDone when: "
      systemImage = "wand.and.stars"
      isEnabled = true
      helpText = "Insert a draft scaffold with outcome, reason, and done signal fields."
    case .needsDetail:
      title = "Add Signals"
      text = Self.repairTemplate(draft: normalizedDraft, missingKinds: guide.missingSignalKinds)
      systemImage = "wand.and.stars"
      isEnabled = text != normalizedDraft
      helpText = "Append only the missing draft signals Compass needs before Plan."
    case .ready:
      title = "Ready"
      text = normalizedDraft
      systemImage = "checkmark.seal"
      isEnabled = false
      helpText = "This draft already has enough signal for Plan."
    }
  }

  private static func repairTemplate(
    draft: String,
    missingKinds: [DraftReadinessGuide.Kind]
  ) -> String {
    var lines: [String] = []

    if missingKinds.contains(.outcome) {
      lines.append("Change: \(draft)")
    } else {
      lines.append(draft)
    }

    if missingKinds.contains(.why) {
      lines.append("Because: ")
    }

    if missingKinds.contains(.success) {
      lines.append("Done when: ")
    }

    return boundedMultilineText(
      lines.joined(separator: "\n"),
      limit: Self.textLimit
    )
  }

  private static func boundedMultilineText(_ text: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard text.count > limit else { return text }
    guard limit > 3 else { return String(text.prefix(limit)) }

    return String(text.prefix(limit - 3))
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}

public extension DraftReadinessGuide {
  var missingSignalKinds: [Kind] {
    cues.filter { !$0.isSatisfied }.map(\.kind)
  }
}
