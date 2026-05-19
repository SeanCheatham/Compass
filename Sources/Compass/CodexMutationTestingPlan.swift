import Foundation

struct CodexMutationTestingPlan: Equatable, Identifiable {
    static let identifierMaxCharacters = 260
    static let labelMaxCharacters = 34
    static let statusLabelMaxCharacters = 34
    static let routeLabelMaxCharacters = 34
    static let languageLabelMaxCharacters = 34
    static let commandMaxCharacters = 96
    static let detailMaxCharacters = 220
    static let copyTextMaxCharacters = 560

    enum ReadinessState: String, Equatable {
        case ready
        case missingImmediate = "missing-immediate"
        case missingVerify = "missing-verify"
        case unsupportedLanguage = "unsupported-language"
    }

    enum RouteState: String, Equatable {
        case nativeRoute = "native-route"
        case appleContainerRoute = "apple-container-route"
        case nativeFallback = "native-fallback"
    }

    var id: String { identifier }

    var identifier: String
    var statusIdentifier: String
    var routeIdentifier: String
    var languageIdentifier: String
    var seedCommandIdentifier: String
    var isReady: Bool
    var statusLabel: String
    var routeLabel: String
    var languageLabel: String
    var badgeLabel: String
    var systemImage: String
    var seedCommand: String?
    var seedCommandLabel: String
    var detailText: String
    var copyText: String

    init(
        state: PlanState,
        languageProfile: RepositoryLanguageProfile,
        launchPlan: CodexExecutionLaunchPlan
    ) {
        self.init(
            immediate: state.immediate,
            languageProfile: languageProfile,
            launchPlan: launchPlan
        )
    }

    init(
        immediate: PlanNext?,
        languageProfile: RepositoryLanguageProfile,
        launchPlan: CodexExecutionLaunchPlan
    ) {
        let language = Self.languageDescriptor(for: languageProfile.primaryLanguage)
        let routeState = Self.routeState(for: launchPlan)
        let rawSeedCommand = immediate?.verify.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedSeedCommand = rawSeedCommand.flatMap {
            Self.sanitizedCommand($0, launchPlan: launchPlan)
        }.flatMap(Self.nilIfEmpty)

        let readinessState: ReadinessState
        if immediate == nil {
            readinessState = .missingImmediate
        } else if sanitizedSeedCommand == nil {
            readinessState = .missingVerify
        } else if !language.isSupported {
            readinessState = .unsupportedLanguage
        } else {
            readinessState = .ready
        }

        let statusLabel = Self.statusLabel(for: readinessState)
        let routeLabel = Self.routeLabel(for: routeState)
        let seedCommandLabel = sanitizedSeedCommand ?? "none"
        let seedCommandIdentifier = "seed-\(Self.fingerprint(seedCommandLabel))"
        let identifier = Self.bounded(
            [
                "codex-mutation-testing",
                "status:\(readinessState.rawValue)",
                "route:\(routeState.rawValue)",
                "language:\(language.identifier)",
                seedCommandIdentifier
            ].joined(separator: "|"),
            limit: Self.identifierMaxCharacters
        )
        let detailText = Self.detailText(
            readinessState: readinessState,
            routeState: routeState,
            languageLabel: language.label,
            seedCommandLabel: seedCommandLabel
        )
        let copyText = Self.boundedMultiline(
            [
                "Mutation Testing Readiness",
                "id: \(identifier)",
                "status: \(readinessState.rawValue)",
                "route: \(routeState.rawValue)",
                "language: \(language.identifier)",
                "seed-command: \(seedCommandLabel)",
                "detail: \(detailText)"
            ].joined(separator: "\n"),
            limit: Self.copyTextMaxCharacters
        )

        self.identifier = identifier
        statusIdentifier = readinessState.rawValue
        routeIdentifier = routeState.rawValue
        languageIdentifier = language.identifier
        self.seedCommandIdentifier = seedCommandIdentifier
        isReady = readinessState == .ready
        self.statusLabel = Self.bounded(statusLabel, limit: Self.statusLabelMaxCharacters)
        self.routeLabel = Self.bounded(routeLabel, limit: Self.routeLabelMaxCharacters)
        languageLabel = Self.bounded(language.label, limit: Self.languageLabelMaxCharacters)
        badgeLabel = Self.bounded(
            readinessState == .ready ? "Mutation: \(routeLabel)" : "Mutation: \(statusLabel)",
            limit: Self.labelMaxCharacters
        )
        systemImage = "testtube.2"
        seedCommand = sanitizedSeedCommand
        self.seedCommandLabel = Self.bounded(seedCommandLabel, limit: Self.commandMaxCharacters)
        self.detailText = detailText
        self.copyText = copyText
    }

    private static func routeState(for launchPlan: CodexExecutionLaunchPlan) -> RouteState {
        switch launchPlan.effectiveRoute {
        case .appleContainer:
            return .appleContainerRoute
        case .nativeMacOS:
            if launchPlan.selectedPreference == .devcontainerPreferred || launchPlan.fallbackReason != nil {
                return .nativeFallback
            }
            return .nativeRoute
        }
    }

    private static func languageDescriptor(
        for language: RepositoryLanguage
    ) -> (identifier: String, label: String, isSupported: Bool) {
        switch language {
        case .swift:
            return ("swift", "Swift", true)
        case .typeScriptJavaScript:
            return ("typescript-javascript", "TypeScript/JavaScript", true)
        case .python:
            return ("python", "Python", true)
        case .go:
            return ("go", "Go", true)
        case .rust:
            return ("rust", "Rust", true)
        case .markdown:
            return ("markdown", "Markdown", false)
        case .other:
            return ("other", "Other", false)
        case .unknown:
            return ("unknown", "Unknown", false)
        }
    }

    private static func statusLabel(for state: ReadinessState) -> String {
        switch state {
        case .ready:
            return "Ready"
        case .missingImmediate:
            return "Missing immediate"
        case .missingVerify:
            return "Missing verify"
        case .unsupportedLanguage:
            return "Unsupported language"
        }
    }

    private static func routeLabel(for state: RouteState) -> String {
        switch state {
        case .nativeRoute:
            return "Native"
        case .appleContainerRoute:
            return "Apple container"
        case .nativeFallback:
            return "Native fallback"
        }
    }

    private static func detailText(
        readinessState: ReadinessState,
        routeState: RouteState,
        languageLabel: String,
        seedCommandLabel: String
    ) -> String {
        let routeDetail: String
        switch routeState {
        case .nativeRoute:
            routeDetail = "native macOS"
        case .appleContainerRoute:
            routeDetail = "Apple container"
        case .nativeFallback:
            routeDetail = "native macOS fallback"
        }

        let detail: String
        switch readinessState {
        case .ready:
            detail = "Seed \(seedCommandLabel) for \(languageLabel); later mutation pass would use \(routeDetail)."
        case .missingImmediate:
            detail = "No immediate plan is available for mutation test planning."
        case .missingVerify:
            detail = "Immediate plan has no verify command to seed mutation testing."
        case .unsupportedLanguage:
            detail = "\(languageLabel) is outside the mutation readiness language set."
        }
        return bounded(detail, limit: detailMaxCharacters)
    }

    private static func sanitizedCommand(
        _ command: String,
        launchPlan: CodexExecutionLaunchPlan
    ) -> String {
        var sanitized = command
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        for value in sensitiveValues(from: launchPlan).sorted(by: { $0.count > $1.count }) where !value.isEmpty {
            sanitized = sanitized.replacingOccurrences(of: value, with: "[redacted]")
        }

        let replacements: [(pattern: String, template: String)] = [
            (#"(^|\s)(?:\./)?\.devcontainer/[^\s"']+"#, "$1[devcontainer-path]"),
            (#"([=:])(?:\./)?\.devcontainer/[^\s"']+"#, "$1[devcontainer-path]"),
            (#"(^|\s)/[^\s"']+"#, "$1[path]"),
            (#"([=:])/[^\s"']+"#, "$1[path]")
        ]

        for replacement in replacements {
            sanitized = sanitized.replacingOccurrences(
                of: replacement.pattern,
                with: replacement.template,
                options: .regularExpression
            )
        }

        return bounded(sanitized, limit: commandMaxCharacters)
    }

    private static func sensitiveValues(from launchPlan: CodexExecutionLaunchPlan) -> [String] {
        var values: [String] = []

        if let supportReport = launchPlan.devcontainerSupportReport {
            let configURL = supportReport.configURL.standardizedFileURL
            let configDirectoryURL = configURL.deletingLastPathComponent().standardizedFileURL
            let repoURL = configDirectoryURL.deletingLastPathComponent().standardizedFileURL
            values += [
                configURL.path,
                configDirectoryURL.path,
                repoURL.path
            ]

            if let imageConfiguration = supportReport.imageConfiguration {
                values += imageConfiguration.containerEnv.map(\.value)
            }
            if let buildConfiguration = supportReport.buildConfiguration {
                values += [
                    buildConfiguration.configURL.path,
                    buildConfiguration.repoURL.path,
                    buildConfiguration.dockerfileURL.path,
                    buildConfiguration.contextURL.path
                ]
                values += buildConfiguration.buildArgs.map(\.value)
                values += buildConfiguration.containerEnv.map(\.value)
            }
        }

        switch launchPlan.effectiveRoute {
        case .nativeMacOS:
            break
        case let .appleContainer(route):
            values += [
                route.toolPath,
                route.hostWorkspaceURL.path,
                route.volumeArgument,
                route.workspaceFolder
            ]
            values += route.containerEnv.map(\.value)
            if let buildConfiguration = route.buildConfiguration {
                values += [
                    buildConfiguration.configURL.path,
                    buildConfiguration.repoURL.path,
                    buildConfiguration.dockerfileURL.path,
                    buildConfiguration.contextURL.path
                ]
                values += buildConfiguration.buildArgs.map(\.value)
                values += buildConfiguration.containerEnv.map(\.value)
            }
        }

        return values
    }

    private static func bounded(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func boundedMultiline(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func nilIfEmpty(_ text: String) -> String? {
        text.isEmpty ? nil : text
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
