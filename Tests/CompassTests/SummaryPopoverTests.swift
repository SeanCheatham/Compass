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
  func frameAppliesWidth440() {
    let popover = SummaryPopover(
      fileName: "Example.swift",
      summary: "Summary"
    )

    let typeName = String(reflecting: popover.body)
    #expect(typeName.contains("440"))
  }

  @Test
  func paddingAppliesValue16() {
    let popover = SummaryPopover(
      fileName: "Example.swift",
      summary: "Summary"
    )

    let typeName = String(reflecting: popover.body)
    #expect(typeName.contains("16"))
  }

  @Test
  func textFrameMaxWidthIs400() {
    let popover = SummaryPopover(
      fileName: "Example.swift",
      summary: "Summary"
    )

    let typeName = String(reflecting: popover.body)
    #expect(typeName.contains("400"))
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

  private func collectText(from view: Any, into texts: inout [String]) {
    guard let childView = view as? any View else { return }
    let mirror = Mirror(reflecting: childView)
    for child in mirror.children {
      if let str = child.value as? String {
        texts.append(str)
      }
      if child.label == nil {
        collectText(from: child.value, into: &texts)
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
}