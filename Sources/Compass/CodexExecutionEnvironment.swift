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
        let plan = launchPlan()
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
                    status: "Running Codex through Apple container for the detected image-based devcontainer.",
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

    init(
        environment: CodexExecutionEnvironment,
        provisioningPlan: CodexDevcontainerProvisioningPlan? = nil
    ) {
        let presentation = environment.presentation
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
    }
}
