import Foundation

struct AgentExecutionInvocation: Equatable {
    var executable: String
    var arguments: [String]
    var workingDirectory: URL?

    init(executable: String, arguments: [String], workingDirectory: URL? = nil) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory?.standardizedFileURL
    }
}

struct AgentExecutionLaunchPlan: Equatable {
    static let fallbackReasonLimit = 180
    static let labelLimit = 80

    enum Route: Equatable {
        case host
        case sharedVM(SharedVMRoute)
    }

    var selectedPreference: AgentExecutionEnvironmentPreference
    var effectiveRoute: Route
    var vmReadiness: SharedCompassVMReadiness?
    var fallbackReason: String?

    init(
        selectedPreference: AgentExecutionEnvironmentPreference,
        effectiveRoute: Route,
        vmReadiness: SharedCompassVMReadiness? = nil,
        fallbackReason: String? = nil
    ) {
        self.selectedPreference = selectedPreference
        self.effectiveRoute = effectiveRoute
        self.vmReadiness = vmReadiness
        self.fallbackReason = Self.boundedOptionalText(fallbackReason, limit: Self.fallbackReasonLimit)
    }

    static func host(
        selectedPreference: AgentExecutionEnvironmentPreference = .host,
        vmReadiness: SharedCompassVMReadiness? = nil,
        fallbackReason: String? = nil
    ) -> Self {
        Self(
            selectedPreference: selectedPreference,
            effectiveRoute: .host,
            vmReadiness: vmReadiness,
            fallbackReason: fallbackReason
        )
    }

    static func plan(
        repoURL: URL,
        preference: AgentExecutionEnvironmentPreference,
        vmReadiness: SharedCompassVMReadiness? = nil,
        sharedVMRouteFactory: (URL) -> SharedVMRoute? = { _ in nil }
    ) -> Self {
        switch preference {
        case .host:
            return host(
                selectedPreference: preference,
                vmReadiness: vmReadiness
            )
        case .sharedVM:
            guard let readiness = vmReadiness else {
                return host(
                    selectedPreference: preference,
                    vmReadiness: nil,
                    fallbackReason: "Shared VM readiness has not been evaluated yet."
                )
            }

            switch readiness {
            case .ready:
                if let route = sharedVMRouteFactory(repoURL.standardizedFileURL) {
                    return Self(
                        selectedPreference: preference,
                        effectiveRoute: .sharedVM(route),
                        vmReadiness: readiness
                    )
                }
                return host(
                    selectedPreference: preference,
                    vmReadiness: readiness,
                    fallbackReason: "Worktree is outside the Shared VM workspaces share; this phase runs on the host."
                )
            case let .unavailable(reason):
                return host(
                    selectedPreference: preference,
                    vmReadiness: readiness,
                    fallbackReason: Self.boundedText(
                        "Shared VM unavailable: \(reason)",
                        limit: Self.fallbackReasonLimit
                    )
                )
            case let .error(detail):
                return host(
                    selectedPreference: preference,
                    vmReadiness: readiness,
                    fallbackReason: Self.boundedText(
                        "Shared VM error: \(detail)",
                        limit: Self.fallbackReasonLimit
                    )
                )
            case .notProvisioned:
                return host(
                    selectedPreference: preference,
                    vmReadiness: readiness,
                    fallbackReason: "Shared VM has not been provisioned yet."
                )
            case .downloadingIPSW:
                return host(
                    selectedPreference: preference,
                    vmReadiness: readiness,
                    fallbackReason: "Shared VM is downloading the restore image."
                )
            case .installing:
                return host(
                    selectedPreference: preference,
                    vmReadiness: readiness,
                    fallbackReason: "Shared VM is installing macOS."
                )
            case .guestPrepping:
                return host(
                    selectedPreference: preference,
                    vmReadiness: readiness,
                    fallbackReason: "Shared VM guest preparation is in progress."
                )
            case .provisioningDevTools:
                return host(
                    selectedPreference: preference,
                    vmReadiness: readiness,
                    fallbackReason: "Shared VM is installing developer tools inside the guest."
                )
            }
        }
    }

    var isVMRoute: Bool {
        if case .sharedVM = effectiveRoute { return true }
        return false
    }

    var effectiveRouteTitle: String {
        switch effectiveRoute {
        case .host:
            return "Native macOS"
        case .sharedVM:
            return "Shared VM"
        }
    }

    var effectiveRouteIdentifier: String {
        switch effectiveRoute {
        case .host:
            return "native-macos"
        case .sharedVM:
            return "shared-vm"
        }
    }

    var imageLabel: String {
        switch effectiveRoute {
        case .host:
            return "none"
        case let .sharedVM(route):
            return Self.boundedText(route.sshDestination, limit: Self.labelLimit)
        }
    }

    var workspaceLabel: String {
        switch effectiveRoute {
        case .host:
            return "host"
        case let .sharedVM(route):
            return Self.boundedText(route.guestWorkspacePath, limit: Self.labelLimit)
        }
    }

    var fallbackReasonLabel: String {
        fallbackReason ?? "none"
    }

    var vmReadinessLabel: String {
        guard let vmReadiness else { return "not-inspected" }
        return Self.readinessSummary(vmReadiness)
    }

    static func readinessSummary(_ readiness: SharedCompassVMReadiness) -> String {
        switch readiness {
        case let .unavailable(reason):
            return "unavailable: \(reason)"
        case .notProvisioned:
            return "not-provisioned"
        case let .downloadingIPSW(fraction):
            return "downloading-ipsw \(Int((fraction * 100).rounded()))%"
        case let .installing(fraction):
            return "installing \(Int((fraction * 100).rounded()))%"
        case .guestPrepping:
            return "guest-prepping"
        case let .provisioningDevTools(fraction):
            return "provisioning-dev-tools \(Int((fraction * 100).rounded()))%"
        case let .ready(sshDestination):
            return "ready \(sshDestination)"
        case let .error(detail):
            return "error: \(detail)"
        }
    }

    func preflightSummary(phase: String) -> String {
        [
            "\(phase) execution environment: selected \(selectedPreference.title)",
            "VM readiness \(vmReadinessLabel)",
            "effective route \(effectiveRouteTitle)",
            "image \(imageLabel)",
            "workspace \(workspaceLabel)",
            "fallback \(fallbackReasonLabel)"
        ].joined(separator: "; ")
    }

    func routeDetail() -> String {
        switch effectiveRoute {
        case .host:
            if let fallbackReason {
                return "Using native macOS execution because \(fallbackReason) VM readiness: \(vmReadinessLabel)."
            }
            return "Using native macOS execution."
        case let .sharedVM(route):
            return "Using Shared VM at \(Self.boundedText(route.sshDestination, limit: Self.labelLimit)) with workspace \(Self.boundedText(route.guestWorkspacePath, limit: Self.labelLimit))."
        }
    }

    /// Build a one-shot shell invocation. Used by `ProcessRunner.runShell` for
    /// out-of-agent commands like mutation testing and Verify steps.
    ///
    /// Always returns a host-side `/bin/zsh -lc` invocation, even when the
    /// effective route is `.sharedVM`. The sharedVM-via-SSH branch this
    /// used to offer never worked end-to-end (sshd-spawned processes on
    /// macOS guests are TCC-blocked from reading any AppleVirtIOFS mount),
    /// and the agent-loop transport that does work — vsock — is
    /// connection-oriented, not a process the caller can spawn. The agent
    /// works on a vsock-synced copy of the worktree inside the guest;
    /// `AppModel.pullDevelopWorktreeIfNeeded` pulls those changes back
    /// onto the host worktree at the end of each attempt, so Verify and
    /// mutation testing read the same bytes the agent produced.
    func shellInvocation(command: String, hostWorkingDirectory: URL) -> AgentExecutionInvocation {
        AgentExecutionInvocation(
            executable: "/bin/zsh",
            arguments: ["-lc", command],
            workingDirectory: hostWorkingDirectory
        )
    }

    static func boundedText(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let normalized = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func boundedOptionalText(_ text: String?, limit: Int) -> String? {
        let bounded = boundedText(text ?? "", limit: limit)
        return bounded.isEmpty ? nil : bounded
    }
}
