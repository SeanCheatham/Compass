import Foundation
import SwiftUI
import Testing

@testable import Compass

/// Tests verifying `WhyGeneratedPopover` SwiftUI view state rendering.
///
/// The popover has three mutually-exclusive states driven by its `@Binding` inputs:
///   1. `isLoading = true`             → loading spinner + "Generating explanation..."
///   2. `isLoading = false` + non-nil  → explanation text with `.textSelection(.enabled)` in maxWidth 400 frame
///   3. `isLoading = false` + nil      → "Explanation unavailable." fallback
///
/// No Foundation Models calls — pure SwiftUI state verification.
///
/// View rendering via `NSHostingView` is valid here because `swift build --target Compass`
/// does not exercise the SwiftTestingMacros linkage that blocks `CompassTests`.
struct ExploreWhyGeneratedPopoverTests {

  // MARK: - State 1: Loading

  /// Verifies the loading state renders spinner + "Generating explanation..." text.
  @Test
  func isLoading_rendersSpinnerAndLabel() {
    var explanation: String? = nil
    var isLoading = true

    let popover = WhyGeneratedPopover(
      fileName: "Test.swift",
      explanation: Binding(&explanation),
      isLoading: Binding(&isLoading)
    )

    let rendered = renderView(popover)

    // Loading branch: ProgressView + "Generating explanation..."
    #require(rendered.contains { $0.type == .spinner })
    #require(rendered.contains { $0.type == .text("Generating explanation...") })
    // No explanation text in loading state
    #expect(!rendered.contains { $0.type == .text("This file was generated") })
    // No fallback in loading state
    #expect(!rendered.contains { $0.type == .text("Explanation unavailable.") })
  }

  /// Verifies loading state is mutually exclusive — loading takes priority over non-nil explanation.
  @Test
  func isLoading_withNonNilExplanation_showsLoadingNotExplanation() {
    var explanation: String? = "This was generated because..."
    var isLoading = true

    let popover = WhyGeneratedPopover(
      fileName: "Test.swift",
      explanation: Binding(&explanation),
      isLoading: Binding(&isLoading)
    )

    let rendered = renderView(popover)

    // Loading branch shown — not the explanation branch
    #require(rendered.contains { $0.type == .text("Generating explanation...") })
    #expect(!rendered.contains { $0.type == .text("This was generated because...") })
  }

  // MARK: - State 2: Non-nil explanation

  /// Verifies explanation text is displayed when not loading and explanation is non-nil.
  @Test
  func notLoading_withExplanation_rendersExplanationText() {
    var explanation: String? = "This file was generated to handle X."
    var isLoading = false

    let popover = WhyGeneratedPopover(
      fileName: "Test.swift",
      explanation: Binding(&explanation),
      isLoading: Binding(&isLoading)
    )

    let rendered = renderView(popover)

    #require(rendered.contains { $0.type == .text("This file was generated to handle X.") })
    // Not in loading state
    #expect(!rendered.contains { $0.type == .text("Generating explanation...") })
    // Not in fallback state
    #expect(!rendered.contains { $0.type == .text("Explanation unavailable.") })
  }

  /// Verifies explanation text has `.textSelection(.enabled)` — text is selectable.
  @Test
  func notLoading_withExplanation_hasTextSelectionEnabled() {
    var explanation: String? = "Selectable explanation text."
    var isLoading = false

    let popover = WhyGeneratedPopover(
      fileName: "Test.swift",
      explanation: Binding(&explanation),
      isLoading: Binding(&isLoading)
    )

    let rendered = renderView(popover)

    // The explanation Text view carries .textSelection(.enabled)
    #require(rendered.contains { $0.type == .text("Selectable explanation text.") && $0.selectable == true })
  }

  /// Verifies explanation text uses `.frame(maxWidth: 400)` — maxWidth 400 constraint.
  @Test
  func notLoading_withExplanation_maxWidth400() {
    var explanation: String? = "Width-constrained text."
    var isLoading = false

    let popover = WhyGeneratedPopover(
      fileName: "Test.swift",
      explanation: Binding(&explanation),
      isLoading: Binding(&isLoading)
    )

    let rendered = renderView(popover)

    #require(rendered.contains { $0.type == .text("Width-constrained text.") && $0.maxWidth == 400 })
  }

  // MARK: - State 3: Fallback

  /// Verifies "Explanation unavailable." is shown when not loading and explanation is nil.
  @Test
  func notLoading_withNilExplanation_rendersFallback() {
    var explanation: String? = nil
    var isLoading = false

    let popover = WhyGeneratedPopover(
      fileName: "Test.swift",
      explanation: Binding(&explanation),
      isLoading: Binding(&isLoading)
    )

    let rendered = renderView(popover)

    #require(rendered.contains { $0.type == .text("Explanation unavailable.") })
    // Not in loading state
    #expect(!rendered.contains { $0.type == .text("Generating explanation...") })
    // Not in explanation state
    #expect(!rendered.contains { $0.type == .text("This file was generated") })
  }

  /// Verifies fallback does NOT have `.textSelection(.enabled)`.
  @Test
  func notLoading_withNilExplanation_fallbackNotSelectable() {
    var explanation: String? = nil
    var isLoading = false

    let popover = WhyGeneratedPopover(
      fileName: "Test.swift",
      explanation: Binding(&explanation),
      isLoading: Binding(&isLoading)
    )

    let rendered = renderView(popover)

    // The fallback "Explanation unavailable." text has no textSelection
    #require(rendered.contains { $0.type == .text("Explanation unavailable.") && $0.selectable == false })
  }

  /// Verifies the three states are mutually exclusive — loading wins over explanation.
  @Test
  func isLoading_winsOverNonNilExplanation() {
    var explanation: String? = "Some explanation"
    var isLoading = true

    let popover = WhyGeneratedPopover(
      fileName: "Test.swift",
      explanation: Binding(&explanation),
      isLoading: Binding(&isLoading)
    )

    let rendered = renderView(popover)

    // Loading branch shown
    #require(rendered.contains { $0.type == .text("Generating explanation...") })
    // Explanation NOT shown (loading takes priority via `else if`)
    #expect(!rendered.contains { $0.type == .text("Some explanation") })
  }

  // MARK: - Common elements

  /// Verifies the header "Why Generated?" label and close button render in all three states.
  @Test
  func allStates_renderHeaderAndCloseButton() {
    // State 1: loading
    {
      var explanation: String? = nil
      var isLoading = true
      let popover = WhyGeneratedPopover(
        fileName: "Test.swift",
        explanation: Binding(&explanation),
        isLoading: Binding(&isLoading)
      )
      let rendered = renderView(popover)
      #require(rendered.contains { $0.type == .text("Why Generated?") })
      #require(rendered.contains { $0.type == .text("Close") })
    }

    // State 2: non-nil explanation
    {
      var explanation: String? = "Explanation text."
      var isLoading = false
      let popover = WhyGeneratedPopover(
        fileName: "Test.swift",
        explanation: Binding(&explanation),
        isLoading: Binding(&isLoading)
      )
      let rendered = renderView(popover)
      #require(rendered.contains { $0.type == .text("Why Generated?") })
      #require(rendered.contains { $0.type == .text("Close") })
    }

    // State 3: nil explanation (fallback)
    {
      var explanation: String? = nil
      var isLoading = false
      let popover = WhyGeneratedPopover(
        fileName: "Test.swift",
        explanation: Binding(&explanation),
        isLoading: Binding(&isLoading)
      )
      let rendered = renderView(popover)
      #require(rendered.contains { $0.type == .text("Why Generated?") })
      #require(rendered.contains { $0.type == .text("Close") })
    }
  }

  /// Verifies the outer container has `.frame(width: 440)` — 440pt total popover width.
  @Test
  func outerFrame_widthIs440() {
    var explanation: String? = "Some explanation"
    var isLoading = false

    let popover = WhyGeneratedPopover(
      fileName: "Test.swift",
      explanation: Binding(&explanation),
      isLoading: Binding(&isLoading)
    )

    let rendered = renderView(popover)

    // The outermost VStack is wrapped in .frame(width: 440)
    #require(rendered.contains { $0.type == .outerFrame(width: 440) })
  }

  // MARK: - Helper types

  private enum RenderedElement: Equatable {
    case spinner
    case text(String, selectable: Bool = false, maxWidth: CGFloat? = nil)
    case outerFrame(width: CGFloat)
  }

  // MARK: - View rendering helpers

  /// Renders the WhyGeneratedPopover view and extracts named child views as a flat array.
  private func renderView(_ view: WhyGeneratedPopover) -> [RenderedElement] {
    var elements: [RenderedElement] = []

    let hosting = NSHostingView(rootView: view)
    hosting.frame = CGRect(x: 0, y: 0, width: 440, height: 300)

    // Walk the SwiftUI view tree by traversing subviews.
    // NSHostingView's subviews reflect the SwiftUI layout.
    collectElements(from: hosting, into: &elements)

    return elements
  }

  private func collectElements(from view: NSView, into elements: inout [RenderedElement]) {
    // Detect ProgressView (rendered as NSProgressView or similar).
    if view is NSProgressView {
      elements.append(.spinner)
    }

    // Detect NSTextField for label/title/text content (non-editable text fields).
    if let textField = view as? NSTextField, !textField.isEditable {
      let string = textField.stringValue
      let selectable = textField.isSelectable
      let maxWidth = explicitWidthConstraint(for: textField)
      elements.append(.text(string, selectable: selectable, maxWidth: maxWidth))
    }

    // Detect the outermost frame container — it has fixed width 440.
    // A plain NSView (not a control) at exactly 440 wide with non-zero height
    // and no subviews with the same width is a good heuristic for the frame wrapper.
    if view.frame.width == 440 && view.frame.height > 0 {
      if !(view is NSTextField) && !(view is NSProgressView) {
        elements.append(.outerFrame(width: 440))
      }
    }

    // Recurse into subviews.
    for subview in view.subviews {
      collectElements(from: subview, into: &elements)
    }
  }

  private func explicitWidthConstraint(for view: NSView) -> CGFloat? {
    for constraint in view.constraints {
      if constraint.firstAttribute == .width && constraint.relation == .lessThanOrEqual {
        return constraint.constant
      }
    }
    return nil
  }
}

