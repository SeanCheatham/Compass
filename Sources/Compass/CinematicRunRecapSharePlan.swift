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
