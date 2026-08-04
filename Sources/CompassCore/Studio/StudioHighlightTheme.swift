import AppKit
import Foundation

/// Capture-name → color map for Studio syntax highlighting. Hand-rolled so
/// the spectator view tracks system appearance without shipping Highlight.js themes.
public struct StudioHighlightTheme: Equatable, Sendable {
  public enum Appearance: String, Sendable {
    case light
    case dark
  }

  public let appearance: Appearance

  public init(appearance: Appearance) {
    self.appearance = appearance
  }

  public static let light = StudioHighlightTheme(appearance: .light)
  public static let dark = StudioHighlightTheme(appearance: .dark)

  /// Resolve a tree-sitter / regex capture name to a color. More-specific
  /// names (`keyword.function`) fall back to the root (`keyword`).
  public func color(forCapture name: String) -> NSColor {
    let key = Self.canonicalKey(for: name)
    switch appearance {
    case .light: return Self.lightPalette[key] ?? Self.lightDefault
    case .dark: return Self.darkPalette[key] ?? Self.darkDefault
    }
  }

  public var defaultForeground: NSColor {
    appearance == .light ? Self.lightDefault : Self.darkDefault
  }

  private static func canonicalKey(for name: String) -> String {
    let parts = name.split(separator: ".")
    guard let first = parts.first.map(String.init) else { return name }
    switch first {
    case "keyword", "string", "comment", "number", "type", "function",
      "constant", "property", "variable", "operator", "punctuation",
      "attribute", "tag", "label", "constructor", "boolean", "character":
      return first
    default:
      return first
    }
  }

  private static let lightDefault = NSColor.labelColor
  private static let darkDefault = NSColor.labelColor

  private static let lightPalette: [String: NSColor] = [
    "keyword": NSColor(calibratedRed: 0.61, green: 0.14, blue: 0.57, alpha: 1),
    "string": NSColor(calibratedRed: 0.77, green: 0.10, blue: 0.09, alpha: 1),
    "comment": NSColor(calibratedRed: 0.42, green: 0.48, blue: 0.54, alpha: 1),
    "number": NSColor(calibratedRed: 0.17, green: 0.00, blue: 0.83, alpha: 1),
    "type": NSColor(calibratedRed: 0.24, green: 0.40, blue: 0.65, alpha: 1),
    "function": NSColor(calibratedRed: 0.24, green: 0.37, blue: 0.65, alpha: 1),
    "constant": NSColor(calibratedRed: 0.55, green: 0.35, blue: 0.15, alpha: 1),
    "property": NSColor(calibratedRed: 0.30, green: 0.35, blue: 0.55, alpha: 1),
    "variable": NSColor.labelColor,
    "operator": NSColor(calibratedRed: 0.61, green: 0.14, blue: 0.57, alpha: 1),
    "punctuation": NSColor.secondaryLabelColor,
    "attribute": NSColor(calibratedRed: 0.55, green: 0.35, blue: 0.15, alpha: 1),
    "constructor": NSColor(calibratedRed: 0.24, green: 0.40, blue: 0.65, alpha: 1),
    "boolean": NSColor(calibratedRed: 0.61, green: 0.14, blue: 0.57, alpha: 1),
    "character": NSColor(calibratedRed: 0.77, green: 0.10, blue: 0.09, alpha: 1),
  ]

  private static let darkPalette: [String: NSColor] = [
    "keyword": NSColor(calibratedRed: 0.98, green: 0.45, blue: 0.71, alpha: 1),
    "string": NSColor(calibratedRed: 0.98, green: 0.57, blue: 0.45, alpha: 1),
    "comment": NSColor(calibratedRed: 0.48, green: 0.53, blue: 0.58, alpha: 1),
    "number": NSColor(calibratedRed: 0.82, green: 0.70, blue: 0.98, alpha: 1),
    "type": NSColor(calibratedRed: 0.57, green: 0.82, blue: 0.98, alpha: 1),
    "function": NSColor(calibratedRed: 0.45, green: 0.78, blue: 0.98, alpha: 1),
    "constant": NSColor(calibratedRed: 0.90, green: 0.70, blue: 0.45, alpha: 1),
    "property": NSColor(calibratedRed: 0.70, green: 0.80, blue: 0.98, alpha: 1),
    "variable": NSColor.labelColor,
    "operator": NSColor(calibratedRed: 0.98, green: 0.45, blue: 0.71, alpha: 1),
    "punctuation": NSColor.secondaryLabelColor,
    "attribute": NSColor(calibratedRed: 0.90, green: 0.70, blue: 0.45, alpha: 1),
    "constructor": NSColor(calibratedRed: 0.57, green: 0.82, blue: 0.98, alpha: 1),
    "boolean": NSColor(calibratedRed: 0.98, green: 0.45, blue: 0.71, alpha: 1),
    "character": NSColor(calibratedRed: 0.98, green: 0.57, blue: 0.45, alpha: 1),
  ]
}
