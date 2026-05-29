import SwiftUI
import Testing

@testable import Compass

struct ExploreWhyGeneratedPopoverTests {
  @Test
  func initializerKeepsFileNameAndLoadingBinding() throws {
    let popover = WhyGeneratedPopover(
      fileName: "GeneratedFile.swift",
      explanation: .constant(nil),
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
    }

    let box = BindingBox()
    var popover = WhyGeneratedPopover(
      fileName: "GeneratedFile.swift",
      explanation: Binding(
        get: { box.explanation },
        set: { box.explanation = $0 }
      ),
      isLoading: Binding(
        get: { box.isLoading },
        set: { box.isLoading = $0 }
      )
    )

    popover.explanation = "Done."
    popover.isLoading = false

    #expect(box.explanation == "Done.")
    #expect(!box.isLoading)
  }
}
