import Foundation
@testable import Compass
import XCTest

final class CinematicRunRecapShareArtifactCommandTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
    }

    func testCommandOrderingDescriptorsAndShortcutCollisionAvoidance() throws {
        let workspace = try makeInitializedWorkspace()
        for session in 1...4 {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-command-order-\(session).md",
                contents: artifactMarkdown(
                    session: session,
                    title: "Command Order \(session)",
                    status: "succeeded",
                    commit: "Command order commit \(session)",
                    body: "command order body \(session)"
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
        let commandPlan = CinematicRunRecapShareArtifactCommandPlanner.plan(actionMenuPlan: fixture.menu)

        XCTAssertEqual(commandPlan.commandCount, CinematicRunRecapShareArtifactCommandPlan.commandLimit)
        XCTAssertEqual(
            commandPlan.commands.map(\.sourceActionKind),
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
                .promoteTourHold
            ]
        )
        XCTAssertEqual(commandPlan.commands.prefix(3).map(\.section), Array(repeating: .navigate, count: 3))
        XCTAssertEqual(commandPlan.commands.dropFirst(3).prefix(7).map(\.section), Array(repeating: .exports, count: 7))
        XCTAssertEqual(commandPlan.commands.dropFirst(10).prefix(2).map(\.section), Array(repeating: .organize, count: 2))
        XCTAssertEqual(commandPlan.commands.dropFirst(12).prefix(3).map(\.section), Array(repeating: .tour, count: 3))
        XCTAssertEqual(Set(commandPlan.commands.map(\.identifier)).count, commandPlan.commandCount)
        XCTAssertTrue(commandPlan.identifier.hasPrefix("run-recap-share-artifact-commands"))
        XCTAssertEqual(
            commandPlan.commands.map(\.label),
            [
                "Previous Artifact",
                "Next Artifact",
                "Reveal in Finder",
                "Copy selected export",
                "Copy filtered export",
                "Copy Library Export",
                "Copy artifact rollup",
                "Copy comparison",
                "Copy pinned export",
                "Copy Tour Export",
                "Use Pinned Compare",
                "Pin Selected",
                "Release Tour Hold",
                "Hold Selected Artifact",
                "Promote Tour Hold"
            ]
        )

        let shortcuts = commandPlan.commands.map(\.shortcut)
        XCTAssertEqual(
            shortcuts.map(\.identifier),
            [
                "command:[",
                "command:]",
                "command+shift:r",
                "command+shift:e",
                "command+option:e",
                "command+option+shift:e",
                "command+shift:b",
                "command+shift:d",
                "command+option+shift:p",
                "command+option:t",
                "command+shift:m",
                "command+shift:p",
                "command+shift:h",
                "command+option+shift:h",
                "command+option:p"
            ]
        )
        XCTAssertEqual(Set(shortcuts).count, shortcuts.count)
        let appLevelShortcuts = Set([
            shortcut(key: .o, modifiers: [.command]),
            shortcut(key: .r, modifiers: [.command]),
            shortcut(key: .returnKey, modifiers: [.command])
        ])
        XCTAssertTrue(Set(shortcuts).isDisjoint(with: appLevelShortcuts))

        for command in commandPlan.commands {
            let sourceAction = try action(command.sourceActionKind, in: fixture.menu)

            XCTAssertFalse(command.identifier.isEmpty)
            XCTAssertFalse(command.label.isEmpty)
            XCTAssertFalse(command.help.isEmpty)
            XCTAssertEqual(command.label, sourceAction.label)
            XCTAssertEqual(command.help, sourceAction.help)
            XCTAssertEqual(command.isEnabled, sourceAction.isEnabled)
            XCTAssertEqual(sourceAction.shortcutHint, command.shortcut.displayText)
            XCTAssertLessThanOrEqual(
                command.identifier.count,
                CinematicRunRecapShareArtifactCommandPlan.identifierMaxCharacters
            )
            XCTAssertLessThanOrEqual(command.label.count, CinematicRunRecapShareArtifactCommandPlan.labelMaxCharacters)
            XCTAssertLessThanOrEqual(command.help.count, CinematicRunRecapShareArtifactCommandPlan.helpMaxCharacters)
            XCTAssertLessThanOrEqual(
                command.shortcut.displayText.count,
                CinematicRunRecapShareArtifactCommandPlan.shortcutHintMaxCharacters
            )
        }
    }

    func testDisabledNoMatchStatesMirrorActionMenu() throws {
        let workspace = try makeInitializedWorkspace()
        for session in 1...2 {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-command-no-match-\(session).md",
                contents: artifactMarkdown(
                    session: session,
                    title: "No Match Command \(session)",
                    status: "succeeded",
                    commit: "No match command commit \(session)",
                    body: "ordinary command archive body"
                )
            )
        }
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let context = CinematicRunRecapShareArtifactLibraryContext(
            searchText: "missing command beacon with extra words"
        )

        let fixture = makeFixture(history: history, context: context)
        let commandPlan = CinematicRunRecapShareArtifactCommandPlanner.plan(actionMenuPlan: fixture.menu)

        XCTAssertFalse(fixture.preview.isAvailable)
        XCTAssertEqual(fixture.preview.noMatchAvailabilityReason, "no-matching-recap-share-artifacts")
        XCTAssertFalse(try command(.navigatePrevious, in: commandPlan).isEnabled)
        XCTAssertFalse(try command(.navigateNext, in: commandPlan).isEnabled)
        XCTAssertFalse(try command(.revealSelected, in: commandPlan).isEnabled)
        XCTAssertFalse(try command(.copySelectedExport, in: commandPlan).isEnabled)
        XCTAssertFalse(try command(.copyFilteredExport, in: commandPlan).isEnabled)
        XCTAssertFalse(try command(.copyRollupExport, in: commandPlan).isEnabled)
        XCTAssertFalse(try command(.copyComparisonExport, in: commandPlan).isEnabled)
        XCTAssertTrue(try command(.copyLibraryExport, in: commandPlan).isEnabled)
        XCTAssertEqual(
            try command(.copyLibraryExport, in: commandPlan).isEnabled,
            try action(.copyLibraryExport, in: fixture.menu).isEnabled
        )
        XCTAssertTrue(try command(.copySelectedExport, in: commandPlan).help.contains("no-matching-recap-share-artifacts"))
        XCTAssertTrue(try command(.navigatePrevious, in: commandPlan).help.contains("newest matching"))
    }

    func testStalePinFilteredHoldAndPromotedHoldCommandStates() throws {
        let workspace = try makeInitializedWorkspace()
        let artifactCount = CinematicRunRecapShareArtifactHistoryPlan.retentionLimit + 2
        for session in 1...artifactCount {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-command-state-\(session).md",
                contents: artifactMarkdown(
                    session: session,
                    title: "Command State \(session)",
                    status: "succeeded",
                    commit: "Command state commit \(session)",
                    body: session == artifactCount ? "active command beacon" : "retained command body"
                )
            )
        }
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let selected = try XCTUnwrap(history.entries.first { $0.sessionNumber == artifactCount })
        let held = try XCTUnwrap(history.entries.first { $0.sessionNumber == artifactCount - 2 })
        let context = CinematicRunRecapShareArtifactLibraryContext(
            selectedEntryIdentifier: selected.identifier,
            searchText: "ACTIVE COMMAND",
            pinnedEntryIdentifiers: [held.identifier, selected.identifier, "stale-command-pin"],
            comparisonTargetMode: .pinnedReference,
            savedTourHoldEntryIdentifier: held.identifier
        )

        let fixture = makeFixture(history: history, context: context)
        let commandPlan = CinematicRunRecapShareArtifactCommandPlanner.plan(actionMenuPlan: fixture.menu)

        XCTAssertEqual(fixture.tour.savedTourHoldStateIdentifier, "filtered-hold")
        XCTAssertEqual(fixture.comparison.promotedHoldStateIdentifier, "filtered-promoted-hold-target")
        XCTAssertEqual(fixture.pins.missingPinnedEntryIdentifiers, ["stale-command-pin"])
        XCTAssertEqual(fixture.pins.filteredPinnedEntryIdentifiers, [held.identifier])
        XCTAssertEqual(try command(.toggleSelectedPin, in: commandPlan).label, "Unpin Selected")
        XCTAssertEqual(try command(.toggleTourHold, in: commandPlan).label, "Release Tour Hold")
        XCTAssertTrue(try command(.toggleTourHold, in: commandPlan).help.contains("hidden by search active command"))
        XCTAssertEqual(try command(.promoteTourHold, in: commandPlan).label, "Hold Promoted")
        XCTAssertTrue(try command(.promoteTourHold, in: commandPlan).help.contains("filtered"))
        XCTAssertTrue(try command(.promoteTourHold, in: commandPlan).isEnabled)
        XCTAssertTrue(try command(.copyPinnedExport, in: commandPlan).help.contains("1 stale"))
        XCTAssertNil(commandPlan.command(for: .cleanupOldArtifacts))
        XCTAssertTrue(try action(.cleanupOldArtifacts, in: fixture.menu).isEnabled)
    }

    func testCommandPlannerDoesNotMutateContextOrSiblingPlans() throws {
        let workspace = try makeInitializedWorkspace()
        for session in 1...3 {
            _ = try workspace.writeSessionArtifact(
                session: session,
                name: "recap-share-command-immutable-\(session).md",
                contents: artifactMarkdown(
                    session: session,
                    title: "Immutable Command \(session)",
                    status: session == 2 ? "failed verify" : "succeeded",
                    commit: "Immutable command commit \(session)",
                    body: session == 3 ? "immutable command beacon" : "ordinary immutable command body"
                )
            )
        }
        let history = workspace.refreshRunRecapShareArtifactHistory()
        let selected = try XCTUnwrap(history.entries.first { $0.sessionNumber == 3 })
        let held = try XCTUnwrap(history.entries.first { $0.sessionNumber == 2 })
        let context = CinematicRunRecapShareArtifactLibraryContext(
            selectedEntryIdentifier: selected.identifier,
            searchText: "IMMUTABLE COMMAND",
            pinnedEntryIdentifiers: [held.identifier, held.identifier, "missing-command-pin"],
            comparisonTargetMode: .pinnedReference,
            savedTourHoldEntryIdentifier: held.identifier
        )
        let contextBefore = context
        let fixture = makeFixture(history: history, context: context)

        _ = CinematicRunRecapShareArtifactCommandPlanner.plan(actionMenuPlan: fixture.menu)

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
        XCTAssertEqual(
            CinematicRunRecapShareArtifactActionMenuPlanner.plan(
                previewPlan: fixture.preview,
                rollupPlan: fixture.rollup,
                comparisonPlan: fixture.comparison,
                pinnedReferencePlan: fixture.pins,
                tourPlan: fixture.tour,
                selectedExportPlan: fixture.selectedExport,
                filteredExportPlan: fixture.filteredExport,
                historyPlan: history
            ),
            fixture.menu
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

    private func command(
        _ kind: CinematicRunRecapShareArtifactActionMenuPlan.ActionKind,
        in commandPlan: CinematicRunRecapShareArtifactCommandPlan
    ) throws -> CinematicRunRecapShareArtifactCommandPlan.Command {
        try XCTUnwrap(commandPlan.command(for: kind))
    }

    private func shortcut(
        key: CinematicRunRecapShareArtifactCommandPlan.Shortcut.Key,
        modifiers: [CinematicRunRecapShareArtifactCommandPlan.Shortcut.Modifier]
    ) -> CinematicRunRecapShareArtifactCommandPlan.Shortcut {
        CinematicRunRecapShareArtifactCommandPlan.Shortcut(key: key, modifiers: modifiers)
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
        - Filename: recap-share-command-\(session).md
        - Share: share-id
        - Recap: recap-id
        - Focus: focus-id
        - End card: end-card-id
        - Title: \(title)
        - Status: \(status)
        - Detail: Command detail
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
            .appending(path: "CinematicRunRecapShareArtifactCommandTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        temporaryDirectories.append(directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
