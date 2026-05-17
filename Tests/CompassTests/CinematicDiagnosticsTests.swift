import Foundation
@testable import Compass
import XCTest

final class CinematicDiagnosticsTests: XCTestCase {
    func testReportIsStableAndUsesDeterministicCopyAndMotifs() {
        let latestEvent = CinematicBriefingEvent(
            line: LiveLine(
                level: .success,
                text: "Develop diagnostics stabilized",
                detail: "Develop diagnostics stabilized",
                kind: .agentMessage,
                status: .completed
            )
        )
        let settings = CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 0.75)
        let input = CinematicDiagnosticsInput(
            repoName: "Compass",
            phase: "Developing",
            immediateTitle: "Add deterministic cinematic diagnostics smoke path",
            completedCount: 4,
            latestEvent: latestEvent,
            languageProfile: languageProfile(primaryLanguage: .swift),
            activityProfile: activityProfile(worktreeChanges: worktreeChanges(modified: 3)),
            influenceSettings: settings
        )

        let report = makeReport(input)
        let repeated = makeReport(input)

        XCTAssertEqual(report, repeated)
        XCTAssertEqual(report.influenceIdentifier, "dramatic|0.7500")
        XCTAssertEqual(report.languageMotif.sigilIdentifier, "language.swift")
        XCTAssertEqual(report.languageMotif.styleIdentifier, "swift-comet")
        XCTAssertEqual(report.languageMotif.ambientSpellIdentifier, "edit")
        XCTAssertEqual(report.activityMotif.eventKindIdentifier, "dirty")
        XCTAssertEqual(report.activityMotif.sigilIdentifier, "activity.dirty")
        XCTAssertEqual(report.activityMotif.styleIdentifier, "pressure-shard")
        XCTAssertEqual(report.activityMotif.tintSourceIdentifier, "pressure")
        XCTAssertEqual(report.activityMotif.transitionSpellIdentifier, "pressure")
        XCTAssertEqual(report.stageBeat.kindIdentifier, "developing")
        XCTAssertEqual(report.stageBeat.cameraShotIdentifier, "cast-prep")
        XCTAssertEqual(report.stageBeat.lightFamilyIdentifier, "shell")
        XCTAssertEqual(report.stageBeat.activityEventKindIdentifier, "dirty")
        XCTAssertEqual(report.stageBeat.activityLightFamilyIdentifier, "pressure")
        XCTAssertEqual(report.stageBeat.activityArenaEffectIdentifier, "activity-pulse")
        XCTAssertTrue(report.worldText.identifier.contains(report.worldText.questLabel))
        XCTAssertTrue(report.briefing.identifier.contains(report.briefing.title))

        let expectedBriefing = CinematicBriefingService.deterministicBriefing(
            for: CinematicBriefingInput(
                repoName: input.repoName,
                currentPhase: input.phase,
                immediatePlanTitle: input.immediateTitle,
                completedCount: input.completedCount,
                latestEvent: input.latestEvent
            )
        )
        let expectedWorldText = CinematicWorldTextService.deterministicWorldText(
            for: CinematicWorldTextInput(
                repoName: input.repoName,
                currentPhase: input.phase,
                immediatePlanTitle: input.immediateTitle,
                completedCount: input.completedCount,
                latestEvent: input.latestEvent,
                languageProfile: input.languageProfile,
                activityProfile: input.activityProfile
            )
        )

        XCTAssertEqual(report.briefing.title, expectedBriefing.title)
        XCTAssertEqual(report.briefing.detail, expectedBriefing.detail)
        XCTAssertEqual(report.worldText.questLabel, expectedWorldText.questLabel)
        XCTAssertEqual(report.worldText.arenaCallout, expectedWorldText.arenaCallout)
        XCTAssertEqual(report.worldText.activityCallout, expectedWorldText.activityCallout)
    }

    func testRepresentativeSmokeMatrixCoversLanguagesAndActivityStates() {
        let reports = CinematicDiagnostics.representativeSmokeMatrix()
        let expectedActivityCaseCount = CinematicDiagnostics.representativeActivityCases().count

        XCTAssertEqual(reports.count, RepositoryLanguage.allCases.count * expectedActivityCaseCount)
        XCTAssertEqual(Set(reports.map(\.languageMotif.language)), Set(RepositoryLanguage.allCases))
        XCTAssertEqual(
            Set(reports.map(\.activityMotif.eventKindIdentifier)),
            Set(CinematicActivityEventKind.allCases.map(\.rawValue))
        )
        XCTAssertEqual(
            Set(reports.map(\.languageMotif.sigilIdentifier)).count,
            RepositoryLanguage.allCases.count
        )
        XCTAssertEqual(
            Set(reports.map(\.activityMotif.sigilIdentifier)),
            Set(CinematicActivityEventKind.allCases.map { "activity.\($0.rawValue)" })
        )
        XCTAssertTrue(
            Set(reports.map(\.activityTuning.pressureLevelIdentifier))
                .isSuperset(of: ["clean", "light", "moderate", "heavy"])
        )
    }

    func testReportContainsEveryCameraShotAndCameraTuningValue() {
        let settings = CinematicInfluenceSettings(cameraStyle: .steady, intensity: 0.25)
        let report = CinematicDiagnostics.representativeSmokeMatrix(influenceSettings: settings).first!

        XCTAssertEqual(
            report.cameraSnapshots.map(\.shotIdentifier),
            CinematicCameraShot.allCases.map(\.identifier)
        )
        XCTAssertEqual(Set(report.cameraSnapshots.map(\.identifier)).count, CinematicCameraShot.allCases.count)
        XCTAssertEqual(report.cameraTuning.orbitScale, CinematicTuning.cameraOrbitScale(settings: settings))
        XCTAssertEqual(report.cameraTuning.pullbackScale, CinematicTuning.cameraPullbackScale(settings: settings))
        XCTAssertEqual(report.cameraTuning.heightOffset, CinematicTuning.cameraHeightOffset(settings: settings))
        XCTAssertEqual(
            report.cameraTuning.followResponsiveness,
            CinematicTuning.cameraFollowResponsiveness(settings: settings)
        )
        XCTAssertEqual(
            report.cameraTuning.followFieldOfView,
            CinematicTuning.cameraFollowFieldOfView(settings: settings)
        )
        XCTAssertEqual(report.cameraTuning.driftScale, CinematicTuning.cameraDriftScale(settings: settings))
        XCTAssertEqual(report.cameraTuning.shakeScale, CinematicTuning.cameraShakeScale(settings: settings))

        for (shot, snapshot) in zip(CinematicCameraShot.allCases, report.cameraSnapshots) {
            XCTAssertEqual(snapshot.shotIdentifier, shot.identifier)
            XCTAssertEqual(snapshot.position, CinematicTuning.cameraPosition(for: shot, settings: settings))
            XCTAssertEqual(
                snapshot.fieldOfView,
                CinematicTuning.cameraFieldOfView(for: shot, settings: settings),
                accuracy: 0.0001
            )
            XCTAssertEqual(
                snapshot.transitionDuration,
                CinematicTuning.cameraTransitionDuration(for: shot, settings: settings),
                accuracy: 0.0001
            )
            XCTAssertTrue(snapshot.identifier.hasPrefix("\(shot.identifier)|steady|0.2500"))
        }
    }

    func testWorldTextAndBriefingStayWithinOverlayBounds() {
        let reports = CinematicDiagnostics.representativeSmokeMatrix(
            influenceSettings: CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 1)
        )

        for report in reports {
            assertWorldTextBounds(report.worldText, file: #filePath, line: #line)
            XCTAssertFalse(report.briefing.title.isEmpty)
            XCTAssertFalse(report.briefing.detail.isEmpty)
            XCTAssertLessThanOrEqual(report.briefing.title.count, 68)
            XCTAssertLessThanOrEqual(report.briefing.detail.count, 150)
        }
    }

    func testCameraAndActivityTuningStayInsideClampRanges() {
        let settingsSamples = [
            CinematicInfluenceSettings(cameraStyle: .steady, intensity: 0),
            CinematicInfluenceSettings(cameraStyle: .follow, intensity: CinematicInfluenceSettings.defaultIntensity),
            CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 1)
        ]

        for settings in settingsSamples {
            let reports = CinematicDiagnostics.representativeSmokeMatrix(influenceSettings: settings)
            for report in reports {
                XCTAssertInRange(report.cameraTuning.followFieldOfView, CinematicTuning.cameraFollowFieldOfViewRange)
                XCTAssertInRange(report.cameraTuning.shakeScale, CinematicTuning.cameraShakeScaleRange)
                XCTAssertFinite(report.cameraTuning.orbitScale)
                XCTAssertFinite(report.cameraTuning.pullbackScale)
                XCTAssertFinite(report.cameraTuning.heightOffset)
                XCTAssertFinite(report.cameraTuning.followResponsiveness)
                XCTAssertFinite(report.cameraTuning.driftScale)
                XCTAssertGreaterThan(report.cameraTuning.orbitScale, 0)
                XCTAssertGreaterThan(report.cameraTuning.pullbackScale, 0)
                XCTAssertGreaterThan(report.cameraTuning.followResponsiveness, 0)
                XCTAssertGreaterThan(report.cameraTuning.driftScale, 0)

                XCTAssertInRange(report.activityTuning.ambientSpawnCadence, CinematicTuning.ambientSpawnCadenceRange)
                XCTAssertInRange(report.activityTuning.ambientEnemyLimit, CinematicTuning.ambientEnemyLimitRange)
                XCTAssertInRange(report.activityTuning.activityLightBoost, CinematicTuning.activityLightBoostRange)
                XCTAssertFinite(report.activityTuning.activityPressureScale)
                XCTAssertGreaterThan(report.activityTuning.activityPressureScale, 0)

                for snapshot in report.cameraSnapshots {
                    XCTAssertFinite(snapshot.position)
                    XCTAssertInRange(snapshot.fieldOfView, CinematicTuning.cameraFieldOfViewRange)
                    XCTAssertGreaterThanOrEqual(snapshot.transitionDuration, 0.16)
                }
            }
        }
    }

    func testSummaryRowsAreDeterministicallyOrderedAndBounded() {
        let report = makeReport(
            CinematicDiagnosticsInput(
                repoName: "Compass Diagnostics Surface With A Deliberately Long Repository Name",
                phase: "Developing",
                immediateTitle: "Add current cinematic diagnostics export rows with a deliberately long title",
                completedCount: 7,
                latestEvent: nil,
                languageProfile: languageProfile(primaryLanguage: .swift),
                activityProfile: activityProfile(worktreeChanges: worktreeChanges(modified: 12)),
                influenceSettings: CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 0.9)
            )
        )

        let summary = CinematicDiagnosticsSummary(report: report)

        XCTAssertEqual(
            summary.rows.map(\.id),
            [
                "repository",
                "immediate",
                "language-motif",
                "activity-motif",
                "stage-beat",
                "world-quest",
                "world-arena",
                "world-activity",
                "set-dressing",
                "textures",
                "activity-tuning",
                "camera-tuning",
                "camera-follow",
                "camera-shot-home",
                "camera-shot-wide",
                "camera-shot-cast-prep",
                "camera-shot-over-shoulder",
                "camera-shot-impact",
                "camera-shot-overhead",
                "camera-shot-failure",
                "camera-shot-victory"
            ]
        )
        XCTAssertEqual(summary.rows.count, CinematicDiagnosticsSummary.maxRows)

        for row in summary.rows {
            XCTAssertLessThanOrEqual(row.label.count, CinematicDiagnosticsSummary.labelMaxCharacters)
            XCTAssertLessThanOrEqual(row.detail.count, CinematicDiagnosticsSummary.detailMaxCharacters)
            XCTAssertFalse(row.label.isEmpty)
            XCTAssertFalse(row.detail.isEmpty)
        }
    }

    func testSummaryExportIncludesMotifSetDressingAndCameraIdentifiers() {
        let report = makeReport(
            CinematicDiagnosticsInput(
                repoName: "Compass",
                phase: "Verifying",
                immediateTitle: "Expose current diagnostics",
                completedCount: 3,
                latestEvent: CinematicBriefingEvent(
                    line: LiveLine(
                        level: .success,
                        text: "Verify passed",
                        detail: "swift test passed",
                        kind: .command,
                        status: .completed
                    )
                ),
                languageProfile: languageProfile(primaryLanguage: .swift),
                activityProfile: activityProfile(recentCommitCount: 2),
                influenceSettings: CinematicInfluenceSettings(cameraStyle: .steady, intensity: 0.2)
            )
        )

        let summary = CinematicDiagnosticsSummary(report: report)

        XCTAssertTrue(summary.exportText.hasPrefix("Cinematic Diagnostics\n"))
        XCTAssertEqual(summary.exportText.components(separatedBy: "\n").count, summary.rows.count + 2)
        XCTAssertTrue(summary.exportText.contains(report.languageMotif.sigilIdentifier))
        XCTAssertTrue(summary.exportText.contains(report.languageMotif.styleIdentifier))
        XCTAssertTrue(summary.exportText.contains(report.activityMotif.sigilIdentifier))
        XCTAssertTrue(summary.exportText.contains(report.activityMotif.styleIdentifier))
        XCTAssertTrue(summary.exportText.contains(report.stageBeat.kindIdentifier))
        XCTAssertTrue(summary.exportText.contains(report.stageBeat.cameraShotIdentifier))
        XCTAssertTrue(summary.exportText.contains(report.setDressing.languageArchitectureIdentifier))
        XCTAssertTrue(summary.exportText.contains(report.setDressing.activityMarkerIdentifier))
        XCTAssertTrue(summary.exportText.contains(report.setDressing.materialTextureVariantIdentifier))
        XCTAssertTrue(summary.exportText.contains(report.setDressing.backdropTextureName))
        XCTAssertTrue(summary.exportText.contains(report.setDressing.arenaTextureName))
        XCTAssertTrue(summary.exportText.contains(report.cameraTuning.identifier))
        XCTAssertTrue(summary.exportText.contains(report.cameraSnapshots[0].identifier))
        XCTAssertTrue(summary.exportText.contains(report.cameraSnapshots[3].shotIdentifier))
    }

    func testCurrentReportUsesCompassProjectInputs() async {
        await MainActor.run {
            let repoURL = URL(fileURLWithPath: "/tmp/CurrentDiagnosticsRepo", isDirectory: true)
            let project = CompassProject(
                repoURL: repoURL,
                cinematicInfluenceSettings: CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 0.75)
            )
            project.state = PlanState(
                completed: ["Stage diagnostics", "Wire copy action"],
                immediate: PlanNext(
                    plan: "Expose current cinematic diagnostics\nKeep behavior unchanged",
                    verify: "swift test"
                ),
                midTerm: "",
                longTerm: ""
            )
            project.phase = .developing
            project.languageProfile = languageProfile(primaryLanguage: .python)
            project.activityProfile = activityProfile(recentCommitCount: 1)
            project.liveLog = [
                LiveLine(
                    level: .success,
                    text: "Generated diagnostics report",
                    detail: "Current motif state is ready",
                    kind: .agentMessage,
                    status: .completed
                )
            ]

            let report = CinematicDiagnostics.currentReport(for: project)
            let expected = CinematicDiagnostics.report(
                repoName: "CurrentDiagnosticsRepo",
                phase: "Developing",
                immediateTitle: "Expose current cinematic diagnostics",
                completedCount: 2,
                latestEvent: project.liveLog.last.map(CinematicBriefingEvent.init(line:)),
                languageProfile: project.languageProfile,
                activityProfile: project.activityProfile,
                influenceSettings: project.cinematicInfluenceSettings
            )

            XCTAssertEqual(report, expected)
            XCTAssertEqual(report.repoName, "CurrentDiagnosticsRepo")
            XCTAssertEqual(report.phase, "Developing")
            XCTAssertEqual(report.immediateTitle, "Expose current cinematic diagnostics")
            XCTAssertEqual(report.completedCount, 2)
            XCTAssertEqual(report.languageMotif.sigilIdentifier, "language.python")
            XCTAssertEqual(report.activityMotif.eventKindIdentifier, "commit")
            XCTAssertEqual(report.stageBeat.phaseIdentifier, "Developing")
            XCTAssertEqual(report.stageBeat.kindIdentifier, "developing")
            XCTAssertEqual(report.stageBeat.cameraShotIdentifier, "cast-prep")
            XCTAssertEqual(report.stageBeat.activityEventKindIdentifier, "commit")
            XCTAssertTrue(report.stageBeat.shouldRunHistoryChains)
            XCTAssertEqual(report.influenceIdentifier, "dramatic|0.7500")
        }
    }

    func testSummaryOutputIsStableAcrossRepeatedCalls() {
        let report = makeReport(
            CinematicDiagnosticsInput(
                repoName: "Compass",
                phase: "Recovering",
                immediateTitle: "Stabilize diagnostics export",
                completedCount: 4,
                latestEvent: nil,
                languageProfile: languageProfile(primaryLanguage: .rust),
                activityProfile: activityProfile(worktreeChanges: worktreeChanges(conflicted: 1)),
                influenceSettings: CinematicInfluenceSettings(cameraStyle: .follow, intensity: 0.5)
            )
        )

        let first = CinematicDiagnosticsSummary(report: report)
        let second = CinematicDiagnosticsSummary(report: report)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.exportText, second.exportText)
    }
}

private struct CinematicDiagnosticsInput {
    var repoName: String
    var phase: String
    var immediateTitle: String
    var completedCount: Int
    var latestEvent: CinematicBriefingEvent?
    var languageProfile: RepositoryLanguageProfile
    var activityProfile: RepositoryActivityProfile
    var influenceSettings: CinematicInfluenceSettings
}

private func makeReport(_ input: CinematicDiagnosticsInput) -> CinematicDiagnosticsReport {
    CinematicDiagnostics.report(
        repoName: input.repoName,
        phase: input.phase,
        immediateTitle: input.immediateTitle,
        completedCount: input.completedCount,
        latestEvent: input.latestEvent,
        languageProfile: input.languageProfile,
        activityProfile: input.activityProfile,
        influenceSettings: input.influenceSettings
    )
}

private func languageProfile(primaryLanguage: RepositoryLanguage) -> RepositoryLanguageProfile {
    var counts = RepositoryLanguageCounts()
    counts[primaryLanguage] = primaryLanguage == .unknown ? 0 : 4
    return RepositoryLanguageProfile(
        counts: counts,
        manifestHints: [],
        primaryLanguage: primaryLanguage,
        scannedFileCount: primaryLanguage == .unknown ? 0 : 4,
        scannedDirectoryCount: primaryLanguage == .unknown ? 0 : 1,
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
    _ text: CinematicDiagnosticsReport.WorldTextSnapshot,
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

private func XCTAssertInRange<T: Comparable>(
    _ value: T,
    _ range: ClosedRange<T>,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertGreaterThanOrEqual(value, range.lowerBound, file: file, line: line)
    XCTAssertLessThanOrEqual(value, range.upperBound, file: file, line: line)
}

private func XCTAssertFinite(
    _ value: Float,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertTrue(value.isFinite, file: file, line: line)
}

private func XCTAssertFinite(
    _ value: SIMD3<Float>,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertTrue(value.x.isFinite, file: file, line: line)
    XCTAssertTrue(value.y.isFinite, file: file, line: line)
    XCTAssertTrue(value.z.isFinite, file: file, line: line)
}
