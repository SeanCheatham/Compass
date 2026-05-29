import Foundation
import Testing

@testable import Compass

struct NativeFeedbackServiceTests {
  @Test func testContentBoundsProjectNameAndCopy() throws {
    let boundedProjectName = String(repeating: "A", count: NativeFeedbackContent.projectNameLimit)
    let content = NativeFeedbackContent(
      milestone: .developStarted,
      projectName: "  \(String(repeating: "A", count: 80))  "
    )

    try #require(content.projectName == boundedProjectName)
    try #require(content.title == "\(boundedProjectName): Develop started")
    try #require(content.body == "Agent is working on the selected plan.")
    try #require(content.spokenPhrase == "\(boundedProjectName). Develop started.")
    try #require(content.projectName.count <= NativeFeedbackContent.projectNameLimit)
    try #require(content.title.count <= NativeFeedbackContent.titleLimit)
    try #require(content.body.count <= NativeFeedbackContent.bodyLimit)
    try #require(content.spokenPhrase.count <= NativeFeedbackContent.spokenPhraseLimit)

    let fallback = NativeFeedbackContent(milestone: .paused, projectName: " \n ")
    try #require(fallback.projectName == "Compass project")
    try #require(fallback.title == "Compass project: Paused")
  }

  @Test func testLongRunningMilestoneCopy() throws {
    let verify = NativeFeedbackContent(milestone: .verifyStarted, projectName: "Editor")
    try #require(verify.title == "Editor: Verify started")
    try #require(verify.body == "Compass is running the verify command.")
    try #require(verify.spokenPhrase == "Editor. Verify started.")

    let retry = NativeFeedbackContent(milestone: .developRetrying, projectName: "Editor")
    try #require(retry.title == "Editor: Develop retrying")
    try #require(retry.body == "Post-checks need another agent pass.")
    try #require(retry.spokenPhrase == "Editor. Develop retrying.")
  }

  @MainActor
  @Test func testDevelopReadyDeliverySnapshotCorrelatesWithoutAuthorizationInOffMode() throws {
    let service = NativeFeedbackService.shared
    let before = service.deliverySnapshot(mode: .off)

    service.emit(
      .developReady,
      projectName: "Editor",
      mode: .off,
      content: NativeFeedbackContent(milestone: .developReady, projectName: "Editor")
    )
    let after = service.deliverySnapshot(mode: .off)

    try #require(
      after.lastAttemptedMilestoneIdentifier == NativeFeedbackMilestone.developReady.rawValue)
    try #require(after.lastAttemptResultIdentifier == "suppressed-off")
    try #require(
      after.authorizationRequestStateIdentifier == before.authorizationRequestStateIdentifier)
    try #require(
      after.notificationAuthorizationStatusIdentifier
        == before.notificationAuthorizationStatusIdentifier)
  }

  @Test func testModeMenuSelectedStateAndOrder() throws {
    let menu = NativeFeedbackModeMenu(selectedMode: .speechAndNotifications, projectName: "Editor")

    try #require(menu.labelSystemImage == "speaker.wave.2")
    try #require(menu.helpText == "Feedback: Speech + Notifications")
    try #require(menu.items.map(\.mode) == [.off, .notifications, .speechAndNotifications])
    try #require(menu.items.map(\.title) == ["Off", "Notifications", "Speech + Notifications"])
    try #require(menu.items.map(\.systemImage) == ["bell.slash", "bell", "checkmark"])
    try #require(menu.items.map(\.isSelected) == [false, false, true])
  }

  @Test func testModeMenuProjectScopedCopyIsBounded() throws {
    let rawProjectName = "  \(String(repeating: "Compass Factory ", count: 8))  "
    let projectName = NativeFeedbackContent.sanitizedProjectName(rawProjectName)
    let menu = NativeFeedbackModeMenu(selectedMode: .notifications, projectName: rawProjectName)

    try #require(menu.projectName == projectName)
    let descriptions = menu.items.map(\.description)
    try #require(
      descriptions == [
        "No macOS alerts or spoken updates for \(projectName).",
        "Show macOS banners when \(projectName) reaches plan, verify, or promotion milestones.",
        "Speak updates for \(projectName) and show macOS banners for key milestones.",
      ])
    try #require(menu.items.allSatisfy { $0.description.contains(projectName) })
    try #require(menu.items.allSatisfy { $0.permissionHint.contains(projectName) })
    try #require(
      menu.items.allSatisfy {
        $0.description.count <= NativeFeedbackModeMenuItem.descriptionLimit
          && $0.permissionHint.count <= NativeFeedbackModeMenuItem.permissionHintLimit
      })
  }

  @Test func testModeMenuPermissionHintsExplainAuthorizationTiming() throws {
    let menu = NativeFeedbackModeMenu(selectedMode: .off, projectName: "Editor")
    let hints = Dictionary(uniqueKeysWithValues: menu.items.map { ($0.mode, $0.permissionHint) })

    try #require(hints[.off] == "No notification permission request for Editor.")
    try #require(
      hints[.notifications],
      "Compass asks notification permission for Editor only when enabled or first delivered."
    )
    try #require(
      hints[.speechAndNotifications],
      "Speech uses local audio; notifications for Editor ask permission only when needed."
    )
  }

  @Test func testDeliverySnapshotBoundsIdentifiersAndDedupeCount() throws {
    let longIdentifier = String(repeating: "native-feedback-delivery-status-", count: 8)
    let snapshot = NativeFeedbackDeliverySnapshot(
      mode: .speechAndNotifications,
      notificationSupportIdentifier: longIdentifier,
      authorizationRequestStateIdentifier: longIdentifier,
      notificationAuthorizationStatusIdentifier: longIdentifier,
      notificationsAllowed: true,
      recentDedupeCount: 1_000,
      lastAttemptedMilestoneIdentifier: longIdentifier,
      lastAttemptResultIdentifier: longIdentifier,
      speechStateIdentifier: longIdentifier
    )

    try #require(
      snapshot.notificationSupportIdentifier.count <= NativeFeedbackDeliverySnapshot.identifierLimit
    )
    try #require(
      snapshot.authorizationRequestStateIdentifier.count
        <= NativeFeedbackDeliverySnapshot.identifierLimit
    )
    try #require(
      snapshot.notificationAuthorizationStatusIdentifier.count
        <= NativeFeedbackDeliverySnapshot.identifierLimit
    )
    try #require(
      snapshot.lastAttemptedMilestoneIdentifier.count
        <= NativeFeedbackDeliverySnapshot.identifierLimit
    )
    try #require(
      snapshot.lastAttemptResultIdentifier.count <= NativeFeedbackDeliverySnapshot.identifierLimit
    )
    try #require(
      snapshot.speechStateIdentifier.count <= NativeFeedbackDeliverySnapshot.identifierLimit
    )
    try #require(
      snapshot.recentDedupeCount == NativeFeedbackDeliverySnapshot.recentDedupeCountLimit)
    try #require(!snapshot.identifier.contains("Compass has accepted"))
  }

  @Test func testModeMenuSurfacesInjectedDeliveryStatusAndBoundsIt() throws {
    let snapshot = NativeFeedbackDeliverySnapshot(
      mode: .speechAndNotifications,
      notificationSupportIdentifier: "available",
      authorizationRequestStateIdentifier: "requested",
      notificationAuthorizationStatusIdentifier: "allowed",
      notificationsAllowed: true,
      recentDedupeCount: 7,
      lastAttemptedMilestoneIdentifier: "verifyStarted",
      lastAttemptResultIdentifier: "notification-delivered",
      speechStateIdentifier: "suppressed-speaking"
    )
    let menu = NativeFeedbackModeMenu(
      selectedMode: .speechAndNotifications,
      projectName: "Editor",
      deliverySnapshot: snapshot
    )

    try #require(
      menu.deliveryStatusText.count <= NativeFeedbackDeliverySnapshot.menuStatusLimit
    )
    try #require(menu.deliveryStatusText.contains("mode speech_and_notifications"))
    try #require(menu.deliveryStatusText.contains("notifications"))
    try #require(menu.deliveryStatusText.contains("speech"))
    try #require(menu.deliveryStatusText.contains("notification-status allowed"))
    try #require(menu.deliveryStatusText.contains("last verifyStarted/notification-delivered"))
    try #require(menu.deliveryStatusText.contains("speech suppressed-speaking"))
  }

  @MainActor
  @Test func testReadOnlySnapshotDoesNotRequestNotificationAuthorization() throws {
    let service = NativeFeedbackService.shared
    let before = service.deliverySnapshot(mode: .notifications)

    _ = NativeFeedbackModeMenu(
      selectedMode: .notifications,
      projectName: "Editor",
      deliverySnapshot: before
    )
    let after = service.deliverySnapshot(mode: .notifications)

    try #require(
      after.authorizationRequestStateIdentifier == before.authorizationRequestStateIdentifier)
    try #require(
      after.notificationAuthorizationStatusIdentifier
        == before.notificationAuthorizationStatusIdentifier)
    try #require(after.lastAttemptedMilestoneIdentifier == before.lastAttemptedMilestoneIdentifier)
  }
}
