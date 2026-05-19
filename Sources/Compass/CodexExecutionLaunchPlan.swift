import Foundation

struct CodexExecutionInvocation: Equatable {
    var executable: String
    var arguments: [String]
    var workingDirectory: URL?

    init(executable: String, arguments: [String], workingDirectory: URL? = nil) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory?.standardizedFileURL
    }
}

struct CodexExecutionLaunchPlan: Equatable {
    static let fallbackReasonLimit = 180
    static let labelLimit = 80

    enum Route: Equatable {
        case host
        case sharedVM(SharedVMRoute)
    }

    var selectedPreference: CodexExecutionEnvironmentPreference
    var effectiveRoute: Route
    var vmReadiness: SharedCompassVMReadiness?
    var fallbackReason: String?

    init(
        selectedPreference: CodexExecutionEnvironmentPreference,
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
        selectedPreference: CodexExecutionEnvironmentPreference = .host,
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
        preference: CodexExecutionEnvironmentPreference,
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
            case let .ready(sshDestination):
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
                    fallbackReason: "Shared VM route unavailable for destination \(Self.boundedText(sshDestination, limit: Self.labelLimit))."
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
            case .firstBootPending:
                return host(
                    selectedPreference: preference,
                    vmReadiness: readiness,
                    fallbackReason: "Shared VM is waiting for first-boot setup to complete."
                )
            case .guestPrepping:
                return host(
                    selectedPreference: preference,
                    vmReadiness: readiness,
                    fallbackReason: "Shared VM guest preparation is in progress."
                )
            case .codexLoginPending:
                return host(
                    selectedPreference: preference,
                    vmReadiness: readiness,
                    fallbackReason: "Shared VM is waiting for the user to run codex login inside the guest."
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
        case .firstBootPending:
            return "first-boot-pending"
        case .guestPrepping:
            return "guest-prepping"
        case .codexLoginPending:
            return "codex-login-pending"
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

    func commandPath(forHostURL url: URL) -> String {
        switch effectiveRoute {
        case .host:
            return url.standardizedFileURL.path
        case let .sharedVM(route):
            return route.guestPath(forHostURL: url) ?? url.standardizedFileURL.path
        }
    }

    func codexWorkingDirectoryPath(forHostURL url: URL) -> String {
        switch effectiveRoute {
        case .host:
            return url.standardizedFileURL.path
        case let .sharedVM(route):
            return route.guestWorkspacePath
        }
    }

    func codexInvocation(codexBinary: String, arguments: [String], hostWorkingDirectory: URL) -> CodexExecutionInvocation {
        switch effectiveRoute {
        case .host:
            return Self.commandInvocation(
                command: codexBinary,
                arguments: arguments,
                workingDirectory: hostWorkingDirectory
            )
        case let .sharedVM(route):
            // `arguments` already contains guest paths for any
            // workspace-relative files: `CodexExecutor` invokes
            // `commandPath(forHostURL:)` upstream when building the argv,
            // which maps host worktree URLs to their `/opt/compass/...`
            // guest counterparts via VirtioFS.
            let remoteCommand = SharedCompassVMGuestBridge.buildRemoteCodexCommand(
                guestWorkspacePath: route.guestWorkspacePath,
                guestCodexPath: route.guestCodexPath,
                environmentVariables: route.environmentVariables,
                codexArguments: arguments
            )
            let options = SharedCompassVMGuestBridge.ConnectionOptions(
                identityFile: route.identityFile,
                knownHostsFile: route.knownHostsFile,
                strictHostKeyChecking: true,
                batchMode: true,
                disablePseudoTerminal: true
            )
            let sshArguments = SharedCompassVMGuestBridge.sshArguments(
                destination: route.sshDestination,
                remoteCommand: remoteCommand,
                options: options
            )
            return CodexExecutionInvocation(
                executable: options.executablePath,
                arguments: sshArguments,
                workingDirectory: hostWorkingDirectory
            )
        }
    }

    func shellInvocation(command: String, hostWorkingDirectory: URL) -> CodexExecutionInvocation {
        switch effectiveRoute {
        case .host:
            return CodexExecutionInvocation(
                executable: "/bin/zsh",
                arguments: ["-lc", command],
                workingDirectory: hostWorkingDirectory
            )
        case let .sharedVM(route):
            let remoteCommand = "cd \(SharedCompassVMGuestBridge.posixQuote(route.guestWorkspacePath)) && zsh -lc \(SharedCompassVMGuestBridge.posixQuote(command))"
            let options = SharedCompassVMGuestBridge.ConnectionOptions(
                identityFile: route.identityFile,
                knownHostsFile: route.knownHostsFile,
                strictHostKeyChecking: true,
                batchMode: true,
                disablePseudoTerminal: true
            )
            let sshArguments = SharedCompassVMGuestBridge.sshArguments(
                destination: route.sshDestination,
                remoteCommand: remoteCommand,
                options: options
            )
            return CodexExecutionInvocation(
                executable: options.executablePath,
                arguments: sshArguments,
                workingDirectory: hostWorkingDirectory
            )
        }
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

    private static func commandInvocation(
        command: String,
        arguments: [String],
        workingDirectory: URL
    ) -> CodexExecutionInvocation {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedCommand.contains("/") {
            return CodexExecutionInvocation(
                executable: trimmedCommand,
                arguments: arguments,
                workingDirectory: workingDirectory
            )
        }

        return CodexExecutionInvocation(
            executable: "/usr/bin/env",
            arguments: [trimmedCommand] + arguments,
            workingDirectory: workingDirectory
        )
    }

    private static func boundedOptionalText(_ text: String?, limit: Int) -> String? {
        let bounded = boundedText(text ?? "", limit: limit)
        return bounded.isEmpty ? nil : bounded
    }
}
