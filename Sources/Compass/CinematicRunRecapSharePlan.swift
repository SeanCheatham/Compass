import Foundation

struct CinematicRunRecapSharePlan: Equatable, Identifiable {
    static let identifierMaxCharacters = 320
    static let textMaxCharacters = 1_200
    static let eventSummaryLimit = CinematicRunRecapPlan.eventChipLimit
    static let eventSummaryMaxCharacters = 112
    static let visualDescriptorTokenLimit = 20
    static let visualDescriptorTokenMaxCharacters = 72
    static let visualDescriptorLineMaxCharacters = 360

    var id: String { identifier }

    var identifier: String
    var availabilityIdentifier: String
    var availabilityReason: String
    var isAvailable: Bool
    var recapIdentifier: String
    var recapFocusIdentifier: String?
    var endCardIdentifier: String?
    var title: String
    var detail: String
    var status: String
    var commitHighlight: String?
    var eventSummaries: [String]
    var visualDescriptorTokens: [String]
    var text: String

    var eventSummaryCount: Int { eventSummaries.count }
    var visualDescriptorTokenCount: Int { visualDescriptorTokens.count }
    var textLength: Int { text.count }
}

struct CinematicRunRecapShareArtifactPlan: Equatable, Identifiable {
    static let identifierMaxCharacters = 320
    static let filenameMaxCharacters = 96
    static let markdownMaxCharacters = 3_600
    static let feedbackMaxCharacters = 180

    var id: String { identifier }

    var identifier: String
    var isAvailable: Bool
    var availabilityReason: String
    var sessionNumber: Int?
    var filename: String
    var shareIdentifier: String
    var recapIdentifier: String
    var recapFocusIdentifier: String?
    var endCardIdentifier: String?
    var title: String
    var status: String
    var detail: String
    var commitHighlight: String?
    var eventSummaries: [String]
    var visualDescriptorTokens: [String]
    var markdownContents: String
    var feedback: String

    var eventSummaryCount: Int { eventSummaries.count }
    var visualDescriptorTokenCount: Int { visualDescriptorTokens.count }
    var markdownLength: Int { markdownContents.count }
}

struct CinematicRunRecapShareArtifactHistoryPlan: Equatable, Identifiable {
    static let identifierMaxCharacters = 320
    static let entryLimit = 8
    static let retentionLimit = entryLimit
    static let warningLimit = 4
    static let cleanupCandidateIdentifierLimit = 8
    static let filenameMaxCharacters = CinematicRunRecapShareArtifactPlan.filenameMaxCharacters
    static let pathDisplayMaxCharacters = 180
    static let snippetMaxCharacters = 96
    static let warningMaxCharacters = 160
    static let entryMarkdownMaxCharacters = 2_400
    static let combinedMarkdownMaxCharacters = 12_000

    var id: String { identifier }

    var identifier: String
    var isAvailable: Bool
    var availabilityReason: String
    var storageRootDisplayText: String
    var sessionsDisplayText: String
    var retentionLimit: Int
    var entries: [Entry]
    var totalCount: Int
    var hiddenCount: Int
    var cleanupCandidateCount: Int
    var hiddenCleanupCandidateCount: Int
    var cleanupCandidateIdentifiers: [String]
    var warnings: [Warning]
    var warningCount: Int
    var hiddenWarningCount: Int
    var exportIdentifier: String
    var combinedMarkdownExport: String

    var latestEntry: Entry? { entries.first }
    var combinedMarkdownLength: Int { combinedMarkdownExport.count }
    var hasWarnings: Bool { warningCount > 0 }

    static func unavailable(
        reason: String,
        storageRootURL: URL? = nil,
        sessionsURL: URL? = nil,
        warnings: [Warning] = []
    ) -> CinematicRunRecapShareArtifactHistoryPlan {
        CinematicRunRecapShareArtifactHistoryPlanner.unavailable(
            reason: reason,
            storageRootURL: storageRootURL,
            sessionsURL: sessionsURL,
            warnings: warnings
        )
    }

    struct Entry: Equatable, Identifiable {
        var id: String { identifier }

        var identifier: String
        var sessionNumber: Int
        var filename: String
        var url: URL
        var pathDisplayText: String
        var titleSnippet: String
        var statusSnippet: String
        var commitSnippet: String?
        var markdownContents: String
        var markdownLength: Int
    }

    struct Warning: Equatable, Identifiable {
        var id: String { identifier }

        var identifier: String
        var fileDisplayText: String
        var message: String
    }

    struct CleanupCandidate: Equatable, Identifiable {
        var id: String { identifier }

        var identifier: String
        var sessionNumber: Int
        var filename: String
        var url: URL
        var pathDisplayText: String
    }
}

struct CinematicRunRecapShareArtifactPreviewBrowserPlan: Equatable, Identifiable {
    static let identifierMaxCharacters = CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
    static let snippetMaxCharacters = CinematicRunRecapShareArtifactHistoryPlan.snippetMaxCharacters
    static let searchQuerySnippetMaxCharacters = 80
    static let pathSnippetMaxCharacters = CinematicRunRecapShareArtifactHistoryPlan.pathDisplayMaxCharacters
    static let bodyPreviewMaxCharacters = 220

    var id: String { identifier }

    var identifier: String
    var isAvailable: Bool
    var availabilityReason: String
    var isSearchActive: Bool
    var searchQuerySnippet: String
    var searchQueryFingerprint: String
    var matchCount: Int
    var unfilteredVisibleCount: Int
    var noMatchAvailabilityReason: String?
    var selectedEntryIdentifier: String?
    var selectedFallbackEntryIdentifier: String?
    var selectedFallbackReasonIdentifier: String
    var previousEntryIdentifier: String?
    var nextEntryIdentifier: String?
    var selectedIndex: Int?
    var selectedOrdinal: Int?
    var entryCount: Int
    var sessionNumber: Int?
    var filename: String?
    var titleSnippet: String
    var statusSnippet: String
    var commitSnippet: String?
    var pathSnippet: String
    var bodyPreviewText: String
    var markdownLength: Int
    var warningStateIdentifier: String
    var warningCount: Int
    var hasWarnings: Bool

    var canNavigatePrevious: Bool { previousEntryIdentifier != nil }
    var canNavigateNext: Bool { nextEntryIdentifier != nil }
}

struct CinematicRunRecapShareArtifactSubsetExportPlan: Equatable, Identifiable {
    static let identifierMaxCharacters = CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
    static let markdownMaxCharacters = CinematicRunRecapShareArtifactHistoryPlan.combinedMarkdownMaxCharacters
    static let snippetMaxCharacters = CinematicRunRecapShareArtifactHistoryPlan.snippetMaxCharacters
    static let searchQuerySnippetMaxCharacters = CinematicRunRecapShareArtifactPreviewBrowserPlan.searchQuerySnippetMaxCharacters
    static let labelMaxCharacters = 34
    static let helpMaxCharacters = 260

    var id: String { identifier }

    var identifier: String
    var exportIdentifier: String
    var scope: Scope
    var isAvailable: Bool
    var availabilityReason: String
    var isSearchActive: Bool
    var searchQuerySnippet: String
    var searchQueryFingerprint: String
    var noMatchAvailabilityReason: String?
    var retainedEntryCount: Int
    var totalCount: Int
    var hiddenCount: Int
    var selectedCount: Int
    var filteredCount: Int
    var exportEntryCount: Int
    var unfilteredVisibleCount: Int
    var selectedEntryIdentifier: String?
    var selectedFallbackEntryIdentifier: String?
    var selectedFallbackReasonIdentifier: String
    var exportedEntryIdentifiers: [String]
    var warningStateIdentifier: String
    var warningCount: Int
    var hiddenWarningCount: Int
    var warningIdentifiers: [String]
    var hasWarnings: Bool
    var markdownContents: String
    var copyLabel: String
    var copyHelp: String

    var markdownLength: Int { markdownContents.count }
    var scopeIdentifier: String { scope.rawValue }

    enum Scope: String, Equatable {
        case selected
        case filtered
    }
}

struct CinematicRunRecapShareArtifactRollupPlan: Equatable, Identifiable {
    static let identifierMaxCharacters = CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
    static let snippetMaxCharacters = CinematicRunRecapShareArtifactHistoryPlan.snippetMaxCharacters
    static let searchQuerySnippetMaxCharacters = CinematicRunRecapShareArtifactPreviewBrowserPlan.searchQuerySnippetMaxCharacters
    static let statusBucketSummaryMaxCharacters = 160
    static let insightTextMaxCharacters = 220
    static let exportTextMaxCharacters = 2_800
    static let copyLabelMaxCharacters = 32
    static let copyHelpMaxCharacters = 240

    var id: String { identifier }

    var identifier: String
    var exportIdentifier: String
    var isAvailable: Bool
    var availabilityReason: String
    var isSearchActive: Bool
    var searchQuerySnippet: String
    var searchQueryFingerprint: String
    var noMatchAvailabilityReason: String?
    var retainedEntryCount: Int
    var totalCount: Int
    var hiddenCount: Int
    var matchingEntryCount: Int
    var unfilteredVisibleCount: Int
    var selectedEntryIdentifier: String?
    var selectedFallbackEntryIdentifier: String?
    var selectedFallbackReasonIdentifier: String
    var sessionRangeLabel: String
    var newestEntryIdentifier: String?
    var newestSessionNumber: Int?
    var newestFilename: String?
    var oldestEntryIdentifier: String?
    var oldestSessionNumber: Int?
    var oldestFilename: String?
    var statusBuckets: [StatusBucket]
    var statusBucketSummary: String
    var cleanupCandidateCount: Int
    var hiddenCleanupCandidateCount: Int
    var cleanupCandidateIdentifiers: [String]
    var warningStateIdentifier: String
    var warningCount: Int
    var hiddenWarningCount: Int
    var warningIdentifiers: [String]
    var hasWarnings: Bool
    var insightText: String
    var exportText: String
    var copyLabel: String
    var copyHelp: String

    var exportTextLength: Int { exportText.count }

    struct StatusBucket: Equatable, Identifiable {
        var id: String { identifier }

        var identifier: String
        var label: String
        var count: Int
    }
}

struct CinematicRunRecapShareArtifactComparisonPlan: Equatable, Identifiable {
    static let identifierMaxCharacters = CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
    static let snippetMaxCharacters = CinematicRunRecapShareArtifactHistoryPlan.snippetMaxCharacters
    static let searchQuerySnippetMaxCharacters = CinematicRunRecapShareArtifactPreviewBrowserPlan.searchQuerySnippetMaxCharacters
    static let bodyPreviewMaxCharacters = 180
    static let exportTextMaxCharacters = 2_800
    static let copyLabelMaxCharacters = 34
    static let copyHelpMaxCharacters = 260

    var id: String { identifier }

    var identifier: String
    var exportIdentifier: String
    var isAvailable: Bool
    var availabilityReason: String
    var isSearchActive: Bool
    var searchQuerySnippet: String
    var searchQueryFingerprint: String
    var noMatchAvailabilityReason: String?
    var retainedEntryCount: Int
    var totalCount: Int
    var hiddenCount: Int
    var matchingEntryCount: Int
    var unfilteredVisibleCount: Int
    var selectedEntryIdentifier: String?
    var selectedFallbackEntryIdentifier: String?
    var selectedFallbackReasonIdentifier: String
    var compareEntryIdentifier: String?
    var targetMode: CinematicRunRecapShareArtifactComparisonTargetMode
    var targetModeIdentifier: String
    var targetDirectionIdentifier: String
    var pinnedTargetEntryIdentifier: String?
    var pinnedTargetStateIdentifier: String
    var pinnedTargetUnavailableReasonIdentifier: String?
    var promotedHoldStateIdentifier: String
    var requestedSavedTourHoldEntryIdentifier: String?
    var retainedSavedTourHoldEntryIdentifier: String?
    var filteredSavedTourHoldEntryIdentifier: String?
    var requestedPinnedEntryIdentifiers: [String]
    var retainedPinnedEntryIdentifiers: [String]
    var missingPinnedEntryIdentifiers: [String]
    var filteredPinnedEntryIdentifiers: [String]
    var pinnedEntryCount: Int
    var retainedPinnedEntryCount: Int
    var missingPinnedEntryCount: Int
    var filteredPinnedEntryCount: Int
    var sessionDelta: Int?
    var selectedSessionNumber: Int?
    var compareSessionNumber: Int?
    var selectedFilename: String?
    var compareFilename: String?
    var selectedTitleSnippet: String?
    var compareTitleSnippet: String?
    var selectedStatusSnippet: String?
    var compareStatusSnippet: String?
    var selectedCommitSnippet: String?
    var compareCommitSnippet: String?
    var selectedBodyPreviewText: String?
    var compareBodyPreviewText: String?
    var cleanupCandidateCount: Int
    var hiddenCleanupCandidateCount: Int
    var cleanupCandidateIdentifiers: [String]
    var warningStateIdentifier: String
    var warningCount: Int
    var hiddenWarningCount: Int
    var warningIdentifiers: [String]
    var hasWarnings: Bool
    var exportText: String
    var copyLabel: String
    var copyHelp: String

    var exportTextLength: Int { exportText.count }
}

struct CinematicRunRecapShareArtifactPinnedReferencePlan: Equatable, Identifiable {
    static let identifierMaxCharacters = CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
    static let pinIdentifierLimit = CinematicRunRecapShareArtifactHistoryPlan.retentionLimit
    static let snippetMaxCharacters = CinematicRunRecapShareArtifactHistoryPlan.snippetMaxCharacters
    static let searchQuerySnippetMaxCharacters = CinematicRunRecapShareArtifactPreviewBrowserPlan.searchQuerySnippetMaxCharacters
    static let exportTextMaxCharacters = 2_400
    static let copyLabelMaxCharacters = 34
    static let copyHelpMaxCharacters = 260

    var id: String { identifier }

    var identifier: String
    var exportIdentifier: String
    var isAvailable: Bool
    var availabilityReason: String
    var isSearchActive: Bool
    var searchQuerySnippet: String
    var searchQueryFingerprint: String
    var noMatchAvailabilityReason: String?
    var retainedEntryCount: Int
    var totalCount: Int
    var hiddenCount: Int
    var matchingEntryCount: Int
    var unfilteredVisibleCount: Int
    var selectedEntryIdentifier: String?
    var selectedEntryIsPinned: Bool
    var selectedPinStateIdentifier: String
    var requestedPinnedEntryIdentifiers: [String]
    var retainedPinnedEntryIdentifiers: [String]
    var missingPinnedEntryIdentifiers: [String]
    var filteredPinnedEntryIdentifiers: [String]
    var quickSelectEntryIdentifiers: [String]
    var pinnedEntryCount: Int
    var retainedPinnedEntryCount: Int
    var missingPinnedEntryCount: Int
    var filteredPinnedEntryCount: Int
    var quickSelectEntryCount: Int
    var references: [Reference]
    var warningStateIdentifier: String
    var warningCount: Int
    var hiddenWarningCount: Int
    var warningIdentifiers: [String]
    var hasWarnings: Bool
    var exportText: String
    var copyLabel: String
    var copyHelp: String

    var exportTextLength: Int { exportText.count }

    struct Reference: Equatable, Identifiable {
        var id: String { identifier }

        var identifier: String
        var sessionNumber: Int
        var filename: String
        var titleSnippet: String
        var statusSnippet: String
        var commitSnippet: String?
        var isQuickSelectable: Bool
    }
}

struct CinematicRunRecapShareArtifactTourPlan: Equatable, Identifiable {
    static let identifierMaxCharacters = CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
    static let snippetMaxCharacters = CinematicRunRecapShareArtifactHistoryPlan.snippetMaxCharacters
    static let searchQuerySnippetMaxCharacters = CinematicRunRecapShareArtifactPreviewBrowserPlan.searchQuerySnippetMaxCharacters
    static let bodyPreviewMaxCharacters = 180
    static let pinIdentifierLimit = CinematicRunRecapShareArtifactPinnedReferencePlan.pinIdentifierLimit

    var id: String { identifier }

    var identifier: String
    var isAvailable: Bool
    var availabilityReason: String
    var stateIdentifier: String
    var selectionSourceIdentifier: String
    var savedTourHoldStateIdentifier: String
    var requestedSavedTourHoldEntryIdentifier: String?
    var retainedSavedTourHoldEntryIdentifier: String?
    var filteredSavedTourHoldEntryIdentifier: String?
    var isSearchActive: Bool
    var searchQuerySnippet: String
    var searchQueryFingerprint: String
    var noMatchAvailabilityReason: String?
    var retainedEntryCount: Int
    var totalCount: Int
    var hiddenCount: Int
    var matchingEntryCount: Int
    var unfilteredVisibleCount: Int
    var selectedEntryIdentifier: String?
    var selectedOrdinal: Int?
    var entryCount: Int
    var rotationSeed: Int
    var sessionNumber: Int?
    var filename: String?
    var titleSnippet: String
    var statusSnippet: String
    var commitSnippet: String?
    var bodyPreviewText: String
    var sessionText: String
    var requestedPinnedEntryIdentifiers: [String]
    var retainedPinnedEntryIdentifiers: [String]
    var missingPinnedEntryIdentifiers: [String]
    var filteredPinnedEntryIdentifiers: [String]
    var pinnedEntryCount: Int
    var retainedPinnedEntryCount: Int
    var missingPinnedEntryCount: Int
    var filteredPinnedEntryCount: Int
    var warningStateIdentifier: String
    var warningCount: Int
    var hiddenWarningCount: Int
    var warningIdentifiers: [String]
    var hasWarnings: Bool

    var shouldDisplay: Bool {
        isAvailable
            || isSearchActive
            || pinnedEntryCount > 0
            || requestedSavedTourHoldEntryIdentifier != nil
            || hasWarnings
    }
}

struct CinematicRunRecapShareArtifactActionMenuPlan: Equatable, Identifiable {
    static let identifierMaxCharacters = CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
    static let actionLimit = 16
    static let labelMaxCharacters = 34
    static let helpMaxCharacters = 180
    static let systemImageMaxCharacters = 64
    static let shortcutHintMaxCharacters = 20

    var id: String { identifier }

    var identifier: String
    var actions: [Action]

    var actionCount: Int { actions.count }

    func actions(in section: Section) -> [Action] {
        actions.filter { $0.section == section }
    }

    enum Section: String, CaseIterable, Equatable, Identifiable {
        case navigate
        case exports
        case organize
        case tour
        case maintain

        var id: String { rawValue }

        var title: String {
            switch self {
            case .navigate:
                return "Navigate"
            case .exports:
                return "Exports"
            case .organize:
                return "Organize"
            case .tour:
                return "Tour"
            case .maintain:
                return "Maintain"
            }
        }
    }

    enum ActionKind: String, Equatable {
        case navigatePrevious
        case navigateNext
        case revealSelected
        case copySelectedExport
        case copyFilteredExport
        case copyLibraryExport
        case copyRollupExport
        case copyComparisonExport
        case copyPinnedExport
        case copyTourExport
        case cleanupOldArtifacts
        case toggleComparisonTargetMode
        case toggleSelectedPin
        case toggleTourHold
        case toggleSelectedTourHold
        case promoteTourHold
    }

    struct Action: Equatable, Identifiable {
        var id: String { identifier }

        var identifier: String
        var section: Section
        var label: String
        var systemImage: String
        var help: String
        var isEnabled: Bool
        var actionKind: ActionKind
        var shortcutHint: String?
    }
}

enum CinematicRunRecapShareArtifactActionMenuPlanner {
    static func plan(
        previewPlan: CinematicRunRecapShareArtifactPreviewBrowserPlan,
        rollupPlan: CinematicRunRecapShareArtifactRollupPlan,
        comparisonPlan: CinematicRunRecapShareArtifactComparisonPlan,
        pinnedReferencePlan: CinematicRunRecapShareArtifactPinnedReferencePlan,
        tourPlan: CinematicRunRecapShareArtifactTourPlan,
        selectedExportPlan: CinematicRunRecapShareArtifactSubsetExportPlan,
        filteredExportPlan: CinematicRunRecapShareArtifactSubsetExportPlan,
        historyPlan: CinematicRunRecapShareArtifactHistoryPlan
    ) -> CinematicRunRecapShareArtifactActionMenuPlan {
        var actions: [CinematicRunRecapShareArtifactActionMenuPlan.Action] = [
            action(
                kind: .navigatePrevious,
                section: .navigate,
                label: "Previous Artifact",
                systemImage: "chevron.left",
                help: previousHelp(previewPlan),
                isEnabled: previewPlan.canNavigatePrevious,
                shortcutHint: "Left",
                stateIdentifier: previewPlan.previousEntryIdentifier ?? previewPlan.availabilityReason
            ),
            action(
                kind: .navigateNext,
                section: .navigate,
                label: "Next Artifact",
                systemImage: "chevron.right",
                help: nextHelp(previewPlan),
                isEnabled: previewPlan.canNavigateNext,
                shortcutHint: "Right",
                stateIdentifier: previewPlan.nextEntryIdentifier ?? previewPlan.availabilityReason
            ),
            action(
                kind: .revealSelected,
                section: .navigate,
                label: "Reveal in Finder",
                systemImage: "folder",
                help: revealHelp(previewPlan),
                isEnabled: previewPlan.selectedEntryIdentifier != nil,
                shortcutHint: "Cmd-R",
                stateIdentifier: previewPlan.selectedEntryIdentifier ?? previewPlan.availabilityReason
            ),
            action(
                kind: .copySelectedExport,
                section: .exports,
                label: selectedExportPlan.copyLabel,
                systemImage: "doc.text",
                help: selectedExportPlan.copyHelp,
                isEnabled: selectedExportPlan.isAvailable,
                stateIdentifier: selectedExportPlan.exportIdentifier
            ),
            action(
                kind: .copyFilteredExport,
                section: .exports,
                label: filteredExportPlan.copyLabel,
                systemImage: "line.3.horizontal.decrease.circle",
                help: filteredExportPlan.copyHelp,
                isEnabled: filteredExportPlan.isAvailable,
                stateIdentifier: filteredExportPlan.exportIdentifier
            ),
            action(
                kind: .copyLibraryExport,
                section: .exports,
                label: historyPlan.isAvailable ? "Copy Library Export" : "Library Export Unavailable",
                systemImage: "doc.on.doc",
                help: libraryExportHelp(historyPlan),
                isEnabled: historyPlan.isAvailable,
                stateIdentifier: historyPlan.exportIdentifier
            ),
            action(
                kind: .copyRollupExport,
                section: .exports,
                label: rollupPlan.copyLabel,
                systemImage: "chart.bar",
                help: rollupPlan.copyHelp,
                isEnabled: rollupPlan.isAvailable,
                stateIdentifier: rollupPlan.exportIdentifier
            ),
            action(
                kind: .copyComparisonExport,
                section: .exports,
                label: comparisonPlan.copyLabel,
                systemImage: comparisonPlan.targetMode == .pinnedReference ? "pin.square" : "rectangle.split.2x1",
                help: comparisonPlan.copyHelp,
                isEnabled: comparisonPlan.isAvailable,
                stateIdentifier: comparisonPlan.exportIdentifier
            ),
            action(
                kind: .copyPinnedExport,
                section: .exports,
                label: pinnedReferencePlan.copyLabel,
                systemImage: "pin",
                help: pinnedExportHelp(pinnedReferencePlan),
                isEnabled: pinnedReferencePlan.isAvailable,
                stateIdentifier: pinnedReferencePlan.exportIdentifier
            ),
            action(
                kind: .copyTourExport,
                section: .exports,
                label: tourPlan.isAvailable ? "Copy Tour Export" : "Tour Export Unavailable",
                systemImage: "sparkles",
                help: tourExportHelp(tourPlan),
                isEnabled: tourPlan.isAvailable && tourPlan.selectedEntryIdentifier != nil,
                stateIdentifier: tourPlan.identifier
            ),
            action(
                kind: .toggleComparisonTargetMode,
                section: .organize,
                label: "Use \(comparisonPlan.targetMode.toggled.title) Compare",
                systemImage: comparisonPlan.targetMode.toggled == .pinnedReference ? "pin" : "rectangle.split.2x1",
                help: comparisonModeToggleHelp(comparisonPlan),
                isEnabled: true,
                stateIdentifier: comparisonPlan.targetModeIdentifier
            ),
            action(
                kind: .toggleSelectedPin,
                section: .organize,
                label: pinnedReferencePlan.selectedEntryIsPinned ? "Unpin Selected" : "Pin Selected",
                systemImage: pinnedReferencePlan.selectedEntryIsPinned ? "pin.slash" : "pin",
                help: togglePinHelp(pinnedReferencePlan, previewPlan: previewPlan),
                isEnabled: previewPlan.selectedEntryIdentifier != nil,
                stateIdentifier: pinnedReferencePlan.selectedPinStateIdentifier
            ),
            action(
                kind: .toggleTourHold,
                section: .tour,
                label: tourPlan.requestedSavedTourHoldEntryIdentifier == nil ? "Hold Tour Artifact" : "Release Tour Hold",
                systemImage: tourPlan.requestedSavedTourHoldEntryIdentifier == nil ? "lock" : "lock.open",
                help: tourHoldHelp(tourPlan),
                isEnabled: tourPlan.requestedSavedTourHoldEntryIdentifier != nil || tourPlan.selectedEntryIdentifier != nil,
                stateIdentifier: tourPlan.savedTourHoldStateIdentifier
            ),
            action(
                kind: .toggleSelectedTourHold,
                section: .tour,
                label: selectedHoldIsActive(previewPlan: previewPlan, tourPlan: tourPlan)
                    ? "Release Selected Hold"
                    : "Hold Selected Artifact",
                systemImage: selectedHoldIsActive(previewPlan: previewPlan, tourPlan: tourPlan)
                    ? "bookmark.slash"
                    : "bookmark",
                help: selectedHoldHelp(previewPlan, tourPlan: tourPlan),
                isEnabled: previewPlan.selectedEntryIdentifier != nil,
                stateIdentifier: previewPlan.selectedEntryIdentifier ?? tourPlan.savedTourHoldStateIdentifier
            ),
            action(
                kind: .promoteTourHold,
                section: .tour,
                label: promoteTourHoldLabel(comparisonPlan),
                systemImage: comparisonPlan.promotedHoldStateIdentifier == "none" ? "pin.circle" : "pin.circle.fill",
                help: promoteTourHoldHelp(tourPlan, comparisonPlan: comparisonPlan),
                isEnabled: tourPlan.retainedSavedTourHoldEntryIdentifier != nil,
                stateIdentifier: comparisonPlan.promotedHoldStateIdentifier
            ),
            action(
                kind: .cleanupOldArtifacts,
                section: .maintain,
                label: historyPlan.cleanupCandidateCount > 0 ? "Clean Up Old Artifacts" : "Cleanup Unavailable",
                systemImage: "trash",
                help: cleanupHelp(historyPlan),
                isEnabled: historyPlan.cleanupCandidateCount > 0,
                stateIdentifier: "cleanup:\(historyPlan.cleanupCandidateCount)|hidden:\(historyPlan.hiddenCleanupCandidateCount)"
            )
        ]

        actions = Array(actions.prefix(CinematicRunRecapShareArtifactActionMenuPlan.actionLimit))
        let identifier = bounded(
            [
                "run-recap-share-artifact-action-menu",
                "actions:\(actions.count)",
                "content:\(fingerprint(actions.map(\.identifier).joined(separator: "|")))"
            ].joined(separator: "|"),
            limit: CinematicRunRecapShareArtifactActionMenuPlan.identifierMaxCharacters
        )

        return CinematicRunRecapShareArtifactActionMenuPlan(
            identifier: identifier,
            actions: actions
        )
    }

    private typealias MenuPlan = CinematicRunRecapShareArtifactActionMenuPlan
    private typealias Action = CinematicRunRecapShareArtifactActionMenuPlan.Action
    private typealias ActionKind = CinematicRunRecapShareArtifactActionMenuPlan.ActionKind
    private typealias ActionSection = CinematicRunRecapShareArtifactActionMenuPlan.Section

    private static func action(
        kind: ActionKind,
        section: ActionSection,
        label: String,
        systemImage: String,
        help: String,
        isEnabled: Bool,
        shortcutHint: String? = nil,
        stateIdentifier: String
    ) -> Action {
        let identifier = bounded(
            [
                "run-recap-share-artifact-action",
                "kind:\(kind.rawValue)",
                "section:\(section.rawValue)",
                "enabled:\(isEnabled)",
                "state:\(fingerprint(stateIdentifier))"
            ].joined(separator: "|"),
            limit: MenuPlan.identifierMaxCharacters
        )

        return Action(
            identifier: identifier,
            section: section,
            label: bounded(label, limit: MenuPlan.labelMaxCharacters),
            systemImage: bounded(systemImage, limit: MenuPlan.systemImageMaxCharacters),
            help: bounded(help, limit: MenuPlan.helpMaxCharacters),
            isEnabled: isEnabled,
            actionKind: kind,
            shortcutHint: boundedOptional(shortcutHint, limit: MenuPlan.shortcutHintMaxCharacters)
        )
    }

    private static func previousHelp(_ previewPlan: CinematicRunRecapShareArtifactPreviewBrowserPlan) -> String {
        if previewPlan.canNavigatePrevious {
            return previewPlan.isSearchActive
                ? "Show the newer matching saved recap share artifact."
                : "Show the newer saved recap share artifact."
        }
        return previewPlan.isSearchActive
            ? "Already showing the newest matching saved recap share artifact."
            : "Already showing the newest saved recap share artifact."
    }

    private static func nextHelp(_ previewPlan: CinematicRunRecapShareArtifactPreviewBrowserPlan) -> String {
        if previewPlan.canNavigateNext {
            return previewPlan.isSearchActive
                ? "Show the older matching saved recap share artifact."
                : "Show the older saved recap share artifact."
        }
        return previewPlan.isSearchActive
            ? "Already showing the oldest matching saved recap share artifact."
            : "Already showing the oldest visible recap share artifact."
    }

    private static func revealHelp(_ previewPlan: CinematicRunRecapShareArtifactPreviewBrowserPlan) -> String {
        guard previewPlan.selectedEntryIdentifier != nil else {
            return "No saved recap share artifact to reveal."
        }
        return "Reveal \(previewPlan.pathSnippet) in Finder."
    }

    private static func libraryExportHelp(_ historyPlan: CinematicRunRecapShareArtifactHistoryPlan) -> String {
        if !historyPlan.isAvailable {
            return "No recap share artifact library export is available: \(historyPlan.availabilityReason)."
        }
        return "Copy combined Markdown export \(historyPlan.exportIdentifier)."
    }

    private static func cleanupHelp(_ historyPlan: CinematicRunRecapShareArtifactHistoryPlan) -> String {
        guard historyPlan.cleanupCandidateCount > 0 else {
            return "No old recap share artifacts to clean up; retaining newest \(historyPlan.retentionLimit)."
        }
        return "Delete \(historyPlan.cleanupCandidateCount) old recap share artifact\(historyPlan.cleanupCandidateCount == 1 ? "" : "s") while retaining newest \(historyPlan.retentionLimit)."
    }

    private static func comparisonModeToggleHelp(
        _ comparisonPlan: CinematicRunRecapShareArtifactComparisonPlan
    ) -> String {
        let nextMode = comparisonPlan.targetMode.toggled.title
        if comparisonPlan.promotedHoldStateIdentifier != "none" {
            return "Switch comparison target mode to \(nextMode); the saved tour hold remains in context."
        }
        return "Switch recap artifact comparison target mode to \(nextMode)."
    }

    private static func togglePinHelp(
        _ pinnedReferencePlan: CinematicRunRecapShareArtifactPinnedReferencePlan,
        previewPlan: CinematicRunRecapShareArtifactPreviewBrowserPlan
    ) -> String {
        guard previewPlan.selectedEntryIdentifier != nil else {
            return "No selected recap share artifact to pin."
        }
        if pinnedReferencePlan.selectedEntryIsPinned {
            return "Unpin the selected recap share artifact from the pinned reference strip."
        }
        let stale = pinnedReferencePlan.missingPinnedEntryCount > 0
            ? " \(pinnedReferencePlan.missingPinnedEntryCount) stale pin\(pinnedReferencePlan.missingPinnedEntryCount == 1 ? "" : "s") remain reported."
            : ""
        return "Pin the selected recap share artifact for quick selection and pinned export.\(stale)"
    }

    private static func pinnedExportHelp(
        _ pinnedReferencePlan: CinematicRunRecapShareArtifactPinnedReferencePlan
    ) -> String {
        guard pinnedReferencePlan.isAvailable else {
            return pinnedReferencePlan.copyHelp
        }

        let stale = pinnedReferencePlan.missingPinnedEntryCount > 0
            ? "; \(pinnedReferencePlan.missingPinnedEntryCount) stale"
            : ""
        let filtered = pinnedReferencePlan.filteredPinnedEntryCount > 0
            ? "; \(pinnedReferencePlan.filteredPinnedEntryCount) filtered"
            : ""
        let search = pinnedReferencePlan.isSearchActive
            ? "; \(pinnedReferencePlan.quickSelectEntryCount) quick visible for \(pinnedReferencePlan.searchQuerySnippet)"
            : ""
        return "Copy pinned export for \(pinnedReferencePlan.retainedPinnedEntryCount) retained pin\(pinnedReferencePlan.retainedPinnedEntryCount == 1 ? "" : "s")\(stale)\(filtered)\(search)."
    }

    private static func tourHoldHelp(_ tourPlan: CinematicRunRecapShareArtifactTourPlan) -> String {
        switch tourPlan.savedTourHoldStateIdentifier {
        case "held":
            return "Release the saved recap artifact tour hold."
        case "filtered-hold":
            return "Release the saved recap artifact tour hold hidden by search \(tourPlan.searchQuerySnippet)."
        case "missing-hold":
            return "Release the saved recap artifact tour hold that is no longer retained."
        default:
            guard tourPlan.selectedEntryIdentifier != nil else {
                return "No currently toured recap artifact to hold."
            }
            return "Hold the currently toured recap artifact so the idle tour keeps returning to it."
        }
    }

    private static func selectedHoldHelp(
        _ previewPlan: CinematicRunRecapShareArtifactPreviewBrowserPlan,
        tourPlan: CinematicRunRecapShareArtifactTourPlan
    ) -> String {
        guard previewPlan.selectedEntryIdentifier != nil else {
            return "No selected recap artifact to hold for the idle tour."
        }
        if selectedHoldIsActive(previewPlan: previewPlan, tourPlan: tourPlan) {
            return "Release the selected recap artifact from the saved tour hold."
        }
        return "Hold the selected recap artifact for the idle saved artifact tour."
    }

    private static func selectedHoldIsActive(
        previewPlan: CinematicRunRecapShareArtifactPreviewBrowserPlan,
        tourPlan: CinematicRunRecapShareArtifactTourPlan
    ) -> Bool {
        previewPlan.selectedEntryIdentifier != nil
            && previewPlan.selectedEntryIdentifier == tourPlan.requestedSavedTourHoldEntryIdentifier
    }

    private static func promoteTourHoldLabel(
        _ comparisonPlan: CinematicRunRecapShareArtifactComparisonPlan
    ) -> String {
        switch comparisonPlan.promotedHoldStateIdentifier {
        case "retained-promoted-hold-target", "filtered-promoted-hold-target":
            return "Hold Promoted"
        case "missing-promoted-hold":
            return "Promote Hold Missing"
        default:
            return "Promote Tour Hold"
        }
    }

    private static func promoteTourHoldHelp(
        _ tourPlan: CinematicRunRecapShareArtifactTourPlan,
        comparisonPlan: CinematicRunRecapShareArtifactComparisonPlan
    ) -> String {
        if comparisonPlan.promotedHoldStateIdentifier == "retained-promoted-hold-target" {
            return "The saved recap tour hold is already the pinned comparison target."
        }
        if comparisonPlan.promotedHoldStateIdentifier == "filtered-promoted-hold-target" {
            return "The saved recap tour hold is promoted and filtered by the current search."
        }
        guard let retainedSavedTourHoldEntryIdentifier = tourPlan.retainedSavedTourHoldEntryIdentifier else {
            if tourPlan.requestedSavedTourHoldEntryIdentifier == nil {
                return "No saved recap tour hold to promote."
            }
            return "The saved recap tour hold is not retained, so it cannot be promoted to a pinned comparison."
        }
        if tourPlan.filteredSavedTourHoldEntryIdentifier == retainedSavedTourHoldEntryIdentifier {
            return "Promote this retained tour hold to pinned comparison even though the current search filters it."
        }
        return "Promote this saved tour hold to pinned comparison."
    }

    private static func tourExportHelp(_ tourPlan: CinematicRunRecapShareArtifactTourPlan) -> String {
        guard tourPlan.isAvailable, let sessionNumber = tourPlan.sessionNumber else {
            return "No currently toured recap artifact export is available: \(tourPlan.availabilityReason)."
        }
        return "Copy the currently toured recap artifact export for S\(sessionNumber) from \(tourPlan.selectionSourceIdentifier) tour state."
    }

    private static func boundedOptional(_ text: String?, limit: Int) -> String? {
        let boundedText = bounded(text ?? "", limit: limit)
        return boundedText == "none" ? nil : boundedText
    }

    private static func bounded(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "none" }
        guard normalized.count <= limit else {
            let prefixLimit = max(1, limit - 3)
            return normalized.prefix(prefixLimit)
                .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }
        return normalized
    }

    private static func fingerprint(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}

enum CinematicRunRecapShareArtifactPinnedReferencePlanner {
    static func plan(
        historyPlan: CinematicRunRecapShareArtifactHistoryPlan,
        pinnedEntryIdentifiers: [String] = [],
        selectedEntryIdentifier: String? = nil,
        searchQuery: String? = nil
    ) -> CinematicRunRecapShareArtifactPinnedReferencePlan {
        let search = searchState(for: searchQuery)
        let retainedEntries = historyPlan.entries
        let matchingEntries = search.isActive
            ? retainedEntries.filter { matches($0, normalizedQuery: search.normalizedQuery) }
            : retainedEntries
        let matchingEntryIdentifiers = Set(matchingEntries.map(\.identifier))
        let requestedPinnedEntryIdentifiers = boundedIdentifierList(pinnedEntryIdentifiers)
        let retainedEntriesByIdentifier = Dictionary(
            uniqueKeysWithValues: retainedEntries.map { ($0.identifier, $0) }
        )
        let retainedPinnedEntries = requestedPinnedEntryIdentifiers.compactMap { retainedEntriesByIdentifier[$0] }
        let retainedPinnedEntryIdentifiers = retainedPinnedEntries.map(\.identifier)
        let retainedPinnedEntryIdentifierSet = Set(retainedPinnedEntryIdentifiers)
        let missingPinnedEntryIdentifiers = requestedPinnedEntryIdentifiers.filter {
            retainedEntriesByIdentifier[$0] == nil
        }
        let filteredPinnedEntryIdentifiers = search.isActive
            ? retainedPinnedEntryIdentifiers.filter { !matchingEntryIdentifiers.contains($0) }
            : []
        let quickSelectEntryIdentifiers = retainedPinnedEntryIdentifiers.filter {
            !search.isActive || matchingEntryIdentifiers.contains($0)
        }
        let quickSelectEntryIdentifierSet = Set(quickSelectEntryIdentifiers)
        let boundedSelectedEntryIdentifier = boundedOptionalIdentifier(selectedEntryIdentifier)
        let selectedEntryIsPinned = boundedSelectedEntryIdentifier.map {
            retainedPinnedEntryIdentifierSet.contains($0)
        } ?? false
        let selectedPinStateIdentifier = selectedPinStateIdentifier(
            selectedEntryIdentifier: boundedSelectedEntryIdentifier,
            selectedEntryIsPinned: selectedEntryIsPinned,
            missingPinnedEntryIdentifiers: missingPinnedEntryIdentifiers
        )
        let noMatchAvailabilityReason = search.isActive && !retainedEntries.isEmpty && matchingEntries.isEmpty
            ? "no-matching-recap-share-artifacts"
            : nil
        let isAvailable = !retainedPinnedEntries.isEmpty
        let availabilityReason = availabilityReason(
            isAvailable: isAvailable,
            requestedPinnedEntryIdentifiers: requestedPinnedEntryIdentifiers,
            missingPinnedEntryIdentifiers: missingPinnedEntryIdentifiers,
            historyPlan: historyPlan
        )
        let warningStateIdentifier = historyPlan.hasWarnings ? "warnings" : "clear"
        let references = retainedPinnedEntries.map { entry in
            reference(
                for: entry,
                isQuickSelectable: quickSelectEntryIdentifierSet.contains(entry.identifier)
            )
        }
        let exportIdentifier = bounded(
            [
                "run-recap-share-artifact-pins-export",
                "availability:\(availabilityReason)",
                "retained:\(retainedEntries.count)",
                "total:\(historyPlan.totalCount)",
                "hidden:\(historyPlan.hiddenCount)",
                "matching:\(matchingEntries.count)",
                "pins:\(requestedPinnedEntryIdentifiers.count)",
                "retained-pins:\(retainedPinnedEntryIdentifiers.count)",
                "missing-pins:\(missingPinnedEntryIdentifiers.count)",
                "filtered-pins:\(filteredPinnedEntryIdentifiers.count)",
                "quick:\(quickSelectEntryIdentifiers.count)",
                "query:\(search.queryFingerprint)",
                "query-snippet:\(search.querySnippet)",
                "no-match:\(noMatchAvailabilityReason ?? "none")",
                "selected:\(boundedSelectedEntryIdentifier ?? "none")",
                "selected-pin:\(selectedPinStateIdentifier)",
                "warnings:\(warningStateIdentifier)",
                "warning-count:\(historyPlan.warningCount)",
                "content:\(fingerprint(retainedPinnedEntryIdentifiers.joined(separator: "|")))"
            ].joined(separator: "|"),
            limit: CinematicRunRecapShareArtifactPinnedReferencePlan.identifierMaxCharacters
        )
        let export = exportText(
            exportIdentifier: exportIdentifier,
            isAvailable: isAvailable,
            availabilityReason: availabilityReason,
            historyPlan: historyPlan,
            retainedEntries: retainedEntries,
            matchingEntries: matchingEntries,
            search: search,
            noMatchAvailabilityReason: noMatchAvailabilityReason,
            selectedEntryIdentifier: boundedSelectedEntryIdentifier,
            selectedPinStateIdentifier: selectedPinStateIdentifier,
            requestedPinnedEntryIdentifiers: requestedPinnedEntryIdentifiers,
            retainedPinnedEntryIdentifiers: retainedPinnedEntryIdentifiers,
            missingPinnedEntryIdentifiers: missingPinnedEntryIdentifiers,
            filteredPinnedEntryIdentifiers: filteredPinnedEntryIdentifiers,
            quickSelectEntryIdentifiers: quickSelectEntryIdentifiers,
            references: references,
            warningStateIdentifier: warningStateIdentifier
        )
        let identifier = bounded(
            [
                "run-recap-share-artifact-pins",
                "availability:\(availabilityReason)",
                "export:\(fingerprint(exportIdentifier))",
                "pins:\(requestedPinnedEntryIdentifiers.count)",
                "retained-pins:\(retainedPinnedEntryIdentifiers.count)",
                "missing-pins:\(missingPinnedEntryIdentifiers.count)",
                "filtered-pins:\(filteredPinnedEntryIdentifiers.count)",
                "quick:\(quickSelectEntryIdentifiers.count)",
                "query:\(search.queryFingerprint)",
                "selected-pin:\(selectedPinStateIdentifier)",
                "warnings:\(warningStateIdentifier)",
                "copy:\(export.count)"
            ].joined(separator: "|"),
            limit: CinematicRunRecapShareArtifactPinnedReferencePlan.identifierMaxCharacters
        )

        return CinematicRunRecapShareArtifactPinnedReferencePlan(
            identifier: identifier,
            exportIdentifier: exportIdentifier,
            isAvailable: isAvailable,
            availabilityReason: availabilityReason,
            isSearchActive: search.isActive,
            searchQuerySnippet: search.querySnippet,
            searchQueryFingerprint: search.queryFingerprint,
            noMatchAvailabilityReason: noMatchAvailabilityReason,
            retainedEntryCount: retainedEntries.count,
            totalCount: historyPlan.totalCount,
            hiddenCount: historyPlan.hiddenCount,
            matchingEntryCount: matchingEntries.count,
            unfilteredVisibleCount: retainedEntries.count,
            selectedEntryIdentifier: boundedSelectedEntryIdentifier,
            selectedEntryIsPinned: selectedEntryIsPinned,
            selectedPinStateIdentifier: selectedPinStateIdentifier,
            requestedPinnedEntryIdentifiers: requestedPinnedEntryIdentifiers,
            retainedPinnedEntryIdentifiers: retainedPinnedEntryIdentifiers,
            missingPinnedEntryIdentifiers: missingPinnedEntryIdentifiers,
            filteredPinnedEntryIdentifiers: filteredPinnedEntryIdentifiers,
            quickSelectEntryIdentifiers: quickSelectEntryIdentifiers,
            pinnedEntryCount: requestedPinnedEntryIdentifiers.count,
            retainedPinnedEntryCount: retainedPinnedEntryIdentifiers.count,
            missingPinnedEntryCount: missingPinnedEntryIdentifiers.count,
            filteredPinnedEntryCount: filteredPinnedEntryIdentifiers.count,
            quickSelectEntryCount: quickSelectEntryIdentifiers.count,
            references: references,
            warningStateIdentifier: warningStateIdentifier,
            warningCount: historyPlan.warningCount,
            hiddenWarningCount: historyPlan.hiddenWarningCount,
            warningIdentifiers: historyPlan.warnings.map(\.identifier),
            hasWarnings: historyPlan.hasWarnings,
            exportText: export,
            copyLabel: copyLabel(isAvailable: isAvailable),
            copyHelp: copyHelp(
                isAvailable: isAvailable,
                availabilityReason: availabilityReason,
                retainedPinnedCount: retainedPinnedEntryIdentifiers.count,
                requestedPinnedCount: requestedPinnedEntryIdentifiers.count,
                missingPinnedCount: missingPinnedEntryIdentifiers.count,
                filteredPinnedCount: filteredPinnedEntryIdentifiers.count,
                quickSelectCount: quickSelectEntryIdentifiers.count,
                search: search,
                exportIdentifier: exportIdentifier
            )
        )
    }

    private struct SearchState {
        var normalizedQuery: String
        var querySnippet: String
        var queryFingerprint: String
        var isActive: Bool
    }

    private static func searchState(for query: String?) -> SearchState {
        let normalizedQuery = normalizedSearchText(query ?? "")
        let isActive = !normalizedQuery.isEmpty
        return SearchState(
            normalizedQuery: normalizedQuery,
            querySnippet: isActive
                ? bounded(
                    normalizedQuery,
                    limit: CinematicRunRecapShareArtifactPinnedReferencePlan.searchQuerySnippetMaxCharacters
                )
                : "none",
            queryFingerprint: isActive ? fingerprint(normalizedQuery) : "none",
            isActive: isActive
        )
    }

    private static func matches(
        _ entry: CinematicRunRecapShareArtifactHistoryPlan.Entry,
        normalizedQuery query: String
    ) -> Bool {
        guard !query.isEmpty else { return true }
        let fields = [
            entry.filename,
            entry.titleSnippet,
            entry.statusSnippet,
            entry.commitSnippet ?? "",
            entry.pathDisplayText,
            previewSearchBody(from: entry.markdownContents) ?? ""
        ]
        return fields.contains { normalizedSearchText($0).contains(query) }
    }

    private static func selectedPinStateIdentifier(
        selectedEntryIdentifier: String?,
        selectedEntryIsPinned: Bool,
        missingPinnedEntryIdentifiers: [String]
    ) -> String {
        guard let selectedEntryIdentifier else { return "no-selection" }
        if selectedEntryIsPinned {
            return "pinned"
        }
        if missingPinnedEntryIdentifiers.contains(selectedEntryIdentifier) {
            return "missing-pinned-selection"
        }
        return "unpinned"
    }

    private static func availabilityReason(
        isAvailable: Bool,
        requestedPinnedEntryIdentifiers: [String],
        missingPinnedEntryIdentifiers: [String],
        historyPlan: CinematicRunRecapShareArtifactHistoryPlan
    ) -> String {
        guard !isAvailable else { return "available" }
        guard !requestedPinnedEntryIdentifiers.isEmpty else {
            return "no-pinned-recap-share-artifacts"
        }
        if historyPlan.entries.isEmpty {
            return "pinned-recap-share-artifacts-missing"
        }
        if missingPinnedEntryIdentifiers.count == requestedPinnedEntryIdentifiers.count {
            return "pinned-recap-share-artifacts-missing"
        }
        return "no-retained-pinned-recap-share-artifacts"
    }

    private static func reference(
        for entry: CinematicRunRecapShareArtifactHistoryPlan.Entry,
        isQuickSelectable: Bool
    ) -> CinematicRunRecapShareArtifactPinnedReferencePlan.Reference {
        CinematicRunRecapShareArtifactPinnedReferencePlan.Reference(
            identifier: entry.identifier,
            sessionNumber: entry.sessionNumber,
            filename: bounded(
                entry.filename,
                limit: CinematicRunRecapShareArtifactHistoryPlan.filenameMaxCharacters
            ),
            titleSnippet: bounded(
                entry.titleSnippet,
                limit: CinematicRunRecapShareArtifactPinnedReferencePlan.snippetMaxCharacters
            ),
            statusSnippet: bounded(
                entry.statusSnippet,
                limit: CinematicRunRecapShareArtifactPinnedReferencePlan.snippetMaxCharacters
            ),
            commitSnippet: entry.commitSnippet.map {
                bounded(
                    $0,
                    limit: CinematicRunRecapShareArtifactPinnedReferencePlan.snippetMaxCharacters
                )
            },
            isQuickSelectable: isQuickSelectable
        )
    }

    private static func exportText(
        exportIdentifier: String,
        isAvailable: Bool,
        availabilityReason: String,
        historyPlan: CinematicRunRecapShareArtifactHistoryPlan,
        retainedEntries: [CinematicRunRecapShareArtifactHistoryPlan.Entry],
        matchingEntries: [CinematicRunRecapShareArtifactHistoryPlan.Entry],
        search: SearchState,
        noMatchAvailabilityReason: String?,
        selectedEntryIdentifier: String?,
        selectedPinStateIdentifier: String,
        requestedPinnedEntryIdentifiers: [String],
        retainedPinnedEntryIdentifiers: [String],
        missingPinnedEntryIdentifiers: [String],
        filteredPinnedEntryIdentifiers: [String],
        quickSelectEntryIdentifiers: [String],
        references: [CinematicRunRecapShareArtifactPinnedReferencePlan.Reference],
        warningStateIdentifier: String
    ) -> String {
        var lines = [
            "# Compass Recap Artifact Pins",
            "",
            "- Export: \(exportIdentifier)",
            "- Availability: \(isAvailable ? "available" : "unavailable (\(availabilityReason))")",
            "- Retention limit: \(historyPlan.retentionLimit)",
            "- Total artifacts: \(historyPlan.totalCount)",
            "- Retained artifacts: \(retainedEntries.count)",
            "- Matching artifacts: \(matchingEntries.count)",
            "- Hidden artifacts: \(historyPlan.hiddenCount)",
            "- Pinned artifacts: \(requestedPinnedEntryIdentifiers.count)",
            "- Retained pins: \(retainedPinnedEntryIdentifiers.count)",
            "- Missing pins: \(missingPinnedEntryIdentifiers.count)",
            "- Filtered pins: \(filteredPinnedEntryIdentifiers.count)",
            "- Quick-select pins: \(quickSelectEntryIdentifiers.count)",
            "- Search active: \(search.isActive)",
            "- Search query: \(search.querySnippet)",
            "- Search fingerprint: \(search.queryFingerprint)",
            "- No-match reason: \(noMatchAvailabilityReason ?? "none")",
            "- Selected entry: \(selectedEntryIdentifier ?? "none")",
            "- Selected pin state: \(selectedPinStateIdentifier)",
            "- Pinned identifiers: \(requestedPinnedEntryIdentifiers.isEmpty ? "none" : requestedPinnedEntryIdentifiers.joined(separator: ", "))",
            "- Retained pin identifiers: \(retainedPinnedEntryIdentifiers.isEmpty ? "none" : retainedPinnedEntryIdentifiers.joined(separator: ", "))",
            "- Missing pin identifiers: \(missingPinnedEntryIdentifiers.isEmpty ? "none" : missingPinnedEntryIdentifiers.joined(separator: ", "))",
            "- Filtered pin identifiers: \(filteredPinnedEntryIdentifiers.isEmpty ? "none" : filteredPinnedEntryIdentifiers.joined(separator: ", "))",
            "- Quick-select identifiers: \(quickSelectEntryIdentifiers.isEmpty ? "none" : quickSelectEntryIdentifiers.joined(separator: ", "))",
            "- Warning state: \(warningStateIdentifier)",
            "- Warnings: \(historyPlan.warningCount)",
            "- Hidden warnings: \(historyPlan.hiddenWarningCount)",
            "- Warning identifiers: \(historyPlan.warnings.isEmpty ? "none" : historyPlan.warnings.map(\.identifier).joined(separator: ", "))",
            "",
            "## Pinned References"
        ]

        if references.isEmpty {
            lines.append("No retained pinned recap share artifacts are available.")
        } else {
            lines.append(contentsOf: references.map { reference in
                [
                    "- S\(reference.sessionNumber) \(reference.filename)",
                    "title \(reference.titleSnippet)",
                    "status \(reference.statusSnippet)",
                    "commit \(reference.commitSnippet ?? "none")",
                    "quick \(reference.isQuickSelectable)",
                    "artifact \(reference.identifier)"
                ].joined(separator: " | ")
            })
        }

        return boundedArtifactText(
            lines.joined(separator: "\n"),
            limit: CinematicRunRecapShareArtifactPinnedReferencePlan.exportTextMaxCharacters
        )
    }

    private static func copyLabel(isAvailable: Bool) -> String {
        bounded(
            isAvailable ? "Copy pinned export" : "Pinned export unavailable",
            limit: CinematicRunRecapShareArtifactPinnedReferencePlan.copyLabelMaxCharacters
        )
    }

    private static func copyHelp(
        isAvailable: Bool,
        availabilityReason: String,
        retainedPinnedCount: Int,
        requestedPinnedCount: Int,
        missingPinnedCount: Int,
        filteredPinnedCount: Int,
        quickSelectCount: Int,
        search: SearchState,
        exportIdentifier: String
    ) -> String {
        guard isAvailable else {
            return bounded(
                "No pinned recap artifact export is available: \(availabilityReason).",
                limit: CinematicRunRecapShareArtifactPinnedReferencePlan.copyHelpMaxCharacters
            )
        }

        let searchDetail = search.isActive
            ? " with \(quickSelectCount) quick-select visible and \(filteredPinnedCount) filtered by \(search.querySnippet)"
            : ""
        let staleDetail = missingPinnedCount > 0
            ? " (\(missingPinnedCount) stale of \(requestedPinnedCount) pins)"
            : ""
        return bounded(
            "Copy pinned recap artifact export \(exportIdentifier) for \(retainedPinnedCount) retained pin\(retainedPinnedCount == 1 ? "" : "s")\(searchDetail)\(staleDetail).",
            limit: CinematicRunRecapShareArtifactPinnedReferencePlan.copyHelpMaxCharacters
        )
    }

    private static func previewSearchBody(from markdownContents: String) -> String? {
        shareTextBody(in: markdownContents)
            ?? fallbackBody(in: markdownContents)
    }

    private static func shareTextBody(in markdownContents: String) -> String? {
        guard let range = markdownContents.range(of: "## Share Text") else {
            return nil
        }

        let text = markdownContents[range.upperBound...]
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { line in
                String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { line in
                !line.isEmpty && !line.hasPrefix("```")
            }
            .joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    private static func fallbackBody(in markdownContents: String) -> String? {
        let text = markdownContents
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { line in
                String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { line in
                !line.isEmpty
                    && !line.hasPrefix("#")
                    && !line.hasPrefix("- ")
                    && !line.hasPrefix("```")
            }
            .joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    private static func boundedIdentifierList(_ identifiers: [String]) -> [String] {
        var seen = Set<String>()
        var boundedIdentifiers: [String] = []

        for identifier in identifiers {
            guard let boundedIdentifier = boundedOptionalIdentifier(identifier),
                  seen.insert(boundedIdentifier).inserted else {
                continue
            }
            boundedIdentifiers.append(boundedIdentifier)
            if boundedIdentifiers.count == CinematicRunRecapShareArtifactPinnedReferencePlan.pinIdentifierLimit {
                break
            }
        }

        return boundedIdentifiers
    }

    private static func boundedOptionalIdentifier(_ identifier: String?) -> String? {
        let boundedIdentifier = bounded(
            identifier ?? "",
            limit: CinematicRunRecapShareArtifactPinnedReferencePlan.identifierMaxCharacters
        )
        return boundedIdentifier == "none" ? nil : boundedIdentifier
    }

    private static func normalizedSearchText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func bounded(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "none" }
        guard normalized.count <= limit else {
            let prefixLimit = max(1, limit - 3)
            return normalized.prefix(prefixLimit)
                .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }
        return normalized
    }

    private static func boundedArtifactText(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = text
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "none" }
        guard normalized.count <= limit else {
            let prefixLimit = max(1, limit - 3)
            return normalized.prefix(prefixLimit)
                .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }
        return normalized
    }

    private static func fingerprint(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}

enum CinematicRunRecapShareArtifactTourPlanner {
    static func plan(
        historyPlan: CinematicRunRecapShareArtifactHistoryPlan,
        libraryContext: CinematicRunRecapShareArtifactLibraryContext = .empty,
        rotationSeed: Int = 0
    ) -> CinematicRunRecapShareArtifactTourPlan {
        let search = searchState(for: libraryContext.searchText)
        let retainedEntries = historyPlan.entries
        let matchingEntries = search.isActive
            ? retainedEntries.filter { matches($0, normalizedQuery: search.normalizedQuery) }
            : retainedEntries
        let matchingEntryIdentifiers = Set(matchingEntries.map(\.identifier))
        let requestedPinnedEntryIdentifiers = boundedIdentifierList(libraryContext.pinnedEntryIdentifiers)
        let retainedEntriesByIdentifier = Dictionary(
            uniqueKeysWithValues: retainedEntries.map { ($0.identifier, $0) }
        )
        let requestedSavedTourHoldEntryIdentifier = boundedOptionalIdentifier(
            libraryContext.savedTourHoldEntryIdentifier
        )
        let retainedSavedTourHoldEntry = requestedSavedTourHoldEntryIdentifier.flatMap {
            retainedEntriesByIdentifier[$0]
        }
        let retainedSavedTourHoldEntryIdentifier = retainedSavedTourHoldEntry?.identifier
        let filteredSavedTourHoldEntryIdentifier = search.isActive
            ? retainedSavedTourHoldEntry
                .flatMap { matchingEntryIdentifiers.contains($0.identifier) ? nil : $0.identifier }
            : nil
        let visibleSavedTourHoldEntry = filteredSavedTourHoldEntryIdentifier == nil
            ? retainedSavedTourHoldEntry
            : nil
        let savedTourHoldStateIdentifier = savedTourHoldStateIdentifier(
            requestedEntryIdentifier: requestedSavedTourHoldEntryIdentifier,
            retainedEntryIdentifier: retainedSavedTourHoldEntryIdentifier,
            filteredEntryIdentifier: filteredSavedTourHoldEntryIdentifier
        )
        let retainedPinnedEntries = requestedPinnedEntryIdentifiers.compactMap { retainedEntriesByIdentifier[$0] }
        let retainedPinnedEntryIdentifiers = retainedPinnedEntries.map(\.identifier)
        let missingPinnedEntryIdentifiers = requestedPinnedEntryIdentifiers.filter {
            retainedEntriesByIdentifier[$0] == nil
        }
        let filteredPinnedEntryIdentifiers = search.isActive
            ? retainedPinnedEntryIdentifiers.filter { !matchingEntryIdentifiers.contains($0) }
            : []
        let visiblePinnedEntries = search.isActive
            ? retainedPinnedEntries.filter { matchingEntryIdentifiers.contains($0.identifier) }
            : retainedPinnedEntries
        let selectionPool: [CinematicRunRecapShareArtifactHistoryPlan.Entry]
        let selectionSourceIdentifier: String
        if let visibleSavedTourHoldEntry {
            selectionPool = [visibleSavedTourHoldEntry]
            selectionSourceIdentifier = "held"
        } else if !visiblePinnedEntries.isEmpty {
            selectionPool = visiblePinnedEntries
            selectionSourceIdentifier = "pinned"
        } else {
            selectionPool = matchingEntries
            selectionSourceIdentifier = "recent"
        }
        let selectedIndex = rotatedIndex(seed: rotationSeed, count: selectionPool.count)
        let selectedEntry = selectedIndex.map { selectionPool[$0] }
        let noMatchAvailabilityReason = search.isActive && !retainedEntries.isEmpty && matchingEntries.isEmpty
            ? "no-matching-recap-share-artifacts"
            : nil
        let stateIdentifier = stateIdentifier(
            selectedEntry: selectedEntry,
            selectionSourceIdentifier: selectionSourceIdentifier,
            historyPlan: historyPlan,
            search: search,
            noMatchAvailabilityReason: noMatchAvailabilityReason,
            savedTourHoldStateIdentifier: savedTourHoldStateIdentifier,
            requestedPinnedEntryIdentifiers: requestedPinnedEntryIdentifiers,
            retainedPinnedEntryIdentifiers: retainedPinnedEntryIdentifiers,
            missingPinnedEntryIdentifiers: missingPinnedEntryIdentifiers,
            filteredPinnedEntryIdentifiers: filteredPinnedEntryIdentifiers
        )
        let availabilityReason = availabilityReason(
            selectedEntry: selectedEntry,
            historyPlan: historyPlan,
            noMatchAvailabilityReason: noMatchAvailabilityReason,
            stateIdentifier: stateIdentifier
        )
        let warningStateIdentifier = historyPlan.hasWarnings ? "warnings" : "clear"
        let identifier = bounded(
            [
                "run-recap-share-artifact-tour",
                "availability:\(availabilityReason)",
                "state:\(stateIdentifier)",
                "source:\(selectionSourceIdentifier)",
                "retained:\(retainedEntries.count)",
                "total:\(historyPlan.totalCount)",
                "hidden:\(historyPlan.hiddenCount)",
                "matching:\(matchingEntries.count)",
                "query:\(search.queryFingerprint)",
                "query-snippet:\(search.querySnippet)",
                "no-match:\(noMatchAvailabilityReason ?? "none")",
                "hold-state:\(savedTourHoldStateIdentifier)",
                "hold:\(requestedSavedTourHoldEntryIdentifier ?? "none")",
                "retained-hold:\(retainedSavedTourHoldEntryIdentifier ?? "none")",
                "filtered-hold:\(filteredSavedTourHoldEntryIdentifier ?? "none")",
                "selected:\(selectedEntry?.identifier ?? "none")",
                "ordinal:\(selectedIndex.map { String($0 + 1) } ?? "none")",
                "entries:\(selectionPool.count)",
                "seed:\(boundedRotationSeed(rotationSeed))",
                "pins:\(requestedPinnedEntryIdentifiers.count)",
                "retained-pins:\(retainedPinnedEntryIdentifiers.count)",
                "missing-pins:\(missingPinnedEntryIdentifiers.count)",
                "filtered-pins:\(filteredPinnedEntryIdentifiers.count)",
                "warnings:\(warningStateIdentifier)",
                "warning-count:\(historyPlan.warningCount)"
            ].joined(separator: "|"),
            limit: CinematicRunRecapShareArtifactTourPlan.identifierMaxCharacters
        )

        guard let selectedEntry else {
            return CinematicRunRecapShareArtifactTourPlan(
                identifier: identifier,
                isAvailable: false,
                availabilityReason: availabilityReason,
                stateIdentifier: stateIdentifier,
                selectionSourceIdentifier: selectionSourceIdentifier,
                savedTourHoldStateIdentifier: savedTourHoldStateIdentifier,
                requestedSavedTourHoldEntryIdentifier: requestedSavedTourHoldEntryIdentifier,
                retainedSavedTourHoldEntryIdentifier: retainedSavedTourHoldEntryIdentifier,
                filteredSavedTourHoldEntryIdentifier: filteredSavedTourHoldEntryIdentifier,
                isSearchActive: search.isActive,
                searchQuerySnippet: search.querySnippet,
                searchQueryFingerprint: search.queryFingerprint,
                noMatchAvailabilityReason: noMatchAvailabilityReason,
                retainedEntryCount: retainedEntries.count,
                totalCount: historyPlan.totalCount,
                hiddenCount: historyPlan.hiddenCount,
                matchingEntryCount: matchingEntries.count,
                unfilteredVisibleCount: retainedEntries.count,
                selectedEntryIdentifier: nil,
                selectedOrdinal: nil,
                entryCount: selectionPool.count,
                rotationSeed: boundedRotationSeed(rotationSeed),
                sessionNumber: nil,
                filename: nil,
                titleSnippet: emptyTitle(stateIdentifier: stateIdentifier),
                statusSnippet: bounded(
                    availabilityReason,
                    limit: CinematicRunRecapShareArtifactTourPlan.snippetMaxCharacters
                ),
                commitSnippet: nil,
                bodyPreviewText: emptyBodyPreviewText(
                    stateIdentifier: stateIdentifier,
                    search: search,
                    retainedCount: retainedEntries.count
                ),
                sessionText: "No saved session",
                requestedPinnedEntryIdentifiers: requestedPinnedEntryIdentifiers,
                retainedPinnedEntryIdentifiers: retainedPinnedEntryIdentifiers,
                missingPinnedEntryIdentifiers: missingPinnedEntryIdentifiers,
                filteredPinnedEntryIdentifiers: filteredPinnedEntryIdentifiers,
                pinnedEntryCount: requestedPinnedEntryIdentifiers.count,
                retainedPinnedEntryCount: retainedPinnedEntryIdentifiers.count,
                missingPinnedEntryCount: missingPinnedEntryIdentifiers.count,
                filteredPinnedEntryCount: filteredPinnedEntryIdentifiers.count,
                warningStateIdentifier: warningStateIdentifier,
                warningCount: historyPlan.warningCount,
                hiddenWarningCount: historyPlan.hiddenWarningCount,
                warningIdentifiers: historyPlan.warnings.map(\.identifier),
                hasWarnings: historyPlan.hasWarnings
            )
        }

        return CinematicRunRecapShareArtifactTourPlan(
            identifier: identifier,
            isAvailable: true,
            availabilityReason: availabilityReason,
            stateIdentifier: stateIdentifier,
            selectionSourceIdentifier: selectionSourceIdentifier,
            savedTourHoldStateIdentifier: savedTourHoldStateIdentifier,
            requestedSavedTourHoldEntryIdentifier: requestedSavedTourHoldEntryIdentifier,
            retainedSavedTourHoldEntryIdentifier: retainedSavedTourHoldEntryIdentifier,
            filteredSavedTourHoldEntryIdentifier: filteredSavedTourHoldEntryIdentifier,
            isSearchActive: search.isActive,
            searchQuerySnippet: search.querySnippet,
            searchQueryFingerprint: search.queryFingerprint,
            noMatchAvailabilityReason: noMatchAvailabilityReason,
            retainedEntryCount: retainedEntries.count,
            totalCount: historyPlan.totalCount,
            hiddenCount: historyPlan.hiddenCount,
            matchingEntryCount: matchingEntries.count,
            unfilteredVisibleCount: retainedEntries.count,
            selectedEntryIdentifier: selectedEntry.identifier,
            selectedOrdinal: selectedIndex.map { $0 + 1 },
            entryCount: selectionPool.count,
            rotationSeed: boundedRotationSeed(rotationSeed),
            sessionNumber: selectedEntry.sessionNumber,
            filename: bounded(
                selectedEntry.filename,
                limit: CinematicRunRecapShareArtifactHistoryPlan.filenameMaxCharacters
            ),
            titleSnippet: bounded(
                selectedEntry.titleSnippet,
                limit: CinematicRunRecapShareArtifactTourPlan.snippetMaxCharacters
            ),
            statusSnippet: statusText(
                entry: selectedEntry,
                stateIdentifier: stateIdentifier,
                warningStateIdentifier: warningStateIdentifier
            ),
            commitSnippet: selectedEntry.commitSnippet.map {
                bounded(
                    $0,
                    limit: CinematicRunRecapShareArtifactTourPlan.snippetMaxCharacters
                )
            },
            bodyPreviewText: bodyPreview(from: selectedEntry.markdownContents),
            sessionText: sessionText(
                entry: selectedEntry,
                selectedOrdinal: selectedIndex.map { $0 + 1 },
                entryCount: selectionPool.count,
                selectionSourceIdentifier: selectionSourceIdentifier
            ),
            requestedPinnedEntryIdentifiers: requestedPinnedEntryIdentifiers,
            retainedPinnedEntryIdentifiers: retainedPinnedEntryIdentifiers,
            missingPinnedEntryIdentifiers: missingPinnedEntryIdentifiers,
            filteredPinnedEntryIdentifiers: filteredPinnedEntryIdentifiers,
            pinnedEntryCount: requestedPinnedEntryIdentifiers.count,
            retainedPinnedEntryCount: retainedPinnedEntryIdentifiers.count,
            missingPinnedEntryCount: missingPinnedEntryIdentifiers.count,
            filteredPinnedEntryCount: filteredPinnedEntryIdentifiers.count,
            warningStateIdentifier: warningStateIdentifier,
            warningCount: historyPlan.warningCount,
            hiddenWarningCount: historyPlan.hiddenWarningCount,
            warningIdentifiers: historyPlan.warnings.map(\.identifier),
            hasWarnings: historyPlan.hasWarnings
        )
    }

    private struct SearchState {
        var normalizedQuery: String
        var querySnippet: String
        var queryFingerprint: String
        var isActive: Bool
    }

    private static func searchState(for query: String?) -> SearchState {
        let normalizedQuery = normalizedSearchText(query ?? "")
        let isActive = !normalizedQuery.isEmpty
        return SearchState(
            normalizedQuery: normalizedQuery,
            querySnippet: isActive
                ? bounded(
                    normalizedQuery,
                    limit: CinematicRunRecapShareArtifactTourPlan.searchQuerySnippetMaxCharacters
                )
                : "none",
            queryFingerprint: isActive ? fingerprint(normalizedQuery) : "none",
            isActive: isActive
        )
    }

    private static func matches(
        _ entry: CinematicRunRecapShareArtifactHistoryPlan.Entry,
        normalizedQuery query: String
    ) -> Bool {
        guard !query.isEmpty else { return true }
        let fields = [
            entry.filename,
            entry.titleSnippet,
            entry.statusSnippet,
            entry.commitSnippet ?? "",
            entry.pathDisplayText,
            previewSearchBody(from: entry.markdownContents) ?? ""
        ]
        return fields.contains { normalizedSearchText($0).contains(query) }
    }

    private static func stateIdentifier(
        selectedEntry: CinematicRunRecapShareArtifactHistoryPlan.Entry?,
        selectionSourceIdentifier: String,
        historyPlan: CinematicRunRecapShareArtifactHistoryPlan,
        search: SearchState,
        noMatchAvailabilityReason: String?,
        savedTourHoldStateIdentifier: String,
        requestedPinnedEntryIdentifiers: [String],
        retainedPinnedEntryIdentifiers: [String],
        missingPinnedEntryIdentifiers: [String],
        filteredPinnedEntryIdentifiers: [String]
    ) -> String {
        if savedTourHoldStateIdentifier == "held" {
            return "held"
        }
        if savedTourHoldStateIdentifier == "missing-hold" {
            return "missing-hold"
        }
        if savedTourHoldStateIdentifier == "filtered-hold" {
            return "filtered-hold"
        }
        if selectedEntry == nil {
            if noMatchAvailabilityReason != nil {
                return "no-match"
            }
            if historyPlan.entries.isEmpty {
                return historyPlan.hasWarnings ? "unavailable-warning" : "unavailable"
            }
            if !requestedPinnedEntryIdentifiers.isEmpty,
               missingPinnedEntryIdentifiers.count == requestedPinnedEntryIdentifiers.count {
                return "missing-pin"
            }
            if search.isActive,
               !retainedPinnedEntryIdentifiers.isEmpty,
               filteredPinnedEntryIdentifiers.count == retainedPinnedEntryIdentifiers.count {
                return "filtered-pin"
            }
            return "unavailable"
        }
        if selectionSourceIdentifier == "pinned" {
            return historyPlan.hasWarnings ? "pinned-warning" : "pinned"
        }
        if !requestedPinnedEntryIdentifiers.isEmpty,
           missingPinnedEntryIdentifiers.count == requestedPinnedEntryIdentifiers.count {
            return historyPlan.hasWarnings ? "missing-pin-warning" : "missing-pin"
        }
        if search.isActive,
           !retainedPinnedEntryIdentifiers.isEmpty,
           filteredPinnedEntryIdentifiers.count == retainedPinnedEntryIdentifiers.count {
            return historyPlan.hasWarnings ? "filtered-pin-warning" : "filtered-pin"
        }
        return historyPlan.hasWarnings ? "recent-warning" : "recent"
    }

    private static func savedTourHoldStateIdentifier(
        requestedEntryIdentifier: String?,
        retainedEntryIdentifier: String?,
        filteredEntryIdentifier: String?
    ) -> String {
        guard requestedEntryIdentifier != nil else { return "none" }
        if retainedEntryIdentifier == nil {
            return "missing-hold"
        }
        if filteredEntryIdentifier != nil {
            return "filtered-hold"
        }
        return "held"
    }

    private static func availabilityReason(
        selectedEntry: CinematicRunRecapShareArtifactHistoryPlan.Entry?,
        historyPlan: CinematicRunRecapShareArtifactHistoryPlan,
        noMatchAvailabilityReason: String?,
        stateIdentifier: String
    ) -> String {
        guard selectedEntry == nil else { return "available" }
        if let noMatchAvailabilityReason {
            return noMatchAvailabilityReason
        }
        if historyPlan.entries.isEmpty {
            return historyPlan.availabilityReason
        }
        switch stateIdentifier {
        case "missing-hold":
            return "saved-tour-hold-missing"
        case "filtered-hold":
            return "saved-tour-hold-filtered"
        case "missing-pin":
            return "pinned-recap-share-artifacts-missing"
        case "filtered-pin":
            return "pinned-recap-share-artifacts-filtered"
        default:
            return "no-tour-recap-share-artifact"
        }
    }

    private static func statusText(
        entry: CinematicRunRecapShareArtifactHistoryPlan.Entry,
        stateIdentifier: String,
        warningStateIdentifier: String
    ) -> String {
        let suffix: String
        switch stateIdentifier {
        case "held":
            suffix = "held archive"
        case "missing-hold":
            suffix = "hold missing, fallback archive"
        case "filtered-hold":
            suffix = "hold filtered, search archive"
        case "pinned", "pinned-warning":
            suffix = "pinned archive"
        case "missing-pin", "missing-pin-warning":
            suffix = "pin missing, recent archive"
        case "filtered-pin", "filtered-pin-warning":
            suffix = "pin filtered, search archive"
        default:
            suffix = warningStateIdentifier == "warnings" ? "recent archive warning" : "recent archive"
        }
        return bounded(
            "\(entry.statusSnippet) | \(suffix)",
            limit: CinematicRunRecapShareArtifactTourPlan.snippetMaxCharacters
        )
    }

    private static func sessionText(
        entry: CinematicRunRecapShareArtifactHistoryPlan.Entry,
        selectedOrdinal: Int?,
        entryCount: Int,
        selectionSourceIdentifier: String
    ) -> String {
        let position = selectedOrdinal.map { "\($0)/\(max(entryCount, 1))" } ?? "1/\(max(entryCount, 1))"
        return bounded(
            "S\(entry.sessionNumber) \(selectionSourceIdentifier) \(position)",
            limit: CinematicRunRecapShareArtifactTourPlan.snippetMaxCharacters
        )
    }

    private static func emptyTitle(stateIdentifier: String) -> String {
        switch stateIdentifier {
        case "missing-hold":
            return "Held recap no longer retained"
        case "filtered-hold":
            return "Held recap hidden by search"
        case "no-match":
            return "No matching saved recap"
        case "missing-pin":
            return "Pinned recap no longer retained"
        case "filtered-pin":
            return "Pinned recap hidden by search"
        case "unavailable-warning":
            return "Recap archive warning"
        default:
            return "No saved recap artifact"
        }
    }

    private static func emptyBodyPreviewText(
        stateIdentifier: String,
        search: SearchState,
        retainedCount: Int
    ) -> String {
        let text: String
        switch stateIdentifier {
        case "missing-hold":
            text = "The held recap artifact is no longer retained; \(retainedCount) artifacts remain."
        case "filtered-hold":
            text = "The held recap artifact is hidden by the active archive search."
        case "no-match":
            text = "No retained recap artifacts match \(search.querySnippet)."
        case "missing-pin":
            text = "Pinned recap artifacts are no longer retained; \(retainedCount) artifacts remain."
        case "filtered-pin":
            text = "Pinned recap artifacts are hidden by the active archive search."
        case "unavailable-warning":
            text = "The saved recap archive has warnings and no displayable artifacts."
        default:
            text = "No saved recap artifacts are available for the idle tour."
        }
        return bounded(
            text,
            limit: CinematicRunRecapShareArtifactTourPlan.bodyPreviewMaxCharacters
        )
    }

    private static func rotatedIndex(seed: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let boundedSeed = boundedRotationSeed(seed)
        return boundedSeed % count
    }

    private static func boundedRotationSeed(_ seed: Int) -> Int {
        abs(seed % 10_000)
    }

    private static func bodyPreview(from markdownContents: String) -> String {
        bounded(
            previewSearchBody(from: markdownContents) ?? "No preview text available.",
            limit: CinematicRunRecapShareArtifactTourPlan.bodyPreviewMaxCharacters
        )
    }

    private static func previewSearchBody(from markdownContents: String) -> String? {
        shareTextBody(in: markdownContents)
            ?? fallbackBody(in: markdownContents)
    }

    private static func shareTextBody(in markdownContents: String) -> String? {
        guard let range = markdownContents.range(of: "## Share Text") else {
            return nil
        }

        let text = markdownContents[range.upperBound...]
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { line in
                String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { line in
                !line.isEmpty && !line.hasPrefix("```")
            }
            .joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    private static func fallbackBody(in markdownContents: String) -> String? {
        let text = markdownContents
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { line in
                String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { line in
                !line.isEmpty
                    && !line.hasPrefix("#")
                    && !line.hasPrefix("- ")
                    && !line.hasPrefix("```")
            }
            .joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    private static func boundedIdentifierList(_ identifiers: [String]) -> [String] {
        var seen = Set<String>()
        var boundedIdentifiers: [String] = []

        for identifier in identifiers {
            guard let boundedIdentifier = boundedOptionalIdentifier(identifier),
                  seen.insert(boundedIdentifier).inserted else {
                continue
            }
            boundedIdentifiers.append(boundedIdentifier)
            if boundedIdentifiers.count == CinematicRunRecapShareArtifactTourPlan.pinIdentifierLimit {
                break
            }
        }

        return boundedIdentifiers
    }

    private static func boundedOptionalIdentifier(_ identifier: String?) -> String? {
        let boundedIdentifier = bounded(
            identifier ?? "",
            limit: CinematicRunRecapShareArtifactTourPlan.identifierMaxCharacters
        )
        return boundedIdentifier == "none" ? nil : boundedIdentifier
    }

    private static func normalizedSearchText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func bounded(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "none" }
        guard normalized.count <= limit else {
            let prefixLimit = max(1, limit - 3)
            return normalized.prefix(prefixLimit)
                .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }
        return normalized
    }

    private static func fingerprint(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}

enum CinematicRunRecapShareArtifactPreviewBrowserPlanner {
    static func plan(
        historyPlan: CinematicRunRecapShareArtifactHistoryPlan,
        selectedEntryIdentifier: String? = nil,
        searchQuery: String? = nil
    ) -> CinematicRunRecapShareArtifactPreviewBrowserPlan {
        let unfilteredEntries = historyPlan.entries
        let search = searchState(for: searchQuery)
        let entries = search.isActive
            ? unfilteredEntries.filter { matches($0, normalizedQuery: search.normalizedQuery) }
            : unfilteredEntries
        let selectedPair = selectedEntry(
            in: entries,
            requestedIdentifier: selectedEntryIdentifier
        )
        let selectedIndex = selectedPair?.index
        let selectedEntry = selectedPair?.entry
        let fallback = selectedFallback(
            requestedIdentifier: selectedEntryIdentifier,
            selectedEntry: selectedEntry,
            unfilteredEntries: unfilteredEntries,
            filteredEntries: entries,
            isSearchActive: search.isActive
        )
        let previousEntryIdentifier = selectedIndex.flatMap { index in
            index > entries.startIndex ? entries[index - 1].identifier : nil
        }
        let nextEntryIdentifier = selectedIndex.flatMap { index in
            let nextIndex = index + 1
            return nextIndex < entries.endIndex ? entries[nextIndex].identifier : nil
        }
        let warningStateIdentifier = historyPlan.hasWarnings ? "warnings" : "clear"
        let noMatchAvailabilityReason = search.isActive && !unfilteredEntries.isEmpty && entries.isEmpty
            ? "no-matching-recap-share-artifacts"
            : nil
        let availabilityReason = noMatchAvailabilityReason ?? historyPlan.availabilityReason
        let identifier = bounded(
            [
                "run-recap-share-artifact-preview",
                "availability:\(availabilityReason)",
                "history:\(fingerprint(historyPlan.identifier))",
                "query:\(search.queryFingerprint)",
                "query-snippet:\(search.querySnippet)",
                "search-active:\(search.isActive)",
                "matches:\(entries.count)",
                "unfiltered:\(unfilteredEntries.count)",
                "no-match:\(noMatchAvailabilityReason ?? "none")",
                "selected:\(selectedEntry?.identifier ?? "none")",
                "fallback:\(fallback.entryIdentifier ?? "none")",
                "fallback-reason:\(fallback.reasonIdentifier)",
                "index:\(selectedIndex.map(String.init) ?? "none")",
                "count:\(entries.count)",
                "previous:\(previousEntryIdentifier ?? "none")",
                "next:\(nextEntryIdentifier ?? "none")",
                "warnings:\(warningStateIdentifier)",
                "warning-count:\(historyPlan.warningCount)"
            ].joined(separator: "|"),
            limit: CinematicRunRecapShareArtifactPreviewBrowserPlan.identifierMaxCharacters
        )

        guard let selectedEntry else {
            return CinematicRunRecapShareArtifactPreviewBrowserPlan(
                identifier: identifier,
                isAvailable: false,
                availabilityReason: availabilityReason,
                isSearchActive: search.isActive,
                searchQuerySnippet: search.querySnippet,
                searchQueryFingerprint: search.queryFingerprint,
                matchCount: entries.count,
                unfilteredVisibleCount: unfilteredEntries.count,
                noMatchAvailabilityReason: noMatchAvailabilityReason,
                selectedEntryIdentifier: nil,
                selectedFallbackEntryIdentifier: fallback.entryIdentifier,
                selectedFallbackReasonIdentifier: fallback.reasonIdentifier,
                previousEntryIdentifier: nil,
                nextEntryIdentifier: nil,
                selectedIndex: nil,
                selectedOrdinal: nil,
                entryCount: entries.count,
                sessionNumber: nil,
                filename: nil,
                titleSnippet: "No recap artifact selected",
                statusSnippet: bounded(
                    availabilityReason,
                    limit: CinematicRunRecapShareArtifactPreviewBrowserPlan.snippetMaxCharacters
                ),
                commitSnippet: nil,
                pathSnippet: bounded(
                    historyPlan.sessionsDisplayText,
                    limit: CinematicRunRecapShareArtifactPreviewBrowserPlan.pathSnippetMaxCharacters
                ),
                bodyPreviewText: boundedBodyPreview(
                    emptyBodyPreviewText(
                        isSearchActive: search.isActive,
                        querySnippet: search.querySnippet,
                        noMatchAvailabilityReason: noMatchAvailabilityReason
                    ),
                    limit: CinematicRunRecapShareArtifactPreviewBrowserPlan.bodyPreviewMaxCharacters
                ),
                markdownLength: 0,
                warningStateIdentifier: warningStateIdentifier,
                warningCount: historyPlan.warningCount,
                hasWarnings: historyPlan.hasWarnings
            )
        }

        return CinematicRunRecapShareArtifactPreviewBrowserPlan(
            identifier: identifier,
            isAvailable: true,
            availabilityReason: availabilityReason,
            isSearchActive: search.isActive,
            searchQuerySnippet: search.querySnippet,
            searchQueryFingerprint: search.queryFingerprint,
            matchCount: entries.count,
            unfilteredVisibleCount: unfilteredEntries.count,
            noMatchAvailabilityReason: noMatchAvailabilityReason,
            selectedEntryIdentifier: selectedEntry.identifier,
            selectedFallbackEntryIdentifier: fallback.entryIdentifier,
            selectedFallbackReasonIdentifier: fallback.reasonIdentifier,
            previousEntryIdentifier: previousEntryIdentifier,
            nextEntryIdentifier: nextEntryIdentifier,
            selectedIndex: selectedIndex,
            selectedOrdinal: selectedIndex.map { $0 + 1 },
            entryCount: entries.count,
            sessionNumber: selectedEntry.sessionNumber,
            filename: selectedEntry.filename,
            titleSnippet: bounded(
                selectedEntry.titleSnippet,
                limit: CinematicRunRecapShareArtifactPreviewBrowserPlan.snippetMaxCharacters
            ),
            statusSnippet: bounded(
                selectedEntry.statusSnippet,
                limit: CinematicRunRecapShareArtifactPreviewBrowserPlan.snippetMaxCharacters
            ),
            commitSnippet: selectedEntry.commitSnippet.map {
                bounded(
                    $0,
                    limit: CinematicRunRecapShareArtifactPreviewBrowserPlan.snippetMaxCharacters
                )
            },
            pathSnippet: bounded(
                selectedEntry.pathDisplayText,
                limit: CinematicRunRecapShareArtifactPreviewBrowserPlan.pathSnippetMaxCharacters
            ),
            bodyPreviewText: previewBody(from: selectedEntry.markdownContents),
            markdownLength: selectedEntry.markdownLength,
            warningStateIdentifier: warningStateIdentifier,
            warningCount: historyPlan.warningCount,
            hasWarnings: historyPlan.hasWarnings
        )
    }

    private struct SearchState {
        var normalizedQuery: String
        var querySnippet: String
        var queryFingerprint: String
        var isActive: Bool
    }

    private static func searchState(for query: String?) -> SearchState {
        let normalizedQuery = normalizedSearchText(query ?? "")
        let isActive = !normalizedQuery.isEmpty
        return SearchState(
            normalizedQuery: normalizedQuery,
            querySnippet: isActive
                ? bounded(
                    normalizedQuery,
                    limit: CinematicRunRecapShareArtifactPreviewBrowserPlan.searchQuerySnippetMaxCharacters
                )
                : "none",
            queryFingerprint: isActive ? fingerprint(normalizedQuery) : "none",
            isActive: isActive
        )
    }

    private static func matches(
        _ entry: CinematicRunRecapShareArtifactHistoryPlan.Entry,
        normalizedQuery query: String
    ) -> Bool {
        guard !query.isEmpty else { return true }
        let fields = [
            entry.filename,
            entry.titleSnippet,
            entry.statusSnippet,
            entry.commitSnippet ?? "",
            entry.pathDisplayText,
            previewSearchBody(from: entry.markdownContents) ?? ""
        ]
        return fields.contains { normalizedSearchText($0).contains(query) }
    }

    private static func selectedFallback(
        requestedIdentifier: String?,
        selectedEntry: CinematicRunRecapShareArtifactHistoryPlan.Entry?,
        unfilteredEntries: [CinematicRunRecapShareArtifactHistoryPlan.Entry],
        filteredEntries: [CinematicRunRecapShareArtifactHistoryPlan.Entry],
        isSearchActive: Bool
    ) -> (entryIdentifier: String?, reasonIdentifier: String) {
        guard let requestedIdentifier else {
            return (nil, "none")
        }
        if selectedEntry?.identifier == requestedIdentifier {
            return (nil, "none")
        }
        guard let selectedEntry else {
            let searchFilteredAllEntries = isSearchActive && !unfilteredEntries.isEmpty && filteredEntries.isEmpty
            return (nil, searchFilteredAllEntries ? "no-match" : "missing-selection")
        }
        let requestedStillRetained = unfilteredEntries.contains { $0.identifier == requestedIdentifier }
        return (
            selectedEntry.identifier,
            requestedStillRetained ? "filtered-selection" : "missing-selection"
        )
    }

    private static func selectedEntry(
        in entries: [CinematicRunRecapShareArtifactHistoryPlan.Entry],
        requestedIdentifier: String?
    ) -> (index: Int, entry: CinematicRunRecapShareArtifactHistoryPlan.Entry)? {
        if let requestedIdentifier,
           let index = entries.firstIndex(where: { $0.identifier == requestedIdentifier }) {
            return (index, entries[index])
        }
        guard let first = entries.first else { return nil }
        return (entries.startIndex, first)
    }

    private static func previewBody(from markdownContents: String) -> String {
        boundedBodyPreview(
            previewSearchBody(from: markdownContents)
                ?? "No preview text available.",
            limit: CinematicRunRecapShareArtifactPreviewBrowserPlan.bodyPreviewMaxCharacters
        )
    }

    private static func previewSearchBody(from markdownContents: String) -> String? {
        shareTextBody(in: markdownContents)
            ?? fallbackBody(in: markdownContents)
    }

    private static func emptyBodyPreviewText(
        isSearchActive: Bool,
        querySnippet: String,
        noMatchAvailabilityReason: String?
    ) -> String {
        if isSearchActive, noMatchAvailabilityReason != nil {
            return "No saved recap share artifacts match \(querySnippet)."
        }
        return "No saved recap share artifacts are available for preview."
    }

    private static func shareTextBody(in markdownContents: String) -> String? {
        guard let range = markdownContents.range(of: "## Share Text") else {
            return nil
        }

        let text = markdownContents[range.upperBound...]
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { line in
                String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { line in
                !line.isEmpty && !line.hasPrefix("```")
            }
            .joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    private static func fallbackBody(in markdownContents: String) -> String? {
        let text = markdownContents
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { line in
                String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { line in
                !line.isEmpty
                    && !line.hasPrefix("#")
                    && !line.hasPrefix("- ")
                    && !line.hasPrefix("```")
            }
            .joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    private static func bounded(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "none" }
        guard normalized.count <= limit else {
            let prefixLimit = max(1, limit - 3)
            return normalized.prefix(prefixLimit)
                .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }
        return normalized
    }

    private static func boundedBodyPreview(_ text: String, limit: Int) -> String {
        bounded(text, limit: limit)
    }

    private static func normalizedSearchText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func fingerprint(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}

enum CinematicRunRecapShareArtifactSubsetExportPlanner {
    typealias Scope = CinematicRunRecapShareArtifactSubsetExportPlan.Scope

    static func plan(
        historyPlan: CinematicRunRecapShareArtifactHistoryPlan,
        selectedEntryIdentifier: String? = nil,
        searchQuery: String? = nil,
        scope: Scope
    ) -> CinematicRunRecapShareArtifactSubsetExportPlan {
        let previewPlan = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: historyPlan,
            selectedEntryIdentifier: selectedEntryIdentifier,
            searchQuery: searchQuery
        )
        let search = searchState(for: searchQuery)
        let retainedEntries = historyPlan.entries
        let filteredEntries = search.isActive
            ? retainedEntries.filter { matches($0, normalizedQuery: search.normalizedQuery) }
            : retainedEntries
        let selectedEntry = previewPlan.selectedEntryIdentifier.flatMap { identifier in
            retainedEntries.first { $0.identifier == identifier }
        }
        let exportEntries: [CinematicRunRecapShareArtifactHistoryPlan.Entry]
        switch scope {
        case .selected:
            exportEntries = selectedEntry.map { [$0] } ?? []
        case .filtered:
            exportEntries = filteredEntries
        }

        let selectedCount = selectedEntry == nil ? 0 : 1
        let filteredCount = filteredEntries.count
        let noMatchAvailabilityReason = search.isActive && !retainedEntries.isEmpty && filteredEntries.isEmpty
            ? "no-matching-recap-share-artifacts"
            : nil
        let availabilityReason = availabilityReason(
            scope: scope,
            exportEntries: exportEntries,
            historyPlan: historyPlan,
            previewPlan: previewPlan,
            noMatchAvailabilityReason: noMatchAvailabilityReason
        )
        let warningStateIdentifier = historyPlan.hasWarnings ? "warnings" : "clear"
        let exportedEntryIdentifiers = exportEntries.map(\.identifier)
        let exportIdentifier = bounded(
            [
                "run-recap-share-artifact-subset-export",
                "scope:\(scope.rawValue)",
                "availability:\(availabilityReason)",
                "retention:\(historyPlan.retentionLimit)",
                "retained:\(retainedEntries.count)",
                "total:\(historyPlan.totalCount)",
                "hidden:\(historyPlan.hiddenCount)",
                "selected:\(selectedCount)",
                "filtered:\(filteredCount)",
                "exported:\(exportEntries.count)",
                "query:\(search.queryFingerprint)",
                "query-snippet:\(search.querySnippet)",
                "no-match:\(noMatchAvailabilityReason ?? "none")",
                "selection:\(selectedEntry?.identifier ?? "none")",
                "fallback:\(previewPlan.selectedFallbackEntryIdentifier ?? "none")",
                "fallback-reason:\(previewPlan.selectedFallbackReasonIdentifier)",
                "warnings:\(warningStateIdentifier)",
                "warning-count:\(historyPlan.warningCount)",
                "content:\(fingerprint(exportedEntryIdentifiers.joined(separator: "|")))"
            ].joined(separator: "|"),
            limit: CinematicRunRecapShareArtifactSubsetExportPlan.identifierMaxCharacters
        )
        let markdown = markdownExport(
            exportIdentifier: exportIdentifier,
            scope: scope,
            availabilityReason: availabilityReason,
            entries: exportEntries,
            historyPlan: historyPlan,
            search: search,
            noMatchAvailabilityReason: noMatchAvailabilityReason,
            selectedEntry: selectedEntry,
            previewPlan: previewPlan,
            selectedCount: selectedCount,
            filteredCount: filteredCount,
            warningStateIdentifier: warningStateIdentifier
        )
        let identifier = bounded(
            [
                "run-recap-share-artifact-subset",
                "scope:\(scope.rawValue)",
                "availability:\(availabilityReason)",
                "export:\(fingerprint(exportIdentifier))",
                "entries:\(exportEntries.count)",
                "markdown:\(markdown.count)",
                "query:\(search.queryFingerprint)",
                "warnings:\(warningStateIdentifier)"
            ].joined(separator: "|"),
            limit: CinematicRunRecapShareArtifactSubsetExportPlan.identifierMaxCharacters
        )

        return CinematicRunRecapShareArtifactSubsetExportPlan(
            identifier: identifier,
            exportIdentifier: exportIdentifier,
            scope: scope,
            isAvailable: !exportEntries.isEmpty,
            availabilityReason: availabilityReason,
            isSearchActive: search.isActive,
            searchQuerySnippet: search.querySnippet,
            searchQueryFingerprint: search.queryFingerprint,
            noMatchAvailabilityReason: noMatchAvailabilityReason,
            retainedEntryCount: retainedEntries.count,
            totalCount: historyPlan.totalCount,
            hiddenCount: historyPlan.hiddenCount,
            selectedCount: selectedCount,
            filteredCount: filteredCount,
            exportEntryCount: exportEntries.count,
            unfilteredVisibleCount: retainedEntries.count,
            selectedEntryIdentifier: selectedEntry?.identifier,
            selectedFallbackEntryIdentifier: previewPlan.selectedFallbackEntryIdentifier,
            selectedFallbackReasonIdentifier: previewPlan.selectedFallbackReasonIdentifier,
            exportedEntryIdentifiers: exportedEntryIdentifiers,
            warningStateIdentifier: warningStateIdentifier,
            warningCount: historyPlan.warningCount,
            hiddenWarningCount: historyPlan.hiddenWarningCount,
            warningIdentifiers: historyPlan.warnings.map(\.identifier),
            hasWarnings: historyPlan.hasWarnings,
            markdownContents: markdown,
            copyLabel: copyLabel(scope: scope, isAvailable: !exportEntries.isEmpty),
            copyHelp: copyHelp(
                scope: scope,
                isAvailable: !exportEntries.isEmpty,
                availabilityReason: availabilityReason,
                exportEntryCount: exportEntries.count,
                filteredCount: filteredCount,
                retainedCount: retainedEntries.count,
                search: search,
                exportIdentifier: exportIdentifier
            )
        )
    }

    private struct SearchState {
        var normalizedQuery: String
        var querySnippet: String
        var queryFingerprint: String
        var isActive: Bool
    }

    private static func searchState(for query: String?) -> SearchState {
        let normalizedQuery = normalizedSearchText(query ?? "")
        let isActive = !normalizedQuery.isEmpty
        return SearchState(
            normalizedQuery: normalizedQuery,
            querySnippet: isActive
                ? bounded(
                    normalizedQuery,
                    limit: CinematicRunRecapShareArtifactSubsetExportPlan.searchQuerySnippetMaxCharacters
                )
                : "none",
            queryFingerprint: isActive ? fingerprint(normalizedQuery) : "none",
            isActive: isActive
        )
    }

    private static func matches(
        _ entry: CinematicRunRecapShareArtifactHistoryPlan.Entry,
        normalizedQuery query: String
    ) -> Bool {
        guard !query.isEmpty else { return true }
        let fields = [
            entry.filename,
            entry.titleSnippet,
            entry.statusSnippet,
            entry.commitSnippet ?? "",
            entry.pathDisplayText,
            previewSearchBody(from: entry.markdownContents) ?? ""
        ]
        return fields.contains { normalizedSearchText($0).contains(query) }
    }

    private static func availabilityReason(
        scope: Scope,
        exportEntries: [CinematicRunRecapShareArtifactHistoryPlan.Entry],
        historyPlan: CinematicRunRecapShareArtifactHistoryPlan,
        previewPlan: CinematicRunRecapShareArtifactPreviewBrowserPlan,
        noMatchAvailabilityReason: String?
    ) -> String {
        guard exportEntries.isEmpty else { return "available" }
        if let noMatchAvailabilityReason {
            return noMatchAvailabilityReason
        }
        if historyPlan.entries.isEmpty {
            return historyPlan.availabilityReason
        }

        switch scope {
        case .selected:
            return previewPlan.availabilityReason == "available"
                ? "no-selected-recap-share-artifact"
                : previewPlan.availabilityReason
        case .filtered:
            return "no-filtered-recap-share-artifacts"
        }
    }

    private static func markdownExport(
        exportIdentifier: String,
        scope: Scope,
        availabilityReason: String,
        entries: [CinematicRunRecapShareArtifactHistoryPlan.Entry],
        historyPlan: CinematicRunRecapShareArtifactHistoryPlan,
        search: SearchState,
        noMatchAvailabilityReason: String?,
        selectedEntry: CinematicRunRecapShareArtifactHistoryPlan.Entry?,
        previewPlan: CinematicRunRecapShareArtifactPreviewBrowserPlan,
        selectedCount: Int,
        filteredCount: Int,
        warningStateIdentifier: String
    ) -> String {
        var lines = [
            "# Compass Recap Share Artifact Subset",
            "",
            "- Export: \(exportIdentifier)",
            "- Scope: \(scope.rawValue)",
            "- Availability: \(entries.isEmpty ? "unavailable (\(availabilityReason))" : "available")",
            "- Retention limit: \(historyPlan.retentionLimit)",
            "- Total artifacts: \(historyPlan.totalCount)",
            "- Hidden artifacts: \(historyPlan.hiddenCount)",
            "- Retained artifacts: \(historyPlan.entries.count)",
            "- Selected artifacts: \(selectedCount)",
            "- Filtered artifacts: \(filteredCount)",
            "- Exported artifacts: \(entries.count)",
            "- Search active: \(search.isActive)",
            "- Search query: \(search.querySnippet)",
            "- Search fingerprint: \(search.queryFingerprint)",
            "- No-match reason: \(noMatchAvailabilityReason ?? "none")",
            "- Selected entry: \(selectedEntry?.identifier ?? "none")",
            "- Selection fallback: \(previewPlan.selectedFallbackEntryIdentifier ?? "none")",
            "- Selection fallback reason: \(previewPlan.selectedFallbackReasonIdentifier)",
            "- Cleanup candidates: \(historyPlan.cleanupCandidateCount)",
            "- Cleanup candidate identifiers: \(historyPlan.cleanupCandidateIdentifiers.isEmpty ? "none" : historyPlan.cleanupCandidateIdentifiers.joined(separator: ", "))",
            "- Warning state: \(warningStateIdentifier)",
            "- Warnings: \(historyPlan.warningCount)",
            "- Hidden warnings: \(historyPlan.hiddenWarningCount)",
            "- Warning identifiers: \(historyPlan.warnings.isEmpty ? "none" : historyPlan.warnings.map(\.identifier).joined(separator: ", "))"
        ]

        if !historyPlan.warnings.isEmpty {
            lines.append("")
            lines.append("## Warnings")
            lines.append(contentsOf: historyPlan.warnings.map { warning in
                "- \(warning.identifier): \(warning.fileDisplayText) - \(warning.message)"
            })
        }

        if entries.isEmpty {
            lines.append("")
            lines.append("No retained recap share artifacts were available for \(scope.rawValue) export.")
        } else {
            for entry in entries {
                lines.append("")
                lines.append("## Session \(entry.sessionNumber) - \(entry.filename)")
                lines.append("")
                lines.append("- Artifact: \(entry.identifier)")
                lines.append("- Path: \(entry.pathDisplayText)")
                lines.append("- Title: \(entry.titleSnippet)")
                lines.append("- Status: \(entry.statusSnippet)")
                lines.append("- Commit: \(entry.commitSnippet ?? "none")")
                lines.append("")
                lines.append(entry.markdownContents)
            }
        }

        return boundedArtifactText(
            lines.joined(separator: "\n"),
            limit: CinematicRunRecapShareArtifactSubsetExportPlan.markdownMaxCharacters
        )
    }

    private static func copyLabel(scope: Scope, isAvailable: Bool) -> String {
        let text: String
        switch (scope, isAvailable) {
        case (.selected, true):
            text = "Copy selected export"
        case (.selected, false):
            text = "Selected export unavailable"
        case (.filtered, true):
            text = "Copy filtered export"
        case (.filtered, false):
            text = "Filtered export unavailable"
        }
        return bounded(
            text,
            limit: CinematicRunRecapShareArtifactSubsetExportPlan.labelMaxCharacters
        )
    }

    private static func copyHelp(
        scope: Scope,
        isAvailable: Bool,
        availabilityReason: String,
        exportEntryCount: Int,
        filteredCount: Int,
        retainedCount: Int,
        search: SearchState,
        exportIdentifier: String
    ) -> String {
        if !isAvailable {
            return bounded(
                "No \(scope.rawValue) recap share artifact export is available: \(availabilityReason).",
                limit: CinematicRunRecapShareArtifactSubsetExportPlan.helpMaxCharacters
            )
        }

        let searchDetail = search.isActive
            ? " matching \(search.querySnippet)"
            : ""
        let filteredDetail = scope == .filtered
            ? " (\(filteredCount)/\(retainedCount) retained\(searchDetail))"
            : ""
        return bounded(
            "Copy \(exportEntryCount) retained recap share artifact\(exportEntryCount == 1 ? "" : "s")\(filteredDetail) from \(scope.rawValue) export \(exportIdentifier).",
            limit: CinematicRunRecapShareArtifactSubsetExportPlan.helpMaxCharacters
        )
    }

    private static func previewSearchBody(from markdownContents: String) -> String? {
        shareTextBody(in: markdownContents)
            ?? fallbackBody(in: markdownContents)
    }

    private static func shareTextBody(in markdownContents: String) -> String? {
        guard let range = markdownContents.range(of: "## Share Text") else {
            return nil
        }

        let text = markdownContents[range.upperBound...]
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { line in
                String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { line in
                !line.isEmpty && !line.hasPrefix("```")
            }
            .joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    private static func fallbackBody(in markdownContents: String) -> String? {
        let text = markdownContents
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { line in
                String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { line in
                !line.isEmpty
                    && !line.hasPrefix("#")
                    && !line.hasPrefix("- ")
                    && !line.hasPrefix("```")
            }
            .joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    private static func normalizedSearchText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func bounded(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "none" }
        guard normalized.count <= limit else {
            let prefixLimit = max(1, limit - 3)
            return normalized.prefix(prefixLimit)
                .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }
        return normalized
    }

    private static func boundedArtifactText(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = text
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "none" }
        guard normalized.count <= limit else {
            let prefixLimit = max(1, limit - 3)
            return normalized.prefix(prefixLimit)
                .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }
        return normalized
    }

    private static func fingerprint(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}

enum CinematicRunRecapShareArtifactRollupPlanner {
    static func plan(
        historyPlan: CinematicRunRecapShareArtifactHistoryPlan,
        selectedEntryIdentifier: String? = nil,
        searchQuery: String? = nil
    ) -> CinematicRunRecapShareArtifactRollupPlan {
        let previewPlan = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: historyPlan,
            selectedEntryIdentifier: selectedEntryIdentifier,
            searchQuery: searchQuery
        )
        let search = searchState(for: searchQuery)
        let retainedEntries = historyPlan.entries
        let matchingEntries = search.isActive
            ? retainedEntries.filter { matches($0, normalizedQuery: search.normalizedQuery) }
            : retainedEntries
        let noMatchAvailabilityReason = search.isActive && !retainedEntries.isEmpty && matchingEntries.isEmpty
            ? "no-matching-recap-share-artifacts"
            : nil
        let availabilityReason = noMatchAvailabilityReason
            ?? (matchingEntries.isEmpty ? historyPlan.availabilityReason : "available")
        let isAvailable = !matchingEntries.isEmpty
        let warningStateIdentifier = historyPlan.hasWarnings ? "warnings" : "clear"
        let newestEntry = matchingEntries.first
        let oldestEntry = matchingEntries.last
        let sessionRangeLabel = sessionRangeLabel(entries: matchingEntries)
        let statusBuckets = statusBuckets(for: matchingEntries)
        let statusBucketSummary = bucketSummary(statusBuckets)
        let exportIdentifier = bounded(
            [
                "run-recap-share-artifact-rollup-export",
                "availability:\(availabilityReason)",
                "retained:\(retainedEntries.count)",
                "total:\(historyPlan.totalCount)",
                "hidden:\(historyPlan.hiddenCount)",
                "matching:\(matchingEntries.count)",
                "query:\(search.queryFingerprint)",
                "query-snippet:\(search.querySnippet)",
                "no-match:\(noMatchAvailabilityReason ?? "none")",
                "selected:\(previewPlan.selectedEntryIdentifier ?? "none")",
                "fallback:\(previewPlan.selectedFallbackEntryIdentifier ?? "none")",
                "fallback-reason:\(previewPlan.selectedFallbackReasonIdentifier)",
                "range:\(sessionRangeLabel)",
                "buckets:\(statusBucketSummary)",
                "cleanup:\(historyPlan.cleanupCandidateCount)",
                "warnings:\(warningStateIdentifier)",
                "warning-count:\(historyPlan.warningCount)",
                "content:\(fingerprint(matchingEntries.map(\.identifier).joined(separator: "|")))"
            ].joined(separator: "|"),
            limit: CinematicRunRecapShareArtifactRollupPlan.identifierMaxCharacters
        )
        let insight = insightText(
            isAvailable: isAvailable,
            availabilityReason: availabilityReason,
            retainedCount: retainedEntries.count,
            matchingCount: matchingEntries.count,
            totalCount: historyPlan.totalCount,
            hiddenCount: historyPlan.hiddenCount,
            sessionRangeLabel: sessionRangeLabel,
            statusBucketSummary: statusBucketSummary,
            cleanupCandidateCount: historyPlan.cleanupCandidateCount,
            warningCount: historyPlan.warningCount,
            search: search
        )
        let export = exportText(
            exportIdentifier: exportIdentifier,
            isAvailable: isAvailable,
            availabilityReason: availabilityReason,
            retainedEntries: retainedEntries,
            matchingEntries: matchingEntries,
            historyPlan: historyPlan,
            search: search,
            noMatchAvailabilityReason: noMatchAvailabilityReason,
            previewPlan: previewPlan,
            sessionRangeLabel: sessionRangeLabel,
            statusBuckets: statusBuckets,
            statusBucketSummary: statusBucketSummary,
            insightText: insight,
            warningStateIdentifier: warningStateIdentifier
        )
        let identifier = bounded(
            [
                "run-recap-share-artifact-rollup",
                "availability:\(availabilityReason)",
                "export:\(fingerprint(exportIdentifier))",
                "retained:\(retainedEntries.count)",
                "matching:\(matchingEntries.count)",
                "query:\(search.queryFingerprint)",
                "range:\(sessionRangeLabel)",
                "buckets:\(statusBucketSummary)",
                "cleanup:\(historyPlan.cleanupCandidateCount)",
                "warnings:\(warningStateIdentifier)",
                "copy:\(export.count)"
            ].joined(separator: "|"),
            limit: CinematicRunRecapShareArtifactRollupPlan.identifierMaxCharacters
        )

        return CinematicRunRecapShareArtifactRollupPlan(
            identifier: identifier,
            exportIdentifier: exportIdentifier,
            isAvailable: isAvailable,
            availabilityReason: availabilityReason,
            isSearchActive: search.isActive,
            searchQuerySnippet: search.querySnippet,
            searchQueryFingerprint: search.queryFingerprint,
            noMatchAvailabilityReason: noMatchAvailabilityReason,
            retainedEntryCount: retainedEntries.count,
            totalCount: historyPlan.totalCount,
            hiddenCount: historyPlan.hiddenCount,
            matchingEntryCount: matchingEntries.count,
            unfilteredVisibleCount: retainedEntries.count,
            selectedEntryIdentifier: previewPlan.selectedEntryIdentifier,
            selectedFallbackEntryIdentifier: previewPlan.selectedFallbackEntryIdentifier,
            selectedFallbackReasonIdentifier: previewPlan.selectedFallbackReasonIdentifier,
            sessionRangeLabel: sessionRangeLabel,
            newestEntryIdentifier: newestEntry?.identifier,
            newestSessionNumber: newestEntry?.sessionNumber,
            newestFilename: newestEntry?.filename,
            oldestEntryIdentifier: oldestEntry?.identifier,
            oldestSessionNumber: oldestEntry?.sessionNumber,
            oldestFilename: oldestEntry?.filename,
            statusBuckets: statusBuckets,
            statusBucketSummary: statusBucketSummary,
            cleanupCandidateCount: historyPlan.cleanupCandidateCount,
            hiddenCleanupCandidateCount: historyPlan.hiddenCleanupCandidateCount,
            cleanupCandidateIdentifiers: historyPlan.cleanupCandidateIdentifiers,
            warningStateIdentifier: warningStateIdentifier,
            warningCount: historyPlan.warningCount,
            hiddenWarningCount: historyPlan.hiddenWarningCount,
            warningIdentifiers: historyPlan.warnings.map(\.identifier),
            hasWarnings: historyPlan.hasWarnings,
            insightText: insight,
            exportText: export,
            copyLabel: copyLabel(isAvailable: isAvailable),
            copyHelp: copyHelp(
                isAvailable: isAvailable,
                availabilityReason: availabilityReason,
                matchingCount: matchingEntries.count,
                retainedCount: retainedEntries.count,
                search: search,
                exportIdentifier: exportIdentifier
            )
        )
    }

    private struct SearchState {
        var normalizedQuery: String
        var querySnippet: String
        var queryFingerprint: String
        var isActive: Bool
    }

    private struct BucketDefinition {
        var identifier: String
        var label: String
    }

    private static let bucketDefinitions = [
        BucketDefinition(identifier: "succeeded", label: "Succeeded"),
        BucketDefinition(identifier: "failed", label: "Failed"),
        BucketDefinition(identifier: "cancelled", label: "Cancelled"),
        BucketDefinition(identifier: "skipped", label: "Skipped"),
        BucketDefinition(identifier: "warning", label: "Warning"),
        BucketDefinition(identifier: "other", label: "Other")
    ]

    private static func searchState(for query: String?) -> SearchState {
        let normalizedQuery = normalizedSearchText(query ?? "")
        let isActive = !normalizedQuery.isEmpty
        return SearchState(
            normalizedQuery: normalizedQuery,
            querySnippet: isActive
                ? bounded(
                    normalizedQuery,
                    limit: CinematicRunRecapShareArtifactRollupPlan.searchQuerySnippetMaxCharacters
                )
                : "none",
            queryFingerprint: isActive ? fingerprint(normalizedQuery) : "none",
            isActive: isActive
        )
    }

    private static func matches(
        _ entry: CinematicRunRecapShareArtifactHistoryPlan.Entry,
        normalizedQuery query: String
    ) -> Bool {
        guard !query.isEmpty else { return true }
        let fields = [
            entry.filename,
            entry.titleSnippet,
            entry.statusSnippet,
            entry.commitSnippet ?? "",
            entry.pathDisplayText,
            previewSearchBody(from: entry.markdownContents) ?? ""
        ]
        return fields.contains { normalizedSearchText($0).contains(query) }
    }

    private static func statusBuckets(
        for entries: [CinematicRunRecapShareArtifactHistoryPlan.Entry]
    ) -> [CinematicRunRecapShareArtifactRollupPlan.StatusBucket] {
        let counts = Dictionary(grouping: entries, by: { bucketIdentifier(for: $0.statusSnippet) })
            .mapValues(\.count)
        return bucketDefinitions.map { definition in
            CinematicRunRecapShareArtifactRollupPlan.StatusBucket(
                identifier: definition.identifier,
                label: definition.label,
                count: counts[definition.identifier, default: 0]
            )
        }
    }

    private static func bucketIdentifier(for status: String) -> String {
        let normalized = normalizedSearchText(status)
        if normalized.contains("fail")
            || normalized.contains("error")
            || normalized.contains("crash")
            || normalized.contains("broken") {
            return "failed"
        }
        if normalized.contains("cancel")
            || normalized.contains("canceled")
            || normalized.contains("reject") {
            return "cancelled"
        }
        if normalized.contains("skip") {
            return "skipped"
        }
        if normalized.contains("warn")
            || normalized.contains("retry")
            || normalized.contains("dirty")
            || normalized.contains("conflict") {
            return "warning"
        }
        if normalized.contains("success")
            || normalized.contains("succeed")
            || normalized.contains("passed")
            || normalized.contains("pass")
            || normalized.contains("done")
            || normalized.contains("clean") {
            return "succeeded"
        }
        return "other"
    }

    private static func bucketSummary(
        _ buckets: [CinematicRunRecapShareArtifactRollupPlan.StatusBucket]
    ) -> String {
        let summary = buckets
            .filter { $0.count > 0 }
            .map { "\($0.identifier) \($0.count)" }
            .joined(separator: ", ")
        return bounded(
            summary.isEmpty ? "none" : summary,
            limit: CinematicRunRecapShareArtifactRollupPlan.statusBucketSummaryMaxCharacters
        )
    }

    private static func sessionRangeLabel(
        entries: [CinematicRunRecapShareArtifactHistoryPlan.Entry]
    ) -> String {
        guard let newest = entries.first?.sessionNumber,
              let oldest = entries.last?.sessionNumber else {
            return "none"
        }
        if newest == oldest {
            return "S\(newest)"
        }
        return "S\(oldest)-S\(newest)"
    }

    private static func insightText(
        isAvailable: Bool,
        availabilityReason: String,
        retainedCount: Int,
        matchingCount: Int,
        totalCount: Int,
        hiddenCount: Int,
        sessionRangeLabel: String,
        statusBucketSummary: String,
        cleanupCandidateCount: Int,
        warningCount: Int,
        search: SearchState
    ) -> String {
        guard isAvailable else {
            let searchDetail = search.isActive ? " for \(search.querySnippet)" : ""
            return bounded(
                "No recap artifact rollup\(searchDetail): \(availabilityReason). \(retainedCount)/\(totalCount) retained.",
                limit: CinematicRunRecapShareArtifactRollupPlan.insightTextMaxCharacters
            )
        }

        var parts = [
            "\(matchingCount)/\(retainedCount) retained",
            "sessions \(sessionRangeLabel)",
            statusBucketSummary
        ]
        if search.isActive {
            parts.append("search \(search.querySnippet)")
        }
        if hiddenCount > 0 {
            parts.append("+\(hiddenCount) hidden")
        }
        if cleanupCandidateCount > 0 {
            parts.append("\(cleanupCandidateCount) cleanup")
        }
        if warningCount > 0 {
            parts.append("\(warningCount) warning")
        }
        return bounded(
            parts.joined(separator: " | "),
            limit: CinematicRunRecapShareArtifactRollupPlan.insightTextMaxCharacters
        )
    }

    private static func exportText(
        exportIdentifier: String,
        isAvailable: Bool,
        availabilityReason: String,
        retainedEntries: [CinematicRunRecapShareArtifactHistoryPlan.Entry],
        matchingEntries: [CinematicRunRecapShareArtifactHistoryPlan.Entry],
        historyPlan: CinematicRunRecapShareArtifactHistoryPlan,
        search: SearchState,
        noMatchAvailabilityReason: String?,
        previewPlan: CinematicRunRecapShareArtifactPreviewBrowserPlan,
        sessionRangeLabel: String,
        statusBuckets: [CinematicRunRecapShareArtifactRollupPlan.StatusBucket],
        statusBucketSummary: String,
        insightText: String,
        warningStateIdentifier: String
    ) -> String {
        var lines = [
            "# Compass Recap Artifact Rollup",
            "",
            "- Export: \(exportIdentifier)",
            "- Availability: \(isAvailable ? "available" : "unavailable (\(availabilityReason))")",
            "- Retention limit: \(historyPlan.retentionLimit)",
            "- Total artifacts: \(historyPlan.totalCount)",
            "- Retained artifacts: \(retainedEntries.count)",
            "- Matching artifacts: \(matchingEntries.count)",
            "- Hidden artifacts: \(historyPlan.hiddenCount)",
            "- Session range: \(sessionRangeLabel)",
            "- Search active: \(search.isActive)",
            "- Search query: \(search.querySnippet)",
            "- Search fingerprint: \(search.queryFingerprint)",
            "- No-match reason: \(noMatchAvailabilityReason ?? "none")",
            "- Selected entry: \(previewPlan.selectedEntryIdentifier ?? "none")",
            "- Selection fallback: \(previewPlan.selectedFallbackEntryIdentifier ?? "none")",
            "- Selection fallback reason: \(previewPlan.selectedFallbackReasonIdentifier)",
            "- Status buckets: \(statusBucketSummary)",
            "- Cleanup candidates: \(historyPlan.cleanupCandidateCount)",
            "- Hidden cleanup candidates: \(historyPlan.hiddenCleanupCandidateCount)",
            "- Cleanup candidate identifiers: \(historyPlan.cleanupCandidateIdentifiers.isEmpty ? "none" : historyPlan.cleanupCandidateIdentifiers.joined(separator: ", "))",
            "- Warning state: \(warningStateIdentifier)",
            "- Warnings: \(historyPlan.warningCount)",
            "- Hidden warnings: \(historyPlan.hiddenWarningCount)",
            "- Warning identifiers: \(historyPlan.warnings.isEmpty ? "none" : historyPlan.warnings.map(\.identifier).joined(separator: ", "))",
            "",
            "## Insight",
            insightText,
            "",
            "## Status Buckets"
        ]

        lines.append(contentsOf: statusBuckets.map { "- \($0.identifier): \($0.count)" })

        if !historyPlan.warnings.isEmpty {
            lines.append("")
            lines.append("## Warnings")
            lines.append(contentsOf: historyPlan.warnings.map { warning in
                "- \(warning.identifier): \(warning.fileDisplayText) - \(warning.message)"
            })
        }

        lines.append("")
        lines.append("## Matching Entries")
        if matchingEntries.isEmpty {
            lines.append("No retained recap share artifacts matched the current rollup context.")
        } else {
            lines.append(contentsOf: matchingEntries.map { entry in
                [
                    "- S\(entry.sessionNumber) \(entry.filename)",
                    "title \(entry.titleSnippet)",
                    "status \(entry.statusSnippet)",
                    "commit \(entry.commitSnippet ?? "none")",
                    "artifact \(entry.identifier)"
                ].joined(separator: " | ")
            })
        }

        return boundedArtifactText(
            lines.joined(separator: "\n"),
            limit: CinematicRunRecapShareArtifactRollupPlan.exportTextMaxCharacters
        )
    }

    private static func copyLabel(isAvailable: Bool) -> String {
        bounded(
            isAvailable ? "Copy artifact rollup" : "Rollup unavailable",
            limit: CinematicRunRecapShareArtifactRollupPlan.copyLabelMaxCharacters
        )
    }

    private static func copyHelp(
        isAvailable: Bool,
        availabilityReason: String,
        matchingCount: Int,
        retainedCount: Int,
        search: SearchState,
        exportIdentifier: String
    ) -> String {
        if !isAvailable {
            return bounded(
                "No recap artifact rollup is available: \(availabilityReason).",
                limit: CinematicRunRecapShareArtifactRollupPlan.copyHelpMaxCharacters
            )
        }

        let searchDetail = search.isActive ? " matching \(search.querySnippet)" : ""
        return bounded(
            "Copy recap artifact rollup \(exportIdentifier) for \(matchingCount) of \(retainedCount) retained artifact\(retainedCount == 1 ? "" : "s")\(searchDetail).",
            limit: CinematicRunRecapShareArtifactRollupPlan.copyHelpMaxCharacters
        )
    }

    private static func previewSearchBody(from markdownContents: String) -> String? {
        shareTextBody(in: markdownContents)
            ?? fallbackBody(in: markdownContents)
    }

    private static func shareTextBody(in markdownContents: String) -> String? {
        guard let range = markdownContents.range(of: "## Share Text") else {
            return nil
        }

        let text = markdownContents[range.upperBound...]
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { line in
                String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { line in
                !line.isEmpty && !line.hasPrefix("```")
            }
            .joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    private static func fallbackBody(in markdownContents: String) -> String? {
        let text = markdownContents
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { line in
                String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { line in
                !line.isEmpty
                    && !line.hasPrefix("#")
                    && !line.hasPrefix("- ")
                    && !line.hasPrefix("```")
            }
            .joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    private static func normalizedSearchText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func bounded(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "none" }
        guard normalized.count <= limit else {
            let prefixLimit = max(1, limit - 3)
            return normalized.prefix(prefixLimit)
                .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }
        return normalized
    }

    private static func boundedArtifactText(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = text
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "none" }
        guard normalized.count <= limit else {
            let prefixLimit = max(1, limit - 3)
            return normalized.prefix(prefixLimit)
                .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }
        return normalized
    }

    private static func fingerprint(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}

enum CinematicRunRecapShareArtifactComparisonPlanner {
    static func plan(
        historyPlan: CinematicRunRecapShareArtifactHistoryPlan,
        selectedEntryIdentifier: String? = nil,
        searchQuery: String? = nil,
        targetMode: CinematicRunRecapShareArtifactComparisonTargetMode = .adjacent,
        pinnedEntryIdentifiers: [String] = [],
        savedTourHoldEntryIdentifier: String? = nil
    ) -> CinematicRunRecapShareArtifactComparisonPlan {
        let previewPlan = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: historyPlan,
            selectedEntryIdentifier: selectedEntryIdentifier,
            searchQuery: searchQuery
        )
        let search = searchState(for: searchQuery)
        let retainedEntries = historyPlan.entries
        let matchingEntries = search.isActive
            ? retainedEntries.filter { matches($0, normalizedQuery: search.normalizedQuery) }
            : retainedEntries
        let selectedIndex = previewPlan.selectedEntryIdentifier.flatMap { identifier in
            matchingEntries.firstIndex { $0.identifier == identifier }
        }
        let selectedEntry = selectedIndex.map { matchingEntries[$0] }
        let requestedPinnedEntryIdentifiers = boundedIdentifierList(pinnedEntryIdentifiers)
        let retainedEntriesByIdentifier = Dictionary(
            uniqueKeysWithValues: retainedEntries.map { ($0.identifier, $0) }
        )
        let requestedSavedTourHoldEntryIdentifier = boundedOptionalIdentifier(savedTourHoldEntryIdentifier)
        let retainedSavedTourHoldEntry = requestedSavedTourHoldEntryIdentifier.flatMap {
            retainedEntriesByIdentifier[$0]
        }
        let retainedSavedTourHoldEntryIdentifier = retainedSavedTourHoldEntry?.identifier
        let retainedPinnedEntries = requestedPinnedEntryIdentifiers.compactMap { retainedEntriesByIdentifier[$0] }
        let retainedPinnedEntryIdentifiers = retainedPinnedEntries.map(\.identifier)
        let matchingEntryIdentifiers = Set(matchingEntries.map(\.identifier))
        let filteredSavedTourHoldEntryIdentifier = search.isActive
            ? retainedSavedTourHoldEntry
                .flatMap { matchingEntryIdentifiers.contains($0.identifier) ? nil : $0.identifier }
            : nil
        let missingPinnedEntryIdentifiers = requestedPinnedEntryIdentifiers.filter {
            retainedEntriesByIdentifier[$0] == nil
        }
        let filteredPinnedEntryIdentifiers = search.isActive
            ? retainedPinnedEntryIdentifiers.filter { !matchingEntryIdentifiers.contains($0) }
            : []
        let comparisonTarget: ComparisonTarget?
        switch targetMode {
        case .adjacent:
            comparisonTarget = selectedIndex.flatMap { target(for: $0, in: matchingEntries) }
        case .pinnedReference:
            comparisonTarget = selectedEntry.flatMap {
                pinnedTarget(
                    for: $0,
                    retainedPinnedEntries: retainedPinnedEntries,
                    matchingEntryIdentifiers: matchingEntryIdentifiers,
                    search: search
                )
            }
        }
        let compareEntry = comparisonTarget?.entry
        let pinnedTargetEntryIdentifier = targetMode == .pinnedReference
            ? compareEntry?.identifier
            : nil
        let targetDirectionIdentifier = comparisonTarget?.directionIdentifier ?? "none"
        let pinnedTargetStateIdentifier = pinnedTargetStateIdentifier(
            targetMode: targetMode,
            compareEntry: compareEntry,
            selectedEntry: selectedEntry,
            requestedPinnedEntryIdentifiers: requestedPinnedEntryIdentifiers,
            retainedPinnedEntryIdentifiers: retainedPinnedEntryIdentifiers,
            missingPinnedEntryIdentifiers: missingPinnedEntryIdentifiers,
            filteredPinnedEntryIdentifiers: filteredPinnedEntryIdentifiers,
            search: search
        )
        let pinnedTargetUnavailableReasonIdentifier = targetMode == .pinnedReference && compareEntry == nil
            ? pinnedTargetStateIdentifier
            : nil
        let sessionDelta = selectedEntry.flatMap { selected in
            compareEntry.map { abs(selected.sessionNumber - $0.sessionNumber) }
        }
        let noMatchAvailabilityReason = search.isActive && !retainedEntries.isEmpty && matchingEntries.isEmpty
            ? "no-matching-recap-share-artifacts"
            : nil
        let promotedHoldStateIdentifier = promotedHoldStateIdentifier(
            targetMode: targetMode,
            requestedSavedTourHoldEntryIdentifier: requestedSavedTourHoldEntryIdentifier,
            retainedSavedTourHoldEntryIdentifier: retainedSavedTourHoldEntryIdentifier,
            filteredSavedTourHoldEntryIdentifier: filteredSavedTourHoldEntryIdentifier,
            selectedEntry: selectedEntry,
            compareEntry: compareEntry,
            noMatchAvailabilityReason: noMatchAvailabilityReason
        )
        let availabilityReason = availabilityReason(
            historyPlan: historyPlan,
            matchingEntries: matchingEntries,
            compareEntry: compareEntry,
            previewPlan: previewPlan,
            targetMode: targetMode,
            pinnedTargetStateIdentifier: pinnedTargetStateIdentifier,
            search: search,
            noMatchAvailabilityReason: noMatchAvailabilityReason
        )
        let isAvailable = compareEntry != nil
        let warningStateIdentifier = historyPlan.hasWarnings ? "warnings" : "clear"
        let selectedBodyPreviewText = selectedEntry.map { bodyPreview(from: $0.markdownContents) }
        let compareBodyPreviewText = compareEntry.map { bodyPreview(from: $0.markdownContents) }
        var exportIdentifierParts = [
            "run-recap-share-artifact-comparison-export",
            "availability:\(availabilityReason)",
            "retained:\(retainedEntries.count)",
            "total:\(historyPlan.totalCount)",
            "hidden:\(historyPlan.hiddenCount)",
            "matching:\(matchingEntries.count)",
            "mode:\(targetMode.rawValue)",
            "query:\(search.queryFingerprint)",
            "query-snippet:\(search.querySnippet)",
            "no-match:\(noMatchAvailabilityReason ?? "none")",
            "selected:\(selectedEntry?.identifier ?? "none")",
            "compare:\(compareEntry?.identifier ?? "none")",
            "direction:\(targetDirectionIdentifier)",
            "pinned-target:\(pinnedTargetEntryIdentifier ?? "none")",
            "pinned-state:\(pinnedTargetStateIdentifier)"
        ]
        if let requestedSavedTourHoldEntryIdentifier {
            exportIdentifierParts.append(
                "promoted-hold-state:\(promotedHoldStateIdentifier)|promoted-hold:\(requestedSavedTourHoldEntryIdentifier)|retained-promoted-hold:\(retainedSavedTourHoldEntryIdentifier ?? "none")|filtered-promoted-hold:\(filteredSavedTourHoldEntryIdentifier ?? "none")"
            )
        }
        exportIdentifierParts += [
            "pins:\(requestedPinnedEntryIdentifiers.count)",
            "retained-pins:\(retainedPinnedEntryIdentifiers.count)",
            "missing-pins:\(missingPinnedEntryIdentifiers.count)",
            "filtered-pins:\(filteredPinnedEntryIdentifiers.count)",
            "delta:\(sessionDelta.map(String.init) ?? "none")",
            "fallback:\(previewPlan.selectedFallbackEntryIdentifier ?? "none")",
            "fallback-reason:\(previewPlan.selectedFallbackReasonIdentifier)",
            "cleanup:\(historyPlan.cleanupCandidateCount)",
            "warnings:\(warningStateIdentifier)",
            "warning-count:\(historyPlan.warningCount)",
            "content:\(fingerprint([selectedEntry?.identifier, compareEntry?.identifier].compactMap { $0 }.joined(separator: "|")))"
        ]
        let exportIdentifier = bounded(
            exportIdentifierParts.joined(separator: "|"),
            limit: CinematicRunRecapShareArtifactComparisonPlan.identifierMaxCharacters
        )
        let export = exportText(
            exportIdentifier: exportIdentifier,
            isAvailable: isAvailable,
            availabilityReason: availabilityReason,
            historyPlan: historyPlan,
            retainedEntries: retainedEntries,
            matchingEntries: matchingEntries,
            search: search,
            noMatchAvailabilityReason: noMatchAvailabilityReason,
            previewPlan: previewPlan,
            targetMode: targetMode,
            selectedEntry: selectedEntry,
            compareEntry: compareEntry,
            targetDirectionIdentifier: targetDirectionIdentifier,
            pinnedTargetStateIdentifier: pinnedTargetStateIdentifier,
            pinnedTargetUnavailableReasonIdentifier: pinnedTargetUnavailableReasonIdentifier,
            promotedHoldStateIdentifier: promotedHoldStateIdentifier,
            requestedSavedTourHoldEntryIdentifier: requestedSavedTourHoldEntryIdentifier,
            retainedSavedTourHoldEntryIdentifier: retainedSavedTourHoldEntryIdentifier,
            filteredSavedTourHoldEntryIdentifier: filteredSavedTourHoldEntryIdentifier,
            requestedPinnedEntryIdentifiers: requestedPinnedEntryIdentifiers,
            retainedPinnedEntryIdentifiers: retainedPinnedEntryIdentifiers,
            missingPinnedEntryIdentifiers: missingPinnedEntryIdentifiers,
            filteredPinnedEntryIdentifiers: filteredPinnedEntryIdentifiers,
            sessionDelta: sessionDelta,
            selectedBodyPreviewText: selectedBodyPreviewText,
            compareBodyPreviewText: compareBodyPreviewText,
            warningStateIdentifier: warningStateIdentifier
        )
        var identifierParts = [
            "run-recap-share-artifact-comparison",
            "availability:\(availabilityReason)",
            "export:\(fingerprint(exportIdentifier))",
            "retained:\(retainedEntries.count)",
            "matching:\(matchingEntries.count)",
            "mode:\(targetMode.rawValue)",
            "query:\(search.queryFingerprint)",
            "selected:\(selectedEntry?.identifier ?? "none")",
            "compare:\(compareEntry?.identifier ?? "none")",
            "direction:\(targetDirectionIdentifier)",
            "pinned-state:\(pinnedTargetStateIdentifier)"
        ]
        if let requestedSavedTourHoldEntryIdentifier {
            identifierParts.append(
                "promoted-hold-state:\(promotedHoldStateIdentifier)|promoted-hold:\(requestedSavedTourHoldEntryIdentifier)"
            )
        }
        identifierParts += [
            "pins:\(requestedPinnedEntryIdentifiers.count)",
            "retained-pins:\(retainedPinnedEntryIdentifiers.count)",
            "missing-pins:\(missingPinnedEntryIdentifiers.count)",
            "filtered-pins:\(filteredPinnedEntryIdentifiers.count)",
            "delta:\(sessionDelta.map(String.init) ?? "none")",
            "cleanup:\(historyPlan.cleanupCandidateCount)",
            "warnings:\(warningStateIdentifier)",
            "copy:\(export.count)"
        ]
        let identifier = bounded(
            identifierParts.joined(separator: "|"),
            limit: CinematicRunRecapShareArtifactComparisonPlan.identifierMaxCharacters
        )

        return CinematicRunRecapShareArtifactComparisonPlan(
            identifier: identifier,
            exportIdentifier: exportIdentifier,
            isAvailable: isAvailable,
            availabilityReason: availabilityReason,
            isSearchActive: search.isActive,
            searchQuerySnippet: search.querySnippet,
            searchQueryFingerprint: search.queryFingerprint,
            noMatchAvailabilityReason: noMatchAvailabilityReason,
            retainedEntryCount: retainedEntries.count,
            totalCount: historyPlan.totalCount,
            hiddenCount: historyPlan.hiddenCount,
            matchingEntryCount: matchingEntries.count,
            unfilteredVisibleCount: retainedEntries.count,
            selectedEntryIdentifier: selectedEntry?.identifier,
            selectedFallbackEntryIdentifier: previewPlan.selectedFallbackEntryIdentifier,
            selectedFallbackReasonIdentifier: previewPlan.selectedFallbackReasonIdentifier,
            compareEntryIdentifier: compareEntry?.identifier,
            targetMode: targetMode,
            targetModeIdentifier: targetMode.rawValue,
            targetDirectionIdentifier: targetDirectionIdentifier,
            pinnedTargetEntryIdentifier: pinnedTargetEntryIdentifier,
            pinnedTargetStateIdentifier: pinnedTargetStateIdentifier,
            pinnedTargetUnavailableReasonIdentifier: pinnedTargetUnavailableReasonIdentifier,
            promotedHoldStateIdentifier: promotedHoldStateIdentifier,
            requestedSavedTourHoldEntryIdentifier: requestedSavedTourHoldEntryIdentifier,
            retainedSavedTourHoldEntryIdentifier: retainedSavedTourHoldEntryIdentifier,
            filteredSavedTourHoldEntryIdentifier: filteredSavedTourHoldEntryIdentifier,
            requestedPinnedEntryIdentifiers: requestedPinnedEntryIdentifiers,
            retainedPinnedEntryIdentifiers: retainedPinnedEntryIdentifiers,
            missingPinnedEntryIdentifiers: missingPinnedEntryIdentifiers,
            filteredPinnedEntryIdentifiers: filteredPinnedEntryIdentifiers,
            pinnedEntryCount: requestedPinnedEntryIdentifiers.count,
            retainedPinnedEntryCount: retainedPinnedEntryIdentifiers.count,
            missingPinnedEntryCount: missingPinnedEntryIdentifiers.count,
            filteredPinnedEntryCount: filteredPinnedEntryIdentifiers.count,
            sessionDelta: sessionDelta,
            selectedSessionNumber: selectedEntry?.sessionNumber,
            compareSessionNumber: compareEntry?.sessionNumber,
            selectedFilename: selectedEntry?.filename,
            compareFilename: compareEntry?.filename,
            selectedTitleSnippet: selectedEntry.map { entrySnippet($0.titleSnippet) },
            compareTitleSnippet: compareEntry.map { entrySnippet($0.titleSnippet) },
            selectedStatusSnippet: selectedEntry.map { entrySnippet($0.statusSnippet) },
            compareStatusSnippet: compareEntry.map { entrySnippet($0.statusSnippet) },
            selectedCommitSnippet: selectedEntry?.commitSnippet.map(entrySnippet),
            compareCommitSnippet: compareEntry?.commitSnippet.map(entrySnippet),
            selectedBodyPreviewText: selectedBodyPreviewText,
            compareBodyPreviewText: compareBodyPreviewText,
            cleanupCandidateCount: historyPlan.cleanupCandidateCount,
            hiddenCleanupCandidateCount: historyPlan.hiddenCleanupCandidateCount,
            cleanupCandidateIdentifiers: historyPlan.cleanupCandidateIdentifiers,
            warningStateIdentifier: warningStateIdentifier,
            warningCount: historyPlan.warningCount,
            hiddenWarningCount: historyPlan.hiddenWarningCount,
            warningIdentifiers: historyPlan.warnings.map(\.identifier),
            hasWarnings: historyPlan.hasWarnings,
            exportText: export,
            copyLabel: copyLabel(isAvailable: isAvailable, targetMode: targetMode),
            copyHelp: copyHelp(
                isAvailable: isAvailable,
                availabilityReason: availabilityReason,
                targetMode: targetMode,
                pinnedTargetStateIdentifier: pinnedTargetStateIdentifier,
                selectedEntry: selectedEntry,
                compareEntry: compareEntry,
                targetDirectionIdentifier: targetDirectionIdentifier,
                search: search,
                exportIdentifier: exportIdentifier
            )
        )
    }

    private struct SearchState {
        var normalizedQuery: String
        var querySnippet: String
        var queryFingerprint: String
        var isActive: Bool
    }

    private struct ComparisonTarget {
        var entry: CinematicRunRecapShareArtifactHistoryPlan.Entry
        var directionIdentifier: String
    }

    private static func searchState(for query: String?) -> SearchState {
        let normalizedQuery = normalizedSearchText(query ?? "")
        let isActive = !normalizedQuery.isEmpty
        return SearchState(
            normalizedQuery: normalizedQuery,
            querySnippet: isActive
                ? bounded(
                    normalizedQuery,
                    limit: CinematicRunRecapShareArtifactComparisonPlan.searchQuerySnippetMaxCharacters
                )
                : "none",
            queryFingerprint: isActive ? fingerprint(normalizedQuery) : "none",
            isActive: isActive
        )
    }

    private static func matches(
        _ entry: CinematicRunRecapShareArtifactHistoryPlan.Entry,
        normalizedQuery query: String
    ) -> Bool {
        guard !query.isEmpty else { return true }
        let fields = [
            entry.filename,
            entry.titleSnippet,
            entry.statusSnippet,
            entry.commitSnippet ?? "",
            entry.pathDisplayText,
            previewSearchBody(from: entry.markdownContents) ?? ""
        ]
        return fields.contains { normalizedSearchText($0).contains(query) }
    }

    private static func target(
        for selectedIndex: Int,
        in entries: [CinematicRunRecapShareArtifactHistoryPlan.Entry]
    ) -> ComparisonTarget? {
        let olderIndex = selectedIndex + 1
        if olderIndex < entries.endIndex {
            return ComparisonTarget(entry: entries[olderIndex], directionIdentifier: "older")
        }
        if selectedIndex > entries.startIndex {
            return ComparisonTarget(entry: entries[selectedIndex - 1], directionIdentifier: "newer")
        }
        return nil
    }

    private static func pinnedTarget(
        for selectedEntry: CinematicRunRecapShareArtifactHistoryPlan.Entry,
        retainedPinnedEntries: [CinematicRunRecapShareArtifactHistoryPlan.Entry],
        matchingEntryIdentifiers: Set<String>,
        search: SearchState
    ) -> ComparisonTarget? {
        let nonSelectedPinnedEntries = retainedPinnedEntries.filter {
            $0.identifier != selectedEntry.identifier
        }
        let visiblePinnedEntries = search.isActive
            ? nonSelectedPinnedEntries.filter { matchingEntryIdentifiers.contains($0.identifier) }
            : nonSelectedPinnedEntries
        if let visiblePinnedEntry = visiblePinnedEntries.first {
            return ComparisonTarget(entry: visiblePinnedEntry, directionIdentifier: "pinned")
        }
        return nonSelectedPinnedEntries.first.map {
            ComparisonTarget(entry: $0, directionIdentifier: "pinned")
        }
    }

    private static func pinnedTargetStateIdentifier(
        targetMode: CinematicRunRecapShareArtifactComparisonTargetMode,
        compareEntry: CinematicRunRecapShareArtifactHistoryPlan.Entry?,
        selectedEntry: CinematicRunRecapShareArtifactHistoryPlan.Entry?,
        requestedPinnedEntryIdentifiers: [String],
        retainedPinnedEntryIdentifiers: [String],
        missingPinnedEntryIdentifiers: [String],
        filteredPinnedEntryIdentifiers: [String],
        search: SearchState
    ) -> String {
        guard targetMode == .pinnedReference else {
            return "adjacent-mode"
        }
        guard let selectedEntry else {
            return "no-selected-recap-share-artifact"
        }
        if let compareEntry {
            return search.isActive && filteredPinnedEntryIdentifiers.contains(compareEntry.identifier)
                ? "filtered-pinned-target"
                : "visible-pinned-target"
        }
        guard !requestedPinnedEntryIdentifiers.isEmpty else {
            return "no-pinned-recap-share-artifacts"
        }
        if retainedPinnedEntryIdentifiers.isEmpty,
           missingPinnedEntryIdentifiers.count == requestedPinnedEntryIdentifiers.count {
            return "pinned-recap-share-artifacts-missing"
        }
        if retainedPinnedEntryIdentifiers.allSatisfy({ $0 == selectedEntry.identifier }) {
            return "selected-only-pinned-recap-share-artifact"
        }
        return "no-retained-pinned-recap-share-target"
    }

    private static func promotedHoldStateIdentifier(
        targetMode: CinematicRunRecapShareArtifactComparisonTargetMode,
        requestedSavedTourHoldEntryIdentifier: String?,
        retainedSavedTourHoldEntryIdentifier: String?,
        filteredSavedTourHoldEntryIdentifier: String?,
        selectedEntry: CinematicRunRecapShareArtifactHistoryPlan.Entry?,
        compareEntry: CinematicRunRecapShareArtifactHistoryPlan.Entry?,
        noMatchAvailabilityReason: String?
    ) -> String {
        guard targetMode == .pinnedReference,
              requestedSavedTourHoldEntryIdentifier != nil else {
            return "none"
        }
        guard let retainedSavedTourHoldEntryIdentifier else {
            return "missing-promoted-hold"
        }
        guard let selectedEntry else {
            return noMatchAvailabilityReason == nil
                ? "no-selected-promoted-hold"
                : "no-match-promoted-hold"
        }
        if retainedSavedTourHoldEntryIdentifier == selectedEntry.identifier,
           compareEntry == nil {
            return "selected-only-promoted-hold"
        }
        guard compareEntry?.identifier == retainedSavedTourHoldEntryIdentifier else {
            return "retained-promoted-hold-not-target"
        }
        if filteredSavedTourHoldEntryIdentifier == retainedSavedTourHoldEntryIdentifier {
            return "filtered-promoted-hold-target"
        }
        return "retained-promoted-hold-target"
    }

    private static func availabilityReason(
        historyPlan: CinematicRunRecapShareArtifactHistoryPlan,
        matchingEntries: [CinematicRunRecapShareArtifactHistoryPlan.Entry],
        compareEntry: CinematicRunRecapShareArtifactHistoryPlan.Entry?,
        previewPlan: CinematicRunRecapShareArtifactPreviewBrowserPlan,
        targetMode: CinematicRunRecapShareArtifactComparisonTargetMode,
        pinnedTargetStateIdentifier: String,
        search: SearchState,
        noMatchAvailabilityReason: String?
    ) -> String {
        guard compareEntry == nil else { return "available" }
        if let noMatchAvailabilityReason {
            return noMatchAvailabilityReason
        }
        if historyPlan.entries.isEmpty {
            return historyPlan.availabilityReason
        }
        if matchingEntries.count == 1 {
            return search.isActive
                ? "single-matching-recap-share-artifact"
                : "single-recap-share-artifact"
        }
        if targetMode == .pinnedReference {
            return pinnedTargetStateIdentifier
        }
        return previewPlan.availabilityReason == "available"
            ? "no-comparison-target"
            : previewPlan.availabilityReason
    }

    private static func exportText(
        exportIdentifier: String,
        isAvailable: Bool,
        availabilityReason: String,
        historyPlan: CinematicRunRecapShareArtifactHistoryPlan,
        retainedEntries: [CinematicRunRecapShareArtifactHistoryPlan.Entry],
        matchingEntries: [CinematicRunRecapShareArtifactHistoryPlan.Entry],
        search: SearchState,
        noMatchAvailabilityReason: String?,
        previewPlan: CinematicRunRecapShareArtifactPreviewBrowserPlan,
        targetMode: CinematicRunRecapShareArtifactComparisonTargetMode,
        selectedEntry: CinematicRunRecapShareArtifactHistoryPlan.Entry?,
        compareEntry: CinematicRunRecapShareArtifactHistoryPlan.Entry?,
        targetDirectionIdentifier: String,
        pinnedTargetStateIdentifier: String,
        pinnedTargetUnavailableReasonIdentifier: String?,
        promotedHoldStateIdentifier: String,
        requestedSavedTourHoldEntryIdentifier: String?,
        retainedSavedTourHoldEntryIdentifier: String?,
        filteredSavedTourHoldEntryIdentifier: String?,
        requestedPinnedEntryIdentifiers: [String],
        retainedPinnedEntryIdentifiers: [String],
        missingPinnedEntryIdentifiers: [String],
        filteredPinnedEntryIdentifiers: [String],
        sessionDelta: Int?,
        selectedBodyPreviewText: String?,
        compareBodyPreviewText: String?,
        warningStateIdentifier: String
    ) -> String {
        let pinnedTargetEntryIdentifier = targetMode == .pinnedReference
            ? compareEntry?.identifier
            : nil
        var lines = [
            "# Compass Recap Artifact Comparison",
            "",
            "- Export: \(exportIdentifier)",
            "- Availability: \(isAvailable ? "available" : "unavailable (\(availabilityReason))")",
            "- Retention limit: \(historyPlan.retentionLimit)",
            "- Total artifacts: \(historyPlan.totalCount)",
            "- Retained artifacts: \(retainedEntries.count)",
            "- Matching artifacts: \(matchingEntries.count)",
            "- Hidden artifacts: \(historyPlan.hiddenCount)",
            "- Comparison mode: \(targetMode.rawValue)",
            "- Search active: \(search.isActive)",
            "- Search query: \(search.querySnippet)",
            "- Search fingerprint: \(search.queryFingerprint)",
            "- No-match reason: \(noMatchAvailabilityReason ?? "none")",
            "- Selected entry: \(selectedEntry?.identifier ?? "none")",
            "- Compare entry: \(compareEntry?.identifier ?? "none")",
            "- Target direction: \(targetDirectionIdentifier)",
            "- Pinned target: \(pinnedTargetEntryIdentifier ?? "none")",
            "- Pinned target state: \(pinnedTargetStateIdentifier)",
            "- Pinned unavailable reason: \(pinnedTargetUnavailableReasonIdentifier ?? "none")",
            "- Promoted hold state: \(promotedHoldStateIdentifier)",
            "- Promoted hold requested: \(requestedSavedTourHoldEntryIdentifier ?? "none")",
            "- Promoted hold retained: \(retainedSavedTourHoldEntryIdentifier ?? "none")",
            "- Promoted hold filtered: \(filteredSavedTourHoldEntryIdentifier ?? "none")",
            "- Pinned artifacts: \(requestedPinnedEntryIdentifiers.count)",
            "- Retained pins: \(retainedPinnedEntryIdentifiers.count)",
            "- Missing pins: \(missingPinnedEntryIdentifiers.count)",
            "- Filtered pins: \(filteredPinnedEntryIdentifiers.count)",
            "- Pinned identifiers: \(requestedPinnedEntryIdentifiers.isEmpty ? "none" : requestedPinnedEntryIdentifiers.joined(separator: ", "))",
            "- Retained pin identifiers: \(retainedPinnedEntryIdentifiers.isEmpty ? "none" : retainedPinnedEntryIdentifiers.joined(separator: ", "))",
            "- Missing pin identifiers: \(missingPinnedEntryIdentifiers.isEmpty ? "none" : missingPinnedEntryIdentifiers.joined(separator: ", "))",
            "- Filtered pin identifiers: \(filteredPinnedEntryIdentifiers.isEmpty ? "none" : filteredPinnedEntryIdentifiers.joined(separator: ", "))",
            "- Session delta: \(sessionDelta.map(String.init) ?? "none")",
            "- Selection fallback: \(previewPlan.selectedFallbackEntryIdentifier ?? "none")",
            "- Selection fallback reason: \(previewPlan.selectedFallbackReasonIdentifier)",
            "- Cleanup candidates: \(historyPlan.cleanupCandidateCount)",
            "- Hidden cleanup candidates: \(historyPlan.hiddenCleanupCandidateCount)",
            "- Cleanup candidate identifiers: \(historyPlan.cleanupCandidateIdentifiers.isEmpty ? "none" : historyPlan.cleanupCandidateIdentifiers.joined(separator: ", "))",
            "- Warning state: \(warningStateIdentifier)",
            "- Warnings: \(historyPlan.warningCount)",
            "- Hidden warnings: \(historyPlan.hiddenWarningCount)",
            "- Warning identifiers: \(historyPlan.warnings.isEmpty ? "none" : historyPlan.warnings.map(\.identifier).joined(separator: ", "))"
        ]

        if !historyPlan.warnings.isEmpty {
            lines.append("")
            lines.append("## Warnings")
            lines.append(contentsOf: historyPlan.warnings.map { warning in
                "- \(warning.identifier): \(warning.fileDisplayText) - \(warning.message)"
            })
        }

        guard let selectedEntry, let compareEntry else {
            lines.append("")
            lines.append("No retained recap share artifact comparison target is available: \(availabilityReason).")
            return boundedArtifactText(
                lines.joined(separator: "\n"),
                limit: CinematicRunRecapShareArtifactComparisonPlan.exportTextMaxCharacters
            )
        }

        lines.append("")
        lines.append("## Selected Artifact")
        lines.append(contentsOf: entryLines(entry: selectedEntry, bodyPreviewText: selectedBodyPreviewText))
        lines.append("")
        lines.append("## Comparison Target")
        lines.append(contentsOf: entryLines(entry: compareEntry, bodyPreviewText: compareBodyPreviewText))

        return boundedArtifactText(
            lines.joined(separator: "\n"),
            limit: CinematicRunRecapShareArtifactComparisonPlan.exportTextMaxCharacters
        )
    }

    private static func entryLines(
        entry: CinematicRunRecapShareArtifactHistoryPlan.Entry,
        bodyPreviewText: String?
    ) -> [String] {
        [
            "- Artifact: \(entry.identifier)",
            "- Session: \(entry.sessionNumber)",
            "- Filename: \(entry.filename)",
            "- Title: \(entrySnippet(entry.titleSnippet))",
            "- Status: \(entrySnippet(entry.statusSnippet))",
            "- Commit: \(entry.commitSnippet.map(entrySnippet) ?? "none")",
            "- Body preview: \(bodyPreviewText ?? "none")"
        ]
    }

    private static func copyLabel(
        isAvailable: Bool,
        targetMode: CinematicRunRecapShareArtifactComparisonTargetMode
    ) -> String {
        let availableLabel = targetMode == .pinnedReference
            ? "Copy pinned comparison"
            : "Copy comparison"
        return bounded(
            isAvailable ? availableLabel : "Comparison unavailable",
            limit: CinematicRunRecapShareArtifactComparisonPlan.copyLabelMaxCharacters
        )
    }

    private static func copyHelp(
        isAvailable: Bool,
        availabilityReason: String,
        targetMode: CinematicRunRecapShareArtifactComparisonTargetMode,
        pinnedTargetStateIdentifier: String,
        selectedEntry: CinematicRunRecapShareArtifactHistoryPlan.Entry?,
        compareEntry: CinematicRunRecapShareArtifactHistoryPlan.Entry?,
        targetDirectionIdentifier: String,
        search: SearchState,
        exportIdentifier: String
    ) -> String {
        guard isAvailable, let selectedEntry, let compareEntry else {
            let modeDetail = targetMode == .pinnedReference
                ? " pinned target state \(pinnedTargetStateIdentifier)"
                : ""
            return bounded(
                "No recap artifact comparison is available: \(availabilityReason)\(modeDetail).",
                limit: CinematicRunRecapShareArtifactComparisonPlan.copyHelpMaxCharacters
            )
        }

        let modeDetail = targetMode == .pinnedReference ? " pinned-reference" : ""
        let searchDetail = search.isActive ? " matching \(search.querySnippet)" : ""
        return bounded(
            "Copy\(modeDetail) recap artifact comparison \(exportIdentifier) for S\(selectedEntry.sessionNumber) against \(targetDirectionIdentifier) S\(compareEntry.sessionNumber)\(searchDetail).",
            limit: CinematicRunRecapShareArtifactComparisonPlan.copyHelpMaxCharacters
        )
    }

    private static func bodyPreview(from markdownContents: String) -> String {
        boundedBodyPreview(
            previewSearchBody(from: markdownContents) ?? "No preview text available.",
            limit: CinematicRunRecapShareArtifactComparisonPlan.bodyPreviewMaxCharacters
        )
    }

    private static func previewSearchBody(from markdownContents: String) -> String? {
        shareTextBody(in: markdownContents)
            ?? fallbackBody(in: markdownContents)
    }

    private static func shareTextBody(in markdownContents: String) -> String? {
        guard let range = markdownContents.range(of: "## Share Text") else {
            return nil
        }

        let text = markdownContents[range.upperBound...]
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { line in
                String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { line in
                !line.isEmpty && !line.hasPrefix("```")
            }
            .joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    private static func fallbackBody(in markdownContents: String) -> String? {
        let text = markdownContents
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { line in
                String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { line in
                !line.isEmpty
                    && !line.hasPrefix("#")
                    && !line.hasPrefix("- ")
                    && !line.hasPrefix("```")
            }
            .joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    private static func normalizedSearchText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func entrySnippet(_ text: String) -> String {
        bounded(
            text,
            limit: CinematicRunRecapShareArtifactComparisonPlan.snippetMaxCharacters
        )
    }

    private static func bounded(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "none" }
        guard normalized.count <= limit else {
            let prefixLimit = max(1, limit - 3)
            return normalized.prefix(prefixLimit)
                .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }
        return normalized
    }

    private static func boundedBodyPreview(_ text: String, limit: Int) -> String {
        bounded(text, limit: limit)
    }

    private static func boundedIdentifierList(_ identifiers: [String]) -> [String] {
        var seen = Set<String>()
        var boundedIdentifiers: [String] = []

        for identifier in identifiers {
            guard let boundedIdentifier = boundedOptionalIdentifier(identifier),
                  seen.insert(boundedIdentifier).inserted else {
                continue
            }
            boundedIdentifiers.append(boundedIdentifier)
            if boundedIdentifiers.count == CinematicRunRecapShareArtifactPinnedReferencePlan.pinIdentifierLimit {
                break
            }
        }

        return boundedIdentifiers
    }

    private static func boundedOptionalIdentifier(_ identifier: String?) -> String? {
        let boundedIdentifier = bounded(
            identifier ?? "",
            limit: CinematicRunRecapShareArtifactComparisonPlan.identifierMaxCharacters
        )
        return boundedIdentifier == "none" ? nil : boundedIdentifier
    }

    private static func boundedArtifactText(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = text
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "none" }
        guard normalized.count <= limit else {
            let prefixLimit = max(1, limit - 3)
            return normalized.prefix(prefixLimit)
                .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }
        return normalized
    }

    private static func fingerprint(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}

struct CinematicRunRecapShareArtifactCleanupResult: Equatable, Identifiable {
    static let identifierMaxCharacters = 320
    static let labelMaxCharacters = 34
    static let detailMaxCharacters = 180
    static let helpMaxCharacters = 260
    static let identifierListLimit = 8

    var id: String { identifier }

    var identifier: String
    var status: Status
    var retentionLimit: Int
    var cleanupCandidateCount: Int
    var deletedCount: Int
    var skippedCount: Int
    var failedCount: Int
    var deletedIdentifiers: [String]
    var skippedIdentifiers: [String]
    var failedIdentifiers: [String]
    var hiddenDeletedCount: Int
    var hiddenSkippedCount: Int
    var hiddenFailedCount: Int
    var refreshedHistory: CinematicRunRecapShareArtifactHistoryPlan
    var label: String
    var detail: String
    var help: String

    enum Status: String, Equatable {
        case deleted
        case skipped
        case failed
    }

    init(
        retentionLimit: Int,
        cleanupCandidateCount: Int,
        deletedIdentifiers allDeletedIdentifiers: [String],
        skippedIdentifiers allSkippedIdentifiers: [String],
        failedIdentifiers allFailedIdentifiers: [String],
        refreshedHistory: CinematicRunRecapShareArtifactHistoryPlan
    ) {
        self.retentionLimit = retentionLimit
        self.cleanupCandidateCount = max(0, cleanupCandidateCount)
        deletedCount = allDeletedIdentifiers.count
        skippedCount = allSkippedIdentifiers.count
        failedCount = allFailedIdentifiers.count
        deletedIdentifiers = Array(allDeletedIdentifiers.prefix(Self.identifierListLimit))
        skippedIdentifiers = Array(allSkippedIdentifiers.prefix(Self.identifierListLimit))
        failedIdentifiers = Array(allFailedIdentifiers.prefix(Self.identifierListLimit))
        hiddenDeletedCount = max(0, deletedCount - deletedIdentifiers.count)
        hiddenSkippedCount = max(0, skippedCount - skippedIdentifiers.count)
        hiddenFailedCount = max(0, failedCount - failedIdentifiers.count)
        self.refreshedHistory = refreshedHistory

        if failedCount > 0 {
            status = .failed
        } else if deletedCount > 0 {
            status = .deleted
        } else {
            status = .skipped
        }

        identifier = Self.bounded(
            [
                "run-recap-share-artifact-cleanup",
                "status:\(status.rawValue)",
                "retention:\(retentionLimit)",
                "candidates:\(cleanupCandidateCount)",
                "deleted:\(deletedCount)",
                "skipped:\(skippedCount)",
                "failed:\(failedCount)",
                "history:\(Self.fingerprint(refreshedHistory.identifier))",
                "deleted-ids:\(Self.fingerprint(allDeletedIdentifiers.joined(separator: ",")))",
                "skipped-ids:\(Self.fingerprint(allSkippedIdentifiers.joined(separator: ",")))",
                "failed-ids:\(Self.fingerprint(allFailedIdentifiers.joined(separator: ",")))"
            ].joined(separator: "|"),
            limit: Self.identifierMaxCharacters
        )
        label = Self.label(status: status)
        detail = Self.detail(
            status: status,
            retentionLimit: retentionLimit,
            cleanupCandidateCount: cleanupCandidateCount,
            deletedCount: deletedCount,
            skippedCount: skippedCount,
            failedCount: failedCount
        )
        help = Self.help(
            status: status,
            deletedIdentifiers: deletedIdentifiers,
            skippedIdentifiers: skippedIdentifiers,
            failedIdentifiers: failedIdentifiers,
            hiddenDeletedCount: hiddenDeletedCount,
            hiddenSkippedCount: hiddenSkippedCount,
            hiddenFailedCount: hiddenFailedCount,
            retentionLimit: retentionLimit
        )
    }

    private static func label(status: Status) -> String {
        switch status {
        case .deleted:
            return bounded("Cleaned", limit: labelMaxCharacters)
        case .skipped:
            return bounded("Nothing to clean", limit: labelMaxCharacters)
        case .failed:
            return bounded("Cleanup failed", limit: labelMaxCharacters)
        }
    }

    private static func detail(
        status: Status,
        retentionLimit: Int,
        cleanupCandidateCount: Int,
        deletedCount: Int,
        skippedCount: Int,
        failedCount: Int
    ) -> String {
        let text: String
        switch status {
        case .deleted:
            text = "Deleted \(deletedCount) old recap share artifact\(deletedCount == 1 ? "" : "s"); retaining newest \(retentionLimit)."
        case .skipped:
            text = cleanupCandidateCount == 0
                ? "No recap share artifact cleanup candidates; retaining newest \(retentionLimit)."
                : "Cleanup skipped \(skippedCount) candidate\(skippedCount == 1 ? "" : "s"); retaining newest \(retentionLimit)."
        case .failed:
            text = "Cleanup deleted \(deletedCount), skipped \(skippedCount), failed \(failedCount) of \(cleanupCandidateCount) candidate\(cleanupCandidateCount == 1 ? "" : "s")."
        }
        return bounded(text, limit: detailMaxCharacters)
    }

    private static func help(
        status: Status,
        deletedIdentifiers: [String],
        skippedIdentifiers: [String],
        failedIdentifiers: [String],
        hiddenDeletedCount: Int,
        hiddenSkippedCount: Int,
        hiddenFailedCount: Int,
        retentionLimit: Int
    ) -> String {
        var parts = ["Retains the newest \(retentionLimit) valid recap share artifacts."]
        if !deletedIdentifiers.isEmpty {
            parts.append("Deleted \(identifierSummary(deletedIdentifiers, hiddenCount: hiddenDeletedCount)).")
        }
        if !skippedIdentifiers.isEmpty {
            parts.append("Skipped \(identifierSummary(skippedIdentifiers, hiddenCount: hiddenSkippedCount)).")
        }
        if !failedIdentifiers.isEmpty {
            parts.append("Failed \(identifierSummary(failedIdentifiers, hiddenCount: hiddenFailedCount)).")
        }
        if status == .skipped && deletedIdentifiers.isEmpty && skippedIdentifiers.isEmpty && failedIdentifiers.isEmpty {
            parts.append("No eligible cleanup candidates were found.")
        }
        return bounded(parts.joined(separator: " "), limit: helpMaxCharacters)
    }

    private static func identifierSummary(_ identifiers: [String], hiddenCount: Int) -> String {
        let visible = identifiers
            .map { bounded($0, limit: 36) }
            .joined(separator: ", ")
        return hiddenCount > 0 ? "\(visible) +\(hiddenCount)" : visible
    }

    private static func bounded(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "none" }
        guard normalized.count <= limit else {
            let prefixLimit = max(1, limit - 3)
            return normalized.prefix(prefixLimit)
                .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }
        return normalized
    }

    private static func fingerprint(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}

enum CinematicRunRecapShareArtifactHistoryPlanner {
    static func plan(
        storageRootURL: URL,
        sessionsURL: URL,
        fileManager: FileManager = .default
    ) -> CinematicRunRecapShareArtifactHistoryPlan {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sessionsURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return unavailable(
                reason: "sessions-directory-unavailable",
                storageRootURL: storageRootURL,
                sessionsURL: sessionsURL
            )
        }

        let fileURLs: [URL]
        do {
            fileURLs = try fileManager.contentsOfDirectory(
                at: sessionsURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            return unavailable(
                reason: "sessions-scan-failed",
                storageRootURL: storageRootURL,
                sessionsURL: sessionsURL,
                warnings: [
                    warning(
                        identifierSeed: "scan:\(sessionsURL.path)",
                        fileDisplayText: displayPath(sessionsURL, relativeTo: storageRootURL),
                        message: "Could not scan recap share artifacts: \(error.localizedDescription)"
                    )
                ]
            )
        }

        var entries: [CinematicRunRecapShareArtifactHistoryPlan.Entry] = []
        var warnings: [CinematicRunRecapShareArtifactHistoryPlan.Warning] = []

        for fileURL in fileURLs where isRecapShareArtifactFilename(fileURL.lastPathComponent) {
            switch parseEntry(fileURL: fileURL, storageRootURL: storageRootURL) {
            case let .success(entry):
                entries.append(entry)
            case let .failure(warning):
                warnings.append(warning)
            }
        }

        entries = sortedEntries(entries)

        return makePlan(
            entries: entries,
            warnings: warnings,
            storageRootURL: storageRootURL,
            sessionsURL: sessionsURL
        )
    }

    static func cleanupCandidates(
        storageRootURL: URL,
        sessionsURL: URL,
        fileManager: FileManager = .default
    ) -> [CinematicRunRecapShareArtifactHistoryPlan.CleanupCandidate] {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sessionsURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              let fileURLs = try? fileManager.contentsOfDirectory(
                at: sessionsURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        let entries = fileURLs.compactMap { fileURL -> CinematicRunRecapShareArtifactHistoryPlan.Entry? in
            guard isRecapShareArtifactFilename(fileURL.lastPathComponent) else { return nil }
            switch parseEntry(fileURL: fileURL, storageRootURL: storageRootURL) {
            case let .success(entry):
                return entry
            case .failure:
                return nil
            }
        }

        return sortedEntries(entries)
            .dropFirst(CinematicRunRecapShareArtifactHistoryPlan.retentionLimit)
            .map(cleanupCandidate)
    }

    static func unavailable(
        reason: String,
        storageRootURL: URL? = nil,
        sessionsURL: URL? = nil,
        warnings: [CinematicRunRecapShareArtifactHistoryPlan.Warning] = []
    ) -> CinematicRunRecapShareArtifactHistoryPlan {
        makePlan(
            entries: [],
            warnings: warnings,
            storageRootURL: storageRootURL,
            sessionsURL: sessionsURL,
            emptyReason: reason
        )
    }

    private enum ParseResult {
        case success(CinematicRunRecapShareArtifactHistoryPlan.Entry)
        case failure(CinematicRunRecapShareArtifactHistoryPlan.Warning)
    }

    private static func parseEntry(fileURL: URL, storageRootURL: URL) -> ParseResult {
        let filename = fileURL.lastPathComponent
        let display = displayPath(fileURL, relativeTo: storageRootURL)
        guard let sessionNumber = sessionNumber(from: filename) else {
            return .failure(
                warning(
                    identifierSeed: "filename:\(fileURL.path)",
                    fileDisplayText: display,
                    message: "Recap share artifact filename is missing a session number."
                )
            )
        }

        let contents: String
        do {
            contents = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            return .failure(
                warning(
                    identifierSeed: "read:\(fileURL.path)",
                    fileDisplayText: display,
                    message: "Could not read recap share artifact: \(error.localizedDescription)"
                )
            )
        }

        guard contents.contains("# Compass Run Recap Share") else {
            return .failure(
                warning(
                    identifierSeed: "corrupt:\(fileURL.path):\(fingerprint(contents))",
                    fileDisplayText: display,
                    message: "Recap share artifact did not contain the expected Markdown header."
                )
            )
        }

        let title = markdownField("Title", in: contents) ?? "Untitled recap share"
        let status = markdownField("Status", in: contents) ?? "status unavailable"
        let commit = markdownField("Commit", in: contents).flatMap { value in
            value == "none" ? nil : value
        }
        let boundedFilename = boundedFilename(filename)
        let boundedContents = boundedArtifactText(
            contents,
            limit: CinematicRunRecapShareArtifactHistoryPlan.entryMarkdownMaxCharacters
        )
        let identifier = bounded(
            [
                "run-recap-share-artifact-history-entry",
                "session:\(sessionNumber)",
                "file:\(boundedFilename)",
                "content:\(fingerprint(contents))"
            ].joined(separator: "|"),
            limit: CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
        )

        return .success(
            CinematicRunRecapShareArtifactHistoryPlan.Entry(
                identifier: identifier,
                sessionNumber: sessionNumber,
                filename: boundedFilename,
                url: fileURL,
                pathDisplayText: boundedPath(display),
                titleSnippet: bounded(
                    title,
                    limit: CinematicRunRecapShareArtifactHistoryPlan.snippetMaxCharacters
                ),
                statusSnippet: bounded(
                    status,
                    limit: CinematicRunRecapShareArtifactHistoryPlan.snippetMaxCharacters
                ),
                commitSnippet: commit.map {
                    bounded(
                        $0,
                        limit: CinematicRunRecapShareArtifactHistoryPlan.snippetMaxCharacters
                    )
                },
                markdownContents: boundedContents,
                markdownLength: contents.count
            )
        )
    }

    private static func makePlan(
        entries allEntries: [CinematicRunRecapShareArtifactHistoryPlan.Entry],
        warnings allWarnings: [CinematicRunRecapShareArtifactHistoryPlan.Warning],
        storageRootURL: URL?,
        sessionsURL: URL?,
        emptyReason: String? = nil
    ) -> CinematicRunRecapShareArtifactHistoryPlan {
        let totalCount = allEntries.count
        let entries = Array(allEntries.prefix(CinematicRunRecapShareArtifactHistoryPlan.retentionLimit))
        let hiddenCount = max(0, totalCount - entries.count)
        let cleanupCandidates = allEntries
            .dropFirst(CinematicRunRecapShareArtifactHistoryPlan.retentionLimit)
            .map(cleanupCandidate)
        let cleanupCandidateCount = cleanupCandidates.count
        let cleanupCandidateIdentifiers = Array(
            cleanupCandidates
                .map(\.identifier)
                .prefix(CinematicRunRecapShareArtifactHistoryPlan.cleanupCandidateIdentifierLimit)
        )
        let hiddenCleanupCandidateCount = max(0, cleanupCandidateCount - cleanupCandidateIdentifiers.count)
        let warningCount = allWarnings.count
        let warnings = Array(allWarnings.prefix(CinematicRunRecapShareArtifactHistoryPlan.warningLimit))
        let hiddenWarningCount = max(0, warningCount - warnings.count)
        let availabilityReason = entries.isEmpty
            ? (emptyReason ?? "no-recap-share-artifacts")
            : "available"
        let exportIdentifier = bounded(
            [
                "run-recap-share-artifact-export",
                "availability:\(availabilityReason)",
                "retention:\(CinematicRunRecapShareArtifactHistoryPlan.retentionLimit)",
                "total:\(totalCount)",
                "hidden:\(hiddenCount)",
                "cleanup:\(cleanupCandidateCount)",
                "latest:\(entries.first?.identifier ?? "none")",
                "warnings:\(warningCount)",
                "content:\(fingerprint(entries.map(\.identifier).joined(separator: "|")))"
            ].joined(separator: "|"),
            limit: CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
        )
        let export = combinedMarkdownExport(
            entries: entries,
            totalCount: totalCount,
            hiddenCount: hiddenCount,
            cleanupCandidateCount: cleanupCandidateCount,
            hiddenCleanupCandidateCount: hiddenCleanupCandidateCount,
            cleanupCandidateIdentifiers: cleanupCandidateIdentifiers,
            warnings: warnings,
            warningCount: warningCount,
            hiddenWarningCount: hiddenWarningCount,
            availabilityReason: availabilityReason,
            exportIdentifier: exportIdentifier,
            storageRootURL: storageRootURL,
            sessionsURL: sessionsURL
        )
        let identifier = bounded(
            [
                "run-recap-share-artifact-history",
                "availability:\(availabilityReason)",
                "retention:\(CinematicRunRecapShareArtifactHistoryPlan.retentionLimit)",
                "total:\(totalCount)",
                "hidden:\(hiddenCount)",
                "cleanup:\(cleanupCandidateCount)",
                "latest:\(entries.first?.identifier ?? "none")",
                "export:\(fingerprint(exportIdentifier))",
                "warnings:\(warningCount)"
            ].joined(separator: "|"),
            limit: CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
        )

        return CinematicRunRecapShareArtifactHistoryPlan(
            identifier: identifier,
            isAvailable: !entries.isEmpty,
            availabilityReason: availabilityReason,
            storageRootDisplayText: boundedPath(storageRootURL?.path ?? "unavailable"),
            sessionsDisplayText: boundedPath(sessionsURL?.path ?? "unavailable"),
            retentionLimit: CinematicRunRecapShareArtifactHistoryPlan.retentionLimit,
            entries: entries,
            totalCount: totalCount,
            hiddenCount: hiddenCount,
            cleanupCandidateCount: cleanupCandidateCount,
            hiddenCleanupCandidateCount: hiddenCleanupCandidateCount,
            cleanupCandidateIdentifiers: cleanupCandidateIdentifiers,
            warnings: warnings,
            warningCount: warningCount,
            hiddenWarningCount: hiddenWarningCount,
            exportIdentifier: exportIdentifier,
            combinedMarkdownExport: export
        )
    }

    private static func combinedMarkdownExport(
        entries: [CinematicRunRecapShareArtifactHistoryPlan.Entry],
        totalCount: Int,
        hiddenCount: Int,
        cleanupCandidateCount: Int,
        hiddenCleanupCandidateCount: Int,
        cleanupCandidateIdentifiers: [String],
        warnings: [CinematicRunRecapShareArtifactHistoryPlan.Warning],
        warningCount: Int,
        hiddenWarningCount: Int,
        availabilityReason: String,
        exportIdentifier: String,
        storageRootURL: URL?,
        sessionsURL: URL?
    ) -> String {
        var lines = [
            "# Compass Recap Share Artifact Library",
            "",
            "- Export: \(exportIdentifier)",
            "- Availability: \(entries.isEmpty ? "unavailable (\(availabilityReason))" : "available")",
            "- Retention limit: \(CinematicRunRecapShareArtifactHistoryPlan.retentionLimit)",
            "- Total artifacts: \(totalCount)",
            "- Hidden artifacts: \(hiddenCount)",
            "- Cleanup candidates: \(cleanupCandidateCount)",
            "- Hidden cleanup candidates: \(hiddenCleanupCandidateCount)",
            "- Cleanup candidate identifiers: \(cleanupCandidateIdentifiers.isEmpty ? "none" : cleanupCandidateIdentifiers.joined(separator: ", "))",
            "- Latest session: \(entries.first?.sessionNumber.description ?? "none")",
            "- Latest filename: \(entries.first?.filename ?? "none")",
            "- Storage root: \(boundedPath(storageRootURL?.path ?? "unavailable"))",
            "- Sessions path: \(boundedPath(sessionsURL?.path ?? "unavailable"))",
            "- Warnings: \(warningCount)",
            "- Hidden warnings: \(hiddenWarningCount)"
        ]

        if !warnings.isEmpty {
            lines.append("")
            lines.append("## Warnings")
            lines.append(contentsOf: warnings.map { warning in
                "- \(warning.identifier): \(warning.fileDisplayText) - \(warning.message)"
            })
        }

        if entries.isEmpty {
            lines.append("")
            lines.append("No recap share artifacts were available for export.")
        } else {
            for entry in entries {
                lines.append("")
                lines.append("## Session \(entry.sessionNumber) - \(entry.filename)")
                lines.append("")
                lines.append("- Artifact: \(entry.identifier)")
                lines.append("- Path: \(entry.pathDisplayText)")
                lines.append("- Title: \(entry.titleSnippet)")
                lines.append("- Status: \(entry.statusSnippet)")
                lines.append("- Commit: \(entry.commitSnippet ?? "none")")
                lines.append("")
                lines.append(entry.markdownContents)
            }
        }

        return boundedArtifactText(
            lines.joined(separator: "\n"),
            limit: CinematicRunRecapShareArtifactHistoryPlan.combinedMarkdownMaxCharacters
        )
    }

    private static func isRecapShareArtifactFilename(_ filename: String) -> Bool {
        guard filename.hasSuffix(".md") else { return false }
        let parts = filename.split(separator: "-", maxSplits: 1).map(String.init)
        guard parts.count == 2, Int(parts[0]) != nil else { return false }
        return parts[1].hasPrefix("recap-share-")
    }

    private static func sortedEntries(
        _ entries: [CinematicRunRecapShareArtifactHistoryPlan.Entry]
    ) -> [CinematicRunRecapShareArtifactHistoryPlan.Entry] {
        entries.sorted { lhs, rhs in
            if lhs.sessionNumber != rhs.sessionNumber {
                return lhs.sessionNumber > rhs.sessionNumber
            }
            if lhs.filename != rhs.filename {
                return lhs.filename > rhs.filename
            }
            return lhs.pathDisplayText < rhs.pathDisplayText
        }
    }

    private static func cleanupCandidate(
        _ entry: CinematicRunRecapShareArtifactHistoryPlan.Entry
    ) -> CinematicRunRecapShareArtifactHistoryPlan.CleanupCandidate {
        CinematicRunRecapShareArtifactHistoryPlan.CleanupCandidate(
            identifier: entry.identifier,
            sessionNumber: entry.sessionNumber,
            filename: entry.filename,
            url: entry.url,
            pathDisplayText: entry.pathDisplayText
        )
    }

    private static func sessionNumber(from filename: String) -> Int? {
        let prefix = filename.split(separator: "-", maxSplits: 1).first.map(String.init) ?? ""
        return Int(prefix).flatMap { $0 > 0 ? $0 : nil }
    }

    private static func markdownField(_ name: String, in contents: String) -> String? {
        let prefix = "- \(name): "
        return contents
            .split(whereSeparator: \.isNewline)
            .first { $0.hasPrefix(prefix) }
            .map { line in
                String(line.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func warning(
        identifierSeed: String,
        fileDisplayText: String,
        message: String
    ) -> CinematicRunRecapShareArtifactHistoryPlan.Warning {
        CinematicRunRecapShareArtifactHistoryPlan.Warning(
            identifier: bounded(
                "recap-share-artifact-history.warning.\(fingerprint(identifierSeed))",
                limit: CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
            ),
            fileDisplayText: boundedPath(fileDisplayText),
            message: bounded(
                message,
                limit: CinematicRunRecapShareArtifactHistoryPlan.warningMaxCharacters
            )
        )
    }

    private static func displayPath(_ url: URL, relativeTo rootURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path == rootPath {
            return rootURL.lastPathComponent
        }
        if path.hasPrefix(rootPath + "/") {
            return String(path.dropFirst(rootPath.count + 1))
        }
        return path
    }

    private static func boundedFilename(_ filename: String) -> String {
        bounded(
            filename
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-"),
            limit: CinematicRunRecapShareArtifactHistoryPlan.filenameMaxCharacters
        )
    }

    private static func boundedPath(_ value: String) -> String {
        bounded(
            value,
            limit: CinematicRunRecapShareArtifactHistoryPlan.pathDisplayMaxCharacters
        )
    }

    private static func bounded(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "none" }
        guard normalized.count <= limit else {
            let prefixLimit = max(1, limit - 3)
            return normalized.prefix(prefixLimit)
                .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }
        return normalized
    }

    private static func boundedArtifactText(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = text
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "none" }
        guard normalized.count <= limit else {
            let prefixLimit = max(1, limit - 3)
            return normalized.prefix(prefixLimit)
                .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }
        return normalized
    }

    private static func fingerprint(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}

enum CinematicRunRecapShareArtifactPlanner {
    static func plan(
        sharePlan: CinematicRunRecapSharePlan,
        sessions: [SessionRecord]
    ) -> CinematicRunRecapShareArtifactPlan {
        plan(
            sharePlan: sharePlan,
            sessionNumber: latestFinishedSession(in: sessions)?.session
        )
    }

    static func plan(
        sharePlan: CinematicRunRecapSharePlan,
        sessionNumber: Int?
    ) -> CinematicRunRecapShareArtifactPlan {
        let latestSessionNumber = sessionNumber.flatMap { $0 > 0 ? $0 : nil }
        let artifactSessionNumber = sharePlan.isAvailable ? latestSessionNumber : nil
        let availabilityReason: String
        let isAvailable: Bool

        if !sharePlan.isAvailable {
            availabilityReason = bounded(
                sharePlan.availabilityReason,
                limit: CinematicRunRecapSharePlan.visualDescriptorTokenMaxCharacters
            )
            isAvailable = false
        } else if artifactSessionNumber == nil {
            availabilityReason = "no-finished-session"
            isAvailable = false
        } else {
            availabilityReason = "available"
            isAvailable = true
        }

        let hash = fingerprint(
            [
                availabilityReason,
                artifactSessionNumber.map(String.init) ?? "none",
                sharePlan.identifier,
                sharePlan.recapIdentifier
            ].joined(separator: "|")
        )
        let filename = safeFilename(
            "recap-share-\(String(hash.prefix(12))).md",
            limit: CinematicRunRecapShareArtifactPlan.filenameMaxCharacters
        )
        let identifier = bounded(
            [
                "run-recap-share-artifact",
                "availability:\(availabilityReason)",
                "session:\(artifactSessionNumber.map(String.init) ?? "none")",
                "file:\(filename)",
                "share:\(fingerprint(sharePlan.identifier))",
                "recap:\(fingerprint(sharePlan.recapIdentifier))",
                "focus:\(fingerprint(sharePlan.recapFocusIdentifier ?? "none"))",
                "end-card:\(fingerprint(sharePlan.endCardIdentifier ?? "none"))"
            ].joined(separator: "|"),
            limit: CinematicRunRecapShareArtifactPlan.identifierMaxCharacters
        )
        let markdown = markdownContents(
            identifier: identifier,
            availabilityReason: availabilityReason,
            isAvailable: isAvailable,
            sessionNumber: artifactSessionNumber,
            filename: filename,
            sharePlan: sharePlan
        )
        let feedback = feedbackText(
            availabilityReason: availabilityReason,
            isAvailable: isAvailable,
            sessionNumber: artifactSessionNumber,
            filename: filename
        )

        return CinematicRunRecapShareArtifactPlan(
            identifier: identifier,
            isAvailable: isAvailable,
            availabilityReason: availabilityReason,
            sessionNumber: artifactSessionNumber,
            filename: filename,
            shareIdentifier: sharePlan.identifier,
            recapIdentifier: sharePlan.recapIdentifier,
            recapFocusIdentifier: sharePlan.recapFocusIdentifier,
            endCardIdentifier: sharePlan.endCardIdentifier,
            title: sharePlan.title,
            status: sharePlan.status,
            detail: sharePlan.detail,
            commitHighlight: sharePlan.commitHighlight,
            eventSummaries: sharePlan.eventSummaries,
            visualDescriptorTokens: sharePlan.visualDescriptorTokens,
            markdownContents: markdown,
            feedback: feedback
        )
    }

    private static func latestFinishedSession(in sessions: [SessionRecord]) -> SessionRecord? {
        sessions
            .filter { session in
                session.endedAt != nil && isFinishedStatus(session.status)
            }
            .max { lhs, rhs in
                let left = outcomeTime(lhs)
                let right = outcomeTime(rhs)
                if left == right {
                    return lhs.session < rhs.session
                }
                return left < right
            }
    }

    private static func isFinishedStatus(_ status: SessionStatus) -> Bool {
        switch status {
        case .succeeded, .failed, .cancelled, .rejectedByPlan, .skipped:
            return true
        case .planning, .awaitingApproval, .developing:
            return false
        }
    }

    private static func outcomeTime(_ session: SessionRecord) -> Double {
        max(session.endedAt ?? session.startedAt, session.startedAt)
    }

    private static func markdownContents(
        identifier: String,
        availabilityReason: String,
        isAvailable: Bool,
        sessionNumber: Int?,
        filename: String,
        sharePlan: CinematicRunRecapSharePlan
    ) -> String {
        let eventLines = sharePlan.eventSummaries.isEmpty
            ? ["- none"]
            : sharePlan.eventSummaries.map { "- \($0)" }
        let visualLines = sharePlan.visualDescriptorTokens.isEmpty
            ? ["- none"]
            : sharePlan.visualDescriptorTokens.map { "- \($0)" }
        let lines = [
            [
                "# Compass Run Recap Share",
                "",
                "- Artifact: \(identifier)",
                "- Availability: \(isAvailable ? "available" : "unavailable (\(availabilityReason))")",
                "- Session: \(sessionNumber.map(String.init) ?? "none")",
                "- Filename: \(filename)",
                "- Share: \(bounded(sharePlan.identifier, limit: 180))",
                "- Recap: \(bounded(sharePlan.recapIdentifier, limit: 180))",
                "- Focus: \(bounded(sharePlan.recapFocusIdentifier ?? "none", limit: 180))",
                "- End card: \(bounded(sharePlan.endCardIdentifier ?? "none", limit: 180))",
                "- Title: \(sharePlan.title)",
                "- Status: \(sharePlan.status)",
                "- Detail: \(sharePlan.detail)",
                "- Commit: \(sharePlan.commitHighlight ?? "none")",
                "",
                "## Events"
            ],
            eventLines,
            [
                "",
                "## Visual Tokens"
            ],
            visualLines,
            [
                "",
                "## Share Text",
                "",
                "```text",
                sharePlan.text,
                "```"
            ]
        ].flatMap { $0 }

        return boundedArtifactText(
            lines.joined(separator: "\n"),
            limit: CinematicRunRecapShareArtifactPlan.markdownMaxCharacters
        )
    }

    private static func feedbackText(
        availabilityReason: String,
        isAvailable: Bool,
        sessionNumber: Int?,
        filename: String
    ) -> String {
        guard isAvailable, let sessionNumber else {
            return bounded(
                "Recap share artifact unavailable: \(availabilityReason).",
                limit: CinematicRunRecapShareArtifactPlan.feedbackMaxCharacters
            )
        }

        return bounded(
            "Ready to record recap share artifact \(filename) for session \(sessionNumber).",
            limit: CinematicRunRecapShareArtifactPlan.feedbackMaxCharacters
        )
    }

    private static func safeFilename(_ value: String, limit: Int) -> String {
        let normalized = value
            .lowercased()
            .map { character -> Character in
                if character.isLetter || character.isNumber || character == "-" || character == "_" || character == "." {
                    return character
                }
                return "-"
            }
        let collapsed = String(normalized)
            .replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        let fallback = collapsed.isEmpty ? "recap-share.md" : collapsed
        guard fallback.count <= limit else {
            let extensionSuffix = ".md"
            let baseLimit = max(1, limit - extensionSuffix.count)
            return String(fallback.prefix(baseLimit))
                .trimmingCharacters(in: CharacterSet(charactersIn: "-."))
                + extensionSuffix
        }
        return fallback.hasSuffix(".md") ? fallback : "\(fallback).md"
    }

    private static func bounded(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "none" }
        guard normalized.count <= limit else {
            let prefixLimit = max(1, limit - 3)
            return normalized.prefix(prefixLimit)
                .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }
        return normalized
    }

    private static func boundedArtifactText(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = text
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "none" }
        guard normalized.count <= limit else {
            let prefixLimit = max(1, limit - 3)
            return normalized.prefix(prefixLimit)
                .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }
        return normalized
    }

    private static func fingerprint(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}

struct CinematicRunRecapShareArtifactRecordingResult: Equatable {
    static let labelMaxCharacters = 28
    static let detailMaxCharacters = 180
    static let helpMaxCharacters = 260

    var status: Status
    var artifactPlan: CinematicRunRecapShareArtifactPlan
    var artifactURL: URL?
    var label: String
    var detail: String
    var help: String

    enum Status: String, Equatable {
        case recorded
        case skipped
        case failed
    }

    static func recorded(
        plan: CinematicRunRecapShareArtifactPlan,
        url: URL
    ) -> CinematicRunRecapShareArtifactRecordingResult {
        CinematicRunRecapShareArtifactRecordingResult(
            status: .recorded,
            artifactPlan: plan,
            artifactURL: url,
            label: "Recorded",
            detail: "Saved \(url.lastPathComponent).",
            help: "Recap share artifact saved at \(url.path)."
        )
    }

    static func skipped(
        plan: CinematicRunRecapShareArtifactPlan
    ) -> CinematicRunRecapShareArtifactRecordingResult {
        CinematicRunRecapShareArtifactRecordingResult(
            status: .skipped,
            artifactPlan: plan,
            artifactURL: nil,
            label: "Copy only",
            detail: plan.feedback,
            help: plan.feedback
        )
    }

    static func failed(
        plan: CinematicRunRecapShareArtifactPlan,
        error: Error
    ) -> CinematicRunRecapShareArtifactRecordingResult {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return CinematicRunRecapShareArtifactRecordingResult(
            status: .failed,
            artifactPlan: plan,
            artifactURL: nil,
            label: "Record failed",
            detail: "Could not save recap artifact: \(message.isEmpty ? "unknown error" : message)",
            help: "Pasteboard copy is independent; artifact recording failed before \(plan.filename) could be saved."
        )
    }

    init(
        status: Status,
        artifactPlan: CinematicRunRecapShareArtifactPlan,
        artifactURL: URL?,
        label: String,
        detail: String,
        help: String
    ) {
        self.status = status
        self.artifactPlan = artifactPlan
        self.artifactURL = artifactURL
        self.label = Self.bounded(label, limit: Self.labelMaxCharacters)
        self.detail = Self.bounded(detail, limit: Self.detailMaxCharacters)
        self.help = Self.bounded(help, limit: Self.helpMaxCharacters)
    }

    private static func bounded(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "none" }
        guard normalized.count <= limit else {
            let prefixLimit = max(1, limit - 3)
            return normalized.prefix(prefixLimit)
                .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }
        return normalized
    }
}

enum CinematicRunRecapSharePlanner {
    static func plan(
        recapPlan: CinematicRunRecapPlan,
        recapFocusDescriptor: CinematicRunRecapSceneFocusPlan.Descriptor? = nil,
        endCardDescriptor: CinematicRunRecapEndCardPlan.Descriptor? = nil
    ) -> CinematicRunRecapSharePlan {
        let title = bounded(
            recapPlan.title,
            limit: CinematicRunRecapPlan.titleLimit
        )
        let detail = bounded(
            recapPlan.detail,
            limit: CinematicRunRecapPlan.detailLimit
        )
        let status = bounded(
            recapPlan.status,
            limit: CinematicRunRecapPlan.statusLimit
        )
        let commitHighlight = recapPlan.newestCommitHighlight.map {
            bounded($0, limit: CinematicRunRecapPlan.commitHighlightLimit)
        }
        let eventSummaries = Array(
            recapPlan.eventChips.prefix(CinematicRunRecapSharePlan.eventSummaryLimit)
        ).map(eventSummary)
        let visualTokens = visualDescriptorTokens(
            recapPlan: recapPlan,
            recapFocusDescriptor: recapFocusDescriptor,
            endCardDescriptor: endCardDescriptor
        )
        let availabilityReason = recapPlan.isAvailable
            ? "available"
            : recapPlan.availabilityIdentifier
        let focusIdentifier = recapFocusDescriptor?.identifier
        let endCardIdentifier = endCardDescriptor?.identifier
        let identifier = bounded(
            [
                "run-recap-share",
                "availability:\(availabilityReason)",
                "recap:\(fingerprint(recapPlan.identifier))",
                "focus:\(fingerprint(focusIdentifier ?? "none"))",
                "end-card:\(fingerprint(endCardIdentifier ?? "none"))",
                "copy:\(fingerprint(copySignature(title, detail, status, commitHighlight, eventSummaries)))",
                "visual:\(fingerprint(visualTokens.joined(separator: ",")))"
            ].joined(separator: "|"),
            limit: CinematicRunRecapSharePlan.identifierMaxCharacters
        )
        let text = shareText(
            identifier: identifier,
            availabilityReason: availabilityReason,
            isAvailable: recapPlan.isAvailable,
            recapIdentifier: recapPlan.identifier,
            focusIdentifier: focusIdentifier,
            endCardIdentifier: endCardIdentifier,
            title: title,
            detail: detail,
            status: status,
            commitHighlight: commitHighlight,
            eventSummaries: eventSummaries,
            visualTokens: visualTokens
        )

        return CinematicRunRecapSharePlan(
            identifier: identifier,
            availabilityIdentifier: recapPlan.availabilityIdentifier,
            availabilityReason: availabilityReason,
            isAvailable: recapPlan.isAvailable,
            recapIdentifier: recapPlan.identifier,
            recapFocusIdentifier: focusIdentifier,
            endCardIdentifier: endCardIdentifier,
            title: title,
            detail: detail,
            status: status,
            commitHighlight: commitHighlight,
            eventSummaries: eventSummaries,
            visualDescriptorTokens: visualTokens,
            text: text
        )
    }

    private static func eventSummary(
        _ chip: CinematicRunRecapPlan.EventChip
    ) -> String {
        bounded(
            [
                chip.label,
                chip.detail,
                "source \(chip.sourceIdentifier)",
                "style \(chip.styleIdentifier)"
            ].joined(separator: " | "),
            limit: CinematicRunRecapSharePlan.eventSummaryMaxCharacters
        )
    }

    private static func visualDescriptorTokens(
        recapPlan: CinematicRunRecapPlan,
        recapFocusDescriptor: CinematicRunRecapSceneFocusPlan.Descriptor?,
        endCardDescriptor: CinematicRunRecapEndCardPlan.Descriptor?
    ) -> [String] {
        var tokens: [String] = [
            "style:\(recapPlan.style.rawValue)",
            "color:\(recapPlan.colorIdentifier)",
            "title-source:\(recapPlan.titleSourceIdentifier)",
            "flavor-state:\(recapPlan.flavorStateIdentifier)",
            "terminal:\(recapPlan.statusIdentifier)"
        ]

        if let recapFocusDescriptor {
            tokens.append("focus-shot:\(recapFocusDescriptor.cameraShotIdentifier)")
            tokens.append("focus-light:\(recapFocusDescriptor.lightFamilyIdentifier)")
            tokens.append("focus-effect:\(recapFocusDescriptor.arenaEffectIdentifier)")
        }

        if let endCardDescriptor {
            tokens.append("end-card-anchor:\(endCardDescriptor.anchorIdentifier)")
            tokens.append("end-card-treatment:\(endCardDescriptor.plaqueTreatmentAccentIdentifier)")
            tokens.append("end-card-glyph:\(endCardDescriptor.glyphIdentifier)")
            tokens.append("end-card-light:\(endCardDescriptor.lightFamilyIdentifier)")
            tokens.append("end-card-tint:\(endCardDescriptor.tintFamilyIdentifier)")
            tokens.append("end-card-route:\(endCardDescriptor.plaqueTreatmentRouteIdentifier)")
            tokens.append("end-card-recipe:\(endCardDescriptor.plaqueTreatmentRenderRecipeIdentifier)")
        }

        if let flavorIdentifier = recapPlan.flavorIdentifier {
            tokens.append("flavor-id:\(fingerprint(flavorIdentifier))")
        }
        if let flavorSourceIdentifier = recapPlan.flavorSourceIdentifier {
            tokens.append("flavor-source:\(fingerprint(flavorSourceIdentifier))")
        }

        if let recapFocusDescriptor {
            tokens.append(
                recapFocusDescriptor.usesFallbackTarget
                    ? "focus-target:fallback"
                    : "focus-target:commit"
            )
        }

        return Array(
            tokens
                .map {
                    bounded(
                        $0,
                        limit: CinematicRunRecapSharePlan.visualDescriptorTokenMaxCharacters
                    )
                }
                .prefix(CinematicRunRecapSharePlan.visualDescriptorTokenLimit)
        )
    }

    private static func shareText(
        identifier: String,
        availabilityReason: String,
        isAvailable: Bool,
        recapIdentifier: String,
        focusIdentifier: String?,
        endCardIdentifier: String?,
        title: String,
        detail: String,
        status: String,
        commitHighlight: String?,
        eventSummaries: [String],
        visualTokens: [String]
    ) -> String {
        let availability = isAvailable
            ? availabilityReason
            : "unavailable (\(availabilityReason))"
        let eventCopy = eventSummaries.isEmpty
            ? "none"
            : bounded(
                eventSummaries.joined(separator: "; "),
                limit: CinematicRunRecapSharePlan.visualDescriptorLineMaxCharacters
            )
        let visualCopy = visualTokens.isEmpty
            ? "none"
            : bounded(
                visualTokens.joined(separator: ", "),
                limit: CinematicRunRecapSharePlan.visualDescriptorLineMaxCharacters
            )
        let lines = [
            "Compass Run Recap",
            "Share: \(identifier)",
            "Availability: \(availability)",
            "Recap: \(bounded(recapIdentifier, limit: 180))",
            "Focus: \(bounded(focusIdentifier ?? "none", limit: 180))",
            "End card: \(bounded(endCardIdentifier ?? "none", limit: 180))",
            "Title: \(title)",
            "Status: \(status)",
            "Detail: \(detail)",
            "Commit: \(commitHighlight ?? "none")",
            "Events: \(eventCopy)",
            "Visual: \(visualCopy)"
        ]

        return boundedArtifactText(
            lines.joined(separator: "\n"),
            limit: CinematicRunRecapSharePlan.textMaxCharacters
        )
    }

    private static func copySignature(
        _ title: String,
        _ detail: String,
        _ status: String,
        _ commitHighlight: String?,
        _ eventSummaries: [String]
    ) -> String {
        [
            title,
            detail,
            status,
            commitHighlight ?? "none",
            eventSummaries.joined(separator: ";")
        ].joined(separator: "|")
    }

    private static func normalizedText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func bounded(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = normalizedText(text)
        guard !normalized.isEmpty else { return "none" }
        guard normalized.count <= limit else {
            let prefixLimit = max(1, limit - 3)
            return normalized.prefix(prefixLimit)
                .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }
        return normalized
    }

    private static func boundedArtifactText(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = text
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "none" }
        guard normalized.count <= limit else {
            let prefixLimit = max(1, limit - 3)
            return normalized.prefix(prefixLimit)
                .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }
        return normalized
    }

    private static func fingerprint(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}
