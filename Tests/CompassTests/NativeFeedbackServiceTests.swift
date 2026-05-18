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
        let menu = NativeFeedbackModeMenu(selectedMode: .speechAndNotifications)

        XCTAssertEqual(menu.labelSystemImage, "speaker.wave.2")
        XCTAssertEqual(menu.helpText, "Feedback: Speech + Notifications")
        XCTAssertEqual(menu.items.map(\.mode), [.off, .notifications, .speechAndNotifications])
        XCTAssertEqual(menu.items.map(\.title), ["Off", "Notifications", "Speech + Notifications"])
        XCTAssertEqual(menu.items.map(\.systemImage), ["bell.slash", "bell", "checkmark"])
        XCTAssertEqual(menu.items.map(\.isSelected), [false, false, true])
    }
}
