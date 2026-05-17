import Foundation
@testable import Compass
import XCTest

final class CinematicWorldTextDeterministicTests: XCTestCase {
    func testFallbackUsesLanguageMotifsForStableQuestAndArenaLabels() {
        let expected: [RepositoryLanguage: (quest: String, arena: String)] = [
            .swift: ("Swift forge", "Comet forge"),
            .typeScriptJavaScript: ("Script circuit", "Circuit arena"),
            .python: ("Python oracle", "Oracle coil"),
            .go: ("Go current", "Current gate"),
            .rust: ("Rust gear", "Gearworks arena"),
            .markdown: ("Markdown archive", "Archive runes"),
            .other: ("Polyglot prism", "Prism yard"),
            .unknown: ("Unknown gate", "Unknown arena")
        ]

        let texts = RepositoryLanguage.allCases.map { language in
            let text = CinematicWorldTextService.deterministicWorldText(
                for: worldTextInput(language: language, activityProfile: activityProfile())
            )

            XCTAssertTrue(text.questLabel.hasPrefix(expected[language]!.quest), language.rawValue)
            XCTAssertTrue(text.arenaCallout.hasPrefix(expected[language]!.arena), language.rawValue)
            assertWorldTextBounds(text, file: #filePath, line: #line)
            return text
        }

        XCTAssertEqual(Set(texts.map(\.questLabel)).count, RepositoryLanguage.allCases.count)
        XCTAssertEqual(Set(texts.map(\.arenaCallout)).count, RepositoryLanguage.allCases.count)
    }

    func testFallbackUsesActivityMotifsForStableActivityLabels() {
        let event = CinematicBriefingEvent(
            line: LiveLine(
                level: .success,
                text: "Develop finished",
                detail: "Develop finished",
                kind: .agentMessage,
                status: .completed
            )
        )
        let cases: [(name: String, profile: RepositoryActivityProfile, prefix: String)] = [
            ("unavailable", .empty, "Dim gate"),
            ("clean", activityProfile(), "Calm halo"),
            ("dirty", activityProfile(worktreeChanges: worktreeChanges(modified: 2)), "Pressure shard"),
            ("conflicted", activityProfile(worktreeChanges: worktreeChanges(conflicted: 1)), "Fracture cross"),
            ("commit", activityProfile(recentCommitCount: 1), "History branch"),
            ("success", activityProfile(lastTerminalStatus: .succeeded, successStreak: 2), "Seal burst"),
            (
                "recovery",
                activityProfile(lastTerminalStatus: .succeeded, successStreak: 1, recoveredFromFailure: true),
                "Recovery arc"
            ),
            (
                "failure",
                activityProfile(recentFailedCount: 1, lastTerminalStatus: .failed, failureStreak: 1),
                "Backlash spike"
            )
        ]

        let texts = cases.map { expectation in
            let text = CinematicWorldTextService.deterministicWorldText(
                for: worldTextInput(
                    activityProfile: expectation.profile,
                    latestEvent: event
                )
            )

            XCTAssertTrue(text.activityCallout.hasPrefix(expectation.prefix), expectation.name)
            XCTAssertTrue(text.activityCallout.contains("Develop finished"), expectation.name)
            assertWorldTextBounds(text, file: #filePath, line: #line)
            return text
        }

        XCTAssertEqual(Set(texts.map(\.activityCallout)).count, cases.count)
    }

    func testFallbackHasStableRepresentativeCopy() {
        let text = CinematicWorldTextService.deterministicWorldText(
            for: worldTextInput(
                repoName: "Compass",
                phase: "Developing",
                plan: "Add bounded cinematic world text callouts",
                completedCount: 2,
                language: .swift,
                activityProfile: activityProfile()
            )
        )

        XCTAssertEqual(text.questLabel, "Swift forge: bounded cinematic")
        XCTAssertEqual(text.arenaCallout, "Comet forge over Compass")
        XCTAssertEqual(text.activityCallout, "Calm halo: Developing 2 milestones")
    }

    func testFallbackUsesLatestCommitSubjectForActivityCopy() {
        let text = CinematicWorldTextService.deterministicWorldText(
            for: worldTextInput(
                activityProfile: activityProfile(recentCommitCount: 1),
                latestCommitSubject: "Ship commit-aware cinematic copy"
            )
        )

        XCTAssertEqual(text.activityCallout, "History branch: Ship commit-aware cinematic copy")
        assertWorldTextBounds(text, file: #filePath, line: #line)
    }

    func testFallbackBoundsUnusualShortWordsAndUnsafeSignals() {
        let event = CinematicBriefingEvent(
            line: LiveLine(
                level: .info,
                text: "Fallback event",
                detail: "a b c d e f g https://example.com `raw` {json}",
                kind: .command,
                status: .running
            )
        )
        let text = CinematicWorldTextService.deterministicWorldText(
            for: worldTextInput(
                repoName: #"Repo {"url":"https://example.com"}"#,
                phase: "Developing",
                plan: "Add a b c d e f g h i j",
                activityProfile: activityProfile(worktreeChanges: worktreeChanges(modified: 1)),
                latestEvent: event
            )
        )

        assertWorldTextBounds(text, file: #filePath, line: #line)
        XCTAssertFalse(text.arenaCallout.contains("https://"))
        XCTAssertFalse(text.activityCallout.contains("https://"))
        XCTAssertFalse(text.activityCallout.contains("{"))
        XCTAssertFalse(text.activityCallout.contains("`"))
    }
}

final class CinematicWorldTextGeneratedParsingTests: XCTestCase {
    func testAcceptsStrictGeneratedLines() throws {
        let text = try XCTUnwrap(
            CinematicWorldTextService.parseGeneratedWorldText(
                """
                Quest: Swift forge opens
                Arena: Comet forge over Compass
                Activity: Seal burst tests passed
                """
            )
        )

        XCTAssertEqual(text.questLabel, "Swift forge opens")
        XCTAssertEqual(text.arenaCallout, "Comet forge over Compass")
        XCTAssertEqual(text.activityCallout, "Seal burst tests passed")
    }

    func testRejectsGeneratedMarkdownURLsAndRawJSONLeakage() {
        XCTAssertNil(
            CinematicWorldTextService.parseGeneratedWorldText(
                """
                Quest: **Swift forge opens**
                Arena: Comet forge over Compass
                Activity: Seal burst tests passed
                """
            )
        )
        XCTAssertNil(
            CinematicWorldTextService.parseGeneratedWorldText(
                """
                Quest: Swift forge opens
                Arena: Review https://example.com
                Activity: Seal burst tests passed
                """
            )
        )
        XCTAssertNil(
            CinematicWorldTextService.parseGeneratedWorldText(
                """
                {"questLabel":"Swift forge opens","arenaCallout":"Comet forge over Compass","activityCallout":"Seal burst tests passed"}
                """
            )
        )
    }

    func testRejectsMissingDuplicateAndOversizedGeneratedFields() {
        XCTAssertNil(
            CinematicWorldTextService.parseGeneratedWorldText(
                """
                Quest: Swift forge opens
                Arena: Comet forge over Compass
                """
            )
        )
        XCTAssertNil(
            CinematicWorldTextService.parseGeneratedWorldText(
                """
                Quest: Swift forge opens
                Quest: Swift forge opens
                Activity: Seal burst tests passed
                """
            )
        )
        XCTAssertNil(
            CinematicWorldTextService.parseGeneratedWorldText(
                """
                Quest: Swift forge opens beyond every small bounded overlay label
                Arena: Comet forge over Compass
                Activity: Seal burst tests passed
                """
            )
        )
        XCTAssertNil(
            CinematicWorldTextService.parseGeneratedWorldText(
                """
                Quest: Swift forge opens
                Arena: Comet forge over Compass
                Activity: One two three four five six seven eight nine
                """
            )
        )
    }
}

final class CinematicWorldTextInputTests: XCTestCase {
    func testInputEqualityIncludesLanguageActivityAndLiveEventSignals() {
        let base = worldTextInput(language: .swift, activityProfile: activityProfile())
        XCTAssertEqual(base, worldTextInput(language: .swift, activityProfile: activityProfile()))

        var languageChanged = base
        languageChanged.languageProfile = languageProfile(primaryLanguage: .python)
        XCTAssertNotEqual(base, languageChanged)

        var activityChanged = base
        activityChanged.activityProfile = activityProfile(worktreeChanges: worktreeChanges(modified: 1))
        XCTAssertNotEqual(base, activityChanged)

        var eventChanged = base
        eventChanged.latestEvent = CinematicBriefingEvent(
            line: LiveLine(
                level: .info,
                text: "Plan accepted",
                detail: nil,
                kind: .lifecycle,
                status: .completed
            )
        )
        XCTAssertNotEqual(base, eventChanged)

        var commitChanged = base
        commitChanged.latestCommitSubject = "Ship commit-aware copy"
        XCTAssertNotEqual(base, commitChanged)
    }
}

private func worldTextInput(
    repoName: String = "Compass",
    phase: String = "Developing",
    plan: String = "Add bounded cinematic world text callouts",
    completedCount: Int = 2,
    language: RepositoryLanguage = .swift,
    activityProfile: RepositoryActivityProfile,
    latestEvent: CinematicBriefingEvent? = nil,
    latestCommitSubject: String? = nil
) -> CinematicWorldTextInput {
    CinematicWorldTextInput(
        repoName: repoName,
        currentPhase: phase,
        immediatePlanTitle: plan,
        completedCount: completedCount,
        latestEvent: latestEvent,
        latestCommitSubject: latestCommitSubject,
        languageProfile: languageProfile(primaryLanguage: language),
        activityProfile: activityProfile
    )
}

private func languageProfile(primaryLanguage: RepositoryLanguage) -> RepositoryLanguageProfile {
    var counts = RepositoryLanguageCounts()
    counts[primaryLanguage] = primaryLanguage == .unknown ? 0 : 4
    return RepositoryLanguageProfile(
        counts: counts,
        manifestHints: [],
        primaryLanguage: primaryLanguage,
        scannedFileCount: 4,
        scannedDirectoryCount: 1,
        wasTruncated: false
    )
}

private func activityProfile(
    worktreeChanges: RepositoryWorktreeChangeCounts = RepositoryWorktreeChangeCounts(),
    recentSessionCount: Int = 1,
    recentSucceededCount: Int = 0,
    recentFailedCount: Int = 0,
    recentCommitCount: Int = 0,
    lastTerminalStatus: SessionStatus? = nil,
    successStreak: Int = 0,
    failureStreak: Int = 0,
    recoveredFromFailure: Bool = false
) -> RepositoryActivityProfile {
    RepositoryActivityProfile(
        isAvailable: true,
        worktreeChanges: worktreeChanges,
        recentSessionCount: recentSessionCount,
        recentSucceededCount: recentSucceededCount,
        recentFailedCount: recentFailedCount,
        recentCommitCount: recentCommitCount,
        lastTerminalStatus: lastTerminalStatus,
        lastSuccessfulSession: successStreak > 0 ? 1 : nil,
        lastFailedSession: failureStreak > 0 || recoveredFromFailure ? 0 : nil,
        successStreak: successStreak,
        failureStreak: failureStreak,
        recoveredFromFailure: recoveredFromFailure
    )
}

private func worktreeChanges(
    added: Int = 0,
    modified: Int = 0,
    deleted: Int = 0,
    renamed: Int = 0,
    untracked: Int = 0,
    conflicted: Int = 0,
    other: Int = 0
) -> RepositoryWorktreeChangeCounts {
    var changes = RepositoryWorktreeChangeCounts()
    changes.added = added
    changes.modified = modified
    changes.deleted = deleted
    changes.renamed = renamed
    changes.untracked = untracked
    changes.conflicted = conflicted
    changes.other = other
    return changes
}

private func assertWorldTextBounds(
    _ text: CinematicWorldText,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertLessThanOrEqual(
        text.questLabel.count,
        CinematicWorldTextService.questLabelMaxCharacters,
        file: file,
        line: line
    )
    XCTAssertLessThanOrEqual(
        text.arenaCallout.count,
        CinematicWorldTextService.arenaCalloutMaxCharacters,
        file: file,
        line: line
    )
    XCTAssertLessThanOrEqual(
        text.activityCallout.count,
        CinematicWorldTextService.activityCalloutMaxCharacters,
        file: file,
        line: line
    )
    XCTAssertLessThanOrEqual(
        wordCount(text.questLabel),
        CinematicWorldTextService.questLabelMaxWords,
        file: file,
        line: line
    )
    XCTAssertLessThanOrEqual(
        wordCount(text.arenaCallout),
        CinematicWorldTextService.arenaCalloutMaxWords,
        file: file,
        line: line
    )
    XCTAssertLessThanOrEqual(
        wordCount(text.activityCallout),
        CinematicWorldTextService.activityCalloutMaxWords,
        file: file,
        line: line
    )
}

private func wordCount(_ text: String) -> Int {
    text.split(whereSeparator: \.isWhitespace).count
}
