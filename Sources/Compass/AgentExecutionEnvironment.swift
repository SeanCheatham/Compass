import Foundation

enum AgentExecutionEnvironmentPreference: String, Codable, CaseIterable, Identifiable {
    case host = "native_macos"
    case sharedVM = "shared_vm"

    var id: Self { self }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = AgentExecutionEnvironmentPreference.decode(rawValue: rawValue)
    }

    /// Decodes a stored raw value into a preference, mapping any legacy values to `.host`.
    /// "devcontainer_preferred" is explicitly mapped to `.host` (no auto-enrollment).
    static func decode(rawValue: String) -> AgentExecutionEnvironmentPreference {
        if let known = AgentExecutionEnvironmentPreference(rawValue: rawValue) {
            return known
        }
        // Legacy "devcontainer_preferred" maps to .host (do not auto-enrol into shared VM).
        return .host
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var title: String {
        switch self {
        case .host:
            return "Native macOS"
        case .sharedVM:
            return "Shared VM"
        }
    }

    var systemImage: String {
        switch self {
        case .host:
            return "desktopcomputer"
        case .sharedVM:
            return "macwindow.on.rectangle"
        }
    }

    init(developSandbox: DevelopSandboxPreference) {
        switch developSandbox {
        case .host:
            self = .host
        case .sharedVM:
            self = .sharedVM
        }
    }

    var developSandbox: DevelopSandboxPreference {
        switch self {
        case .host:
            return .host
        case .sharedVM:
            return .sharedVM
        }
    }
}

struct AgentExecutionEnvironmentReadiness: Equatable {
    static let detailLimit = 280

    var vmReadiness: SharedCompassVMReadiness
    var detail: String

    init(
        vmReadiness: SharedCompassVMReadiness,
        detail: String? = nil
    ) {
        self.vmReadiness = vmReadiness
        let computed = detail ?? Self.detail(for: vmReadiness)
        self.detail = Self.boundedText(computed, limit: Self.detailLimit)
    }

    static func inspect(vmReadiness: SharedCompassVMReadiness) -> Self {
        Self(vmReadiness: vmReadiness)
    }

    private static func detail(for readiness: SharedCompassVMReadiness) -> String {
        switch readiness {
        case let .unavailable(reason):
            return "Shared VM is unavailable: \(reason). Native macOS execution remains available."
        case .notProvisioned:
            return "Shared VM has not been provisioned. Native macOS execution remains available."
        case let .downloadingIPSW(fraction):
            return "Shared VM is downloading the macOS restore image (\(Int((fraction * 100).rounded()))%)."
        case let .installing(fraction):
            return "Shared VM is installing macOS (\(Int((fraction * 100).rounded()))%)."
        case .guestPrepping:
            return "Shared VM is finishing headless first-boot setup."
        case let .ready(sshDestination):
            return "Shared VM is ready at \(sshDestination)."
        case let .error(detail):
            return "Shared VM reported an error: \(detail). Native macOS execution remains available."
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

struct AgentExecutionEnvironmentPresentation: Equatable {
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

struct AgentExecutionEnvironment: Equatable {
    var preference: AgentExecutionEnvironmentPreference
    var readiness: AgentExecutionEnvironmentReadiness

    init(
        preference: AgentExecutionEnvironmentPreference = .host,
        readiness: AgentExecutionEnvironmentReadiness
    ) {
        self.preference = preference
        self.readiness = readiness
    }

    static func discover(
        preference: AgentExecutionEnvironmentPreference = .host,
        vmReadiness: SharedCompassVMReadiness = .notProvisioned
    ) -> Self {
        Self(
            preference: preference,
            readiness: AgentExecutionEnvironmentReadiness.inspect(vmReadiness: vmReadiness)
        )
    }

    var effectivePreference: AgentExecutionEnvironmentPreference {
        launchPlan(repoURL: URL(fileURLWithPath: "/")).isVMRoute ? .sharedVM : .host
    }

    var presentation: AgentExecutionEnvironmentPresentation {
        presentation(launchPlan: launchPlan(repoURL: URL(fileURLWithPath: "/")))
    }

    func presentation(launchPlan plan: AgentExecutionLaunchPlan) -> AgentExecutionEnvironmentPresentation {
        switch preference {
        case .host:
            return AgentExecutionEnvironmentPresentation(
                title: "Native macOS",
                status: "Running the agent on the host. Shared VM remains available as an opt-in sandbox.",
                detail: readiness.detail,
                systemImage: preference.systemImage
            )
        case .sharedVM:
            if plan.isVMRoute {
                return AgentExecutionEnvironmentPresentation(
                    title: "Shared VM",
                    status: "Running the agent inside the Shared VM via SSH.",
                    detail: plan.routeDetail(),
                    systemImage: preference.systemImage
                )
            }
            return AgentExecutionEnvironmentPresentation(
                title: "Shared VM",
                status: "Shared VM selected, but Compass is falling back to native macOS.",
                detail: fallbackDetail(plan: plan),
                systemImage: "desktopcomputer.trianglebadge.exclamationmark",
                isWarning: true
            )
        }
    }

    func launchPreflightSummary(phase: String, nativeExecutionURL: URL) -> String {
        launchPlan(repoURL: nativeExecutionURL).preflightSummary(phase: phase)
    }

    var launchPreflightDetail: String {
        let plan = launchPlan(repoURL: URL(fileURLWithPath: "/"))
        let presentation = presentation
        return [presentation.status, presentation.detail, "VM readiness: \(plan.vmReadinessLabel).", plan.routeDetail()]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    func launchPlan(
        repoURL: URL,
        sharedVMRouteFactory: (URL) -> SharedVMRoute? = { _ in nil }
    ) -> AgentExecutionLaunchPlan {
        AgentExecutionLaunchPlan.plan(
            repoURL: repoURL,
            preference: preference,
            vmReadiness: readiness.vmReadiness,
            sharedVMRouteFactory: sharedVMRouteFactory
        )
    }

    private func fallbackDetail(plan: AgentExecutionLaunchPlan) -> String {
        [readiness.detail, plan.fallbackReason.map { "Fallback: \($0)" }]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

struct AgentExecutionEnvironmentDiagnosticsReport: Equatable, Identifiable {
    static let copyTextLimit = 2_000
    static let fieldLimit = 120
    static let helpLimit = 240
    static let stableCopyActionIdentifier = "runtime-diagnostics.copy"
    static let copyIdentifierPrefix = "runtime-diagnostics.copy.v1"

    var selectedPreferenceIdentifier: String
    var selectedPreferenceTitle: String
    var effectiveRouteIdentifier: String
    var effectiveRouteTitle: String
    var vmReadinessIdentifier: String
    var vmBuildStateIdentifier: String
    var vmBundleSizeLabel: String
    var vmGuestOSVersion: String
    var imageLabel: String
    var workspaceLabel: String
    var fallbackReason: String
    var mutationReadinessIdentifier: String
    var mutationStatusIdentifier: String
    var mutationRouteIdentifier: String
    var mutationLanguageIdentifier: String
    var mutationSeedCommandIdentifier: String
    var mutationSeedCommandLabel: String
    var mutationRecoveryStateIdentifier: String
    var mutationRecoveryIdentifier: String
    var mutationRecoveryDetail: String
    var copyActionIdentifier: String
    var copyIdentifier: String

    var id: String { copyIdentifier }

    init(
        environment: AgentExecutionEnvironment,
        launchPlan: AgentExecutionLaunchPlan,
        mutationTestingPlan: AgentMutationTestingPlan? = nil,
        mutationRecoveryDescriptor: MutationTestingRecoveryDescriptor? = nil,
        vmBundleSizeBytes: Int? = nil,
        vmGuestOSVersion: String? = nil
    ) {
        selectedPreferenceIdentifier = environment.preference.rawValue
        selectedPreferenceTitle = Self.sanitizedField(
            environment.preference.title,
            limit: Self.fieldLimit
        )
        effectiveRouteIdentifier = launchPlan.effectiveRouteIdentifier
        effectiveRouteTitle = Self.sanitizedField(
            launchPlan.effectiveRouteTitle,
            limit: Self.fieldLimit
        )
        vmReadinessIdentifier = Self.vmReadinessIdentifier(launchPlan.vmReadiness)
        vmBuildStateIdentifier = Self.vmBuildStateIdentifier(launchPlan.vmReadiness)
        vmBundleSizeLabel = Self.vmBundleSizeLabel(vmBundleSizeBytes)
        self.vmGuestOSVersion = Self.sanitizedField(vmGuestOSVersion ?? "unknown", limit: Self.fieldLimit)
        imageLabel = Self.sanitizedField(launchPlan.imageLabel, limit: Self.fieldLimit)
        workspaceLabel = Self.sanitizedField(launchPlan.workspaceLabel, limit: Self.fieldLimit)
        fallbackReason = Self.sanitizedField(
            launchPlan.fallbackReasonLabel,
            limit: AgentExecutionLaunchPlan.fallbackReasonLimit
        )

        if let mutationTestingPlan {
            mutationReadinessIdentifier = Self.sanitizedField(mutationTestingPlan.identifier, limit: Self.fieldLimit)
            mutationStatusIdentifier = Self.sanitizedField(mutationTestingPlan.statusIdentifier, limit: Self.fieldLimit)
            mutationRouteIdentifier = Self.sanitizedField(mutationTestingPlan.routeIdentifier, limit: Self.fieldLimit)
            mutationLanguageIdentifier = Self.sanitizedField(mutationTestingPlan.languageIdentifier, limit: Self.fieldLimit)
            mutationSeedCommandIdentifier = Self.sanitizedField(mutationTestingPlan.seedCommandIdentifier, limit: Self.fieldLimit)
            mutationSeedCommandLabel = Self.sanitizedField(mutationTestingPlan.seedCommandLabel, limit: Self.fieldLimit)
        } else {
            mutationReadinessIdentifier = "not-evaluated"
            mutationStatusIdentifier = "not-evaluated"
            mutationRouteIdentifier = "not-evaluated"
            mutationLanguageIdentifier = "not-evaluated"
            mutationSeedCommandIdentifier = "none"
            mutationSeedCommandLabel = "none"
        }

        if let mutationRecoveryDescriptor {
            mutationRecoveryStateIdentifier = Self.sanitizedField(
                mutationRecoveryDescriptor.stateIdentifier,
                limit: Self.fieldLimit
            )
            mutationRecoveryIdentifier = Self.sanitizedField(
                mutationRecoveryDescriptor.identifier,
                limit: Self.fieldLimit
            )
            mutationRecoveryDetail = Self.sanitizedField(
                mutationRecoveryDescriptor.detailText,
                limit: Self.helpLimit
            )
        } else {
            mutationRecoveryStateIdentifier = "not-evaluated"
            mutationRecoveryIdentifier = "none"
            mutationRecoveryDetail = "none"
        }

        copyActionIdentifier = Self.stableCopyActionIdentifier
        copyIdentifier = [
            Self.copyIdentifierPrefix,
            selectedPreferenceIdentifier,
            effectiveRouteIdentifier,
            vmReadinessIdentifier
        ].joined(separator: ".")
    }

    var copyText: String {
        Self.boundedCopyText(
            [
                "Runtime Diagnostics",
                "copy-id: \(copyIdentifier)",
                "copy-action-id: \(copyActionIdentifier)",
                "selected-preference: \(selectedPreferenceIdentifier) (\(selectedPreferenceTitle))",
                "effective-route: \(effectiveRouteIdentifier) (\(effectiveRouteTitle))",
                "vm-readiness: \(vmReadinessIdentifier)",
                "vm-build-state: \(vmBuildStateIdentifier)",
                "vm-bundle-size: \(vmBundleSizeLabel)",
                "vm-guest-os: \(vmGuestOSVersion)",
                "image: \(imageLabel)",
                "workspace: \(workspaceLabel)",
                "fallback: \(fallbackReason)",
                "mutation-readiness-id: \(mutationReadinessIdentifier)",
                "mutation-status: \(mutationStatusIdentifier)",
                "mutation-route: \(mutationRouteIdentifier)",
                "mutation-language: \(mutationLanguageIdentifier)",
                "mutation-seed-id: \(mutationSeedCommandIdentifier)",
                "mutation-seed-command: \(mutationSeedCommandLabel)",
                "mutation-recovery-state: \(mutationRecoveryStateIdentifier)",
                "mutation-recovery-id: \(mutationRecoveryIdentifier)",
                "mutation-recovery-detail: \(mutationRecoveryDetail)"
            ].joined(separator: "\n"),
            limit: Self.copyTextLimit
        )
    }

    var helpText: String {
        Self.boundedField(
            "Copy sanitized runtime diagnostics using \(copyActionIdentifier). No runtime preference, VM lifecycle, or project state is changed.",
            limit: Self.helpLimit
        )
    }

    private static func vmReadinessIdentifier(_ readiness: SharedCompassVMReadiness?) -> String {
        guard let readiness else { return "not-evaluated" }
        switch readiness {
        case .unavailable:
            return "unavailable"
        case .notProvisioned:
            return "not-provisioned"
        case .downloadingIPSW:
            return "downloading-ipsw"
        case .installing:
            return "installing"
        case .guestPrepping:
            return "guest-prepping"
        case .ready:
            return "ready"
        case .error:
            return "error"
        }
    }

    private static func vmBuildStateIdentifier(_ readiness: SharedCompassVMReadiness?) -> String {
        guard let readiness else { return "not-evaluated" }
        switch readiness {
        case .downloadingIPSW, .installing:
            return "building"
        case .ready, .guestPrepping:
            return "built"
        case .notProvisioned:
            return "not-built"
        case .unavailable, .error:
            return "blocked"
        }
    }

    private static func vmBundleSizeLabel(_ bytes: Int?) -> String {
        guard let bytes, bytes > 0 else { return "unknown" }
        let gigabytes = Double(bytes) / 1_073_741_824
        if gigabytes >= 1 {
            return String(format: "%.1fGB", gigabytes)
        }
        let megabytes = Double(bytes) / 1_048_576
        return String(format: "%.0fMB", megabytes)
    }

    private static func sanitizedField(_ text: String, limit: Int) -> String {
        boundedField(
            text
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            limit: limit
        )
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

struct AgentExecutionEnvironmentCopyDiagnosticsAction: Identifiable, Equatable {
    static let actionIdentifier = AgentExecutionEnvironmentDiagnosticsReport.stableCopyActionIdentifier
    static let titleLimit = 34
    static let descriptionLimit = 220

    var report: AgentExecutionEnvironmentDiagnosticsReport

    var id: String { Self.actionIdentifier }

    var title: String {
        Self.boundedText("Copy Runtime Diagnostics", limit: Self.titleLimit)
    }

    var systemImage: String {
        "doc.on.doc"
    }

    var description: String {
        Self.boundedText(
            "Copy a bounded sanitized runtime report for the selected route, VM readiness, and mutation status.",
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

struct AgentExecutionEnvironmentMenuItem: Identifiable, Equatable {
    static let descriptionLimit = 180

    var preference: AgentExecutionEnvironmentPreference
    var title: String
    var systemImage: String
    var isSelected: Bool
    var description: String

    var id: AgentExecutionEnvironmentPreference { preference }

    init(
        preference: AgentExecutionEnvironmentPreference,
        selectedPreference: AgentExecutionEnvironmentPreference,
        readiness: AgentExecutionEnvironmentReadiness
    ) {
        self.preference = preference
        title = preference.title
        systemImage = selectedPreference == preference ? "checkmark" : preference.systemImage
        isSelected = selectedPreference == preference
        description = Self.boundedText(
            Self.description(for: preference, readiness: readiness),
            limit: Self.descriptionLimit
        )
    }

    private static func description(
        for preference: AgentExecutionEnvironmentPreference,
        readiness: AgentExecutionEnvironmentReadiness
    ) -> String {
        switch preference {
        case .host:
            return "Run the agent on the host. Best for macOS frameworks, UI automation, and local tools."
        case .sharedVM:
            switch readiness.vmReadiness {
            case .ready:
                return "Run the agent inside the Shared VM via SSH. Provides reproducible Linux/macOS isolation."
            case .unavailable(let reason):
                return "Shared VM is unavailable: \(reason). Compass falls back to native macOS."
            case .notProvisioned:
                return "Shared VM has not been provisioned yet. Provision the VM from the Sandbox section to enable this route."
            case .downloadingIPSW, .installing, .guestPrepping:
                return "Shared VM is still preparing. Compass falls back to native macOS until the VM is ready."
            case .error(let detail):
                return "Shared VM reported an error: \(detail). Compass falls back to native macOS."
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

struct AgentExecutionEnvironmentMenu: Equatable {
    var labelSystemImage: String
    var helpText: String
    var statusText: String
    var items: [AgentExecutionEnvironmentMenuItem]
    var copyDiagnosticsAction: AgentExecutionEnvironmentCopyDiagnosticsAction
    var mutationTestingAction: AgentMutationTestingMenuAction?
    var mutationRecoveryDescriptor: MutationTestingRecoveryDescriptor?

    init(
        environment: AgentExecutionEnvironment,
        launchPlan: AgentExecutionLaunchPlan? = nil,
        mutationTestingPlan: AgentMutationTestingPlan? = nil,
        mutationRecoveryDescriptor: MutationTestingRecoveryDescriptor? = nil,
        mutationExecutionState: AgentMutationTestingMenuAction.ExecutionState = .idle,
        vmBundleSizeBytes: Int? = nil,
        vmGuestOSVersion: String? = nil
    ) {
        let effectiveLaunchPlan = launchPlan ?? environment.launchPlan(repoURL: URL(fileURLWithPath: "/"))
        let presentation = environment.presentation(launchPlan: effectiveLaunchPlan)
        labelSystemImage = presentation.systemImage
        helpText = "Execution environment: \(presentation.title). \(presentation.detail)"
        statusText = [presentation.status, presentation.detail]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        items = AgentExecutionEnvironmentPreference.allCases.map {
            AgentExecutionEnvironmentMenuItem(
                preference: $0,
                selectedPreference: environment.preference,
                readiness: environment.readiness
            )
        }
        copyDiagnosticsAction = AgentExecutionEnvironmentCopyDiagnosticsAction(
            report: AgentExecutionEnvironmentDiagnosticsReport(
                environment: environment,
                launchPlan: effectiveLaunchPlan,
                mutationTestingPlan: mutationTestingPlan,
                mutationRecoveryDescriptor: mutationRecoveryDescriptor,
                vmBundleSizeBytes: vmBundleSizeBytes,
                vmGuestOSVersion: vmGuestOSVersion
            )
        )
        mutationTestingAction = mutationTestingPlan.map {
            AgentMutationTestingMenuAction(
                readiness: $0,
                executionState: mutationExecutionState
            )
        }
        self.mutationRecoveryDescriptor = mutationRecoveryDescriptor
    }
}
