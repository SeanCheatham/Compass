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
}
