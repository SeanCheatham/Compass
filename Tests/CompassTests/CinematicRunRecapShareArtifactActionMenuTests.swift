import Foundation
@testable import Compass
import XCTest

final class CinematicRunRecapShareArtifactActionMenuTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
    }

    func testActionOrderingSectionsAndBoundedDescriptors() throws {
        let workspace = try makeInitializedWorkspace()
        for session in 1...4 {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-menu-order-\(session).md",
                contents: artifactMarkdown(
                    session: session,
                    title: "Menu Order \(session)",
                    status: "succeeded",
                    commit: "Menu order commit \(session)",
                    body: "menu order body \(session)"
                )
            )
        }
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let selected = try XCTUnwrap(history.entries.first { $0.sessionNumber == 3 })
        let pinned = try XCTUnwrap(history.entries.first { $0.sessionNumber == 1 })
        let held = try XCTUnwrap(history.entries.first { $0.sessionNumber == 2 })
        let context = CinematicRunRecapShareArtifactLibraryContext(
            selectedEntryIdentifier: selected.identifier,
            pinnedEntryIdentifiers: [pinned.identifier],
            savedTourHoldEntryIdentifier: held.identifier
        )

        let fixture = makeFixture(history: history, context: context)

        XCTAssertEqual(fixture.menu.actionCount, CinematicRunRecapShareArtifactActionMenuPlan.actionLimit)
        XCTAssertEqual(
            fixture.menu.actions.map(\.actionKind),
            [
                .navigatePrevious,
                .navigateNext,
                .revealSelected,
                .copySelectedExport,
                .copyFilteredExport,
                .copyLibraryExport,
                .copyRollupExport,
                .copyComparisonExport,
                .copyPinnedExport,
                .copyTourExport,
                .toggleComparisonTargetMode,
                .toggleSelectedPin,
                .toggleTourHold,
                .toggleSelectedTourHold,
                .promoteTourHold,
                .cleanupOldArtifacts
            ]
        )
        XCTAssertEqual(fixture.menu.actions.prefix(3).map(\.section), Array(repeating: .navigate, count: 3))
        XCTAssertEqual(fixture.menu.actions.dropFirst(3).prefix(7).map(\.section), Array(repeating: .exports, count: 7))
        XCTAssertEqual(fixture.menu.actions.dropFirst(10).prefix(2).map(\.section), Array(repeating: .organize, count: 2))
        XCTAssertEqual(fixture.menu.actions.dropFirst(12).prefix(3).map(\.section), Array(repeating: .tour, count: 3))
        XCTAssertEqual(fixture.menu.actions.last?.section, .maintain)
        XCTAssertEqual(Set(fixture.menu.actions.map(\.identifier)).count, fixture.menu.actionCount)
        XCTAssertTrue(fixture.menu.identifier.hasPrefix("run-recap-share-artifact-action-menu"))

        for action in fixture.menu.actions {
            XCTAssertFalse(action.identifier.isEmpty)
            XCTAssertFalse(action.label.isEmpty)
            XCTAssertFalse(action.systemImage.isEmpty)
            XCTAssertFalse(action.help.isEmpty)
            XCTAssertLessThanOrEqual(action.identifier.count, CinematicRunRecapShareArtifactActionMenuPlan.identifierMaxCharacters)
            XCTAssertLessThanOrEqual(action.label.count, CinematicRunRecapShareArtifactActionMenuPlan.labelMaxCharacters)
            XCTAssertLessThanOrEqual(action.help.count, CinematicRunRecapShareArtifactActionMenuPlan.helpMaxCharacters)
            XCTAssertLessThanOrEqual(action.systemImage.count, CinematicRunRecapShareArtifactActionMenuPlan.systemImageMaxCharacters)
            XCTAssertLessThanOrEqual(action.shortcutHint?.count ?? 0, CinematicRunRecapShareArtifactActionMenuPlan.shortcutHintMaxCharacters)
        }

        XCTAssertTrue(try action(.navigatePrevious, in: fixture.menu).isEnabled)
        XCTAssertTrue(try action(.navigateNext, in: fixture.menu).isEnabled)
        XCTAssertTrue(try action(.revealSelected, in: fixture.menu).isEnabled)
        XCTAssertEqual(fixture.tour.savedTourHoldStateIdentifier, "held")
        XCTAssertEqual(try action(.toggleComparisonTargetMode, in: fixture.menu).label, "Use Pinned Compare")
        XCTAssertEqual(try action(.toggleSelectedPin, in: fixture.menu).label, "Pin Selected")
        XCTAssertEqual(try action(.toggleTourHold, in: fixture.menu).label, "Release Tour Hold")
        XCTAssertFalse(try action(.cleanupOldArtifacts, in: fixture.menu).isEnabled)
    }

    func testSearchNoMatchDisablesNavigationRevealAndSearchScopedExports() throws {
        let workspace = try makeInitializedWorkspace()
        for session in 1...2 {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-menu-no-match-\(session).md",
                contents: artifactMarkdown(
                    session: session,
                    title: "No Match Menu \(session)",
                    status: "succeeded",
                    commit: "No match commit \(session)",
                    body: "ordinary archive body"
                )
            )
        }
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let context = CinematicRunRecapShareArtifactLibraryContext(
            searchText: "missing menu beacon with extra words"
        )

        let fixture = makeFixture(history: history, context: context)

        XCTAssertFalse(fixture.preview.isAvailable)
        XCTAssertEqual(fixture.preview.noMatchAvailabilityReason, "no-matching-recap-share-artifacts")
        XCTAssertFalse(try action(.navigatePrevious, in: fixture.menu).isEnabled)
        XCTAssertFalse(try action(.navigateNext, in: fixture.menu).isEnabled)
        XCTAssertFalse(try action(.revealSelected, in: fixture.menu).isEnabled)
        XCTAssertFalse(try action(.copySelectedExport, in: fixture.menu).isEnabled)
        XCTAssertFalse(try action(.copyFilteredExport, in: fixture.menu).isEnabled)
        XCTAssertFalse(try action(.copyRollupExport, in: fixture.menu).isEnabled)
        XCTAssertFalse(try action(.copyComparisonExport, in: fixture.menu).isEnabled)
        XCTAssertTrue(try action(.copyLibraryExport, in: fixture.menu).isEnabled)
        XCTAssertTrue(try action(.copySelectedExport, in: fixture.menu).help.contains("no-matching-recap-share-artifacts"))
        XCTAssertTrue(try action(.navigatePrevious, in: fixture.menu).help.contains("newest matching"))

        for action in fixture.menu.actions {
            XCTAssertLessThanOrEqual(action.label.count, CinematicRunRecapShareArtifactActionMenuPlan.labelMaxCharacters)
            XCTAssertLessThanOrEqual(action.help.count, CinematicRunRecapShareArtifactActionMenuPlan.helpMaxCharacters)
        }
    }

    func testStalePinsFilteredTourHoldCleanupCandidatesAndPromotedHoldStates() throws {
        let workspace = try makeInitializedWorkspace()
        let artifactCount = CinematicRunRecapShareArtifactHistoryPlan.retentionLimit + 2
        for session in 1...artifactCount {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-menu-state-\(session).md",
                contents: artifactMarkdown(
                    session: session,
                    title: "Menu State \(session)",
                    status: "succeeded",
                    commit: "Menu state commit \(session)",
                    body: session == artifactCount ? "active menu beacon" : "retained archive body"
                )
            )
        }
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let selected = try XCTUnwrap(history.entries.first { $0.sessionNumber == artifactCount })
        let held = try XCTUnwrap(history.entries.first { $0.sessionNumber == artifactCount - 2 })
        let context = CinematicRunRecapShareArtifactLibraryContext(
            selectedEntryIdentifier: selected.identifier,
            searchText: "ACTIVE MENU",
            pinnedEntryIdentifiers: [held.identifier, selected.identifier, "stale-menu-pin"],
            comparisonTargetMode: .pinnedReference,
            savedTourHoldEntryIdentifier: held.identifier
        )

        let fixture = makeFixture(history: history, context: context)

        XCTAssertEqual(history.cleanupCandidateCount, 2)
        XCTAssertEqual(fixture.tour.savedTourHoldStateIdentifier, "filtered-hold")
        XCTAssertEqual(fixture.comparison.promotedHoldStateIdentifier, "filtered-promoted-hold-target")
        XCTAssertEqual(fixture.pins.missingPinnedEntryIdentifiers, ["stale-menu-pin"])
        XCTAssertEqual(fixture.pins.filteredPinnedEntryIdentifiers, [held.identifier])
        XCTAssertEqual(try action(.toggleSelectedPin, in: fixture.menu).label, "Unpin Selected")
        XCTAssertEqual(try action(.toggleTourHold, in: fixture.menu).label, "Release Tour Hold")
        XCTAssertTrue(try action(.toggleTourHold, in: fixture.menu).help.contains("hidden by search active menu"))
        XCTAssertEqual(try action(.promoteTourHold, in: fixture.menu).label, "Hold Promoted")
        XCTAssertTrue(try action(.promoteTourHold, in: fixture.menu).help.contains("filtered"))
        XCTAssertTrue(try action(.promoteTourHold, in: fixture.menu).isEnabled)
        XCTAssertTrue(try action(.cleanupOldArtifacts, in: fixture.menu).isEnabled)
        XCTAssertTrue(try action(.cleanupOldArtifacts, in: fixture.menu).help.contains("Delete 2 old recap share artifacts"))
        XCTAssertTrue(try action(.copyPinnedExport, in: fixture.menu).help.contains("1 stale"))
    }

    func testPlannerDoesNotMutateContextOrSiblingPlans() throws {
        let workspace = try makeInitializedWorkspace()
        for session in 1...3 {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-menu-immutable-\(session).md",
                contents: artifactMarkdown(
                    session: session,
                    title: "Immutable Menu \(session)",
                    status: session == 2 ? "failed verify" : "succeeded",
                    commit: "Immutable menu commit \(session)",
                    body: session == 3 ? "immutable search beacon" : "ordinary immutable body"
                )
            )
        }
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let selected = try XCTUnwrap(history.entries.first { $0.sessionNumber == 3 })
        let held = try XCTUnwrap(history.entries.first { $0.sessionNumber == 2 })
        let context = CinematicRunRecapShareArtifactLibraryContext(
            selectedEntryIdentifier: selected.identifier,
            searchText: "IMMUTABLE SEARCH",
            pinnedEntryIdentifiers: [held.identifier, held.identifier, "missing-immutable-pin"],
            comparisonTargetMode: .pinnedReference,
            savedTourHoldEntryIdentifier: held.identifier
        )
        let contextBefore = context
        let fixture = makeFixture(history: history, context: context)

        _ = CinematicRunRecapShareArtifactActionMenuPlanner.plan(
            previewPlan: fixture.preview,
            rollupPlan: fixture.rollup,
            comparisonPlan: fixture.comparison,
            pinnedReferencePlan: fixture.pins,
            tourPlan: fixture.tour,
            selectedExportPlan: fixture.selectedExport,
            filteredExportPlan: fixture.filteredExport,
            historyPlan: history
        )

        XCTAssertEqual(context, contextBefore)
        XCTAssertEqual(
            CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
                historyPlan: history,
                selectedEntryIdentifier: context.selectedEntryIdentifier,
                searchQuery: context.searchText
            ),
            fixture.preview
        )
        XCTAssertEqual(
            CinematicRunRecapShareArtifactRollupPlanner.plan(
                historyPlan: history,
                selectedEntryIdentifier: context.selectedEntryIdentifier,
                searchQuery: context.searchText
            ),
            fixture.rollup
        )
        XCTAssertEqual(
            CinematicRunRecapShareArtifactComparisonPlanner.plan(
                historyPlan: history,
                selectedEntryIdentifier: context.selectedEntryIdentifier,
                searchQuery: context.searchText,
                targetMode: context.comparisonTargetMode,
                pinnedEntryIdentifiers: context.pinnedEntryIdentifiers,
                savedTourHoldEntryIdentifier: context.savedTourHoldEntryIdentifier
            ),
            fixture.comparison
        )
        XCTAssertEqual(
            CinematicRunRecapShareArtifactPinnedReferencePlanner.plan(
                historyPlan: history,
                pinnedEntryIdentifiers: context.pinnedEntryIdentifiers,
                selectedEntryIdentifier: context.selectedEntryIdentifier,
                searchQuery: context.searchText
            ),
            fixture.pins
        )
        XCTAssertEqual(
            CinematicRunRecapShareArtifactTourPlanner.plan(
                historyPlan: history,
                libraryContext: context
            ),
            fixture.tour
        )
    }

    private struct Fixture {
        var preview: CinematicRunRecapShareArtifactPreviewBrowserPlan
        var rollup: CinematicRunRecapShareArtifactRollupPlan
        var comparison: CinematicRunRecapShareArtifactComparisonPlan
        var pins: CinematicRunRecapShareArtifactPinnedReferencePlan
        var tour: CinematicRunRecapShareArtifactTourPlan
        var selectedExport: CinematicRunRecapShareArtifactSubsetExportPlan
        var filteredExport: CinematicRunRecapShareArtifactSubsetExportPlan
        var menu: CinematicRunRecapShareArtifactActionMenuPlan
    }

    private func makeFixture(
        history: CinematicRunRecapShareArtifactHistoryPlan,
        context: CinematicRunRecapShareArtifactLibraryContext
    ) -> Fixture {
        let preview = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: context.selectedEntryIdentifier,
            searchQuery: context.searchText
        )
        let rollup = CinematicRunRecapShareArtifactRollupPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: context.selectedEntryIdentifier,
            searchQuery: context.searchText
        )
        let comparison = CinematicRunRecapShareArtifactComparisonPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: context.selectedEntryIdentifier,
            searchQuery: context.searchText,
            targetMode: context.comparisonTargetMode,
            pinnedEntryIdentifiers: context.pinnedEntryIdentifiers,
            savedTourHoldEntryIdentifier: context.savedTourHoldEntryIdentifier
        )
        let pins = CinematicRunRecapShareArtifactPinnedReferencePlanner.plan(
            historyPlan: history,
            pinnedEntryIdentifiers: context.pinnedEntryIdentifiers,
            selectedEntryIdentifier: context.selectedEntryIdentifier,
            searchQuery: context.searchText
        )
        let tour = CinematicRunRecapShareArtifactTourPlanner.plan(
            historyPlan: history,
            libraryContext: context
        )
        let selectedExport = CinematicRunRecapShareArtifactSubsetExportPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: context.selectedEntryIdentifier,
            searchQuery: context.searchText,
            scope: .selected
        )
        let filteredExport = CinematicRunRecapShareArtifactSubsetExportPlanner.plan(
            historyPlan: history,
            selectedEntryIdentifier: context.selectedEntryIdentifier,
            searchQuery: context.searchText,
            scope: .filtered
        )
        let menu = CinematicRunRecapShareArtifactActionMenuPlanner.plan(
            previewPlan: preview,
            rollupPlan: rollup,
            comparisonPlan: comparison,
            pinnedReferencePlan: pins,
            tourPlan: tour,
            selectedExportPlan: selectedExport,
            filteredExportPlan: filteredExport,
            historyPlan: history
        )

        return Fixture(
            preview: preview,
            rollup: rollup,
            comparison: comparison,
            pins: pins,
            tour: tour,
            selectedExport: selectedExport,
            filteredExport: filteredExport,
            menu: menu
        )
    }

    private func action(
        _ kind: CinematicRunRecapShareArtifactActionMenuPlan.ActionKind,
        in menu: CinematicRunRecapShareArtifactActionMenuPlan
    ) throws -> CinematicRunRecapShareArtifactActionMenuPlan.Action {
        try XCTUnwrap(menu.actions.first { $0.actionKind == kind })
    }

    private func artifactMarkdown(
        session: Int,
        title: String,
        status: String,
        commit: String,
        body: String
    ) -> String {
        """
        # Compass Run Recap Share

        - Artifact: artifact-\(session)
        - Availability: available
        - Session: \(session)
        - Filename: recap-share-menu-\(session).md
        - Share: share-id
        - Recap: recap-id
        - Focus: focus-id
        - End card: end-card-id
        - Title: \(title)
        - Status: \(status)
        - Detail: Action menu detail
        - Commit: \(commit)

        ## Events
        - event

        ## Share Text

        ```text
        \(body)
        ```
        """
    }

    private func makeInitializedWorkspace() throws -> CompassWorkspace {
        let repoURL = try makeTemporaryGitRepository()
        let workspace = CompassWorkspace(repoURL: repoURL)
        try workspace.initialize()
        return workspace
    }

    private func makeTemporaryGitRepository() throws -> URL {
        let directory = try makeTemporaryDirectory()
        try FileManager.default.createDirectory(
            at: directory.appending(path: ".git", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        return directory
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "CinematicRunRecapShareArtifactActionMenuTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        temporaryDirectories.append(directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
