import SwiftUI

extension ProductSignalTone {
  var compassColor: Color {
    switch self {
    case .strong:
      return .green
    case .progressing:
      return .blue
    case .missing:
      return .orange
    case .blocked:
      return .red
    case .risk:
      return .yellow
    case .neutral:
      return .secondary
    }
  }

  var accessibilityPhrase: String {
    switch self {
    case .strong:
      return "strong signal"
    case .progressing:
      return "progressing signal"
    case .missing:
      return "missing proof"
    case .blocked:
      return "blocked proof"
    case .risk:
      return "risk signal"
    case .neutral:
      return "neutral signal"
    }
  }
}

extension ProductIconRole {
  var systemImage: String {
    switch self {
    case .pain:
      return "person.crop.circle.badge.exclamationmark"
    case .contender:
      return "rectangle.3.group"
    case .alternative:
      return "arrow.left.arrow.right"
    case .evidence:
      return "chart.bar.doc.horizontal"
    case .payIntent:
      return "dollarsign.circle"
    case .useProof:
      return "checkmark.seal"
    case .revision:
      return "wand.and.stars"
    case .advance:
      return "arrow.turn.down.right"
    case .eliminate:
      return "xmark.circle"
    case .audit:
      return "doc.text.magnifyingglass"
    case .workflow:
      return "point.3.connected.trianglepath.dotted"
    case .switching:
      return "arrow.triangle.2.circlepath"
    case .winner:
      return "trophy"
    }
  }
}

extension EvidenceStrength {
  var productSignalTone: ProductSignalTone {
    ProductPresentationLanguage.tone(for: self)
  }
}

extension EvidenceDimension {
  var productIconRole: ProductIconRole {
    ProductPresentationLanguage.iconRole(for: self)
  }
}
