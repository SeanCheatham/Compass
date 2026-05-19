import Foundation

enum CodexExecutionEnvironmentPreference: String, Codable, CaseIterable, Identifiable {
    case nativeMacOS = "native_macos"
    case devcontainerPreferred = "devcontainer_preferred"

    var id: Self { self }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = CodexExecutionEnvironmentPreference(rawValue: rawValue) ?? .nativeMacOS
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var title: String {
        switch self {
        case .nativeMacOS:
            return "Native macOS"
        case .devcontainerPreferred:
            return "Dev Container Preferred"
        }
    }

    var systemImage: String {
        switch self {
        case .nativeMacOS:
            return "desktopcomputer"
        case .devcontainerPreferred:
            return "shippingbox"
        }
    }
}

struct CodexExecutionEnvironmentDiscovery: Equatable {
    static let nameLimit = 80
    static let detailLimit = 280
    static let reasonLimit = 220

    enum Status: String, Equatable {
        case ready
        case missing
        case malformed
    }

    var status: Status
    var configURL: URL
    var name: String?
    var detail: String
    var reason: String?
    var supportReport: CodexDevcontainerSupportReport

    init(
        status: Status,
        configURL: URL,
        name: String? = nil,
        detail: String,
        reason: String? = nil,
        supportReport: CodexDevcontainerSupportReport? = nil
    ) {
        self.status = status
        self.configURL = configURL.standardizedFileURL
        self.name = Self.boundedOptionalText(name, limit: Self.nameLimit)
        self.detail = Self.boundedText(detail, limit: Self.detailLimit)
        self.reason = Self.boundedOptionalText(reason, limit: Self.reasonLimit)
        self.supportReport = supportReport ?? CodexDevcontainerSupportReport(
            classification: status == .missing ? .missing : .malformed,
            configURL: configURL,
            name: name,
            reason: reason
        )
    }

    static func inspect(repoURL: URL, fileManager: FileManager = .default) -> Self {
        let standardizedRepoURL = repoURL.standardizedFileURL
        let supportReport = CodexDevcontainerSupportReport.inspect(
            repoURL: standardizedRepoURL,
            fileManager: fileManager
        )

        switch supportReport.classification {
        case .missing:
            return Self(
                status: .missing,
                configURL: supportReport.configURL,
                detail: "No .devcontainer/devcontainer.json was found. Native macOS execution remains available.",
                reason: supportReport.reason,
                supportReport: supportReport
            )
        case .malformed:
            return Self(
                status: .malformed,
                configURL: supportReport.configURL,
                name: supportReport.name,
                detail: "Found devcontainer.json, but it is malformed. Native macOS execution remains available. Support: \(supportReport.supportSummary).",
                reason: supportReport.reason,
                supportReport: supportReport
            )
        case .imageRouteable:
            return Self(
                status: .ready,
                configURL: supportReport.configURL,
                name: supportReport.name,
                detail: "Found image-routeable .devcontainer/devcontainer.json. Dev Container Preferred can use Apple container when the CLI is available; native macOS remains available. Support: \(supportReport.supportSummary).",
                reason: supportReport.reason,
                supportReport: supportReport
            )
        case .buildBased where supportReport.isBuildRouteable:
            return Self(
                status: .ready,
                configURL: supportReport.configURL,
                name: supportReport.name,
                detail: "Found build-based .devcontainer/devcontainer.json. Dev Container Preferred can build a local Apple container image when the CLI is available; native macOS remains available. Support: \(supportReport.supportSummary).",
                reason: supportReport.reason,
                supportReport: supportReport
            )
        case .buildBased, .composeBased, .featureBased, .unsupportedExtraFields:
            return Self(
                status: .ready,
                configURL: supportReport.configURL,
                name: supportReport.name,
                detail: "Found .devcontainer/devcontainer.json, but Apple container routing cannot use this config. Native macOS execution remains available. Support: \(supportReport.supportSummary).",
                reason: supportReport.unsupportedRouteReason,
                supportReport: supportReport
            )
        }
    }

    private static func boundedOptionalText(_ text: String?, limit: Int) -> String? {
        let bounded = boundedText(text ?? "", limit: limit)
        return bounded.isEmpty ? nil : bounded
    }

    private static func boundedText(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct CodexExecutionEnvironmentPresentation: Equatable {
    static let titleLimit = 48
    static let statusLimit = 180
    static let detailLimit = 320

    var title: String
    var status: String
    var detail: String
    var systemImage: String
    var isWarning: Bool

    init(
        title: String,
        status: String,
        detail: String,
        systemImage: String,
        isWarning: Bool = false
    ) {
        self.title = Self.boundedText(title, limit: Self.titleLimit)
        self.status = Self.boundedText(status, limit: Self.statusLimit)
        self.detail = Self.boundedText(detail, limit: Self.detailLimit)
        self.systemImage = systemImage
        self.isWarning = isWarning
    }

    private static func boundedText(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct CodexExecutionEnvironment: Equatable {
    var preference: CodexExecutionEnvironmentPreference
    var devcontainerDiscovery: CodexExecutionEnvironmentDiscovery

    init(
        preference: CodexExecutionEnvironmentPreference = .nativeMacOS,
        devcontainerDiscovery: CodexExecutionEnvironmentDiscovery
    ) {
        self.preference = preference
        self.devcontainerDiscovery = devcontainerDiscovery
    }

    static func discover(
        repoURL: URL,
        preference: CodexExecutionEnvironmentPreference = .nativeMacOS,
        fileManager: FileManager = .default
    ) -> Self {
        Self(
            preference: preference,
            devcontainerDiscovery: CodexExecutionEnvironmentDiscovery.inspect(
                repoURL: repoURL,
                fileManager: fileManager
            )
        )
    }

    var effectivePreference: CodexExecutionEnvironmentPreference {
        launchPlan().isContainerRoute ? .devcontainerPreferred : .nativeMacOS
    }

    var presentation: CodexExecutionEnvironmentPresentation {
        presentation(launchPlan: launchPlan())
    }

    func presentation(launchPlan plan: CodexExecutionLaunchPlan) -> CodexExecutionEnvironmentPresentation {
        switch preference {
        case .nativeMacOS:
            switch devcontainerDiscovery.status {
            case .ready:
                if devcontainerDiscovery.supportReport.isImageRouteable {
                    return CodexExecutionEnvironmentPresentation(
                        title: "Native macOS",
                        status: "Running on native macOS. An image-routeable devcontainer is present when container execution is enabled.",
                        detail: devcontainerDiscovery.detail,
                        systemImage: preference.systemImage
                    )
                }
                return CodexExecutionEnvironmentPresentation(
                    title: "Native macOS",
                    status: "Running on native macOS. The devcontainer is present but not Apple-container routeable.",
                    detail: devcontainerDiscovery.detail,
                    systemImage: preference.systemImage
                )
            case .missing:
                return CodexExecutionEnvironmentPresentation(
                    title: "Native macOS",
                    status: "Running on native macOS. Dev containers are optional for this project.",
                    detail: devcontainerDiscovery.detail,
                    systemImage: preference.systemImage
                )
            case .malformed:
                return CodexExecutionEnvironmentPresentation(
                    title: "Native macOS",
                    status: "Running on native macOS. The devcontainer config needs attention before it can be preferred.",
                    detail: malformedDetail(prefix: devcontainerDiscovery.detail),
                    systemImage: "exclamationmark.triangle",
                    isWarning: true
                )
            }
        case .devcontainerPreferred:
            if plan.isContainerRoute {
                return CodexExecutionEnvironmentPresentation(
                    title: "Dev Container Preferred",
                    status: plan.devcontainerSupportReport?.isBuildRouteable == true
                        ? "Running Codex through Apple container for the detected build-based devcontainer."
                        : "Running Codex through Apple container for the detected image-based devcontainer.",
                    detail: plan.routeDetail(),
                    systemImage: preference.systemImage
                )
            }

            switch devcontainerDiscovery.status {
            case .ready:
                return CodexExecutionEnvironmentPresentation(
                    title: "Dev Container Preferred",
                    status: "Dev Container Preferred selected, but Compass is falling back to native macOS.",
                    detail: fallbackDetail(plan: plan, prefix: devcontainerDiscovery.detail),
                    systemImage: "desktopcomputer.trianglebadge.exclamationmark",
                    isWarning: true
                )
            case .missing:
                return CodexExecutionEnvironmentPresentation(
                    title: "Dev Container Preferred",
                    status: "Dev Container Preferred selected, but no config was found; falling back to native macOS.",
                    detail: fallbackDetail(plan: plan, prefix: devcontainerDiscovery.detail),
                    systemImage: "desktopcomputer.trianglebadge.exclamationmark",
                    isWarning: true
                )
            case .malformed:
                return CodexExecutionEnvironmentPresentation(
                    title: "Dev Container Preferred",
                    status: "Dev Container Preferred selected, but the config is malformed; falling back to native macOS.",
                    detail: fallbackDetail(plan: plan, prefix: malformedDetail(prefix: devcontainerDiscovery.detail)),
                    systemImage: "desktopcomputer.trianglebadge.exclamationmark",
                    isWarning: true
                )
            }
        }
    }

    func launchPreflightSummary(phase: String, nativeExecutionURL: URL) -> String {
        launchPlan(repoURL: nativeExecutionURL).preflightSummary(phase: phase)
    }

    var launchPreflightDetail: String {
        let plan = launchPlan()
        let presentation = presentation
        return [presentation.status, presentation.detail, "Support: \(plan.devcontainerSupportLabel).", plan.routeDetail()]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    func launchPlan(
        repoURL: URL? = nil,
        fileManager: FileManager = .default,
        containerToolResolver: (String) -> String? = CodexExecutionLaunchPlan.defaultContainerToolResolver
    ) -> CodexExecutionLaunchPlan {
        CodexExecutionLaunchPlan.plan(
            repoURL: repoURL ?? inferredRepoURL,
            preference: preference,
            fileManager: fileManager,
            containerToolResolver: containerToolResolver
        )
    }

    private func malformedDetail(prefix: String) -> String {
        [prefix, devcontainerDiscovery.reason.map { "Reason: \($0)" }]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private var inferredRepoURL: URL {
        devcontainerDiscovery.configURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .standardizedFileURL
    }

    private func fallbackDetail(plan: CodexExecutionLaunchPlan, prefix: String) -> String {
        [prefix, "Support: \(devcontainerDiscovery.supportReport.supportSummary).", plan.fallbackReason.map { "Fallback: \($0)" }]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

struct CodexExecutionEnvironmentDiagnosticsReport: Equatable, Identifiable {
    static let copyTextLimit = 1_600
    static let fieldLimit = 120
    static let helpLimit = 240
    static let stableCopyActionIdentifier = "runtime-diagnostics.copy"
    static let copyIdentifierPrefix = "runtime-diagnostics.copy.v1"

    var selectedPreferenceIdentifier: String
    var selectedPreferenceTitle: String
    var effectiveRouteIdentifier: String
    var effectiveRouteTitle: String
    var supportClassificationIdentifier: String
    var visibleSupportTokens: [String]
    var omittedSupportTokenCount: Int
    var imageLabel: String
    var workspaceLabel: String
    var fallbackReason: String
    var provisioningStatusIdentifier: String
    var provisioningAvailabilityIdentifier: String
    var provisioningActionIdentifier: String
    var provisioningTemplateIdentifier: String
    var provisioningImageLabel: String
    var provisioningWorkspaceLabel: String
    var mutationReadinessIdentifier: String
    var mutationStatusIdentifier: String
    var mutationRouteIdentifier: String
    var mutationLanguageIdentifier: String
    var mutationSeedCommandIdentifier: String
    var mutationSeedCommandLabel: String
    var copyActionIdentifier: String
    var copyIdentifier: String

    var id: String { copyIdentifier }

    init(
        environment: CodexExecutionEnvironment,
        launchPlan: CodexExecutionLaunchPlan,
        provisioningPlan: CodexDevcontainerProvisioningPlan? = nil,
        mutationTestingPlan: CodexMutationTestingPlan? = nil
    ) {
        let supportReport = launchPlan.devcontainerSupportReport ?? environment.devcontainerDiscovery.supportReport
        let configURL = supportReport.configURL
        let repoURL = configURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .standardizedFileURL

        selectedPreferenceIdentifier = environment.preference.rawValue
        selectedPreferenceTitle = Self.sanitizedField(
            environment.preference.title,
            repoURL: repoURL,
            configURL: configURL,
            limit: Self.fieldLimit
        )
        effectiveRouteIdentifier = launchPlan.effectiveRouteIdentifier
        effectiveRouteTitle = Self.sanitizedField(
            launchPlan.effectiveRouteTitle,
            repoURL: repoURL,
            configURL: configURL,
            limit: Self.fieldLimit
        )
        supportClassificationIdentifier = supportReport.classification.rawValue
        visibleSupportTokens = supportReport.supportTokens
            .map {
                Self.sanitizedField(
                    $0,
                    repoURL: repoURL,
                    configURL: configURL,
                    limit: CodexDevcontainerSupportReport.tokenLimit
                )
            }
            .filter { !$0.isEmpty }
        omittedSupportTokenCount = supportReport.omittedTokenCount
        imageLabel = Self.sanitizedField(
            launchPlan.imageLabel,
            repoURL: repoURL,
            configURL: configURL,
            limit: Self.fieldLimit
        )
        workspaceLabel = Self.sanitizedField(
            launchPlan.workspaceLabel,
            repoURL: repoURL,
            configURL: configURL,
            limit: Self.fieldLimit
        )
        fallbackReason = Self.sanitizedField(
            launchPlan.fallbackReasonLabel,
            repoURL: repoURL,
            configURL: configURL,
            limit: CodexExecutionLaunchPlan.fallbackReasonLimit
        )

        if let provisioningPlan {
            provisioningStatusIdentifier = Self.provisioningStatusIdentifier(provisioningPlan.status)
            provisioningAvailabilityIdentifier = provisioningPlan.isAvailable ? "available" : "unavailable"
            provisioningTemplateIdentifier = Self.sanitizedField(
                provisioningPlan.template.id,
                repoURL: repoURL,
                configURL: configURL,
                limit: Self.fieldLimit
            )
            provisioningImageLabel = Self.sanitizedField(
                provisioningPlan.template.imageLabel,
                repoURL: repoURL,
                configURL: configURL,
                limit: Self.fieldLimit
            )
            provisioningWorkspaceLabel = Self.sanitizedField(
                provisioningPlan.template.workspaceLabel,
                repoURL: repoURL,
                configURL: configURL,
                limit: Self.fieldLimit
            )
        } else {
            provisioningStatusIdentifier = "not-evaluated"
            provisioningAvailabilityIdentifier = "unknown"
            provisioningTemplateIdentifier = "none"
            provisioningImageLabel = "none"
            provisioningWorkspaceLabel = "none"
        }

        if let mutationTestingPlan {
            mutationReadinessIdentifier = Self.sanitizedField(
                mutationTestingPlan.identifier,
                repoURL: repoURL,
                configURL: configURL,
                limit: Self.fieldLimit
            )
            mutationStatusIdentifier = Self.sanitizedField(
                mutationTestingPlan.statusIdentifier,
                repoURL: repoURL,
                configURL: configURL,
                limit: Self.fieldLimit
            )
            mutationRouteIdentifier = Self.sanitizedField(
                mutationTestingPlan.routeIdentifier,
                repoURL: repoURL,
                configURL: configURL,
                limit: Self.fieldLimit
            )
            mutationLanguageIdentifier = Self.sanitizedField(
                mutationTestingPlan.languageIdentifier,
                repoURL: repoURL,
                configURL: configURL,
                limit: Self.fieldLimit
            )
            mutationSeedCommandIdentifier = Self.sanitizedField(
                mutationTestingPlan.seedCommandIdentifier,
                repoURL: repoURL,
                configURL: configURL,
                limit: Self.fieldLimit
            )
            mutationSeedCommandLabel = Self.sanitizedField(
                mutationTestingPlan.seedCommandLabel,
                repoURL: repoURL,
                configURL: configURL,
                limit: Self.fieldLimit
            )
        } else {
            mutationReadinessIdentifier = "not-evaluated"
            mutationStatusIdentifier = "not-evaluated"
            mutationRouteIdentifier = "not-evaluated"
            mutationLanguageIdentifier = "not-evaluated"
            mutationSeedCommandIdentifier = "none"
            mutationSeedCommandLabel = "none"
        }

        provisioningActionIdentifier = CodexDevcontainerProvisioningMenuAction.actionIdentifier
        copyActionIdentifier = Self.stableCopyActionIdentifier
        copyIdentifier = [
            Self.copyIdentifierPrefix,
            selectedPreferenceIdentifier,
            effectiveRouteIdentifier,
            supportClassificationIdentifier,
            provisioningStatusIdentifier
        ].joined(separator: ".")
    }

    var copyText: String {
        let tokenText = visibleSupportTokens.isEmpty
            ? "none"
            : visibleSupportTokens.joined(separator: ",")
        return Self.boundedCopyText(
            [
                "Runtime Diagnostics",
                "copy-id: \(copyIdentifier)",
                "copy-action-id: \(copyActionIdentifier)",
                "selected-preference: \(selectedPreferenceIdentifier) (\(selectedPreferenceTitle))",
                "effective-route: \(effectiveRouteIdentifier) (\(effectiveRouteTitle))",
                "support-classification: \(supportClassificationIdentifier)",
                "support-tokens: \(tokenText)",
                "omitted-support-token-count: \(omittedSupportTokenCount)",
                "image: \(imageLabel)",
                "workspace: \(workspaceLabel)",
                "fallback: \(fallbackReason)",
                "provisioning: \(provisioningAvailabilityIdentifier) (\(provisioningStatusIdentifier))",
                "provisioning-action-id: \(provisioningActionIdentifier)",
                "provisioning-template: \(provisioningTemplateIdentifier)",
                "provisioning-image: \(provisioningImageLabel)",
                "provisioning-workspace: \(provisioningWorkspaceLabel)",
                "mutation-readiness-id: \(mutationReadinessIdentifier)",
                "mutation-status: \(mutationStatusIdentifier)",
                "mutation-route: \(mutationRouteIdentifier)",
                "mutation-language: \(mutationLanguageIdentifier)",
                "mutation-seed-id: \(mutationSeedCommandIdentifier)",
                "mutation-seed-command: \(mutationSeedCommandLabel)"
            ].joined(separator: "\n"),
            limit: Self.copyTextLimit
        )
    }

    var helpText: String {
        Self.boundedField(
            "Copy sanitized runtime diagnostics using \(copyActionIdentifier). No runtime preference, provisioning action, discovery mutation, or project state is changed.",
            limit: Self.helpLimit
        )
    }

    private static func provisioningStatusIdentifier(_ status: CodexDevcontainerProvisioningPlan.Status) -> String {
        switch status {
        case .available:
            return "available"
        case .alreadyPresent:
            return "already-present"
        case .malformed:
            return "malformed"
        }
    }

    private static func sanitizedField(
        _ text: String,
        repoURL: URL,
        configURL: URL,
        limit: Int
    ) -> String {
        let repoPath = repoURL.standardizedFileURL.path
        let configPath = configURL.standardizedFileURL.path
        let configDirectoryPath = configURL.deletingLastPathComponent().standardizedFileURL.path
        var sanitized = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let replacements = [
            (configPath, "[devcontainer-json]"),
            (configDirectoryPath, "[devcontainer-dir]"),
            (repoPath, "[repo]")
        ].sorted { $0.0.count > $1.0.count }

        for (path, replacement) in replacements where !path.isEmpty {
            let pathPrefix = path.hasSuffix("/") ? path : path + "/"
            sanitized = sanitized.replacingOccurrences(of: pathPrefix, with: "\(replacement)/")
            sanitized = sanitized.replacingOccurrences(of: path, with: replacement)
        }

        return boundedField(sanitized, limit: limit)
    }

    private static func boundedField(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func boundedCopyText(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct CodexExecutionEnvironmentCopyDiagnosticsAction: Identifiable, Equatable {
    static let actionIdentifier = CodexExecutionEnvironmentDiagnosticsReport.stableCopyActionIdentifier
    static let titleLimit = 34
    static let descriptionLimit = 220

    var report: CodexExecutionEnvironmentDiagnosticsReport

    var id: String { Self.actionIdentifier }

    var title: String {
        Self.boundedText(
            "Copy Runtime Diagnostics",
            limit: Self.titleLimit
        )
    }

    var systemImage: String {
        "doc.on.doc"
    }

    var description: String {
        Self.boundedText(
            "Copy a bounded sanitized runtime report for the selected route, devcontainer support, and provisioning availability.",
            limit: Self.descriptionLimit
        )
    }

    var helpText: String {
        report.helpText
    }

    var copyIdentifier: String {
        report.copyIdentifier
    }

    var copyText: String {
        report.copyText
    }

    private static func boundedText(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct CodexExecutionEnvironmentMenuItem: Identifiable, Equatable {
    static let descriptionLimit = 180

    var preference: CodexExecutionEnvironmentPreference
    var title: String
    var systemImage: String
    var isSelected: Bool
    var description: String

    var id: CodexExecutionEnvironmentPreference { preference }

    init(
        preference: CodexExecutionEnvironmentPreference,
        selectedPreference: CodexExecutionEnvironmentPreference,
        discovery: CodexExecutionEnvironmentDiscovery
    ) {
        self.preference = preference
        title = preference.title
        systemImage = selectedPreference == preference ? "checkmark" : preference.systemImage
        isSelected = selectedPreference == preference
        description = Self.boundedText(
            Self.description(for: preference, discovery: discovery),
            limit: Self.descriptionLimit
        )
    }

    private static func description(
        for preference: CodexExecutionEnvironmentPreference,
        discovery: CodexExecutionEnvironmentDiscovery
    ) -> String {
        switch preference {
        case .nativeMacOS:
            return "Run Codex on the host. Best for macOS frameworks, UI automation, and local tools."
        case .devcontainerPreferred:
            switch discovery.status {
            case .ready:
                if discovery.supportReport.isImageRouteable {
                    return "Prefer image-routeable devcontainers through Apple container; missing tooling falls back to native macOS."
                }
                if discovery.supportReport.isBuildRouteable {
                    return "Build a local Apple container image for this build-based devcontainer; missing tooling falls back to native macOS."
                }
                return "This \(discovery.supportReport.classification.rawValue) config falls back to native macOS; tokens \(discovery.supportReport.tokenSummary)."
            case .missing:
                return "Prefer devcontainers when .devcontainer/devcontainer.json exists; until then Compass runs on native macOS."
            case .malformed:
                return "Prefer devcontainers after the config is fixed; Compass falls back to native macOS."
            }
        }
    }

    private static func boundedText(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct CodexExecutionEnvironmentMenu: Equatable {
    var labelSystemImage: String
    var helpText: String
    var statusText: String
    var items: [CodexExecutionEnvironmentMenuItem]
    var createDevcontainerAction: CodexDevcontainerProvisioningMenuAction?
    var copyDiagnosticsAction: CodexExecutionEnvironmentCopyDiagnosticsAction
    var mutationTestingAction: CodexMutationTestingMenuAction?

    init(
        environment: CodexExecutionEnvironment,
        provisioningPlan: CodexDevcontainerProvisioningPlan? = nil,
        launchPlan: CodexExecutionLaunchPlan? = nil,
        mutationTestingPlan: CodexMutationTestingPlan? = nil,
        mutationExecutionState: CodexMutationTestingMenuAction.ExecutionState = .idle
    ) {
        let effectiveLaunchPlan = launchPlan ?? environment.launchPlan()
        let presentation = environment.presentation(launchPlan: effectiveLaunchPlan)
        labelSystemImage = presentation.systemImage
        helpText = "Execution environment: \(presentation.title). \(presentation.detail)"
        statusText = [presentation.status, presentation.detail]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        items = CodexExecutionEnvironmentPreference.allCases.map {
            CodexExecutionEnvironmentMenuItem(
                preference: $0,
                selectedPreference: environment.preference,
                discovery: environment.devcontainerDiscovery
            )
        }
        createDevcontainerAction = provisioningPlan.flatMap(CodexDevcontainerProvisioningMenuAction.init(plan:))
        copyDiagnosticsAction = CodexExecutionEnvironmentCopyDiagnosticsAction(
            report: CodexExecutionEnvironmentDiagnosticsReport(
                environment: environment,
                launchPlan: effectiveLaunchPlan,
                provisioningPlan: provisioningPlan,
                mutationTestingPlan: mutationTestingPlan
            )
        )
        mutationTestingAction = mutationTestingPlan.map {
            CodexMutationTestingMenuAction(
                readiness: $0,
                executionState: mutationExecutionState
            )
        }
    }
}
