import AppKit
import Foundation
@testable import Compass
import XCTest

final class CinematicLanguageMotifTests: XCTestCase {
    func testEveryLanguageHasStableMotifValues() {
        let expectations: [RepositoryLanguage: LanguageExpectation] = [
            .swift: LanguageExpectation(
                ambientSpell: .edit,
                phaseBlend: 0.38,
                sigilIdentifier: "language.swift",
                style: .swiftComet,
                accent: rgb(1.0, 0.43, 0.15),
                secondary: rgb(1.0, 0.76, 0.34)
            ),
            .typeScriptJavaScript: LanguageExpectation(
                ambientSpell: .shell,
                phaseBlend: 0.3,
                sigilIdentifier: "language.typescript-javascript",
                style: .scriptCircuit,
                accent: rgb(0.22, 0.66, 1.0),
                secondary: rgb(1.0, 0.84, 0.24)
            ),
            .python: LanguageExpectation(
                ambientSpell: .insight,
                phaseBlend: 0.32,
                sigilIdentifier: "language.python",
                style: .pythonCoil,
                accent: rgb(0.24, 0.48, 0.95),
                secondary: rgb(1.0, 0.78, 0.24)
            ),
            .go: LanguageExpectation(
                ambientSpell: .scan,
                phaseBlend: 0.32,
                sigilIdentifier: "language.go",
                style: .goCurrent,
                accent: rgb(0.0, 0.74, 0.82),
                secondary: rgb(0.42, 1.0, 0.82)
            ),
            .rust: LanguageExpectation(
                ambientSpell: .git,
                phaseBlend: 0.34,
                sigilIdentifier: "language.rust",
                style: .rustGear,
                accent: rgb(0.92, 0.38, 0.14),
                secondary: rgb(1.0, 0.58, 0.28)
            ),
            .markdown: LanguageExpectation(
                ambientSpell: .insight,
                phaseBlend: 0.26,
                sigilIdentifier: "language.markdown",
                style: .markdownRune,
                accent: rgb(0.48, 0.62, 1.0),
                secondary: rgb(0.82, 0.9, 1.0)
            ),
            .other: LanguageExpectation(
                ambientSpell: .pressure,
                phaseBlend: 0.18,
                sigilIdentifier: "language.other",
                style: .polyglotPrism,
                accent: rgb(0.56, 0.5, 0.72),
                secondary: rgb(0.72, 0.68, 0.9)
            ),
            .unknown: LanguageExpectation(
                ambientSpell: .pressure,
                phaseBlend: 0.12,
                sigilIdentifier: "language.unknown",
                style: .unknownGate,
                accent: rgb(0.32, 0.84, 1.0),
                secondary: rgb(0.28, 0.58, 1.0)
            )
        ]

        XCTAssertEqual(Set(expectations.keys), Set(RepositoryLanguage.allCases))

        for language in RepositoryLanguage.allCases {
            let expectation = expectations[language]!
            let motif = CinematicMotif.language(for: languageProfile(primaryLanguage: language))
            let repeated = CinematicMotif.language(for: languageProfile(primaryLanguage: language))

            XCTAssertEqual(motif, repeated)
            XCTAssertEqual(motif, CinematicMotif.language(for: language))
            XCTAssertEqual(motif.language, language)
            XCTAssertEqual(motif.ambientSpell, expectation.ambientSpell)
            XCTAssertEqual(motif.phaseBlend, expectation.phaseBlend, accuracy: 0.0001)
            XCTAssertGreaterThanOrEqual(motif.phaseBlend, CinematicMotif.phaseBlendRange.lowerBound)
            XCTAssertLessThanOrEqual(motif.phaseBlend, CinematicMotif.phaseBlendRange.upperBound)
            XCTAssertEqual(motif.sigilIdentifier, expectation.sigilIdentifier)
            XCTAssertEqual(motif.style, expectation.style)
            XCTAssertEqual(motif.styleIdentifier, expectation.style.rawValue)
            XCTAssertColorEqual(motif.accent, expectation.accent)
            XCTAssertColorEqual(motif.secondaryAccent, expectation.secondary)
            XCTAssertColorEqual(motif.phaseColor(.black), repeated.phaseColor(.black))
        }
    }
}

final class CinematicActivityMotifTests: XCTestCase {
    func testMainActivityStatesHaveStableMotifValues() {
        let languageAmbient = SpellSchool.insight
        let cases: [ActivityExpectation] = [
            ActivityExpectation(
                name: "clean",
                profile: activityProfile(),
                eventKind: .clean,
                tintSource: nil,
                transitionSpell: nil,
                ambientBySpawnIndex: [0: languageAmbient, 1: languageAmbient],
                shouldShake: false,
                sigilIdentifier: "activity.clean",
                style: .calmHalo
            ),
            ActivityExpectation(
                name: "dirty",
                profile: activityProfile(worktreeChanges: worktreeChanges(modified: 3)),
                eventKind: .dirty,
                tintSource: .pressure,
                transitionSpell: .pressure,
                ambientBySpawnIndex: [0: languageAmbient, 1: languageAmbient],
                shouldShake: false,
                sigilIdentifier: "activity.dirty",
                style: .pressureShard
            ),
            ActivityExpectation(
                name: "conflicted",
                profile: activityProfile(worktreeChanges: worktreeChanges(conflicted: 1)),
                eventKind: .conflicted,
                tintSource: .failure,
                transitionSpell: .failure,
                ambientBySpawnIndex: [0: .failure, 1: .failure],
                shouldShake: true,
                sigilIdentifier: "activity.conflicted",
                style: .fractureCross
            ),
            ActivityExpectation(
                name: "commit",
                profile: activityProfile(recentCommitCount: 2),
                eventKind: .commit,
                tintSource: .git,
                transitionSpell: .git,
                ambientBySpawnIndex: [0: .git, 1: languageAmbient, 3: .git],
                shouldShake: false,
                sigilIdentifier: "activity.commit",
                style: .historyBranch
            ),
            ActivityExpectation(
                name: "success",
                profile: activityProfile(lastTerminalStatus: .succeeded, successStreak: 3),
                eventKind: .success,
                tintSource: .verify,
                transitionSpell: .verify,
                ambientBySpawnIndex: [0: .verify, 1: languageAmbient, 2: .verify],
                shouldShake: false,
                sigilIdentifier: "activity.success",
                style: .sealBurst
            ),
            ActivityExpectation(
                name: "recovery",
                profile: activityProfile(
                    lastTerminalStatus: .succeeded,
                    successStreak: 1,
                    recoveredFromFailure: true
                ),
                eventKind: .recovery,
                tintSource: nil,
                transitionSpell: .verify,
                ambientBySpawnIndex: [0: languageAmbient, 2: languageAmbient],
                shouldShake: false,
                sigilIdentifier: "activity.recovery",
                style: .recoveryArc
            ),
            ActivityExpectation(
                name: "failure",
                profile: activityProfile(
                    recentFailedCount: 1,
                    lastTerminalStatus: .failed,
                    failureStreak: 1
                ),
                eventKind: .failure,
                tintSource: .failure,
                transitionSpell: .failure,
                ambientBySpawnIndex: [0: .failure, 1: .failure],
                shouldShake: true,
                sigilIdentifier: "activity.failure",
                style: .backlashSpike
            )
        ]

        XCTAssertEqual(Set(cases.map(\.sigilIdentifier)).count, cases.count)
        XCTAssertEqual(Set(cases.map(\.style.rawValue)).count, cases.count)

        for expectation in cases {
            let motif = CinematicMotif.activity(for: expectation.profile)
            let repeated = CinematicMotif.activity(for: expectation.profile)

            XCTAssertEqual(motif, repeated, expectation.name)
            XCTAssertEqual(motif.eventKind, expectation.eventKind, expectation.name)
            XCTAssertEqual(motif.tintSource, expectation.tintSource, expectation.name)
            XCTAssertEqual(motif.transitionSpell, expectation.transitionSpell, expectation.name)
            XCTAssertEqual(motif.shouldShakeOnTransition, expectation.shouldShake, expectation.name)
            XCTAssertEqual(motif.sigilIdentifier, expectation.sigilIdentifier, expectation.name)
            XCTAssertEqual(motif.style, expectation.style, expectation.name)
            XCTAssertEqual(motif.styleIdentifier, expectation.style.rawValue, expectation.name)

            for (spawnIndex, ambientSpell) in expectation.ambientBySpawnIndex {
                XCTAssertEqual(
                    motif.ambientSpell(languageAmbient: languageAmbient, spawnIndex: spawnIndex),
                    ambientSpell,
                    "\(expectation.name) spawn \(spawnIndex)"
                )
            }
        }
    }

    func testUnavailableAndHeavyDirtyProfilesKeepDeterministicAmbientRules() {
        let languageAmbient = SpellSchool.shell
        let unavailable = CinematicMotif.activity(for: .empty)

        XCTAssertEqual(unavailable.eventKind, .unavailable)
        XCTAssertNil(unavailable.tintSource)
        XCTAssertNil(unavailable.transitionSpell)
        XCTAssertEqual(unavailable.sigilIdentifier, "activity.unavailable")
        XCTAssertEqual(unavailable.style, .dimGate)
        XCTAssertEqual(unavailable.ambientSpell(languageAmbient: languageAmbient, spawnIndex: 0), languageAmbient)

        let heavyDirty = CinematicMotif.activity(
            for: activityProfile(worktreeChanges: worktreeChanges(modified: 16))
        )
        XCTAssertEqual(heavyDirty.eventKind, .dirty)
        XCTAssertEqual(heavyDirty.tintSource, .pressure)
        XCTAssertEqual(heavyDirty.transitionSpell, .pressure)
        XCTAssertEqual(heavyDirty.ambientSpell(languageAmbient: languageAmbient, spawnIndex: 0), .pressure)
        XCTAssertEqual(heavyDirty.ambientSpell(languageAmbient: languageAmbient, spawnIndex: 5), .pressure)
        XCTAssertEqual(heavyDirty, CinematicMotif.activity(for: activityProfile(worktreeChanges: worktreeChanges(modified: 16))))
    }
}

private struct LanguageExpectation {
    var ambientSpell: SpellSchool
    var phaseBlend: CGFloat
    var sigilIdentifier: String
    var style: CinematicLanguageSigilStyle
    var accent: NSColor
    var secondary: NSColor
}

private struct ActivityExpectation {
    var name: String
    var profile: RepositoryActivityProfile
    var eventKind: CinematicActivityEventKind
    var tintSource: SpellSchool?
    var transitionSpell: SpellSchool?
    var ambientBySpawnIndex: [Int: SpellSchool]
    var shouldShake: Bool
    var sigilIdentifier: String
    var style: CinematicActivitySigilStyle
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

private func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
    NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1)
}

private func XCTAssertColorEqual(
    _ actual: NSColor,
    _ expected: NSColor,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let actual = actual.usingColorSpace(.deviceRGB) ?? actual
    let expected = expected.usingColorSpace(.deviceRGB) ?? expected
    XCTAssertEqual(actual.redComponent, expected.redComponent, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(actual.greenComponent, expected.greenComponent, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(actual.blueComponent, expected.blueComponent, accuracy: 0.0001, file: file, line: line)
    XCTAssertEqual(actual.alphaComponent, expected.alphaComponent, accuracy: 0.0001, file: file, line: line)
}
