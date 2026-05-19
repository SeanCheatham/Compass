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

struct CodexDevcontainerSupportReport: Equatable {
    static let nameLimit = 80
    static let reasonLimit = 180
    static let supportSummaryLimit = 180
    static let tokenLimit = 48
    static let maxTokenCount = 8

    enum Classification: String, Equatable {
        case missing
        case malformed
        case imageRouteable = "image-routeable"
        case buildBased = "build-based"
        case composeBased = "compose-based"
        case featureBased = "feature-based"
        case unsupportedExtraFields = "unsupported-extra-fields"
    }

    var classification: Classification
    var configURL: URL
    var name: String?
    var imageConfiguration: CodexDevcontainerImageConfiguration?
    var supportTokens: [String]
    var omittedTokenCount: Int
    var reason: String?

    init(
        classification: Classification,
        configURL: URL,
        name: String? = nil,
        imageConfiguration: CodexDevcontainerImageConfiguration? = nil,
        supportTokens: [String] = [],
        omittedTokenCount: Int = 0,
        reason: String? = nil
    ) {
        self.classification = classification
        self.configURL = configURL.standardizedFileURL
        self.name = Self.boundedOptionalText(name, limit: Self.nameLimit)
        self.imageConfiguration = imageConfiguration
        self.supportTokens = supportTokens.map { Self.boundedText($0, limit: Self.tokenLimit) }
        self.omittedTokenCount = max(0, omittedTokenCount)
        self.reason = Self.boundedOptionalText(reason, limit: Self.reasonLimit)
    }

    var isImageRouteable: Bool {
        classification == .imageRouteable && imageConfiguration != nil
    }

    var tokenSummary: String {
        var tokens = supportTokens
        if omittedTokenCount > 0 {
            tokens.append("+\(omittedTokenCount)-more")
        }
        let summary = tokens.isEmpty ? "none" : tokens.joined(separator: ",")
        return Self.boundedText(summary, limit: Self.supportSummaryLimit)
    }

    var supportSummary: String {
        let text: String
        switch classification {
        case .missing:
            text = "missing"
        case .malformed:
            if let reason {
                text = "malformed reason \(reason)"
            } else {
                text = "malformed"
            }
        case .imageRouteable:
            if let imageConfiguration {
                text = "image-routeable image \(imageConfiguration.imageLabel) workspace \(imageConfiguration.workspaceLabel)"
            } else {
                text = "image-routeable"
            }
        case .buildBased, .composeBased, .featureBased, .unsupportedExtraFields:
            text = "\(classification.rawValue) tokens \(tokenSummary)"
        }
        return Self.boundedText(text, limit: Self.supportSummaryLimit)
    }

    var unsupportedRouteReason: String? {
        switch classification {
        case .missing:
            return "No .devcontainer/devcontainer.json was found."
        case .malformed:
            let detail = reason ?? "Unreadable devcontainer config."
            return Self.boundedText(
                "The devcontainer config is malformed: \(detail)",
                limit: CodexExecutionLaunchPlan.fallbackReasonLimit
            )
        case .imageRouteable:
            return nil
        case .composeBased, .buildBased, .featureBased:
            return Self.boundedText(
                "Unsupported devcontainer route: \(classification.rawValue) tokens \(tokenSummary).",
                limit: CodexExecutionLaunchPlan.fallbackReasonLimit
            )
        case .unsupportedExtraFields:
            if let reason {
                return Self.boundedText(
                    "\(reason) Tokens: \(tokenSummary).",
                    limit: CodexExecutionLaunchPlan.fallbackReasonLimit
                )
            }
            return Self.boundedText(
                "Unsupported devcontainer route: \(classification.rawValue) tokens \(tokenSummary).",
                limit: CodexExecutionLaunchPlan.fallbackReasonLimit
            )
        }
    }

    var parseOutcome: CodexExecutionLaunchPlan.ParseOutcome {
        switch classification {
        case .missing:
            return .missing(configURL: configURL)
        case .malformed:
            return .malformed(
                configURL: configURL,
                reason: reason ?? "Unreadable devcontainer config."
            )
        case .imageRouteable:
            if let imageConfiguration {
                return .ready(imageConfiguration)
            }
            return .unsupported(
                configURL: configURL,
                reason: unsupportedRouteReason ?? "Only image-based devcontainer configs are supported."
            )
        case .buildBased, .composeBased, .featureBased, .unsupportedExtraFields:
            return .unsupported(
                configURL: configURL,
                reason: unsupportedRouteReason ?? "Unsupported devcontainer route: \(classification.rawValue)."
            )
        }
    }

    static func inspect(
        repoURL: URL,
        fileManager: FileManager = .default
    ) -> Self {
        let configURL = repoURL.standardizedFileURL
            .appending(path: ".devcontainer", directoryHint: .isDirectory)
            .appending(path: "devcontainer.json")

        guard fileManager.fileExists(atPath: configURL.path) else {
            return Self(
                classification: .missing,
                configURL: configURL,
                reason: "No .devcontainer/devcontainer.json was found."
            )
        }

        let data: Data
        do {
            data = try Data(contentsOf: configURL)
        } catch {
            return Self(
                classification: .malformed,
                configURL: configURL,
                reason: error.localizedDescription
            )
        }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            return Self(
                classification: .malformed,
                configURL: configURL,
                reason: error.localizedDescription
            )
        }

        guard let dictionary = object as? [String: Any] else {
            return Self(
                classification: .malformed,
                configURL: configURL,
                reason: "Expected a JSON object."
            )
        }

        return inspectDictionary(dictionary, configURL: configURL)
    }

    private static func inspectDictionary(
        _ dictionary: [String: Any],
        configURL: URL
    ) -> Self {
        let name = (dictionary["name"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let composeKeys = presentKeys(["composeFile", "dockerComposeFile"], in: dictionary)
        let buildKeys = presentKeys(["build", "dockerFile", "dockerfile"], in: dictionary)
        let featureKeys = presentKeys(["features"], in: dictionary)
        let routeableKeys: Set<String> = ["image", "workspaceFolder", "name"]
        let classifiedKeys = Set(composeKeys + buildKeys + featureKeys)
        let unsupportedKeys = Set(dictionary.keys)
            .subtracting(routeableKeys)
            .subtracting(classifiedKeys)
            .sorted()
        let supportTokenResult = supportTokens(
            hasCompose: !composeKeys.isEmpty,
            hasBuild: !buildKeys.isEmpty,
            hasFeatures: !featureKeys.isEmpty,
            unsupportedKeys: unsupportedKeys
        )

        if !composeKeys.isEmpty {
            return Self(
                classification: .composeBased,
                configURL: configURL,
                name: name,
                supportTokens: supportTokenResult.tokens,
                omittedTokenCount: supportTokenResult.omittedCount,
                reason: "Compose devcontainer fields require unsupported routing."
            )
        }

        if !buildKeys.isEmpty {
            return Self(
                classification: .buildBased,
                configURL: configURL,
                name: name,
                supportTokens: supportTokenResult.tokens,
                omittedTokenCount: supportTokenResult.omittedCount,
                reason: "Build devcontainer fields require unsupported routing."
            )
        }

        if !featureKeys.isEmpty {
            return Self(
                classification: .featureBased,
                configURL: configURL,
                name: name,
                supportTokens: supportTokenResult.tokens,
                omittedTokenCount: supportTokenResult.omittedCount,
                reason: "Devcontainer features require unsupported routing."
            )
        }

        if !unsupportedKeys.isEmpty {
            return Self(
                classification: .unsupportedExtraFields,
                configURL: configURL,
                name: name,
                supportTokens: supportTokenResult.tokens,
                omittedTokenCount: supportTokenResult.omittedCount,
                reason: "Only image, workspaceFolder, and name are routeable."
            )
        }

        guard let rawImage = dictionary["image"] else {
            let tokens = boundedTokenList(["missing-image"])
            return Self(
                classification: .unsupportedExtraFields,
                configURL: configURL,
                name: name,
                supportTokens: tokens.tokens,
                omittedTokenCount: tokens.omittedCount,
                reason: "Only image-based devcontainer configs are supported."
            )
        }

        guard let image = rawImage as? String else {
            return Self(
                classification: .malformed,
                configURL: configURL,
                name: name,
                reason: "The devcontainer image must be a string."
            )
        }

        let trimmedImage = image.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedImage.isEmpty else {
            return Self(
                classification: .malformed,
                configURL: configURL,
                name: name,
                reason: "The devcontainer image must not be empty."
            )
        }

        let workspaceFolder: String
        if let rawWorkspaceFolder = dictionary["workspaceFolder"] {
            guard let rawWorkspaceFolder = rawWorkspaceFolder as? String else {
                return Self(
                    classification: .malformed,
                    configURL: configURL,
                    name: name,
                    reason: "workspaceFolder must be a string."
                )
            }

            let trimmedWorkspaceFolder = rawWorkspaceFolder.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedWorkspaceFolder.isEmpty else {
                return Self(
                    classification: .malformed,
                    configURL: configURL,
                    name: name,
                    reason: "workspaceFolder must not be empty."
                )
            }

            guard isSafelyMountedWorkspaceFolder(trimmedWorkspaceFolder) else {
                let tokens = boundedTokenList(["workspaceFolder"])
                return Self(
                    classification: .unsupportedExtraFields,
                    configURL: configURL,
                    name: name,
                    supportTokens: tokens.tokens,
                    omittedTokenCount: tokens.omittedCount,
                    reason: "workspaceFolder must be an absolute /workspace path for Apple container routing."
                )
            }

            workspaceFolder = trimmedWorkspaceFolder
        } else {
            workspaceFolder = "/workspace"
        }

        let imageConfiguration = CodexDevcontainerImageConfiguration(
            configURL: configURL,
            image: trimmedImage,
            workspaceFolder: workspaceFolder
        )
        return Self(
            classification: .imageRouteable,
            configURL: configURL,
            name: name,
            imageConfiguration: imageConfiguration,
            supportTokens: ["image"],
            reason: "Image-based devcontainer can be routed through Apple container."
        )
    }

    private static func supportTokens(
        hasCompose: Bool,
        hasBuild: Bool,
        hasFeatures: Bool,
        unsupportedKeys: [String]
    ) -> (tokens: [String], omittedCount: Int) {
        var rawTokens: [String] = []
        if hasCompose {
            rawTokens.append("compose")
        }
        if hasBuild {
            rawTokens.append("build")
        }
        if hasFeatures {
            rawTokens.append("features")
        }
        rawTokens += unsupportedKeys.map { "extra:\($0)" }
        return boundedTokenList(rawTokens)
    }

    private static func boundedTokenList(_ rawTokens: [String]) -> (tokens: [String], omittedCount: Int) {
        let visibleTokens = Array(rawTokens.prefix(Self.maxTokenCount))
            .map { boundedText($0, limit: Self.tokenLimit) }
        return (visibleTokens, max(0, rawTokens.count - visibleTokens.count))
    }

    private static func presentKeys(
        _ keys: [String],
        in dictionary: [String: Any]
    ) -> [String] {
        keys.filter { dictionary[$0] != nil }
    }

    private static func boundedOptionalText(_ text: String?, limit: Int) -> String? {
        let bounded = boundedText(text ?? "", limit: limit)
        return bounded.isEmpty ? nil : bounded
    }

    private static func boundedText(_ text: String, limit: Int) -> String {
        CodexExecutionLaunchPlan.boundedText(text, limit: limit)
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
    var devcontainerSupportReport: CodexDevcontainerSupportReport?
    var fallbackReason: String?

    init(
        selectedPreference: CodexExecutionEnvironmentPreference,
        effectiveRoute: Route,
        devcontainer: CodexDevcontainerImageConfiguration? = nil,
        devcontainerSupportReport: CodexDevcontainerSupportReport? = nil,
        fallbackReason: String? = nil
    ) {
        self.selectedPreference = selectedPreference
        self.effectiveRoute = effectiveRoute
        self.devcontainer = devcontainer
        self.devcontainerSupportReport = devcontainerSupportReport
        self.fallbackReason = Self.boundedOptionalText(fallbackReason, limit: Self.fallbackReasonLimit)
    }

    static func native(
        selectedPreference: CodexExecutionEnvironmentPreference = .nativeMacOS,
        devcontainer: CodexDevcontainerImageConfiguration? = nil,
        devcontainerSupportReport: CodexDevcontainerSupportReport? = nil,
        fallbackReason: String? = nil
    ) -> Self {
        Self(
            selectedPreference: selectedPreference,
            effectiveRoute: .nativeMacOS,
            devcontainer: devcontainer,
            devcontainerSupportReport: devcontainerSupportReport,
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
        let supportReport = CodexDevcontainerSupportReport.inspect(
            repoURL: standardizedRepoURL,
            fileManager: fileManager
        )
        let parseOutcome = supportReport.parseOutcome

        switch preference {
        case .nativeMacOS:
            let config: CodexDevcontainerImageConfiguration?
            if case let .ready(readyConfig) = parseOutcome {
                config = readyConfig
            } else {
                config = nil
            }
            return native(
                selectedPreference: preference,
                devcontainer: config,
                devcontainerSupportReport: supportReport
            )
        case .devcontainerPreferred:
            switch parseOutcome {
            case .missing:
                return native(
                    selectedPreference: preference,
                    devcontainerSupportReport: supportReport,
                    fallbackReason: supportReport.unsupportedRouteReason
                )
            case .malformed:
                return native(
                    selectedPreference: preference,
                    devcontainerSupportReport: supportReport,
                    fallbackReason: supportReport.unsupportedRouteReason
                )
            case .unsupported:
                return native(
                    selectedPreference: preference,
                    devcontainerSupportReport: supportReport,
                    fallbackReason: supportReport.unsupportedRouteReason
                )
            case let .ready(config):
                guard let containerToolPath = containerToolResolver("container")?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                    !containerToolPath.isEmpty
                else {
                    return native(
                        selectedPreference: preference,
                        devcontainer: config,
                        devcontainerSupportReport: supportReport,
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
                    devcontainer: config,
                    devcontainerSupportReport: supportReport
                )
            }
        }
    }

    static func parseDevcontainerImageConfig(
        repoURL: URL,
        fileManager: FileManager = .default
    ) -> ParseOutcome {
        CodexDevcontainerSupportReport.inspect(
            repoURL: repoURL,
            fileManager: fileManager
        ).parseOutcome
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

    var devcontainerSupportLabel: String {
        devcontainerSupportReport?.supportSummary ?? "not-inspected"
    }

    func preflightSummary(phase: String) -> String {
        [
            "\(phase) execution environment: selected \(selectedPreference.title)",
            "devcontainer \(devcontainerSupportLabel)",
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
                return "Using native macOS execution because \(fallbackReason) Devcontainer support: \(devcontainerSupportLabel)."
            }
            return "Using native macOS execution."
        case let .appleContainer(route):
            return "Using Apple container image \(Self.boundedText(route.image, limit: Self.labelLimit)) at workspace \(Self.boundedText(route.workspaceFolder, limit: Self.labelLimit)) because devcontainer support is \(devcontainerSupportLabel)."
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
}
