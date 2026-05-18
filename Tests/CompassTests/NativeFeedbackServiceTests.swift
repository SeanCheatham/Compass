@testable import Compass
import XCTest

final class NativeFeedbackServiceTests: XCTestCase {
    func testContentBoundsProjectNameAndCopy() {
        let boundedProjectName = String(repeating: "A", count: NativeFeedbackContent.projectNameLimit)
        let content = NativeFeedbackContent(
            milestone: .developStarted,
            projectName: "  \(String(repeating: "A", count: 80))  "
        )

        XCTAssertEqual(content.projectName, boundedProjectName)
        XCTAssertEqual(content.title, "\(boundedProjectName): Develop started")
        XCTAssertEqual(content.body, "Codex is working on the selected plan.")
        XCTAssertEqual(content.spokenPhrase, "\(boundedProjectName). Develop started.")
        XCTAssertLessThanOrEqual(content.projectName.count, NativeFeedbackContent.projectNameLimit)
        XCTAssertLessThanOrEqual(content.title.count, NativeFeedbackContent.titleLimit)
        XCTAssertLessThanOrEqual(content.body.count, NativeFeedbackContent.bodyLimit)
        XCTAssertLessThanOrEqual(content.spokenPhrase.count, NativeFeedbackContent.spokenPhraseLimit)

        let fallback = NativeFeedbackContent(milestone: .paused, projectName: " \n ")
        XCTAssertEqual(fallback.projectName, "Compass project")
        XCTAssertEqual(fallback.title, "Compass project: Paused")
    }

    func testLongRunningMilestoneCopy() {
        let verify = NativeFeedbackContent(milestone: .verifyStarted, projectName: "Editor")
        XCTAssertEqual(verify.title, "Editor: Verify started")
        XCTAssertEqual(verify.body, "Compass is running the verify command.")
        XCTAssertEqual(verify.spokenPhrase, "Editor. Verify started.")

        let retry = NativeFeedbackContent(milestone: .developRetrying, projectName: "Editor")
        XCTAssertEqual(retry.title, "Editor: Develop retrying")
        XCTAssertEqual(retry.body, "Post-checks need another Codex pass.")
        XCTAssertEqual(retry.spokenPhrase, "Editor. Develop retrying.")
    }

    func testDevelopReadyContentCanBeDerivedFromReadinessAndStaysBounded() {
        let state = PlanState(
            completed: ["Mapped native feedback readiness"],
            immediate: PlanNext(
                plan: "Wait for the Develop gate",
                verify: "swift test",
                verifyTimeoutMs: 120_000,
                estimatedDifficulty: .medium
            ),
            midTerm: "",
            longTerm: ""
        )
        let plan = CinematicPlanCompassPlan(state: state)
        let readiness = CinematicPlanCompassReadinessPlan(
            state: state,
            planCompassPlan: plan,
            reliabilityFeedback: PlanReliabilityFeedback(state: state, sessions: [])
        )
        let content = NativeFeedbackContent(readinessPlan: readiness, projectName: "Editor")

        XCTAssertEqual(content.projectName, "Editor")
        XCTAssertEqual(content.title, "Editor: Ready for Develop")
        XCTAssertTrue(content.body.contains("Prove: swift test"))
        XCTAssertTrue(content.body.contains("Timeout 2m"))
        XCTAssertTrue(content.body.contains("Medium"))
        XCTAssertTrue(content.body.contains("warnings clear"))
        XCTAssertTrue(content.body.contains("retry none"))
        XCTAssertTrue(content.body.contains("1 completed iteration"))
        XCTAssertLessThanOrEqual(content.title.count, NativeFeedbackContent.titleLimit)
        XCTAssertLessThanOrEqual(content.body.count, NativeFeedbackContent.bodyLimit)
        XCTAssertLessThanOrEqual(content.spokenPhrase.count, NativeFeedbackContent.spokenPhraseLimit)

        let generic = NativeFeedbackContent(milestone: .developReady, projectName: "Editor")
        XCTAssertEqual(generic.title, "Editor: Develop ready")
        XCTAssertEqual(generic.body, "The accepted plan is waiting at the Develop gate.")
    }

    @MainActor
    func testDevelopReadyDeliverySnapshotCorrelatesWithoutAuthorizationInOffMode() {
        let service = NativeFeedbackService.shared
        let before = service.deliverySnapshot(mode: .off)

        service.emit(
            .developReady,
            projectName: "Editor",
            mode: .off,
            content: NativeFeedbackContent(milestone: .developReady, projectName: "Editor")
        )
        let after = service.deliverySnapshot(mode: .off)

        XCTAssertEqual(after.lastAttemptedMilestoneIdentifier, NativeFeedbackMilestone.developReady.rawValue)
        XCTAssertEqual(after.lastAttemptResultIdentifier, "suppressed-off")
        XCTAssertEqual(after.authorizationRequestStateIdentifier, before.authorizationRequestStateIdentifier)
        XCTAssertEqual(after.notificationAuthorizationStatusIdentifier, before.notificationAuthorizationStatusIdentifier)
    }

    func testModeMenuSelectedStateAndOrder() {
        let menu = NativeFeedbackModeMenu(selectedMode: .speechAndNotifications, projectName: "Editor")

        XCTAssertEqual(menu.labelSystemImage, "speaker.wave.2")
        XCTAssertEqual(menu.helpText, "Feedback: Speech + Notifications")
        XCTAssertEqual(menu.items.map(\.mode), [.off, .notifications, .speechAndNotifications])
        XCTAssertEqual(menu.items.map(\.title), ["Off", "Notifications", "Speech + Notifications"])
        XCTAssertEqual(menu.items.map(\.systemImage), ["bell.slash", "bell", "checkmark"])
        XCTAssertEqual(menu.items.map(\.isSelected), [false, false, true])
    }

    func testModeMenuProjectScopedCopyIsBounded() {
        let rawProjectName = "  \(String(repeating: "Compass Factory ", count: 8))  "
        let projectName = NativeFeedbackContent.sanitizedProjectName(rawProjectName)
        let menu = NativeFeedbackModeMenu(selectedMode: .notifications, projectName: rawProjectName)

        XCTAssertEqual(menu.projectName, projectName)
        XCTAssertEqual(
            menu.items.map(\.description),
            [
                "No macOS alerts or spoken updates for \(projectName).",
                "Show macOS banners when \(projectName) reaches plan, verify, or promotion milestones.",
                "Speak updates for \(projectName) and show macOS banners for key milestones."
            ]
        )
        XCTAssertTrue(menu.items.allSatisfy { $0.description.contains(projectName) })
        XCTAssertTrue(menu.items.allSatisfy { $0.permissionHint.contains(projectName) })
        XCTAssertTrue(menu.items.allSatisfy {
            $0.description.count <= NativeFeedbackModeMenuItem.descriptionLimit
                && $0.permissionHint.count <= NativeFeedbackModeMenuItem.permissionHintLimit
        })
    }

    func testModeMenuPermissionHintsExplainAuthorizationTiming() {
        let menu = NativeFeedbackModeMenu(selectedMode: .off, projectName: "Editor")
        let hints = Dictionary(uniqueKeysWithValues: menu.items.map { ($0.mode, $0.permissionHint) })

        XCTAssertEqual(hints[.off], "No notification permission request for Editor.")
        XCTAssertEqual(
            hints[.notifications],
            "Compass asks notification permission for Editor only when enabled or first delivered."
        )
        XCTAssertEqual(
            hints[.speechAndNotifications],
            "Speech uses local audio; notifications for Editor ask permission only when needed."
        )
    }

    func testDeliverySnapshotBoundsIdentifiersAndDedupeCount() {
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

        XCTAssertLessThanOrEqual(
            snapshot.notificationSupportIdentifier.count,
            NativeFeedbackDeliverySnapshot.identifierLimit
        )
        XCTAssertLessThanOrEqual(
            snapshot.authorizationRequestStateIdentifier.count,
            NativeFeedbackDeliverySnapshot.identifierLimit
        )
        XCTAssertLessThanOrEqual(
            snapshot.notificationAuthorizationStatusIdentifier.count,
            NativeFeedbackDeliverySnapshot.identifierLimit
        )
        XCTAssertLessThanOrEqual(
            snapshot.lastAttemptedMilestoneIdentifier.count,
            NativeFeedbackDeliverySnapshot.identifierLimit
        )
        XCTAssertLessThanOrEqual(
            snapshot.lastAttemptResultIdentifier.count,
            NativeFeedbackDeliverySnapshot.identifierLimit
        )
        XCTAssertLessThanOrEqual(
            snapshot.speechStateIdentifier.count,
            NativeFeedbackDeliverySnapshot.identifierLimit
        )
        XCTAssertEqual(snapshot.recentDedupeCount, NativeFeedbackDeliverySnapshot.recentDedupeCountLimit)
        XCTAssertFalse(snapshot.identifier.contains("Compass has accepted"))
    }

    func testModeMenuSurfacesInjectedDeliveryStatusAndBoundsIt() {
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

        XCTAssertLessThanOrEqual(
            menu.deliveryStatusText.count,
            NativeFeedbackDeliverySnapshot.menuStatusLimit
        )
        XCTAssertTrue(menu.deliveryStatusText.contains("mode speech_and_notifications"))
        XCTAssertTrue(menu.deliveryStatusText.contains("notifications"))
        XCTAssertTrue(menu.deliveryStatusText.contains("speech"))
        XCTAssertTrue(menu.deliveryStatusText.contains("notification-status allowed"))
        XCTAssertTrue(menu.deliveryStatusText.contains("last verifyStarted/notification-delivered"))
        XCTAssertTrue(menu.deliveryStatusText.contains("speech suppressed-speaking"))
    }

    @MainActor
    func testReadOnlySnapshotDoesNotRequestNotificationAuthorization() {
        let service = NativeFeedbackService.shared
        let before = service.deliverySnapshot(mode: .notifications)

        _ = NativeFeedbackModeMenu(
            selectedMode: .notifications,
            projectName: "Editor",
            deliverySnapshot: before
        )
        let after = service.deliverySnapshot(mode: .notifications)

        XCTAssertEqual(after.authorizationRequestStateIdentifier, before.authorizationRequestStateIdentifier)
        XCTAssertEqual(after.notificationAuthorizationStatusIdentifier, before.notificationAuthorizationStatusIdentifier)
        XCTAssertEqual(after.lastAttemptedMilestoneIdentifier, before.lastAttemptedMilestoneIdentifier)
    }
}
