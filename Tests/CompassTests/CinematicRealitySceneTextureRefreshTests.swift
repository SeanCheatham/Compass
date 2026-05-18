import Foundation
@testable import Compass
import XCTest

final class CinematicRealitySceneTextureRefreshTests: XCTestCase {
    func testBackdropRefreshesWhenLanguageTextureRouteChanges() {
        let cleanActivity = activityProfile()
        let appliedPlan = setDressingPlan(language: .swift, activityProfile: cleanActivity)
        let nextPlan = setDressingPlan(language: .python, activityProfile: cleanActivity)
        let appliedState = CinematicSetDressingTextureRouteState(
            materialTextureVariants: appliedPlan.materialTextureVariants
        )

        let refresh = CinematicSetDressingTextureRefreshPlanner.plan(
            appliedState: appliedState,
            setDressingPlan: nextPlan
        )

        XCTAssertTrue(refresh.refreshesBackdrop)
        XCTAssertFalse(refresh.refreshesArena)
        XCTAssertTrue(refresh.hasRefreshes)
        XCTAssertEqual(refresh.previousState, appliedState)
        XCTAssertEqual(refresh.nextState.backdropTextureName, "python-coil-backdrop")
        XCTAssertEqual(refresh.nextState.arenaTextureName, appliedState.arenaTextureName)
        assertRouteStateIsBoundedRecognizedAndExtensionless(refresh.nextState)
    }

    func testArenaRefreshesWhenActivityTextureRouteChanges() {
        let appliedPlan = setDressingPlan(language: .swift, activityProfile: activityProfile())
        var changes = RepositoryWorktreeChangeCounts()
        changes.modified = 3
        let nextPlan = setDressingPlan(language: .swift, activityProfile: activityProfile(worktreeChanges: changes))
        let appliedState = CinematicSetDressingTextureRouteState(
            materialTextureVariants: appliedPlan.materialTextureVariants
        )

        let refresh = CinematicSetDressingTextureRefreshPlanner.plan(
            appliedState: appliedState,
            setDressingPlan: nextPlan
        )

        XCTAssertFalse(refresh.refreshesBackdrop)
        XCTAssertTrue(refresh.refreshesArena)
        XCTAssertTrue(refresh.hasRefreshes)
        XCTAssertEqual(refresh.nextState.backdropTextureName, appliedState.backdropTextureName)
        XCTAssertEqual(refresh.nextState.arenaTextureName, "dirty-arena")
        assertRouteStateIsBoundedRecognizedAndExtensionless(refresh.nextState)
    }

    func testNoRefreshOccursWhenTextureRoutesStayStable() {
        var changes = RepositoryWorktreeChangeCounts()
        changes.modified = 2
        let activity = activityProfile(worktreeChanges: changes)
        let appliedPlan = setDressingPlan(
            language: .swift,
            activityProfile: activity,
            influenceSettings: CinematicInfluenceSettings(cameraStyle: .steady, intensity: 0)
        )
        let nextPlan = setDressingPlan(
            language: .swift,
            activityProfile: activity,
            influenceSettings: CinematicInfluenceSettings(cameraStyle: .dramatic, intensity: 1)
        )
        let appliedState = CinematicSetDressingTextureRouteState(
            materialTextureVariants: appliedPlan.materialTextureVariants
        )

        let refresh = CinematicSetDressingTextureRefreshPlanner.plan(
            appliedState: appliedState,
            setDressingPlan: nextPlan
        )

        XCTAssertFalse(refresh.refreshesBackdrop)
        XCTAssertFalse(refresh.refreshesArena)
        XCTAssertFalse(refresh.hasRefreshes)
        XCTAssertEqual(refresh.nextState.backdropRouteIdentifier, appliedState.backdropRouteIdentifier)
        XCTAssertEqual(refresh.nextState.backdropTextureName, appliedState.backdropTextureName)
        XCTAssertEqual(refresh.nextState.arenaRouteIdentifier, appliedState.arenaRouteIdentifier)
        XCTAssertEqual(refresh.nextState.arenaTextureName, appliedState.arenaTextureName)
        assertRouteStateIsBoundedRecognizedAndExtensionless(refresh.nextState)
    }

    func testMissingAppliedStateRefreshesBothTextureRoutes() {
        let plan = setDressingPlan(language: .rust, activityProfile: activityProfile(recentCommitCount: 1))

        let refresh = CinematicSetDressingTextureRefreshPlanner.plan(
            appliedState: nil,
            setDressingPlan: plan
        )

        XCTAssertNil(refresh.previousState)
        XCTAssertTrue(refresh.refreshesBackdrop)
        XCTAssertTrue(refresh.refreshesArena)
        XCTAssertEqual(refresh.nextState.backdropTextureName, "rust-gear-backdrop")
        XCTAssertEqual(refresh.nextState.arenaTextureName, "commit-arena")
        assertRouteStateIsBoundedRecognizedAndExtensionless(refresh.nextState)
    }

    func testFallbackRouteStateNamesStayExtensionlessAndRecognized() {
        let fallbackState = CinematicSetDressingTextureRouteState(
            backdropRouteIdentifier: "fallback.backdrop",
            backdropTextureName: "void-arches",
            arenaRouteIdentifier: "fallback.arena",
            arenaTextureName: "arena-runes"
        )

        assertRouteStateIsBoundedRecognizedAndExtensionless(fallbackState)

        for fallbackName in CinematicTextureAssetCatalog.backdropFallbackNames {
            XCTAssertFalse(fallbackName.contains("/"))
            XCTAssertFalse(fallbackName.hasSuffix(".png"))
            XCTAssertTrue(CinematicTextureAssetCatalog.recognizes(fallbackName, role: .backdrop))
        }

        for fallbackName in CinematicTextureAssetCatalog.arenaFallbackNames {
            XCTAssertFalse(fallbackName.contains("/"))
            XCTAssertFalse(fallbackName.hasSuffix(".png"))
            XCTAssertTrue(CinematicTextureAssetCatalog.recognizes(fallbackName, role: .arena))
        }
    }
}

private func setDressingPlan(
    language: RepositoryLanguage,
    activityProfile: RepositoryActivityProfile,
    influenceSettings: CinematicInfluenceSettings = CinematicInfluenceSettings()
) -> CinematicSetDressingPlan {
    CinematicSetDressingPlanner.plan(
        languageProfile: languageProfile(primaryLanguage: language),
        activityProfile: activityProfile,
        influenceSettings: influenceSettings
    )
}

private func assertRouteStateIsBoundedRecognizedAndExtensionless(
    _ state: CinematicSetDressingTextureRouteState,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertLessThanOrEqual(
        state.identifier.count,
        CinematicSetDressingTextureRouteState.identifierMaxCharacters,
        file: file,
        line: line
    )
    XCTAssertTrue(state.textureNamesAreRecognized, file: file, line: line)
    XCTAssertTrue(state.usesExtensionlessTextureNames, file: file, line: line)
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
        lastSuccessfulSession: lastTerminalStatus == .succeeded ? 1 : nil,
        lastFailedSession: lastTerminalStatus == .failed ? 1 : nil,
        successStreak: successStreak,
        failureStreak: failureStreak,
        recoveredFromFailure: recoveredFromFailure
    )
}
