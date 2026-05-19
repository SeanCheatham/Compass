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

struct CodexDevcontainerEnvironmentVariable: Equatable {
    static let nameLimit = 128
    static let valueLimit = 4096

    var name: String
    var value: String

    init(name: String, value: String) {
        self.name = String(name.prefix(Self.nameLimit))
        self.value = String(value.prefix(Self.valueLimit))
    }

    var argumentValue: String {
        "\(name)=\(value)"
    }
}

struct CodexDevcontainerBuildDescriptor: Equatable {
    static let labelLimit = 48
    static let buildArgNameLimit = 128
    static let buildArgCountLimit = 32
    static let buildArgValueLimit = 4096
    static let buildArgTotalValueLimit = 16_384

    var dockerfileLabel: String?
    var contextLabel: String?
    var targetLabel: String?
    var hasBuildArgs: Bool
    var buildArgNames: [String]

    init(
        dockerfileLabel: String? = nil,
        contextLabel: String? = nil,
        targetLabel: String? = nil,
        hasBuildArgs: Bool = false,
        buildArgNames: [String] = []
    ) {
        self.dockerfileLabel = Self.boundedOptionalText(dockerfileLabel, limit: Self.labelLimit)
        self.contextLabel = Self.boundedOptionalText(contextLabel, limit: Self.labelLimit)
        self.targetLabel = Self.boundedOptionalText(targetLabel, limit: Self.labelLimit)
        self.hasBuildArgs = hasBuildArgs
        self.buildArgNames = buildArgNames
            .map { Self.boundedText($0, limit: Self.buildArgNameLimit) }
            .filter { !$0.isEmpty }
            .sorted()
    }

    var supportTokens: [String] {
        var tokens: [String] = []
        if let dockerfileLabel {
            tokens.append("dockerfile:\(dockerfileLabel)")
        }
        if let contextLabel {
            tokens.append("context:\(contextLabel)")
        }
        if let targetLabel {
            tokens.append("target:\(targetLabel)")
        }
        if hasBuildArgs {
            tokens.append("buildArgs:\(buildArgNames.count)")
            tokens += buildArgNames.map { "arg:\($0)" }
        }
        return tokens
    }

    private static func boundedOptionalText(_ text: String?, limit: Int) -> String? {
        let bounded = boundedText(text ?? "", limit: limit)
        return bounded.isEmpty ? nil : bounded
    }

    private static func boundedText(_ text: String, limit: Int) -> String {
        CodexExecutionLaunchPlan.boundedText(text, limit: limit)
    }
}

struct CodexDevcontainerBuildArgument: Equatable {
    static let nameLimit = CodexDevcontainerBuildDescriptor.buildArgNameLimit
    static let valueLimit = CodexDevcontainerBuildDescriptor.buildArgValueLimit

    var name: String
    var value: String

    init(name: String, value: String) {
        self.name = String(name.prefix(Self.nameLimit))
        self.value = String(value.prefix(Self.valueLimit))
    }

    var argumentValue: String {
        "\(name)=\(value)"
    }
}

struct CodexDevcontainerBuildConfiguration: Equatable {
    static let localImageName = "compass-devcontainer"

    var configURL: URL
    var repoURL: URL
    var dockerfileURL: URL
    var contextURL: URL
    var target: String?
    var buildArgs: [CodexDevcontainerBuildArgument]
    var containerEnv: [CodexDevcontainerEnvironmentVariable]

    init(
        configURL: URL,
        repoURL: URL,
        dockerfileURL: URL,
        contextURL: URL,
        target: String? = nil,
        buildArgs: [CodexDevcontainerBuildArgument] = [],
        containerEnv: [CodexDevcontainerEnvironmentVariable] = []
    ) {
        self.configURL = configURL.standardizedFileURL
        self.repoURL = repoURL.standardizedFileURL
        self.dockerfileURL = dockerfileURL.standardizedFileURL
        self.contextURL = contextURL.standardizedFileURL
        self.target = Self.boundedOptionalText(
            target,
            limit: CodexDevcontainerBuildDescriptor.labelLimit
        )
        self.buildArgs = buildArgs.sorted { $0.name < $1.name }
        self.containerEnv = containerEnv.sorted { $0.name < $1.name }
    }

    var localImageTag: String {
        let buildArgFingerprint = buildArgs.flatMap {
            [
                "arg-name:\($0.name.utf8.count):\($0.name)",
                "arg-value:\($0.value.utf8.count):\($0.value)"
            ]
        }
        let fingerprint = ([
            repoURL.path,
            relativePath(for: dockerfileURL) ?? dockerfileURL.path,
            relativePath(for: contextURL) ?? contextURL.path,
            target ?? ""
        ] + buildArgFingerprint).joined(separator: "\n")
        return "\(Self.localImageName):\(Self.stableHexDigest(fingerprint))"
    }

    var buildArguments: [String] {
        var arguments = [
            "build",
            "--tag", localImageTag,
            "--file", dockerfileURL.path
        ]
        if let target {
            arguments += ["--target", target]
        }
        for buildArg in buildArgs {
            arguments += ["--build-arg", buildArg.argumentValue]
        }
        arguments.append(contextURL.path)
        return arguments
    }

    func buildInvocation(containerToolPath: String) -> CodexExecutionInvocation {
        let trimmedToolPath = containerToolPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedToolPath.contains("/") {
            return CodexExecutionInvocation(
                executable: trimmedToolPath,
                arguments: buildArguments,
                workingDirectory: repoURL
            )
        }

        return CodexExecutionInvocation(
            executable: "/usr/bin/env",
            arguments: [trimmedToolPath] + buildArguments,
            workingDirectory: repoURL
        )
    }

    private func relativePath(for url: URL) -> String? {
        let rootPath = repoURL.standardizedFileURL.path
        let targetPath = url.standardizedFileURL.path
        if targetPath == rootPath {
            return "."
        }

        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard targetPath.hasPrefix(rootPrefix) else { return nil }
        return String(targetPath.dropFirst(rootPrefix.count))
    }

    private static func stableHexDigest(_ text: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }

    private static func boundedOptionalText(_ text: String?, limit: Int) -> String? {
        let bounded = CodexExecutionLaunchPlan.boundedText(text ?? "", limit: limit)
        return bounded.isEmpty ? nil : bounded
    }
}

struct CodexDevcontainerImageConfiguration: Equatable {
    static let imageLabelLimit = 80
    static let workspaceLabelLimit = 80
    static let containerEnvCountLimit = 32
    static let containerEnvTotalValueLimit = 16_384

    var configURL: URL
    var image: String
    var workspaceFolder: String
    var containerEnv: [CodexDevcontainerEnvironmentVariable]

    init(
        configURL: URL,
        image: String,
        workspaceFolder: String,
        containerEnv: [CodexDevcontainerEnvironmentVariable] = []
    ) {
        self.configURL = configURL.standardizedFileURL
        self.image = image
        self.workspaceFolder = workspaceFolder
        self.containerEnv = containerEnv.sorted { $0.name < $1.name }
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
    var buildDescriptor: CodexDevcontainerBuildDescriptor?
    var buildConfiguration: CodexDevcontainerBuildConfiguration?
    var supportTokens: [String]
    var omittedTokenCount: Int
    var reason: String?

    init(
        classification: Classification,
        configURL: URL,
        name: String? = nil,
        imageConfiguration: CodexDevcontainerImageConfiguration? = nil,
        buildDescriptor: CodexDevcontainerBuildDescriptor? = nil,
        buildConfiguration: CodexDevcontainerBuildConfiguration? = nil,
        supportTokens: [String] = [],
        omittedTokenCount: Int = 0,
        reason: String? = nil
    ) {
        self.classification = classification
        self.configURL = configURL.standardizedFileURL
        self.name = Self.boundedOptionalText(name, limit: Self.nameLimit)
        self.imageConfiguration = imageConfiguration
        self.buildDescriptor = buildDescriptor
        self.buildConfiguration = buildConfiguration
        self.supportTokens = supportTokens.map { Self.boundedText($0, limit: Self.tokenLimit) }
        self.omittedTokenCount = max(0, omittedTokenCount)
        self.reason = Self.boundedOptionalText(reason, limit: Self.reasonLimit)
    }

    var isImageRouteable: Bool {
        classification == .imageRouteable && imageConfiguration != nil
    }

    var isBuildRouteable: Bool {
        classification == .buildBased && buildConfiguration != nil
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
                let base = "image-routeable image \(imageConfiguration.imageLabel) workspace \(imageConfiguration.workspaceLabel)"
                if imageConfiguration.containerEnv.isEmpty {
                    text = base
                } else {
                    text = "\(base) tokens \(tokenSummary)"
                }
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
        case .buildBased where buildConfiguration != nil:
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
                reason: unsupportedRouteReason ?? "\(classification.rawValue) devcontainer can be routed through Apple container."
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
        let routeableKeys: Set<String> = ["image", "workspaceFolder", "name", "containerEnv"]
        let classifiedKeys = Set(composeKeys + buildKeys + featureKeys)
        let unsupportedKeys = Set(dictionary.keys)
            .subtracting(routeableKeys)
            .subtracting(classifiedKeys)
            .sorted()

        let containerEnv: [CodexDevcontainerEnvironmentVariable]
        switch parseContainerEnv(dictionary["containerEnv"]) {
        case let .success(parsedContainerEnv):
            containerEnv = parsedContainerEnv
        case let .failure(reason):
            return Self(
                classification: .malformed,
                configURL: configURL,
                name: name,
                reason: reason
            )
        }

        let parsedBuildPlan: ParsedBuildPlan?
        let hasMalformedBuildDescriptor: Bool
        switch parseBuildPlan(dictionary, configURL: configURL, containerEnv: containerEnv) {
        case let .success(buildPlan):
            parsedBuildPlan = buildPlan
            hasMalformedBuildDescriptor = false
        case let .failure(reason):
            if composeKeys.isEmpty {
                return Self(
                    classification: .malformed,
                    configURL: configURL,
                    name: name,
                    reason: reason
                )
            }
            parsedBuildPlan = nil
            hasMalformedBuildDescriptor = true
        }
        let buildDescriptor = parsedBuildPlan?.descriptor
        let buildConfiguration: CodexDevcontainerBuildConfiguration?
        if composeKeys.isEmpty,
           featureKeys.isEmpty,
           unsupportedKeys.isEmpty {
            buildConfiguration = parsedBuildPlan?.configuration
        } else {
            buildConfiguration = nil
        }

        let supportTokenResult = supportTokens(
            hasCompose: !composeKeys.isEmpty,
            hasBuild: !buildKeys.isEmpty,
            buildDescriptor: buildDescriptor,
            buildExtraSupportTokens: parsedBuildPlan?.extraSupportTokens ?? [],
            hasMalformedBuildDescriptor: hasMalformedBuildDescriptor,
            hasFeatures: !featureKeys.isEmpty,
            unsupportedKeys: unsupportedKeys,
            containerEnvNames: containerEnv.map(\.name)
        )

        if !composeKeys.isEmpty {
            return Self(
                classification: .composeBased,
                configURL: configURL,
                name: name,
                buildDescriptor: buildDescriptor,
                buildConfiguration: buildConfiguration,
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
                buildDescriptor: buildDescriptor,
                buildConfiguration: buildConfiguration,
                supportTokens: supportTokenResult.tokens,
                omittedTokenCount: supportTokenResult.omittedCount,
                reason: buildConfiguration == nil
                    ? "Build devcontainer fields require unsupported routing."
                    : "Build-based devcontainer can be routed through Apple container."
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
                reason: "Only image, workspaceFolder, name, and containerEnv are routeable."
            )
        }

        guard let rawImage = dictionary["image"] else {
            let tokens = boundedTokenList(["missing-image"] + containerEnvSupportTokens(names: containerEnv.map(\.name)))
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
            workspaceFolder: workspaceFolder,
            containerEnv: containerEnv
        )
        let routeableTokens = boundedTokenList(["image"] + containerEnvSupportTokens(names: containerEnv.map(\.name)))
        return Self(
            classification: .imageRouteable,
            configURL: configURL,
            name: name,
            imageConfiguration: imageConfiguration,
            supportTokens: routeableTokens.tokens,
            omittedTokenCount: routeableTokens.omittedCount,
            reason: "Image-based devcontainer can be routed through Apple container."
        )
    }

    private enum ContainerEnvParseResult {
        case success([CodexDevcontainerEnvironmentVariable])
        case failure(String)
    }

    private struct ParsedBuildPlan {
        var descriptor: CodexDevcontainerBuildDescriptor
        var configuration: CodexDevcontainerBuildConfiguration?
        var extraSupportTokens: [String]
    }

    private enum BuildPlanParseResult {
        case success(ParsedBuildPlan?)
        case failure(String)
    }

    private enum BuildLabelParseResult {
        case success(String)
        case failure(String)
    }

    private enum BuildPathParseResult {
        case success(url: URL, label: String)
        case unsupported(label: String)
        case failure(String)
    }

    private enum BuildPathKind {
        case dockerfile
        case context
    }

    private enum BuildArgsParseResult {
        case success(arguments: [CodexDevcontainerBuildArgument], totalValueLength: Int)
        case failure(String)
    }

    private static func parseContainerEnv(_ rawValue: Any?) -> ContainerEnvParseResult {
        guard let rawValue else {
            return .success([])
        }

        guard let dictionary = rawValue as? [String: Any] else {
            return .failure("containerEnv must be an object with string values.")
        }

        guard dictionary.count <= CodexDevcontainerImageConfiguration.containerEnvCountLimit else {
            return .failure(
                "containerEnv may include at most \(CodexDevcontainerImageConfiguration.containerEnvCountLimit) variables."
            )
        }

        var variables: [CodexDevcontainerEnvironmentVariable] = []
        var totalValueLength = 0
        for name in dictionary.keys.sorted() {
            guard isSafeContainerEnvName(name) else {
                return .failure("containerEnv contains an unsafe variable name.")
            }

            guard let value = dictionary[name] as? String else {
                return .failure("containerEnv values must be strings.")
            }

            guard !value.contains("\0") else {
                return .failure("containerEnv values must not contain NUL characters.")
            }

            guard value.count <= CodexDevcontainerEnvironmentVariable.valueLimit else {
                return .failure(
                    "containerEnv value exceeds \(CodexDevcontainerEnvironmentVariable.valueLimit) characters."
                )
            }

            totalValueLength += value.count
            guard totalValueLength <= CodexDevcontainerImageConfiguration.containerEnvTotalValueLimit else {
                return .failure(
                    "containerEnv values exceed \(CodexDevcontainerImageConfiguration.containerEnvTotalValueLimit) total characters."
                )
            }

            variables.append(CodexDevcontainerEnvironmentVariable(name: name, value: value))
        }

        return .success(variables)
    }

    private static func parseBuildPlan(
        _ dictionary: [String: Any],
        configURL: URL,
        containerEnv: [CodexDevcontainerEnvironmentVariable]
    ) -> BuildPlanParseResult {
        let buildKeys = presentKeys(["build", "dockerFile", "dockerfile"], in: dictionary)
        guard !buildKeys.isEmpty else {
            return .success(nil)
        }

        let standardizedConfigURL = configURL.standardizedFileURL
        let configDirectoryURL = standardizedConfigURL
            .deletingLastPathComponent()
            .standardizedFileURL
        let repoURL = configDirectoryURL
            .deletingLastPathComponent()
            .standardizedFileURL

        var dockerfileLabel: String?
        var dockerfileURL: URL?
        var contextLabel: String?
        var contextURL: URL?
        var targetLabel: String?
        var target: String?
        var hasBuildArgs = false
        var buildArgs: [CodexDevcontainerBuildArgument] = []
        var buildArgTotalValueLength = 0
        var hasUnsupportedBuildComponent = false
        var extraSupportTokens: [String] = []

        for key in ["dockerFile", "dockerfile"] where dictionary[key] != nil {
            switch parseBuildPath(
                dictionary[key],
                fieldName: key,
                configDirectoryURL: configDirectoryURL,
                repoURL: repoURL,
                kind: .dockerfile
            ) {
            case let .success(url, label):
                if dockerfileLabel == nil {
                    dockerfileLabel = label
                    dockerfileURL = url
                }
            case let .unsupported(label):
                if dockerfileLabel == nil {
                    dockerfileLabel = label
                }
                hasUnsupportedBuildComponent = true
            case let .failure(reason):
                return .failure(reason)
            }
        }

        if let rawBuild = dictionary["build"] {
            if let stringBuild = rawBuild as? String {
                switch parseBuildPath(
                    stringBuild,
                    fieldName: "build",
                    configDirectoryURL: configDirectoryURL,
                    repoURL: repoURL,
                    kind: .dockerfile
                ) {
                case let .success(url, label):
                    if dockerfileLabel == nil {
                        dockerfileLabel = label
                        dockerfileURL = url
                    }
                case let .unsupported(label):
                    if dockerfileLabel == nil {
                        dockerfileLabel = label
                    }
                    hasUnsupportedBuildComponent = true
                case let .failure(reason):
                    return .failure(reason)
                }
            } else if let buildObject = rawBuild as? [String: Any] {
                let supportedBuildObjectKeys: Set<String> = [
                    "dockerfile",
                    "dockerFile",
                    "context",
                    "target",
                    "args",
                    "buildArgs"
                ]
                let unsupportedBuildObjectKeys = Set(buildObject.keys)
                    .subtracting(supportedBuildObjectKeys)
                    .sorted()
                if !unsupportedBuildObjectKeys.isEmpty {
                    extraSupportTokens += unsupportedBuildObjectKeys.map { "extra:build.\($0)" }
                    hasUnsupportedBuildComponent = true
                }

                for key in ["dockerfile", "dockerFile"] where buildObject[key] != nil {
                    switch parseBuildPath(
                        buildObject[key],
                        fieldName: "build.\(key)",
                        configDirectoryURL: configDirectoryURL,
                        repoURL: repoURL,
                        kind: .dockerfile
                    ) {
                    case let .success(url, label):
                        if dockerfileLabel == nil {
                            dockerfileLabel = label
                            dockerfileURL = url
                        }
                    case let .unsupported(label):
                        if dockerfileLabel == nil {
                            dockerfileLabel = label
                        }
                        hasUnsupportedBuildComponent = true
                    case let .failure(reason):
                        return .failure(reason)
                    }
                }

                if buildObject["context"] != nil {
                    switch parseBuildPath(
                        buildObject["context"],
                        fieldName: "build.context",
                        configDirectoryURL: configDirectoryURL,
                        repoURL: repoURL,
                        kind: .context
                    ) {
                    case let .success(url, label):
                        contextLabel = label
                        contextURL = url
                    case let .unsupported(label):
                        contextLabel = label
                        hasUnsupportedBuildComponent = true
                    case let .failure(reason):
                        return .failure(reason)
                    }
                }

                if buildObject["target"] != nil {
                    switch parseBuildNameLabel(buildObject["target"], fieldName: "build.target") {
                    case let .success(label):
                        targetLabel = label
                        target = label
                    case let .failure(reason):
                        return .failure(reason)
                    }
                }

                for key in ["args", "buildArgs"] where buildObject[key] != nil {
                    hasBuildArgs = true
                    switch parseBuildArgs(
                        buildObject[key],
                        existingArguments: buildArgs,
                        totalValueLength: buildArgTotalValueLength
                    ) {
                    case let .success(arguments, totalValueLength):
                        buildArgs = arguments
                        buildArgTotalValueLength = totalValueLength
                    case let .failure(reason):
                        return .failure(reason)
                    }
                }
            } else {
                return .failure("build must be a string or object.")
            }
        }

        if dockerfileURL != nil, contextURL == nil {
            contextURL = configDirectoryURL
        }
        if dockerfileURL == nil {
            hasUnsupportedBuildComponent = true
        }

        let descriptor = CodexDevcontainerBuildDescriptor(
            dockerfileLabel: dockerfileLabel,
            contextLabel: contextLabel,
            targetLabel: targetLabel,
            hasBuildArgs: hasBuildArgs,
            buildArgNames: buildArgs.map(\.name)
        )
        let configuration: CodexDevcontainerBuildConfiguration?
        if let dockerfileURL,
           let contextURL,
           !hasUnsupportedBuildComponent {
            configuration = CodexDevcontainerBuildConfiguration(
                configURL: standardizedConfigURL,
                repoURL: repoURL,
                dockerfileURL: dockerfileURL,
                contextURL: contextURL,
                target: target,
                buildArgs: buildArgs,
                containerEnv: containerEnv
            )
        } else {
            configuration = nil
        }

        return .success(ParsedBuildPlan(
            descriptor: descriptor,
            configuration: configuration,
            extraSupportTokens: extraSupportTokens
        ))
    }

    private static func parseBuildPath(
        _ rawValue: Any?,
        fieldName: String,
        configDirectoryURL: URL,
        repoURL: URL,
        kind: BuildPathKind
    ) -> BuildPathParseResult {
        guard let value = rawValue as? String else {
            return .failure("\(fieldName) must be a string.")
        }

        guard !value.contains("\0") else {
            return .failure("\(fieldName) must not contain NUL characters.")
        }

        guard !value.contains("\n"), !value.contains("\r") else {
            return .failure("\(fieldName) must not contain line breaks.")
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure("\(fieldName) must not be empty.")
        }

        let normalized = trimmed.replacingOccurrences(of: "\\", with: "/")
        if normalized.hasPrefix("/") || isWindowsAbsolutePath(normalized) {
            return .unsupported(label: "absolute")
        }

        let resolvedURL = URL(fileURLWithPath: normalized, relativeTo: configDirectoryURL)
            .standardizedFileURL
        guard isURL(resolvedURL, containedIn: repoURL) else {
            return .unsupported(label: "out-of-repo")
        }

        return .success(url: resolvedURL, label: buildPathLabel(
            for: resolvedURL,
            repoURL: repoURL,
            configDirectoryURL: configDirectoryURL,
            kind: kind
        ))
    }

    private static func parseBuildNameLabel(_ rawValue: Any?, fieldName: String) -> BuildLabelParseResult {
        guard let value = rawValue as? String else {
            return .failure("\(fieldName) must be a string.")
        }

        guard !value.contains("\0") else {
            return .failure("\(fieldName) must not contain NUL characters.")
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure("\(fieldName) must not be empty.")
        }

        let bounded = boundedText(trimmed, limit: CodexDevcontainerBuildDescriptor.labelLimit)
        guard isSafeBuildLabel(bounded) else {
            return .failure("\(fieldName) contains unsupported characters.")
        }
        return .success(bounded)
    }

    private static func parseBuildArgs(
        _ rawValue: Any?,
        existingArguments: [CodexDevcontainerBuildArgument],
        totalValueLength: Int
    ) -> BuildArgsParseResult {
        guard let dictionary = rawValue as? [String: Any] else {
            return .failure("build args must be an object with string values.")
        }

        var arguments = existingArguments
        var names = Set(existingArguments.map(\.name))
        var runningValueLength = totalValueLength
        guard arguments.count + dictionary.count <= CodexDevcontainerBuildDescriptor.buildArgCountLimit else {
            return .failure(
                "build args may include at most \(CodexDevcontainerBuildDescriptor.buildArgCountLimit) variables."
            )
        }

        for name in dictionary.keys.sorted() {
            guard !names.contains(name) else {
                return .failure("build args contain duplicate names.")
            }

            guard isSafeBuildArgName(name) else {
                return .failure("build args contain an unsafe name.")
            }

            guard let value = dictionary[name] as? String else {
                return .failure("build args values must be strings.")
            }

            guard !value.contains("\0") else {
                return .failure("build args values must not contain NUL characters.")
            }

            guard value.count <= CodexDevcontainerBuildDescriptor.buildArgValueLimit else {
                return .failure(
                    "build arg value exceeds \(CodexDevcontainerBuildDescriptor.buildArgValueLimit) characters."
                )
            }

            runningValueLength += value.count
            guard runningValueLength <= CodexDevcontainerBuildDescriptor.buildArgTotalValueLimit else {
                return .failure(
                    "build arg values exceed \(CodexDevcontainerBuildDescriptor.buildArgTotalValueLimit) total characters."
                )
            }

            names.insert(name)
            arguments.append(CodexDevcontainerBuildArgument(name: name, value: value))
        }

        return .success(arguments: arguments.sorted { $0.name < $1.name }, totalValueLength: runningValueLength)
    }

    private static func supportTokens(
        hasCompose: Bool,
        hasBuild: Bool,
        buildDescriptor: CodexDevcontainerBuildDescriptor? = nil,
        buildExtraSupportTokens: [String] = [],
        hasMalformedBuildDescriptor: Bool = false,
        hasFeatures: Bool,
        unsupportedKeys: [String],
        containerEnvNames: [String] = []
    ) -> (tokens: [String], omittedCount: Int) {
        var rawTokens: [String] = []
        if hasCompose {
            rawTokens.append("compose")
        }
        if hasBuild {
            rawTokens.append("build")
            if hasMalformedBuildDescriptor {
                rawTokens.append("build:malformed")
            } else {
                rawTokens += buildDescriptor?.supportTokens ?? []
                rawTokens += buildExtraSupportTokens
            }
        }
        if hasFeatures {
            rawTokens.append("features")
        }
        rawTokens += containerEnvSupportTokens(names: containerEnvNames)
        rawTokens += unsupportedKeys.map { "extra:\($0)" }
        return boundedTokenList(rawTokens)
    }

    private static func containerEnvSupportTokens(names: [String]) -> [String] {
        guard !names.isEmpty else { return [] }
        let sortedNames = names.sorted()
        return ["containerEnv:\(sortedNames.count)"] + sortedNames.map { "env:\($0)" }
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

    private static func buildPathLabel(
        for url: URL,
        repoURL: URL,
        configDirectoryURL: URL,
        kind: BuildPathKind
    ) -> String {
        let standardizedURL = url.standardizedFileURL
        if kind == .context {
            if standardizedURL.path == repoURL.standardizedFileURL.path {
                return "repo-root"
            }
            if standardizedURL.path == configDirectoryURL.standardizedFileURL.path {
                return ".devcontainer"
            }
        }

        let last = standardizedURL.lastPathComponent
        let bounded = boundedText(last, limit: CodexDevcontainerBuildDescriptor.labelLimit)
        guard isSafeBuildLabel(bounded) else {
            switch kind {
            case .dockerfile:
                return "dockerfile"
            case .context:
                return "context"
            }
        }
        return bounded
    }

    private static func isURL(_ url: URL, containedIn rootURL: URL) -> Bool {
        let rootPath = rootURL.standardizedFileURL.path
        let targetPath = url.standardizedFileURL.path
        if targetPath == rootPath {
            return true
        }

        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return targetPath.hasPrefix(rootPrefix)
    }

    private static func isWindowsAbsolutePath(_ value: String) -> Bool {
        let scalars = Array(value.unicodeScalars)
        guard scalars.count >= 3 else { return false }
        return isASCIILetter(scalars[0]) && scalars[1] == ":" && scalars[2] == "/"
    }

    private static func isSafeBuildLabel(_ label: String) -> Bool {
        guard !label.isEmpty,
              label.count <= CodexDevcontainerBuildDescriptor.labelLimit else {
            return false
        }

        return label.unicodeScalars.allSatisfy { scalar in
            isASCIILetter(scalar)
                || isASCIIDigit(scalar)
                || scalar == "_"
                || scalar == "-"
                || scalar == "."
        }
    }

    private static func isSafeBuildArgName(_ name: String) -> Bool {
        guard !name.isEmpty,
              name.count <= CodexDevcontainerBuildDescriptor.buildArgNameLimit,
              let first = name.unicodeScalars.first,
              isASCIILetter(first) || first == "_" else {
            return false
        }

        return name.unicodeScalars.allSatisfy { scalar in
            isASCIILetter(scalar) || isASCIIDigit(scalar) || scalar == "_"
        }
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

    private static func isSafeContainerEnvName(_ name: String) -> Bool {
        guard !name.isEmpty,
              name.count <= CodexDevcontainerEnvironmentVariable.nameLimit,
              let first = name.unicodeScalars.first,
              isASCIILetter(first) || first == "_" else {
            return false
        }

        return name.unicodeScalars.allSatisfy { scalar in
            isASCIILetter(scalar) || isASCIIDigit(scalar) || scalar == "_"
        }
    }

    private static func isASCIILetter(_ scalar: UnicodeScalar) -> Bool {
        (65...90).contains(Int(scalar.value)) || (97...122).contains(Int(scalar.value))
    }

    private static func isASCIIDigit(_ scalar: UnicodeScalar) -> Bool {
        (48...57).contains(Int(scalar.value))
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
        var containerEnv: [CodexDevcontainerEnvironmentVariable]
        var buildConfiguration: CodexDevcontainerBuildConfiguration?

        init(
            toolPath: String,
            hostWorkspaceURL: URL,
            image: String,
            workspaceFolder: String,
            containerEnv: [CodexDevcontainerEnvironmentVariable] = [],
            buildConfiguration: CodexDevcontainerBuildConfiguration? = nil
        ) {
            self.toolPath = toolPath
            self.hostWorkspaceURL = hostWorkspaceURL.standardizedFileURL
            self.image = image
            self.workspaceFolder = workspaceFolder
            self.containerEnv = containerEnv.sorted { $0.name < $1.name }
            self.buildConfiguration = buildConfiguration
        }

        var volumeArgument: String {
            "\(hostWorkspaceURL.path):/workspace"
        }

        var environmentArguments: [String] {
            containerEnv.flatMap { ["--env", $0.argumentValue] }
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
            if let buildConfiguration = supportReport.buildConfiguration,
               supportReport.classification == .buildBased {
                guard let containerToolPath = containerToolResolver("container")?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                    !containerToolPath.isEmpty
                else {
                    return native(
                        selectedPreference: preference,
                        devcontainerSupportReport: supportReport,
                        fallbackReason: "Apple container CLI is unavailable."
                    )
                }

                return Self(
                    selectedPreference: preference,
                    effectiveRoute: .appleContainer(AppleContainerRoute(
                        toolPath: containerToolPath,
                        hostWorkspaceURL: standardizedRepoURL,
                        image: buildConfiguration.localImageTag,
                        workspaceFolder: "/workspace",
                        containerEnv: buildConfiguration.containerEnv,
                        buildConfiguration: buildConfiguration
                    )),
                    devcontainerSupportReport: supportReport
                )
            }

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
                        workspaceFolder: config.workspaceFolder,
                        containerEnv: config.containerEnv
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

    var buildInvocation: CodexExecutionInvocation? {
        switch effectiveRoute {
        case .nativeMacOS:
            return nil
        case let .appleContainer(route):
            return route.buildConfiguration?.buildInvocation(containerToolPath: route.toolPath)
        }
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

    func buildFeedbackSummary(fallbackReason: String? = nil) -> String {
        [
            "devcontainer \(devcontainerSupportLabel)",
            "local image \(imageLabel)",
            "fallback \(Self.boundedText(fallbackReason ?? fallbackReasonLabel, limit: Self.fallbackReasonLimit))"
        ].joined(separator: "; ")
    }

    func buildFailureFallback(exitCode: Int32?) -> Self {
        Self.native(
            selectedPreference: selectedPreference,
            devcontainer: devcontainer,
            devcontainerSupportReport: devcontainerSupportReport,
            fallbackReason: buildFailureFallbackReason(exitCode: exitCode)
        )
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

    private func buildFailureFallbackReason(exitCode: Int32?) -> String {
        let detail: String
        if let exitCode {
            detail = "Apple container build failed for local image \(imageLabel) (exit \(exitCode))."
        } else {
            detail = "Apple container build could not start for local image \(imageLabel)."
        }
        return Self.boundedText(detail, limit: Self.fallbackReasonLimit)
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
                    "--workdir", route.workspaceFolder
                ] + route.environmentArguments + [
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
                    "--workdir", route.workspaceFolder
                ] + route.environmentArguments + [
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
