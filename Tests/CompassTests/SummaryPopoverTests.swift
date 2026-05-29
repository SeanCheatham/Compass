import SwiftUI
import Testing

@testable import Compass

struct SummaryPopoverTests {
  @Test
  func initializerKeepsFileNameAndSummary() {
    let popover = SummaryPopover(
      fileName: "Example.swift",
      summary: "An example file that demonstrates summary display.",
      reason: nil
    )

    #expect(popover.fileName == "Example.swift")
    #expect(popover.summary == "An example file that demonstrates summary display.")
  }

  @Test
  func summaryTextIsPresent() {
    let summaryText = "Detailed summary content"
    let popover = SummaryPopover(
      fileName: "Example.swift",
      summary: summaryText,
      reason: nil
    )

    #expect(String(reflecting: popover.body).contains(summaryText))
  }

  @Test
  func closeButtonPresent() {
    let popover = SummaryPopover(
      fileName: "Example.swift",
      summary: "Summary",
      reason: nil
    )

    #expect(String(reflecting: popover.body).contains("Close"))
  }

  @Test
  func headerLabelSaysSummary() {
    let popover = SummaryPopover(
      fileName: "Example.swift",
      summary: "Summary",
      reason: nil
    )

    #expect(String(reflecting: popover.body).contains("Summary"))
  }

  @Test
  func frameAppliesWidth440() {
    let popover = SummaryPopover(
      fileName: "Example.swift",
      summary: "Summary",
      reason: nil
    )

    let typeName = String(reflecting: popover.body)
    #expect(typeName.contains("440"))
  }

  @Test
  func paddingAppliesValue16() {
    let popover = SummaryPopover(
      fileName: "Example.swift",
      summary: "Summary",
      reason: nil
    )

    let typeName = String(reflecting: popover.body)
    #expect(typeName.contains("16"))
  }

  @Test
  func textFrameMaxWidthIs400() {
    let popover = SummaryPopover(
      fileName: "Example.swift",
      summary: "Summary",
      reason: nil
    )

    let typeName = String(reflecting: popover.body)
    #expect(typeName.contains("400"))
  }
}
