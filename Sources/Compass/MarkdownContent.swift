import CompassCore
import Foundation
import SwiftUI

struct MarkdownContent: View {
  private var text: String
  private var empty: String?
  private var compact: Bool

  init(_ text: String, empty: String? = nil, compact: Bool = false) {
    self.text = text
    self.empty = empty
    self.compact = compact
  }

  var body: some View {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      if let empty {
        Text(empty)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, compact ? 0 : 8)
      }
    } else {
      VStack(alignment: .leading, spacing: compact ? 6 : 10) {
        ForEach(Array(MarkdownParser.parse(text).enumerated()), id: \.offset) { _, element in
          MarkdownElementView(element: element, compact: compact)
        }
      }
      .textSelection(.enabled)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

struct InlineMarkdownText: View {
  var text: String

  var body: some View {
    Text(attributedText)
      .textSelection(.enabled)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var attributedText: AttributedString {
    do {
      return try AttributedString(
        markdown: text,
        options: AttributedString.MarkdownParsingOptions(
          interpretedSyntax: .inlineOnlyPreservingWhitespace)
      )
    } catch {
      return AttributedString(text)
    }
  }
}

private struct MarkdownElementView: View {
  var element: MarkdownElement
  var compact: Bool

  var body: some View {
    switch element {
    case .heading(let level, let text):
      InlineMarkdownText(text: text)
        .font(headingFont(for: level))
        .padding(.top, compact ? 0 : headingTopPadding(for: level))

    case .paragraph(let text):
      InlineMarkdownText(text: text)
        .font(.body)
        .lineSpacing(compact ? 1 : 3)

    case .unorderedList(let items):
      VStack(alignment: .leading, spacing: compact ? 3 : 5) {
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
          UnorderedMarkdownRow(item: item, compact: compact)
        }
      }
      .padding(.leading, compact ? 2 : 6)

    case .orderedList(let items):
      VStack(alignment: .leading, spacing: compact ? 3 : 5) {
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
          OrderedMarkdownRow(item: item, compact: compact)
        }
      }
      .padding(.leading, compact ? 2 : 6)

    case .quote(let text):
      HStack(alignment: .top, spacing: 8) {
        Rectangle()
          .fill(.secondary.opacity(0.45))
          .frame(width: 3)
        InlineMarkdownText(text: text)
          .font(.callout)
          .foregroundStyle(.secondary)
          .lineSpacing(2)
      }

    case .code(let text):
      Text(text.isEmpty ? " " : text)
        .font(.system(.caption, design: .monospaced))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))

    case .rule:
      Divider()
    }
  }

  private func headingFont(for level: Int) -> Font {
    switch level {
    case 1:
      return compact ? .headline : .title3.weight(.semibold)
    case 2:
      return compact ? .subheadline.weight(.semibold) : .headline
    case 3:
      return .subheadline.weight(.semibold)
    default:
      return .callout.weight(.semibold)
    }
  }

  private func headingTopPadding(for level: Int) -> CGFloat {
    level <= 2 ? 6 : 2
  }
}

private struct UnorderedMarkdownRow: View {
  var item: String
  var compact: Bool

  var body: some View {
    let checkbox = MarkdownParser.checkbox(in: item)
    HStack(alignment: .top, spacing: 8) {
      if let checkbox {
        Image(systemName: checkbox.isChecked ? "checkmark.square.fill" : "square")
          .foregroundStyle(checkbox.isChecked ? .green : .secondary)
          .frame(width: compact ? 14 : 18, alignment: .center)
      } else {
        Image(systemName: "circle.fill")
          .font(.system(size: compact ? 4 : 5))
          .frame(width: compact ? 14 : 18, alignment: .center)
      }
      InlineMarkdownText(text: checkbox?.text ?? item)
        .font(.body)
        .lineSpacing(compact ? 1 : 3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

private struct OrderedMarkdownRow: View {
  var item: OrderedMarkdownItem
  var compact: Bool

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Text(item.marker)
        .font(.body.monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(width: compact ? 24 : 32, alignment: .trailing)
      InlineMarkdownText(text: item.text)
        .font(.body)
        .lineSpacing(compact ? 1 : 3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

private enum MarkdownElement: Equatable {
  case heading(level: Int, text: String)
  case paragraph(String)
  case unorderedList([String])
  case orderedList([OrderedMarkdownItem])
  case quote(String)
  case code(String)
  case rule
}

private struct OrderedMarkdownItem: Equatable {
  var marker: String
  var text: String
}

private enum MarkdownParser {
  struct Checkbox {
    var isChecked: Bool
    var text: String
  }

  static func parse(_ markdown: String) -> [MarkdownElement] {
    let normalized =
      markdown
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    let lines = normalized.components(separatedBy: "\n")
    var elements: [MarkdownElement] = []
    var paragraph: [String] = []
    var index = 0

    func flushParagraph() {
      guard !paragraph.isEmpty else { return }
      elements.append(.paragraph(paragraph.joined(separator: " ")))
      paragraph.removeAll()
    }

    while index < lines.count {
      let line = lines[index]
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      if trimmed.isEmpty {
        flushParagraph()
        index += 1
        continue
      }

      if let fence = codeFence(in: trimmed) {
        flushParagraph()
        index += 1
        var codeLines: [String] = []
        while index < lines.count {
          let candidate = lines[index].trimmingCharacters(in: .whitespaces)
          if candidate.hasPrefix(fence) {
            index += 1
            break
          }
          codeLines.append(lines[index])
          index += 1
        }
        elements.append(.code(codeLines.joined(separator: "\n")))
        continue
      }

      if isRule(trimmed) {
        flushParagraph()
        elements.append(.rule)
        index += 1
        continue
      }

      if let heading = heading(in: trimmed) {
        flushParagraph()
        elements.append(.heading(level: heading.level, text: heading.text))
        index += 1
        continue
      }

      if unorderedItem(in: line) != nil {
        flushParagraph()
        var items: [String] = []
        while index < lines.count, let item = unorderedItem(in: lines[index]) {
          items.append(item)
          index += 1
        }
        elements.append(.unorderedList(items))
        continue
      }

      if orderedItem(in: line) != nil {
        flushParagraph()
        var items: [OrderedMarkdownItem] = []
        while index < lines.count, let item = orderedItem(in: lines[index]) {
          items.append(item)
          index += 1
        }
        elements.append(.orderedList(items))
        continue
      }

      if quoteLine(in: line) != nil {
        flushParagraph()
        var quoteLines: [String] = []
        while index < lines.count, let quoted = quoteLine(in: lines[index]) {
          quoteLines.append(quoted)
          index += 1
        }
        elements.append(.quote(quoteLines.joined(separator: "\n")))
        continue
      }

      paragraph.append(trimmed)
      index += 1
    }

    flushParagraph()
    return elements
  }

  static func checkbox(in text: String) -> Checkbox? {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    let prefixes: [(String, Bool)] = [
      ("[x] ", true),
      ("[X] ", true),
      ("[ ] ", false),
    ]
    for (prefix, isChecked) in prefixes where trimmed.hasPrefix(prefix) {
      return Checkbox(
        isChecked: isChecked,
        text: String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
      )
    }
    return nil
  }

  private static func codeFence(in trimmed: String) -> String? {
    if trimmed.hasPrefix("```") { return "```" }
    if trimmed.hasPrefix("~~~") { return "~~~" }
    return nil
  }

  private static func heading(in trimmed: String) -> (level: Int, text: String)? {
    var level = 0
    var current = trimmed.startIndex
    while current < trimmed.endIndex, trimmed[current] == "#", level < 6 {
      level += 1
      current = trimmed.index(after: current)
    }
    guard level > 0 else { return nil }
    guard current == trimmed.endIndex || trimmed[current].isWhitespace else { return nil }
    let text = String(trimmed[current...]).trimmingCharacters(in: .whitespaces)
    return (level, text)
  }

  private static func unorderedItem(in line: String) -> String? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    for marker in ["- ", "* ", "+ "] where trimmed.hasPrefix(marker) {
      return String(trimmed.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
    }
    return nil
  }

  private static func orderedItem(in line: String) -> OrderedMarkdownItem? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    var digits = ""
    var index = trimmed.startIndex

    while index < trimmed.endIndex, trimmed[index].isNumber {
      digits.append(trimmed[index])
      index = trimmed.index(after: index)
    }

    guard !digits.isEmpty, index < trimmed.endIndex else { return nil }
    let delimiter = trimmed[index]
    guard delimiter == "." || delimiter == ")" else { return nil }
    index = trimmed.index(after: index)
    guard index < trimmed.endIndex, trimmed[index].isWhitespace else { return nil }

    let text = String(trimmed[index...]).trimmingCharacters(in: .whitespaces)
    return OrderedMarkdownItem(marker: "\(digits).", text: text)
  }

  private static func quoteLine(in line: String) -> String? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix(">") else { return nil }
    return String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
  }

  private static func isRule(_ trimmed: String) -> Bool {
    guard trimmed.count >= 3 else { return false }
    let compact = trimmed.replacingOccurrences(of: " ", with: "")
    return compact.allSatisfy { $0 == "-" } || compact.allSatisfy { $0 == "*" }
      || compact.allSatisfy { $0 == "_" }
  }
}
