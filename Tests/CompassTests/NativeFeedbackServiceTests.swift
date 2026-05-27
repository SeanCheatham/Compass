import Foundation
import Testing

@testable import Compass

struct NativeFeedbackServiceTests {
  @Test func testContentBoundsProjectNameAndCopy() {
    let boundedProjectName = String(repeating: "A", count: NativeFeedbackContent.projectNameLimit)
    let content = NativeFeedbackContent(
      milestone: .developStarted,
      projectName: "  \(String(repeating: "A", count: 80))  "
    )

    #require(content.projectName == boundedProjectName)
    #require(content.title == "\(boundedProjectName): Develop started")
    #require(content.body == "Agent is working on the selected plan.")
    #require(content.spokenPhrase == "\(boundedProjectName). Develop started.")
    #require(content.projectName.count <= NativeFeedbackContent.projectNameLimit)
    #require(content.title.count <= NativeFeedbackContent.titleLimit)
    #require(content.body.count <= NativeFeedbackContent.bodyLimit)
    #require(content.spokenPhrase.count <= NativeFeedbackContent.spokenPhraseLimit)

    let fallback = NativeFeedbackContent(milestone: .paused, projectName: " \n ")
    #require(fallback.projectName == "Compass project")
    #require(fallback.title == "Compass project: Paused")
  }

  @Test func testLongRunningMilestoneCopy() {
    let verify = NativeFeedbackContent(milestone: .verifyStarted, projectName: "Editor")
    #require(verify.title == "Editor: Verify started")
    #require(verify.body == "Compass is running the verify command.")
    #require(verify.spokenPhrase == "Editor. Verify started.")

    let retry = NativeFeedbackContent(milestone: .developRetrying, projectName: "Editor")
    #require(retry.title == "Editor: Develop retrying")
    #require(retry.body == "Post-checks need another agent pass.")
    #require(retry.spokenPhrase == "Editor. Develop retrying.")
  }

  @MainActor
  @Test func testDevelopReadyDeliverySnapshotCorrelatesWithoutAuthorizationInOffMode() {
    let service = NativeFeedbackService.shared
    let before = service.deliverySnapshot(mode: .off)

    service.emit(
      .developReady,
      projectName: "Editor",
      mode: .off,
      content: NativeFeedbackContent(milestone: .developReady, projectName: "Editor")
    )
    let after = service.deliverySnapshot(mode: .off)

    #require(
      after.lastAttemptedMilestoneIdentifier == NativeFeedbackMilestone.developReady.rawValue)
    #require(after.lastAttemptResultIdentifier == "suppressed-off")
    #require(
      after.authorizationRequestStateIdentifier == before.authorizationRequestStateIdentifier)
    #require(
      after.notificationAuthorizationStatusIdentifier ==
      before.notificationAuthorizationStatusIdentifier)
  }

  @Test func testModeMenuSelectedStateAndOrder() {
    let menu = NativeFeedbackModeMenu(selectedMode: .speechAndNotifications, projectName: "Editor")

    #require(menu.labelSystemImage == "speaker.wave.2")
    #require(menu.helpText == "Feedback: Speech + Notifications")
    #require(menu.items.map(\.mode) == [.off, .notifications, .speechAndNotifications])
    #require(menu.items.map(\.title) == ["Off", "Notifications", "Speech + Notifications"])
    #require(menu.items.map(\.systemImage) == ["bell.slash", "bell", "checkmark"])
    #require(menu.items.map(\.isSelected) == [false, false, true])
  }

  @Test func testModeMenuProjectScopedCopyIsBounded() {
    let rawProjectName = "  \(String(repeating: "Compass Factory ", count: 8))  "
    let projectName = NativeFeedbackContent.sanitizedProjectName(rawProjectName)
    let menu = NativeFeedbackModeMenu(selectedMode: .notifications, projectName: rawProjectName)

    #require(menu.projectName == projectName)
    let descriptions = menu.items.map(\.description)
    #require(descriptions == [
      "No macOS alerts or spoken updates for \(projectName).",
      "Show macOS banners when \(projectName) reaches plan, verify, or promotion milestones.",
      "Speak updates for \(projectName) and show macOS banners for key milestones.",
    ])
    #require(menu.items.allSatisfy { $0.description.contains(projectName) })
    #require(menu.items.allSatisfy { $0.permissionHint.contains(projectName) })
    #require(
      menu.items.allSatisfy {
        $0.description.count <= NativeFeedbackModeMenuItem.descriptionLimit
          && $0.permissionHint.count <= NativeFeedbackModeMenuItem.permissionHintLimit
      })
  }

  @Test func testModeMenuPermissionHintsExplainAuthorizationTiming() {
    let menu = NativeFeedbackModeMenu(selectedMode: .off, projectName: "Editor")
    let hints = Dictionary(uniqueKeysWithValues: menu.items.map { ($0.mode, $0.permissionHint) })

    #require(hints[.off] == "No notification permission request for Editor.")
    #require(
      hints[.notifications],
      "Compass asks notification permission for Editor only when enabled or first delivered."
    )
    #require(
      hints[.speechAndNotifications],
      "Speech uses local audio; notifications for Editor ask permission only when needed."
    )
  }

  @Test func testDeliverySnapshotBoundsIdentifiersAndDedupeCount() {
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

    #require(
      snapshot.notificationSupportIdentifier.count <=
      NativeFeedbackDeliverySnapshot.identifierLimit
    )
    #require(
      snapshot.authorizationRequestStateIdentifier.count <=
      NativeFeedbackDeliverySnapshot.identifierLimit
    )
    #require(
      snapshot.notificationAuthorizationStatusIdentifier.count <=
      NativeFeedbackDeliverySnapshot.identifierLimit
    )
    #require(
      snapshot.lastAttemptedMilestoneIdentifier.count <=
      NativeFeedbackDeliverySnapshot.identifierLimit
    )
    #require(
      snapshot.lastAttemptResultIdentifier.count <=
      NativeFeedbackDeliverySnapshot.identifierLimit
    )
    #require(
      snapshot.speechStateIdentifier.count <=
      NativeFeedbackDeliverySnapshot.identifierLimit
    )
    #require(
      snapshot.recentDedupeCount == NativeFeedbackDeliverySnapshot.recentDedupeCountLimit)
    #require(!snapshot.identifier.contains("Compass has accepted"))
  }

  @Test func testModeMenuSurfacesInjectedDeliveryStatusAndBoundsIt() {
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

    #require(
      menu.deliveryStatusText.count <=
      NativeFeedbackDeliverySnapshot.menuStatusLimit
    )
    #require(menu.deliveryStatusText.contains("mode speech_and_notifications"))
    #require(menu.deliveryStatusText.contains("notifications"))
    #require(menu.deliveryStatusText.contains("speech"))
    #require(menu.deliveryStatusText.contains("notification-status allowed"))
    #require(menu.deliveryStatusText.contains("last verifyStarted/notification-delivered"))
    #require(menu.deliveryStatusText.contains("speech suppressed-speaking"))
  }

  @MainActor
  @Test func testReadOnlySnapshotDoesNotRequestNotificationAuthorization() {
    let service = NativeFeedbackService.shared
    let before = service.deliverySnapshot(mode: .notifications)

    _ = NativeFeedbackModeMenu(
      selectedMode: .notifications,
      projectName: "Editor",
      deliverySnapshot: before
    )
    let after = service.deliverySnapshot(mode: .notifications)

    #require(
      after.authorizationRequestStateIdentifier == before.authorizationRequestStateIdentifier);
    #require(
      after.notificationAuthorizationStatusIdentifier ==
      before.notificationAuthorizationStatusIdentifier)
    #require(after.lastAttemptedMilestoneIdentifier == before.lastAttemptedMilestoneIdentifier)
  }
}