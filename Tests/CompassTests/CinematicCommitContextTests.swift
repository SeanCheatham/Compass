import Foundation
@testable import Compass
import XCTest

final class CinematicCommitContextTests: XCTestCase {
    func testLatestSubjectUsesNewestSessionAndNewestCommit() {
        let sessions = [
            makeSession(
                1,
                startedAt: 100,
                endedAt: 200,
                commits: [makeCommit(subject: "Old navigation pass")]
            ),
            makeSession(
                3,
                startedAt: 300,
                endedAt: 400,
                commits: [
                    makeCommit(subject: "Older commit in newest session"),
                    makeCommit(subject: "Ship commit-aware cinematic copy")
                ]
            ),
            makeSession(
                2,
                startedAt: 200,
                endedAt: 300,
                commits: [makeCommit(subject: "Middle session copy")]
            )
        ]

        XCTAssertEqual(
            CinematicCommitContext.latestSubject(from: sessions),
            "Ship commit-aware cinematic copy"
        )
    }

    func testLatestSubjectOnlyConsidersRecentSessions() {
        let sessions = (1...9).map { number in
            makeSession(
                number,
                startedAt: Double(number),
                endedAt: Double(number),
                commits: number == 1 ? [makeCommit(subject: "Too old for cinematic copy")] : []
            )
        }

        XCTAssertNil(CinematicCommitContext.latestSubject(from: sessions))
    }

    func testDisplaySubjectSanitizesAndBoundsUnsafeCommitText() throws {
        let subject = try XCTUnwrap(
            CinematicCommitContext.displaySubject(
                from: #"Add [unsafe] `HUD` {"json":true} details at https://example.com with a deliberately overflowing subject line"#
            )
        )

        XCTAssertLessThanOrEqual(subject.count, CinematicCommitContext.subjectMaxCharacters)
        XCTAssertFalse(subject.contains("https://"))
        XCTAssertFalse(subject.contains("["))
        XCTAssertFalse(subject.contains("]"))
        XCTAssertFalse(subject.contains("`"))
        XCTAssertFalse(subject.contains("{"))
        XCTAssertFalse(subject.contains("}"))
        XCTAssertFalse(subject.contains("\""))
        XCTAssertTrue(subject.hasPrefix("Add unsafe HUD json:true details at"))
    }
}

private func makeSession(
    _ number: Int,
    startedAt: Double,
    endedAt: Double?,
    commits: [SessionCommit]
) -> SessionRecord {
    SessionRecord(
        session: number,
        startedAt: startedAt,
        endedAt: endedAt,
        plan: nil,
        verify: nil,
        beforeSha: nil,
        afterSha: nil,
        commits: commits,
        status: .succeeded,
        notes: [],
        verifyOutput: nil,
        feedback: nil
    )
}

private func makeCommit(subject: String) -> SessionCommit {
    let checksum = subject.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % 1_000_000 }
    let short = String(("0000000" + String(checksum)).suffix(7))
    return SessionCommit(
        sha: "abcdef\(short)",
        short: short,
        subject: subject
    )
}
