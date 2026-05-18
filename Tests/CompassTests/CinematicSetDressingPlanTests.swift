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
        XCTAssertEqual(
            Set(languagePlans.map(\.languageArchitecture.pedestalLayoutIdentifier)),
            CinematicSetDressingGeometryCatalog.expectedPedestalLayoutIdentifiers
        )
        XCTAssertEqual(
            Set(languagePlans.map(\.languageArchitecture.shardFormationIdentifier)),
            CinematicSetDressingGeometryCatalog.expectedShardFormationIdentifiers
        )
        XCTAssertTrue(languagePlans.allSatisfy(\.languageArchitecture.geometryIsBounded))
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
            Set(activityPlans.map(\.materialTextureVariants.arenaTextureName)),
            CinematicTextureAssetCatalog.generatedArenaNames
        )
        XCTAssertEqual(
            Set(activityPlans.map(\.materialTextureVariants.runeMaterialIdentifier)),
            CinematicRuneMaterialTreatmentCatalog.expectedRuneMaterialIdentifiers
        )
        XCTAssertEqual(
            Set(activityPlans.map(\.materialTextureVariants.runeMaterialTreatment.identifier)),
            CinematicRuneMaterialTreatmentCatalog.expectedTreatmentIdentifiers
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
            XCTAssertEqual(
                plan.materialTextureVariants.arenaTextureName,
                CinematicTextureAssetCatalog.generatedArenaTextureName(for: eventKind)
            )
            assertTextureAssetIsBounded(expectedArena, file: #filePath, line: #line)
            XCTAssertTrue(CinematicTextureAssetCatalog.isGeneratedArenaTextureName(expectedArena.textureName))
            XCTAssertTrue(CinematicTextureAssetCatalog.isPackagedResourceAvailable(for: expectedArena))
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

    func testGeneratedArenaAssetsAreUniquePackagedAndKeepFallbacks() {
        let generatedAssets = CinematicActivityEventKind.allCases.map(CinematicTextureAssetCatalog.arenaAsset)
        let generatedNames = Set(generatedAssets.map(\.textureName))

        XCTAssertEqual(generatedNames, CinematicTextureAssetCatalog.generatedArenaNames)
        XCTAssertEqual(generatedNames.count, CinematicActivityEventKind.allCases.count)
        XCTAssertEqual(CinematicTextureAssetCatalog.arenaFallbackNames, ["arena-runes", "arena-runes-v2", "arena-runes-v3"])

        for (kind, asset) in zip(CinematicActivityEventKind.allCases, generatedAssets) {
            XCTAssertEqual(asset.textureName, CinematicTextureAssetCatalog.generatedArenaTextureName(for: kind))
            XCTAssertTrue(CinematicTextureAssetCatalog.isGeneratedArenaTextureName(asset.textureName))
            XCTAssertTrue(CinematicTextureAssetCatalog.isPackagedResourceAvailable(for: asset))
            XCTAssertFalse(asset.usesFallback)
            assertTextureAssetIsBounded(asset, file: #filePath, line: #line)
        }

        for fallbackName in CinematicTextureAssetCatalog.arenaFallbackNames {
            XCTAssertTrue(CinematicTextureAssetCatalog.recognizes(fallbackName, role: .arena))
            XCTAssertFalse(CinematicTextureAssetCatalog.isGeneratedArenaTextureName(fallbackName))
            XCTAssertTrue(CinematicTextureAssetCatalog.isPackagedResourceAvailable(fallbackName, role: .arena))
        }
    }

    func testTextureCatalogUsesExtensionlessRealityKitTextureNamesAndKeepsFallbacks() {
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
        XCTAssertEqual(dirtySwift.materialTextureVariants.arenaTextureName, "dirty-arena")
        XCTAssertEqual(cleanMarkdown.materialTextureVariants.backdropTextureName, "markdown-rune-backdrop")
        XCTAssertEqual(cleanMarkdown.materialTextureVariants.arenaTextureName, "clean-arena")
        XCTAssertEqual(commitSwift.materialTextureVariants.arenaTextureName, "commit-arena")

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
        XCTAssertTrue(CinematicTextureAssetCatalog.recognizesBundledTextureName("arena-runes"))
        XCTAssertTrue(CinematicTextureAssetCatalog.recognizesBundledTextureName("arena-runes-v2"))
        XCTAssertTrue(CinematicTextureAssetCatalog.recognizesBundledTextureName("arena-runes-v3"))
    }

    func testLanguageGeometryDescriptorsAreUniqueBoundedAndKeyedByLayoutIdentifiers() {
        for language in RepositoryLanguage.allCases {
            let plan = CinematicSetDressingPlanner.plan(
                languageProfile: languageProfile(primaryLanguage: language),
                activityProfile: activityProfile(),
                influenceSettings: CinematicInfluenceSettings()
            )
            let architecture = plan.languageArchitecture

            XCTAssertEqual(architecture.pedestalSlots.count, CinematicSetDressingPlan.pedestalCountRange.upperBound)
            XCTAssertEqual(architecture.shardSlots.count, CinematicSetDressingPlan.shardCountRange.upperBound)
            XCTAssertEqual(
                Set(architecture.pedestalSlots.map(\.identifier)).count,
                architecture.pedestalSlots.count
            )
            XCTAssertEqual(
                Set(architecture.shardSlots.map(\.identifier)).count,
                architecture.shardSlots.count
            )
            XCTAssertTrue(architecture.geometryIsBounded)
            XCTAssertEqual(
                Set(architecture.pedestalSlots.map(\.layoutIdentifier)),
                Set([architecture.pedestalLayoutIdentifier])
            )
            XCTAssertEqual(
                Set(architecture.shardSlots.map(\.formationIdentifier)),
                Set([architecture.shardFormationIdentifier])
            )
            XCTAssertTrue(architecture.layoutCoverageIdentifier.contains(architecture.pedestalLayoutIdentifier))
            XCTAssertTrue(architecture.layoutCoverageIdentifier.contains(architecture.shardFormationIdentifier))

            for slot in architecture.pedestalSlots {
                assertPedestalSlotInBounds(slot, file: #filePath, line: #line)
            }
            for slot in architecture.shardSlots {
                assertShardSlotInBounds(slot, file: #filePath, line: #line)
            }
        }
    }

    func testRuneMaterialTreatmentsAreActivitySpecificAndBoundedWithoutChangingTextureRoutes() {
        let settings = CinematicInfluenceSettings()
        let plans = CinematicDiagnostics.representativeActivityCases().map { activityCase in
            CinematicSetDressingPlanner.plan(
                languageProfile: languageProfile(primaryLanguage: .swift),
                activityProfile: activityCase.profile,
                influenceSettings: settings
            )
        }

        XCTAssertEqual(
            Set(plans.map(\.materialTextureVariants.runeMaterialIdentifier)),
            CinematicRuneMaterialTreatmentCatalog.expectedRuneMaterialIdentifiers
        )
        XCTAssertEqual(
            Set(plans.map(\.materialTextureVariants.runeMaterialTreatment.identifier)),
            CinematicRuneMaterialTreatmentCatalog.expectedTreatmentIdentifiers
        )

        for plan in plans {
            let variants = plan.materialTextureVariants
            XCTAssertEqual(variants.runeMaterialTreatment.runeMaterialIdentifier, variants.runeMaterialIdentifier)
            XCTAssertFalse(variants.backdropTextureName.hasSuffix(".png"))
            XCTAssertFalse(variants.arenaTextureName.hasSuffix(".png"))
            XCTAssertTrue(CinematicTextureAssetCatalog.recognizes(variants.backdropTextureName, role: .backdrop))
            XCTAssertTrue(CinematicTextureAssetCatalog.recognizes(variants.arenaTextureName, role: .arena))
            assertRuneTreatmentInBounds(variants.runeMaterialTreatment, file: #filePath, line: #line)
        }
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
        XCTAssertEqual(report.setDressing.pedestalLayoutIdentifier, plan.languageArchitecture.pedestalLayoutIdentifier)
        XCTAssertEqual(report.setDressing.shardFormationIdentifier, plan.languageArchitecture.shardFormationIdentifier)
        XCTAssertEqual(report.setDressing.pedestalSlotCount, plan.languageArchitecture.pedestalSlots.count)
        XCTAssertEqual(report.setDressing.shardSlotCount, plan.languageArchitecture.shardSlots.count)
        XCTAssertEqual(report.setDressing.layoutGeometryCoverageIdentifier, plan.languageArchitecture.layoutCoverageIdentifier)
        XCTAssertEqual(report.setDressing.layoutGeometryIsBounded, plan.languageArchitecture.geometryIsBounded)
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
        XCTAssertEqual(
            report.setDressing.runeMaterialIdentifier,
            plan.materialTextureVariants.runeMaterialIdentifier
        )
        XCTAssertEqual(
            report.setDressing.runeMaterialTreatmentIdentifier,
            plan.materialTextureVariants.runeMaterialTreatment.identifier
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
    XCTAssertEqual(plan.languageArchitecture.pedestalSlots.count, CinematicSetDressingPlan.pedestalCountRange.upperBound, file: file, line: line)
    XCTAssertEqual(plan.languageArchitecture.shardSlots.count, CinematicSetDressingPlan.shardCountRange.upperBound, file: file, line: line)
    XCTAssertTrue(plan.languageArchitecture.geometryIsBounded, file: file, line: line)
    for slot in plan.languageArchitecture.pedestalSlots {
        assertPedestalSlotInBounds(slot, file: file, line: line)
    }
    for slot in plan.languageArchitecture.shardSlots {
        assertShardSlotInBounds(slot, file: file, line: line)
    }
    assertRuneTreatmentInBounds(plan.materialTextureVariants.runeMaterialTreatment, file: file, line: line)
}

private func assertPedestalSlotInBounds(
    _ slot: CinematicSetDressingPlan.PedestalSlotGeometry,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertInRange(slot.position.x, CinematicSetDressingPlan.pedestalSlotXRange, file: file, line: line)
    XCTAssertInRange(slot.position.y, CinematicSetDressingPlan.pedestalSlotYRange, file: file, line: line)
    XCTAssertInRange(slot.position.z, CinematicSetDressingPlan.pedestalSlotZRange, file: file, line: line)
    XCTAssertTrue(slot.isInsideArenaBounds, file: file, line: line)
    XCTAssertFalse(slot.identifier.isEmpty, file: file, line: line)
    XCTAssertFalse(slot.layoutIdentifier.isEmpty, file: file, line: line)
}

private func assertShardSlotInBounds(
    _ slot: CinematicSetDressingPlan.FloatingShardSlotGeometry,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertInRange(slot.position.x, CinematicSetDressingPlan.shardSlotXRange, file: file, line: line)
    XCTAssertInRange(slot.position.y, CinematicSetDressingPlan.shardSlotYRange, file: file, line: line)
    XCTAssertInRange(slot.position.z, CinematicSetDressingPlan.shardSlotZRange, file: file, line: line)
    XCTAssertTrue(slot.isInsideArenaBounds, file: file, line: line)
    XCTAssertFalse(slot.identifier.isEmpty, file: file, line: line)
    XCTAssertFalse(slot.formationIdentifier.isEmpty, file: file, line: line)
}

private func assertRuneTreatmentInBounds(
    _ treatment: CinematicSetDressingPlan.RuneMaterialTreatment,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertInRange(treatment.floorEmissionOpacity, CinematicSetDressingPlan.runeFloorEmissionOpacityRange, file: file, line: line)
    XCTAssertInRange(treatment.plinthOpacity, CinematicSetDressingPlan.runePlinthOpacityRange, file: file, line: line)
    XCTAssertInRange(treatment.ringOpacityScale, CinematicSetDressingPlan.runeRingOpacityScaleRange, file: file, line: line)
    XCTAssertInRange(treatment.segmentRadiusScale, CinematicSetDressingPlan.runeSegmentRadiusScaleRange, file: file, line: line)
    XCTAssertInRange(treatment.segmentOpacityScale, CinematicSetDressingPlan.runeSegmentOpacityScaleRange, file: file, line: line)
    XCTAssertInRange(treatment.coreOpacity, CinematicSetDressingPlan.runeCoreOpacityRange, file: file, line: line)
    XCTAssertInRange(treatment.arenaAccentOpacityScale, CinematicSetDressingPlan.arenaAccentOpacityScaleRange, file: file, line: line)
    XCTAssertInRange(treatment.arenaAccentScale, CinematicSetDressingPlan.arenaAccentScaleRange, file: file, line: line)
    XCTAssertFalse(treatment.identifier.isEmpty, file: file, line: line)
    XCTAssertFalse(treatment.runeMaterialIdentifier.isEmpty, file: file, line: line)
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
