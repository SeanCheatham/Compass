import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct CinematicRunRecapPlan: Equatable, Identifiable {
    static let titleLimit = 64
    static let detailLimit = 128
    static let statusLimit = 72
    static let completedSummaryLimit = 96
    static let commitHighlightLimit = 72
    static let eventChipLimit = 3
    static let eventChipLabelLimit = 34
    static let eventChipDetailLimit = 68

    var id: String { identifier }

    var identifier: String
    var availabilityIdentifier: String
    var isAvailable: Bool
    var sessionNumber: Int?
    var statusIdentifier: String
    var title: String
    var detail: String
    var status: String
    var systemImage: String
    var style: Style
    var latestCompletedSummary: String
    var newestCommitHighlight: String?
    var commitHighlightCount: Int
    var completedCount: Int
    var eventChips: [EventChip]
    var sourceIdentifier: String?
    var flavorStateIdentifier: String
    var flavorIdentifier: String?
    var flavorSourceIdentifier: String?
    var titleSourceIdentifier: String

    var colorIdentifier: String {
        style.colorIdentifier
    }

    var eventChipCount: Int {
        eventChips.count
    }

    enum Style: String, Equatable {
        case success
        case failure
        case warning
        case paused
        case empty

        var colorIdentifier: String {
            switch self {
            case .success:
                return "green"
            case .failure:
                return "red"
            case .warning:
                return "orange"
            case .paused:
                return "blue"
            case .empty:
                return "secondary"
            }
        }
    }

    struct EventChip: Equatable, Identifiable {
        var id: String { identifier }

        var identifier: String
        var sourceIdentifier: String
        var label: String
        var detail: String
        var systemImage: String
        var styleIdentifier: String
        var colorIdentifier: String
    }

    static func empty(reason: String) -> CinematicRunRecapPlan {
        let availability = normalizedIdentifierComponent(reason, fallback: "empty")
        return CinematicRunRecapPlan(
            identifier: "run-recap.empty|reason:\(availability)",
            availabilityIdentifier: availability,
            isAvailable: false,
            sessionNumber: nil,
            statusIdentifier: "none",
            title: boundedText("Run recap unavailable", limit: titleLimit),
            detail: boundedText(emptyDetail(for: availability), limit: detailLimit),
            status: boundedText("No recap", limit: statusLimit),
            systemImage: "clock.badge.questionmark",
            style: .empty,
            latestCompletedSummary: boundedText("No completed plan items recorded.", limit: completedSummaryLimit),
            newestCommitHighlight: nil,
            commitHighlightCount: 0,
            completedCount: 0,
            eventChips: [],
            sourceIdentifier: nil,
            flavorStateIdentifier: CinematicRunRecapFlavorApplication.deterministic.rawValue,
            flavorIdentifier: nil,
            flavorSourceIdentifier: nil,
            titleSourceIdentifier: CinematicRunRecapFlavor.TitleSource.deterministic.rawValue
        )
    }

    static func available(
        session: SessionRecord,
        latestCompletedSummary: String,
        newestCommitHighlight: String?,
        commitHighlightCount: Int,
        completedCount: Int,
        eventChips: [EventChip],
        flavor: CinematicRunRecapFlavor? = nil
    ) -> CinematicRunRecapPlan {
        let statusCopy = statusText(for: session.status)
        let boundedCompletedSummary = boundedText(latestCompletedSummary, limit: completedSummaryLimit)
        let boundedCommitHighlight = newestCommitHighlight.map {
            boundedText($0, limit: commitHighlightLimit)
        }
        let boundedEventChips = Array(eventChips.prefix(eventChipLimit))
        let deterministicTitle = boundedText(
            "Run #\(session.session) \(statusCopy.lowercased())",
            limit: titleLimit
        )
        let deterministicDetail = boundedText(boundedCompletedSummary, limit: detailLimit)
        let status = boundedText(
            [
                countCopy(commitHighlightCount, singular: "commit highlight", plural: "commit highlights"),
                countCopy(completedCount, singular: "completed item", plural: "completed items"),
                countCopy(boundedEventChips.count, singular: "event", plural: "events")
            ].joined(separator: " - "),
            limit: statusLimit
        )
        let style = style(for: session.status)
        let sourceIdentifier = recapSourceIdentifier(
            session: session,
            latestCompletedSummary: boundedCompletedSummary,
            newestCommitHighlight: boundedCommitHighlight,
            commitHighlightCount: commitHighlightCount,
            completedCount: completedCount,
            eventChipIdentifiers: boundedEventChips.map(\.identifier)
        )
        let flavorApplication = flavorApplication(
            flavor,
            sourceIdentifier: sourceIdentifier
        )
        let title = flavorApplication.appliedFlavor.map {
            boundedText($0.title, limit: titleLimit)
        } ?? deterministicTitle
        let detail = flavorApplication.appliedFlavor.map {
            boundedText($0.detail, limit: detailLimit)
        } ?? deterministicDetail
        var identifierComponents = [
            "run-recap",
            "session:\(session.session)",
            "status:\(session.status.rawValue)",
            "style:\(style.rawValue)",
            "completed:\(completedCount)",
            "summary:\(copyIdentifier(boundedCompletedSummary))",
            "commit-count:\(max(0, commitHighlightCount))",
            "commit:\(copyIdentifier(boundedCommitHighlight ?? "none"))",
            "events:\(boundedEventChips.map(\.identifier).joined(separator: ","))"
        ]
        if let appliedFlavor = flavorApplication.appliedFlavor {
            identifierComponents.append("flavor:\(appliedFlavor.tokenIdentifier)")
        }
        let identifier = identifierComponents.joined(separator: "|")

        return CinematicRunRecapPlan(
            identifier: identifier,
            availabilityIdentifier: "available",
            isAvailable: true,
            sessionNumber: session.session,
            statusIdentifier: session.status.rawValue,
            title: title,
            detail: detail,
            status: status,
            systemImage: systemImage(for: session.status),
            style: style,
            latestCompletedSummary: boundedCompletedSummary,
            newestCommitHighlight: boundedCommitHighlight,
            commitHighlightCount: max(0, commitHighlightCount),
            completedCount: max(0, completedCount),
            eventChips: boundedEventChips,
            sourceIdentifier: sourceIdentifier,
            flavorStateIdentifier: flavorApplication.state.rawValue,
            flavorIdentifier: flavorApplication.flavor?.identifier,
            flavorSourceIdentifier: flavorApplication.flavor?.sourceIdentifier,
            titleSourceIdentifier: flavorApplication.titleSourceIdentifier
        )
    }

    static func eventChip(
        sourceIdentifier: String,
        label: String,
        detail: String,
        systemImage: String,
        styleIdentifier: String,
        colorIdentifier: String
    ) -> EventChip {
        let boundedLabel = boundedText(label, limit: eventChipLabelLimit)
        let boundedDetail = boundedText(detail, limit: eventChipDetailLimit)
        let boundedSystemImage = boundedText(systemImage, limit: 48)
        let boundedStyle = normalizedIdentifierComponent(styleIdentifier, fallback: "event")
        let boundedColor = normalizedIdentifierComponent(colorIdentifier, fallback: "secondary")
        let source = normalizedSourceIdentifier(sourceIdentifier)
        let identifier = [
            source,
            "style:\(boundedStyle)",
            "color:\(boundedColor)",
            "copy:\(copyIdentifier(boundedLabel, boundedDetail))"
        ].joined(separator: "|")

        return EventChip(
            identifier: identifier,
            sourceIdentifier: source,
            label: boundedLabel,
            detail: boundedDetail,
            systemImage: boundedSystemImage.isEmpty ? "circle.fill" : boundedSystemImage,
            styleIdentifier: boundedStyle,
            colorIdentifier: boundedColor
        )
    }

    static func boundedText(_ value: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = normalizedText(value)
        guard !normalized.isEmpty else { return "" }
        guard normalized.count > limit else { return normalized }
        guard limit > 3 else { return String(normalized.prefix(limit)) }
        return normalized
            .prefix(limit - 3)
            .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    static func statusText(for status: SessionStatus) -> String {
        switch status {
        case .planning:
            return "Planning"
        case .awaitingApproval:
            return "Awaiting approval"
        case .developing:
            return "Developing"
        case .succeeded:
            return "Succeeded"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        case .rejectedByPlan:
            return "Rejected by plan"
        case .skipped:
            return "Skipped"
        }
    }

    private static func emptyDetail(for availability: String) -> String {
        switch availability {
        case "active-run":
            return "Compass is still working on the active run."
        case "no-finished-session":
            return "No finished session is available to recap."
        default:
            return "No finished session is available to recap."
        }
    }

    private static func style(for status: SessionStatus) -> Style {
        switch status {
        case .succeeded:
            return .success
        case .failed, .rejectedByPlan:
            return .failure
        case .cancelled, .skipped:
            return .warning
        case .awaitingApproval:
            return .paused
        case .planning, .developing:
            return .empty
        }
    }

    private static func systemImage(for status: SessionStatus) -> String {
        switch status {
        case .succeeded:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.octagon.fill"
        case .cancelled:
            return "pause.circle.fill"
        case .rejectedByPlan:
            return "exclamationmark.triangle.fill"
        case .skipped:
            return "forward.end.circle"
        case .awaitingApproval:
            return "play.circle.fill"
        case .planning:
            return "clock"
        case .developing:
            return "hammer.circle"
        }
    }

    private static func countCopy(_ count: Int, singular: String, plural: String) -> String {
        count == 1 ? "1 \(singular)" : "\(max(0, count)) \(plural)"
    }

    static func recapSourceIdentifier(
        session: SessionRecord,
        latestCompletedSummary: String,
        newestCommitHighlight: String?,
        commitHighlightCount: Int,
        completedCount: Int,
        eventChipIdentifiers: [String]
    ) -> String {
        [
            "run-recap-source",
            "session:\(session.session)",
            "status:\(session.status.rawValue)",
            "completed:\(max(0, completedCount))",
            "summary:\(copyIdentifier(boundedText(latestCompletedSummary, limit: completedSummaryLimit)))",
            "commit-count:\(max(0, commitHighlightCount))",
            "commit:\(copyIdentifier(newestCommitHighlight ?? "none"))",
            "events:\(eventChipIdentifiers.joined(separator: ","))"
        ].joined(separator: "|")
    }

    private static func flavorApplication(
        _ flavor: CinematicRunRecapFlavor?,
        sourceIdentifier: String
    ) -> (state: CinematicRunRecapFlavorApplication, flavor: CinematicRunRecapFlavor?, appliedFlavor: CinematicRunRecapFlavor?, titleSourceIdentifier: String) {
        guard let flavor else {
            return (
                .deterministic,
                nil,
                nil,
                CinematicRunRecapFlavor.TitleSource.deterministic.rawValue
            )
        }

        guard flavor.sourceIdentifier == sourceIdentifier else {
            return (
                .stale,
                flavor,
                nil,
                CinematicRunRecapFlavor.TitleSource.deterministic.rawValue
            )
        }

        guard flavor.titleSource == .generated else {
            return (
                .deterministic,
                flavor,
                nil,
                CinematicRunRecapFlavor.TitleSource.deterministic.rawValue
            )
        }

        return (
            .applied,
            flavor,
            flavor,
            flavor.titleSource.rawValue
        )
    }

    private static func normalizedSourceIdentifier(_ value: String) -> String {
        let normalized = normalizedText(value)
        return normalized.isEmpty ? "source:unknown" : normalized
    }

    private static func normalizedIdentifierComponent(_ value: String, fallback: String) -> String {
        let normalized = normalizedText(value)
            .lowercased()
            .map { character -> Character in
                if character.isLetter || character.isNumber || character == "-" || character == "_" || character == "." {
                    return character
                }
                return "-"
            }
        let collapsed = String(normalized)
            .replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return collapsed.isEmpty ? fallback : collapsed
    }

    private static func copyIdentifier(_ values: String...) -> String {
        values.map(normalizedText).joined(separator: "/")
    }

    private static func normalizedText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum CinematicRunRecapFlavorApplication: String, Equatable {
    case applied
    case deterministic
    case stale
}

struct CinematicRunRecapFlavorInput: Equatable, Sendable {
    var sourceIdentifier: String
    var sessionNumber: Int
    var statusIdentifier: String
    var statusCopy: String
    var deterministicTitle: String
    var deterministicDetail: String
    var latestCompletedSummary: String
    var newestCommitHighlight: String?
    var commitHighlightCount: Int
    var completedCount: Int
    var eventSummaries: [String]
}

struct CinematicRunRecapFlavor: Equatable, Sendable {
    static let titleMaxCharacters = 58
    static let detailMaxCharacters = 118
    static let titleMaxWords = 8
    static let detailMaxWords = 20
    static let tokenMaxCharacters = 84

    var identifier: String
    var sourceIdentifier: String
    var tokenIdentifier: String
    var title: String
    var detail: String
    var titleSource: TitleSource

    var titleSourceIdentifier: String { titleSource.rawValue }

    enum TitleSource: String, Equatable, Sendable {
        case deterministic
        case generated
    }

    init(
        sourceIdentifier: String,
        title: String,
        detail: String,
        titleSource: TitleSource
    ) {
        let cleanTitle = CinematicRunRecapFlavorService.fittedPlainText(
            title,
            maxCharacters: Self.titleMaxCharacters
        )
        let cleanDetail = CinematicRunRecapFlavorService.fittedPlainText(
            detail,
            maxCharacters: Self.detailMaxCharacters
        )
        let token = CinematicRunRecapFlavorService.tokenIdentifier(
            title: cleanTitle,
            detail: cleanDetail,
            titleSource: titleSource
        )
        self.sourceIdentifier = sourceIdentifier
        self.title = cleanTitle
        self.detail = cleanDetail
        self.titleSource = titleSource
        self.tokenIdentifier = token
        self.identifier = [
            "run-recap-flavor",
            "source:\(CinematicRunRecapFlavorService.sourceToken(sourceIdentifier))",
            "title-source:\(titleSource.rawValue)",
            "copy:\(token)"
        ].joined(separator: "|")
    }
}

enum CinematicRunRecapFlavorService {
    static func makeFlavor(input: CinematicRunRecapFlavorInput) async -> CinematicRunRecapFlavor {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if let generated = try? await FoundationModelCinematicRunRecapFlavorGenerator.generate(input: input) {
                return generated
            }
        }
        #endif

        return deterministicFlavor(for: input)
    }

    static func deterministicFlavor(for input: CinematicRunRecapFlavorInput) -> CinematicRunRecapFlavor {
        CinematicRunRecapFlavor(
            sourceIdentifier: input.sourceIdentifier,
            title: input.deterministicTitle,
            detail: input.deterministicDetail,
            titleSource: .deterministic
        )
    }

    static func parseGeneratedFlavor(
        _ raw: String,
        sourceIdentifier: String
    ) -> CinematicRunRecapFlavor? {
        let lines = raw
            .replacingOccurrences(of: "\r", with: "\n")
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard lines.count == 2 else { return nil }

        var title: String?
        var detail: String?
        for line in lines {
            let lowercased = line.lowercased()
            if lowercased.hasPrefix("title:") {
                guard title == nil else { return nil }
                title = stripLabel(from: line)
            } else if lowercased.hasPrefix("detail:") {
                guard detail == nil else { return nil }
                detail = stripLabel(from: line)
            } else {
                return nil
            }
        }

        guard let title, let detail else { return nil }
        return validateGenerated(
            title: title,
            detail: detail,
            sourceIdentifier: sourceIdentifier
        )
    }

    static func fittedPlainText(_ text: String, maxCharacters: Int) -> String {
        let normalized = normalizePlainText(text)
        guard normalized.count > maxCharacters else { return normalized }

        let prefix = normalized.prefix(maxCharacters)
        if let lastSpace = prefix.lastIndex(where: { $0 == " " }), lastSpace > prefix.startIndex {
            return String(prefix[..<lastSpace]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(prefix).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func tokenIdentifier(
        title: String,
        detail: String,
        titleSource: CinematicRunRecapFlavor.TitleSource
    ) -> String {
        boundedIdentifierComponent(
            [
                titleSource.rawValue,
                title,
                detail
            ].joined(separator: "-"),
            fallback: titleSource.rawValue,
            limit: CinematicRunRecapFlavor.tokenMaxCharacters
        )
    }

    static func sourceToken(_ sourceIdentifier: String) -> String {
        boundedIdentifierComponent(sourceIdentifier, fallback: "source", limit: 96)
    }

    private static func validateGenerated(
        title: String,
        detail: String,
        sourceIdentifier: String
    ) -> CinematicRunRecapFlavor? {
        let cleanTitle = normalizeGeneratedText(title)
        let cleanDetail = normalizeGeneratedText(detail)

        guard (4...CinematicRunRecapFlavor.titleMaxCharacters).contains(cleanTitle.count),
              (8...CinematicRunRecapFlavor.detailMaxCharacters).contains(cleanDetail.count),
              wordCount(cleanTitle) <= CinematicRunRecapFlavor.titleMaxWords,
              wordCount(cleanDetail) <= CinematicRunRecapFlavor.detailMaxWords,
              cleanTitle != cleanDetail,
              isUsableGeneratedText(cleanTitle),
              isUsableGeneratedText(cleanDetail) else {
            return nil
        }

        return CinematicRunRecapFlavor(
            sourceIdentifier: sourceIdentifier,
            title: cleanTitle,
            detail: cleanDetail,
            titleSource: .generated
        )
    }

    private static func stripLabel(from line: String) -> String {
        guard let colon = line.firstIndex(of: ":") else { return line }
        return String(line[line.index(after: colon)...])
    }

    private static func normalizeGeneratedText(_ text: String) -> String {
        normalizePlainText(text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizePlainText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    private static func isUsableGeneratedText(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        let disallowedScalars = CharacterSet(charactersIn: "\"'“”‘’`{}[]#*")
        guard text.rangeOfCharacter(from: disallowedScalars) == nil,
              !lowercased.contains("http://"),
              !lowercased.contains("https://"),
              !lowercased.contains("www."),
              !lowercased.contains("```"),
              !lowercased.contains("title:"),
              !lowercased.contains("detail:"),
              !lowercased.contains("json"),
              !lowercased.contains("rm -rf"),
              !lowercased.contains("sudo "),
              !lowercased.contains("password"),
              !lowercased.contains("secret"),
              !lowercased.contains("api key"),
              !lowercased.contains("private key") else {
            return false
        }
        return true
    }

    private static func boundedIdentifierComponent(
        _ value: String,
        fallback: String,
        limit: Int
    ) -> String {
        let normalized = normalizePlainText(value)
            .lowercased()
            .map { character -> Character in
                if character.isLetter || character.isNumber || character == "-" || character == "_" || character == "." {
                    return character
                }
                return "-"
            }
        let collapsed = String(normalized)
            .replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let candidate = collapsed.isEmpty ? fallback : collapsed
        guard candidate.count > limit else { return candidate }
        return String(candidate.prefix(limit))
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
private enum FoundationModelCinematicRunRecapFlavorGenerator {
    static func generate(input: CinematicRunRecapFlavorInput) async throws -> CinematicRunRecapFlavor? {
        let model = SystemLanguageModel.default
        guard model.isAvailable else { return nil }

        let session = LanguageModelSession(instructions: """
        You write bounded cinematic recap copy for a macOS software factory after a terminal agent run.
        Return exactly two plain-text lines in this format:
        Title: ...
        Detail: ...
        Use only the supplied status, completed summary, commit highlight, counts, and event summaries.
        Do not invent files, outcomes, people, metrics, commands, markdown, URLs, JSON, code, bullets, or quotes.
        """)

        let response = try await session.respond(
            to: """
            Source identifier: \(input.sourceIdentifier)
            Session: \(input.sessionNumber)
            Status: \(input.statusCopy)
            Deterministic title: \(input.deterministicTitle)
            Deterministic detail: \(input.deterministicDetail)
            Latest completed summary: \(input.latestCompletedSummary)
            Latest commit highlight: \(input.newestCommitHighlight ?? "none")
            Commit highlight count: \(input.commitHighlightCount)
            Completed count: \(input.completedCount)
            Event summaries: \(input.eventSummaries.isEmpty ? "none" : input.eventSummaries.joined(separator: " | "))

            Title under \(CinematicRunRecapFlavor.titleMaxWords) words.
            Detail under \(CinematicRunRecapFlavor.detailMaxWords) words.
            """,
            options: GenerationOptions(temperature: 0.45, maximumResponseTokens: 70)
        )

        return CinematicRunRecapFlavorService.parseGeneratedFlavor(
            response.content,
            sourceIdentifier: input.sourceIdentifier
        )
    }
}
#endif

enum CinematicRunRecapPlanner {
    static func plan(
        state: PlanState,
        sessions: [SessionRecord],
        isRunning: Bool,
        isAutoPlaying: Bool,
        recentRunCues: [Int: PlanReliabilityFeedback.RunCue],
        commitConstellationPlan: CinematicCommitConstellationPlan,
        nativeFeedbackLifecycle: CinematicNativeFeedbackCueLifecycle,
        flavor: CinematicRunRecapFlavor? = nil
    ) -> CinematicRunRecapPlan {
        guard !isRunning && !isAutoPlaying else {
            return .empty(reason: "active-run")
        }

        guard let session = latestFinishedSession(in: sessions) else {
            return .empty(reason: "no-finished-session")
        }

        let latestCompletedSummary = state.completed.last.map {
            CinematicRunRecapPlan.boundedText(
                $0,
                limit: CinematicRunRecapPlan.completedSummaryLimit
            )
        } ?? "No completed plan items recorded."
        let eventChips = eventChips(
            recentRunCues: recentRunCues,
            nativeFeedbackLifecycle: nativeFeedbackLifecycle
        )

        return .available(
            session: session,
            latestCompletedSummary: latestCompletedSummary,
            newestCommitHighlight: commitConstellationPlan.newestSubject,
            commitHighlightCount: commitConstellationPlan.count,
            completedCount: state.completed.count,
            eventChips: eventChips,
            flavor: flavor
        )
    }

    static func flavorInput(
        state: PlanState,
        sessions: [SessionRecord],
        isRunning: Bool,
        isAutoPlaying: Bool,
        recentRunCues: [Int: PlanReliabilityFeedback.RunCue],
        commitConstellationPlan: CinematicCommitConstellationPlan,
        nativeFeedbackLifecycle: CinematicNativeFeedbackCueLifecycle
    ) -> CinematicRunRecapFlavorInput? {
        guard !isRunning && !isAutoPlaying,
              let session = latestFinishedSession(in: sessions) else {
            return nil
        }

        let latestCompletedSummary = state.completed.last.map {
            CinematicRunRecapPlan.boundedText(
                $0,
                limit: CinematicRunRecapPlan.completedSummaryLimit
            )
        } ?? "No completed plan items recorded."
        let newestCommitHighlight = commitConstellationPlan.newestSubject.map {
            CinematicRunRecapPlan.boundedText(
                $0,
                limit: CinematicRunRecapPlan.commitHighlightLimit
            )
        }
        let boundedEventChips = Array(
            eventChips(
                recentRunCues: recentRunCues,
                nativeFeedbackLifecycle: nativeFeedbackLifecycle
            )
            .prefix(CinematicRunRecapPlan.eventChipLimit)
        )
        let statusCopy = CinematicRunRecapPlan.statusText(for: session.status)
        let deterministicTitle = CinematicRunRecapPlan.boundedText(
            "Run #\(session.session) \(statusCopy.lowercased())",
            limit: CinematicRunRecapPlan.titleLimit
        )
        let deterministicDetail = CinematicRunRecapPlan.boundedText(
            latestCompletedSummary,
            limit: CinematicRunRecapPlan.detailLimit
        )
        let sourceIdentifier = CinematicRunRecapPlan.recapSourceIdentifier(
            session: session,
            latestCompletedSummary: latestCompletedSummary,
            newestCommitHighlight: newestCommitHighlight,
            commitHighlightCount: commitConstellationPlan.count,
            completedCount: state.completed.count,
            eventChipIdentifiers: boundedEventChips.map(\.identifier)
        )

        return CinematicRunRecapFlavorInput(
            sourceIdentifier: sourceIdentifier,
            sessionNumber: session.session,
            statusIdentifier: session.status.rawValue,
            statusCopy: statusCopy,
            deterministicTitle: deterministicTitle,
            deterministicDetail: deterministicDetail,
            latestCompletedSummary: latestCompletedSummary,
            newestCommitHighlight: newestCommitHighlight,
            commitHighlightCount: commitConstellationPlan.count,
            completedCount: state.completed.count,
            eventSummaries: boundedEventChips.map {
                "\($0.label): \($0.detail)"
            }
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

    private static func eventChips(
        recentRunCues: [Int: PlanReliabilityFeedback.RunCue],
        nativeFeedbackLifecycle: CinematicNativeFeedbackCueLifecycle
    ) -> [CinematicRunRecapPlan.EventChip] {
        let runCueChips = recentRunCues
            .map { sessionNumber, cue in
                RunCueEntry(sessionNumber: sessionNumber, cue: cue)
            }
            .sorted(by: earlierRunCueEntry)
            .map(runCueChip)
        let nativeChips = nativeFeedbackHistoryChips(nativeFeedbackLifecycle)
        return Array((runCueChips + nativeChips).prefix(CinematicRunRecapPlan.eventChipLimit))
    }

    private struct RunCueEntry {
        var sessionNumber: Int
        var cue: PlanReliabilityFeedback.RunCue
    }

    private static func earlierRunCueEntry(_ lhs: RunCueEntry, _ rhs: RunCueEntry) -> Bool {
        let leftPriority = PlanReliabilityFeedback.priority(for: lhs.cue.kind)
        let rightPriority = PlanReliabilityFeedback.priority(for: rhs.cue.kind)
        if leftPriority != rightPriority {
            return leftPriority < rightPriority
        }
        if lhs.cue.severity != rhs.cue.severity {
            return severityPriority(lhs.cue.severity) < severityPriority(rhs.cue.severity)
        }
        return lhs.sessionNumber > rhs.sessionNumber
    }

    private static func runCueChip(
        _ entry: RunCueEntry
    ) -> CinematicRunRecapPlan.EventChip {
        CinematicRunRecapPlan.eventChip(
            sourceIdentifier: "run-cue:\(entry.sessionNumber):\(entry.cue.kind.rawValue)",
            label: entry.cue.label,
            detail: entry.cue.detail,
            systemImage: entry.cue.systemImage,
            styleIdentifier: entry.cue.severity.rawValue,
            colorIdentifier: colorIdentifier(for: entry.cue.severity)
        )
    }

    private static func nativeFeedbackHistoryChips(
        _ lifecycle: CinematicNativeFeedbackCueLifecycle
    ) -> [CinematicRunRecapPlan.EventChip] {
        let activeChips = lifecycle.active.map { active in
            [
                CinematicRunRecapPlan.eventChip(
                    sourceIdentifier: "native-feedback:active:\(active.metadata.sequence):\(active.cue.milestoneIdentifier)",
                    label: active.cue.title,
                    detail: active.cue.detail,
                    systemImage: active.cue.systemImage,
                    styleIdentifier: active.cue.styleIdentifier,
                    colorIdentifier: active.cue.colorIdentifier
                )
            ]
        } ?? []

        let archiveChips = lifecycle.recentArchive.map { archived in
            CinematicRunRecapPlan.eventChip(
                sourceIdentifier: "native-feedback:archived:\(archived.sequence):\(archived.archiveReason.rawValue):\(archived.milestoneIdentifier)",
                label: "Feedback \(displayMilestone(archived.milestoneIdentifier))",
                detail: [
                    "archived/\(archived.archiveReason.rawValue)",
                    archived.sourceIdentifier
                ].filter { !$0.isEmpty }.joined(separator: " - "),
                systemImage: systemImage(forMilestone: archived.milestoneIdentifier),
                styleIdentifier: archived.styleIdentifier,
                colorIdentifier: colorIdentifier(forStyle: archived.styleIdentifier)
            )
        }

        return activeChips + archiveChips
    }

    private static func severityPriority(_ severity: PlanReliabilityFeedback.Severity) -> Int {
        switch severity {
        case .failure:
            return 0
        case .warning:
            return 1
        case .paused:
            return 2
        }
    }

    private static func colorIdentifier(for severity: PlanReliabilityFeedback.Severity) -> String {
        switch severity {
        case .failure:
            return "red"
        case .warning:
            return "orange"
        case .paused:
            return "blue"
        }
    }

    private static func colorIdentifier(forStyle styleIdentifier: String) -> String {
        switch styleIdentifier {
        case "success":
            return "green"
        case "warning":
            return "orange"
        case "failure":
            return "red"
        case "paused":
            return "blue"
        case "plan":
            return "indigo"
        case "develop":
            return "cyan"
        case "verify":
            return "yellow"
        default:
            return "secondary"
        }
    }

    private static func displayMilestone(_ milestoneIdentifier: String) -> String {
        let spaced = milestoneIdentifier.reduce(into: "") { result, character in
            if character.isUppercase && !result.isEmpty {
                result.append(" ")
            }
            result.append(character)
        }
        return spaced.capitalized
    }

    private static func systemImage(forMilestone milestoneIdentifier: String) -> String {
        switch milestoneIdentifier {
        case NativeFeedbackMilestone.planAccepted.rawValue:
            return "map.fill"
        case NativeFeedbackMilestone.developReady.rawValue:
            return "checkmark.seal.fill"
        case NativeFeedbackMilestone.developStarted.rawValue:
            return "hammer.fill"
        case NativeFeedbackMilestone.verifyStarted.rawValue:
            return "checkmark.seal"
        case NativeFeedbackMilestone.verifyPassed.rawValue:
            return "checkmark.circle.fill"
        case NativeFeedbackMilestone.developRetrying.rawValue:
            return "arrow.clockwise.circle.fill"
        case NativeFeedbackMilestone.postChecksFailed.rawValue:
            return "exclamationmark.triangle.fill"
        case NativeFeedbackMilestone.commitsPromoted.rawValue:
            return "arrow.triangle.branch"
        case NativeFeedbackMilestone.paused.rawValue:
            return "pause.circle.fill"
        case NativeFeedbackMilestone.stopped.rawValue:
            return "stop.circle.fill"
        case NativeFeedbackMilestone.noImmediateWork.rawValue:
            return "clock.badge.questionmark"
        default:
            return "circle.fill"
        }
    }
}
