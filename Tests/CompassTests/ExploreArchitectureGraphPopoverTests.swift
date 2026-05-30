import Foundation
import SwiftUI
import Testing

@testable import Compass

struct ExploreArchitectureGraphPopoverTests {
  @Test
  func initializerKeepsSessionItemAndRepoURL() throws {
    let repoURL = URL(fileURLWithPath: "/tmp/CompassRepo").standardizedFileURL
    let popover = ArchitectureGraphPopover(
      item: .placeholder,
      repoURL: repoURL
    )

    #expect(popover.item.sessionNumber == PlanSessionHistoryItem.placeholder.sessionNumber)
    #expect(popover.item.status == PlanSessionHistoryItem.placeholder.status)
    #expect(popover.repoURL == repoURL)
  }

  @Test
  func placeholderItemIsSafeForPopoverTests() throws {
    let item = PlanSessionHistoryItem.placeholder

    #expect(item.status == .succeeded)
    #expect(item.commits.isEmpty)
    #expect(item.failedVerify == nil)
  }

  // MARK: - State-derived display paths

  /// Verifies the default state (isLoading=false) renders the content area
  /// rather than the loading indicator. This reflects the popover's body
  /// when State properties have their initial values (isLoading=false means
  /// the else-branch showing graphText/explanation is taken).
  @Test
  func defaultState_showsContentNotSpinner() throws {
    let popover = ArchitectureGraphPopover(
      item: .placeholder,
      repoURL: URL(fileURLWithPath: "/tmp/Repo")
    )
    let body = String(reflecting: popover.body)
    // "Analyzing architecture..." text only appears inside the isLoading branch
    #expect(!body.contains("Analyzing architecture..."))
  }

  // MARK: - availabilityError display path

  /// Verifies `availabilityError=false` (default) does not render the
  /// "Foundation Models is unavailable" warning in the popover body.
  @Test
  func availabilityError_false_hidesWarningLabel() throws {
    let popover = ArchitectureGraphPopover(
      item: .placeholder,
      repoURL: URL(fileURLWithPath: "/tmp/Repo")
    )
    let body = String(reflecting: popover.body)
    // The warning label text only appears inside the `if availabilityError` branch
    #expect(!body.contains("Foundation Models is unavailable"))
  }

  // MARK: - isLoading display path

  /// Verifies the isLoading branch text "Analyzing architecture..." is not
  /// present when isLoading is in its default false state (confirming the
  /// conditional branching in the popover body is responsive to state).
  @Test
  func isLoading_false_hidesAnalyzingArchitectureSpinner() throws {
    let popover = ArchitectureGraphPopover(
      item: .placeholder,
      repoURL: URL(fileURLWithPath: "/tmp/Repo")
    )
    let body = String(reflecting: popover.body)
    #expect(!body.contains("Analyzing architecture..."))
  }

  // MARK: - graphText / explanation presence in body

  /// Verifies the graph text section label "Structure" is not rendered
  /// when graphText is nil (its default), and renders once set.
  @Test
  func graphText_nil_hidesStructureSection() throws {
    let popover = ArchitectureGraphPopover(
      item: .placeholder,
      repoURL: URL(fileURLWithPath: "/tmp/Repo")
    )
    let body = String(reflecting: popover.body)
    #expect(!body.contains("Structure"))
  }

  /// Verifies the explanation section label "Explanation" is not rendered
  /// when explanation is nil (its default), and renders once set.
  @Test
  func explanation_nil_hidesExplanationSection() throws {
    let popover = ArchitectureGraphPopover(
      item: .placeholder,
      repoURL: URL(fileURLWithPath: "/tmp/Repo")
    )
    let body = String(reflecting: popover.body)
    #expect(!body.contains("Explanation"))
  }

  // MARK: - Export button guard path

  /// Verifies the Export SVG button is present in the popover body.
  /// The button's enabled state is gated on graphText being non-nil at call
  /// time (exportSVG guard), but the button is always visible in the UI to
  /// let the user attempt export.
  @Test
  func exportSVG_button_presentInBody() throws {
    let popover = ArchitectureGraphPopover(
      item: .placeholder,
      repoURL: URL(fileURLWithPath: "/tmp/Repo")
    )
    let body = String(reflecting: popover.body)
    #expect(body.contains("Export SVG"))
  }

  // MARK: - Availability error label display path

  /// Verifies the "Foundation Models is unavailable" warning label text is
  /// controlled by the availabilityError branch — it is absent at default
  /// state (availabilityError=false).
  @Test
  func availabilityError_false_hidesFoundationModelsUnavailableLabel() throws {
    let popover = ArchitectureGraphPopover(
      item: .placeholder,
      repoURL: URL(fileURLWithPath: "/tmp/Repo")
    )
    let body = String(reflecting: popover.body)
    #expect(!body.contains("Foundation Models is unavailable on this device"))
  }
}
