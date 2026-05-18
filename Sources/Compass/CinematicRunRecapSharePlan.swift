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
    var targetDirectionIdentifier: String
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
        searchQuery: String? = nil
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
        let comparisonTarget = selectedIndex.flatMap { target(for: $0, in: matchingEntries) }
        let compareEntry = comparisonTarget?.entry
        let targetDirectionIdentifier = comparisonTarget?.directionIdentifier ?? "none"
        let sessionDelta = selectedEntry.flatMap { selected in
            compareEntry.map { abs(selected.sessionNumber - $0.sessionNumber) }
        }
        let noMatchAvailabilityReason = search.isActive && !retainedEntries.isEmpty && matchingEntries.isEmpty
            ? "no-matching-recap-share-artifacts"
            : nil
        let availabilityReason = availabilityReason(
            historyPlan: historyPlan,
            matchingEntries: matchingEntries,
            compareEntry: compareEntry,
            previewPlan: previewPlan,
            search: search,
            noMatchAvailabilityReason: noMatchAvailabilityReason
        )
        let isAvailable = compareEntry != nil
        let warningStateIdentifier = historyPlan.hasWarnings ? "warnings" : "clear"
        let selectedBodyPreviewText = selectedEntry.map { bodyPreview(from: $0.markdownContents) }
        let compareBodyPreviewText = compareEntry.map { bodyPreview(from: $0.markdownContents) }
        let exportIdentifier = bounded(
            [
                "run-recap-share-artifact-comparison-export",
                "availability:\(availabilityReason)",
                "retained:\(retainedEntries.count)",
                "total:\(historyPlan.totalCount)",
                "hidden:\(historyPlan.hiddenCount)",
                "matching:\(matchingEntries.count)",
                "query:\(search.queryFingerprint)",
                "query-snippet:\(search.querySnippet)",
                "no-match:\(noMatchAvailabilityReason ?? "none")",
                "selected:\(selectedEntry?.identifier ?? "none")",
                "compare:\(compareEntry?.identifier ?? "none")",
                "direction:\(targetDirectionIdentifier)",
                "delta:\(sessionDelta.map(String.init) ?? "none")",
                "fallback:\(previewPlan.selectedFallbackEntryIdentifier ?? "none")",
                "fallback-reason:\(previewPlan.selectedFallbackReasonIdentifier)",
                "cleanup:\(historyPlan.cleanupCandidateCount)",
                "warnings:\(warningStateIdentifier)",
                "warning-count:\(historyPlan.warningCount)",
                "content:\(fingerprint([selectedEntry?.identifier, compareEntry?.identifier].compactMap { $0 }.joined(separator: "|")))"
            ].joined(separator: "|"),
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
            selectedEntry: selectedEntry,
            compareEntry: compareEntry,
            targetDirectionIdentifier: targetDirectionIdentifier,
            sessionDelta: sessionDelta,
            selectedBodyPreviewText: selectedBodyPreviewText,
            compareBodyPreviewText: compareBodyPreviewText,
            warningStateIdentifier: warningStateIdentifier
        )
        let identifier = bounded(
            [
                "run-recap-share-artifact-comparison",
                "availability:\(availabilityReason)",
                "export:\(fingerprint(exportIdentifier))",
                "retained:\(retainedEntries.count)",
                "matching:\(matchingEntries.count)",
                "query:\(search.queryFingerprint)",
                "selected:\(selectedEntry?.identifier ?? "none")",
                "compare:\(compareEntry?.identifier ?? "none")",
                "direction:\(targetDirectionIdentifier)",
                "delta:\(sessionDelta.map(String.init) ?? "none")",
                "cleanup:\(historyPlan.cleanupCandidateCount)",
                "warnings:\(warningStateIdentifier)",
                "copy:\(export.count)"
            ].joined(separator: "|"),
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
            targetDirectionIdentifier: targetDirectionIdentifier,
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
            copyLabel: copyLabel(isAvailable: isAvailable),
            copyHelp: copyHelp(
                isAvailable: isAvailable,
                availabilityReason: availabilityReason,
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

    private static func availabilityReason(
        historyPlan: CinematicRunRecapShareArtifactHistoryPlan,
        matchingEntries: [CinematicRunRecapShareArtifactHistoryPlan.Entry],
        compareEntry: CinematicRunRecapShareArtifactHistoryPlan.Entry?,
        previewPlan: CinematicRunRecapShareArtifactPreviewBrowserPlan,
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
        selectedEntry: CinematicRunRecapShareArtifactHistoryPlan.Entry?,
        compareEntry: CinematicRunRecapShareArtifactHistoryPlan.Entry?,
        targetDirectionIdentifier: String,
        sessionDelta: Int?,
        selectedBodyPreviewText: String?,
        compareBodyPreviewText: String?,
        warningStateIdentifier: String
    ) -> String {
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
            "- Search active: \(search.isActive)",
            "- Search query: \(search.querySnippet)",
            "- Search fingerprint: \(search.queryFingerprint)",
            "- No-match reason: \(noMatchAvailabilityReason ?? "none")",
            "- Selected entry: \(selectedEntry?.identifier ?? "none")",
            "- Compare entry: \(compareEntry?.identifier ?? "none")",
            "- Target direction: \(targetDirectionIdentifier)",
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

    private static func copyLabel(isAvailable: Bool) -> String {
        bounded(
            isAvailable ? "Copy comparison" : "Comparison unavailable",
            limit: CinematicRunRecapShareArtifactComparisonPlan.copyLabelMaxCharacters
        )
    }

    private static func copyHelp(
        isAvailable: Bool,
        availabilityReason: String,
        selectedEntry: CinematicRunRecapShareArtifactHistoryPlan.Entry?,
        compareEntry: CinematicRunRecapShareArtifactHistoryPlan.Entry?,
        targetDirectionIdentifier: String,
        search: SearchState,
        exportIdentifier: String
    ) -> String {
        guard isAvailable, let selectedEntry, let compareEntry else {
            return bounded(
                "No recap artifact comparison is available: \(availabilityReason).",
                limit: CinematicRunRecapShareArtifactComparisonPlan.copyHelpMaxCharacters
            )
        }

        let searchDetail = search.isActive ? " matching \(search.querySnippet)" : ""
        return bounded(
            "Copy recap artifact comparison \(exportIdentifier) for S\(selectedEntry.sessionNumber) against \(targetDirectionIdentifier) S\(compareEntry.sessionNumber)\(searchDetail).",
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
