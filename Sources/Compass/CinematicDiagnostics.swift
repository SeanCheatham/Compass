import Foundation

struct CinematicDiagnosticsReport: Equatable {
    var identifier: String
    var repoName: String
    var phase: String
    var immediateTitle: String
    var completedCount: Int
    var influenceIdentifier: String
    var languageMotif: LanguageMotifSnapshot
    var activityMotif: ActivityMotifSnapshot
    var worldText: WorldTextSnapshot
    var briefing: BriefingSnapshot
    var cameraTuning: CameraTuningSnapshot
    var activityTuning: ActivityTuningSnapshot
    var setDressing: SetDressingSnapshot
    var cameraSnapshots: [CameraSnapshot]

    struct LanguageMotifSnapshot: Equatable {
        var identifier: String
        var language: RepositoryLanguage
        var sigilIdentifier: String
        var styleIdentifier: String
        var ambientSpellIdentifier: String
        var phaseBlend: Double
    }

    struct ActivityMotifSnapshot: Equatable {
        var identifier: String
        var eventKindIdentifier: String
        var sigilIdentifier: String
        var styleIdentifier: String
        var tintSourceIdentifier: String?
        var transitionSpellIdentifier: String?
        var ambientOverrideIdentifier: String?
        var usesCommitAmbient: Bool
        var usesSuccessAmbient: Bool
        var shouldShakeOnTransition: Bool
    }

    struct WorldTextSnapshot: Equatable {
        var identifier: String
        var questLabel: String
        var arenaCallout: String
        var activityCallout: String
    }

    struct BriefingSnapshot: Equatable {
        var identifier: String
        var title: String
        var detail: String
    }

    struct CameraTuningSnapshot: Equatable {
        var identifier: String
        var orbitScale: Float
        var pullbackScale: Float
        var heightOffset: Float
        var followResponsiveness: Float
        var followFieldOfView: Float
        var driftScale: Float
        var shakeScale: Float
    }

    struct ActivityTuningSnapshot: Equatable {
        var identifier: String
        var pressureLevelIdentifier: String
        var ambientSpawnCadence: TimeInterval
        var ambientEnemyLimit: Int
        var activityLightBoost: Float
        var activityPressureScale: Float
    }

    struct SetDressingSnapshot: Equatable {
        var identifier: String
        var languageArchitectureIdentifier: String
        var activityMarkerIdentifier: String
        var pedestalCount: Int
        var flameLightIntensity: Float
        var flameOpacity: Float
        var rimOpacity: Float
        var shardCount: Int
        var shardEmissionOpacity: Float
        var runeIntensityIdentifier: String
        var animationCadenceIdentifier: String
        var flamePulseRate: Float
        var shardBobRate: Float
        var ambientSpawnCadence: TimeInterval
        var ambientEnemyLimit: Int
        var activityLightBoost: Float
        var materialTextureVariantIdentifier: String
        var backdropTextureName: String
        var arenaTextureName: String
    }

    struct CameraSnapshot: Equatable {
        var identifier: String
        var shotIdentifier: String
        var position: SIMD3<Float>
        var fieldOfView: Float
        var transitionDuration: TimeInterval
    }
}

enum CinematicDiagnostics {
    struct ActivityCase: Equatable {
        var identifier: String
        var phase: String
        var immediateTitle: String
        var completedCount: Int
        var profile: RepositoryActivityProfile
    }

    static func report(
        repoName: String,
        phase: String,
        immediateTitle: String,
        completedCount: Int,
        latestEvent: CinematicBriefingEvent?,
        languageProfile: RepositoryLanguageProfile,
        activityProfile: RepositoryActivityProfile,
        influenceSettings: CinematicInfluenceSettings
    ) -> CinematicDiagnosticsReport {
        let languageMotif = CinematicMotif.language(for: languageProfile)
        let activityMotif = CinematicMotif.activity(for: activityProfile)
        let briefing = CinematicBriefingService.deterministicBriefing(
            for: CinematicBriefingInput(
                repoName: repoName,
                currentPhase: phase,
                immediatePlanTitle: immediateTitle,
                completedCount: completedCount,
                latestEvent: latestEvent
            )
        )
        let worldText = CinematicWorldTextService.deterministicWorldText(
            for: CinematicWorldTextInput(
                repoName: repoName,
                currentPhase: phase,
                immediatePlanTitle: immediateTitle,
                completedCount: completedCount,
                latestEvent: latestEvent,
                languageProfile: languageProfile,
                activityProfile: activityProfile
            )
        )
        let influenceIdentifier = settingsIdentifier(influenceSettings)
        let languageSnapshot = languageSnapshot(for: languageMotif)
        let activitySnapshot = activitySnapshot(for: activityMotif)
        let worldTextSnapshot = worldTextSnapshot(for: worldText)
        let briefingSnapshot = briefingSnapshot(for: briefing)
        let cameraTuningSnapshot = cameraTuningSnapshot(settings: influenceSettings)
        let activityTuningSnapshot = activityTuningSnapshot(
            activityProfile: activityProfile,
            settings: influenceSettings
        )
        let setDressingPlan = CinematicSetDressingPlanner.plan(
            languageMotif: languageMotif,
            activityMotif: activityMotif,
            languageProfile: languageProfile,
            activityProfile: activityProfile,
            influenceSettings: influenceSettings
        )
        let setDressingSnapshot = setDressingSnapshot(for: setDressingPlan)
        let cameraSnapshots = CinematicCameraShot.allCases.map {
            cameraSnapshot(for: $0, settings: influenceSettings)
        }

        return CinematicDiagnosticsReport(
            identifier: [
                "repo:\(repoName)",
                "phase:\(phase)",
                "language:\(languageSnapshot.identifier)",
                "activity:\(activitySnapshot.identifier)",
                "influence:\(influenceIdentifier)",
                "set-dressing:\(setDressingSnapshot.identifier)"
            ].joined(separator: "|"),
            repoName: repoName,
            phase: phase,
            immediateTitle: immediateTitle,
            completedCount: completedCount,
            influenceIdentifier: influenceIdentifier,
            languageMotif: languageSnapshot,
            activityMotif: activitySnapshot,
            worldText: worldTextSnapshot,
            briefing: briefingSnapshot,
            cameraTuning: cameraTuningSnapshot,
            activityTuning: activityTuningSnapshot,
            setDressing: setDressingSnapshot,
            cameraSnapshots: cameraSnapshots
        )
    }

    static func representativeSmokeMatrix(
        influenceSettings: CinematicInfluenceSettings = CinematicInfluenceSettings()
    ) -> [CinematicDiagnosticsReport] {
        RepositoryLanguage.allCases.flatMap { language in
            representativeActivityCases().map { activityCase in
                report(
                    repoName: "Diagnostics \(language.displayName)",
                    phase: activityCase.phase,
                    immediateTitle: activityCase.immediateTitle,
                    completedCount: activityCase.completedCount,
                    latestEvent: nil,
                    languageProfile: representativeLanguageProfile(for: language),
                    activityProfile: activityCase.profile,
                    influenceSettings: influenceSettings
                )
            }
        }
    }

    static func representativeActivityCases() -> [ActivityCase] {
        [
            ActivityCase(
                identifier: "unavailable",
                phase: "Staging",
                immediateTitle: "No immediate plan",
                completedCount: 0,
                profile: .empty
            ),
            ActivityCase(
                identifier: "clean",
                phase: "Developing",
                immediateTitle: "Add deterministic cinematic diagnostics",
                completedCount: 1,
                profile: activityProfile()
            ),
            ActivityCase(
                identifier: "dirty-light",
                phase: "Developing",
                immediateTitle: "Update renderer smoke copy",
                completedCount: 2,
                profile: activityProfile(worktreeChanges: worktreeChanges(modified: 2))
            ),
            ActivityCase(
                identifier: "dirty-moderate",
                phase: "Developing",
                immediateTitle: "Refine camera pressure tuning",
                completedCount: 3,
                profile: activityProfile(worktreeChanges: worktreeChanges(modified: 8))
            ),
            ActivityCase(
                identifier: "dirty-heavy",
                phase: "Verifying",
                immediateTitle: "Stabilize intense activity tuning",
                completedCount: 4,
                profile: activityProfile(worktreeChanges: worktreeChanges(modified: 16))
            ),
            ActivityCase(
                identifier: "conflicted",
                phase: "Recovering",
                immediateTitle: "Resolve deterministic cinematic conflict",
                completedCount: 2,
                profile: activityProfile(worktreeChanges: worktreeChanges(conflicted: 1))
            ),
            ActivityCase(
                identifier: "commit",
                phase: "Committing",
                immediateTitle: "Record cinematic diagnostics commit",
                completedCount: 5,
                profile: activityProfile(recentCommitCount: 2)
            ),
            ActivityCase(
                identifier: "success",
                phase: "Verifying",
                immediateTitle: "Confirm cinematic diagnostics smoke path",
                completedCount: 6,
                profile: activityProfile(lastTerminalStatus: .succeeded, successStreak: 3)
            ),
            ActivityCase(
                identifier: "recovery",
                phase: "Recovering",
                immediateTitle: "Recover cinematic diagnostics after failure",
                completedCount: 3,
                profile: activityProfile(
                    lastTerminalStatus: .succeeded,
                    successStreak: 1,
                    recoveredFromFailure: true
                )
            ),
            ActivityCase(
                identifier: "failure",
                phase: "Repairing",
                immediateTitle: "Fix cinematic diagnostics failure state",
                completedCount: 1,
                profile: activityProfile(
                    recentFailedCount: 1,
                    lastTerminalStatus: .failed,
                    failureStreak: 1
                )
            )
        ]
    }

    private static func languageSnapshot(
        for motif: CinematicLanguageMotif
    ) -> CinematicDiagnosticsReport.LanguageMotifSnapshot {
        let ambientSpellIdentifier = motif.ambientSpell.diagnosticsIdentifier
        let identifier = [
            motif.sigilIdentifier,
            motif.styleIdentifier,
            ambientSpellIdentifier,
            fixed(Double(motif.phaseBlend))
        ].joined(separator: "|")

        return CinematicDiagnosticsReport.LanguageMotifSnapshot(
            identifier: identifier,
            language: motif.language,
            sigilIdentifier: motif.sigilIdentifier,
            styleIdentifier: motif.styleIdentifier,
            ambientSpellIdentifier: ambientSpellIdentifier,
            phaseBlend: Double(motif.phaseBlend)
        )
    }

    private static func activitySnapshot(
        for motif: CinematicActivityMotif
    ) -> CinematicDiagnosticsReport.ActivityMotifSnapshot {
        let tintSourceIdentifier = motif.tintSource?.diagnosticsIdentifier
        let transitionSpellIdentifier = motif.transitionSpell?.diagnosticsIdentifier
        let ambientOverrideIdentifier = motif.ambientOverride?.diagnosticsIdentifier
        let identifier = [
            motif.sigilIdentifier,
            motif.styleIdentifier,
            motif.eventKind.rawValue,
            tintSourceIdentifier ?? "none",
            transitionSpellIdentifier ?? "none",
            ambientOverrideIdentifier ?? "none"
        ].joined(separator: "|")

        return CinematicDiagnosticsReport.ActivityMotifSnapshot(
            identifier: identifier,
            eventKindIdentifier: motif.eventKind.rawValue,
            sigilIdentifier: motif.sigilIdentifier,
            styleIdentifier: motif.styleIdentifier,
            tintSourceIdentifier: tintSourceIdentifier,
            transitionSpellIdentifier: transitionSpellIdentifier,
            ambientOverrideIdentifier: ambientOverrideIdentifier,
            usesCommitAmbient: motif.usesCommitAmbient,
            usesSuccessAmbient: motif.usesSuccessAmbient,
            shouldShakeOnTransition: motif.shouldShakeOnTransition
        )
    }

    private static func worldTextSnapshot(
        for worldText: CinematicWorldText
    ) -> CinematicDiagnosticsReport.WorldTextSnapshot {
        let identifier = [
            worldText.questLabel,
            worldText.arenaCallout,
            worldText.activityCallout
        ].joined(separator: "|")

        return CinematicDiagnosticsReport.WorldTextSnapshot(
            identifier: identifier,
            questLabel: worldText.questLabel,
            arenaCallout: worldText.arenaCallout,
            activityCallout: worldText.activityCallout
        )
    }

    private static func briefingSnapshot(
        for briefing: CinematicBriefing
    ) -> CinematicDiagnosticsReport.BriefingSnapshot {
        let identifier = [briefing.title, briefing.detail].joined(separator: "|")
        return CinematicDiagnosticsReport.BriefingSnapshot(
            identifier: identifier,
            title: briefing.title,
            detail: briefing.detail
        )
    }

    private static func cameraTuningSnapshot(
        settings: CinematicInfluenceSettings
    ) -> CinematicDiagnosticsReport.CameraTuningSnapshot {
        let orbitScale = CinematicTuning.cameraOrbitScale(settings: settings)
        let pullbackScale = CinematicTuning.cameraPullbackScale(settings: settings)
        let heightOffset = CinematicTuning.cameraHeightOffset(settings: settings)
        let followResponsiveness = CinematicTuning.cameraFollowResponsiveness(settings: settings)
        let followFieldOfView = CinematicTuning.cameraFollowFieldOfView(settings: settings)
        let driftScale = CinematicTuning.cameraDriftScale(settings: settings)
        let shakeScale = CinematicTuning.cameraShakeScale(settings: settings)
        let identifier = [
            settingsIdentifier(settings),
            fixed(Double(orbitScale)),
            fixed(Double(pullbackScale)),
            fixed(Double(heightOffset)),
            fixed(Double(followResponsiveness)),
            fixed(Double(followFieldOfView)),
            fixed(Double(driftScale)),
            fixed(Double(shakeScale))
        ].joined(separator: "|")

        return CinematicDiagnosticsReport.CameraTuningSnapshot(
            identifier: identifier,
            orbitScale: orbitScale,
            pullbackScale: pullbackScale,
            heightOffset: heightOffset,
            followResponsiveness: followResponsiveness,
            followFieldOfView: followFieldOfView,
            driftScale: driftScale,
            shakeScale: shakeScale
        )
    }

    private static func activityTuningSnapshot(
        activityProfile: RepositoryActivityProfile,
        settings: CinematicInfluenceSettings
    ) -> CinematicDiagnosticsReport.ActivityTuningSnapshot {
        let ambientSpawnCadence = CinematicTuning.ambientSpawnCadence(
            activityProfile: activityProfile,
            settings: settings
        )
        let ambientEnemyLimit = CinematicTuning.ambientEnemyLimit(
            activityProfile: activityProfile,
            settings: settings
        )
        let activityLightBoost = CinematicTuning.activityLightBoost(
            activityProfile: activityProfile,
            settings: settings
        )
        let activityPressureScale = CinematicTuning.activityPressureScale(settings: settings)
        let pressureLevelIdentifier = activityProfile.pressureLevel.rawValue
        let identifier = [
            settingsIdentifier(settings),
            pressureLevelIdentifier,
            fixed(ambientSpawnCadence),
            String(ambientEnemyLimit),
            fixed(Double(activityLightBoost)),
            fixed(Double(activityPressureScale))
        ].joined(separator: "|")

        return CinematicDiagnosticsReport.ActivityTuningSnapshot(
            identifier: identifier,
            pressureLevelIdentifier: pressureLevelIdentifier,
            ambientSpawnCadence: ambientSpawnCadence,
            ambientEnemyLimit: ambientEnemyLimit,
            activityLightBoost: activityLightBoost,
            activityPressureScale: activityPressureScale
        )
    }

    private static func setDressingSnapshot(
        for plan: CinematicSetDressingPlan
    ) -> CinematicDiagnosticsReport.SetDressingSnapshot {
        CinematicDiagnosticsReport.SetDressingSnapshot(
            identifier: plan.identifier,
            languageArchitectureIdentifier: plan.languageArchitecture.identifier,
            activityMarkerIdentifier: plan.activityMarker.identifier,
            pedestalCount: plan.pedestalFlames.pedestalCount,
            flameLightIntensity: plan.pedestalFlames.flameLightIntensity,
            flameOpacity: plan.pedestalFlames.flameOpacity,
            rimOpacity: plan.pedestalFlames.rimOpacity,
            shardCount: plan.floatingShards.shardCount,
            shardEmissionOpacity: plan.floatingShards.emissionOpacity,
            runeIntensityIdentifier: plan.runeIntensity.identifier,
            animationCadenceIdentifier: plan.animationCadence.identifier,
            flamePulseRate: plan.animationCadence.flamePulseRate,
            shardBobRate: plan.animationCadence.shardBobRate,
            ambientSpawnCadence: plan.ambientSpawnCadence,
            ambientEnemyLimit: plan.ambientEnemyLimit,
            activityLightBoost: plan.activityLightBoost,
            materialTextureVariantIdentifier: plan.materialTextureVariants.identifier,
            backdropTextureName: plan.materialTextureVariants.backdropTextureName,
            arenaTextureName: plan.materialTextureVariants.arenaTextureName
        )
    }

    private static func cameraSnapshot(
        for shot: CinematicCameraShot,
        settings: CinematicInfluenceSettings
    ) -> CinematicDiagnosticsReport.CameraSnapshot {
        let position = CinematicTuning.cameraPosition(for: shot, settings: settings)
        let fieldOfView = CinematicTuning.cameraFieldOfView(for: shot, settings: settings)
        let transitionDuration = CinematicTuning.cameraTransitionDuration(for: shot, settings: settings)
        let identifier = [
            shot.identifier,
            settingsIdentifier(settings),
            positionIdentifier(position),
            fixed(Double(fieldOfView)),
            fixed(transitionDuration)
        ].joined(separator: "|")

        return CinematicDiagnosticsReport.CameraSnapshot(
            identifier: identifier,
            shotIdentifier: shot.identifier,
            position: position,
            fieldOfView: fieldOfView,
            transitionDuration: transitionDuration
        )
    }

    private static func representativeLanguageProfile(
        for language: RepositoryLanguage
    ) -> RepositoryLanguageProfile {
        var counts = RepositoryLanguageCounts()
        counts[language] = language == .unknown ? 0 : 4
        return RepositoryLanguageProfile(
            counts: counts,
            manifestHints: manifestHints(for: language),
            primaryLanguage: language,
            scannedFileCount: language == .unknown ? 0 : 4,
            scannedDirectoryCount: language == .unknown ? 0 : 1,
            wasTruncated: false
        )
    }

    private static func manifestHints(for language: RepositoryLanguage) -> [RepositoryManifestHint] {
        switch language {
        case .typeScriptJavaScript:
            return [.packageJSON]
        case .python:
            return [.pyprojectToml]
        case .go:
            return [.goMod]
        case .rust:
            return [.cargoToml]
        case .swift:
            return [.packageSwift]
        case .markdown, .other, .unknown:
            return []
        }
    }

    private static func activityProfile(
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

    private static func worktreeChanges(
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

    private static func settingsIdentifier(_ settings: CinematicInfluenceSettings) -> String {
        "\(settings.cameraStyle.rawValue)|\(fixed(settings.intensity))"
    }

    private static func positionIdentifier(_ position: SIMD3<Float>) -> String {
        [
            fixed(Double(position.x)),
            fixed(Double(position.y)),
            fixed(Double(position.z))
        ].joined(separator: ",")
    }

    private static func fixed(_ value: Float) -> String {
        fixed(Double(value))
    }

    private static func fixed(_ value: Double) -> String {
        String(format: "%.4f", value)
    }
}

private extension SpellSchool {
    var diagnosticsIdentifier: String {
        switch self {
        case .scan:
            return "scan"
        case .shell:
            return "shell"
        case .edit:
            return "edit"
        case .git:
            return "git"
        case .verify:
            return "verify"
        case .insight:
            return "insight"
        case .lifecycle:
            return "lifecycle"
        case .pressure:
            return "pressure"
        case .failure:
            return "failure"
        }
    }
}
