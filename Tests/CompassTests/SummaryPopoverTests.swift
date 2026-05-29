import SwiftUI
import Testing

@testable import Compass

struct SummaryPopoverTests {
  @Test
  func initializerKeepsFileNameAndSummary() {
    let popover = SummaryPopover(
      fileName: "Example.swift",
      summary: "An example file that demonstrates summary display."
    )

    #expect(popover.fileName == "Example.swift")
    #expect(popover.summary == "An example file that demonstrates summary display.")
  }

  @Test
  func summaryTextIsPresent() {
    let summaryText = "Detailed summary content"
    let popover = SummaryPopover(
      fileName: "Example.swift",
      summary: summaryText
    )

    #expect(popover.bodyText.contains(summaryText))
  }

  @Test
  func closeButtonPresent() {
    let popover = SummaryPopover(
      fileName: "Example.swift",
      summary: "Summary"
    )

    #expect(popover.hasCloseButton)
  }

  @Test
  func headerLabelSaysSummary() {
    let popover = SummaryPopover(
      fileName: "Example.swift",
      summary: "Summary"
    )

    #expect(popover.headerLabelText == "Summary")
  }

  @Test
  func frameWidthIs440() {
    let popover = SummaryPopover(
      fileName: "Example.swift",
      summary: "Summary"
    )

    #expect(popover.frameWidth == 440)
  }

  @Test
  func paddingIs16() {
    let popover = SummaryPopover(
      fileName: "Example.swift",
      summary: "Summary"
    )

    #expect(popover.paddingValue == 16)
  }

  @Test
  func summaryTextFrameMaxWidthIs400() {
    let popover = SummaryPopover(
      fileName: "Example.swift",
      summary: "Summary"
    )

    #expect(popover.summaryTextMaxWidth == 400)
  }
}

// MARK: - View inspection helpers

private extension SummaryPopover {
  /// All text strings found anywhere in the view tree.
  var bodyText: String {
    var texts: [String] = []
    collectText(from: body, into: &texts)
    return texts.joined()
  }

  private func collectText(from view: some View, into texts: inout [String]) {
    let mirror = Mirror(reflecting: view)
    for child in mirror.children {
      if let str = child.value as? String {
        texts.append(str)
      }
      if child.label == nil {
        if let sub = child.value as? (any View) {
          collectText(from: sub, into: &texts)
        }
      } else if let conditional = child.value as? _ConditionalContent<any View, any View> {
        collectText(from: conditional, into: &texts)
      } else if let anyView = child.value as? AnyView {
        collectText(from: anyView, into: &texts)
      }
    }
  }

  var hasCloseButton: Bool {
    bodyText.contains("Close")
  }

  var headerLabelText: String? {
    let allText = bodyText
    let components = allText.components(separatedBy: "\n").filter { !$0.isEmpty }
    return components.first
  }

  var frameWidth: CGFloat? {
    let mirror = Mirror(reflecting: body)
    for child in mirror.children {
      if let sub = child.value as? ModifiedContent<any View, some _SizeLayout> {
        let subMirror = Mirror(reflecting: sub)
        for subChild in subMirror.children {
          if subChild.label == "value", let size = subChild.value as? CGSize {
            return size.width
          }
          if subChild.label == "transform", let size = subChild.value as? CGSize {
            return size.width
          }
        }
      }
    }
    return nil
  }

  var paddingValue: CGFloat? {
    let mirror = Mirror(reflecting: body)
    for child in mirror.children {
      if let mod = child.value as? ModifiedContent<any View, some _PaddingLayout> {
        let modMirror = Mirror(reflecting: mod)
        for modChild in modMirror.children {
          if modChild.label == "length", let length = modChild.value as? CGFloat {
            return length
          }
        }
      }
      if child.label == nil {
        if let sub = child.value as? (any View) {
          if let found = extractPadding(from: sub) {
            return found
          }
        }
      }
    }
    return nil
  }

  private func extractPadding(from view: any View) -> CGFloat? {
    let mirror = Mirror(reflecting: view)
    for child in mirror.children {
      if let mod = child.value as? ModifiedContent<any View, some _PaddingLayout> {
        let modMirror = Mirror(reflecting: mod)
        for modChild in modMirror.children {
          if modChild.label == "length", let length = modChild.value as? CGFloat {
            return length
          }
        }
      }
    }
    return nil
  }

  var summaryTextMaxWidth: CGFloat? {
    findMaxWidthInView(body)
  }

  private func findMaxWidthInView(_ view: any View) -> CGFloat? {
    let mirror = Mirror(reflecting: view)
    for child in mirror.children {
      if child.label == "value", let size = child.value as? CGSize {
        return size.width
      }
      if child.label == "transform", let size = child.value as? CGSize {
        return size.width
      }
      if child.label == nil {
        if let sub = child.value as? (any View) {
          if let found = findMaxWidthInView(sub) {
            return found
          }
        }
      }
    }
    return nil
  }
}
