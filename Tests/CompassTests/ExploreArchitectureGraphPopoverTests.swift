import Foundation
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
}
