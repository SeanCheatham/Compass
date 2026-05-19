import Foundation

typealias CodexDevcontainerProvisioningAction = (CodexDevcontainerProvisioningPlan) throws -> CodexDevcontainerProvisioningResult

struct CodexDevcontainerProvisioningTemplate: Equatable, Identifiable {
    static let titleLimit = 52
    static let imageLimit = 96
    static let workspaceLimit = 80
    static let configurationNameLimit = 64
    static let workspaceFolder = "/workspace"

    var id: String
    var title: String
    var language: RepositoryLanguage
    var image: String
    var workspaceFolder: String
    var configurationName: String

    init(
        id: String,
        title: String,
        language: RepositoryLanguage,
        image: String,
        workspaceFolder: String = Self.workspaceFolder,
        configurationName: String
    ) {
        self.id = id
        self.title = Self.boundedText(title, limit: Self.titleLimit)
        self.language = language
        self.image = Self.boundedText(image, limit: Self.imageLimit)
        self.workspaceFolder = Self.boundedText(workspaceFolder, limit: Self.workspaceLimit)
        self.configurationName = Self.boundedText(configurationName, limit: Self.configurationNameLimit)
    }

    var imageLabel: String {
        Self.boundedText(image, limit: Self.imageLimit)
    }

    var workspaceLabel: String {
        Self.boundedText(workspaceFolder, limit: Self.workspaceLimit)
    }

    func configurationData() throws -> Data {
        let configuration = CodexDevcontainerStarterConfiguration(
            image: image,
            name: configurationName,
            workspaceFolder: workspaceFolder
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(configuration)
        data.append(0x0A)
        return data
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
}

private struct CodexDevcontainerStarterConfiguration: Codable, Equatable {
    var image: String
    var name: String
    var workspaceFolder: String
}

enum CodexDevcontainerProvisioningTemplateCatalog {
    static let swift = CodexDevcontainerProvisioningTemplate(
        id: "swift",
        title: "Swift image starter",
        language: .swift,
        image: "swift:6.0",
        configurationName: "Compass Swift"
    )

    static let typeScriptJavaScript = CodexDevcontainerProvisioningTemplate(
        id: "typescript-javascript",
        title: "TypeScript/JavaScript image starter",
        language: .typeScriptJavaScript,
        image: "node:22-bookworm",
        configurationName: "Compass TypeScript JavaScript"
    )

    static let python = CodexDevcontainerProvisioningTemplate(
        id: "python",
        title: "Python image starter",
        language: .python,
        image: "python:3.12-bookworm",
        configurationName: "Compass Python"
    )

    static let go = CodexDevcontainerProvisioningTemplate(
        id: "go",
        title: "Go image starter",
        language: .go,
        image: "golang:1.23-bookworm",
        configurationName: "Compass Go"
    )

    static let rust = CodexDevcontainerProvisioningTemplate(
        id: "rust",
        title: "Rust image starter",
        language: .rust,
        image: "rust:1.82-bookworm",
        configurationName: "Compass Rust"
    )

    static let generic = CodexDevcontainerProvisioningTemplate(
        id: "generic",
        title: "Generic Debian image starter",
        language: .unknown,
        image: "mcr.microsoft.com/devcontainers/base:1-bookworm",
        configurationName: "Compass Dev Container"
    )

    static let all: [CodexDevcontainerProvisioningTemplate] = [
        swift,
        typeScriptJavaScript,
        python,
        go,
        rust,
        generic
    ]

    static func template(for profile: RepositoryLanguageProfile) -> CodexDevcontainerProvisioningTemplate {
        switch profile.primaryLanguage {
        case .swift:
            return swift
        case .typeScriptJavaScript:
            return typeScriptJavaScript
        case .python:
            return python
        case .go:
            return go
        case .rust:
            return rust
        case .markdown, .other, .unknown:
            return manifestTemplate(for: profile) ?? generic
        }
    }

    private static func manifestTemplate(
        for profile: RepositoryLanguageProfile
    ) -> CodexDevcontainerProvisioningTemplate? {
        for hint in profile.manifestHints {
            switch hint.language {
            case .swift:
                return swift
            case .typeScriptJavaScript:
                return typeScriptJavaScript
            case .python:
                return python
            case .go:
                return go
            case .rust:
                return rust
            case .markdown, .other, .unknown:
                continue
            }
        }
        return nil
    }
}

struct CodexDevcontainerProvisioningPlan: Equatable {
    static let labelLimit = 42
    static let detailLimit = 320
    static let pathLimit = 160

    enum Status: Equatable {
        case available
        case alreadyPresent
        case malformed
    }

    var repoURL: URL
    var configURL: URL
    var template: CodexDevcontainerProvisioningTemplate
    var status: Status
    var discovery: CodexExecutionEnvironmentDiscovery

    init(
        repoURL: URL,
        configURL: URL,
        template: CodexDevcontainerProvisioningTemplate,
        status: Status,
        discovery: CodexExecutionEnvironmentDiscovery
    ) {
        self.repoURL = repoURL.standardizedFileURL
        self.configURL = configURL.standardizedFileURL
        self.template = template
        self.status = status
        self.discovery = discovery
    }

    static func plan(
        repoURL: URL,
        languageProfile: RepositoryLanguageProfile,
        fileManager: FileManager = .default
    ) -> Self {
        let standardizedRepoURL = repoURL.standardizedFileURL
        let discovery = CodexExecutionEnvironmentDiscovery.inspect(
            repoURL: standardizedRepoURL,
            fileManager: fileManager
        )
        let status: Status
        switch discovery.status {
        case .missing:
            status = .available
        case .ready:
            status = .alreadyPresent
        case .malformed:
            status = .malformed
        }

        return Self(
            repoURL: standardizedRepoURL,
            configURL: discovery.configURL,
            template: CodexDevcontainerProvisioningTemplateCatalog.template(for: languageProfile),
            status: status,
            discovery: discovery
        )
    }

    var isAvailable: Bool {
        status == .available
    }

    var label: String {
        switch status {
        case .available:
            return Self.boundedText("Create Dev Container", limit: Self.labelLimit)
        case .alreadyPresent:
            return Self.boundedText("Dev Container exists", limit: Self.labelLimit)
        case .malformed:
            return Self.boundedText("Dev Container needs attention", limit: Self.labelLimit)
        }
    }

    var detail: String {
        switch status {
        case .available:
            return Self.boundedText(
                "Create \(relativeConfigPath) from \(template.title) using image \(template.imageLabel) at workspace \(template.workspaceLabel). Native macOS remains selectable.",
                limit: Self.detailLimit
            )
        case .alreadyPresent:
            return Self.boundedText(
                "Compass will not overwrite existing \(relativeConfigPath). Native macOS remains selectable.",
                limit: Self.detailLimit
            )
        case .malformed:
            return Self.boundedText(
                "Compass will not replace malformed \(relativeConfigPath). Fix or remove the file before creating a starter.",
                limit: Self.detailLimit
            )
        }
    }

    var systemImage: String {
        switch status {
        case .available:
            return "plus.circle"
        case .alreadyPresent:
            return "shippingbox"
        case .malformed:
            return "exclamationmark.triangle"
        }
    }

    var relativeConfigPath: String {
        ".devcontainer/devcontainer.json"
    }

    func configurationData() throws -> Data {
        try template.configurationData()
    }

    static func boundedText(_ text: String, limit: Int) -> String {
        CodexDevcontainerProvisioningTemplate.boundedText(text, limit: limit)
    }

    static func boundedPath(_ value: String, limit: Int = pathLimit) -> String {
        guard value.count > limit else { return value }
        guard limit > 3 else { return String(value.prefix(max(0, limit))) }
        return "..." + value.suffix(max(0, limit - 3))
    }
}

struct CodexDevcontainerProvisioningConfirmation: Equatable, Identifiable {
    static let titleLimit = 58
    static let messageLimit = 900
    static let actionLabelLimit = 32

    var plan: CodexDevcontainerProvisioningPlan

    var id: String {
        [
            plan.repoURL.path,
            plan.configURL.path,
            plan.template.id,
            plan.template.image
        ]
        .joined(separator: "|")
    }

    var title: String {
        CodexDevcontainerProvisioningPlan.boundedText(
            "Create Dev Container?",
            limit: Self.titleLimit
        )
    }

    var message: String {
        CodexDevcontainerProvisioningPlan.boundedText(
            [
                "Template: \(plan.template.title)",
                "Image: \(plan.template.imageLabel)",
                "Workspace: \(plan.template.workspaceLabel)",
                "Writes: \(CodexDevcontainerProvisioningPlan.boundedPath(plan.configURL.path, limit: 220))",
                "Only an image-based \(plan.relativeConfigPath) starter will be created; Native macOS remains selectable."
            ]
            .joined(separator: "\n"),
            limit: Self.messageLimit
        )
    }

    var confirmLabel: String {
        CodexDevcontainerProvisioningPlan.boundedText("Create", limit: Self.actionLabelLimit)
    }

    var cancelLabel: String {
        CodexDevcontainerProvisioningPlan.boundedText("Cancel", limit: Self.actionLabelLimit)
    }
}

struct CodexDevcontainerProvisioningResult: Equatable {
    static let detailLimit = 320

    var plan: CodexDevcontainerProvisioningPlan
    var configURL: URL

    init(plan: CodexDevcontainerProvisioningPlan) {
        self.plan = plan
        self.configURL = plan.configURL.standardizedFileURL
    }

    var detail: String {
        CodexDevcontainerProvisioningPlan.boundedText(
            "Created \(plan.relativeConfigPath) with \(plan.template.title), image \(plan.template.imageLabel), and workspace \(plan.template.workspaceLabel). Native macOS remains selectable.",
            limit: Self.detailLimit
        )
    }
}

enum CodexDevcontainerProvisioningError: LocalizedError, Equatable {
    case unavailable(String)
    case configAlreadyExists(String)
    case parentPathIsFile(String)
    case writtenConfigNotReady(String)

    var errorDescription: String? {
        switch self {
        case let .unavailable(detail):
            return "Dev Container provisioning is unavailable: \(detail)"
        case let .configAlreadyExists(path):
            return "Refusing to overwrite existing devcontainer config at \(path)."
        case let .parentPathIsFile(path):
            return "Cannot create .devcontainer directory because a file already exists at \(path)."
        case let .writtenConfigNotReady(reason):
            return "Created devcontainer config, but Compass could not verify it: \(reason)"
        }
    }
}

enum CodexDevcontainerProvisioner {
    static func write(
        plan: CodexDevcontainerProvisioningPlan,
        fileManager: FileManager = .default
    ) throws -> CodexDevcontainerProvisioningResult {
        guard plan.isAvailable else {
            throw CodexDevcontainerProvisioningError.unavailable(plan.detail)
        }

        let directoryURL = plan.configURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory),
           !isDirectory.boolValue {
            throw CodexDevcontainerProvisioningError.parentPathIsFile(directoryURL.path)
        }

        guard !fileManager.fileExists(atPath: plan.configURL.path) else {
            throw CodexDevcontainerProvisioningError.configAlreadyExists(plan.configURL.path)
        }

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        guard !fileManager.fileExists(atPath: plan.configURL.path) else {
            throw CodexDevcontainerProvisioningError.configAlreadyExists(plan.configURL.path)
        }

        try plan.configurationData().write(to: plan.configURL, options: .atomic)
        return CodexDevcontainerProvisioningResult(plan: plan)
    }
}

struct CompassProjectDevcontainerProvisioningState: Equatable {
    static let labelLimit = 38
    static let detailLimit = 300
    static let helpLimit = 560

    enum Phase: Equatable {
        case idle
        case awaitingConfirmation
        case running
        case succeeded
        case failed
        case blocked
    }

    var phase: Phase
    var label: String
    var detail: String
    var systemImage: String

    var isRunning: Bool {
        phase == .running
    }

    var shouldShowFeedback: Bool {
        phase != .idle
    }

    var helpText: String {
        CodexDevcontainerProvisioningPlan.boundedText(
            [label, detail]
                .filter { !$0.isEmpty }
                .joined(separator: " - "),
            limit: Self.helpLimit
        )
    }

    static let idle = CompassProjectDevcontainerProvisioningState(
        phase: .idle,
        label: "Create Dev Container",
        detail: "Create a safe image-based .devcontainer/devcontainer.json starter when the project does not already have one.",
        systemImage: "plus.circle"
    )

    static func awaitingConfirmation(_ confirmation: CodexDevcontainerProvisioningConfirmation) -> Self {
        Self(
            phase: .awaitingConfirmation,
            label: "Confirm Dev Container",
            detail: "Review the image-based starter before Compass writes \(confirmation.plan.relativeConfigPath).",
            systemImage: confirmation.plan.systemImage
        )
    }

    static func running(plan: CodexDevcontainerProvisioningPlan) -> Self {
        Self(
            phase: .running,
            label: "Creating Dev Container",
            detail: "Writing \(plan.relativeConfigPath) with image \(plan.template.imageLabel) and workspace \(plan.template.workspaceLabel).",
            systemImage: "plus.circle"
        )
    }

    static func succeeded(_ result: CodexDevcontainerProvisioningResult) -> Self {
        Self(
            phase: .succeeded,
            label: "Dev Container ready",
            detail: result.detail,
            systemImage: "checkmark.circle.fill"
        )
    }

    static func failed(_ error: Error) -> Self {
        Self(
            phase: .failed,
            label: "Dev Container failed",
            detail: error.localizedDescription,
            systemImage: "exclamationmark.triangle.fill"
        )
    }

    static func blocked(plan: CodexDevcontainerProvisioningPlan) -> Self {
        Self(
            phase: .blocked,
            label: plan.label,
            detail: plan.detail,
            systemImage: plan.systemImage
        )
    }

    static func blockedWhileBusy() -> Self {
        Self(
            phase: .blocked,
            label: "Creation blocked",
            detail: "Stop or finish the active Compass run before creating a Dev Container starter.",
            systemImage: "pause.circle.fill"
        )
    }

    init(phase: Phase, label: String, detail: String, systemImage: String) {
        self.phase = phase
        self.label = CodexDevcontainerProvisioningPlan.boundedText(label, limit: Self.labelLimit)
        self.detail = CodexDevcontainerProvisioningPlan.boundedText(detail, limit: Self.detailLimit)
        self.systemImage = systemImage
    }
}

struct CodexDevcontainerProvisioningMenuAction: Equatable, Identifiable {
    static let actionIdentifier = "devcontainer-provisioning.create"
    static let titleLimit = 34
    static let descriptionLimit = 220
    static let helpLimit = 320

    var id: String
    var title: String
    var systemImage: String
    var description: String
    var helpText: String

    init?(plan: CodexDevcontainerProvisioningPlan) {
        guard plan.isAvailable else { return nil }
        id = Self.actionIdentifier
        title = CodexDevcontainerProvisioningPlan.boundedText(
            "Create Dev Container",
            limit: Self.titleLimit
        )
        systemImage = plan.systemImage
        description = CodexDevcontainerProvisioningPlan.boundedText(
            "Use \(plan.template.title): image \(plan.template.imageLabel), workspace \(plan.template.workspaceLabel), writes \(plan.relativeConfigPath).",
            limit: Self.descriptionLimit
        )
        helpText = CodexDevcontainerProvisioningPlan.boundedText(
            plan.detail,
            limit: Self.helpLimit
        )
    }
}
