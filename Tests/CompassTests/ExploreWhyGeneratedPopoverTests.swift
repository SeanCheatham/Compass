import SwiftUI
import Testing

@testable import Compass

struct ExploreWhyGeneratedPopoverTests {
  @Test
  func initializerKeepsFileNameAndLoadingBinding() throws {
    let popover = WhyGeneratedPopover(
      fileName: "GeneratedFile.swift",
      explanation: .constant(nil),
      reason: .constant(nil),
      isLoading: .constant(true)
    )

    #expect(popover.fileName == "GeneratedFile.swift")
    #expect(popover.explanation == nil)
    #expect(popover.isLoading)
  }

  @Test
  func initializerKeepsExplanationBinding() throws {
    let popover = WhyGeneratedPopover(
      fileName: "GeneratedFile.swift",
      explanation: .constant("Created from the latest plan."),
      reason: .constant(nil),
      isLoading: .constant(false)
    )

    #expect(popover.explanation == "Created from the latest plan.")
    #expect(!popover.isLoading)
  }

  @Test
  func mutableBindingsPropagateWrites() throws {
    final class BindingBox {
      var explanation: String?
      var isLoading = true
      var reason: ExplainUnavailableReason?
    }

    let box = BindingBox()
    var popover = WhyGeneratedPopover(
      fileName: "GeneratedFile.swift",
      explanation: Binding(
        get: { box.explanation },
        set: { box.explanation = $0 }
      ),
      reason: Binding(
        get: { box.reason },
        set: { box.reason = $0 }
      ),
      isLoading: Binding(
        get: { box.isLoading },
        set: { box.isLoading = $0 }
      )
    )

    popover.explanation = "Done."
    popover.isLoading = false
    popover.reason = .foundationModelsUnavailable

    #expect(box.explanation == "Done.")
    #expect(!box.isLoading)
    #expect(box.reason == .foundationModelsUnavailable)
  }

  // MARK: - reason.message display path

  /// Verifies `ExplainUnavailableReason.foundationModelsUnavailable.message`
  /// returns the expected user-facing string.
  ///
  /// When `WhyGeneratedPopover` has a non-nil `reason` binding (the
  /// `else if let reason = reason { HStack { Image + Text(reason.message) } }`
  /// branch at line 1740-1748), `reason.message` is displayed in the popover body.
  /// This test exercises that data path without requiring a full SwiftUI
  /// view render — matching the approach used in `ExploreTabWhyGeneratedTests`
  /// which tests the same reason cases that the popover's UI path exercises.
  @Test
  func reasonMessage_forFoundationModelsUnavailable_showsExpectedMessage() throws {
    #expect(ExplainUnavailableReason.foundationModelsUnavailable.message
      == "Explanation requires Apple Intelligence, which is not available on this device.")
  }

  /// Verifies `ExplainUnavailableReason.noDiff.message` returns the expected
  /// user-facing string displayed in the popover's reason branch.
  @Test
  func reasonMessage_forNoDiff_showsExpectedMessage() throws {
    #expect(ExplainUnavailableReason.noDiff.message
      == "No commit diff available for this file.")
  }

  /// Verifies `ExplainUnavailableReason.emptyDiff.message` returns the expected
  /// user-facing string displayed in the popover's reason branch.
  @Test
  func reasonMessage_forEmptyDiff_showsExpectedMessage() throws {
    #expect(ExplainUnavailableReason.emptyDiff.message
      == "No content changes found in this file.")
  }

  /// Verifies `ExplainUnavailableReason.emptyResponse.message` returns the expected
  /// user-facing string displayed in the popover's reason branch.
  @Test
  func reasonMessage_forEmptyResponse_showsExpectedMessage() throws {
    #expect(ExplainUnavailableReason.emptyResponse.message
      == "The model did not produce an explanation. Please try again.")
  }

  /// Verifies `ExplainUnavailableReason.unavailable.message` returns the expected
  /// user-facing string displayed in the popover's reason branch.
  @Test
  func reasonMessage_forUnavailable_showsExpectedMessage() throws {
    #expect(ExplainUnavailableReason.unavailable.message
      == "Explanation unavailable.")
  }

  // MARK: - fileURL property

  @Test
  func fileURL_initNil_staysNil() throws {
    let popover = WhyGeneratedPopover(
      fileName: "Gen.swift",
      fileURL: nil,
      explanation: .constant(nil),
      reason: .constant(nil),
      isLoading: .constant(false)
    )
    #expect(popover.fileURL == nil)
  }

  @Test
  func fileURL_initNonNil_preservesURL() throws {
    let url = URL(fileURLWithPath: "/Users/test/Gen.swift")
    let popover = WhyGeneratedPopover(
      fileName: "Gen.swift",
      fileURL: url,
      explanation: .constant(nil),
      reason: .constant(nil),
      isLoading: .constant(false)
    )
    #expect(popover.fileURL == url)
  }

  // MARK: - isLoading binding display path

  @Test
  func isLoading_true_showsGeneratingExplanation() throws {
    let popover = WhyGeneratedPopover(
      fileName: "Gen.swift",
      explanation: .constant(nil),
      reason: .constant(nil),
      isLoading: .constant(true)
    )
    let body = String(reflecting: popover.body)
    #expect(body.contains("Generating explanation..."))
  }

  @Test
  func isLoading_false_hidesGeneratingExplanation() throws {
    let popover = WhyGeneratedPopover(
      fileName: "Gen.swift",
      explanation: .constant(nil),
      reason: .constant(nil),
      isLoading: .constant(false)
    )
    let body = String(reflecting: popover.body)
    #expect(!body.contains("Generating explanation..."))
  }
}
