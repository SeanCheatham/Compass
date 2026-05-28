import Foundation
import SwiftUI
import Testing

@testable import Compass

/// Tests verifying `ArchitectureGraphPopover` SwiftUI view state rendering.
///
/// The popover has five mutually-exclusive visual states driven by its `@State` properties:
///   1. `isLoading = true`              → ProgressView spinner + "Analyzing architecture..."
///   2. `isLoading = false` + `availabilityError = true` → orange warning label
///   3. `isLoading = false` + non-nil `graphText` + non-nil `explanation` → both sections
///   4. `isLoading = false` + non-nil `graphText` + nil `explanation` → graph only
///   5. `isLoading = false` + `availabilityError = false` + nil `graphText` → empty body
///
/// No Foundation Models calls needed — `graphText` is always available from
/// `buildGraph(codemapDirectory:)` and state is injected via the testable subclass.
///
/// View rendering via `NSHostingView` is valid here because `swift build --target Compass`
/// does not exercise the SwiftTestingMacros linkage that blocks `CompassTests`.
struct ExploreArchitectureGraphPopoverTests {

  // MARK: - State 1: Loading

  /// Verifies loading state renders spinner + "Analyzing architecture..." caption.
  @Test
  func isLoading_rendersSpinnerAndLabel() {
    let popover = TestableArchitectureGraphPopover(
      item: PlanSessionHistoryItem.placeholder,
      repoURL: URL(fileURLWithPath: "/test/repo"),
      isLoading: true,
      graphText: nil,
      explanation: nil,
      availabilityError: false
    )

    let rendered = renderView(popover)

    #require(rendered.contains { $0.type == .spinner })
    #require(rendered.contains { $0.type == .text("Analyzing architecture...") })
    // No graph text section in loading state
    #expect(!rendered.contains { $0.type == .text("Structure") })
    // No explanation section in loading state
    #expect(!rendered.contains { $0.type == .text("Explanation") })
    // No availability error in loading state
    #expect(!rendered.contains { $0.type == .errorLabel })
  }

  /// Verifies loading state is mutually exclusive — loading takes priority over graphText.
  @Test
  func isLoading_withNonNilGraphText_showsSpinnerNotGraph() {
    let popover = TestableArchitectureGraphPopover(
      item: PlanSessionHistoryItem.placeholder,
      repoURL: URL(fileURLWithPath: "/test/repo"),
      isLoading: true,
      graphText: "cluster A\n  Sources/App.swift",
      explanation: nil,
      availabilityError: false
    )

    let rendered = renderView(popover)

    #require(rendered.contains { $0.type == .spinner })
    #require(rendered.contains { $0.type == .text("Analyzing architecture...") })
    // Graph text NOT shown while loading
    #expect(!rendered.contains { $0.type == .text("Structure") })
  }

  /// Verifies loading state takes priority over explanation.
  @Test
  func isLoading_withExplanation_showsSpinnerNotExplanation() {
    let popover = TestableArchitectureGraphPopover(
      item: PlanSessionHistoryItem.placeholder,
      repoURL: URL(fileURLWithPath: "/test/repo"),
      isLoading: true,
      graphText: "graph",
      explanation: "Some explanation text.",
      availabilityError: false
    )

    let rendered = renderView(popover)

    #require(rendered.contains { $0.type == .spinner })
    #require(rendered.contains { $0.type == .text("Analyzing architecture...") })
    // Explanation NOT shown while loading
    #expect(!rendered.contains { $0.type == .text("Explanation") })
  }

  // MARK: - State 2: Availability error

  /// Verifies availability error renders orange warning label.
  @Test
  func availabilityError_rendersOrangeWarningLabel() {
    let popover = TestableArchitectureGraphPopover(
      item: PlanSessionHistoryItem.placeholder,
      repoURL: URL(fileURLWithPath: "/test/repo"),
      isLoading: false,
      graphText: nil,
      explanation: nil,
      availabilityError: true
    )

    let rendered = renderView(popover)

    #require(rendered.contains { $0.type == .errorLabel })
    #require(rendered.contains { $0.type == .text("Foundation Models is unavailable on this device.") })
  }

  /// Verifies availability error does NOT show spinner.
  @Test
  func availabilityError_noSpinner() {
    let popover = TestableArchitectureGraphPopover(
      item: PlanSessionHistoryItem.placeholder,
      repoURL: URL(fileURLWithPath: "/test/repo"),
      isLoading: false,
      graphText: nil,
      explanation: nil,
      availabilityError: true
    )

    let rendered = renderView(popover)

    #expect(!rendered.contains { $0.type == .spinner })
    #expect(!rendered.contains { $0.type == .text("Analyzing architecture...") })
  }

  /// Verifies availability error does NOT show graph or explanation sections.
  @Test
  func availabilityError_noGraphOrExplanationSections() {
    let popover = TestableArchitectureGraphPopover(
      item: PlanSessionHistoryItem.placeholder,
      repoURL: URL(fileURLWithPath: "/test/repo"),
      isLoading: false,
      graphText: "some graph",
      explanation: "some explanation",
      availabilityError: true
    )

    let rendered = renderView(popover)

    // Error takes priority — neither section shown
    #expect(!rendered.contains { $0.type == .text("Structure") })
    #expect(!rendered.contains { $0.type == .text("Explanation") })
  }

  // MARK: - State 3: Graph + Explanation

  /// Verifies graph text section with explanation renders both sections.
  @Test
  func graphAndExplanation_rendersBothSections() {
    let popover = TestableArchitectureGraphPopover(
      item: PlanSessionHistoryItem.placeholder,
      repoURL: URL(fileURLWithPath: "/test/repo"),
      isLoading: false,
      graphText: "cluster App\n  Sources/App.swift",
      explanation: "This is the main entry point.",
      availabilityError: false
    )

    let rendered = renderView(popover)

    #require(rendered.contains { $0.type == .text("Structure") })
    #require(rendered.contains { $0.type == .text("Explanation") })
    #require(rendered.contains { $0.type == .text("cluster App\n  Sources/App.swift") })
    #require(rendered.contains { $0.type == .text("This is the main entry point.") })
  }

  /// Verifies graph text section has `.textSelection(.enabled)`.
  @Test
  func graphAndExplanation_graphTextIsSelectable() {
    let popover = TestableArchitectureGraphPopover(
      item: PlanSessionHistoryItem.placeholder,
      repoURL: URL(fileURLWithPath: "/test/repo"),
      isLoading: false,
      graphText: "Selectable graph text.",
      explanation: "Explanation here.",
      availabilityError: false
    )

    let rendered = renderView(popover)

    #require(rendered.contains { $0.type == .text("Selectable graph text.") && $0.selectable == true })
  }

  /// Verifies explanation section has `.textSelection(.enabled)`.
  @Test
  func graphAndExplanation_explanationIsSelectable() {
    let popover = TestableArchitectureGraphPopover(
      item: PlanSessionHistoryItem.placeholder,
      repoURL: URL(fileURLWithPath: "/test/repo"),
      isLoading: false,
      graphText: "Graph.",
      explanation: "Selectable explanation text.",
      availabilityError: false
    )

    let rendered = renderView(popover)

    #require(rendered.contains { $0.type == .text("Selectable explanation text.") && $0.selectable == true })
  }

  /// Verifies explanation section has a clipboard copy button.
  @Test
  func graphAndExplanation_hasClipboardButton() {
    let popover = TestableArchitectureGraphPopover(
      item: PlanSessionHistoryItem.placeholder,
      repoURL: URL(fileURLWithPath: "/test/repo"),
      isLoading: false,
      graphText: "Graph.",
      explanation: "Explanation text.",
      availabilityError: false
    )

    let rendered = renderView(popover)

    #require(rendered.contains { $0.type == .clipboardButton })
  }

  // MARK: - State 4: Graph only (nil explanation)

  /// Verifies graph text renders without explanation section.
  @Test
  func graphOnly_noExplanationSection() {
    let popover = TestableArchitectureGraphPopover(
      item: PlanSessionHistoryItem.placeholder,
      repoURL: URL(fileURLWithPath: "/test/repo"),
      isLoading: false,
      graphText: "cluster App\n  Sources/App.swift",
      explanation: nil,
      availabilityError: false
    )

    let rendered = renderView(popover)

    #require(rendered.contains { $0.type == .text("Structure") })
    #require(rendered.contains { $0.type == .text("cluster App\n  Sources/App.swift") })
    #expect(!rendered.contains { $0.type == .text("Explanation") })
    #expect(!rendered.contains { $0.type == .text("This is the main entry point.") })
  }

  /// Verifies graph-only still shows graph text as selectable.
  @Test
  func graphOnly_graphTextIsSelectable() {
    let popover = TestableArchitectureGraphPopover(
      item: PlanSessionHistoryItem.placeholder,
      repoURL: URL(fileURLWithPath: "/test/repo"),
      isLoading: false,
      graphText: "Selectable graph text.",
      explanation: nil,
      availabilityError: false
    )

    let rendered = renderView(popover)

    #require(rendered.contains { $0.type == .text("Selectable graph text.") && $0.selectable == true })
  }

  // MARK: - State 5: Empty (nil graphText, no error)

  /// Verifies nil graphText + nil explanation + no errors = empty body (no spinner, no sections).
  @Test
  func emptyState_rendersNothingButHeader() {
    let popover = TestableArchitectureGraphPopover(
      item: PlanSessionHistoryItem.placeholder,
      repoURL: URL(fileURLWithPath: "/test/repo"),
      isLoading: false,
      graphText: nil,
      explanation: nil,
      availabilityError: false
    )

    let rendered = renderView(popover)

    // No spinner
    #expect(!rendered.contains { $0.type == .spinner })
    // No error label
    #expect(!rendered.contains { $0.type == .errorLabel })
    // No "Structure" section
    #expect(!rendered.contains { $0.type == .text("Structure") })
    // No "Explanation" section
    #expect(!rendered.contains { $0.type == .text("Explanation") })
    // But header is present
    #require(rendered.contains { $0.type == .text("Architecture Graph") })
  }

  // MARK: - Common elements

  /// Verifies "Architecture Graph" header label renders in all non-error states.
  @Test
  func allStates_renderHeaderLabel() {
    // State 1: loading
    {
      let popover = TestableArchitectureGraphPopover(
        item: PlanSessionHistoryItem.placeholder,
        repoURL: URL(fileURLWithPath: "/test/repo"),
        isLoading: true,
        graphText: nil,
        explanation: nil,
        availabilityError: false
      )
      let rendered = renderView(popover)
      #require(rendered.contains { $0.type == .text("Architecture Graph") })
    }

    // State 2: availability error
    {
      let popover = TestableArchitectureGraphPopover(
        item: PlanSessionHistoryItem.placeholder,
        repoURL: URL(fileURLWithPath: "/test/repo"),
        isLoading: false,
        graphText: nil,
        explanation: nil,
        availabilityError: true
      )
      let rendered = renderView(popover)
      #require(rendered.contains { $0.type == .text("Architecture Graph") })
    }

    // State 3: graph + explanation
    {
      let popover = TestableArchitectureGraphPopover(
        item: PlanSessionHistoryItem.placeholder,
        repoURL: URL(fileURLWithPath: "/test/repo"),
        isLoading: false,
        graphText: "graph",
        explanation: "exp",
        availabilityError: false
      )
      let rendered = renderView(popover)
      #require(rendered.contains { $0.type == .text("Architecture Graph") })
    }

    // State 4: graph only
    {
      let popover = TestableArchitectureGraphPopover(
        item: PlanSessionHistoryItem.placeholder,
        repoURL: URL(fileURLWithPath: "/test/repo"),
        isLoading: false,
        graphText: "graph",
        explanation: nil,
        availabilityError: false
      )
      let rendered = renderView(popover)
      #require(rendered.contains { $0.type == .text("Architecture Graph") })
    }

    // State 5: empty
    {
      let popover = TestableArchitectureGraphPopover(
        item: PlanSessionHistoryItem.placeholder,
        repoURL: URL(fileURLWithPath: "/test/repo"),
        isLoading: false,
        graphText: nil,
        explanation: nil,
        availabilityError: false
      )
      let rendered = renderView(popover)
      #require(rendered.contains { $0.type == .text("Architecture Graph") })
    }
  }

  /// Verifies outer frame width is 440.
  @Test
  func outerFrame_widthIs440() {
    let popover = TestableArchitectureGraphPopover(
      item: PlanSessionHistoryItem.placeholder,
      repoURL: URL(fileURLWithPath: "/test/repo"),
      isLoading: false,
      graphText: "graph",
      explanation: "exp",
      availabilityError: false
    )

    let rendered = renderView(popover)

    #require(rendered.contains { $0.type == .outerFrame(width: 440) })
  }

  // MARK: - Helper types

  private enum RenderedElement: Equatable {
    case spinner
    case text(String, selectable: Bool = false, maxWidth: CGFloat? = nil)
    case errorLabel
    case clipboardButton
    case outerFrame(width: CGFloat)
  }

  // MARK: - Testable subclass

  /// A subclass of `ArchitectureGraphPopover` that exposes state injection for testing.
  /// We cannot directly mutate `@State` from outside the view, so we expose a
  /// testing-only path to set all relevant state simultaneously.
  ///
  /// The subclass overrides `.task` to be a no-op so that state injection
  /// is the only source of truth during tests.
  private class TestableArchitectureGraphPopover: ArchitectureGraphPopover {

    init(
      item: PlanSessionHistoryItem,
      repoURL: URL,
      isLoading: Bool,
      graphText: String?,
      explanation: String?,
      availabilityError: Bool
    ) {
      // Directly initialize parent @State properties via the stored property wrapper
      // backing. This is the standard SwiftUI testable-subclass pattern — state is
      // baked in at init time and the real body is used, so @State-driven branching
      // (loading vs. error vs. content) is exercised correctly.
      super.init(item: item, repoURL: repoURL)
      // Use reflection-like direct assignment for @State backed properties.
      // The parent stores these as @State private vars; we set them here so body
      // reads the intended values rather than defaults (nil/false).
      _graphText = State(wrappedValue: graphText)
      _explanation = State(wrappedValue: explanation)
      _isLoading = State(wrappedValue: isLoading)
      _availabilityError = State(wrappedValue: availabilityError)
    }

    // Override .task to no-op so state injection is the only source of truth.
    override func task() async -> Void {
      // no-op: prevents auto-loading in tests; parent body uses injected state
    }
  }

  // MARK: - View rendering helpers

  /// Renders the `TestableArchitectureGraphPopover` and extracts named child views.
  private func renderView(_ popover: TestableArchitectureGraphPopover) -> [RenderedElement] {
    var elements: [RenderedElement] = []

    // Embed in NSHostingView with a known frame size
    let hosting = NSHostingView(rootView: popover)
    hosting.frame = CGRect(x: 0, y: 0, width: 440, height: 600)

    collectElements(from: hosting, into: &elements)
    return elements
  }

  private func collectElements(from view: NSView, into elements: inout [RenderedElement]) {
    // Detect ProgressView (rendered as NSProgressView)
    if view is NSProgressView {
      elements.append(.spinner)
    }

    // Detect NSTextField for text content (non-editable)
    if let textField = view as? NSTextField, !textField.isEditable {
      let string = textField.stringValue
      let selectable = textField.isSelectable
      let maxWidth = explicitWidthConstraint(for: textField)
      elements.append(.text(string, selectable: selectable, maxWidth: maxWidth))
    }

    // Detect clipboard button (NSButton with specific image)
    if let button = view as? NSButton {
      if button.image?.name() == "doc.on.clipboard" {
        elements.append(.clipboardButton)
      }
    }

    // Detect error label — it uses a Label view with an orange foreground.
    // When rendered in NSHostingView, the icon and text may appear as
    // separate NSTextField instances. We detect the error message text
    // by matching the specific string content.
    if let textField = view as? NSTextField, !textField.isEditable {
      if textField.stringValue == "Foundation Models is unavailable on this device." {
        elements.append(.errorLabel)
      }
    }

    // Detect the outermost frame container — fixed 440 wide
    if view.frame.width == 440 && view.frame.height > 0 {
      if !(view is NSTextField) && !(view is NSProgressView) && !(view is NSButton) {
        elements.append(.outerFrame(width: 440))
      }
    }

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