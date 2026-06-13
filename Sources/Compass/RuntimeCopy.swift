import Foundation
import CompassCore

enum RuntimeCopy {
  static func containsImplementationTerm(_ text: String) -> Bool {
    let normalized = text.lowercased()
    return normalized.contains("shared vm")
      || normalized.contains("ssh")
      || normalized.contains("ipsw")

      || normalized.range(
        of: #"\b[\w.-]+@\d{1,3}(?:\.\d{1,3}){3}\b"#,
        options: .regularExpression
      ) != nil
  }
}
