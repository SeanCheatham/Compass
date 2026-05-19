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
    var runtimeRouteAudit: CinematicRunRecapShareArtifactRuntimeRouteAudit?
    var mutationTestingAudit: CinematicRunRecapShareArtifactMutationTestingAudit?
    var warningPulseAudit: CinematicRunRecapShareArtifactWarningPulseAudit?
    var markdownContents: String
    var feedback: String

    var eventSummaryCount: Int { eventSummaries.count }
    var visualDescriptorTokenCount: Int { visualDescriptorTokens.count }
    var markdownLength: Int { markdownContents.count }
}

struct CinematicRunRecapShareArtifactWarningPulseAudit: Equatable, Identifiable {
    static let identifierMaxCharacters = CinematicRunRecapShareArtifactPlan.identifierMaxCharacters
    static let markdownMaxCharacters = 1_200
    static let fieldMaxCharacters = CinematicDiagnosticsWarningBundleHistory.identifierMaxCharacters
    static let warningIdentifierLimit = CinematicDiagnosticsWarningBundleHistory.visibleWarningIdentifierLimit
    static let anchorLimit = CinematicDiagnosticsWarningBundleHistory.visibleAnchorLimit

    var id: String { identifier }

    var identifier: String
    var stateIdentifier: String
    var quietingStatusIdentifier: String
    var bundleIdentifier: String
    var sequence: Int
    var captureCount: Int
    var targetCount: Int
    var warningCount: Int
    var warningIdentifiers: [String]
    var omittedWarningIdentifierCount: Int
    var targetAnchors: [String]
    var omittedTargetAnchorCount: Int
    var relatedRowAnchors: [String]
    var omittedRelatedRowAnchorCount: Int
    var markdownSection: String

    var markdownLength: Int { markdownSection.count }
    var totalOmittedCount: Int {
        omittedWarningIdentifierCount + omittedTargetAnchorCount + omittedRelatedRowAnchorCount
    }

    init(
        entry: CinematicDiagnosticsWarningBundleHistory.Entry,
        status: CinematicDiagnosticsWarningPulseQuietingStatusDescriptor
    ) {
        let bundleIdentifier = Self.safeToken(entry.bundleIdentifier)
        let stateIdentifier = status.stateIdentifier == "snoozed" ? "snoozed" : "active"
        let quietingStatusIdentifier = Self.safeToken(status.id)
        let warningIdentifiers = Self.visibleTokens(
            entry.warningIdentifiers,
            limit: Self.warningIdentifierLimit
        )
        let targetAnchors = Self.visibleTokens(
            entry.targetAnchors,
            limit: Self.anchorLimit
        )
        let relatedRowAnchors = Self.visibleTokens(
            entry.relatedRowAnchors,
            limit: Self.anchorLimit
        )
        let sequence = max(0, entry.sequence)
        let captureCount = max(0, entry.captureCount)
        let targetCount = max(0, entry.targetCount)
        let warningCount = max(0, entry.warningCount)
        let omittedWarningIdentifierCount = max(0, entry.warningIdentifiers.count - warningIdentifiers.count)
        let omittedTargetAnchorCount = max(0, entry.targetAnchors.count - targetAnchors.count)
        let omittedRelatedRowAnchorCount = max(0, entry.relatedRowAnchors.count - relatedRowAnchors.count)
        let totalOmittedCount = omittedWarningIdentifierCount
            + omittedTargetAnchorCount
            + omittedRelatedRowAnchorCount
        let identifier = Self.bounded(
            [
                "run-recap-share-artifact-warning-pulse",
                "state:\(stateIdentifier)",
                "bundle:\(bundleIdentifier)",
                "sequence:\(sequence)",
                "captures:\(captureCount)",
                "targets:\(targetCount)",
                "warnings:\(warningCount)",
                "warning-ids:\(Self.fingerprint(warningIdentifiers.joined(separator: "|")))",
                "target-anchors:\(Self.fingerprint(targetAnchors.joined(separator: "|")))",
                "related-rows:\(Self.fingerprint(relatedRowAnchors.joined(separator: "|")))",
                "omitted:\(totalOmittedCount)"
            ].joined(separator: "|"),
            limit: Self.identifierMaxCharacters
        )
        let markdownSection = Self.boundedArtifactText(
            [
                "## Diagnostics Warning Pulse",
                "",
                "- Warning pulse audit: \(identifier)",
                "- State: \(stateIdentifier)",
                "- Bundle: \(bundleIdentifier)",
                "- Quieting status: \(quietingStatusIdentifier)",
                "- Sequence: \(sequence)",
                "- Capture count: \(captureCount)",
                "- Target count: \(targetCount)",
                "- Warning count: \(warningCount)",
                "- Warning identifiers: \(Self.identifierList(warningIdentifiers))",
                "- Omitted warning identifiers: \(omittedWarningIdentifierCount)",
                "- Target anchors: \(Self.identifierList(targetAnchors))",
                "- Omitted target anchors: \(omittedTargetAnchorCount)",
                "- Related rows: \(Self.identifierList(relatedRowAnchors))",
                "- Omitted related rows: \(omittedRelatedRowAnchorCount)",
                "- Copy safety: notification-body-free; target-text-free; read-only"
            ].joined(separator: "\n"),
            limit: Self.markdownMaxCharacters
        )

        self.identifier = identifier
        self.stateIdentifier = stateIdentifier
        self.quietingStatusIdentifier = quietingStatusIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.sequence = sequence
        self.captureCount = captureCount
        self.targetCount = targetCount
        self.warningCount = warningCount
        self.warningIdentifiers = warningIdentifiers
        self.omittedWarningIdentifierCount = omittedWarningIdentifierCount
        self.targetAnchors = targetAnchors
        self.omittedTargetAnchorCount = omittedTargetAnchorCount
        self.relatedRowAnchors = relatedRowAnchors
        self.omittedRelatedRowAnchorCount = omittedRelatedRowAnchorCount
        self.markdownSection = markdownSection
    }

    private static func visibleTokens(_ values: [String], limit: Int) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let token = safeToken(value)
            guard !token.isEmpty, !seen.contains(token) else { continue }
            seen.insert(token)
            result.append(token)
            if result.count >= max(0, limit) {
                break
            }
        }
        return result
    }

    private static func identifierList(_ values: [String]) -> String {
        values.isEmpty ? "none" : values.joined(separator: ", ")
    }

    private static func safeToken(_ text: String) -> String {
        bounded(text, limit: Self.fieldMaxCharacters)
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

struct CinematicRunRecapShareArtifactMutationTestingAudit: Equatable, Identifiable {
    static let identifierMaxCharacters = CinematicRunRecapShareArtifactPlan.identifierMaxCharacters
    static let markdownMaxCharacters = 1_200
    static let fieldMaxCharacters = SessionMutationTestingExecution.fieldLimit
    static let commandMaxCharacters = SessionMutationTestingExecution.commandLimit
    static let tailSummaryMaxCharacters = 360
    static let tailLineLimit = 5

    var id: String { identifier }

    var identifier: String
    var statusIdentifier: String
    var statusLabel: String
    var routeIdentifier: String
    var routeLabel: String
    var languageIdentifier: String
    var languageLabel: String
    var seedCommandLabel: String
    var exitCodeLabel: String
    var durationLabel: String
    var tailSummary: String
    var runtimeRouteAuditIdentifier: String
    var runtimeRouteCorrelationIdentifier: String
    var markdownSection: String

    var markdownLength: Int { markdownSection.count }

    init?(
        execution: SessionMutationTestingExecution?,
        runtimeRouteAudit: CinematicRunRecapShareArtifactRuntimeRouteAudit?
    ) {
        guard let execution else { return nil }

        let statusIdentifier = MutationTestingPresentationSanitizer.statusIdentifier(
            execution.statusIdentifier
        )
        let statusLabel = MutationTestingPresentationSanitizer.statusLabel(statusIdentifier)
        let routeIdentifier = MutationTestingPresentationSanitizer.routeIdentifier(
            execution.routeIdentifier
        )
        let routeLabel = MutationTestingPresentationSanitizer.routeLabel(routeIdentifier)
        let languageIdentifier = MutationTestingPresentationSanitizer.languageIdentifier(
            execution.languageIdentifier
        )
        let languageLabel = MutationTestingPresentationSanitizer.languageLabel(languageIdentifier)
        let seedCommandLabel = MutationTestingPresentationSanitizer.field(
            execution.seedCommandLabel,
            limit: Self.commandMaxCharacters
        )
        let exitCodeLabel = MutationTestingPresentationSanitizer.exitCodeLabel(execution.exitCode)
        let durationLabel = MutationTestingPresentationSanitizer.durationLabel(
            startedAt: execution.startedAt,
            endedAt: execution.endedAt
        )
        let tailSummary = MutationTestingPresentationSanitizer.outputTail(
            execution.outputTail,
            limit: Self.tailSummaryMaxCharacters,
            lineLimit: Self.tailLineLimit
        )
        let tailSummaryMarkdown = MutationTestingPresentationSanitizer.field(
            tailSummary,
            limit: Self.tailSummaryMaxCharacters
        )
        let runtimeRouteAuditIdentifier = MutationTestingPresentationSanitizer.field(
            runtimeRouteAudit?.identifier ?? "none",
            limit: CinematicRunRecapShareArtifactRuntimeRouteAudit.identifierMaxCharacters
        )
        let runtimeRouteCorrelationIdentifier = Self.runtimeRouteCorrelationIdentifier(
            mutationRouteIdentifier: routeIdentifier,
            runtimeRouteAudit: runtimeRouteAudit
        )
        let identifier = MutationTestingPresentationSanitizer.bounded(
            [
                "run-recap-share-artifact-mutation-testing",
                "status:\(statusIdentifier)",
                "route:\(routeIdentifier)",
                "language:\(languageIdentifier)",
                "seed:\(MutationTestingPresentationSanitizer.fingerprint(seedCommandLabel))",
                "exit:\(exitCodeLabel)",
                "duration:\(durationLabel)",
                "tail:\(MutationTestingPresentationSanitizer.fingerprint(tailSummary))",
                "runtime:\(MutationTestingPresentationSanitizer.fingerprint(runtimeRouteAuditIdentifier))",
                "correlation:\(runtimeRouteCorrelationIdentifier)"
            ].joined(separator: "|"),
            limit: Self.identifierMaxCharacters
        )
        let markdownSection = MutationTestingPresentationSanitizer.markdownSection(
            [
                "## Mutation Tests",
                "",
                "- Mutation audit: \(identifier)",
                "- Status: \(statusIdentifier) (\(statusLabel))",
                "- Route: \(routeIdentifier) (\(routeLabel))",
                "- Language: \(languageIdentifier) (\(languageLabel))",
                "- Seed command: \(seedCommandLabel)",
                "- Exit code: \(exitCodeLabel)",
                "- Duration: \(durationLabel)",
                "- Runtime route audit: \(runtimeRouteAuditIdentifier)",
                "- Runtime route correlation: \(runtimeRouteCorrelationIdentifier)",
                "- Output tail: \(tailSummaryMarkdown.isEmpty ? "none" : tailSummaryMarkdown)"
            ].joined(separator: "\n"),
            limit: Self.markdownMaxCharacters
        )

        self.identifier = identifier
        self.statusIdentifier = statusIdentifier
        self.statusLabel = statusLabel
        self.routeIdentifier = routeIdentifier
        self.routeLabel = routeLabel
        self.languageIdentifier = languageIdentifier
        self.languageLabel = languageLabel
        self.seedCommandLabel = seedCommandLabel
        self.exitCodeLabel = exitCodeLabel
        self.durationLabel = durationLabel
        self.tailSummary = tailSummary
        self.runtimeRouteAuditIdentifier = runtimeRouteAuditIdentifier
        self.runtimeRouteCorrelationIdentifier = runtimeRouteCorrelationIdentifier
        self.markdownSection = markdownSection
    }

    private static func runtimeRouteCorrelationIdentifier(
        mutationRouteIdentifier: String,
        runtimeRouteAudit: CinematicRunRecapShareArtifactRuntimeRouteAudit?
    ) -> String {
        guard let runtimeRouteAudit else {
            return "missing-runtime-route"
        }
        let expectedRuntimeRoute: String
        switch mutationRouteIdentifier {
        case CodexMutationTestingPlan.RouteState.appleContainerRoute.rawValue:
            expectedRuntimeRoute = "apple-container"
        case CodexMutationTestingPlan.RouteState.nativeRoute.rawValue,
            CodexMutationTestingPlan.RouteState.nativeFallback.rawValue:
            expectedRuntimeRoute = "native-macos"
        default:
            expectedRuntimeRoute = "unknown"
        }

        let routeState = runtimeRouteAudit.effectiveRouteIdentifier == expectedRuntimeRoute
            ? "route-aligned"
            : "route-diverged"
        let fallbackState: String
        if mutationRouteIdentifier == CodexMutationTestingPlan.RouteState.nativeFallback.rawValue {
            fallbackState = runtimeRouteAudit.fallbackStateIdentifier == "fallback"
                ? "fallback-aligned"
                : "fallback-missing"
        } else {
            fallbackState = "fallback-not-required"
        }

        return MutationTestingPresentationSanitizer.identifier(
            [
                routeState,
                fallbackState,
                "mutation:\(mutationRouteIdentifier)",
                "runtime:\(runtimeRouteAudit.effectiveRouteIdentifier)"
            ].joined(separator: "|"),
            fallback: "runtime-route-correlation",
            limit: Self.fieldMaxCharacters
        )
    }
}

struct CinematicRunRecapShareArtifactRuntimeRouteAudit: Equatable, Identifiable {
    static let identifierMaxCharacters = CinematicRunRecapShareArtifactPlan.identifierMaxCharacters
    static let markdownMaxCharacters = 1_200
    static let fieldMaxCharacters = SessionExecutionEnvironmentSnapshot.fieldLimit
    static let phaseMaxCharacters = SessionExecutionEnvironmentSnapshot.phaseLimit
    static let tokenMaxCharacters = CodexDevcontainerSupportReport.tokenLimit
    static let tokenLimit = CodexDevcontainerSupportReport.maxTokenCount

    var id: String { identifier }

    var identifier: String
    var phase: String
    var phaseIdentifier: String
    var attemptLabel: String
    var selectedPreferenceIdentifier: String
    var selectedPreferenceTitle: String
    var effectiveRouteIdentifier: String
    var effectiveRouteTitle: String
    var supportClassificationIdentifier: String
    var visibleSupportTokens: [String]
    var omittedSupportTokenCount: Int
    var imageLabel: String
    var workspaceLabel: String
    var fallbackStateIdentifier: String
    var fallbackReason: String
    var provisioningAvailabilityIdentifier: String
    var provisioningStatusIdentifier: String
    var provisioningActionIdentifier: String
    var markdownSection: String

    var markdownLength: Int { markdownSection.count }

    init?(snapshot: SessionExecutionEnvironmentSnapshot?) {
        guard let snapshot else { return nil }

        let phase = Self.sanitizedField(
            snapshot.phase,
            limit: Self.phaseMaxCharacters,
            fallback: "phase"
        )
        let phaseIdentifier = Self.sanitizedIdentifier(
            snapshot.phaseIdentifier,
            fallback: "phase",
            limit: Self.phaseMaxCharacters
        )
        let attemptLabel = snapshot.attempt.map { max(1, $0).description } ?? "none"
        let selectedPreferenceIdentifier = Self.sanitizedIdentifier(
            snapshot.selectedPreferenceIdentifier,
            fallback: "unknown",
            limit: Self.fieldMaxCharacters
        )
        let selectedPreferenceTitle = Self.title(
            identifier: selectedPreferenceIdentifier,
            fallback: snapshot.selectedPreferenceTitle,
            knownTitles: [
                CodexExecutionEnvironmentPreference.nativeMacOS.rawValue:
                    CodexExecutionEnvironmentPreference.nativeMacOS.title,
                CodexExecutionEnvironmentPreference.devcontainerPreferred.rawValue:
                    CodexExecutionEnvironmentPreference.devcontainerPreferred.title
            ],
            defaultTitle: "Unknown"
        )
        let effectiveRouteIdentifier = Self.sanitizedIdentifier(
            snapshot.effectiveRouteIdentifier,
            fallback: "unknown",
            limit: Self.fieldMaxCharacters
        )
        let effectiveRouteTitle = Self.title(
            identifier: effectiveRouteIdentifier,
            fallback: snapshot.effectiveRouteTitle,
            knownTitles: [
                "apple-container": "Apple container",
                "native-macos": "Native macOS"
            ],
            defaultTitle: "Unknown route"
        )
        let supportClassificationIdentifier = Self.sanitizedIdentifier(
            snapshot.supportClassificationIdentifier,
            fallback: "not-inspected",
            limit: Self.fieldMaxCharacters
        )
        let visibleSupportTokens = Array(
            snapshot.visibleSupportTokens
                .map(Self.sanitizedSupportToken)
                .filter { !$0.isEmpty }
                .prefix(Self.tokenLimit)
        )
        let omittedSupportTokenCount = max(0, snapshot.omittedSupportTokenCount)
        let imageLabel = Self.sanitizedField(
            snapshot.imageLabel,
            limit: Self.fieldMaxCharacters,
            fallback: "none"
        )
        let workspaceLabel = Self.sanitizedField(
            snapshot.workspaceLabel,
            limit: Self.fieldMaxCharacters,
            fallback: "none"
        )
        let fallbackReason = Self.sanitizedField(
            snapshot.fallbackReason ?? "none",
            limit: CodexExecutionLaunchPlan.fallbackReasonLimit,
            fallback: "none"
        )
        let fallbackStateIdentifier = fallbackReason == "none" ? "direct" : "fallback"
        let provisioningAvailabilityIdentifier = Self.sanitizedIdentifier(
            snapshot.provisioningAvailabilityIdentifier ?? "none",
            fallback: "none",
            limit: Self.fieldMaxCharacters
        )
        let provisioningStatusIdentifier = Self.sanitizedIdentifier(
            snapshot.provisioningStatusIdentifier ?? "none",
            fallback: "none",
            limit: Self.fieldMaxCharacters
        )
        let provisioningActionIdentifier = Self.sanitizedIdentifier(
            snapshot.provisioningActionIdentifier ?? "none",
            fallback: "none",
            limit: Self.fieldMaxCharacters
        )
        let identifier = Self.bounded(
            [
                "run-recap-share-artifact-runtime-route",
                "phase:\(phaseIdentifier)",
                "attempt:\(attemptLabel)",
                "preference:\(selectedPreferenceIdentifier)",
                "route:\(effectiveRouteIdentifier)",
                "support:\(supportClassificationIdentifier)",
                "tokens:\(Self.fingerprint(visibleSupportTokens.joined(separator: "|")))",
                "omitted:\(omittedSupportTokenCount)",
                "image:\(Self.fingerprint(imageLabel))",
                "workspace:\(Self.fingerprint(workspaceLabel))",
                "fallback:\(fallbackStateIdentifier)",
                "provisioning:\(provisioningAvailabilityIdentifier).\(provisioningStatusIdentifier).\(provisioningActionIdentifier)"
            ].joined(separator: "|"),
            limit: Self.identifierMaxCharacters
        )
        let tokenText = visibleSupportTokens.isEmpty ? "none" : visibleSupportTokens.joined(separator: ", ")
        let markdownSection = Self.boundedArtifactText(
            [
                "## Runtime Route",
                "",
                "- Runtime audit: \(identifier)",
                "- Phase: \(phase) (\(phaseIdentifier))",
                "- Attempt: \(attemptLabel)",
                "- Selected preference: \(selectedPreferenceIdentifier) (\(selectedPreferenceTitle))",
                "- Effective route: \(effectiveRouteIdentifier) (\(effectiveRouteTitle))",
                "- Support classification: \(supportClassificationIdentifier)",
                "- Visible support tokens: \(tokenText)",
                "- Omitted support tokens: \(omittedSupportTokenCount)",
                "- Image label: \(imageLabel)",
                "- Workspace label: \(workspaceLabel)",
                "- Fallback state: \(fallbackStateIdentifier)",
                "- Fallback reason: \(fallbackReason)",
                "- Provisioning availability: \(provisioningAvailabilityIdentifier)",
                "- Provisioning status: \(provisioningStatusIdentifier)",
                "- Provisioning action: \(provisioningActionIdentifier)"
            ].joined(separator: "\n"),
            limit: Self.markdownMaxCharacters
        )

        self.identifier = identifier
        self.phase = phase
        self.phaseIdentifier = phaseIdentifier
        self.attemptLabel = attemptLabel
        self.selectedPreferenceIdentifier = selectedPreferenceIdentifier
        self.selectedPreferenceTitle = selectedPreferenceTitle
        self.effectiveRouteIdentifier = effectiveRouteIdentifier
        self.effectiveRouteTitle = effectiveRouteTitle
        self.supportClassificationIdentifier = supportClassificationIdentifier
        self.visibleSupportTokens = visibleSupportTokens
        self.omittedSupportTokenCount = omittedSupportTokenCount
        self.imageLabel = imageLabel
        self.workspaceLabel = workspaceLabel
        self.fallbackStateIdentifier = fallbackStateIdentifier
        self.fallbackReason = fallbackReason
        self.provisioningAvailabilityIdentifier = provisioningAvailabilityIdentifier
        self.provisioningStatusIdentifier = provisioningStatusIdentifier
        self.provisioningActionIdentifier = provisioningActionIdentifier
        self.markdownSection = markdownSection
    }

    private static func title(
        identifier: String,
        fallback: String,
        knownTitles: [String: String],
        defaultTitle: String
    ) -> String {
        if let knownTitle = knownTitles[identifier] {
            return knownTitle
        }
        return sanitizedField(fallback, limit: fieldMaxCharacters, fallback: defaultTitle)
    }

    private static func sanitizedSupportToken(_ token: String) -> String {
        let sanitized = sanitizedField(token, limit: tokenMaxCharacters, fallback: "")
        guard !sanitized.isEmpty else { return "" }
        guard sanitized.unicodeScalars.allSatisfy(isStableTokenScalar) else {
            return "token"
        }
        return sanitized
    }

    private static func sanitizedIdentifier(
        _ text: String,
        fallback: String,
        limit: Int
    ) -> String {
        let normalized = bounded(text, limit: limit).lowercased()
        let filtered = String(normalized.unicodeScalars.map { scalar in
            if isASCIILetter(scalar)
                || isASCIIDigit(scalar)
                || scalar == "-"
                || scalar == "_"
                || scalar == "." {
                return Character(scalar)
            }
            return "-"
        })
        .replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet(charactersIn: "-_."))
        return filtered.isEmpty ? fallback : filtered
    }

    private static func sanitizedField(
        _ text: String,
        limit: Int,
        fallback: String
    ) -> String {
        let redacted = redactHostPaths(in: text)
        let bounded = bounded(redacted, limit: limit)
        return bounded.isEmpty ? fallback : bounded
    }

    private static func redactHostPaths(in text: String) -> String {
        let hostPathPattern = #"(?:(?:file://)?/(?:Users|private|var|tmp|opt|usr|bin|sbin|Library|Applications|Volumes)/[^\s,;)`"]+)|(?:\.\./[^\s,;)`"]+)"#
        return text.replacingOccurrences(
            of: hostPathPattern,
            with: "[path]",
            options: .regularExpression
        )
    }

    private static func bounded(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
        guard normalized.count <= limit else {
            let prefixLimit = max(1, limit - 3)
            return normalized.prefix(prefixLimit)
                .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }
        return normalized
    }

    private static func isStableTokenScalar(_ scalar: UnicodeScalar) -> Bool {
        isASCIILetter(scalar)
            || isASCIIDigit(scalar)
            || scalar == ":"
            || scalar == "."
            || scalar == "_"
            || scalar == "-"
            || scalar == "@"
            || scalar == "+"
    }

    private static func isASCIILetter(_ scalar: UnicodeScalar) -> Bool {
        (65...90).contains(Int(scalar.value)) || (97...122).contains(Int(scalar.value))
    }

    private static func isASCIIDigit(_ scalar: UnicodeScalar) -> Bool {
        (48...57).contains(Int(scalar.value))
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

struct CinematicRunRecapShareArtifactRuntimeRouteCue: Equatable, Identifiable {
    static let identifierMaxCharacters = CinematicRunRecapShareArtifactPlan.identifierMaxCharacters
    static let fieldMaxCharacters = SessionExecutionEnvironmentSnapshot.fieldLimit
    static let copyMaxCharacters = 96
    static let detailMaxCharacters = 180
    static let helpMaxCharacters = 220
    static let sectionLineLimit = 32

    var id: String { identifier }

    var identifier: String
    var routeKindIdentifier: String
    var effectiveRouteIdentifier: String
    var fallbackStateIdentifier: String
    var selectedPreferenceIdentifier: String
    var supportClassificationIdentifier: String
    var phaseIdentifier: String
    var attemptLabel: String
    var compactCopy: String
    var detailCopy: String
    var helpCopy: String

    init?(markdownContents: String) {
        guard let sectionLines = Self.runtimeRouteSectionLines(in: markdownContents) else {
            return nil
        }
        let effectiveRouteIdentifier = Self.knownIdentifier(
            Self.leadingIdentifier(Self.markdownField("Effective route", in: sectionLines)),
            allowed: ["apple-container", "native-macos"],
            fallback: "unknown"
        )
        let fallbackStateIdentifier = Self.knownIdentifier(
            Self.markdownField("Fallback state", in: sectionLines),
            allowed: ["direct", "fallback"],
            fallback: "unknown"
        )
        let selectedPreferenceIdentifier = Self.knownIdentifier(
            Self.leadingIdentifier(Self.markdownField("Selected preference", in: sectionLines)),
            allowed: [
                CodexExecutionEnvironmentPreference.nativeMacOS.rawValue,
                CodexExecutionEnvironmentPreference.devcontainerPreferred.rawValue
            ],
            fallback: "unknown"
        )
        let supportClassificationIdentifier = Self.knownIdentifier(
            Self.markdownField("Support classification", in: sectionLines),
            allowed: [
                "not-inspected",
                "image-routeable",
                "build-based",
                "compose-based",
                "feature-based",
                "missing",
                "malformed"
            ],
            fallback: "not-inspected"
        )
        let phaseIdentifier = Self.sanitizedIdentifier(
            Self.parenthesizedSuffix(Self.markdownField("Phase", in: sectionLines))
                ?? Self.markdownField("Phase", in: sectionLines)
                ?? "phase",
            fallback: "phase",
            limit: CinematicRunRecapShareArtifactRuntimeRouteAudit.phaseMaxCharacters
        )
        let attemptLabel = Self.sanitizedAttemptLabel(
            Self.markdownField("Attempt", in: sectionLines)
        )
        let routeKindIdentifier = Self.routeKindIdentifier(
            effectiveRouteIdentifier: effectiveRouteIdentifier,
            fallbackStateIdentifier: fallbackStateIdentifier
        )
        let compactCopy = Self.compactCopy(routeKindIdentifier: routeKindIdentifier)
        let detailCopy = Self.bounded(
            [
                "route \(compactCopy.lowercased())",
                "support \(supportClassificationIdentifier)",
                "phase \(phaseIdentifier)",
                "attempt \(attemptLabel)"
            ].joined(separator: " | "),
            limit: Self.detailMaxCharacters
        )
        let helpCopy = Self.bounded(
            "Runtime route cue from the saved recap artifact Markdown. It is read-only and only shows sanitized route, support, phase, and attempt identifiers.",
            limit: Self.helpMaxCharacters
        )
        let identifier = Self.bounded(
            [
                "run-recap-share-artifact-runtime-route-cue",
                "kind:\(routeKindIdentifier)",
                "effective:\(effectiveRouteIdentifier)",
                "fallback:\(fallbackStateIdentifier)",
                "preference:\(selectedPreferenceIdentifier)",
                "support:\(supportClassificationIdentifier)",
                "phase:\(phaseIdentifier)",
                "attempt:\(attemptLabel)"
            ].joined(separator: "|"),
            limit: Self.identifierMaxCharacters
        )

        self.identifier = identifier
        self.routeKindIdentifier = routeKindIdentifier
        self.effectiveRouteIdentifier = effectiveRouteIdentifier
        self.fallbackStateIdentifier = fallbackStateIdentifier
        self.selectedPreferenceIdentifier = selectedPreferenceIdentifier
        self.supportClassificationIdentifier = supportClassificationIdentifier
        self.phaseIdentifier = phaseIdentifier
        self.attemptLabel = attemptLabel
        self.compactCopy = compactCopy
        self.detailCopy = detailCopy
        self.helpCopy = helpCopy
    }

    static func runtimeRouteSectionLines(in markdownContents: String) -> [String]? {
        let lines = markdownContents
            .replacingOccurrences(of: "\r", with: "")
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map(String.init)
        guard let headerIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines) == "## Runtime Route"
        }) else {
            return nil
        }

        var sectionLines: [String] = []
        for line in lines.dropFirst(headerIndex + 1) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("## ") {
                break
            }
            sectionLines.append(line)
            if sectionLines.count == sectionLineLimit {
                break
            }
        }
        return sectionLines.isEmpty ? nil : sectionLines
    }

    private static func markdownField(_ name: String, in lines: [String]) -> String? {
        let prefix = "- \(name): "
        return lines
            .lazy
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.hasPrefix(prefix) }
            .map { line in
                String(line.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func routeKindIdentifier(
        effectiveRouteIdentifier: String,
        fallbackStateIdentifier: String
    ) -> String {
        if effectiveRouteIdentifier == "apple-container" {
            return "apple-container"
        }
        if effectiveRouteIdentifier == "native-macos", fallbackStateIdentifier == "fallback" {
            return "native-fallback"
        }
        if effectiveRouteIdentifier == "native-macos" {
            return "native"
        }
        return "unknown"
    }

    private static func compactCopy(routeKindIdentifier: String) -> String {
        switch routeKindIdentifier {
        case "apple-container":
            return "Container"
        case "native":
            return "Native"
        case "native-fallback":
            return "Native fallback"
        default:
            return "Runtime route"
        }
    }

    private static func leadingIdentifier(_ text: String?) -> String? {
        guard let text else { return nil }
        let prefix = text.split(separator: " ", maxSplits: 1).first.map(String.init) ?? text
        return prefix.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parenthesizedSuffix(_ text: String?) -> String? {
        guard let text,
              let open = text.lastIndex(of: "("),
              text.hasSuffix(")") else {
            return nil
        }
        let suffix = text[text.index(after: open)..<text.index(before: text.endIndex)]
        let normalized = String(suffix).trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func knownIdentifier(
        _ text: String?,
        allowed: Set<String>,
        fallback: String
    ) -> String {
        let identifier = sanitizedIdentifier(
            text ?? "",
            fallback: fallback,
            limit: Self.fieldMaxCharacters
        )
        return allowed.contains(identifier) ? identifier : fallback
    }

    private static func sanitizedAttemptLabel(_ text: String?) -> String {
        let identifier = sanitizedIdentifier(
            text ?? "none",
            fallback: "none",
            limit: Self.fieldMaxCharacters
        )
        if identifier == "none" {
            return identifier
        }
        return identifier.allSatisfy(\.isNumber) ? identifier : "unknown"
    }

    private static func sanitizedIdentifier(
        _ text: String,
        fallback: String,
        limit: Int
    ) -> String {
        let normalized = bounded(redactHostPaths(in: text), limit: limit).lowercased()
        let filtered = String(normalized.unicodeScalars.map { scalar in
            if isASCIILetter(scalar)
                || isASCIIDigit(scalar)
                || scalar == "-"
                || scalar == "_"
                || scalar == "." {
                return Character(scalar)
            }
            return "-"
        })
        .replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet(charactersIn: "-_."))
        return filtered.isEmpty ? fallback : filtered
    }

    private static func redactHostPaths(in text: String) -> String {
        let hostPathPattern = #"(?:(?:file://)?/(?:Users|private|var|tmp|opt|usr|bin|sbin|Library|Applications|Volumes)/[^\s,;)`"]+)|(?:\.\./[^\s,;)`"]+)"#
        return text.replacingOccurrences(
            of: hostPathPattern,
            with: "[path]",
            options: .regularExpression
        )
    }

    private static func bounded(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "" }
        guard normalized.count <= limit else {
            let prefixLimit = max(1, limit - 3)
            return normalized.prefix(prefixLimit)
                .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }
        return normalized
    }

    private static func isASCIILetter(_ scalar: UnicodeScalar) -> Bool {
        (65...90).contains(Int(scalar.value)) || (97...122).contains(Int(scalar.value))
    }

    private static func isASCIIDigit(_ scalar: UnicodeScalar) -> Bool {
        (48...57).contains(Int(scalar.value))
    }
}

struct CinematicRunRecapShareArtifactMutationTestingCue: Equatable, Identifiable {
    static let identifierMaxCharacters = CinematicRunRecapShareArtifactPlan.identifierMaxCharacters
    static let fieldMaxCharacters = SessionMutationTestingExecution.fieldLimit
    static let copyMaxCharacters = 120
    static let detailMaxCharacters = 220
    static let helpMaxCharacters = 240
    static let sectionLineLimit = 32

    var id: String { identifier }

    var identifier: String
    var auditIdentifier: String
    var statusIdentifier: String
    var routeIdentifier: String
    var languageIdentifier: String
    var exitCodeLabel: String
    var durationLabel: String
    var runtimeRouteAuditIdentifier: String
    var runtimeRouteCorrelationIdentifier: String
    var compactCopy: String
    var detailCopy: String
    var helpCopy: String

    init?(markdownContents: String) {
        guard let sectionLines = Self.mutationTestingSectionLines(in: markdownContents) else {
            return nil
        }

        let auditIdentifier = Self.sanitizedField(
            Self.markdownField("Mutation audit", in: sectionLines) ?? "unknown",
            fallback: "unknown",
            limit: CinematicRunRecapShareArtifactMutationTestingAudit.identifierMaxCharacters
        )
        let statusIdentifier = MutationTestingPresentationSanitizer.statusIdentifier(
            Self.leadingIdentifier(Self.markdownField("Status", in: sectionLines)) ?? "unknown"
        )
        let routeIdentifier = MutationTestingPresentationSanitizer.routeIdentifier(
            Self.leadingIdentifier(Self.markdownField("Route", in: sectionLines)) ?? "unknown"
        )
        let languageIdentifier = MutationTestingPresentationSanitizer.languageIdentifier(
            Self.leadingIdentifier(Self.markdownField("Language", in: sectionLines)) ?? "unknown"
        )
        let exitCodeLabel = Self.sanitizedField(
            Self.markdownField("Exit code", in: sectionLines) ?? "exit unknown",
            fallback: "exit unknown",
            limit: Self.fieldMaxCharacters
        )
        let durationLabel = Self.sanitizedField(
            Self.markdownField("Duration", in: sectionLines) ?? "unknown",
            fallback: "unknown",
            limit: Self.fieldMaxCharacters
        )
        let runtimeRouteAuditIdentifier = Self.sanitizedField(
            Self.markdownField("Runtime route audit", in: sectionLines) ?? "none",
            fallback: "none",
            limit: CinematicRunRecapShareArtifactRuntimeRouteAudit.identifierMaxCharacters
        )
        let runtimeRouteCorrelationIdentifier = MutationTestingPresentationSanitizer.identifier(
            Self.markdownField("Runtime route correlation", in: sectionLines) ?? "unknown",
            fallback: "unknown",
            limit: Self.fieldMaxCharacters
        )
        let compactCopy = Self.compactCopy(statusIdentifier: statusIdentifier)
        let detailCopy = MutationTestingPresentationSanitizer.bounded(
            [
                "mutation \(statusIdentifier)",
                "route \(routeIdentifier)",
                "language \(languageIdentifier)",
                exitCodeLabel,
                durationLabel,
                "runtime \(runtimeRouteCorrelationIdentifier)"
            ].joined(separator: " | "),
            limit: Self.detailMaxCharacters
        )
        let helpCopy = MutationTestingPresentationSanitizer.bounded(
            "Mutation cue from the saved recap artifact Markdown. It is read-only and only shows sanitized status, route, language, exit, duration, and route-correlation identifiers.",
            limit: Self.helpMaxCharacters
        )
        let identifier = MutationTestingPresentationSanitizer.bounded(
            [
                "run-recap-share-artifact-mutation-testing-cue",
                "audit:\(MutationTestingPresentationSanitizer.fingerprint(auditIdentifier))",
                "status:\(statusIdentifier)",
                "route:\(routeIdentifier)",
                "language:\(languageIdentifier)",
                "exit:\(exitCodeLabel)",
                "duration:\(durationLabel)",
                "runtime:\(MutationTestingPresentationSanitizer.fingerprint(runtimeRouteAuditIdentifier))",
                "correlation:\(runtimeRouteCorrelationIdentifier)"
            ].joined(separator: "|"),
            limit: Self.identifierMaxCharacters
        )

        self.identifier = identifier
        self.auditIdentifier = auditIdentifier
        self.statusIdentifier = statusIdentifier
        self.routeIdentifier = routeIdentifier
        self.languageIdentifier = languageIdentifier
        self.exitCodeLabel = exitCodeLabel
        self.durationLabel = durationLabel
        self.runtimeRouteAuditIdentifier = runtimeRouteAuditIdentifier
        self.runtimeRouteCorrelationIdentifier = runtimeRouteCorrelationIdentifier
        self.compactCopy = compactCopy
        self.detailCopy = detailCopy
        self.helpCopy = helpCopy
    }

    static func mutationTestingSectionLines(in markdownContents: String) -> [String]? {
        let lines = markdownContents
            .replacingOccurrences(of: "\r", with: "")
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map(String.init)
        guard let headerIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines) == "## Mutation Tests"
        }) else {
            return nil
        }

        var sectionLines: [String] = []
        for line in lines.dropFirst(headerIndex + 1) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("## ") {
                break
            }
            sectionLines.append(line)
            if sectionLines.count == sectionLineLimit {
                break
            }
        }
        return sectionLines.isEmpty ? nil : sectionLines
    }

    private static func markdownField(_ name: String, in lines: [String]) -> String? {
        let prefix = "- \(name): "
        return lines
            .lazy
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.hasPrefix(prefix) }
            .map { line in
                String(line.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func compactCopy(statusIdentifier: String) -> String {
        switch statusIdentifier {
        case "succeeded":
            return "Mutation passed"
        case "failed":
            return "Mutation failed"
        default:
            return "Mutation recorded"
        }
    }

    private static func leadingIdentifier(_ text: String?) -> String? {
        guard let text else { return nil }
        let prefix = text.split(separator: " ", maxSplits: 1).first.map(String.init) ?? text
        return prefix.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sanitizedField(
        _ text: String,
        fallback: String,
        limit: Int
    ) -> String {
        MutationTestingPresentationSanitizer.field(text, limit: limit, fallback: fallback)
    }
}

struct CinematicRunRecapShareArtifactWarningPulseCue: Equatable, Identifiable {
    static let identifierMaxCharacters = CinematicRunRecapShareArtifactPlan.identifierMaxCharacters
    static let fieldMaxCharacters = CinematicRunRecapShareArtifactWarningPulseAudit.fieldMaxCharacters
    static let copyMaxCharacters = 120
    static let detailMaxCharacters = 220
    static let helpMaxCharacters = 240
    static let sectionLineLimit = 32

    var id: String { identifier }

    var identifier: String
    var auditIdentifier: String
    var stateIdentifier: String
    var bundleIdentifier: String
    var quietingStatusIdentifier: String
    var sequence: Int
    var captureCount: Int
    var targetCount: Int
    var warningCount: Int
    var warningIdentifiers: [String]
    var omittedWarningIdentifierCount: Int
    var targetAnchors: [String]
    var omittedTargetAnchorCount: Int
    var relatedRowAnchors: [String]
    var omittedRelatedRowAnchorCount: Int
    var compactCopy: String
    var detailCopy: String
    var helpCopy: String

    var totalOmittedCount: Int {
        omittedWarningIdentifierCount + omittedTargetAnchorCount + omittedRelatedRowAnchorCount
    }

    init?(markdownContents: String) {
        guard let sectionLines = Self.warningPulseSectionLines(in: markdownContents) else {
            return nil
        }

        let auditIdentifier = Self.sanitizedField(
            Self.markdownField("Warning pulse audit", in: sectionLines) ?? "unknown",
            fallback: "unknown",
            limit: CinematicRunRecapShareArtifactWarningPulseAudit.identifierMaxCharacters
        )
        let stateIdentifier = Self.knownIdentifier(
            Self.markdownField("State", in: sectionLines),
            allowed: ["active", "snoozed"],
            fallback: "unknown"
        )
        let bundleIdentifier = Self.sanitizedField(
            Self.markdownField("Bundle", in: sectionLines) ?? "unknown",
            fallback: "unknown",
            limit: Self.fieldMaxCharacters
        )
        let quietingStatusIdentifier = Self.sanitizedField(
            Self.markdownField("Quieting status", in: sectionLines) ?? "unknown",
            fallback: "unknown",
            limit: CinematicDiagnosticsWarningPulseQuietingStatusDescriptor.identifierMaxCharacters
        )
        let sequence = Self.nonnegativeInt(Self.markdownField("Sequence", in: sectionLines))
        let captureCount = Self.nonnegativeInt(Self.markdownField("Capture count", in: sectionLines))
        let targetCount = Self.nonnegativeInt(Self.markdownField("Target count", in: sectionLines))
        let warningCount = Self.nonnegativeInt(Self.markdownField("Warning count", in: sectionLines))
        let warningIdentifiers = Self.identifierList(
            Self.markdownField("Warning identifiers", in: sectionLines),
            limit: CinematicRunRecapShareArtifactWarningPulseAudit.warningIdentifierLimit
        )
        let omittedWarningIdentifierCount = Self.nonnegativeInt(
            Self.markdownField("Omitted warning identifiers", in: sectionLines)
        )
        let targetAnchors = Self.identifierList(
            Self.markdownField("Target anchors", in: sectionLines),
            limit: CinematicRunRecapShareArtifactWarningPulseAudit.anchorLimit
        )
        let omittedTargetAnchorCount = Self.nonnegativeInt(
            Self.markdownField("Omitted target anchors", in: sectionLines)
        )
        let relatedRowAnchors = Self.identifierList(
            Self.markdownField("Related rows", in: sectionLines),
            limit: CinematicRunRecapShareArtifactWarningPulseAudit.anchorLimit
        )
        let omittedRelatedRowAnchorCount = Self.nonnegativeInt(
            Self.markdownField("Omitted related rows", in: sectionLines)
        )
        let compactCopy = stateIdentifier == "snoozed"
            ? "Warning pulse snoozed"
            : "Warning pulse active"
        let detailCopy = Self.bounded(
            [
                "pulse \(stateIdentifier)",
                "bundle \(bundleIdentifier)",
                "captures \(captureCount)",
                "targets \(targetCount)",
                "warnings \(warningCount)",
                "omitted \(omittedWarningIdentifierCount + omittedTargetAnchorCount + omittedRelatedRowAnchorCount)"
            ].joined(separator: " | "),
            limit: Self.detailMaxCharacters
        )
        let helpCopy = Self.bounded(
            "Diagnostics warning pulse cue from saved recap artifact Markdown. It is read-only and only shows bounded bundle, state, warning identifier, target anchor, and related row identifiers.",
            limit: Self.helpMaxCharacters
        )
        let identifier = Self.bounded(
            [
                "run-recap-share-artifact-warning-pulse-cue",
                "audit:\(Self.fingerprint(auditIdentifier))",
                "state:\(stateIdentifier)",
                "bundle:\(Self.fingerprint(bundleIdentifier))",
                "sequence:\(sequence)",
                "captures:\(captureCount)",
                "targets:\(targetCount)",
                "warnings:\(warningCount)",
                "warning-ids:\(Self.fingerprint(warningIdentifiers.joined(separator: "|")))",
                "target-anchors:\(Self.fingerprint(targetAnchors.joined(separator: "|")))",
                "related:\(Self.fingerprint(relatedRowAnchors.joined(separator: "|")))",
                "omitted:\(omittedWarningIdentifierCount + omittedTargetAnchorCount + omittedRelatedRowAnchorCount)"
            ].joined(separator: "|"),
            limit: Self.identifierMaxCharacters
        )

        self.identifier = identifier
        self.auditIdentifier = auditIdentifier
        self.stateIdentifier = stateIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.quietingStatusIdentifier = quietingStatusIdentifier
        self.sequence = sequence
        self.captureCount = captureCount
        self.targetCount = targetCount
        self.warningCount = warningCount
        self.warningIdentifiers = warningIdentifiers
        self.omittedWarningIdentifierCount = omittedWarningIdentifierCount
        self.targetAnchors = targetAnchors
        self.omittedTargetAnchorCount = omittedTargetAnchorCount
        self.relatedRowAnchors = relatedRowAnchors
        self.omittedRelatedRowAnchorCount = omittedRelatedRowAnchorCount
        self.compactCopy = Self.bounded(compactCopy, limit: Self.copyMaxCharacters)
        self.detailCopy = detailCopy
        self.helpCopy = helpCopy
    }

    static func warningPulseSectionLines(in markdownContents: String) -> [String]? {
        let lines = markdownContents
            .replacingOccurrences(of: "\r", with: "")
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map(String.init)
        guard let headerIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines) == "## Diagnostics Warning Pulse"
        }) else {
            return nil
        }

        var sectionLines: [String] = []
        for line in lines.dropFirst(headerIndex + 1) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("## ") {
                break
            }
            sectionLines.append(line)
            if sectionLines.count == sectionLineLimit {
                break
            }
        }
        return sectionLines.isEmpty ? nil : sectionLines
    }

    private static func markdownField(_ name: String, in lines: [String]) -> String? {
        let prefix = "- \(name): "
        return lines
            .lazy
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.hasPrefix(prefix) }
            .map { line in
                String(line.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func identifierList(_ text: String?, limit: Int) -> [String] {
        guard let text else { return [] }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "none" else { return [] }

        var seen = Set<String>()
        var result: [String] = []
        for value in trimmed.components(separatedBy: ",") {
            let token = sanitizedField(value, fallback: "", limit: Self.fieldMaxCharacters)
            guard !token.isEmpty, !seen.contains(token) else { continue }
            seen.insert(token)
            result.append(token)
            if result.count >= max(0, limit) {
                break
            }
        }
        return result
    }

    private static func knownIdentifier(
        _ text: String?,
        allowed: Set<String>,
        fallback: String
    ) -> String {
        let identifier = sanitizedIdentifier(text ?? "", fallback: fallback, limit: Self.fieldMaxCharacters)
        return allowed.contains(identifier) ? identifier : fallback
    }

    private static func nonnegativeInt(_ text: String?) -> Int {
        max(0, Int(text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0)
    }

    private static func sanitizedIdentifier(
        _ text: String,
        fallback: String,
        limit: Int
    ) -> String {
        let normalized = bounded(text, limit: limit).lowercased()
        let filtered = String(normalized.unicodeScalars.map { scalar in
            if isASCIILetter(scalar)
                || isASCIIDigit(scalar)
                || scalar == "-"
                || scalar == "_"
                || scalar == "." {
                return Character(scalar)
            }
            return "-"
        })
        .replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet(charactersIn: "-_."))
        return filtered.isEmpty ? fallback : filtered
    }

    private static func sanitizedField(
        _ text: String,
        fallback: String,
        limit: Int
    ) -> String {
        let normalized = MutationTestingPresentationSanitizer.field(
            text,
            limit: limit,
            fallback: fallback
        )
        return normalized.isEmpty ? fallback : normalized
    }

    private static func bounded(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "" }
        guard normalized.count <= limit else {
            let prefixLimit = max(1, limit - 3)
            return normalized.prefix(prefixLimit)
                .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }
        return normalized
    }

    private static func isASCIILetter(_ scalar: UnicodeScalar) -> Bool {
        (65...90).contains(Int(scalar.value)) || (97...122).contains(Int(scalar.value))
    }

    private static func isASCIIDigit(_ scalar: UnicodeScalar) -> Bool {
        (48...57).contains(Int(scalar.value))
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

struct CinematicRunRecapShareArtifactWarningPulseTreatmentDescriptor: Equatable {
    static let identifierMaxCharacters = 180
    static let componentMaxCharacters = 48
    static let copyMaxCharacters = CinematicRunRecapShareArtifactWarningPulseCue.copyMaxCharacters
    static let helpMaxCharacters = CinematicRunRecapShareArtifactWarningPulseCue.helpMaxCharacters

    var identifier: String
    var stateIdentifier: String
    var accentIdentifier: String
    var railIdentifier: String
    var sealIdentifier: String
    var textIdentifier: String
    var compactCopy: String
    var helpCopy: String
    var plateOpacityBoost: Double
    var railOpacityScale: Double
    var sealOpacityScale: Double
    var textOpacityScale: Double

    init(cue: CinematicRunRecapShareArtifactWarningPulseCue?) {
        let stateIdentifier = Self.stateIdentifier(cue?.stateIdentifier, hasCue: cue != nil)
        let presentation = Self.presentation(stateIdentifier: stateIdentifier)

        self.stateIdentifier = stateIdentifier
        accentIdentifier = presentation.accentIdentifier
        railIdentifier = presentation.railIdentifier
        sealIdentifier = presentation.sealIdentifier
        textIdentifier = presentation.textIdentifier
        compactCopy = Self.bounded(
            cue?.compactCopy ?? presentation.compactCopy,
            limit: Self.copyMaxCharacters
        )
        helpCopy = Self.bounded(
            cue?.helpCopy ?? presentation.helpCopy,
            limit: Self.helpMaxCharacters
        )
        plateOpacityBoost = presentation.plateOpacityBoost
        railOpacityScale = presentation.railOpacityScale
        sealOpacityScale = presentation.sealOpacityScale
        textOpacityScale = presentation.textOpacityScale
        identifier = Self.bounded(
            [
                "warning-pulse-treatment",
                "state:\(stateIdentifier)",
                "accent:\(accentIdentifier)",
                "rail:\(railIdentifier)",
                "seal:\(sealIdentifier)",
                "text:\(textIdentifier)",
                "cue:\(Self.fingerprint(cue?.identifier ?? "missing-cue"))"
            ].joined(separator: "|"),
            limit: Self.identifierMaxCharacters
        )
    }

    private struct Presentation {
        var accentIdentifier: String
        var railIdentifier: String
        var sealIdentifier: String
        var textIdentifier: String
        var compactCopy: String
        var helpCopy: String
        var plateOpacityBoost: Double
        var railOpacityScale: Double
        var sealOpacityScale: Double
        var textOpacityScale: Double
    }

    private static func stateIdentifier(_ cueStateIdentifier: String?, hasCue: Bool) -> String {
        guard hasCue else { return "missing" }
        switch cueStateIdentifier {
        case "active":
            return "active"
        case "snoozed":
            return "snoozed"
        default:
            return "unknown"
        }
    }

    private static func presentation(stateIdentifier: String) -> Presentation {
        switch stateIdentifier {
        case "active":
            return Presentation(
                accentIdentifier: "warning-pulse-amber",
                railIdentifier: "warning-pulse-active-rail",
                sealIdentifier: "warning-pulse-active-seal",
                textIdentifier: "warning-pulse-active-text",
                compactCopy: "Warning pulse active",
                helpCopy: "Saved artifact warning-pulse cue is active and read-only.",
                plateOpacityBoost: 0.055,
                railOpacityScale: 1.28,
                sealOpacityScale: 1.2,
                textOpacityScale: 1.12
            )
        case "snoozed":
            return Presentation(
                accentIdentifier: "warning-pulse-teal",
                railIdentifier: "warning-pulse-snoozed-rail",
                sealIdentifier: "warning-pulse-snoozed-seal",
                textIdentifier: "warning-pulse-snoozed-text",
                compactCopy: "Warning pulse snoozed",
                helpCopy: "Saved artifact warning-pulse cue is snoozed and read-only.",
                plateOpacityBoost: 0.035,
                railOpacityScale: 1.04,
                sealOpacityScale: 0.94,
                textOpacityScale: 0.96
            )
        case "unknown":
            return Presentation(
                accentIdentifier: "warning-pulse-violet",
                railIdentifier: "warning-pulse-unknown-rail",
                sealIdentifier: "warning-pulse-unknown-seal",
                textIdentifier: "warning-pulse-unknown-text",
                compactCopy: "Warning pulse unknown",
                helpCopy: "Saved artifact warning-pulse cue was present but its bounded state was unknown.",
                plateOpacityBoost: 0.02,
                railOpacityScale: 0.9,
                sealOpacityScale: 0.84,
                textOpacityScale: 0.82
            )
        default:
            return Presentation(
                accentIdentifier: "warning-pulse-muted",
                railIdentifier: "warning-pulse-missing-rail",
                sealIdentifier: "warning-pulse-missing-seal",
                textIdentifier: "warning-pulse-missing-text",
                compactCopy: "Warning pulse missing",
                helpCopy: "No warning-pulse cue was found in the selected saved recap artifact.",
                plateOpacityBoost: 0,
                railOpacityScale: 0.72,
                sealOpacityScale: 0.66,
                textOpacityScale: 0.7
            )
        }
    }

    private static func bounded(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "" }
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

struct CinematicRunRecapShareArtifactMutationTestingTreatmentDescriptor: Equatable {
    static let identifierMaxCharacters = 180
    static let componentMaxCharacters = 48
    static let copyMaxCharacters = CinematicRunRecapShareArtifactMutationTestingCue.copyMaxCharacters
    static let helpMaxCharacters = CinematicRunRecapShareArtifactMutationTestingCue.helpMaxCharacters

    var identifier: String
    var stateIdentifier: String
    var accentIdentifier: String
    var railIdentifier: String
    var sealIdentifier: String
    var textIdentifier: String
    var compactCopy: String
    var helpCopy: String
    var railOpacityScale: Double
    var sealOpacityScale: Double
    var textOpacityScale: Double

    init(cue: CinematicRunRecapShareArtifactMutationTestingCue?) {
        let statusIdentifier = cue?.statusIdentifier ?? "missing"
        let routeCorrelationIdentifier = cue?.runtimeRouteCorrelationIdentifier ?? "missing-cue"
        let stateIdentifier = Self.stateIdentifier(
            statusIdentifier: statusIdentifier,
            routeCorrelationIdentifier: routeCorrelationIdentifier,
            hasCue: cue != nil
        )
        let presentation = Self.presentation(stateIdentifier: stateIdentifier)

        self.stateIdentifier = stateIdentifier
        accentIdentifier = presentation.accentIdentifier
        railIdentifier = presentation.railIdentifier
        sealIdentifier = presentation.sealIdentifier
        textIdentifier = presentation.textIdentifier
        compactCopy = MutationTestingPresentationSanitizer.bounded(
            presentation.compactCopy,
            limit: Self.copyMaxCharacters
        )
        helpCopy = MutationTestingPresentationSanitizer.bounded(
            presentation.helpCopy,
            limit: Self.helpMaxCharacters
        )
        railOpacityScale = presentation.railOpacityScale
        sealOpacityScale = presentation.sealOpacityScale
        textOpacityScale = presentation.textOpacityScale
        identifier = MutationTestingPresentationSanitizer.bounded(
            [
                "mutation-testing-treatment",
                "state:\(stateIdentifier)",
                "status:\(statusIdentifier)",
                "correlation:\(routeCorrelationIdentifier)",
                "accent:\(accentIdentifier)",
                "rail:\(railIdentifier)",
                "seal:\(sealIdentifier)",
                "text:\(textIdentifier)"
            ].joined(separator: "|"),
            limit: Self.identifierMaxCharacters
        )
    }

    private struct Presentation {
        var accentIdentifier: String
        var railIdentifier: String
        var sealIdentifier: String
        var textIdentifier: String
        var compactCopy: String
        var helpCopy: String
        var railOpacityScale: Double
        var sealOpacityScale: Double
        var textOpacityScale: Double
    }

    private static func stateIdentifier(
        statusIdentifier: String,
        routeCorrelationIdentifier: String,
        hasCue: Bool
    ) -> String {
        guard hasCue else { return "missing" }
        if routeCorrelationIdentifier.contains("route-diverged") {
            return "runtime-route-diverged"
        }
        switch statusIdentifier {
        case "succeeded":
            return "succeeded"
        case "failed":
            return "failed"
        default:
            return "unknown"
        }
    }

    private static func presentation(stateIdentifier: String) -> Presentation {
        switch stateIdentifier {
        case "succeeded":
            return Presentation(
                accentIdentifier: "mutation-green",
                railIdentifier: "mutation-pass-rail",
                sealIdentifier: "mutation-pass-seal",
                textIdentifier: "mutation-pass-text",
                compactCopy: "Mutation passed",
                helpCopy: "Saved artifact mutation testing cue reported a sanitized succeeded status.",
                railOpacityScale: 1.08,
                sealOpacityScale: 1.04,
                textOpacityScale: 1.0
            )
        case "failed":
            return Presentation(
                accentIdentifier: "mutation-red",
                railIdentifier: "mutation-fail-rail",
                sealIdentifier: "mutation-fail-seal",
                textIdentifier: "mutation-fail-text",
                compactCopy: "Mutation failed",
                helpCopy: "Saved artifact mutation testing cue reported a sanitized failed status.",
                railOpacityScale: 1.32,
                sealOpacityScale: 1.24,
                textOpacityScale: 1.16
            )
        case "runtime-route-diverged":
            return Presentation(
                accentIdentifier: "mutation-amber",
                railIdentifier: "mutation-diverged-rail",
                sealIdentifier: "mutation-diverged-seal",
                textIdentifier: "mutation-diverged-text",
                compactCopy: "Mutation route diverged",
                helpCopy: "Saved artifact mutation testing cue reported sanitized route-correlation divergence.",
                railOpacityScale: 1.24,
                sealOpacityScale: 1.18,
                textOpacityScale: 1.12
            )
        case "unknown":
            return Presentation(
                accentIdentifier: "mutation-violet",
                railIdentifier: "mutation-unknown-rail",
                sealIdentifier: "mutation-unknown-seal",
                textIdentifier: "mutation-unknown-text",
                compactCopy: "Mutation unknown",
                helpCopy: "Saved artifact mutation testing cue was present but its sanitized status was unknown.",
                railOpacityScale: 1.0,
                sealOpacityScale: 0.96,
                textOpacityScale: 0.92
            )
        default:
            return Presentation(
                accentIdentifier: "mutation-muted",
                railIdentifier: "mutation-missing-rail",
                sealIdentifier: "mutation-missing-seal",
                textIdentifier: "mutation-missing-text",
                compactCopy: "Mutation missing",
                helpCopy: "No mutation testing cue was found in the selected saved recap artifact.",
                railOpacityScale: 0.72,
                sealOpacityScale: 0.66,
                textOpacityScale: 0.7
            )
        }
    }
}

struct CinematicRunRecapShareArtifactRuntimeRouteTreatmentDescriptor: Equatable {
    static let identifierMaxCharacters = 160
    static let componentMaxCharacters = 48

    var identifier: String
    var routeKindIdentifier: String
    var accentIdentifier: String
    var railIdentifier: String
    var orbIdentifier: String
    var plateOpacityBoost: Double
    var railOpacityScale: Double
    var orbOpacityScale: Double

    init(cue: CinematicRunRecapShareArtifactRuntimeRouteCue?) {
        let routeKindIdentifier = cue?.routeKindIdentifier ?? "missing-cue"
        let accentIdentifier: String
        let railIdentifier: String
        let orbIdentifier: String
        let plateOpacityBoost: Double
        let railOpacityScale: Double
        let orbOpacityScale: Double
        switch routeKindIdentifier {
        case "apple-container":
            accentIdentifier = "container-blue"
            railIdentifier = "container-rail"
            orbIdentifier = "container-orb"
            plateOpacityBoost = 0.04
            railOpacityScale = 1.18
            orbOpacityScale = 1.12
        case "native":
            accentIdentifier = "native-green"
            railIdentifier = "native-rail"
            orbIdentifier = "native-orb"
            plateOpacityBoost = 0.02
            railOpacityScale = 1.06
            orbOpacityScale = 1.02
        case "native-fallback":
            accentIdentifier = "fallback-amber"
            railIdentifier = "fallback-rail"
            orbIdentifier = "fallback-orb"
            plateOpacityBoost = 0.06
            railOpacityScale = 1.28
            orbOpacityScale = 1.22
        default:
            accentIdentifier = "missing-muted"
            railIdentifier = "missing-rail"
            orbIdentifier = "missing-orb"
            plateOpacityBoost = 0
            railOpacityScale = 0.9
            orbOpacityScale = 0.86
        }
        self.routeKindIdentifier = routeKindIdentifier
        self.accentIdentifier = accentIdentifier
        self.railIdentifier = railIdentifier
        self.orbIdentifier = orbIdentifier
        self.plateOpacityBoost = plateOpacityBoost
        self.railOpacityScale = railOpacityScale
        self.orbOpacityScale = orbOpacityScale
        identifier = Self.bounded(
            [
                "runtime-route-treatment",
                "route:\(routeKindIdentifier)",
                "accent:\(accentIdentifier)",
                "rail:\(railIdentifier)",
                "orb:\(orbIdentifier)"
            ].joined(separator: "|"),
            limit: Self.identifierMaxCharacters
        )
    }

    private static func bounded(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "" }
        guard normalized.count <= limit else {
            let prefixLimit = max(1, limit - 3)
            return normalized.prefix(prefixLimit)
                .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }
        return normalized
    }
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

struct CinematicRunRecapShareArtifactSourceReconciliationPlan: Equatable, Identifiable {
    static let identifierMaxCharacters = CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
    static let representativeEntryLimit = 3
    static let pathDisplayMaxCharacters = CinematicRunRecapShareArtifactHistoryPlan.pathDisplayMaxCharacters

    var id: String { identifier }

    var identifier: String
    var stateIdentifier: String
    var activeStorageIdentifier: String
    var activitySourceIdentifier: String
    var activeHistoryIdentifier: String
    var repoLocalHistoryIdentifier: String
    var activeAvailabilityReason: String
    var repoLocalAvailabilityReason: String
    var activeTotalCount: Int
    var repoLocalTotalCount: Int
    var activeWarningCount: Int
    var repoLocalWarningCount: Int
    var activeLatestSessionNumber: Int?
    var repoLocalLatestSessionNumber: Int?
    var activeLatestEntryIdentifier: String?
    var repoLocalLatestEntryIdentifier: String?
    var representativeActiveEntryIdentifiers: [String]
    var representativeRepoLocalEntryIdentifiers: [String]
    var representativeRepoLocalExtraEntryIdentifiers: [String]
    var activeStorageRootDisplayText: String
    var activeSessionsDisplayText: String
    var repoLocalStorageRootDisplayText: String
    var repoLocalSessionsDisplayText: String
    var warningStateIdentifier: String
    var isApplicationSupportComparison: Bool
}

struct CinematicRunRecapShareArtifactSourceExportAuditPlan: Equatable, Identifiable {
    static let identifierMaxCharacters = CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
    static let representativeEntryLimit = CinematicRunRecapShareArtifactSourceReconciliationPlan.representativeEntryLimit
    static let markdownMaxCharacters = 1_800
    static let readOnlyDisclaimerMaxCharacters = 220

    var id: String { identifier }

    var identifier: String
    var sourceReconciliationIdentifier: String
    var stateIdentifier: String
    var activeStorageIdentifier: String
    var activeTotalCount: Int
    var repoLocalTotalCount: Int
    var activeLatestSessionNumber: Int?
    var repoLocalLatestSessionNumber: Int?
    var activeWarningCount: Int
    var repoLocalWarningCount: Int
    var representativeActiveEntryIdentifiers: [String]
    var representativeRepoLocalEntryIdentifiers: [String]
    var representativeRepoLocalExtraEntryIdentifiers: [String]
    var readOnlyDisclaimer: String
    var markdownSection: String
    var isVisible: Bool

    var markdownLength: Int { markdownSection.count }
}

struct CinematicRunRecapShareArtifactSourceBadgePlan: Equatable, Identifiable {
    static let identifierMaxCharacters = CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
    static let labelMaxCharacters = 38
    static let detailMaxCharacters = 190
    static let helpMaxCharacters = 280
    static let copyTextMaxCharacters = 1_600
    static let copyLabelMaxCharacters = 32
    static let systemImageMaxCharacters = 64
    static let tintIdentifierMaxCharacters = 24

    var id: String { identifier }

    var identifier: String
    var sourceReconciliationIdentifier: String
    var stateIdentifier: String
    var isVisible: Bool
    var label: String
    var detail: String
    var help: String
    var copyText: String
    var copyLabel: String
    var severity: CompassWorkspaceStorageAssessment.Severity
    var tintIdentifier: String
    var systemImage: String
    var accessibilityIdentifier: String
    var copyAccessibilityIdentifier: String

    var copyTextLength: Int { copyText.count }
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
    var warningPulseFilterIdentifier: String
    var isWarningPulseFilterActive: Bool
    var warningPulseFilterMatchCount: Int
    var warningPulseAnyCount: Int
    var warningPulseActiveCount: Int
    var warningPulseSnoozedCount: Int
    var warningPulseUnknownCount: Int
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
    var warningPulseFilterIdentifier: String
    var isWarningPulseFilterActive: Bool
    var warningPulseFilterMatchCount: Int
    var warningPulseAnyCount: Int
    var warningPulseActiveCount: Int
    var warningPulseSnoozedCount: Int
    var warningPulseUnknownCount: Int
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
    var sourceExportAuditIncluded: Bool
    var sourceExportAuditIdentifier: String?
    var sourceExportAuditMarkdownLength: Int
    var warningPulseAuditCount: Int
    var warningPulseStateSummary: String
    var warningPulseAuditIdentifiers: [String]
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
    var warningPulseFilterIdentifier: String
    var isWarningPulseFilterActive: Bool
    var warningPulseFilterMatchCount: Int
    var warningPulseAnyCount: Int
    var warningPulseActiveCount: Int
    var warningPulseSnoozedCount: Int
    var warningPulseUnknownCount: Int
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
    var sourceExportAuditIncluded: Bool
    var sourceExportAuditIdentifier: String?
    var sourceExportAuditMarkdownLength: Int
    var mutationTestingAuditCount: Int
    var mutationTestingSummary: String
    var warningPulseAuditCount: Int
    var warningPulseStateSummary: String
    var warningPulseAuditIdentifiers: [String]
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
    var warningPulseFilterIdentifier: String
    var isWarningPulseFilterActive: Bool
    var warningPulseFilterMatchCount: Int
    var warningPulseAnyCount: Int
    var warningPulseActiveCount: Int
    var warningPulseSnoozedCount: Int
    var warningPulseUnknownCount: Int
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
    var sourceExportAuditIncluded: Bool
    var sourceExportAuditIdentifier: String?
    var sourceExportAuditMarkdownLength: Int
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
    var warningPulseFilterIdentifier: String
    var isWarningPulseFilterActive: Bool
    var warningPulseFilterMatchCount: Int
    var warningPulseAnyCount: Int
    var warningPulseActiveCount: Int
    var warningPulseSnoozedCount: Int
    var warningPulseUnknownCount: Int
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
    var sourceExportAuditIncluded: Bool
    var sourceExportAuditIdentifier: String?
    var sourceExportAuditMarkdownLength: Int
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
    var warningPulseFilterIdentifier: String
    var isWarningPulseFilterActive: Bool
    var warningPulseFilterMatchCount: Int
    var warningPulseAnyCount: Int
    var warningPulseActiveCount: Int
    var warningPulseSnoozedCount: Int
    var warningPulseUnknownCount: Int
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
    var runtimeRouteCue: CinematicRunRecapShareArtifactRuntimeRouteCue?
    var runtimeRouteTreatment: CinematicRunRecapShareArtifactRuntimeRouteTreatmentDescriptor
    var mutationTestingCue: CinematicRunRecapShareArtifactMutationTestingCue?
    var mutationTestingTreatment: CinematicRunRecapShareArtifactMutationTestingTreatmentDescriptor
    var warningPulseCue: CinematicRunRecapShareArtifactWarningPulseCue?
    var warningPulseTreatment: CinematicRunRecapShareArtifactWarningPulseTreatmentDescriptor
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

    var runtimeRouteCueStateIdentifier: String {
        runtimeRouteCue?.routeKindIdentifier ?? "missing-cue"
    }

    var mutationTestingCueAvailabilityIdentifier: String {
        mutationTestingCue == nil ? "missing" : "available"
    }

    var mutationTestingCueStatusIdentifier: String {
        mutationTestingCue?.statusIdentifier ?? "missing"
    }

    var mutationTestingCueStateIdentifier: String {
        mutationTestingTreatment.stateIdentifier
    }

    var warningPulseCueAvailabilityIdentifier: String {
        warningPulseCue == nil ? "missing" : "available"
    }

    var warningPulseCueStateIdentifier: String {
        warningPulseTreatment.stateIdentifier
    }

    var warningPulseCueWarningCountIdentifier: String {
        String(warningPulseCue?.warningCount ?? 0)
    }

    var warningPulseCueIdentifierFingerprint: String {
        Self.fingerprint(warningPulseCue?.identifier ?? "missing-cue")
    }

    var warningPulseCueAuditIdentifierFingerprint: String {
        Self.fingerprint(warningPulseCue?.auditIdentifier ?? "missing-audit")
    }

    var warningPulseCueBundleIdentifierFingerprint: String {
        Self.fingerprint(warningPulseCue?.bundleIdentifier ?? "missing-bundle")
    }

    var warningPulseCueWarningIdentifiersFingerprint: String {
        Self.fingerprint(warningPulseCue?.warningIdentifiers.joined(separator: "|") ?? "none")
    }

    var warningPulseCueTargetAnchorsFingerprint: String {
        Self.fingerprint(warningPulseCue?.targetAnchors.joined(separator: "|") ?? "none")
    }

    var warningPulseCueRelatedRowAnchorsFingerprint: String {
        Self.fingerprint(warningPulseCue?.relatedRowAnchors.joined(separator: "|") ?? "none")
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

struct CinematicRunRecapShareArtifactWarningPulseFilterState: Equatable {
    var filter: CinematicRunRecapShareArtifactWarningPulseFilter
    var retainedCount: Int
    var matchingCount: Int
    var anyCount: Int
    var activeCount: Int
    var snoozedCount: Int
    var unknownCount: Int

    var filterIdentifier: String { filter.rawValue }
    var isActive: Bool { filter.isActive }
}

enum CinematicRunRecapShareArtifactWarningPulseFiltering {
    static func state(
        filter: CinematicRunRecapShareArtifactWarningPulseFilter,
        entries: [CinematicRunRecapShareArtifactHistoryPlan.Entry]
    ) -> CinematicRunRecapShareArtifactWarningPulseFilterState {
        let cues = entries.compactMap {
            CinematicRunRecapShareArtifactWarningPulseCue(markdownContents: $0.markdownContents)
        }
        let activeCount = cues.filter { $0.stateIdentifier == "active" }.count
        let snoozedCount = cues.filter { $0.stateIdentifier == "snoozed" }.count
        let unknownCount = max(0, cues.count - activeCount - snoozedCount)
        return CinematicRunRecapShareArtifactWarningPulseFilterState(
            filter: filter,
            retainedCount: entries.count,
            matchingCount: count(for: filter, retainedCount: entries.count, anyCount: cues.count, activeCount: activeCount, snoozedCount: snoozedCount),
            anyCount: cues.count,
            activeCount: activeCount,
            snoozedCount: snoozedCount,
            unknownCount: unknownCount
        )
    }

    static func filteredEntries(
        _ entries: [CinematicRunRecapShareArtifactHistoryPlan.Entry],
        filter: CinematicRunRecapShareArtifactWarningPulseFilter
    ) -> [CinematicRunRecapShareArtifactHistoryPlan.Entry] {
        guard filter != .all else { return entries }
        return entries.filter { entry in
            guard let cue = CinematicRunRecapShareArtifactWarningPulseCue(
                markdownContents: entry.markdownContents
            ) else {
                return false
            }
            switch filter {
            case .all:
                return true
            case .any:
                return true
            case .active:
                return cue.stateIdentifier == "active"
            case .snoozed:
                return cue.stateIdentifier == "snoozed"
            }
        }
    }

    static func noMatchAvailabilityReason(
        retainedEntries: [CinematicRunRecapShareArtifactHistoryPlan.Entry],
        warningFilteredEntries: [CinematicRunRecapShareArtifactHistoryPlan.Entry],
        matchingEntries: [CinematicRunRecapShareArtifactHistoryPlan.Entry],
        searchIsActive: Bool,
        filter: CinematicRunRecapShareArtifactWarningPulseFilter
    ) -> String? {
        guard !retainedEntries.isEmpty, matchingEntries.isEmpty else { return nil }
        if filter.isActive, warningFilteredEntries.isEmpty {
            return "no-matching-warning-pulse-artifacts"
        }
        if searchIsActive, !warningFilteredEntries.isEmpty {
            return "no-matching-recap-share-artifacts"
        }
        return nil
    }

    private static func count(
        for filter: CinematicRunRecapShareArtifactWarningPulseFilter,
        retainedCount: Int,
        anyCount: Int,
        activeCount: Int,
        snoozedCount: Int
    ) -> Int {
        switch filter {
        case .all:
            return retainedCount
        case .any:
            return anyCount
        case .active:
            return activeCount
        case .snoozed:
            return snoozedCount
        }
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

struct CinematicRunRecapShareArtifactCommandPlan: Equatable, Identifiable {
    static let identifierMaxCharacters = CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters
    static let commandLimit = 15
    static let labelMaxCharacters = CinematicRunRecapShareArtifactActionMenuPlan.labelMaxCharacters
    static let helpMaxCharacters = CinematicRunRecapShareArtifactActionMenuPlan.helpMaxCharacters
    static let shortcutHintMaxCharacters = CinematicRunRecapShareArtifactActionMenuPlan.shortcutHintMaxCharacters

    var id: String { identifier }

    var identifier: String
    var commands: [Command]

    var commandCount: Int { commands.count }

    func commands(in section: CinematicRunRecapShareArtifactActionMenuPlan.Section) -> [Command] {
        commands.filter { $0.section == section }
    }

    func command(
        for sourceActionKind: CinematicRunRecapShareArtifactActionMenuPlan.ActionKind
    ) -> Command? {
        commands.first { $0.sourceActionKind == sourceActionKind }
    }

    struct Command: Equatable, Identifiable {
        var id: String { identifier }

        var identifier: String
        var section: CinematicRunRecapShareArtifactActionMenuPlan.Section
        var label: String
        var help: String
        var isEnabled: Bool
        var sourceActionKind: CinematicRunRecapShareArtifactActionMenuPlan.ActionKind
        var shortcut: Shortcut
    }

    struct Shortcut: Equatable, Hashable {
        var key: Key
        var modifiers: [Modifier]

        var identifier: String {
            let modifierText = modifiers.map(\.rawValue).joined(separator: "+")
            return "\(modifierText):\(key.rawValue)"
        }

        var displayText: String {
            let modifierText = modifiers.map(\.displayText)
            return (modifierText + [key.displayText]).joined(separator: "-")
        }

        enum Key: String, Equatable, Hashable {
            case leftBracket = "["
            case rightBracket = "]"
            case b = "b"
            case d = "d"
            case e = "e"
            case h = "h"
            case m = "m"
            case o = "o"
            case p = "p"
            case r = "r"
            case returnKey = "return"
            case t = "t"

            var displayText: String {
                switch self {
                case .leftBracket, .rightBracket:
                    return rawValue
                case .returnKey:
                    return "Return"
                default:
                    return rawValue.uppercased()
                }
            }
        }

        enum Modifier: String, Equatable, Hashable {
            case command
            case control
            case option
            case shift

            var displayText: String {
                switch self {
                case .command:
                    return "Cmd"
                case .control:
                    return "Ctrl"
                case .option:
                    return "Opt"
                case .shift:
                    return "Shift"
                }
            }
        }
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
        historyPlan: CinematicRunRecapShareArtifactHistoryPlan,
        tourExportPlan: CinematicRunRecapShareArtifactSubsetExportPlan? = nil
    ) -> CinematicRunRecapShareArtifactActionMenuPlan {
        var actions: [CinematicRunRecapShareArtifactActionMenuPlan.Action] = [
            action(
                kind: .navigatePrevious,
                section: .navigate,
                label: "Previous Artifact",
                systemImage: "chevron.left",
                help: previousHelp(previewPlan),
                isEnabled: previewPlan.canNavigatePrevious,
                shortcutHint: CinematicRunRecapShareArtifactCommandPlanner.shortcutHint(for: .navigatePrevious),
                stateIdentifier: previewPlan.previousEntryIdentifier ?? previewPlan.availabilityReason
            ),
            action(
                kind: .navigateNext,
                section: .navigate,
                label: "Next Artifact",
                systemImage: "chevron.right",
                help: nextHelp(previewPlan),
                isEnabled: previewPlan.canNavigateNext,
                shortcutHint: CinematicRunRecapShareArtifactCommandPlanner.shortcutHint(for: .navigateNext),
                stateIdentifier: previewPlan.nextEntryIdentifier ?? previewPlan.availabilityReason
            ),
            action(
                kind: .revealSelected,
                section: .navigate,
                label: "Reveal in Finder",
                systemImage: "folder",
                help: revealHelp(previewPlan),
                isEnabled: previewPlan.selectedEntryIdentifier != nil,
                shortcutHint: CinematicRunRecapShareArtifactCommandPlanner.shortcutHint(for: .revealSelected),
                stateIdentifier: previewPlan.selectedEntryIdentifier ?? previewPlan.availabilityReason
            ),
            action(
                kind: .copySelectedExport,
                section: .exports,
                label: selectedExportPlan.copyLabel,
                systemImage: "doc.text",
                help: selectedExportPlan.copyHelp,
                isEnabled: selectedExportPlan.isAvailable,
                shortcutHint: CinematicRunRecapShareArtifactCommandPlanner.shortcutHint(for: .copySelectedExport),
                stateIdentifier: selectedExportPlan.exportIdentifier
            ),
            action(
                kind: .copyFilteredExport,
                section: .exports,
                label: filteredExportPlan.copyLabel,
                systemImage: "line.3.horizontal.decrease.circle",
                help: filteredExportPlan.copyHelp,
                isEnabled: filteredExportPlan.isAvailable,
                shortcutHint: CinematicRunRecapShareArtifactCommandPlanner.shortcutHint(for: .copyFilteredExport),
                stateIdentifier: filteredExportPlan.exportIdentifier
            ),
            action(
                kind: .copyLibraryExport,
                section: .exports,
                label: historyPlan.isAvailable ? "Copy Library Export" : "Library Export Unavailable",
                systemImage: "doc.on.doc",
                help: libraryExportHelp(historyPlan),
                isEnabled: historyPlan.isAvailable,
                shortcutHint: CinematicRunRecapShareArtifactCommandPlanner.shortcutHint(for: .copyLibraryExport),
                stateIdentifier: historyPlan.exportIdentifier
            ),
            action(
                kind: .copyRollupExport,
                section: .exports,
                label: rollupPlan.copyLabel,
                systemImage: "chart.bar",
                help: rollupPlan.copyHelp,
                isEnabled: rollupPlan.isAvailable,
                shortcutHint: CinematicRunRecapShareArtifactCommandPlanner.shortcutHint(for: .copyRollupExport),
                stateIdentifier: rollupPlan.exportIdentifier
            ),
            action(
                kind: .copyComparisonExport,
                section: .exports,
                label: comparisonPlan.copyLabel,
                systemImage: comparisonPlan.targetMode == .pinnedReference ? "pin.square" : "rectangle.split.2x1",
                help: comparisonPlan.copyHelp,
                isEnabled: comparisonPlan.isAvailable,
                shortcutHint: CinematicRunRecapShareArtifactCommandPlanner.shortcutHint(for: .copyComparisonExport),
                stateIdentifier: comparisonPlan.exportIdentifier
            ),
            action(
                kind: .copyPinnedExport,
                section: .exports,
                label: pinnedReferencePlan.copyLabel,
                systemImage: "pin",
                help: pinnedExportHelp(pinnedReferencePlan),
                isEnabled: pinnedReferencePlan.isAvailable,
                shortcutHint: CinematicRunRecapShareArtifactCommandPlanner.shortcutHint(for: .copyPinnedExport),
                stateIdentifier: pinnedReferencePlan.exportIdentifier
            ),
            action(
                kind: .copyTourExport,
                section: .exports,
                label: tourPlan.isAvailable ? "Copy Tour Export" : "Tour Export Unavailable",
                systemImage: "sparkles",
                help: tourExportHelp(tourPlan),
                isEnabled: tourPlan.isAvailable && tourPlan.selectedEntryIdentifier != nil,
                shortcutHint: CinematicRunRecapShareArtifactCommandPlanner.shortcutHint(for: .copyTourExport),
                stateIdentifier: tourExportPlan?.exportIdentifier ?? tourPlan.identifier
            ),
            action(
                kind: .toggleComparisonTargetMode,
                section: .organize,
                label: "Use \(comparisonPlan.targetMode.toggled.title) Compare",
                systemImage: comparisonPlan.targetMode.toggled == .pinnedReference ? "pin" : "rectangle.split.2x1",
                help: comparisonModeToggleHelp(comparisonPlan),
                isEnabled: true,
                shortcutHint: CinematicRunRecapShareArtifactCommandPlanner.shortcutHint(for: .toggleComparisonTargetMode),
                stateIdentifier: comparisonPlan.targetModeIdentifier
            ),
            action(
                kind: .toggleSelectedPin,
                section: .organize,
                label: pinnedReferencePlan.selectedEntryIsPinned ? "Unpin Selected" : "Pin Selected",
                systemImage: pinnedReferencePlan.selectedEntryIsPinned ? "pin.slash" : "pin",
                help: togglePinHelp(pinnedReferencePlan, previewPlan: previewPlan),
                isEnabled: previewPlan.selectedEntryIdentifier != nil,
                shortcutHint: CinematicRunRecapShareArtifactCommandPlanner.shortcutHint(for: .toggleSelectedPin),
                stateIdentifier: pinnedReferencePlan.selectedPinStateIdentifier
            ),
            action(
                kind: .toggleTourHold,
                section: .tour,
                label: tourPlan.requestedSavedTourHoldEntryIdentifier == nil ? "Hold Tour Artifact" : "Release Tour Hold",
                systemImage: tourPlan.requestedSavedTourHoldEntryIdentifier == nil ? "lock" : "lock.open",
                help: tourHoldHelp(tourPlan),
                isEnabled: tourPlan.requestedSavedTourHoldEntryIdentifier != nil || tourPlan.selectedEntryIdentifier != nil,
                shortcutHint: CinematicRunRecapShareArtifactCommandPlanner.shortcutHint(for: .toggleTourHold),
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
                shortcutHint: CinematicRunRecapShareArtifactCommandPlanner.shortcutHint(for: .toggleSelectedTourHold),
                stateIdentifier: previewPlan.selectedEntryIdentifier ?? tourPlan.savedTourHoldStateIdentifier
            ),
            action(
                kind: .promoteTourHold,
                section: .tour,
                label: promoteTourHoldLabel(comparisonPlan),
                systemImage: comparisonPlan.promotedHoldStateIdentifier == "none" ? "pin.circle" : "pin.circle.fill",
                help: promoteTourHoldHelp(tourPlan, comparisonPlan: comparisonPlan),
                isEnabled: tourPlan.retainedSavedTourHoldEntryIdentifier != nil,
                shortcutHint: CinematicRunRecapShareArtifactCommandPlanner.shortcutHint(for: .promoteTourHold),
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

enum CinematicRunRecapShareArtifactCommandPlanner {
    static func plan(
        actionMenuPlan: CinematicRunRecapShareArtifactActionMenuPlan
    ) -> CinematicRunRecapShareArtifactCommandPlan {
        let commands = actionMenuPlan.actions.compactMap { action -> Command? in
            guard let shortcut = shortcut(for: action.actionKind) else { return nil }
            return command(for: action, shortcut: shortcut)
        }.prefix(CinematicRunRecapShareArtifactCommandPlan.commandLimit)

        let boundedCommands = Array(commands)
        let identifier = bounded(
            [
                "run-recap-share-artifact-commands",
                "commands:\(boundedCommands.count)",
                "source:\(fingerprint(actionMenuPlan.identifier))",
                "content:\(fingerprint(boundedCommands.map(\.identifier).joined(separator: "|")))"
            ].joined(separator: "|"),
            limit: CommandPlan.identifierMaxCharacters
        )

        return CinematicRunRecapShareArtifactCommandPlan(
            identifier: identifier,
            commands: boundedCommands
        )
    }

    static func shortcutHint(
        for actionKind: CinematicRunRecapShareArtifactActionMenuPlan.ActionKind
    ) -> String? {
        shortcut(for: actionKind)?.displayText
    }

    static func shortcut(
        for actionKind: CinematicRunRecapShareArtifactActionMenuPlan.ActionKind
    ) -> CinematicRunRecapShareArtifactCommandPlan.Shortcut? {
        switch actionKind {
        case .navigatePrevious:
            return Shortcut(key: .leftBracket, modifiers: [.command])
        case .navigateNext:
            return Shortcut(key: .rightBracket, modifiers: [.command])
        case .revealSelected:
            return Shortcut(key: .r, modifiers: [.command, .shift])
        case .copySelectedExport:
            return Shortcut(key: .e, modifiers: [.command, .shift])
        case .copyFilteredExport:
            return Shortcut(key: .e, modifiers: [.command, .option])
        case .copyLibraryExport:
            return Shortcut(key: .e, modifiers: [.command, .option, .shift])
        case .copyRollupExport:
            return Shortcut(key: .b, modifiers: [.command, .shift])
        case .copyComparisonExport:
            return Shortcut(key: .d, modifiers: [.command, .shift])
        case .copyPinnedExport:
            return Shortcut(key: .p, modifiers: [.command, .option, .shift])
        case .copyTourExport:
            return Shortcut(key: .t, modifiers: [.command, .option])
        case .toggleComparisonTargetMode:
            return Shortcut(key: .m, modifiers: [.command, .shift])
        case .toggleSelectedPin:
            return Shortcut(key: .p, modifiers: [.command, .shift])
        case .toggleTourHold:
            return Shortcut(key: .h, modifiers: [.command, .shift])
        case .toggleSelectedTourHold:
            return Shortcut(key: .h, modifiers: [.command, .option, .shift])
        case .promoteTourHold:
            return Shortcut(key: .p, modifiers: [.command, .option])
        case .cleanupOldArtifacts:
            return nil
        }
    }

    private typealias CommandPlan = CinematicRunRecapShareArtifactCommandPlan
    private typealias Command = CinematicRunRecapShareArtifactCommandPlan.Command
    private typealias Shortcut = CinematicRunRecapShareArtifactCommandPlan.Shortcut
    private typealias Action = CinematicRunRecapShareArtifactActionMenuPlan.Action

    private static func command(
        for action: Action,
        shortcut: Shortcut
    ) -> Command {
        let identifier = bounded(
            [
                "run-recap-share-artifact-command",
                "kind:\(action.actionKind.rawValue)",
                "section:\(action.section.rawValue)",
                "enabled:\(action.isEnabled)",
                "shortcut:\(shortcut.identifier)",
                "source:\(fingerprint(action.identifier))"
            ].joined(separator: "|"),
            limit: CommandPlan.identifierMaxCharacters
        )

        return Command(
            identifier: identifier,
            section: action.section,
            label: bounded(action.label, limit: CommandPlan.labelMaxCharacters),
            help: bounded(action.help, limit: CommandPlan.helpMaxCharacters),
            isEnabled: action.isEnabled,
            sourceActionKind: action.actionKind,
            shortcut: shortcut
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
        searchQuery: String? = nil,
        warningPulseFilter: CinematicRunRecapShareArtifactWarningPulseFilter = .all,
        sourceExportAuditPlan: CinematicRunRecapShareArtifactSourceExportAuditPlan? = nil
    ) -> CinematicRunRecapShareArtifactPinnedReferencePlan {
        let search = searchState(for: searchQuery)
        let retainedEntries = historyPlan.entries
        let filterState = CinematicRunRecapShareArtifactWarningPulseFiltering.state(
            filter: warningPulseFilter,
            entries: retainedEntries
        )
        let warningFilteredEntries = CinematicRunRecapShareArtifactWarningPulseFiltering.filteredEntries(
            retainedEntries,
            filter: warningPulseFilter
        )
        let matchingEntries = search.isActive
            ? warningFilteredEntries.filter { matches($0, normalizedQuery: search.normalizedQuery) }
            : warningFilteredEntries
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
        let filteredPinnedEntryIdentifiers = (search.isActive || filterState.isActive)
            ? retainedPinnedEntryIdentifiers.filter { !matchingEntryIdentifiers.contains($0) }
            : []
        let quickSelectEntryIdentifiers = retainedPinnedEntryIdentifiers.filter {
            !(search.isActive || filterState.isActive) || matchingEntryIdentifiers.contains($0)
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
        let noMatchAvailabilityReason = CinematicRunRecapShareArtifactWarningPulseFiltering
            .noMatchAvailabilityReason(
                retainedEntries: retainedEntries,
                warningFilteredEntries: warningFilteredEntries,
                matchingEntries: matchingEntries,
                searchIsActive: search.isActive,
                filter: warningPulseFilter
            )
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
        let includedSourceExportAuditPlan = visibleSourceExportAuditPlan(sourceExportAuditPlan)
        var exportIdentifierParts = [
            "run-recap-share-artifact-pins-export",
            "availability:\(availabilityReason)"
        ]
        if let includedSourceExportAuditPlan {
            exportIdentifierParts.append("source-audit:\(fingerprint(includedSourceExportAuditPlan.identifier))")
            exportIdentifierParts.append("source-audit-length:\(includedSourceExportAuditPlan.markdownLength)")
        }
        exportIdentifierParts.append(contentsOf: [
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
            "warning-pulse-filter:\(filterState.filterIdentifier)",
            "warning-pulse-filter-active:\(filterState.isActive)",
            "warning-pulse-filter-matches:\(filterState.matchingCount)",
            "warning-pulse-any:\(filterState.anyCount)",
            "warning-pulse-active:\(filterState.activeCount)",
            "warning-pulse-snoozed:\(filterState.snoozedCount)",
            "warning-pulse-unknown:\(filterState.unknownCount)",
            "no-match:\(noMatchAvailabilityReason ?? "none")",
            "selected:\(boundedSelectedEntryIdentifier ?? "none")",
            "selected-pin:\(selectedPinStateIdentifier)",
            "warnings:\(warningStateIdentifier)",
            "warning-count:\(historyPlan.warningCount)",
            "content:\(fingerprint(retainedPinnedEntryIdentifiers.joined(separator: "|")))"
        ])
        let exportIdentifier = bounded(
            exportIdentifierParts.joined(separator: "|"),
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
            filterState: filterState,
            noMatchAvailabilityReason: noMatchAvailabilityReason,
            selectedEntryIdentifier: boundedSelectedEntryIdentifier,
            selectedPinStateIdentifier: selectedPinStateIdentifier,
            requestedPinnedEntryIdentifiers: requestedPinnedEntryIdentifiers,
            retainedPinnedEntryIdentifiers: retainedPinnedEntryIdentifiers,
            missingPinnedEntryIdentifiers: missingPinnedEntryIdentifiers,
            filteredPinnedEntryIdentifiers: filteredPinnedEntryIdentifiers,
            quickSelectEntryIdentifiers: quickSelectEntryIdentifiers,
            references: references,
            warningStateIdentifier: warningStateIdentifier,
            sourceExportAuditPlan: includedSourceExportAuditPlan
        )
        var identifierParts = [
            "run-recap-share-artifact-pins",
            "availability:\(availabilityReason)",
            "export:\(fingerprint(exportIdentifier))",
            "pins:\(requestedPinnedEntryIdentifiers.count)",
            "retained-pins:\(retainedPinnedEntryIdentifiers.count)",
            "missing-pins:\(missingPinnedEntryIdentifiers.count)",
            "filtered-pins:\(filteredPinnedEntryIdentifiers.count)",
            "quick:\(quickSelectEntryIdentifiers.count)",
            "query:\(search.queryFingerprint)",
            "warning-pulse-filter:\(filterState.filterIdentifier)",
            "selected-pin:\(selectedPinStateIdentifier)",
            "warnings:\(warningStateIdentifier)",
            "copy:\(export.count)"
        ]
        if let includedSourceExportAuditPlan {
            identifierParts.append("source-audit:\(fingerprint(includedSourceExportAuditPlan.identifier))")
        }
        let identifier = bounded(
            identifierParts.joined(separator: "|"),
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
            warningPulseFilterIdentifier: filterState.filterIdentifier,
            isWarningPulseFilterActive: filterState.isActive,
            warningPulseFilterMatchCount: filterState.matchingCount,
            warningPulseAnyCount: filterState.anyCount,
            warningPulseActiveCount: filterState.activeCount,
            warningPulseSnoozedCount: filterState.snoozedCount,
            warningPulseUnknownCount: filterState.unknownCount,
            noMatchAvailabilityReason: noMatchAvailabilityReason,
            retainedEntryCount: retainedEntries.count,
            totalCount: historyPlan.totalCount,
            hiddenCount: historyPlan.hiddenCount,
            matchingEntryCount: matchingEntries.count,
            unfilteredVisibleCount: warningFilteredEntries.count,
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
            sourceExportAuditIncluded: includedSourceExportAuditPlan != nil,
            sourceExportAuditIdentifier: includedSourceExportAuditPlan?.identifier,
            sourceExportAuditMarkdownLength: includedSourceExportAuditPlan?.markdownLength ?? 0,
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
        filterState: CinematicRunRecapShareArtifactWarningPulseFilterState,
        noMatchAvailabilityReason: String?,
        selectedEntryIdentifier: String?,
        selectedPinStateIdentifier: String,
        requestedPinnedEntryIdentifiers: [String],
        retainedPinnedEntryIdentifiers: [String],
        missingPinnedEntryIdentifiers: [String],
        filteredPinnedEntryIdentifiers: [String],
        quickSelectEntryIdentifiers: [String],
        references: [CinematicRunRecapShareArtifactPinnedReferencePlan.Reference],
        warningStateIdentifier: String,
        sourceExportAuditPlan: CinematicRunRecapShareArtifactSourceExportAuditPlan?
    ) -> String {
        var lines = [
            "# Compass Recap Artifact Pins",
            "",
            "- Export: \(exportIdentifier)",
            "- Availability: \(isAvailable ? "available" : "unavailable (\(availabilityReason))")",
            "- Retention limit: \(historyPlan.retentionLimit)",
            "- Total artifacts: \(historyPlan.totalCount)"
        ]

        if let sourceExportAuditPlan {
            lines.append("- Source audit included: true")
            lines.append("- Source audit identifier: \(sourceExportAuditPlan.identifier)")
            lines.append("- Source audit markdown length: \(sourceExportAuditPlan.markdownLength)")
        }

        lines.append(contentsOf: [
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
            "- Warning pulse filter: \(filterState.filterIdentifier)",
            "- Warning pulse filter active: \(filterState.isActive)",
            "- Warning pulse filter matches: \(filterState.matchingCount)",
            "- Warning pulse any artifacts: \(filterState.anyCount)",
            "- Warning pulse active artifacts: \(filterState.activeCount)",
            "- Warning pulse snoozed artifacts: \(filterState.snoozedCount)",
            "- Warning pulse unknown artifacts: \(filterState.unknownCount)",
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
        ])

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

        return CinematicRunRecapShareArtifactSourceExportAuditPlanner.markdownExport(
            baseMarkdown: lines.joined(separator: "\n"),
            sourceExportAuditPlan: sourceExportAuditPlan,
            limit: CinematicRunRecapShareArtifactPinnedReferencePlan.exportTextMaxCharacters
        )
    }

    private static func visibleSourceExportAuditPlan(
        _ sourceExportAuditPlan: CinematicRunRecapShareArtifactSourceExportAuditPlan?
    ) -> CinematicRunRecapShareArtifactSourceExportAuditPlan? {
        guard let sourceExportAuditPlan,
              sourceExportAuditPlan.isVisible,
              !sourceExportAuditPlan.markdownSection.isEmpty else {
            return nil
        }
        return sourceExportAuditPlan
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
        let filterState = CinematicRunRecapShareArtifactWarningPulseFiltering.state(
            filter: libraryContext.warningPulseFilter,
            entries: retainedEntries
        )
        let warningFilteredEntries = CinematicRunRecapShareArtifactWarningPulseFiltering.filteredEntries(
            retainedEntries,
            filter: libraryContext.warningPulseFilter
        )
        let matchingEntries = search.isActive
            ? warningFilteredEntries.filter { matches($0, normalizedQuery: search.normalizedQuery) }
            : warningFilteredEntries
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
        let filteredSavedTourHoldEntryIdentifier = (search.isActive || filterState.isActive)
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
        let filteredPinnedEntryIdentifiers = (search.isActive || filterState.isActive)
            ? retainedPinnedEntryIdentifiers.filter { !matchingEntryIdentifiers.contains($0) }
            : []
        let visiblePinnedEntries = (search.isActive || filterState.isActive)
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
        let noMatchAvailabilityReason = CinematicRunRecapShareArtifactWarningPulseFiltering
            .noMatchAvailabilityReason(
                retainedEntries: retainedEntries,
                warningFilteredEntries: warningFilteredEntries,
                matchingEntries: matchingEntries,
                searchIsActive: search.isActive,
                filter: libraryContext.warningPulseFilter
            )
        let stateIdentifier = stateIdentifier(
            selectedEntry: selectedEntry,
            selectionSourceIdentifier: selectionSourceIdentifier,
            historyPlan: historyPlan,
            search: search,
            isWarningPulseFilterActive: filterState.isActive,
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
        let runtimeRouteCue = selectedEntry.flatMap {
            CinematicRunRecapShareArtifactRuntimeRouteCue(markdownContents: $0.markdownContents)
        }
        let runtimeRouteTreatment = CinematicRunRecapShareArtifactRuntimeRouteTreatmentDescriptor(
            cue: runtimeRouteCue
        )
        let mutationTestingCue = selectedEntry.flatMap {
            CinematicRunRecapShareArtifactMutationTestingCue(markdownContents: $0.markdownContents)
        }
        let mutationTestingTreatment = CinematicRunRecapShareArtifactMutationTestingTreatmentDescriptor(
            cue: mutationTestingCue
        )
        let warningPulseCue = selectedEntry.flatMap {
            CinematicRunRecapShareArtifactWarningPulseCue(markdownContents: $0.markdownContents)
        }
        let warningPulseTreatment = CinematicRunRecapShareArtifactWarningPulseTreatmentDescriptor(
            cue: warningPulseCue
        )
        var identifierParts = [
            "run-recap-share-artifact-tour",
            "availability:\(availabilityReason)",
            "state:\(stateIdentifier)",
            "source:\(selectionSourceIdentifier)",
            "mutation-state:\(mutationTestingTreatment.stateIdentifier)",
            "mutation-cue:\(fingerprint(mutationTestingCue?.identifier ?? "missing"))",
            "mutation-treatment:\(fingerprint(mutationTestingTreatment.identifier))",
            "warning-pulse-availability:\(warningPulseCue == nil ? "missing" : "available")",
            "warning-pulse-state:\(warningPulseTreatment.stateIdentifier)",
            "warning-pulse-count:\(warningPulseCue?.warningCount ?? 0)",
            "warning-pulse-cue:\(fingerprint(warningPulseCue?.identifier ?? "missing"))",
            "warning-pulse-audit:\(fingerprint(warningPulseCue?.auditIdentifier ?? "missing"))",
            "warning-pulse-bundle:\(fingerprint(warningPulseCue?.bundleIdentifier ?? "missing"))",
            "warning-pulse-warning-ids:\(fingerprint(warningPulseCue?.warningIdentifiers.joined(separator: "|") ?? "none"))",
            "warning-pulse-targets:\(fingerprint(warningPulseCue?.targetAnchors.joined(separator: "|") ?? "none"))",
            "warning-pulse-related:\(fingerprint(warningPulseCue?.relatedRowAnchors.joined(separator: "|") ?? "none"))",
            "warning-pulse-treatment:\(fingerprint(warningPulseTreatment.identifier))",
            "retained:\(retainedEntries.count)",
            "total:\(historyPlan.totalCount)",
            "hidden:\(historyPlan.hiddenCount)",
            "matching:\(matchingEntries.count)",
            "query:\(search.queryFingerprint)",
            "query-snippet:\(search.querySnippet)",
            "warning-pulse-filter:\(filterState.filterIdentifier)",
            "warning-pulse-filter-active:\(filterState.isActive)",
            "warning-pulse-filter-matches:\(filterState.matchingCount)",
            "warning-pulse-any:\(filterState.anyCount)",
            "warning-pulse-active:\(filterState.activeCount)",
            "warning-pulse-snoozed:\(filterState.snoozedCount)",
            "warning-pulse-unknown:\(filterState.unknownCount)",
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
        ]
        if let runtimeRouteCue {
            identifierParts.append("runtime-route:\(runtimeRouteCue.identifier)")
        }
        let identifier = bounded(
            identifierParts.joined(separator: "|"),
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
                warningPulseFilterIdentifier: filterState.filterIdentifier,
                isWarningPulseFilterActive: filterState.isActive,
                warningPulseFilterMatchCount: filterState.matchingCount,
                warningPulseAnyCount: filterState.anyCount,
                warningPulseActiveCount: filterState.activeCount,
                warningPulseSnoozedCount: filterState.snoozedCount,
                warningPulseUnknownCount: filterState.unknownCount,
                noMatchAvailabilityReason: noMatchAvailabilityReason,
                retainedEntryCount: retainedEntries.count,
                totalCount: historyPlan.totalCount,
                hiddenCount: historyPlan.hiddenCount,
                matchingEntryCount: matchingEntries.count,
                unfilteredVisibleCount: warningFilteredEntries.count,
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
                    filter: libraryContext.warningPulseFilter,
                    retainedCount: retainedEntries.count
                ),
                sessionText: "No saved session",
                runtimeRouteCue: runtimeRouteCue,
                runtimeRouteTreatment: runtimeRouteTreatment,
                mutationTestingCue: mutationTestingCue,
                mutationTestingTreatment: mutationTestingTreatment,
                warningPulseCue: warningPulseCue,
                warningPulseTreatment: warningPulseTreatment,
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
            warningPulseFilterIdentifier: filterState.filterIdentifier,
            isWarningPulseFilterActive: filterState.isActive,
            warningPulseFilterMatchCount: filterState.matchingCount,
            warningPulseAnyCount: filterState.anyCount,
            warningPulseActiveCount: filterState.activeCount,
            warningPulseSnoozedCount: filterState.snoozedCount,
            warningPulseUnknownCount: filterState.unknownCount,
            noMatchAvailabilityReason: noMatchAvailabilityReason,
            retainedEntryCount: retainedEntries.count,
            totalCount: historyPlan.totalCount,
            hiddenCount: historyPlan.hiddenCount,
            matchingEntryCount: matchingEntries.count,
            unfilteredVisibleCount: warningFilteredEntries.count,
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
            runtimeRouteCue: runtimeRouteCue,
            runtimeRouteTreatment: runtimeRouteTreatment,
            mutationTestingCue: mutationTestingCue,
            mutationTestingTreatment: mutationTestingTreatment,
            warningPulseCue: warningPulseCue,
            warningPulseTreatment: warningPulseTreatment,
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
        isWarningPulseFilterActive: Bool,
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
            if search.isActive || isWarningPulseFilterActive,
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
        if search.isActive || isWarningPulseFilterActive,
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
        filter: CinematicRunRecapShareArtifactWarningPulseFilter,
        retainedCount: Int
    ) -> String {
        let text: String
        switch stateIdentifier {
        case "missing-hold":
            text = "The held recap artifact is no longer retained; \(retainedCount) artifacts remain."
        case "filtered-hold":
            text = "The held recap artifact is hidden by the active archive search."
        case "no-match":
            if filter.isActive {
                text = search.isActive
                    ? "No retained \(filter.title.lowercased()) warning-pulse recap artifacts match \(search.querySnippet)."
                    : "No retained recap artifacts match the \(filter.title.lowercased()) warning-pulse filter."
            } else {
                text = "No retained recap artifacts match \(search.querySnippet)."
            }
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
        searchQuery: String? = nil,
        warningPulseFilter: CinematicRunRecapShareArtifactWarningPulseFilter = .all
    ) -> CinematicRunRecapShareArtifactPreviewBrowserPlan {
        let unfilteredEntries = historyPlan.entries
        let search = searchState(for: searchQuery)
        let filterState = CinematicRunRecapShareArtifactWarningPulseFiltering.state(
            filter: warningPulseFilter,
            entries: unfilteredEntries
        )
        let warningFilteredEntries = CinematicRunRecapShareArtifactWarningPulseFiltering.filteredEntries(
            unfilteredEntries,
            filter: warningPulseFilter
        )
        let entries = search.isActive
            ? warningFilteredEntries.filter { matches($0, normalizedQuery: search.normalizedQuery) }
            : warningFilteredEntries
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
            isSearchActive: search.isActive,
            isWarningPulseFilterActive: filterState.isActive
        )
        let previousEntryIdentifier = selectedIndex.flatMap { index in
            index > entries.startIndex ? entries[index - 1].identifier : nil
        }
        let nextEntryIdentifier = selectedIndex.flatMap { index in
            let nextIndex = index + 1
            return nextIndex < entries.endIndex ? entries[nextIndex].identifier : nil
        }
        let warningStateIdentifier = historyPlan.hasWarnings ? "warnings" : "clear"
        let noMatchAvailabilityReason = CinematicRunRecapShareArtifactWarningPulseFiltering
            .noMatchAvailabilityReason(
                retainedEntries: unfilteredEntries,
                warningFilteredEntries: warningFilteredEntries,
                matchingEntries: entries,
                searchIsActive: search.isActive,
                filter: warningPulseFilter
            )
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
                "unfiltered:\(warningFilteredEntries.count)",
                "warning-pulse-filter:\(filterState.filterIdentifier)",
                "warning-pulse-filter-active:\(filterState.isActive)",
                "warning-pulse-filter-matches:\(filterState.matchingCount)",
                "warning-pulse-any:\(filterState.anyCount)",
                "warning-pulse-active:\(filterState.activeCount)",
                "warning-pulse-snoozed:\(filterState.snoozedCount)",
                "warning-pulse-unknown:\(filterState.unknownCount)",
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
                warningPulseFilterIdentifier: filterState.filterIdentifier,
                isWarningPulseFilterActive: filterState.isActive,
                warningPulseFilterMatchCount: filterState.matchingCount,
                warningPulseAnyCount: filterState.anyCount,
                warningPulseActiveCount: filterState.activeCount,
                warningPulseSnoozedCount: filterState.snoozedCount,
                warningPulseUnknownCount: filterState.unknownCount,
                matchCount: entries.count,
                unfilteredVisibleCount: warningFilteredEntries.count,
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
                        noMatchAvailabilityReason: noMatchAvailabilityReason,
                        warningPulseFilter: warningPulseFilter
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
            warningPulseFilterIdentifier: filterState.filterIdentifier,
            isWarningPulseFilterActive: filterState.isActive,
            warningPulseFilterMatchCount: filterState.matchingCount,
            warningPulseAnyCount: filterState.anyCount,
            warningPulseActiveCount: filterState.activeCount,
            warningPulseSnoozedCount: filterState.snoozedCount,
            warningPulseUnknownCount: filterState.unknownCount,
            matchCount: entries.count,
            unfilteredVisibleCount: warningFilteredEntries.count,
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
        isSearchActive: Bool,
        isWarningPulseFilterActive: Bool
    ) -> (entryIdentifier: String?, reasonIdentifier: String) {
        guard let requestedIdentifier else {
            return (nil, "none")
        }
        if selectedEntry?.identifier == requestedIdentifier {
            return (nil, "none")
        }
        guard let selectedEntry else {
            let filteredAllEntries = (isSearchActive || isWarningPulseFilterActive)
                && !unfilteredEntries.isEmpty
                && filteredEntries.isEmpty
            return (nil, filteredAllEntries ? "no-match" : "missing-selection")
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
        noMatchAvailabilityReason: String?,
        warningPulseFilter: CinematicRunRecapShareArtifactWarningPulseFilter
    ) -> String {
        if noMatchAvailabilityReason == "no-matching-warning-pulse-artifacts" {
            return "No saved recap share artifacts match the \(warningPulseFilter.title.lowercased()) warning-pulse filter."
        }
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
        scope: Scope,
        warningPulseFilter: CinematicRunRecapShareArtifactWarningPulseFilter = .all,
        sourceExportAuditPlan: CinematicRunRecapShareArtifactSourceExportAuditPlan? = nil
    ) -> CinematicRunRecapShareArtifactSubsetExportPlan {
        let previewPlan = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: historyPlan,
            selectedEntryIdentifier: selectedEntryIdentifier,
            searchQuery: searchQuery,
            warningPulseFilter: warningPulseFilter
        )
        let search = searchState(for: searchQuery)
        let retainedEntries = historyPlan.entries
        let filterState = CinematicRunRecapShareArtifactWarningPulseFiltering.state(
            filter: warningPulseFilter,
            entries: retainedEntries
        )
        let warningFilteredEntries = CinematicRunRecapShareArtifactWarningPulseFiltering.filteredEntries(
            retainedEntries,
            filter: warningPulseFilter
        )
        let filteredEntries = search.isActive
            ? warningFilteredEntries.filter { matches($0, normalizedQuery: search.normalizedQuery) }
            : warningFilteredEntries
        let selectedEntry = previewPlan.selectedEntryIdentifier.flatMap { identifier in
            filteredEntries.first { $0.identifier == identifier }
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
        let noMatchAvailabilityReason = CinematicRunRecapShareArtifactWarningPulseFiltering
            .noMatchAvailabilityReason(
                retainedEntries: retainedEntries,
                warningFilteredEntries: warningFilteredEntries,
                matchingEntries: filteredEntries,
                searchIsActive: search.isActive,
                filter: warningPulseFilter
            )
        let availabilityReason = availabilityReason(
            scope: scope,
            exportEntries: exportEntries,
            historyPlan: historyPlan,
            previewPlan: previewPlan,
            noMatchAvailabilityReason: noMatchAvailabilityReason
        )
        let warningStateIdentifier = historyPlan.hasWarnings ? "warnings" : "clear"
        let exportedEntryIdentifiers = exportEntries.map(\.identifier)
        let warningPulseCues = exportEntries.compactMap {
            CinematicRunRecapShareArtifactWarningPulseCue(markdownContents: $0.markdownContents)
        }
        let warningPulseStateSummary = warningPulseSummary(warningPulseCues)
        let warningPulseAuditIdentifiers = warningPulseCues.map(\.auditIdentifier)
        let includedSourceExportAuditPlan = visibleSourceExportAuditPlan(sourceExportAuditPlan)
        var exportIdentifierParts = [
            "run-recap-share-artifact-subset-export",
            "scope:\(scope.rawValue)",
            "availability:\(availabilityReason)"
        ]
        if let includedSourceExportAuditPlan {
            exportIdentifierParts.append("source-audit:\(fingerprint(includedSourceExportAuditPlan.identifier))")
            exportIdentifierParts.append("source-audit-length:\(includedSourceExportAuditPlan.markdownLength)")
        }
        exportIdentifierParts.append(contentsOf: [
            "retention:\(historyPlan.retentionLimit)",
            "retained:\(retainedEntries.count)",
            "total:\(historyPlan.totalCount)",
            "hidden:\(historyPlan.hiddenCount)",
            "warning-pulse-filter:\(filterState.filterIdentifier)",
            "warning-pulse-filter-active:\(filterState.isActive)",
            "warning-pulse-filter-matches:\(filterState.matchingCount)",
            "warning-pulse-any:\(filterState.anyCount)",
            "warning-pulse-active:\(filterState.activeCount)",
            "warning-pulse-snoozed:\(filterState.snoozedCount)",
            "warning-pulse-unknown:\(filterState.unknownCount)",
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
            "warning-pulses:\(warningPulseCues.count)",
            "warning-pulse-summary:\(warningPulseStateSummary)",
            "warning-pulse-ids:\(fingerprint(warningPulseAuditIdentifiers.joined(separator: "|")))",
            "content:\(fingerprint(exportedEntryIdentifiers.joined(separator: "|")))"
        ])
        let exportIdentifier = bounded(
            exportIdentifierParts.joined(separator: "|"),
            limit: CinematicRunRecapShareArtifactSubsetExportPlan.identifierMaxCharacters
        )
        let markdown = markdownExport(
            exportIdentifier: exportIdentifier,
            scope: scope,
            availabilityReason: availabilityReason,
            entries: exportEntries,
            historyPlan: historyPlan,
            search: search,
            filterState: filterState,
            noMatchAvailabilityReason: noMatchAvailabilityReason,
            selectedEntry: selectedEntry,
            previewPlan: previewPlan,
            selectedCount: selectedCount,
            filteredCount: filteredCount,
            warningStateIdentifier: warningStateIdentifier,
            warningPulseCues: warningPulseCues,
            warningPulseStateSummary: warningPulseStateSummary,
            sourceExportAuditPlan: includedSourceExportAuditPlan
        )
        var identifierParts = [
            "run-recap-share-artifact-subset",
            "scope:\(scope.rawValue)",
            "availability:\(availabilityReason)",
            "export:\(fingerprint(exportIdentifier))",
            "entries:\(exportEntries.count)",
            "markdown:\(markdown.count)",
            "query:\(search.queryFingerprint)",
            "warning-pulse-filter:\(filterState.filterIdentifier)",
            "warnings:\(warningStateIdentifier)",
            "warning-pulses:\(warningPulseCues.count)"
        ]
        if let includedSourceExportAuditPlan {
            identifierParts.append("source-audit:\(fingerprint(includedSourceExportAuditPlan.identifier))")
        }
        let identifier = bounded(
            identifierParts.joined(separator: "|"),
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
            warningPulseFilterIdentifier: filterState.filterIdentifier,
            isWarningPulseFilterActive: filterState.isActive,
            warningPulseFilterMatchCount: filterState.matchingCount,
            warningPulseAnyCount: filterState.anyCount,
            warningPulseActiveCount: filterState.activeCount,
            warningPulseSnoozedCount: filterState.snoozedCount,
            warningPulseUnknownCount: filterState.unknownCount,
            noMatchAvailabilityReason: noMatchAvailabilityReason,
            retainedEntryCount: retainedEntries.count,
            totalCount: historyPlan.totalCount,
            hiddenCount: historyPlan.hiddenCount,
            selectedCount: selectedCount,
            filteredCount: filteredCount,
            exportEntryCount: exportEntries.count,
            unfilteredVisibleCount: warningFilteredEntries.count,
            selectedEntryIdentifier: selectedEntry?.identifier,
            selectedFallbackEntryIdentifier: previewPlan.selectedFallbackEntryIdentifier,
            selectedFallbackReasonIdentifier: previewPlan.selectedFallbackReasonIdentifier,
            exportedEntryIdentifiers: exportedEntryIdentifiers,
            warningStateIdentifier: warningStateIdentifier,
            warningCount: historyPlan.warningCount,
            hiddenWarningCount: historyPlan.hiddenWarningCount,
            warningIdentifiers: historyPlan.warnings.map(\.identifier),
            hasWarnings: historyPlan.hasWarnings,
            sourceExportAuditIncluded: includedSourceExportAuditPlan != nil,
            sourceExportAuditIdentifier: includedSourceExportAuditPlan?.identifier,
            sourceExportAuditMarkdownLength: includedSourceExportAuditPlan?.markdownLength ?? 0,
            warningPulseAuditCount: warningPulseCues.count,
            warningPulseStateSummary: warningPulseStateSummary,
            warningPulseAuditIdentifiers: warningPulseAuditIdentifiers,
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
        filterState: CinematicRunRecapShareArtifactWarningPulseFilterState,
        noMatchAvailabilityReason: String?,
        selectedEntry: CinematicRunRecapShareArtifactHistoryPlan.Entry?,
        previewPlan: CinematicRunRecapShareArtifactPreviewBrowserPlan,
        selectedCount: Int,
        filteredCount: Int,
        warningStateIdentifier: String,
        warningPulseCues: [CinematicRunRecapShareArtifactWarningPulseCue],
        warningPulseStateSummary: String,
        sourceExportAuditPlan: CinematicRunRecapShareArtifactSourceExportAuditPlan?
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
            "- Warning pulse filter: \(filterState.filterIdentifier)",
            "- Warning pulse filter active: \(filterState.isActive)",
            "- Warning pulse filter matches: \(filterState.matchingCount)",
            "- Warning pulse any artifacts: \(filterState.anyCount)",
            "- Warning pulse active artifacts: \(filterState.activeCount)",
            "- Warning pulse snoozed artifacts: \(filterState.snoozedCount)",
            "- Warning pulse unknown artifacts: \(filterState.unknownCount)",
            "- No-match reason: \(noMatchAvailabilityReason ?? "none")",
            "- Selected entry: \(selectedEntry?.identifier ?? "none")",
            "- Selection fallback: \(previewPlan.selectedFallbackEntryIdentifier ?? "none")",
            "- Selection fallback reason: \(previewPlan.selectedFallbackReasonIdentifier)",
            "- Cleanup candidates: \(historyPlan.cleanupCandidateCount)",
            "- Cleanup candidate identifiers: \(historyPlan.cleanupCandidateIdentifiers.isEmpty ? "none" : historyPlan.cleanupCandidateIdentifiers.joined(separator: ", "))",
            "- Warning state: \(warningStateIdentifier)",
            "- Warnings: \(historyPlan.warningCount)",
            "- Hidden warnings: \(historyPlan.hiddenWarningCount)",
            "- Warning identifiers: \(historyPlan.warnings.isEmpty ? "none" : historyPlan.warnings.map(\.identifier).joined(separator: ", "))",
            "- Warning pulse audits: \(warningPulseCues.count)",
            "- Warning pulse summary: \(warningPulseStateSummary)",
            "- Warning pulse audit identifiers: \(warningPulseCues.isEmpty ? "none" : warningPulseCues.map(\.auditIdentifier).joined(separator: ", "))"
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

        return CinematicRunRecapShareArtifactSourceExportAuditPlanner.markdownExport(
            baseMarkdown: lines.joined(separator: "\n"),
            sourceExportAuditPlan: sourceExportAuditPlan,
            limit: CinematicRunRecapShareArtifactSubsetExportPlan.markdownMaxCharacters
        )
    }

    private static func visibleSourceExportAuditPlan(
        _ sourceExportAuditPlan: CinematicRunRecapShareArtifactSourceExportAuditPlan?
    ) -> CinematicRunRecapShareArtifactSourceExportAuditPlan? {
        guard let sourceExportAuditPlan,
              sourceExportAuditPlan.isVisible,
              !sourceExportAuditPlan.markdownSection.isEmpty else {
            return nil
        }
        return sourceExportAuditPlan
    }

    private static func warningPulseSummary(
        _ cues: [CinematicRunRecapShareArtifactWarningPulseCue]
    ) -> String {
        guard !cues.isEmpty else { return "none" }
        let active = cues.filter { $0.stateIdentifier == "active" }.count
        let snoozed = cues.filter { $0.stateIdentifier == "snoozed" }.count
        let unknown = max(0, cues.count - active - snoozed)
        var parts: [String] = []
        if active > 0 {
            parts.append("active \(active)")
        }
        if snoozed > 0 {
            parts.append("snoozed \(snoozed)")
        }
        if unknown > 0 {
            parts.append("unknown \(unknown)")
        }
        return bounded(
            parts.joined(separator: ", "),
            limit: CinematicRunRecapShareArtifactRollupPlan.statusBucketSummaryMaxCharacters
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
        searchQuery: String? = nil,
        warningPulseFilter: CinematicRunRecapShareArtifactWarningPulseFilter = .all,
        sourceExportAuditPlan: CinematicRunRecapShareArtifactSourceExportAuditPlan? = nil
    ) -> CinematicRunRecapShareArtifactRollupPlan {
        let previewPlan = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: historyPlan,
            selectedEntryIdentifier: selectedEntryIdentifier,
            searchQuery: searchQuery,
            warningPulseFilter: warningPulseFilter
        )
        let search = searchState(for: searchQuery)
        let retainedEntries = historyPlan.entries
        let filterState = CinematicRunRecapShareArtifactWarningPulseFiltering.state(
            filter: warningPulseFilter,
            entries: retainedEntries
        )
        let warningFilteredEntries = CinematicRunRecapShareArtifactWarningPulseFiltering.filteredEntries(
            retainedEntries,
            filter: warningPulseFilter
        )
        let matchingEntries = search.isActive
            ? warningFilteredEntries.filter { matches($0, normalizedQuery: search.normalizedQuery) }
            : warningFilteredEntries
        let noMatchAvailabilityReason = CinematicRunRecapShareArtifactWarningPulseFiltering
            .noMatchAvailabilityReason(
                retainedEntries: retainedEntries,
                warningFilteredEntries: warningFilteredEntries,
                matchingEntries: matchingEntries,
                searchIsActive: search.isActive,
                filter: warningPulseFilter
            )
        let availabilityReason = noMatchAvailabilityReason
            ?? (matchingEntries.isEmpty ? historyPlan.availabilityReason : "available")
        let isAvailable = !matchingEntries.isEmpty
        let warningStateIdentifier = historyPlan.hasWarnings ? "warnings" : "clear"
        let newestEntry = matchingEntries.first
        let oldestEntry = matchingEntries.last
        let sessionRangeLabel = sessionRangeLabel(entries: matchingEntries)
        let statusBuckets = statusBuckets(for: matchingEntries)
        let statusBucketSummary = bucketSummary(statusBuckets)
        let mutationTestingCues = matchingEntries.compactMap {
            CinematicRunRecapShareArtifactMutationTestingCue(markdownContents: $0.markdownContents)
        }
        let mutationTestingSummary = mutationTestingSummary(mutationTestingCues)
        let warningPulseCues = matchingEntries.compactMap {
            CinematicRunRecapShareArtifactWarningPulseCue(markdownContents: $0.markdownContents)
        }
        let warningPulseStateSummary = warningPulseSummary(warningPulseCues)
        let warningPulseAuditIdentifiers = warningPulseCues.map(\.auditIdentifier)
        let includedSourceExportAuditPlan = visibleSourceExportAuditPlan(sourceExportAuditPlan)
        var exportIdentifierParts = [
            "run-recap-share-artifact-rollup-export",
            "availability:\(availabilityReason)"
        ]
        if let includedSourceExportAuditPlan {
            exportIdentifierParts.append("source-audit:\(fingerprint(includedSourceExportAuditPlan.identifier))")
            exportIdentifierParts.append("source-audit-length:\(includedSourceExportAuditPlan.markdownLength)")
        }
        exportIdentifierParts.append(contentsOf: [
            "retained:\(retainedEntries.count)",
            "total:\(historyPlan.totalCount)",
            "hidden:\(historyPlan.hiddenCount)",
            "matching:\(matchingEntries.count)",
            "query:\(search.queryFingerprint)",
            "query-snippet:\(search.querySnippet)",
            "warning-pulse-filter:\(filterState.filterIdentifier)",
            "warning-pulse-filter-active:\(filterState.isActive)",
            "warning-pulse-filter-matches:\(filterState.matchingCount)",
            "warning-pulse-any:\(filterState.anyCount)",
            "warning-pulse-active:\(filterState.activeCount)",
            "warning-pulse-snoozed:\(filterState.snoozedCount)",
            "warning-pulse-unknown:\(filterState.unknownCount)",
            "no-match:\(noMatchAvailabilityReason ?? "none")",
            "selected:\(previewPlan.selectedEntryIdentifier ?? "none")",
            "fallback:\(previewPlan.selectedFallbackEntryIdentifier ?? "none")",
            "fallback-reason:\(previewPlan.selectedFallbackReasonIdentifier)",
            "range:\(sessionRangeLabel)",
            "buckets:\(statusBucketSummary)",
            "mutation-tests:\(mutationTestingCues.count)",
            "mutation-summary:\(mutationTestingSummary)",
            "warning-pulses:\(warningPulseCues.count)",
            "warning-pulse-summary:\(warningPulseStateSummary)",
            "warning-pulse-ids:\(fingerprint(warningPulseAuditIdentifiers.joined(separator: "|")))",
            "cleanup:\(historyPlan.cleanupCandidateCount)",
            "warnings:\(warningStateIdentifier)",
            "warning-count:\(historyPlan.warningCount)",
            "content:\(fingerprint(matchingEntries.map(\.identifier).joined(separator: "|")))"
        ])
        let exportIdentifier = bounded(
            exportIdentifierParts.joined(separator: "|"),
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
            mutationTestingAuditCount: mutationTestingCues.count,
            mutationTestingSummary: mutationTestingSummary,
            warningPulseAuditCount: warningPulseCues.count,
            warningPulseStateSummary: warningPulseStateSummary,
            cleanupCandidateCount: historyPlan.cleanupCandidateCount,
            warningCount: historyPlan.warningCount,
            search: search,
            filterState: filterState
        )
        let export = exportText(
            exportIdentifier: exportIdentifier,
            isAvailable: isAvailable,
            availabilityReason: availabilityReason,
            retainedEntries: retainedEntries,
            matchingEntries: matchingEntries,
            historyPlan: historyPlan,
            search: search,
            filterState: filterState,
            noMatchAvailabilityReason: noMatchAvailabilityReason,
            previewPlan: previewPlan,
            sessionRangeLabel: sessionRangeLabel,
            statusBuckets: statusBuckets,
            statusBucketSummary: statusBucketSummary,
            mutationTestingCues: mutationTestingCues,
            mutationTestingSummary: mutationTestingSummary,
            warningPulseCues: warningPulseCues,
            warningPulseStateSummary: warningPulseStateSummary,
            insightText: insight,
            warningStateIdentifier: warningStateIdentifier,
            sourceExportAuditPlan: includedSourceExportAuditPlan
        )
        var identifierParts = [
            "run-recap-share-artifact-rollup",
            "availability:\(availabilityReason)",
            "export:\(fingerprint(exportIdentifier))",
            "retained:\(retainedEntries.count)",
            "matching:\(matchingEntries.count)",
            "query:\(search.queryFingerprint)",
            "warning-pulse-filter:\(filterState.filterIdentifier)",
            "range:\(sessionRangeLabel)",
            "buckets:\(statusBucketSummary)",
            "mutation-tests:\(mutationTestingCues.count)",
            "warning-pulses:\(warningPulseCues.count)",
            "cleanup:\(historyPlan.cleanupCandidateCount)",
            "warnings:\(warningStateIdentifier)",
            "copy:\(export.count)"
        ]
        if let includedSourceExportAuditPlan {
            identifierParts.append("source-audit:\(fingerprint(includedSourceExportAuditPlan.identifier))")
        }
        let identifier = bounded(
            identifierParts.joined(separator: "|"),
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
            warningPulseFilterIdentifier: filterState.filterIdentifier,
            isWarningPulseFilterActive: filterState.isActive,
            warningPulseFilterMatchCount: filterState.matchingCount,
            warningPulseAnyCount: filterState.anyCount,
            warningPulseActiveCount: filterState.activeCount,
            warningPulseSnoozedCount: filterState.snoozedCount,
            warningPulseUnknownCount: filterState.unknownCount,
            noMatchAvailabilityReason: noMatchAvailabilityReason,
            retainedEntryCount: retainedEntries.count,
            totalCount: historyPlan.totalCount,
            hiddenCount: historyPlan.hiddenCount,
            matchingEntryCount: matchingEntries.count,
            unfilteredVisibleCount: warningFilteredEntries.count,
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
            sourceExportAuditIncluded: includedSourceExportAuditPlan != nil,
            sourceExportAuditIdentifier: includedSourceExportAuditPlan?.identifier,
            sourceExportAuditMarkdownLength: includedSourceExportAuditPlan?.markdownLength ?? 0,
            mutationTestingAuditCount: mutationTestingCues.count,
            mutationTestingSummary: mutationTestingSummary,
            warningPulseAuditCount: warningPulseCues.count,
            warningPulseStateSummary: warningPulseStateSummary,
            warningPulseAuditIdentifiers: warningPulseAuditIdentifiers,
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
        mutationTestingAuditCount: Int,
        mutationTestingSummary: String,
        warningPulseAuditCount: Int,
        warningPulseStateSummary: String,
        cleanupCandidateCount: Int,
        warningCount: Int,
        search: SearchState,
        filterState: CinematicRunRecapShareArtifactWarningPulseFilterState
    ) -> String {
        guard isAvailable else {
            let searchDetail = search.isActive ? " for \(search.querySnippet)" : ""
            let filterDetail = filterState.isActive ? " with \(filterState.filter.title.lowercased()) pulse filter" : ""
            return bounded(
                "No recap artifact rollup\(searchDetail)\(filterDetail): \(availabilityReason). \(retainedCount)/\(totalCount) retained.",
                limit: CinematicRunRecapShareArtifactRollupPlan.insightTextMaxCharacters
            )
        }

        var parts = [
            "\(matchingCount)/\(retainedCount) retained",
            "sessions \(sessionRangeLabel)",
            statusBucketSummary
        ]
        if mutationTestingAuditCount > 0 {
            parts.append("mutation \(mutationTestingSummary)")
        }
        if warningPulseAuditCount > 0 {
            parts.append("warning pulse \(warningPulseStateSummary)")
        }
        if search.isActive {
            parts.append("search \(search.querySnippet)")
        }
        if filterState.isActive {
            parts.append("\(filterState.filter.title.lowercased()) pulse \(filterState.matchingCount)")
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
        filterState: CinematicRunRecapShareArtifactWarningPulseFilterState,
        noMatchAvailabilityReason: String?,
        previewPlan: CinematicRunRecapShareArtifactPreviewBrowserPlan,
        sessionRangeLabel: String,
        statusBuckets: [CinematicRunRecapShareArtifactRollupPlan.StatusBucket],
        statusBucketSummary: String,
        mutationTestingCues: [CinematicRunRecapShareArtifactMutationTestingCue],
        mutationTestingSummary: String,
        warningPulseCues: [CinematicRunRecapShareArtifactWarningPulseCue],
        warningPulseStateSummary: String,
        insightText: String,
        warningStateIdentifier: String,
        sourceExportAuditPlan: CinematicRunRecapShareArtifactSourceExportAuditPlan?
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
            "- Warning pulse filter: \(filterState.filterIdentifier)",
            "- Warning pulse filter active: \(filterState.isActive)",
            "- Warning pulse filter matches: \(filterState.matchingCount)",
            "- Warning pulse any artifacts: \(filterState.anyCount)",
            "- Warning pulse active artifacts: \(filterState.activeCount)",
            "- Warning pulse snoozed artifacts: \(filterState.snoozedCount)",
            "- Warning pulse unknown artifacts: \(filterState.unknownCount)",
            "- No-match reason: \(noMatchAvailabilityReason ?? "none")",
            "- Selected entry: \(previewPlan.selectedEntryIdentifier ?? "none")",
            "- Selection fallback: \(previewPlan.selectedFallbackEntryIdentifier ?? "none")",
            "- Selection fallback reason: \(previewPlan.selectedFallbackReasonIdentifier)",
            "- Status buckets: \(statusBucketSummary)",
            "- Mutation test audits: \(mutationTestingCues.count)",
            "- Mutation test summary: \(mutationTestingSummary)",
            "- Warning pulse audits: \(warningPulseCues.count)",
            "- Warning pulse summary: \(warningPulseStateSummary)",
            "- Warning pulse audit identifiers: \(warningPulseCues.isEmpty ? "none" : warningPulseCues.map(\.auditIdentifier).joined(separator: ", "))",
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

        let runtimeRouteLines = matchingEntries.compactMap(runtimeRouteLine)
        if !runtimeRouteLines.isEmpty {
            lines.append("")
            lines.append("## Runtime Routes")
            lines.append(contentsOf: runtimeRouteLines)
        }

        let mutationTestingLines = matchingEntries.compactMap(mutationTestingLine)
        if !mutationTestingLines.isEmpty {
            lines.append("")
            lines.append("## Mutation Tests")
            lines.append(contentsOf: mutationTestingLines)
        }

        let warningPulseLines = matchingEntries.compactMap(warningPulseLine)
        if !warningPulseLines.isEmpty {
            lines.append("")
            lines.append("## Diagnostics Warning Pulses")
            lines.append(contentsOf: warningPulseLines)
        }

        return CinematicRunRecapShareArtifactSourceExportAuditPlanner.markdownExport(
            baseMarkdown: lines.joined(separator: "\n"),
            sourceExportAuditPlan: sourceExportAuditPlan,
            limit: CinematicRunRecapShareArtifactRollupPlan.exportTextMaxCharacters
        )
    }

    private static func runtimeRouteLine(
        for entry: CinematicRunRecapShareArtifactHistoryPlan.Entry
    ) -> String? {
        guard let cue = CinematicRunRecapShareArtifactRuntimeRouteCue(
            markdownContents: entry.markdownContents
        ) else {
            return nil
        }
        return bounded(
            "- S\(entry.sessionNumber) \(entry.filename): \(cue.detailCopy)",
            limit: CinematicRunRecapShareArtifactRollupPlan.exportTextMaxCharacters
        )
    }

    private static func mutationTestingSummary(
        _ cues: [CinematicRunRecapShareArtifactMutationTestingCue]
    ) -> String {
        guard !cues.isEmpty else { return "none" }
        let succeeded = cues.filter { $0.statusIdentifier == "succeeded" }.count
        let failed = cues.filter { $0.statusIdentifier == "failed" }.count
        let unknown = max(0, cues.count - succeeded - failed)
        var parts: [String] = []
        if succeeded > 0 {
            parts.append("succeeded \(succeeded)")
        }
        if failed > 0 {
            parts.append("failed \(failed)")
        }
        if unknown > 0 {
            parts.append("unknown \(unknown)")
        }
        return bounded(
            parts.joined(separator: ", "),
            limit: CinematicRunRecapShareArtifactRollupPlan.statusBucketSummaryMaxCharacters
        )
    }

    private static func warningPulseSummary(
        _ cues: [CinematicRunRecapShareArtifactWarningPulseCue]
    ) -> String {
        guard !cues.isEmpty else { return "none" }
        let active = cues.filter { $0.stateIdentifier == "active" }.count
        let snoozed = cues.filter { $0.stateIdentifier == "snoozed" }.count
        let unknown = max(0, cues.count - active - snoozed)
        var parts: [String] = []
        if active > 0 {
            parts.append("active \(active)")
        }
        if snoozed > 0 {
            parts.append("snoozed \(snoozed)")
        }
        if unknown > 0 {
            parts.append("unknown \(unknown)")
        }
        return bounded(
            parts.joined(separator: ", "),
            limit: CinematicRunRecapShareArtifactRollupPlan.statusBucketSummaryMaxCharacters
        )
    }

    private static func mutationTestingLine(
        for entry: CinematicRunRecapShareArtifactHistoryPlan.Entry
    ) -> String? {
        guard let cue = CinematicRunRecapShareArtifactMutationTestingCue(
            markdownContents: entry.markdownContents
        ) else {
            return nil
        }
        return bounded(
            "- S\(entry.sessionNumber) \(entry.filename): \(cue.detailCopy)",
            limit: CinematicRunRecapShareArtifactRollupPlan.exportTextMaxCharacters
        )
    }

    private static func warningPulseLine(
        for entry: CinematicRunRecapShareArtifactHistoryPlan.Entry
    ) -> String? {
        guard let cue = CinematicRunRecapShareArtifactWarningPulseCue(
            markdownContents: entry.markdownContents
        ) else {
            return nil
        }
        return bounded(
            "- S\(entry.sessionNumber) \(entry.filename): \(cue.detailCopy)",
            limit: CinematicRunRecapShareArtifactRollupPlan.exportTextMaxCharacters
        )
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

    private static func visibleSourceExportAuditPlan(
        _ sourceExportAuditPlan: CinematicRunRecapShareArtifactSourceExportAuditPlan?
    ) -> CinematicRunRecapShareArtifactSourceExportAuditPlan? {
        guard let sourceExportAuditPlan,
              sourceExportAuditPlan.isVisible,
              !sourceExportAuditPlan.markdownSection.isEmpty else {
            return nil
        }
        return sourceExportAuditPlan
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
        savedTourHoldEntryIdentifier: String? = nil,
        warningPulseFilter: CinematicRunRecapShareArtifactWarningPulseFilter = .all,
        sourceExportAuditPlan: CinematicRunRecapShareArtifactSourceExportAuditPlan? = nil
    ) -> CinematicRunRecapShareArtifactComparisonPlan {
        let previewPlan = CinematicRunRecapShareArtifactPreviewBrowserPlanner.plan(
            historyPlan: historyPlan,
            selectedEntryIdentifier: selectedEntryIdentifier,
            searchQuery: searchQuery,
            warningPulseFilter: warningPulseFilter
        )
        let search = searchState(for: searchQuery)
        let retainedEntries = historyPlan.entries
        let filterState = CinematicRunRecapShareArtifactWarningPulseFiltering.state(
            filter: warningPulseFilter,
            entries: retainedEntries
        )
        let warningFilteredEntries = CinematicRunRecapShareArtifactWarningPulseFiltering.filteredEntries(
            retainedEntries,
            filter: warningPulseFilter
        )
        let matchingEntries = search.isActive
            ? warningFilteredEntries.filter { matches($0, normalizedQuery: search.normalizedQuery) }
            : warningFilteredEntries
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
        let filteredSavedTourHoldEntryIdentifier = (search.isActive || filterState.isActive)
            ? retainedSavedTourHoldEntry
                .flatMap { matchingEntryIdentifiers.contains($0.identifier) ? nil : $0.identifier }
            : nil
        let missingPinnedEntryIdentifiers = requestedPinnedEntryIdentifiers.filter {
            retainedEntriesByIdentifier[$0] == nil
        }
        let filteredPinnedEntryIdentifiers = (search.isActive || filterState.isActive)
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
                    search: search,
                    isWarningPulseFilterActive: filterState.isActive
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
            search: search,
            isWarningPulseFilterActive: filterState.isActive
        )
        let pinnedTargetUnavailableReasonIdentifier = targetMode == .pinnedReference && compareEntry == nil
            ? pinnedTargetStateIdentifier
            : nil
        let sessionDelta = selectedEntry.flatMap { selected in
            compareEntry.map { abs(selected.sessionNumber - $0.sessionNumber) }
        }
        let noMatchAvailabilityReason = CinematicRunRecapShareArtifactWarningPulseFiltering
            .noMatchAvailabilityReason(
                retainedEntries: retainedEntries,
                warningFilteredEntries: warningFilteredEntries,
                matchingEntries: matchingEntries,
                searchIsActive: search.isActive,
                filter: warningPulseFilter
            )
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
            isWarningPulseFilterActive: filterState.isActive,
            noMatchAvailabilityReason: noMatchAvailabilityReason
        )
        let isAvailable = compareEntry != nil
        let warningStateIdentifier = historyPlan.hasWarnings ? "warnings" : "clear"
        let selectedBodyPreviewText = selectedEntry.map { bodyPreview(from: $0.markdownContents) }
        let compareBodyPreviewText = compareEntry.map { bodyPreview(from: $0.markdownContents) }
        let includedSourceExportAuditPlan = visibleSourceExportAuditPlan(sourceExportAuditPlan)
        var exportIdentifierParts = [
            "run-recap-share-artifact-comparison-export",
            "availability:\(availabilityReason)",
        ]
        if let includedSourceExportAuditPlan {
            exportIdentifierParts.append("source-audit:\(fingerprint(includedSourceExportAuditPlan.identifier))")
            exportIdentifierParts.append("source-audit-length:\(includedSourceExportAuditPlan.markdownLength)")
        }
        exportIdentifierParts.append(contentsOf: [
            "retained:\(retainedEntries.count)",
            "total:\(historyPlan.totalCount)",
            "hidden:\(historyPlan.hiddenCount)",
            "matching:\(matchingEntries.count)",
            "mode:\(targetMode.rawValue)",
            "query:\(search.queryFingerprint)",
            "query-snippet:\(search.querySnippet)",
            "warning-pulse-filter:\(filterState.filterIdentifier)",
            "warning-pulse-filter-active:\(filterState.isActive)",
            "warning-pulse-filter-matches:\(filterState.matchingCount)",
            "warning-pulse-any:\(filterState.anyCount)",
            "warning-pulse-active:\(filterState.activeCount)",
            "warning-pulse-snoozed:\(filterState.snoozedCount)",
            "warning-pulse-unknown:\(filterState.unknownCount)",
            "no-match:\(noMatchAvailabilityReason ?? "none")",
            "selected:\(selectedEntry?.identifier ?? "none")",
            "compare:\(compareEntry?.identifier ?? "none")",
            "direction:\(targetDirectionIdentifier)",
            "pinned-target:\(pinnedTargetEntryIdentifier ?? "none")",
            "pinned-state:\(pinnedTargetStateIdentifier)"
        ])
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
            filterState: filterState,
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
            warningStateIdentifier: warningStateIdentifier,
            sourceExportAuditPlan: includedSourceExportAuditPlan
        )
        var identifierParts = [
            "run-recap-share-artifact-comparison",
            "availability:\(availabilityReason)",
            "export:\(fingerprint(exportIdentifier))",
            "retained:\(retainedEntries.count)",
            "matching:\(matchingEntries.count)",
            "mode:\(targetMode.rawValue)",
            "query:\(search.queryFingerprint)",
            "warning-pulse-filter:\(filterState.filterIdentifier)",
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
        if let includedSourceExportAuditPlan {
            identifierParts.append("source-audit:\(fingerprint(includedSourceExportAuditPlan.identifier))")
        }
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
            warningPulseFilterIdentifier: filterState.filterIdentifier,
            isWarningPulseFilterActive: filterState.isActive,
            warningPulseFilterMatchCount: filterState.matchingCount,
            warningPulseAnyCount: filterState.anyCount,
            warningPulseActiveCount: filterState.activeCount,
            warningPulseSnoozedCount: filterState.snoozedCount,
            warningPulseUnknownCount: filterState.unknownCount,
            noMatchAvailabilityReason: noMatchAvailabilityReason,
            retainedEntryCount: retainedEntries.count,
            totalCount: historyPlan.totalCount,
            hiddenCount: historyPlan.hiddenCount,
            matchingEntryCount: matchingEntries.count,
            unfilteredVisibleCount: warningFilteredEntries.count,
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
            sourceExportAuditIncluded: includedSourceExportAuditPlan != nil,
            sourceExportAuditIdentifier: includedSourceExportAuditPlan?.identifier,
            sourceExportAuditMarkdownLength: includedSourceExportAuditPlan?.markdownLength ?? 0,
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
        search: SearchState,
        isWarningPulseFilterActive: Bool
    ) -> ComparisonTarget? {
        let nonSelectedPinnedEntries = retainedPinnedEntries.filter {
            $0.identifier != selectedEntry.identifier
        }
        let visiblePinnedEntries = (search.isActive || isWarningPulseFilterActive)
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
        search: SearchState,
        isWarningPulseFilterActive: Bool
    ) -> String {
        guard targetMode == .pinnedReference else {
            return "adjacent-mode"
        }
        guard let selectedEntry else {
            return "no-selected-recap-share-artifact"
        }
        if let compareEntry {
            return (search.isActive || isWarningPulseFilterActive)
                && filteredPinnedEntryIdentifiers.contains(compareEntry.identifier)
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
        isWarningPulseFilterActive: Bool,
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
            return search.isActive || isWarningPulseFilterActive
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
        filterState: CinematicRunRecapShareArtifactWarningPulseFilterState,
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
        warningStateIdentifier: String,
        sourceExportAuditPlan: CinematicRunRecapShareArtifactSourceExportAuditPlan?
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
            "- Total artifacts: \(historyPlan.totalCount)"
        ]

        if let sourceExportAuditPlan {
            lines.append("- Source audit included: true")
            lines.append("- Source audit identifier: \(sourceExportAuditPlan.identifier)")
            lines.append("- Source audit markdown length: \(sourceExportAuditPlan.markdownLength)")
        }

        lines.append(contentsOf: [
            "- Retained artifacts: \(retainedEntries.count)",
            "- Matching artifacts: \(matchingEntries.count)",
            "- Hidden artifacts: \(historyPlan.hiddenCount)",
            "- Comparison mode: \(targetMode.rawValue)",
            "- Search active: \(search.isActive)",
            "- Search query: \(search.querySnippet)",
            "- Search fingerprint: \(search.queryFingerprint)",
            "- Warning pulse filter: \(filterState.filterIdentifier)",
            "- Warning pulse filter active: \(filterState.isActive)",
            "- Warning pulse filter matches: \(filterState.matchingCount)",
            "- Warning pulse any artifacts: \(filterState.anyCount)",
            "- Warning pulse active artifacts: \(filterState.activeCount)",
            "- Warning pulse snoozed artifacts: \(filterState.snoozedCount)",
            "- Warning pulse unknown artifacts: \(filterState.unknownCount)",
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
        ])

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
            return CinematicRunRecapShareArtifactSourceExportAuditPlanner.markdownExport(
                baseMarkdown: lines.joined(separator: "\n"),
                sourceExportAuditPlan: sourceExportAuditPlan,
                limit: CinematicRunRecapShareArtifactComparisonPlan.exportTextMaxCharacters
            )
        }

        lines.append("")
        lines.append("## Selected Artifact")
        lines.append(contentsOf: entryLines(entry: selectedEntry, bodyPreviewText: selectedBodyPreviewText))
        lines.append("")
        lines.append("## Comparison Target")
        lines.append(contentsOf: entryLines(entry: compareEntry, bodyPreviewText: compareBodyPreviewText))

        return CinematicRunRecapShareArtifactSourceExportAuditPlanner.markdownExport(
            baseMarkdown: lines.joined(separator: "\n"),
            sourceExportAuditPlan: sourceExportAuditPlan,
            limit: CinematicRunRecapShareArtifactComparisonPlan.exportTextMaxCharacters
        )
    }

    private static func visibleSourceExportAuditPlan(
        _ sourceExportAuditPlan: CinematicRunRecapShareArtifactSourceExportAuditPlan?
    ) -> CinematicRunRecapShareArtifactSourceExportAuditPlan? {
        guard let sourceExportAuditPlan,
              sourceExportAuditPlan.isVisible,
              !sourceExportAuditPlan.markdownSection.isEmpty else {
            return nil
        }
        return sourceExportAuditPlan
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
            storageRootDisplayText: storageRootDisplayPath(storageRootURL),
            sessionsDisplayText: sessionsDisplayPath(storageRootURL: storageRootURL, sessionsURL: sessionsURL),
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
            "- Storage root: \(storageRootDisplayPath(storageRootURL))",
            "- Sessions path: \(sessionsDisplayPath(storageRootURL: storageRootURL, sessionsURL: sessionsURL))",
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

    private static func storageRootDisplayPath(_ url: URL?) -> String {
        guard let url else { return "unavailable" }
        let lastPathComponent = url.standardizedFileURL.lastPathComponent
        return boundedPath(lastPathComponent.isEmpty ? "storage-root" : lastPathComponent)
    }

    private static func sessionsDisplayPath(storageRootURL: URL?, sessionsURL: URL?) -> String {
        guard let sessionsURL else { return "unavailable" }
        let sessionsPath = sessionsURL.standardizedFileURL.path
        if let storageRootURL {
            let rootPath = storageRootURL.standardizedFileURL.path
            if sessionsPath == rootPath {
                return storageRootDisplayPath(storageRootURL)
            }
            if sessionsPath.hasPrefix(rootPath + "/") {
                let relative = String(sessionsPath.dropFirst(rootPath.count + 1))
                return boundedPath("\(storageRootDisplayPath(storageRootURL))/\(relative)")
            }
        }
        let lastPathComponent = sessionsURL.standardizedFileURL.lastPathComponent
        return boundedPath(lastPathComponent.isEmpty ? "sessions" : lastPathComponent)
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

enum CinematicRunRecapShareArtifactSourceReconciliationPlanner {
    static func plan(
        activeHistoryPlan: CinematicRunRecapShareArtifactHistoryPlan,
        activitySourceSnapshot: RepositoryActivitySourceSnapshot,
        workspace: CompassWorkspace,
        fileManager: FileManager = .default
    ) -> CinematicRunRecapShareArtifactSourceReconciliationPlan {
        let repoLocalHistoryPlan: CinematicRunRecapShareArtifactHistoryPlan?
        if activitySourceSnapshot.activeStorage == .applicationSupport {
            let repoLocalStorageRootURL = workspace.repoLocalCompassURL
            repoLocalHistoryPlan = CinematicRunRecapShareArtifactHistoryPlanner.plan(
                storageRootURL: repoLocalStorageRootURL,
                sessionsURL: repoLocalStorageRootURL.appending(path: "sessions", directoryHint: .isDirectory),
                fileManager: fileManager
            )
        } else {
            repoLocalHistoryPlan = nil
        }

        return plan(
            activeHistoryPlan: activeHistoryPlan,
            repoLocalHistoryPlan: repoLocalHistoryPlan,
            activitySourceSnapshot: activitySourceSnapshot
        )
    }

    static func plan(
        activeHistoryPlan: CinematicRunRecapShareArtifactHistoryPlan,
        repoLocalHistoryPlan: CinematicRunRecapShareArtifactHistoryPlan? = nil,
        activitySourceSnapshot: RepositoryActivitySourceSnapshot
    ) -> CinematicRunRecapShareArtifactSourceReconciliationPlan {
        let state = stateIdentifier(
            activeHistoryPlan: activeHistoryPlan,
            repoLocalHistoryPlan: repoLocalHistoryPlan,
            activitySourceSnapshot: activitySourceSnapshot
        )
        let repoLocalAvailabilityReason = repoLocalHistoryPlan?.availabilityReason ?? "not-scanned"
        let activeEntryIdentifiers = representativeEntryIdentifiers(activeHistoryPlan.entries)
        let repoLocalEntryIdentifiers = representativeEntryIdentifiers(repoLocalHistoryPlan?.entries ?? [])
        let repoLocalExtraEntryIdentifiers = representativeRepoLocalExtraEntryIdentifiers(
            activeHistoryPlan: activeHistoryPlan,
            repoLocalHistoryPlan: repoLocalHistoryPlan
        )
        let warningStateIdentifier = activeHistoryPlan.hasWarnings || (repoLocalHistoryPlan?.hasWarnings ?? false)
            ? "warnings"
            : "clear"
        let repoLocalHistoryIdentifier = repoLocalHistoryPlan?.identifier ?? "not-scanned"
        let identifier = bounded(
            [
                "run-recap-share-artifact-source-reconciliation",
                "state:\(state)",
                "storage:\(activitySourceSnapshot.activeStorageIdentifier)",
                "active:\(fingerprint(activeHistoryPlan.identifier))",
                "repo-local:\(fingerprint(repoLocalHistoryIdentifier))",
                "activity-source:\(fingerprint(activitySourceSnapshot.identifier))",
                "active-total:\(activeHistoryPlan.totalCount)",
                "repo-local-total:\(repoLocalHistoryPlan?.totalCount ?? 0)",
                "active-latest:\(activeHistoryPlan.latestEntry?.sessionNumber.description ?? "none")",
                "repo-local-latest:\(repoLocalHistoryPlan?.latestEntry?.sessionNumber.description ?? "none")",
                "warnings:\(warningStateIdentifier)"
            ].joined(separator: "|"),
            limit: CinematicRunRecapShareArtifactSourceReconciliationPlan.identifierMaxCharacters
        )

        return CinematicRunRecapShareArtifactSourceReconciliationPlan(
            identifier: identifier,
            stateIdentifier: state,
            activeStorageIdentifier: activitySourceSnapshot.activeStorageIdentifier,
            activitySourceIdentifier: activitySourceSnapshot.identifier,
            activeHistoryIdentifier: activeHistoryPlan.identifier,
            repoLocalHistoryIdentifier: repoLocalHistoryIdentifier,
            activeAvailabilityReason: activeHistoryPlan.availabilityReason,
            repoLocalAvailabilityReason: repoLocalAvailabilityReason,
            activeTotalCount: activeHistoryPlan.totalCount,
            repoLocalTotalCount: repoLocalHistoryPlan?.totalCount ?? 0,
            activeWarningCount: activeHistoryPlan.warningCount,
            repoLocalWarningCount: repoLocalHistoryPlan?.warningCount ?? 0,
            activeLatestSessionNumber: activeHistoryPlan.latestEntry?.sessionNumber,
            repoLocalLatestSessionNumber: repoLocalHistoryPlan?.latestEntry?.sessionNumber,
            activeLatestEntryIdentifier: activeHistoryPlan.latestEntry?.identifier,
            repoLocalLatestEntryIdentifier: repoLocalHistoryPlan?.latestEntry?.identifier,
            representativeActiveEntryIdentifiers: activeEntryIdentifiers,
            representativeRepoLocalEntryIdentifiers: repoLocalEntryIdentifiers,
            representativeRepoLocalExtraEntryIdentifiers: repoLocalExtraEntryIdentifiers,
            activeStorageRootDisplayText: activeHistoryPlan.storageRootDisplayText,
            activeSessionsDisplayText: activeHistoryPlan.sessionsDisplayText,
            repoLocalStorageRootDisplayText: repoLocalHistoryPlan?.storageRootDisplayText ?? "not-scanned",
            repoLocalSessionsDisplayText: repoLocalHistoryPlan?.sessionsDisplayText ?? "not-scanned",
            warningStateIdentifier: warningStateIdentifier,
            isApplicationSupportComparison: activitySourceSnapshot.activeStorage == .applicationSupport
        )
    }

    private static func stateIdentifier(
        activeHistoryPlan: CinematicRunRecapShareArtifactHistoryPlan,
        repoLocalHistoryPlan: CinematicRunRecapShareArtifactHistoryPlan?,
        activitySourceSnapshot: RepositoryActivitySourceSnapshot
    ) -> String {
        guard activitySourceSnapshot.activeStorage == .applicationSupport else {
            return "active-only"
        }
        guard let repoLocalHistoryPlan else {
            return "repo-local-missing"
        }
        if activeHistoryPlan.hasWarnings || repoLocalHistoryPlan.hasWarnings {
            return "scan-warnings"
        }
        if !activeHistoryPlan.isAvailable, repoLocalHistoryPlan.isAvailable {
            return "active-missing-repo-local-available"
        }
        if repoLocalHistoryPlan.availabilityReason == "sessions-directory-unavailable" {
            return "repo-local-missing"
        }
        if historiesAreCompatible(activeHistoryPlan, repoLocalHistoryPlan) {
            return "compatible"
        }
        if repoLocalHasExtra(activeHistoryPlan: activeHistoryPlan, repoLocalHistoryPlan: repoLocalHistoryPlan) {
            return "repo-local-extra"
        }
        return "active-only"
    }

    private static func historiesAreCompatible(
        _ activeHistoryPlan: CinematicRunRecapShareArtifactHistoryPlan,
        _ repoLocalHistoryPlan: CinematicRunRecapShareArtifactHistoryPlan
    ) -> Bool {
        activeHistoryPlan.totalCount == repoLocalHistoryPlan.totalCount
            && activeHistoryPlan.availabilityReason == repoLocalHistoryPlan.availabilityReason
            && activeHistoryPlan.entries.map(\.identifier) == repoLocalHistoryPlan.entries.map(\.identifier)
    }

    private static func repoLocalHasExtra(
        activeHistoryPlan: CinematicRunRecapShareArtifactHistoryPlan,
        repoLocalHistoryPlan: CinematicRunRecapShareArtifactHistoryPlan
    ) -> Bool {
        let activeEntryIdentifiers = Set(activeHistoryPlan.entries.map(\.identifier))
        return repoLocalHistoryPlan.totalCount > activeHistoryPlan.totalCount
            || repoLocalHistoryPlan.entries.contains { !activeEntryIdentifiers.contains($0.identifier) }
    }

    private static func representativeEntryIdentifiers(
        _ entries: [CinematicRunRecapShareArtifactHistoryPlan.Entry]
    ) -> [String] {
        Array(
            entries
                .map(\.identifier)
                .prefix(CinematicRunRecapShareArtifactSourceReconciliationPlan.representativeEntryLimit)
        )
    }

    private static func representativeRepoLocalExtraEntryIdentifiers(
        activeHistoryPlan: CinematicRunRecapShareArtifactHistoryPlan,
        repoLocalHistoryPlan: CinematicRunRecapShareArtifactHistoryPlan?
    ) -> [String] {
        guard let repoLocalHistoryPlan else { return [] }
        let activeEntryIdentifiers = Set(activeHistoryPlan.entries.map(\.identifier))
        return Array(
            repoLocalHistoryPlan.entries
                .map(\.identifier)
                .filter { !activeEntryIdentifiers.contains($0) }
                .prefix(CinematicRunRecapShareArtifactSourceReconciliationPlan.representativeEntryLimit)
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

    private static func fingerprint(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}

enum CinematicRunRecapShareArtifactSourceExportAuditPlanner {
    static func plan(
        reconciliationPlan: CinematicRunRecapShareArtifactSourceReconciliationPlan
    ) -> CinematicRunRecapShareArtifactSourceExportAuditPlan {
        let isVisible = CinematicRunRecapShareArtifactSourceBadgePlanner.plan(
            reconciliationPlan: reconciliationPlan
        ).isVisible
        let readOnlyDisclaimer = bounded(
            "Read-only: export audit only; no repair, migration, deletion, pin, hold, search, session, active-storage, or artifact-history mutation.",
            limit: CinematicRunRecapShareArtifactSourceExportAuditPlan.readOnlyDisclaimerMaxCharacters
        )
        let representativeActiveEntryIdentifiers = Array(
            reconciliationPlan.representativeActiveEntryIdentifiers
                .map { bounded($0, limit: CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters) }
                .prefix(CinematicRunRecapShareArtifactSourceExportAuditPlan.representativeEntryLimit)
        )
        let representativeRepoLocalEntryIdentifiers = Array(
            reconciliationPlan.representativeRepoLocalEntryIdentifiers
                .map { bounded($0, limit: CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters) }
                .prefix(CinematicRunRecapShareArtifactSourceExportAuditPlan.representativeEntryLimit)
        )
        let representativeRepoLocalExtraEntryIdentifiers = Array(
            reconciliationPlan.representativeRepoLocalExtraEntryIdentifiers
                .map { bounded($0, limit: CinematicRunRecapShareArtifactHistoryPlan.identifierMaxCharacters) }
                .prefix(CinematicRunRecapShareArtifactSourceExportAuditPlan.representativeEntryLimit)
        )
        let markdownSection = isVisible
            ? markdownSection(
                reconciliationPlan: reconciliationPlan,
                representativeActiveEntryIdentifiers: representativeActiveEntryIdentifiers,
                representativeRepoLocalEntryIdentifiers: representativeRepoLocalEntryIdentifiers,
                representativeRepoLocalExtraEntryIdentifiers: representativeRepoLocalExtraEntryIdentifiers,
                readOnlyDisclaimer: readOnlyDisclaimer
            )
            : ""
        let identifier = bounded(
            [
                "run-recap-share-artifact-source-export-audit",
                "visible:\(isVisible)",
                "state:\(reconciliationPlan.stateIdentifier)",
                "source:\(fingerprint(reconciliationPlan.identifier))",
                "storage:\(reconciliationPlan.activeStorageIdentifier)",
                "active-total:\(reconciliationPlan.activeTotalCount)",
                "repo-local-total:\(reconciliationPlan.repoLocalTotalCount)",
                "active-latest:\(sessionIdentifier(reconciliationPlan.activeLatestSessionNumber))",
                "repo-local-latest:\(sessionIdentifier(reconciliationPlan.repoLocalLatestSessionNumber))",
                "active-warnings:\(reconciliationPlan.activeWarningCount)",
                "repo-local-warnings:\(reconciliationPlan.repoLocalWarningCount)",
                "active-ids:\(fingerprint(representativeActiveEntryIdentifiers.joined(separator: "|")))",
                "repo-local-ids:\(fingerprint(representativeRepoLocalEntryIdentifiers.joined(separator: "|")))",
                "repo-local-extra-ids:\(fingerprint(representativeRepoLocalExtraEntryIdentifiers.joined(separator: "|")))",
                "markdown:\(markdownSection.count)"
            ].joined(separator: "|"),
            limit: CinematicRunRecapShareArtifactSourceExportAuditPlan.identifierMaxCharacters
        )

        return CinematicRunRecapShareArtifactSourceExportAuditPlan(
            identifier: identifier,
            sourceReconciliationIdentifier: reconciliationPlan.identifier,
            stateIdentifier: reconciliationPlan.stateIdentifier,
            activeStorageIdentifier: reconciliationPlan.activeStorageIdentifier,
            activeTotalCount: reconciliationPlan.activeTotalCount,
            repoLocalTotalCount: reconciliationPlan.repoLocalTotalCount,
            activeLatestSessionNumber: reconciliationPlan.activeLatestSessionNumber,
            repoLocalLatestSessionNumber: reconciliationPlan.repoLocalLatestSessionNumber,
            activeWarningCount: reconciliationPlan.activeWarningCount,
            repoLocalWarningCount: reconciliationPlan.repoLocalWarningCount,
            representativeActiveEntryIdentifiers: representativeActiveEntryIdentifiers,
            representativeRepoLocalEntryIdentifiers: representativeRepoLocalEntryIdentifiers,
            representativeRepoLocalExtraEntryIdentifiers: representativeRepoLocalExtraEntryIdentifiers,
            readOnlyDisclaimer: readOnlyDisclaimer,
            markdownSection: markdownSection,
            isVisible: isVisible
        )
    }

    static func markdownExport(
        baseMarkdown: String,
        sourceExportAuditPlan: CinematicRunRecapShareArtifactSourceExportAuditPlan?,
        limit: Int
    ) -> String {
        guard let sourceExportAuditPlan,
              sourceExportAuditPlan.isVisible,
              !sourceExportAuditPlan.markdownSection.isEmpty else {
            return boundedArtifactText(baseMarkdown, limit: limit)
        }

        let separator = "\n\n"
        let section = sourceExportAuditPlan.markdownSection
        let baseLimit = max(0, limit - section.count - separator.count)
        let boundedBase = boundedArtifactText(baseMarkdown, limit: baseLimit)
        guard !boundedBase.isEmpty else {
            return boundedArtifactText(section, limit: limit)
        }
        return boundedArtifactText(
            [boundedBase, section].joined(separator: separator),
            limit: limit
        )
    }

    private static func markdownSection(
        reconciliationPlan: CinematicRunRecapShareArtifactSourceReconciliationPlan,
        representativeActiveEntryIdentifiers: [String],
        representativeRepoLocalEntryIdentifiers: [String],
        representativeRepoLocalExtraEntryIdentifiers: [String],
        readOnlyDisclaimer: String
    ) -> String {
        let lines = [
            "## Storage Source",
            "",
            "- Reconciliation: \(reconciliationPlan.identifier)",
            "- State: \(reconciliationPlan.stateIdentifier)",
            "- \(readOnlyDisclaimer)",
            "- Active storage: \(reconciliationPlan.activeStorageIdentifier)",
            "- Active artifacts: \(reconciliationPlan.activeTotalCount)",
            "- Repo-local artifacts: \(reconciliationPlan.repoLocalTotalCount)",
            "- Active latest session: \(sessionLabel(reconciliationPlan.activeLatestSessionNumber))",
            "- Repo-local latest session: \(sessionLabel(reconciliationPlan.repoLocalLatestSessionNumber))",
            "- Active warnings: \(reconciliationPlan.activeWarningCount)",
            "- Repo-local warnings: \(reconciliationPlan.repoLocalWarningCount)",
            "- Warning state: \(reconciliationPlan.warningStateIdentifier)",
            "- Active availability: \(reconciliationPlan.activeAvailabilityReason)",
            "- Repo-local availability: \(reconciliationPlan.repoLocalAvailabilityReason)",
            "- Active sessions: \(reconciliationPlan.activeSessionsDisplayText)",
            "- Repo-local sessions: \(reconciliationPlan.repoLocalSessionsDisplayText)",
            "- Active ids: \(identifierList(representativeActiveEntryIdentifiers))",
            "- Repo-local ids: \(identifierList(representativeRepoLocalEntryIdentifiers))",
            "- Repo-local extra ids: \(identifierList(representativeRepoLocalExtraEntryIdentifiers))"
        ]

        return boundedArtifactText(
            lines.joined(separator: "\n"),
            limit: CinematicRunRecapShareArtifactSourceExportAuditPlan.markdownMaxCharacters
        )
    }

    private static func sessionIdentifier(_ sessionNumber: Int?) -> String {
        sessionNumber.map(String.init) ?? "none"
    }

    private static func sessionLabel(_ sessionNumber: Int?) -> String {
        sessionNumber.map { "S\($0)" } ?? "none"
    }

    private static func identifierList(_ identifiers: [String]) -> String {
        identifiers.isEmpty ? "none" : identifiers.joined(separator: ", ")
    }

    private static func bounded(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "" }
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
        guard !normalized.isEmpty else { return "" }
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

enum CinematicRunRecapShareArtifactSourceBadgePlanner {
    static func plan(
        reconciliationPlan: CinematicRunRecapShareArtifactSourceReconciliationPlan
    ) -> CinematicRunRecapShareArtifactSourceBadgePlan {
        let presentation = presentation(for: reconciliationPlan)
        let copyText = presentation.isVisible
            ? copyText(for: reconciliationPlan)
            : ""
        let identifier = bounded(
            [
                "run-recap-share-artifact-source-badge",
                "visible:\(presentation.isVisible)",
                "state:\(reconciliationPlan.stateIdentifier)",
                "source:\(fingerprint(reconciliationPlan.identifier))",
                "active:\(fingerprint(reconciliationPlan.activeHistoryIdentifier))",
                "repo-local:\(fingerprint(reconciliationPlan.repoLocalHistoryIdentifier))",
                "severity:\(presentation.severity.rawValue)",
                "copy:\(copyText.count)"
            ].joined(separator: "|"),
            limit: CinematicRunRecapShareArtifactSourceBadgePlan.identifierMaxCharacters
        )

        return CinematicRunRecapShareArtifactSourceBadgePlan(
            identifier: identifier,
            sourceReconciliationIdentifier: reconciliationPlan.identifier,
            stateIdentifier: reconciliationPlan.stateIdentifier,
            isVisible: presentation.isVisible,
            label: bounded(presentation.label, limit: CinematicRunRecapShareArtifactSourceBadgePlan.labelMaxCharacters),
            detail: bounded(presentation.detail, limit: CinematicRunRecapShareArtifactSourceBadgePlan.detailMaxCharacters),
            help: bounded(presentation.help, limit: CinematicRunRecapShareArtifactSourceBadgePlan.helpMaxCharacters),
            copyText: copyText,
            copyLabel: bounded(presentation.copyLabel, limit: CinematicRunRecapShareArtifactSourceBadgePlan.copyLabelMaxCharacters),
            severity: presentation.severity,
            tintIdentifier: bounded(
                presentation.tintIdentifier,
                limit: CinematicRunRecapShareArtifactSourceBadgePlan.tintIdentifierMaxCharacters
            ),
            systemImage: bounded(
                presentation.systemImage,
                limit: CinematicRunRecapShareArtifactSourceBadgePlan.systemImageMaxCharacters
            ),
            accessibilityIdentifier: "cinematic-run-recap-artifact-source-badge-\(identifier)",
            copyAccessibilityIdentifier: "cinematic-run-recap-artifact-source-badge-copy-\(identifier)"
        )
    }

    private struct Presentation {
        var isVisible: Bool
        var label: String
        var detail: String
        var help: String
        var copyLabel: String
        var severity: CompassWorkspaceStorageAssessment.Severity
        var tintIdentifier: String
        var systemImage: String
    }

    private static func presentation(
        for plan: CinematicRunRecapShareArtifactSourceReconciliationPlan
    ) -> Presentation {
        guard plan.isApplicationSupportComparison else {
            return Presentation(
                isVisible: false,
                label: "",
                detail: "",
                help: "",
                copyLabel: "",
                severity: .healthy,
                tintIdentifier: "hidden",
                systemImage: "checkmark.circle"
            )
        }

        let presentation: Presentation
        switch plan.stateIdentifier {
        case "compatible":
            presentation = Presentation(
                isVisible: true,
                label: "Application Support source",
                detail: "Application Support and repo-local recap artifacts match at \(plan.activeTotalCount) saved\(latestSuffix(plan.activeLatestSessionNumber)).",
                help: visibleHelp(for: plan, stateLabel: "matching Application Support recap artifacts"),
                copyLabel: "Copy source details",
                severity: .info,
                tintIdentifier: "teal",
                systemImage: "externaldrive.fill.badge.checkmark"
            )
        case "repo-local-missing":
            presentation = Presentation(
                isVisible: true,
                label: "Repo-local source missing",
                detail: "Active storage has \(plan.activeTotalCount) saved; repo-local .compass/sessions is \(plan.repoLocalAvailabilityReason).",
                help: visibleHelp(for: plan, stateLabel: "missing repo-local recap artifacts"),
                copyLabel: "Copy source details",
                severity: .info,
                tintIdentifier: "blue",
                systemImage: "folder.badge.questionmark"
            )
        case "repo-local-extra":
            let extraCount = max(0, plan.repoLocalTotalCount - plan.activeTotalCount)
            presentation = Presentation(
                isVisible: true,
                label: "Repo-local has extras",
                detail: "Active storage has \(plan.activeTotalCount) saved; repo-local has \(plan.repoLocalTotalCount) saved\(extraCount > 0 ? " with \(extraCount) extra" : "").",
                help: visibleHelp(for: plan, stateLabel: "repo-local-only recap artifacts"),
                copyLabel: "Copy source details",
                severity: .warning,
                tintIdentifier: "orange",
                systemImage: "archivebox.badge.plus"
            )
        case "active-missing-repo-local-available":
            presentation = Presentation(
                isVisible: true,
                label: "Active source missing",
                detail: "Active Application Support artifacts are \(plan.activeAvailabilityReason); repo-local still has \(plan.repoLocalTotalCount) saved.",
                help: visibleHelp(for: plan, stateLabel: "repo-local artifacts while active storage is missing"),
                copyLabel: "Copy source details",
                severity: .failure,
                tintIdentifier: "red",
                systemImage: "externaldrive.badge.xmark"
            )
        case "scan-warnings":
            presentation = Presentation(
                isVisible: true,
                label: "Artifact scan warning",
                detail: "Recap artifact scan reported warnings active \(plan.activeWarningCount), repo-local \(plan.repoLocalWarningCount).",
                help: visibleHelp(for: plan, stateLabel: "recap artifact scan warnings"),
                copyLabel: "Copy source details",
                severity: .warning,
                tintIdentifier: "yellow",
                systemImage: "exclamationmark.triangle.fill"
            )
        default:
            presentation = Presentation(
                isVisible: true,
                label: "Application Support only",
                detail: "Application Support has \(plan.activeTotalCount) saved; repo-local comparison state is \(plan.stateIdentifier).",
                help: visibleHelp(for: plan, stateLabel: "Application Support recap artifacts"),
                copyLabel: "Copy source details",
                severity: .info,
                tintIdentifier: "purple",
                systemImage: "externaldrive.fill"
            )
        }

        return presentation
    }

    private static func visibleHelp(
        for plan: CinematicRunRecapShareArtifactSourceReconciliationPlan,
        stateLabel: String
    ) -> String {
        bounded(
            "Copy read-only source details for \(stateLabel). This badge is derived from reconciliation \(fingerprint(plan.identifier)) and does not repair, migrate, delete, or change saved recap artifacts.",
            limit: CinematicRunRecapShareArtifactSourceBadgePlan.helpMaxCharacters
        )
    }

    private static func copyText(
        for plan: CinematicRunRecapShareArtifactSourceReconciliationPlan
    ) -> String {
        let lines = [
            "Recap artifact source reconciliation",
            "Reconciliation: \(plan.identifier)",
            "State: \(plan.stateIdentifier)",
            "Storage: \(plan.activeStorageIdentifier)",
            "Activity source: \(plan.activitySourceIdentifier)",
            "Active history: \(plan.activeHistoryIdentifier)",
            "Repo-local history: \(plan.repoLocalHistoryIdentifier)",
            "Active availability: \(plan.activeAvailabilityReason)",
            "Repo-local availability: \(plan.repoLocalAvailabilityReason)",
            "Active total: \(plan.activeTotalCount)",
            "Repo-local total: \(plan.repoLocalTotalCount)",
            "Active latest: \(sessionLabel(plan.activeLatestSessionNumber))",
            "Repo-local latest: \(sessionLabel(plan.repoLocalLatestSessionNumber))",
            "Warnings: active \(plan.activeWarningCount), repo-local \(plan.repoLocalWarningCount)",
            "Warning state: \(plan.warningStateIdentifier)",
            "Active sessions: \(plan.activeSessionsDisplayText)",
            "Repo-local sessions: \(plan.repoLocalSessionsDisplayText)",
            identifierLine("Active ids", plan.representativeActiveEntryIdentifiers),
            identifierLine("Repo-local ids", plan.representativeRepoLocalEntryIdentifiers),
            identifierLine("Repo-local extra ids", plan.representativeRepoLocalExtraEntryIdentifiers),
            "Read-only: copy only; no repair, migration, deletion, pin, hold, search, session, active-storage, or artifact-history mutation."
        ]

        return boundedArtifactText(
            lines.joined(separator: "\n"),
            limit: CinematicRunRecapShareArtifactSourceBadgePlan.copyTextMaxCharacters
        )
    }

    private static func latestSuffix(_ sessionNumber: Int?) -> String {
        sessionNumber.map { "; latest S\($0)" } ?? ""
    }

    private static func sessionLabel(_ sessionNumber: Int?) -> String {
        sessionNumber.map { "S\($0)" } ?? "none"
    }

    private static func identifierLine(_ label: String, _ identifiers: [String]) -> String {
        guard !identifiers.isEmpty else { return "\(label): none" }
        return "\(label): \(identifiers.joined(separator: ", "))"
    }

    private static func bounded(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "" }
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
        guard !normalized.isEmpty else { return "" }
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
        sessions: [SessionRecord],
        warningPulseAudit: CinematicRunRecapShareArtifactWarningPulseAudit? = nil
    ) -> CinematicRunRecapShareArtifactPlan {
        let latestSession = latestFinishedSession(in: sessions)
        let runtimeRouteAudit = CinematicRunRecapShareArtifactRuntimeRouteAudit(
            snapshot: latestSession?.latestExecutionEnvironmentSnapshot
        )
        return plan(
            sharePlan: sharePlan,
            sessionNumber: latestSession?.session,
            runtimeRouteAudit: runtimeRouteAudit,
            mutationTestingAudit: CinematicRunRecapShareArtifactMutationTestingAudit(
                execution: latestSession?.mutationTestingExecutions.last,
                runtimeRouteAudit: runtimeRouteAudit
            ),
            warningPulseAudit: warningPulseAudit
        )
    }

    static func plan(
        sharePlan: CinematicRunRecapSharePlan,
        sessionNumber: Int?,
        warningPulseAudit: CinematicRunRecapShareArtifactWarningPulseAudit? = nil
    ) -> CinematicRunRecapShareArtifactPlan {
        plan(
            sharePlan: sharePlan,
            sessionNumber: sessionNumber,
            runtimeRouteAudit: nil,
            mutationTestingAudit: nil,
            warningPulseAudit: warningPulseAudit
        )
    }

    private static func plan(
        sharePlan: CinematicRunRecapSharePlan,
        sessionNumber: Int?,
        runtimeRouteAudit providedRuntimeRouteAudit: CinematicRunRecapShareArtifactRuntimeRouteAudit?,
        mutationTestingAudit providedMutationTestingAudit: CinematicRunRecapShareArtifactMutationTestingAudit?,
        warningPulseAudit providedWarningPulseAudit: CinematicRunRecapShareArtifactWarningPulseAudit?
    ) -> CinematicRunRecapShareArtifactPlan {
        let latestSessionNumber = sessionNumber.flatMap { $0 > 0 ? $0 : nil }
        let artifactSessionNumber = sharePlan.isAvailable ? latestSessionNumber : nil
        let runtimeRouteAudit = artifactSessionNumber == nil ? nil : providedRuntimeRouteAudit
        let mutationTestingAudit = artifactSessionNumber == nil ? nil : providedMutationTestingAudit
        let warningPulseAudit = artifactSessionNumber == nil ? nil : providedWarningPulseAudit
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

        var hashParts = [
            availabilityReason,
            artifactSessionNumber.map(String.init) ?? "none",
            sharePlan.identifier,
            sharePlan.recapIdentifier
        ]
        if let runtimeRouteAudit {
            hashParts.append("runtime:\(runtimeRouteAudit.identifier)")
        }
        if let mutationTestingAudit {
            hashParts.append("mutation:\(mutationTestingAudit.identifier)")
        }
        if let warningPulseAudit {
            hashParts.append("warning-pulse:\(warningPulseAudit.identifier)")
        }
        let hash = fingerprint(hashParts.joined(separator: "|"))
        let filename = safeFilename(
            "recap-share-\(String(hash.prefix(12))).md",
            limit: CinematicRunRecapShareArtifactPlan.filenameMaxCharacters
        )
        var identifierParts = [
            "run-recap-share-artifact",
            "availability:\(availabilityReason)",
            "session:\(artifactSessionNumber.map(String.init) ?? "none")",
            "file:\(filename)",
            "share:\(fingerprint(sharePlan.identifier))",
            "recap:\(fingerprint(sharePlan.recapIdentifier))",
            "focus:\(fingerprint(sharePlan.recapFocusIdentifier ?? "none"))",
            "end-card:\(fingerprint(sharePlan.endCardIdentifier ?? "none"))"
        ]
        if let runtimeRouteAudit {
            identifierParts.append("runtime:\(fingerprint(runtimeRouteAudit.identifier))")
        }
        if let mutationTestingAudit {
            identifierParts.append("mutation:\(fingerprint(mutationTestingAudit.identifier))")
        }
        if let warningPulseAudit {
            identifierParts.append("warning-pulse:\(fingerprint(warningPulseAudit.identifier))")
        }
        let identifier = bounded(
            identifierParts.joined(separator: "|"),
            limit: CinematicRunRecapShareArtifactPlan.identifierMaxCharacters
        )
        let markdown = markdownContents(
            identifier: identifier,
            availabilityReason: availabilityReason,
            isAvailable: isAvailable,
            sessionNumber: artifactSessionNumber,
            filename: filename,
            sharePlan: sharePlan,
            runtimeRouteAudit: runtimeRouteAudit,
            mutationTestingAudit: mutationTestingAudit,
            warningPulseAudit: warningPulseAudit
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
            runtimeRouteAudit: runtimeRouteAudit,
            mutationTestingAudit: mutationTestingAudit,
            warningPulseAudit: warningPulseAudit,
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
        sharePlan: CinematicRunRecapSharePlan,
        runtimeRouteAudit: CinematicRunRecapShareArtifactRuntimeRouteAudit?,
        mutationTestingAudit: CinematicRunRecapShareArtifactMutationTestingAudit?,
        warningPulseAudit: CinematicRunRecapShareArtifactWarningPulseAudit?
    ) -> String {
        let eventLines = sharePlan.eventSummaries.isEmpty
            ? ["- none"]
            : sharePlan.eventSummaries.map { "- \($0)" }
        let visualLines = sharePlan.visualDescriptorTokens.isEmpty
            ? ["- none"]
            : sharePlan.visualDescriptorTokens.map { "- \($0)" }
        var sections: [[String]] = [
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
                "- Commit: \(sharePlan.commitHighlight ?? "none")"
            ],
            [
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
        ]
        if let runtimeRouteAudit, !runtimeRouteAudit.markdownSection.isEmpty {
            sections.insert([""] + runtimeRouteAudit.markdownSection.components(separatedBy: "\n"), at: 1)
        }
        if let mutationTestingAudit, !mutationTestingAudit.markdownSection.isEmpty {
            let insertionIndex = runtimeRouteAudit?.markdownSection.isEmpty == false ? 2 : 1
            sections.insert(
                [""] + mutationTestingAudit.markdownSection.components(separatedBy: "\n"),
                at: insertionIndex
            )
        }
        if let warningPulseAudit, !warningPulseAudit.markdownSection.isEmpty {
            sections.insert(
                [""] + warningPulseAudit.markdownSection.components(separatedBy: "\n"),
                at: 1
            )
        }
        let lines = sections.flatMap { $0 }

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
            help: "Recap share artifact saved as \(url.lastPathComponent) in the active sessions directory."
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
        let message = sanitizedErrorMessage(error.localizedDescription)
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

    private static func sanitizedErrorMessage(_ text: String) -> String {
        let hostPathPattern = #"(?:(?:file://)?/(?:Users|private|var|tmp|opt|usr|bin|sbin|Library|Applications|Volumes)/[^\s,;)`"]+)|(?:\.\./[^\s,;)`"]+)"#
        return text
            .replacingOccurrences(
                of: hostPathPattern,
                with: "[path]",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
