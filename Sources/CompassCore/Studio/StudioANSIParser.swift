import AppKit
import Foundation

/// Parses CSI SGR / OSC sequences in terminal output into an attributed string
/// for the Studio bash log. Not a full VT emulator — enough for colored
/// command output without SwiftTerm.
public enum StudioANSIParser {
  public struct Options {
    public var defaultForeground: NSColor
    public var defaultBackground: NSColor?
    public var font: NSFont

    public init(
      defaultForeground: NSColor = .secondaryLabelColor,
      defaultBackground: NSColor? = nil,
      font: NSFont = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
    ) {
      self.defaultForeground = defaultForeground
      self.defaultBackground = defaultBackground
      self.font = font
    }
  }

  /// Convert `text` (possibly containing ANSI escapes) into an attributed string.
  public static func attributedString(
    _ text: String,
    options: Options = Options()
  ) -> AttributedString {
    AttributedString(nsAttributedString(text, options: options))
  }

  public static func nsAttributedString(
    _ text: String,
    options: Options = Options()
  ) -> NSAttributedString {
    let result = NSMutableAttributedString()
    var foreground = options.defaultForeground
    var bold = false
    var dim = false
    var index = text.startIndex

    while index < text.endIndex {
      if text[index] == "\u{001B}" {
        let next = text.index(after: index)
        guard next < text.endIndex else {
          index = next
          continue
        }
        if text[next] == "]" {
          // OSC … BEL or ST — strip
          index = skipOSC(text, from: next)
          continue
        }
        if text[next] == "[" {
          let (params, after) = parseCSI(text, from: text.index(after: next))
          applySGR(params, foreground: &foreground, bold: &bold, dim: &dim, options: options)
          index = after
          continue
        }
        // Other escapes (cursor, etc.) — skip ESC + one char when possible
        index = text.index(after: next)
        continue
      }

      let end = text[index...].firstIndex(of: "\u{001B}") ?? text.endIndex
      let chunk = String(text[index..<end])
      if !chunk.isEmpty {
        var attrs: [NSAttributedString.Key: Any] = [
          .font: options.font,
          .foregroundColor: resolvedColor(foreground, bold: bold, dim: dim),
        ]
        if let bg = options.defaultBackground {
          attrs[.backgroundColor] = bg
        }
        result.append(NSAttributedString(string: chunk, attributes: attrs))
      }
      index = end
    }

    return result
  }

  /// Strip ANSI sequences, returning plain text.
  public static func strip(_ text: String) -> String {
    nsAttributedString(text).string
  }

  // MARK: - Parsing helpers

  private static func skipOSC(_ text: String, from afterBracket: String.Index) -> String.Index {
    var i = text.index(after: afterBracket)
    while i < text.endIndex {
      let ch = text[i]
      if ch == "\u{0007}" { return text.index(after: i) }
      if ch == "\u{001B}" {
        let n = text.index(after: i)
        if n < text.endIndex, text[n] == "\\" { return text.index(after: n) }
      }
      i = text.index(after: i)
    }
    return text.endIndex
  }

  private static func parseCSI(
    _ text: String,
    from start: String.Index
  ) -> (params: [Int], after: String.Index) {
    var i = start
    var raw = ""
    while i < text.endIndex {
      let ch = text[i]
      if ch.isLetter || ch == "@" || ch == "`" {
        let final = ch
        i = text.index(after: i)
        if final == "m" {
          return (parseParams(raw), i)
        }
        // Non-SGR CSI — ignore params
        return ([], i)
      }
      raw.append(ch)
      i = text.index(after: i)
    }
    return ([], text.endIndex)
  }

  private static func parseParams(_ raw: String) -> [Int] {
    if raw.isEmpty { return [0] }
    return raw.split(separator: ";", omittingEmptySubsequences: false).map {
      Int($0) ?? 0
    }
  }

  private static func applySGR(
    _ params: [Int],
    foreground: inout NSColor,
    bold: inout Bool,
    dim: inout Bool,
    options: Options
  ) {
    if params.isEmpty {
      foreground = options.defaultForeground
      bold = false
      dim = false
      return
    }
    var i = 0
    while i < params.count {
      let code = params[i]
      switch code {
      case 0:
        foreground = options.defaultForeground
        bold = false
        dim = false
      case 1:
        bold = true
        dim = false
      case 2:
        dim = true
      case 22:
        bold = false
        dim = false
      case 30...37:
        foreground = basicColor(code - 30, bright: false)
      case 90...97:
        foreground = basicColor(code - 90, bright: true)
      case 39:
        foreground = options.defaultForeground
      case 38:
        // 256 or RGB
        if i + 1 < params.count {
          let mode = params[i + 1]
          if mode == 5, i + 2 < params.count {
            foreground = color256(params[i + 2])
            i += 2
          } else if mode == 2, i + 4 < params.count {
            foreground = NSColor(
              calibratedRed: CGFloat(params[i + 2]) / 255,
              green: CGFloat(params[i + 3]) / 255,
              blue: CGFloat(params[i + 4]) / 255,
              alpha: 1
            )
            i += 4
          }
        }
      default:
        break
      }
      i += 1
    }
  }

  private static func resolvedColor(_ color: NSColor, bold: Bool, dim: Bool) -> NSColor {
    if dim { return color.withAlphaComponent(0.55) }
    if bold {
      // Slightly brighten for bold when possible
      return color.blended(withFraction: 0.15, of: .white) ?? color
    }
    return color
  }

  private static func basicColor(_ index: Int, bright: Bool) -> NSColor {
    let palette: [(CGFloat, CGFloat, CGFloat)] = bright
      ? [
        (0.5, 0.5, 0.5), (1, 0.4, 0.4), (0.4, 1, 0.4), (1, 1, 0.4),
        (0.4, 0.6, 1), (1, 0.4, 1), (0.4, 1, 1), (1, 1, 1),
      ]
      : [
        (0.1, 0.1, 0.1), (0.8, 0.2, 0.2), (0.2, 0.7, 0.2), (0.75, 0.7, 0.15),
        (0.25, 0.4, 0.85), (0.7, 0.25, 0.7), (0.2, 0.7, 0.7), (0.85, 0.85, 0.85),
      ]
    let rgb = palette[max(0, min(index, 7))]
    return NSColor(calibratedRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
  }

  private static func color256(_ index: Int) -> NSColor {
    if index < 16 {
      return basicColor(index % 8, bright: index >= 8)
    }
    if index < 232 {
      let i = index - 16
      let r = CGFloat(i / 36) / 5
      let g = CGFloat((i / 6) % 6) / 5
      let b = CGFloat(i % 6) / 5
      return NSColor(calibratedRed: r, green: g, blue: b, alpha: 1)
    }
    let gray = CGFloat(index - 232) / 23
    return NSColor(calibratedWhite: gray, alpha: 1)
  }
}
