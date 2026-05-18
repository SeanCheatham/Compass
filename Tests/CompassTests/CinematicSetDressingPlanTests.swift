import Foundation
@testable import Compass
import XCTest

final class CinematicSetDressingPlanTests: XCTestCase {
    func testPlanIdentifiersAreStableForSameInputs() {
        let settings = CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 0.7)
        let languageProfile = languageProfile(primaryLanguage: .swift)
        let activityProfile = activityProfile(worktreeChanges: worktreeChanges(modified: 3))

        let plan = CinematicSetDressingPlanner.plan(
            languageProfile: languageProfile,
            activityProfile: activityProfile,
            influenceSettings: settings
        )
        let repeated = CinematicSetDressingPlanner.plan(
            languageProfile: languageProfile,
            activityProfile: activityProfile,
            influenceSettings: settings
        )

        XCTAssertEqual(plan, repeated)
        XCTAssertEqual(plan.languageArchitecture.architectureIdentifier, "comet-spires")
        XCTAssertEqual(plan.languageArchitecture.sigilIdentifier, "language.swift")
        XCTAssertEqual(plan.activityMarker.eventKindIdentifier, "dirty")
        XCTAssertEqual(plan.activityMarker.transitionSpellIdentifier, "pressure")
        XCTAssertTrue(plan.identifier.contains(plan.languageArchitecture.identifier))
        XCTAssertTrue(plan.identifier.contains(plan.activityMarker.identifier))
    }

    func testRepresentativeLanguagesAndActivityStatesProduceDistinctSnapshots() {
        let settings = CinematicInfluenceSettings()
        let cleanActivity = activityProfile()
        let languagePlans = RepositoryLanguage.allCases.map { language in
            CinematicSetDressingPlanner.plan(
                languageProfile: languageProfile(primaryLanguage: language),
                activityProfile: cleanActivity,
                influenceSettings: settings
            )
        }

        XCTAssertEqual(
            Set(languagePlans.map(\.languageArchitecture.sigilIdentifier)).count,
            RepositoryLanguage.allCases.count
        )
        XCTAssertEqual(
            Set(languagePlans.map(\.materialTextureVariants.backdropTextureAsset.routeIdentifier)),
            CinematicTextureAssetCatalog.expectedRouteIdentifiers(for: .backdrop)
        )
        XCTAssertEqual(
            Set(languagePlans.map(\.materialTextureVariants.backdropTextureName)),
            CinematicTextureAssetCatalog.generatedBackdropNames
        )
        XCTAssertGreaterThan(Set(languagePlans.map(\.languageArchitecture.architectureIdentifier)).count, 5)
        XCTAssertGreaterThan(Set(languagePlans.map(\.pedestalFlames.pedestalCount)).count, 2)
        XCTAssertGreaterThan(Set(languagePlans.map(\.materialTextureVariants.pedestalMaterialIdentifier)).count, 5)

        let activityPlans = CinematicDiagnostics.representativeActivityCases().map { activityCase in
            CinematicSetDressingPlanner.plan(
                languageProfile: languageProfile(primaryLanguage: .swift),
                activityProfile: activityCase.profile,
                influenceSettings: settings
            )
        }

        XCTAssertEqual(
            Set(activityPlans.map(\.activityMarker.eventKindIdentifier)),
            Set(CinematicActivityEventKind.allCases.map(\.rawValue))
        )
        XCTAssertEqual(
            Set(activityPlans.map(\.materialTextureVariants.arenaTextureAsset.routeIdentifier)),
            CinematicTextureAssetCatalog.expectedRouteIdentifiers(for: .arena)
        )
        XCTAssertEqual(
            Set(activityPlans.map(\.activityMarker.identifier)).count,
            CinematicDiagnostics.representativeActivityCases().filter { $0.hasRepository }.count
        )
        XCTAssertTrue(
            Set(activityPlans.map(\.activityMarker.pressureLevelIdentifier))
                .isSuperset(of: ["clean", "light", "moderate", "heavy"])
        )
    }

    func testTextureCatalogRoutesEveryRepresentativeCaseToBundledNames() {
        let settings = CinematicInfluenceSettings()

        for language in RepositoryLanguage.allCases {
            let motif = CinematicMotif.language(for: language)
            let expectedBackdrop = CinematicTextureAssetCatalog.backdropAsset(for: motif.style)
            let plan = CinematicSetDressingPlanner.plan(
                languageProfile: languageProfile(primaryLanguage: language),
                activityProfile: activityProfile(),
                influenceSettings: settings
            )

            XCTAssertEqual(plan.materialTextureVariants.backdropTextureAsset, expectedBackdrop)
            XCTAssertEqual(
                plan.materialTextureVariants.backdropTextureName,
                CinematicTextureAssetCatalog.generatedBackdropTextureName(for: motif.style)
            )
            assertTextureAssetIsBounded(expectedBackdrop, file: #filePath, line: #line)
            XCTAssertTrue(CinematicTextureAssetCatalog.isGeneratedBackdropTextureName(expectedBackdrop.textureName))
            XCTAssertTrue(CinematicTextureAssetCatalog.isPackagedResourceAvailable(for: expectedBackdrop))
            XCTAssertTrue(
                CinematicTextureAssetCatalog.recognizes(plan.materialTextureVariants.backdropTextureName, role: .backdrop)
            )
            XCTAssertFalse(plan.materialTextureVariants.usesFallbackTextureAsset)
        }

        for activityCase in CinematicDiagnostics.representativeActivityCases() {
            let eventKind = CinematicMotif.activity(for: activityCase.profile).eventKind
            let expectedArena = CinematicTextureAssetCatalog.arenaAsset(for: eventKind)
            let plan = CinematicSetDressingPlanner.plan(
                languageProfile: languageProfile(primaryLanguage: .swift),
                activityProfile: activityCase.profile,
                influenceSettings: settings
            )

            XCTAssertEqual(plan.materialTextureVariants.arenaTextureAsset, expectedArena)
            assertTextureAssetIsBounded(expectedArena, file: #filePath, line: #line)
            XCTAssertTrue(
                CinematicTextureAssetCatalog.recognizes(plan.materialTextureVariants.arenaTextureName, role: .arena)
            )
            XCTAssertFalse(plan.materialTextureVariants.usesFallbackTextureAsset)
        }
    }

    func testGeneratedBackdropAssetsAreUniquePackagedAndKeepFallbacks() {
        let generatedAssets = CinematicLanguageSigilStyle.allCases.map(CinematicTextureAssetCatalog.backdropAsset)
        let generatedNames = Set(generatedAssets.map(\.textureName))

        XCTAssertEqual(generatedNames, CinematicTextureAssetCatalog.generatedBackdropNames)
        XCTAssertEqual(generatedNames.count, CinematicLanguageSigilStyle.allCases.count)
        XCTAssertEqual(CinematicTextureAssetCatalog.backdropFallbackNames, ["void-arches", "void-arches-v2"])

        for asset in generatedAssets {
            XCTAssertTrue(CinematicTextureAssetCatalog.isGeneratedBackdropTextureName(asset.textureName))
            XCTAssertTrue(CinematicTextureAssetCatalog.isPackagedResourceAvailable(for: asset))
            XCTAssertFalse(asset.usesFallback)
            assertTextureAssetIsBounded(asset, file: #filePath, line: #line)
        }

        for fallbackName in CinematicTextureAssetCatalog.backdropFallbackNames {
            XCTAssertTrue(CinematicTextureAssetCatalog.recognizes(fallbackName, role: .backdrop))
            XCTAssertFalse(CinematicTextureAssetCatalog.isGeneratedBackdropTextureName(fallbackName))
            XCTAssertTrue(CinematicTextureAssetCatalog.isPackagedResourceAvailable(fallbackName, role: .backdrop))
        }
    }

    func testTextureCatalogPreservesExistingRealityKitTextureNames() {
        let settings = CinematicInfluenceSettings()
        let dirtySwift = CinematicSetDressingPlanner.plan(
            languageProfile: languageProfile(primaryLanguage: .swift),
            activityProfile: activityProfile(worktreeChanges: worktreeChanges(modified: 2)),
            influenceSettings: settings
        )
        let cleanMarkdown = CinematicSetDressingPlanner.plan(
            languageProfile: languageProfile(primaryLanguage: .markdown),
            activityProfile: activityProfile(),
            influenceSettings: settings
        )
        let commitSwift = CinematicSetDressingPlanner.plan(
            languageProfile: languageProfile(primaryLanguage: .swift),
            activityProfile: activityProfile(recentCommitCount: 1),
            influenceSettings: settings
        )

        XCTAssertEqual(dirtySwift.materialTextureVariants.backdropTextureName, "swift-comet-backdrop")
        XCTAssertEqual(dirtySwift.materialTextureVariants.arenaTextureName, "arena-runes-v3")
        XCTAssertEqual(cleanMarkdown.materialTextureVariants.backdropTextureName, "markdown-rune-backdrop")
        XCTAssertEqual(cleanMarkdown.materialTextureVariants.arenaTextureName, "arena-runes-v3")
        XCTAssertEqual(commitSwift.materialTextureVariants.arenaTextureName, "arena-runes-v2")

        for textureName in [
            dirtySwift.materialTextureVariants.backdropTextureName,
            dirtySwift.materialTextureVariants.arenaTextureName,
            cleanMarkdown.materialTextureVariants.backdropTextureName,
            cleanMarkdown.materialTextureVariants.arenaTextureName,
            commitSwift.materialTextureVariants.arenaTextureName
        ] {
            XCTAssertFalse(textureName.contains("/"))
            XCTAssertFalse(textureName.hasSuffix(".png"))
            XCTAssertTrue(CinematicTextureAssetCatalog.recognizesBundledTextureName(textureName))
        }

        XCTAssertTrue(CinematicTextureAssetCatalog.recognizesBundledTextureName("void-arches"))
        XCTAssertTrue(CinematicTextureAssetCatalog.recognizesBundledTextureName("void-arches-v2"))
    }

    func testPlanValuesStayInsideBoundedRanges() {
        let settingsSamples = [
            CinematicInfluenceSettings(cameraStyle: .steady, intensity: 0),
            CinematicInfluenceSettings(cameraStyle: .follow, intensity: CinematicInfluenceSettings.defaultIntensity),
            CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 1)
        ]

        for settings in settingsSamples {
            for language in RepositoryLanguage.allCases {
                for activityCase in CinematicDiagnostics.representativeActivityCases() {
                    let plan = CinematicSetDressingPlanner.plan(
                        languageProfile: languageProfile(primaryLanguage: language),
                        activityProfile: activityCase.profile,
                        influenceSettings: settings
                    )
                    assertPlanInBounds(plan, file: #filePath, line: #line)
                }
            }
        }
    }

    func testDiagnosticsReportIncludesSetDressingSnapshot() {
        let settings = CinematicInfluenceSettings(cameraStyle: .steady, intensity: 0.2)
        let languageProfile = languageProfile(primaryLanguage: .rust)
        let activityProfile = activityProfile(
            worktreeChanges: worktreeChanges(conflicted: 1),
            lastTerminalStatus: .failed,
            failureStreak: 1
        )
        let plan = CinematicSetDressingPlanner.plan(
            languageProfile: languageProfile,
            activityProfile: activityProfile,
            influenceSettings: settings
        )
        let report = CinematicDiagnostics.report(
            repoName: "Compass",
            phase: "Recovering",
            immediateTitle: "Inspect deterministic set dressing",
            completedCount: 2,
            latestEvent: nil,
            languageProfile: languageProfile,
            activityProfile: activityProfile,
            influenceSettings: settings
        )

        XCTAssertEqual(report.setDressing.identifier, plan.identifier)
        XCTAssertEqual(report.setDressing.languageArchitectureIdentifier, plan.languageArchitecture.identifier)
        XCTAssertEqual(report.setDressing.activityMarkerIdentifier, plan.activityMarker.identifier)
        XCTAssertEqual(report.setDressing.pedestalCount, plan.pedestalFlames.pedestalCount)
        XCTAssertEqual(report.setDressing.shardCount, plan.floatingShards.shardCount)
        XCTAssertEqual(report.setDressing.ambientSpawnCadence, plan.ambientSpawnCadence)
        XCTAssertEqual(report.setDressing.ambientEnemyLimit, plan.ambientEnemyLimit)
        XCTAssertEqual(
            report.setDressing.backdropTextureAssetIdentifier,
            plan.materialTextureVariants.backdropTextureAsset.identifier
        )
        XCTAssertEqual(
            report.setDressing.arenaTextureAssetIdentifier,
            plan.materialTextureVariants.arenaTextureAsset.identifier
        )
        XCTAssertEqual(
            report.setDressing.textureRoleCoverageIdentifier,
            plan.materialTextureVariants.textureRoleCoverageIdentifier
        )
        XCTAssertTrue(report.identifier.contains("set-dressing:\(plan.identifier)"))
    }

    func testExtremeInputsClampSetDressingValues() {
        let extremeActivity = activityProfile(
            worktreeChanges: worktreeChanges(modified: 500, untracked: 500, conflicted: 12),
            recentCommitCount: 80,
            lastTerminalStatus: .failed,
            successStreak: 40,
            failureStreak: 25,
            recoveredFromFailure: true
        )
        let intensePlan = CinematicSetDressingPlanner.plan(
            languageProfile: languageProfile(primaryLanguage: .rust),
            activityProfile: extremeActivity,
            influenceSettings: CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 99)
        )
        let quietPlan = CinematicSetDressingPlanner.plan(
            languageProfile: languageProfile(primaryLanguage: .unknown),
            activityProfile: .empty,
            influenceSettings: CinematicInfluenceSettings(cameraStyle: .steady, intensity: -99)
        )

        assertPlanInBounds(intensePlan, file: #filePath, line: #line)
        assertPlanInBounds(quietPlan, file: #filePath, line: #line)
        XCTAssertEqual(intensePlan.pedestalFlames.pedestalCount, CinematicSetDressingPlan.pedestalCountRange.upperBound)
        XCTAssertEqual(intensePlan.floatingShards.shardCount, CinematicSetDressingPlan.shardCountRange.upperBound)
        XCTAssertEqual(quietPlan.pedestalFlames.pedestalCount, CinematicSetDressingPlan.pedestalCountRange.lowerBound)
        XCTAssertEqual(quietPlan.floatingShards.shardCount, CinematicSetDressingPlan.shardCountRange.lowerBound)
    }
}

private func assertPlanInBounds(
    _ plan: CinematicSetDressingPlan,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertInRange(plan.pedestalFlames.pedestalCount, CinematicSetDressingPlan.pedestalCountRange, file: file, line: line)
    XCTAssertInRange(plan.pedestalFlames.flameLightIntensity, CinematicSetDressingPlan.flameLightIntensityRange, file: file, line: line)
    XCTAssertInRange(plan.pedestalFlames.flameOpacity, CinematicSetDressingPlan.flameOpacityRange, file: file, line: line)
    XCTAssertInRange(plan.pedestalFlames.rimOpacity, CinematicSetDressingPlan.rimOpacityRange, file: file, line: line)
    XCTAssertInRange(plan.pedestalFlames.flameXZScale, CinematicSetDressingPlan.flameScaleRange, file: file, line: line)
    XCTAssertInRange(plan.pedestalFlames.flameHeightScale, CinematicSetDressingPlan.flameHeightScaleRange, file: file, line: line)
    XCTAssertInRange(plan.pedestalFlames.activityTintFraction, CinematicSetDressingPlan.activityTintBlendRange, file: file, line: line)
    XCTAssertInRange(plan.floatingShards.shardCount, CinematicSetDressingPlan.shardCountRange, file: file, line: line)
    XCTAssertInRange(plan.floatingShards.opacity, CinematicSetDressingPlan.shardOpacityRange, file: file, line: line)
    XCTAssertInRange(plan.floatingShards.emissionOpacity, CinematicSetDressingPlan.shardEmissionOpacityRange, file: file, line: line)
    XCTAssertInRange(plan.floatingShards.activityTintFraction, CinematicSetDressingPlan.activityTintBlendRange, file: file, line: line)
    XCTAssertInRange(plan.runeIntensity.segmentRadiusScale, CinematicSetDressingPlan.segmentRadiusScaleRange, file: file, line: line)
    XCTAssertInRange(plan.runeIntensity.coreScale, CinematicSetDressingPlan.sigilCoreScaleRange, file: file, line: line)
    XCTAssertInRange(plan.runeIntensity.activityPulseScale, CinematicSetDressingPlan.runeIntensityRange, file: file, line: line)
    XCTAssertInRange(plan.animationCadence.flamePulseRate, CinematicSetDressingPlan.flamePulseRateRange, file: file, line: line)
    XCTAssertInRange(plan.animationCadence.flamePulseAmplitude, CinematicSetDressingPlan.flamePulseAmplitudeRange, file: file, line: line)
    XCTAssertInRange(plan.animationCadence.shardBobRate, CinematicSetDressingPlan.shardBobRateRange, file: file, line: line)
    XCTAssertInRange(plan.animationCadence.shardBobAmplitude, CinematicSetDressingPlan.shardBobAmplitudeRange, file: file, line: line)
    XCTAssertInRange(plan.animationCadence.shardRotationStep, CinematicSetDressingPlan.shardRotationStepRange, file: file, line: line)
    XCTAssertInRange(plan.ambientSpawnCadence, CinematicTuning.ambientSpawnCadenceRange, file: file, line: line)
    XCTAssertInRange(plan.ambientEnemyLimit, CinematicTuning.ambientEnemyLimitRange, file: file, line: line)
    XCTAssertInRange(plan.activityLightBoost, CinematicTuning.activityLightBoostRange, file: file, line: line)
}

private func assertTextureAssetIsBounded(
    _ asset: CinematicTextureAsset,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertLessThanOrEqual(asset.identifier.count, CinematicTextureAssetCatalog.identifierMaxCharacters, file: file, line: line)
    XCTAssertFalse(asset.identifier.isEmpty, file: file, line: line)
    XCTAssertFalse(asset.routeIdentifier.isEmpty, file: file, line: line)
    XCTAssertFalse(asset.requestedTextureName.isEmpty, file: file, line: line)
    XCTAssertFalse(asset.textureName.isEmpty, file: file, line: line)
    XCTAssertFalse(asset.fallbackTextureName.isEmpty, file: file, line: line)
    XCTAssertFalse(asset.textureName.contains("/"), file: file, line: line)
    XCTAssertFalse(asset.textureName.hasSuffix(".png"), file: file, line: line)
    XCTAssertTrue(
        CinematicTextureAssetCatalog.recognizes(asset.textureName, role: asset.role),
        file: file,
        line: line
    )
    XCTAssertTrue(
        CinematicTextureAssetCatalog.recognizes(asset.fallbackTextureName, role: asset.role),
        file: file,
        line: line
    )
    XCTAssertTrue(CinematicTextureAssetCatalog.isPackagedResourceAvailable(for: asset), file: file, line: line)
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

private func XCTAssertInRange<T: Comparable>(
    _ value: T,
    _ range: ClosedRange<T>,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertGreaterThanOrEqual(value, range.lowerBound, file: file, line: line)
    XCTAssertLessThanOrEqual(value, range.upperBound, file: file, line: line)
}
