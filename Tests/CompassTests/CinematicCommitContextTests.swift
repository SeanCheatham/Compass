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

    func testConstellationUsesNewestSixSanitizedCommitsInDisplayOrder() {
        let sessions = [
            makeSession(
                1,
                startedAt: 100,
                endedAt: 150,
                commits: [
                    makeCommit(subject: "Commit 1"),
                    makeCommit(subject: "Commit 2"),
                    makeCommit(subject: "Commit 3")
                ]
            ),
            makeSession(
                2,
                startedAt: 200,
                endedAt: 250,
                commits: [
                    makeCommit(subject: "Commit 4"),
                    makeCommit(subject: "Commit 5")
                ]
            ),
            makeSession(
                3,
                startedAt: 300,
                endedAt: 350,
                commits: [
                    makeCommit(subject: "Commit 6"),
                    makeCommit(subject: "Commit 7"),
                    makeCommit(subject: "Commit 8")
                ]
            )
        ]

        let plan = CinematicCommitConstellationPlan(sessions: sessions)

        XCTAssertEqual(plan.count, CinematicCommitConstellationPlan.maxCommitCount)
        XCTAssertEqual(
            plan.nodes.map(\.subject),
            ["Commit 8", "Commit 7", "Commit 6", "Commit 5", "Commit 4", "Commit 3"]
        )
        XCTAssertEqual(plan.newestSubject, "Commit 8")
        XCTAssertEqual(plan.branchSegments.count, 5)
        XCTAssertEqual(plan.branchSegments.first?.fromNodeID, plan.nodes[1].stableID)
        XCTAssertEqual(plan.branchSegments.first?.toNodeID, plan.nodes[0].stableID)
        XCTAssertTrue(plan.identifier.contains(plan.nodes[0].stableID))
        XCTAssertTrue(plan.identifier.contains(plan.branchSegments[0].stableID))
    }

    func testConstellationNodePositionsStayInsideSceneBounds() {
        let plan = CinematicCommitConstellationPlan(
            sessions: [
                makeSession(
                    1,
                    startedAt: 100,
                    endedAt: 200,
                    commits: (1...6).map { makeCommit(subject: "Bounded commit \($0)") }
                )
            ]
        )

        XCTAssertEqual(plan.nodes.count, 6)
        for node in plan.nodes {
            XCTAssertInRange(node.position.x, CinematicCommitConstellationPlan.positionXRange)
            XCTAssertInRange(node.position.y, CinematicCommitConstellationPlan.positionYRange)
            XCTAssertInRange(node.position.z, CinematicCommitConstellationPlan.positionZRange)
        }
        for branch in plan.branchSegments {
            XCTAssertInRange(branch.startPosition.x, CinematicCommitConstellationPlan.positionXRange)
            XCTAssertInRange(branch.endPosition.x, CinematicCommitConstellationPlan.positionXRange)
        }
    }

    func testConstellationSanitizesSubjectsBeforeLabeling() throws {
        let plan = CinematicCommitConstellationPlan(
            sessions: [
                makeSession(
                    1,
                    startedAt: 100,
                    endedAt: 200,
                    commits: [
                        makeCommit(
                            subject: #"Ship [unsafe] `constellation` {"payload":true} at https://example.com with a deliberately long title"#
                        )
                    ]
                )
            ]
        )

        let node = try XCTUnwrap(plan.nodes.first)

        XCTAssertLessThanOrEqual(node.subject.count, CinematicCommitContext.subjectMaxCharacters)
        XCTAssertFalse(node.subject.contains("https://"))
        XCTAssertFalse(node.subject.contains("["))
        XCTAssertFalse(node.subject.contains("]"))
        XCTAssertFalse(node.subject.contains("`"))
        XCTAssertFalse(node.subject.contains("{"))
        XCTAssertFalse(node.subject.contains("}"))
        XCTAssertFalse(node.subject.contains("\""))
        XCTAssertTrue(node.label.contains(node.shortHash))
        XCTAssertTrue(node.label.contains(node.subject))
    }

    func testConstellationIsEmptyForEmptyHistoryOrUnavailableRepository() {
        let emptyPlan = CinematicCommitConstellationPlan(sessions: [])
        let unavailablePlan = CinematicCommitConstellationPlan(
            sessions: [
                makeSession(
                    1,
                    startedAt: 100,
                    endedAt: 200,
                    commits: [makeCommit(subject: "Hidden commit")]
                )
            ],
            hasRepository: false
        )

        XCTAssertTrue(emptyPlan.isEmpty)
        XCTAssertEqual(emptyPlan.identifier, CinematicCommitConstellationPlan.empty.identifier)
        XCTAssertTrue(unavailablePlan.isEmpty)
        XCTAssertNil(unavailablePlan.newestSubject)
        XCTAssertTrue(unavailablePlan.nodeIdentifiers.isEmpty)
        XCTAssertTrue(unavailablePlan.branchIdentifiers.isEmpty)
    }

    func testConstellationFocusPlanUsesFallbackForEmptyAndNewestNodeForNonEmpty() throws {
        let emptyFocus = CinematicCommitConstellationPlan.empty.focusPlan

        XCTAssertTrue(emptyFocus.isFallback)
        XCTAssertEqual(emptyFocus.shot, .home)
        XCTAssertEqual(emptyFocus.lookTarget, CinematicCommitConstellationPlan.fallbackFocusLookTarget)
        XCTAssertEqual(emptyFocus.identifier, "commit-constellation-focus.empty")

        let plan = CinematicCommitConstellationPlan(
            sessions: [
                makeSession(
                    1,
                    startedAt: 100,
                    endedAt: 200,
                    commits: [
                        makeCommit(subject: "Older constellation anchor"),
                        makeCommit(subject: "Newest constellation anchor")
                    ]
                )
            ]
        )
        let focus = plan.focusPlan

        XCTAssertFalse(focus.isFallback)
        XCTAssertEqual(focus.shot, .commitConstellation)
        XCTAssertEqual(focus.lookTarget, try XCTUnwrap(plan.nodes.first).position)
        XCTAssertTrue(focus.identifier.contains(plan.identifier))
        XCTAssertTrue(focus.identifier.contains(plan.nodes[0].stableID))
    }

    func testDiagnosticsExposeCommitConstellationSnapshotAndSummaryRow() throws {
        let plan = CinematicCommitConstellationPlan(
            sessions: [
                makeSession(
                    1,
                    startedAt: 100,
                    endedAt: 200,
                    commits: [
                        makeCommit(subject: "Prepare commit constellation"),
                        makeCommit(subject: "Render branch trails")
                    ]
                )
            ]
        )
        let report = CinematicDiagnostics.report(
            repoName: "Compass",
            phase: LoopPhase.verifying.rawValue,
            immediateTitle: "Expose constellation diagnostics",
            completedCount: 3,
            latestEvent: nil,
            latestCommitSubject: plan.newestSubject,
            languageProfile: .empty,
            activityProfile: .empty,
            influenceSettings: CinematicInfluenceSettings(),
            commitConstellationPlan: plan
        )

        XCTAssertEqual(report.commitConstellation.count, 2)
        XCTAssertEqual(report.commitConstellation.newestSubject, "Render branch trails")
        XCTAssertEqual(report.commitConstellation.nodeIdentifiers, plan.nodeIdentifiers)
        XCTAssertEqual(report.commitConstellation.branchIdentifiers, plan.branchIdentifiers)
        XCTAssertEqual(report.commitConstellation.focusIdentifier, plan.focusPlan.identifier)
        XCTAssertEqual(report.commitConstellation.focusShotIdentifier, CinematicCameraShot.commitConstellation.identifier)
        XCTAssertEqual(report.commitConstellation.focusLookTarget, plan.focusPlan.lookTarget)
        XCTAssertFalse(report.commitConstellation.usesFallbackFocus)
        XCTAssertTrue(report.identifier.contains(plan.identifier))
        XCTAssertTrue(report.identifier.contains(plan.focusPlan.identifier))

        let summary = CinematicDiagnosticsSummary(report: report)
        let row = try XCTUnwrap(summary.rows.first { $0.id == "commit-constellation" })
        XCTAssertEqual(row.label, "Commit constellation")
        XCTAssertTrue(row.detail.contains("count 2"))
        XCTAssertTrue(row.detail.contains(plan.nodes[0].stableID))
        XCTAssertTrue(row.detail.contains("shot commit-constellation"))
        XCTAssertTrue(summary.exportText.contains("Commit constellation:"))
        XCTAssertTrue(summary.exportText.contains(plan.focusPlan.identifier))
        XCTAssertTrue(summary.exportText.contains(plan.branchSegments[0].stableID))
    }

    func testRefreshInputEqualityIncludesConstellationIdentifierForUpdateTriggering() {
        let briefing = CinematicBriefingInput(
            repoName: "Compass",
            currentPhase: "Verifying",
            immediatePlanTitle: "Render commits",
            completedCount: 2,
            latestEvent: nil,
            latestCommitSubject: "Render branch trails"
        )
        let worldText = CinematicWorldTextInput(
            repoName: briefing.repoName,
            currentPhase: briefing.currentPhase,
            immediatePlanTitle: briefing.immediatePlanTitle,
            completedCount: briefing.completedCount,
            latestEvent: briefing.latestEvent,
            latestCommitSubject: briefing.latestCommitSubject,
            languageProfile: .empty,
            activityProfile: .empty
        )
        let firstPlan = CinematicCommitConstellationPlan(
            sessions: [
                makeSession(
                    1,
                    startedAt: 100,
                    endedAt: 200,
                    commits: [makeCommit(subject: "Render branch trails")]
                )
            ]
        )
        let secondPlan = CinematicCommitConstellationPlan(
            sessions: [
                makeSession(
                    2,
                    startedAt: 200,
                    endedAt: 300,
                    commits: [makeCommit(subject: "Focus new constellation node")]
                )
            ]
        )
        let first = CinematicRefreshInput(
            briefing: briefing,
            worldText: worldText,
            commitConstellationIdentifier: firstPlan.focusPlan.identifier
        )
        let second = CinematicRefreshInput(
            briefing: briefing,
            worldText: worldText,
            commitConstellationIdentifier: secondPlan.focusPlan.identifier
        )

        XCTAssertNotEqual(firstPlan.focusPlan.identifier, secondPlan.focusPlan.identifier)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first, first)
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

private func XCTAssertInRange<T: Comparable>(
    _ value: T,
    _ range: ClosedRange<T>,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertGreaterThanOrEqual(value, range.lowerBound, file: file, line: line)
    XCTAssertLessThanOrEqual(value, range.upperBound, file: file, line: line)
}
