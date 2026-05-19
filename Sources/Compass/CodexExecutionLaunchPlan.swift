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

struct CodexDevcontainerImageConfiguration: Equatable {
    static let imageLabelLimit = 80
    static let workspaceLabelLimit = 80

    var configURL: URL
    var image: String
    var workspaceFolder: String

    init(configURL: URL, image: String, workspaceFolder: String) {
        self.configURL = configURL.standardizedFileURL
        self.image = image
        self.workspaceFolder = workspaceFolder
    }

    var imageLabel: String {
        Self.boundedText(image, limit: Self.imageLabelLimit)
    }

    var workspaceLabel: String {
        Self.boundedText(workspaceFolder, limit: Self.workspaceLabelLimit)
    }

    private static func boundedText(_ text: String, limit: Int) -> String {
        CodexExecutionLaunchPlan.boundedText(text, limit: limit)
    }
}

struct CodexExecutionLaunchPlan: Equatable {
    static let fallbackReasonLimit = 180
    static let labelLimit = 80

    struct AppleContainerRoute: Equatable {
        var toolPath: String
        var hostWorkspaceURL: URL
        var image: String
        var workspaceFolder: String

        init(toolPath: String, hostWorkspaceURL: URL, image: String, workspaceFolder: String) {
            self.toolPath = toolPath
            self.hostWorkspaceURL = hostWorkspaceURL.standardizedFileURL
            self.image = image
            self.workspaceFolder = workspaceFolder
        }

        var volumeArgument: String {
            "\(hostWorkspaceURL.path):/workspace"
        }

        func containerPath(for hostURL: URL) -> String? {
            let root = hostWorkspaceURL.standardizedFileURL
            let target = hostURL.standardizedFileURL
            let rootPath = root.path
            let targetPath = target.path

            if targetPath == rootPath {
                return "/workspace"
            }

            let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
            guard targetPath.hasPrefix(rootPrefix) else {
                return nil
            }

            let relativePath = String(targetPath.dropFirst(rootPrefix.count))
            guard !relativePath.isEmpty else { return "/workspace" }
            return "/workspace/\(relativePath)"
        }
    }

    enum Route: Equatable {
        case nativeMacOS
        case appleContainer(AppleContainerRoute)
    }

    enum ParseOutcome: Equatable {
        case missing(configURL: URL)
        case malformed(configURL: URL, reason: String)
        case unsupported(configURL: URL, reason: String)
        case ready(CodexDevcontainerImageConfiguration)
    }

    var selectedPreference: CodexExecutionEnvironmentPreference
    var effectiveRoute: Route
    var devcontainer: CodexDevcontainerImageConfiguration?
    var fallbackReason: String?

    init(
        selectedPreference: CodexExecutionEnvironmentPreference,
        effectiveRoute: Route,
        devcontainer: CodexDevcontainerImageConfiguration? = nil,
        fallbackReason: String? = nil
    ) {
        self.selectedPreference = selectedPreference
        self.effectiveRoute = effectiveRoute
        self.devcontainer = devcontainer
        self.fallbackReason = Self.boundedOptionalText(fallbackReason, limit: Self.fallbackReasonLimit)
    }

    static func native(
        selectedPreference: CodexExecutionEnvironmentPreference = .nativeMacOS,
        devcontainer: CodexDevcontainerImageConfiguration? = nil,
        fallbackReason: String? = nil
    ) -> Self {
        Self(
            selectedPreference: selectedPreference,
            effectiveRoute: .nativeMacOS,
            devcontainer: devcontainer,
            fallbackReason: fallbackReason
        )
    }

    static func plan(
        repoURL: URL,
        preference: CodexExecutionEnvironmentPreference,
        fileManager: FileManager = .default,
        containerToolResolver: (String) -> String? = defaultContainerToolResolver
    ) -> Self {
        let standardizedRepoURL = repoURL.standardizedFileURL
        let parseOutcome = parseDevcontainerImageConfig(
            repoURL: standardizedRepoURL,
            fileManager: fileManager
        )

        switch preference {
        case .nativeMacOS:
            let config: CodexDevcontainerImageConfiguration?
            if case let .ready(readyConfig) = parseOutcome {
                config = readyConfig
            } else {
                config = nil
            }
            return native(selectedPreference: preference, devcontainer: config)
        case .devcontainerPreferred:
            switch parseOutcome {
            case .missing:
                return native(
                    selectedPreference: preference,
                    fallbackReason: "No .devcontainer/devcontainer.json was found."
                )
            case let .malformed(_, reason):
                return native(
                    selectedPreference: preference,
                    fallbackReason: "The devcontainer config is malformed: \(reason)"
                )
            case let .unsupported(_, reason):
                return native(
                    selectedPreference: preference,
                    fallbackReason: reason
                )
            case let .ready(config):
                guard let containerToolPath = containerToolResolver("container")?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                    !containerToolPath.isEmpty
                else {
                    return native(
                        selectedPreference: preference,
                        devcontainer: config,
                        fallbackReason: "Apple container CLI is unavailable."
                    )
                }

                return Self(
                    selectedPreference: preference,
                    effectiveRoute: .appleContainer(AppleContainerRoute(
                        toolPath: containerToolPath,
                        hostWorkspaceURL: standardizedRepoURL,
                        image: config.image,
                        workspaceFolder: config.workspaceFolder
                    )),
                    devcontainer: config
                )
            }
        }
    }

    static func parseDevcontainerImageConfig(
        repoURL: URL,
        fileManager: FileManager = .default
    ) -> ParseOutcome {
        let configURL = repoURL.standardizedFileURL
            .appending(path: ".devcontainer", directoryHint: .isDirectory)
            .appending(path: "devcontainer.json")

        guard fileManager.fileExists(atPath: configURL.path) else {
            return .missing(configURL: configURL)
        }

        let data: Data
        do {
            data = try Data(contentsOf: configURL)
        } catch {
            return .malformed(
                configURL: configURL,
                reason: boundedText(error.localizedDescription, limit: fallbackReasonLimit)
            )
        }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            return .malformed(
                configURL: configURL,
                reason: boundedText(error.localizedDescription, limit: fallbackReasonLimit)
            )
        }

        guard let dictionary = object as? [String: Any] else {
            return .malformed(configURL: configURL, reason: "Expected a JSON object.")
        }

        if dictionary["dockerComposeFile"] != nil || dictionary["composeFile"] != nil {
            return .unsupported(
                configURL: configURL,
                reason: "Docker Compose devcontainer configs are not supported by Apple container routing."
            )
        }

        if dictionary["build"] != nil || dictionary["dockerFile"] != nil || dictionary["dockerfile"] != nil {
            return .unsupported(
                configURL: configURL,
                reason: "Build-based devcontainer configs are not supported by Apple container routing."
            )
        }

        let supportedKeys: Set<String> = ["image", "workspaceFolder", "name"]
        let unsupportedKeys = Set(dictionary.keys).subtracting(supportedKeys)
        if let firstUnsupportedKey = unsupportedKeys.sorted().first {
            return .unsupported(
                configURL: configURL,
                reason: "Only image and workspaceFolder devcontainer fields are supported; found \(firstUnsupportedKey)."
            )
        }

        guard let rawImage = dictionary["image"] else {
            return .unsupported(
                configURL: configURL,
                reason: "Only image-based devcontainer configs are supported."
            )
        }

        guard let image = rawImage as? String else {
            return .malformed(configURL: configURL, reason: "The devcontainer image must be a string.")
        }

        let trimmedImage = image.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedImage.isEmpty else {
            return .malformed(configURL: configURL, reason: "The devcontainer image must not be empty.")
        }

        let workspaceFolder: String
        if let rawWorkspaceFolder = dictionary["workspaceFolder"] {
            guard let rawWorkspaceFolder = rawWorkspaceFolder as? String else {
                return .malformed(configURL: configURL, reason: "workspaceFolder must be a string.")
            }

            let trimmedWorkspaceFolder = rawWorkspaceFolder.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedWorkspaceFolder.isEmpty else {
                return .malformed(configURL: configURL, reason: "workspaceFolder must not be empty.")
            }

            guard isSafelyMountedWorkspaceFolder(trimmedWorkspaceFolder) else {
                return .unsupported(
                    configURL: configURL,
                    reason: "workspaceFolder must be an absolute /workspace path for Apple container routing."
                )
            }

            workspaceFolder = trimmedWorkspaceFolder
        } else {
            workspaceFolder = "/workspace"
        }

        return .ready(CodexDevcontainerImageConfiguration(
            configURL: configURL,
            image: trimmedImage,
            workspaceFolder: workspaceFolder
        ))
    }

    var isContainerRoute: Bool {
        if case .appleContainer = effectiveRoute { return true }
        return false
    }

    var effectiveRouteTitle: String {
        switch effectiveRoute {
        case .nativeMacOS:
            return "Native macOS"
        case .appleContainer:
            return "Apple container"
        }
    }

    var effectiveRouteIdentifier: String {
        switch effectiveRoute {
        case .nativeMacOS:
            return "native-macos"
        case .appleContainer:
            return "apple-container"
        }
    }

    var imageLabel: String {
        switch effectiveRoute {
        case .nativeMacOS:
            return devcontainer?.imageLabel ?? "none"
        case let .appleContainer(route):
            return Self.boundedText(route.image, limit: Self.labelLimit)
        }
    }

    var workspaceLabel: String {
        switch effectiveRoute {
        case .nativeMacOS:
            return "host"
        case let .appleContainer(route):
            return Self.boundedText(route.workspaceFolder, limit: Self.labelLimit)
        }
    }

    var fallbackReasonLabel: String {
        fallbackReason ?? "none"
    }

    func preflightSummary(phase: String) -> String {
        [
            "\(phase) execution environment: selected \(selectedPreference.title)",
            "effective route \(effectiveRouteTitle)",
            "image \(imageLabel)",
            "workspace \(workspaceLabel)",
            "fallback \(fallbackReasonLabel)"
        ].joined(separator: "; ")
    }

    func routeDetail() -> String {
        switch effectiveRoute {
        case .nativeMacOS:
            if let fallbackReason {
                return "Using native macOS execution because \(fallbackReason)"
            }
            return "Using native macOS execution."
        case let .appleContainer(route):
            return "Using Apple container image \(Self.boundedText(route.image, limit: Self.labelLimit)) at workspace \(Self.boundedText(route.workspaceFolder, limit: Self.labelLimit))."
        }
    }

    func commandPath(forHostURL url: URL) -> String {
        switch effectiveRoute {
        case .nativeMacOS:
            return url.standardizedFileURL.path
        case let .appleContainer(route):
            return route.containerPath(for: url) ?? url.standardizedFileURL.path
        }
    }

    func codexWorkingDirectoryPath(forHostURL url: URL) -> String {
        switch effectiveRoute {
        case .nativeMacOS:
            return url.standardizedFileURL.path
        case let .appleContainer(route):
            return route.workspaceFolder
        }
    }

    func codexInvocation(codexBinary: String, arguments: [String], hostWorkingDirectory: URL) -> CodexExecutionInvocation {
        switch effectiveRoute {
        case .nativeMacOS:
            return Self.commandInvocation(
                command: codexBinary,
                arguments: arguments,
                workingDirectory: hostWorkingDirectory
            )
        case let .appleContainer(route):
            return Self.commandInvocation(
                command: route.toolPath,
                arguments: [
                    "run",
                    "--rm",
                    "--volume", route.volumeArgument,
                    "--workdir", route.workspaceFolder,
                    route.image,
                    "codex"
                ] + arguments,
                workingDirectory: hostWorkingDirectory
            )
        }
    }

    func shellInvocation(command: String, hostWorkingDirectory: URL) -> CodexExecutionInvocation {
        switch effectiveRoute {
        case .nativeMacOS:
            return CodexExecutionInvocation(
                executable: "/bin/zsh",
                arguments: ["-lc", command],
                workingDirectory: hostWorkingDirectory
            )
        case let .appleContainer(route):
            return Self.commandInvocation(
                command: route.toolPath,
                arguments: [
                    "run",
                    "--rm",
                    "--volume", route.volumeArgument,
                    "--workdir", route.workspaceFolder,
                    route.image,
                    "sh",
                    "-lc",
                    command
                ],
                workingDirectory: hostWorkingDirectory
            )
        }
    }

    static func defaultContainerToolResolver(_ toolName: String) -> String? {
        guard toolName == "container" else { return nil }

        let environmentPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let pathCandidates = environmentPath
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }
        let defaultDirectories = [
            "/Applications/Container.app/Contents/MacOS",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin"
        ]

        for directory in pathCandidates + defaultDirectories {
            let candidate = URL(fileURLWithPath: directory)
                .appendingPathComponent(toolName)
                .standardizedFileURL
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate.path
            }
        }

        return nil
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

    private static func isSafelyMountedWorkspaceFolder(_ workspaceFolder: String) -> Bool {
        guard workspaceFolder == "/workspace" || workspaceFolder.hasPrefix("/workspace/") else {
            return false
        }

        guard !workspaceFolder.contains("\0"),
              !workspaceFolder.contains("\n"),
              !workspaceFolder.contains("\r"),
              !workspaceFolder.contains("$") else {
            return false
        }

        return !workspaceFolder
            .split(separator: "/")
            .contains("..")
    }
}
