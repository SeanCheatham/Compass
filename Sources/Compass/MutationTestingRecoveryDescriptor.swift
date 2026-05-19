import Foundation

struct MutationTestingRecoveryDescriptor: Equatable, Identifiable {
    static let fieldLimit = 120
    static let titleLimit = 80
    static let badgeLimit = 140
    static let detailLimit = 260
    static let helpLimit = 480
    static let copyTextLimit = 1_000
    static let tailLimit = 260
    static let tailLineLimit = 4

    enum State: String, Equatable {
        case active
        case succeeded
        case missing
        case oldSession = "old-session"
        case readinessOnly = "readiness-only"
    }

    struct ExecutionContext: Equatable {
        var sessionNumber: Int
        var sessionStartedAt: Double
        var execution: SessionMutationTestingExecution
    }

    var id: String { identifier }

    var identifier: String
    var stateIdentifier: String
    var isActive: Bool
    var sessionNumber: Int?
    var statusIdentifier: String
    var statusLabel: String
    var routeIdentifier: String
    var routeLabel: String
    var languageIdentifier: String
    var languageLabel: String
    var seedCommandLabel: String
    var exitCodeText: String
    var durationText: String
    var tailSummary: String
    var title: String
    var badgeText: String
    var detailText: String
    var metadata: String?
    var reviewActionLabel: String
    var copyActionLabel: String
    var helpText: String
    var copyText: String
    var systemImage: String

    static func latestContext(in sessions: [SessionRecord]) -> ExecutionContext? {
        sessions.compactMap { session -> ExecutionContext? in
            guard let execution = session.mutationTestingExecutions.last else {
                return nil
            }
            return ExecutionContext(
                sessionNumber: session.session,
                sessionStartedAt: session.startedAt,
                execution: execution
            )
        }
        .max { lhs, rhs in
            if lhs.execution.startedAt != rhs.execution.startedAt {
                return lhs.execution.startedAt < rhs.execution.startedAt
            }
            if lhs.sessionStartedAt != rhs.sessionStartedAt {
                return lhs.sessionStartedAt < rhs.sessionStartedAt
            }
            return lhs.sessionNumber < rhs.sessionNumber
        }
    }

    static func projectDescriptor(sessions: [SessionRecord]) -> MutationTestingRecoveryDescriptor {
        guard let context = latestContext(in: sessions) else {
            return MutationTestingRecoveryDescriptor(state: .missing)
        }

        return MutationTestingRecoveryDescriptor(
            state: statusIdentifier(for: context.execution) == "failed" ? .active : .succeeded,
            context: context
        )
    }

    static func runtimeDescriptor(
        sessions: [SessionRecord],
        readiness: CodexMutationTestingPlan
    ) -> MutationTestingRecoveryDescriptor {
        guard let context = latestContext(in: sessions) else {
            return MutationTestingRecoveryDescriptor(state: .readinessOnly, readiness: readiness)
        }

        return MutationTestingRecoveryDescriptor(
            state: statusIdentifier(for: context.execution) == "failed" ? .active : .succeeded,
            context: context,
            readiness: readiness
        )
    }

    static func historyDescriptor(
        session: SessionRecord,
        latestContext: ExecutionContext?
    ) -> MutationTestingRecoveryDescriptor? {
        guard let execution = session.mutationTestingExecutions.last else {
            return nil
        }

        let context = ExecutionContext(
            sessionNumber: session.session,
            sessionStartedAt: session.startedAt,
            execution: execution
        )
        let isLatest = latestContext.map {
            $0.sessionNumber == context.sessionNumber
                && Int($0.execution.startedAt) == Int(context.execution.startedAt)
                && $0.execution.id == context.execution.id
        } ?? false
        let statusIdentifier = statusIdentifier(for: execution)
        let state: State
        if isLatest {
            state = statusIdentifier == "failed" ? .active : .succeeded
        } else if statusIdentifier == "failed" {
            state = .oldSession
        } else {
            state = .succeeded
        }

        return MutationTestingRecoveryDescriptor(state: state, context: context)
    }

    init(state: State) {
        self.init(state: state, context: nil, readiness: nil)
    }

    private init(
        state: State,
        context: ExecutionContext? = nil,
        readiness: CodexMutationTestingPlan? = nil
    ) {
        let execution = context?.execution
        let statusIdentifier = execution.map(Self.statusIdentifier) ?? readiness?.statusIdentifier ?? "missing"
        let statusLabel = execution.map { MutationTestingPresentationSanitizer.statusLabel(Self.statusIdentifier(for: $0)) }
            ?? readiness?.statusLabel
            ?? "Missing"
        let routeIdentifier = execution.map { MutationTestingPresentationSanitizer.routeIdentifier($0.routeIdentifier) }
            ?? readiness?.routeIdentifier
            ?? "unknown"
        let routeLabel = execution.map { _ in MutationTestingPresentationSanitizer.routeLabel(routeIdentifier) }
            ?? readiness?.routeLabel
            ?? "Unknown route"
        let languageIdentifier = execution.map { MutationTestingPresentationSanitizer.languageIdentifier($0.languageIdentifier) }
            ?? readiness?.languageIdentifier
            ?? "unknown"
        let languageLabel = execution.map { _ in MutationTestingPresentationSanitizer.languageLabel(languageIdentifier) }
            ?? readiness?.languageLabel
            ?? "Unknown"
        let seedCommandLabel = execution.map {
            MutationTestingPresentationSanitizer.field(
                $0.seedCommandLabel,
                limit: SessionMutationTestingExecution.commandLimit
            )
        }
            ?? readiness?.seedCommandLabel
            ?? "none"
        let exitCodeText = execution.map { MutationTestingPresentationSanitizer.exitCodeLabel($0.exitCode) }
            ?? "exit none"
        let durationText = execution.map {
            MutationTestingPresentationSanitizer.durationLabel(
                startedAt: $0.startedAt,
                endedAt: $0.endedAt
            )
        }
            ?? "not run"
        let tailSummary = execution.map {
            MutationTestingPresentationSanitizer.outputTail(
                $0.outputTail,
                limit: Self.tailLimit,
                lineLimit: Self.tailLineLimit
            )
        }
            ?? ""

        let sessionNumber = context?.sessionNumber
        let stateCopy = Self.copy(for: state)
        let title = Self.bounded(stateCopy.title, limit: Self.titleLimit)
        let detailText = Self.bounded(
            Self.detailText(
                state: state,
                stateCopy: stateCopy,
                readiness: readiness,
                tailSummary: tailSummary,
                statusLabel: statusLabel,
                routeLabel: routeLabel,
                languageLabel: languageLabel,
                seedCommandLabel: seedCommandLabel,
                exitCodeText: exitCodeText
            ),
            limit: Self.detailLimit
        )
        let metadata = Self.metadata(
            sessionNumber: sessionNumber,
            seedCommandLabel: seedCommandLabel,
            exitCodeText: exitCodeText
        )
        let identifier = Self.identifier(
            state: state,
            sessionNumber: sessionNumber,
            statusIdentifier: statusIdentifier,
            routeIdentifier: routeIdentifier,
            languageIdentifier: languageIdentifier,
            seedCommandLabel: seedCommandLabel,
            startedAt: execution?.startedAt
        )
        let badgeText = Self.bounded(
            [
                title,
                sessionNumber.map { "#\($0)" },
                routeLabel,
                exitCodeText
            ]
                .compactMap { $0 }
                .joined(separator: " · "),
            limit: Self.badgeLimit
        )
        let helpText = Self.bounded(
            [
                title,
                stateCopy.help,
                sessionNumber.map { "Session #\($0)" },
                "Status: \(statusLabel)",
                "Route: \(routeLabel)",
                "Language: \(languageLabel)",
                "Seed: \(seedCommandLabel)",
                "Exit: \(exitCodeText)",
                "Duration: \(durationText)",
                tailSummary.isEmpty ? nil : "Tail: \(tailSummary)"
            ]
                .compactMap { $0 }
                .joined(separator: "; "),
            limit: Self.helpLimit
        )
        let copyText = Self.copyText(
            identifier: identifier,
            state: state,
            sessionNumber: sessionNumber,
            statusIdentifier: statusIdentifier,
            routeIdentifier: routeIdentifier,
            languageIdentifier: languageIdentifier,
            seedCommandLabel: seedCommandLabel,
            exitCodeText: exitCodeText,
            durationText: durationText,
            tailSummary: tailSummary,
            detailText: detailText
        )

        self.identifier = identifier
        stateIdentifier = state.rawValue
        isActive = state == .active
        self.sessionNumber = sessionNumber
        self.statusIdentifier = Self.bounded(statusIdentifier, limit: Self.fieldLimit)
        self.statusLabel = Self.bounded(statusLabel, limit: Self.fieldLimit)
        self.routeIdentifier = Self.bounded(routeIdentifier, limit: Self.fieldLimit)
        self.routeLabel = Self.bounded(routeLabel, limit: Self.fieldLimit)
        self.languageIdentifier = Self.bounded(languageIdentifier, limit: Self.fieldLimit)
        self.languageLabel = Self.bounded(languageLabel, limit: Self.fieldLimit)
        self.seedCommandLabel = Self.bounded(seedCommandLabel, limit: SessionMutationTestingExecution.commandLimit)
        self.exitCodeText = Self.bounded(exitCodeText, limit: Self.fieldLimit)
        self.durationText = Self.bounded(durationText, limit: Self.fieldLimit)
        self.tailSummary = tailSummary
        self.title = title
        self.badgeText = badgeText
        self.detailText = detailText
        self.metadata = metadata
        reviewActionLabel = stateCopy.reviewActionLabel
        copyActionLabel = stateCopy.copyActionLabel
        self.helpText = helpText
        self.copyText = copyText
        systemImage = stateCopy.systemImage
    }

    private static func statusIdentifier(for execution: SessionMutationTestingExecution) -> String {
        MutationTestingPresentationSanitizer.statusIdentifier(execution.statusIdentifier)
    }

    private static func copy(
        for state: State
    ) -> (title: String, help: String, reviewActionLabel: String, copyActionLabel: String, systemImage: String) {
        switch state {
        case .active:
            return (
                "Mutation recovery",
                "Latest explicit mutation run failed; review the bounded record before another opt-in pass.",
                "Review Mutation",
                "Copy Mutation Recovery",
                "testtube.2"
            )
        case .succeeded:
            return (
                "Mutation clear",
                "Latest explicit mutation run succeeded; this stays as ordinary history.",
                "Review Mutation",
                "Copy Mutation Summary",
                "checkmark.seal"
            )
        case .missing:
            return (
                "No mutation recovery",
                "No explicit mutation execution is recorded.",
                "Review Runtime",
                "Copy Mutation Summary",
                "testtube.2"
            )
        case .oldSession:
            return (
                "Older mutation failure",
                "A newer explicit mutation run exists; this failure remains ordinary history.",
                "Review Mutation",
                "Copy Mutation Summary",
                "clock.arrow.circlepath"
            )
        case .readinessOnly:
            return (
                "Mutation readiness only",
                "Runtime can describe mutation readiness, but no explicit mutation execution is recorded.",
                "Review Runtime",
                "Copy Mutation Readiness",
                "testtube.2"
            )
        }
    }

    private static func detailText(
        state: State,
        stateCopy: (title: String, help: String, reviewActionLabel: String, copyActionLabel: String, systemImage: String),
        readiness: CodexMutationTestingPlan?,
        tailSummary: String,
        statusLabel: String,
        routeLabel: String,
        languageLabel: String,
        seedCommandLabel: String,
        exitCodeText: String
    ) -> String {
        switch state {
        case .active:
            if !tailSummary.isEmpty {
                return tailSummary
            }
            return "Latest mutation run failed via \(routeLabel) for \(languageLabel); seed \(seedCommandLabel) ended \(exitCodeText)."
        case .succeeded:
            return "Latest mutation run succeeded via \(routeLabel) for \(languageLabel); no recovery cue is active."
        case .oldSession:
            return "Older failed mutation run via \(routeLabel) remains in history only because a newer mutation run exists."
        case .readinessOnly:
            return readiness?.detailText ?? stateCopy.help
        case .missing:
            return stateCopy.help
        }
    }

    private static func metadata(
        sessionNumber: Int?,
        seedCommandLabel: String,
        exitCodeText: String
    ) -> String? {
        guard let sessionNumber else { return nil }
        return bounded(
            [
                "#\(sessionNumber)",
                seedCommandLabel,
                exitCodeText
            ].joined(separator: " · "),
            limit: Self.fieldLimit
        )
    }

    private static func identifier(
        state: State,
        sessionNumber: Int?,
        statusIdentifier: String,
        routeIdentifier: String,
        languageIdentifier: String,
        seedCommandLabel: String,
        startedAt: Double?
    ) -> String {
        let seedFingerprint = MutationTestingPresentationSanitizer.fingerprint(seedCommandLabel)
        return boundedIdentifier(
            [
                "mutation-recovery",
                state.rawValue,
                sessionNumber.map { "session-\($0)" } ?? "session-none",
                statusIdentifier,
                routeIdentifier,
                languageIdentifier,
                "started-\(Int(startedAt ?? 0))",
                "seed-\(seedFingerprint)"
            ].joined(separator: ".")
        )
    }

    private static func copyText(
        identifier: String,
        state: State,
        sessionNumber: Int?,
        statusIdentifier: String,
        routeIdentifier: String,
        languageIdentifier: String,
        seedCommandLabel: String,
        exitCodeText: String,
        durationText: String,
        tailSummary: String,
        detailText: String
    ) -> String {
        boundedMultiline(
            [
                "Mutation Recovery",
                "id: \(identifier)",
                "state: \(state.rawValue)",
                "session: \(sessionNumber.map(String.init) ?? "none")",
                "status: \(statusIdentifier)",
                "route: \(routeIdentifier)",
                "language: \(languageIdentifier)",
                "seed-command: \(seedCommandLabel)",
                "exit: \(exitCodeText)",
                "duration: \(durationText)",
                "detail: \(detailText)",
                tailSummary.isEmpty ? nil : "tail: \(tailSummary)",
                "read-only: review/copy only; no mutation tests, Plan state, Develop retry, sessions, or runtime preferences are changed."
            ]
                .compactMap { $0 }
                .joined(separator: "\n"),
            limit: Self.copyTextLimit
        )
    }

    private static func boundedIdentifier(_ rawValue: String) -> String {
        let identifier = MutationTestingPresentationSanitizer.identifier(
            rawValue,
            fallback: "mutation-recovery.unknown",
            limit: Self.fieldLimit
        )
        return bounded(identifier, limit: Self.fieldLimit)
    }

    private static func bounded(_ text: String, limit: Int) -> String {
        MutationTestingPresentationSanitizer.bounded(text, limit: limit)
    }

    private static func boundedMultiline(_ text: String, limit: Int) -> String {
        MutationTestingPresentationSanitizer.bounded(text, limit: limit, preservesNewlines: true)
    }
}
