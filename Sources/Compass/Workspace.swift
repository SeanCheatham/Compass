import Foundation

struct CompassWorkspace {
    var repoURL: URL

    var compassURL: URL { repoURL.appending(path: ".compass", directoryHint: .isDirectory) }
    var stateURL: URL { compassURL.appending(path: "state.json") }
    var stateBackupURL: URL { compassURL.appending(path: "state.json.bak") }
    var draftsURL: URL { compassURL.appending(path: "drafts.md") }
    var lessonsURL: URL { compassURL.appending(path: "lessons.md") }
    var visionURL: URL { compassURL.appending(path: "COMPASS.md") }
    var sessionsURL: URL { compassURL.appending(path: "sessions", directoryHint: .isDirectory) }
    var sessionsRecordURL: URL { compassURL.appending(path: "sessions.json") }

    static func isGitRepository(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appending(path: ".git").path)
    }

    static func discover(from startURL: URL) -> URL? {
        var current = startURL.standardizedFileURL

        while true {
            if isGitRepository(current) {
                return current
            }

            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { return nil }
            current = parent
        }
    }

    static func normalizedURL(from path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            .standardizedFileURL
    }

    func initialize() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: compassURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: sessionsURL, withIntermediateDirectories: true)

        try createFileIfMissing(stateURL, contents: Self.encodeState(.empty))
        try createFileIfMissing(draftsURL, contents: "")
        try createFileIfMissing(lessonsURL, contents: "")
        try createFileIfMissing(visionURL, contents: "")
        try createFileIfMissing(sessionsRecordURL, contents: "[]\n")
        try ensureCompassIsIgnored()
    }

    func readState() throws -> PlanState {
        guard FileManager.default.fileExists(atPath: stateURL.path) else {
            return .empty
        }
        let data = try Data(contentsOf: stateURL)
        if data.isEmpty { return .empty }
        return try JSONDecoder().decode(PlanState.self, from: data)
    }

    func writeState(_ state: PlanState) throws {
        try Self.encodeState(state).write(to: stateURL, atomically: true, encoding: .utf8)
    }

    func backupStateFile() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: stateURL.path) else { return }
        if fm.fileExists(atPath: stateBackupURL.path) {
            try fm.removeItem(at: stateBackupURL)
        }
        try fm.copyItem(at: stateURL, to: stateBackupURL)
    }

    func readDrafts() -> String {
        (try? String(contentsOf: draftsURL, encoding: .utf8)) ?? ""
    }

    func writeDrafts(_ text: String) throws {
        try text.write(to: draftsURL, atomically: true, encoding: .utf8)
    }

    func appendDraft(_ text: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var existing = readDrafts()
        if existing.isEmpty || existing.hasSuffix("\n\n") {
            // No separator needed.
        } else if existing.hasSuffix("\n") {
            existing += "\n"
        } else {
            existing += "\n\n"
        }
        existing += "- \(trimmed)\n"
        try writeDrafts(existing)
    }

    func snapshotAndClearDrafts() throws -> String {
        let fm = FileManager.default
        let snapshotURL = draftsURL.deletingLastPathComponent()
            .appending(path: "\(draftsURL.lastPathComponent).snapshot")

        do {
            if fm.fileExists(atPath: snapshotURL.path) {
                try fm.removeItem(at: snapshotURL)
            }
            try fm.moveItem(at: draftsURL, to: snapshotURL)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
            return ""
        }

        try writeDrafts("")
        defer { try? fm.removeItem(at: snapshotURL) }
        return (try? String(contentsOf: snapshotURL, encoding: .utf8)) ?? ""
    }

    func readLessons() -> String {
        (try? String(contentsOf: lessonsURL, encoding: .utf8)) ?? ""
    }

    func writeLessons(_ text: String) throws {
        try text.write(to: lessonsURL, atomically: true, encoding: .utf8)
    }

    @discardableResult
    func applyLessonEdits(_ edits: [LessonEdit]) throws -> Int {
        guard !edits.isEmpty else { return 0 }
        var current = readLessons()
        var applied = 0
        for edit in edits {
            current = try applyingLessonEdit(edit, to: current)
            applied += 1
        }
        try writeLessons(current)
        return applied
    }

    private func applyingLessonEdit(_ edit: LessonEdit, to current: String) throws -> String {
        if edit.find.isEmpty {
            guard current.isEmpty else {
                throw CompassWorkspaceError.lessonEditFailed(
                    "Empty `find` is only allowed when lessons.md is empty."
                )
            }
            return edit.replace
        }

        let matches = current.nonOverlappingOccurrences(of: edit.find)
        guard matches > 0 else {
            throw CompassWorkspaceError.lessonEditFailed("Lesson edit `find` text was not found in lessons.md.")
        }
        guard matches == 1 || edit.replaceAll == true else {
            throw CompassWorkspaceError.lessonEditFailed(
                "Lesson edit `find` text matched \(matches) times. Include more context or set replaceAll=true."
            )
        }

        let updated: String
        if edit.replaceAll == true {
            updated = current.replacingOccurrences(of: edit.find, with: edit.replace)
        } else if let range = current.range(of: edit.find) {
            updated = current.replacingCharacters(in: range, with: edit.replace)
        } else {
            throw CompassWorkspaceError.lessonEditFailed("Lesson edit `find` text was not found in lessons.md.")
        }
        return updated
    }

    func readVision() -> String {
        (try? String(contentsOf: visionURL, encoding: .utf8)) ?? ""
    }

    func writeVision(_ text: String) throws {
        try text.write(to: visionURL, atomically: true, encoding: .utf8)
    }

    func readSessions() -> [SessionRecord] {
        guard let data = try? Data(contentsOf: sessionsRecordURL), !data.isEmpty else {
            return []
        }
        return (try? JSONDecoder().decode([SessionRecord].self, from: data)) ?? []
    }

    func writeSessions(_ records: [SessionRecord]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(records)
        let text = String(decoding: data, as: UTF8.self) + "\n"
        try text.write(to: sessionsRecordURL, atomically: true, encoding: .utf8)
    }

    func writeSessionArtifact(session: Int, name: String, contents: String) throws -> URL {
        try FileManager.default.createDirectory(at: sessionsURL, withIntermediateDirectories: true)
        let safeName = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let url = sessionsURL.appending(path: "\(session)-\(safeName)")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func encodeState(_ state: PlanState) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    private func createFileIfMissing(_ url: URL, contents: String) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func ensureCompassIsIgnored() throws {
        let gitignoreURL = repoURL.appending(path: ".gitignore")
        let marker = ".compass/"
        var text = (try? String(contentsOf: gitignoreURL, encoding: .utf8)) ?? ""
        let alreadyIgnored = text
            .split(whereSeparator: \.isNewline)
            .contains {
                let line = $0.trimmingCharacters(in: .whitespaces)
                return line == marker || line == ".compass"
            }
        guard !alreadyIgnored else { return }

        if !text.isEmpty && !text.hasSuffix("\n") {
            text += "\n"
        }
        text += "\(marker)\n"
        try text.write(to: gitignoreURL, atomically: true, encoding: .utf8)
    }
}

struct CompassWorkspaceStorageAssessment: Equatable {
    static let maxProjectIdentifierLength = 64
    static let labelLimit = 34
    static let detailLimit = 180
    static let recommendationLimit = 140

    var repoURL: URL
    var applicationSupportRoots: KnownProjectStore.ApplicationSupportRoots
    var projectStorageIdentifier: String
    var currentApplicationSupportCandidateURL: URL
    var legacyApplicationSupportCandidateURL: URL
    var facts: Facts
    var issues: [Issue]
    var primaryIssue: Issue

    var kind: Kind { primaryIssue.kind }
    var severity: Severity { primaryIssue.severity }
    var label: String { primaryIssue.label }
    var detail: String { primaryIssue.detail }
    var recommendation: String { primaryIssue.recommendation }
    var systemImage: String { primaryIssue.systemImage }
    var isHealthy: Bool { issues.isEmpty }

    init(
        repoURL: URL,
        applicationSupportRoots: KnownProjectStore.ApplicationSupportRoots = KnownProjectStore.productionApplicationSupportRoots(),
        fileManager: FileManager = .default
    ) {
        let standardizedRepoURL = repoURL.standardizedFileURL
        let identifier = Self.projectStorageIdentifier(for: standardizedRepoURL)
        let currentCandidateURL = Self.currentApplicationSupportCandidateURL(
            for: standardizedRepoURL,
            applicationSupportRoots: applicationSupportRoots,
            identifier: identifier
        )
        let legacyCandidateURL = Self.legacyApplicationSupportCandidateURL(
            for: standardizedRepoURL,
            applicationSupportRoots: applicationSupportRoots,
            identifier: identifier
        )
        let facts = Self.collectFacts(
            repoURL: standardizedRepoURL,
            currentCandidateURL: currentCandidateURL,
            legacyCandidateURL: legacyCandidateURL,
            fileManager: fileManager
        )
        self.init(
            repoURL: standardizedRepoURL,
            applicationSupportRoots: applicationSupportRoots,
            projectStorageIdentifier: identifier,
            currentApplicationSupportCandidateURL: currentCandidateURL,
            legacyApplicationSupportCandidateURL: legacyCandidateURL,
            facts: facts
        )
    }

    init(
        repoURL: URL,
        applicationSupportRoots: KnownProjectStore.ApplicationSupportRoots,
        projectStorageIdentifier: String? = nil,
        currentApplicationSupportCandidateURL: URL? = nil,
        legacyApplicationSupportCandidateURL: URL? = nil,
        facts: Facts
    ) {
        let standardizedRepoURL = repoURL.standardizedFileURL
        let identifier = projectStorageIdentifier ?? Self.projectStorageIdentifier(for: standardizedRepoURL)
        let currentCandidateURL = currentApplicationSupportCandidateURL ?? Self.currentApplicationSupportCandidateURL(
            for: standardizedRepoURL,
            applicationSupportRoots: applicationSupportRoots,
            identifier: identifier
        )
        let legacyCandidateURL = legacyApplicationSupportCandidateURL ?? Self.legacyApplicationSupportCandidateURL(
            for: standardizedRepoURL,
            applicationSupportRoots: applicationSupportRoots,
            identifier: identifier
        )

        self.repoURL = standardizedRepoURL
        self.applicationSupportRoots = applicationSupportRoots
        self.projectStorageIdentifier = Self.boundedIdentifier(identifier)
        self.currentApplicationSupportCandidateURL = currentCandidateURL
        self.legacyApplicationSupportCandidateURL = legacyCandidateURL
        self.facts = facts

        let derivedIssues = Self.issues(
            facts: facts,
            repoURL: standardizedRepoURL,
            currentCandidateURL: currentCandidateURL,
            legacyCandidateURL: legacyCandidateURL
        )
        issues = derivedIssues
        primaryIssue = derivedIssues.first ?? Self.healthyIssue(repoURL: standardizedRepoURL)
    }

    static func projectStorageIdentifier(for repoURL: URL) -> String {
        let slugLimit = max(8, maxProjectIdentifierLength - 17)
        let fallback = repoURL.lastPathComponent.isEmpty ? "project" : repoURL.lastPathComponent
        let slug = sanitizedSlug(from: fallback, limit: slugLimit)
        let hash = stableHash(repoURL.standardizedFileURL.path)
        return boundedIdentifier("\(slug)-\(hash.prefix(16))")
    }

    static func currentApplicationSupportCandidateURL(
        for repoURL: URL,
        applicationSupportRoots roots: KnownProjectStore.ApplicationSupportRoots,
        identifier: String? = nil
    ) -> URL {
        KnownProjectStore.directoryURL(in: roots.current)
            .appending(path: "Projects", directoryHint: .isDirectory)
            .appending(path: identifier ?? projectStorageIdentifier(for: repoURL), directoryHint: .isDirectory)
    }

    static func legacyApplicationSupportCandidateURL(
        for repoURL: URL,
        applicationSupportRoots roots: KnownProjectStore.ApplicationSupportRoots,
        identifier: String? = nil
    ) -> URL {
        KnownProjectStore.legacyDirectoryURL(in: roots.legacy)
            .appending(path: "Projects", directoryHint: .isDirectory)
            .appending(path: identifier ?? projectStorageIdentifier(for: repoURL), directoryHint: .isDirectory)
    }

    struct Facts: Equatable {
        var compassDirectoryExists: Bool
        var presentCoreFiles: Set<CoreFile>
        var sessionsDirectoryExists: Bool
        var gitignoreContents: String?
        var currentApplicationSupportCandidateExists: Bool
        var legacyApplicationSupportCandidateExists: Bool

        var missingCoreFiles: [CoreFile] {
            CoreFile.allCases.filter { !presentCoreFiles.contains($0) }
        }

        var gitignoreCoversCompass: Bool {
            CompassWorkspaceStorageAssessment.gitignoreCoversCompass(gitignoreContents)
        }
    }

    enum CoreFile: String, CaseIterable, Hashable, Equatable {
        case state = "state.json"
        case drafts = "drafts.md"
        case lessons = "lessons.md"
        case vision = "COMPASS.md"
        case sessionsRecord = "sessions.json"

        var relativePath: String { rawValue }
    }

    enum Kind: String, Equatable {
        case repoLocalHealthy
        case missingWorkspace
        case incompleteCoreFiles
        case currentApplicationSupportCandidateExists
        case unignoredCompass
        case legacyApplicationSupportCandidateExists
    }

    enum Severity: String, Equatable {
        case healthy
        case info
        case warning
        case failure
    }

    struct Issue: Identifiable, Equatable {
        var kind: Kind
        var severity: Severity
        var label: String
        var detail: String
        var recommendation: String
        var systemImage: String

        var id: String { kind.rawValue }
    }

    private static func collectFacts(
        repoURL: URL,
        currentCandidateURL: URL,
        legacyCandidateURL: URL,
        fileManager: FileManager
    ) -> Facts {
        let workspace = CompassWorkspace(repoURL: repoURL)
        let compassDirectoryExists = directoryExists(workspace.compassURL, fileManager: fileManager)
        let presentCoreFiles = Set(CoreFile.allCases.filter { coreFile in
            fileExists(url(for: coreFile, in: workspace), fileManager: fileManager)
        })
        let sessionsDirectoryExists = directoryExists(workspace.sessionsURL, fileManager: fileManager)
        let gitignoreURL = repoURL.appending(path: ".gitignore")

        return Facts(
            compassDirectoryExists: compassDirectoryExists,
            presentCoreFiles: presentCoreFiles,
            sessionsDirectoryExists: sessionsDirectoryExists,
            gitignoreContents: try? String(contentsOf: gitignoreURL, encoding: .utf8),
            currentApplicationSupportCandidateExists: fileManager.fileExists(atPath: currentCandidateURL.path),
            legacyApplicationSupportCandidateExists: fileManager.fileExists(atPath: legacyCandidateURL.path)
        )
    }

    private static func issues(
        facts: Facts,
        repoURL: URL,
        currentCandidateURL: URL,
        legacyCandidateURL: URL
    ) -> [Issue] {
        var issues: [Issue] = []

        if !facts.compassDirectoryExists {
            issues.append(
                issue(
                    kind: .missingWorkspace,
                    severity: .warning,
                    label: "Workspace missing",
                    detail: "Repo-local .compass/ has not been initialized for \(boundedPath(repoURL.path, limit: 96)).",
                    recommendation: "Initialize the Compass workspace before running Plan or Develop.",
                    systemImage: "folder.badge.questionmark"
                )
            )
        } else {
            let missingItems = facts.missingCoreFiles.map(\.relativePath)
                + (facts.sessionsDirectoryExists ? [] : ["sessions/"])
            if !missingItems.isEmpty {
                issues.append(
                    issue(
                        kind: .incompleteCoreFiles,
                        severity: .failure,
                        label: "Workspace incomplete",
                        detail: ".compass/ is present but missing \(missingItems.joined(separator: ", ")).",
                        recommendation: "Reinitialize the workspace to restore the repo-local storage skeleton.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                )
            }
        }

        if facts.currentApplicationSupportCandidateExists {
            issues.append(
                issue(
                    kind: .currentApplicationSupportCandidateExists,
                    severity: .warning,
                    label: "Support path occupied",
                    detail: "Future storage candidate already exists at \(boundedPath(currentCandidateURL.path, limit: 112)).",
                    recommendation: "Keep repo-local storage for now; inspect that directory before any migration or mirroring work.",
                    systemImage: "externaldrive.badge.exclamationmark"
                )
            )
        }

        if facts.compassDirectoryExists,
           facts.missingCoreFiles.isEmpty,
           facts.sessionsDirectoryExists,
           !facts.gitignoreCoversCompass {
            issues.append(
                issue(
                    kind: .unignoredCompass,
                    severity: .warning,
                    label: ".compass unignored",
                    detail: ".compass/ exists but is not covered by the repository .gitignore.",
                    recommendation: "Add .compass/ to .gitignore before committing from this repository.",
                    systemImage: "eye.fill"
                )
            )
        }

        if facts.legacyApplicationSupportCandidateExists {
            issues.append(
                issue(
                    kind: .legacyApplicationSupportCandidateExists,
                    severity: .info,
                    label: "Legacy support data",
                    detail: "Legacy CompassNative candidate exists at \(boundedPath(legacyCandidateURL.path, limit: 112)).",
                    recommendation: "Account for the legacy directory before future migration or mirroring work.",
                    systemImage: "clock.arrow.circlepath"
                )
            )
        }

        return issues
    }

    private static func healthyIssue(repoURL: URL) -> Issue {
        issue(
            kind: .repoLocalHealthy,
            severity: .healthy,
            label: "Repo-local healthy",
            detail: ".compass/ has the expected core files, session storage, and .gitignore coverage.",
            recommendation: "No storage action needed for \(boundedPath(repoURL.lastPathComponent, limit: 48)).",
            systemImage: "checkmark.seal.fill"
        )
    }

    private static func issue(
        kind: Kind,
        severity: Severity,
        label: String,
        detail: String,
        recommendation: String,
        systemImage: String
    ) -> Issue {
        Issue(
            kind: kind,
            severity: severity,
            label: boundedText(label, limit: labelLimit),
            detail: boundedText(detail, limit: detailLimit),
            recommendation: boundedText(recommendation, limit: recommendationLimit),
            systemImage: systemImage
        )
    }

    private static func url(for coreFile: CoreFile, in workspace: CompassWorkspace) -> URL {
        switch coreFile {
        case .state:
            return workspace.stateURL
        case .drafts:
            return workspace.draftsURL
        case .lessons:
            return workspace.lessonsURL
        case .vision:
            return workspace.visionURL
        case .sessionsRecord:
            return workspace.sessionsRecordURL
        }
    }

    private static func gitignoreCoversCompass(_ text: String?) -> Bool {
        guard let text else { return false }
        return text
            .split(whereSeparator: \.isNewline)
            .contains { rawLine in
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty, !line.hasPrefix("#") else { return false }
                return line == ".compass"
                    || line == ".compass/"
                    || line == "/.compass"
                    || line == "/.compass/"
            }
    }

    private static func directoryExists(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory = ObjCBool(false)
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func fileExists(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory = ObjCBool(false)
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    private static func sanitizedSlug(from value: String, limit: Int) -> String {
        var scalars = String.UnicodeScalarView()
        var previousWasSeparator = false

        for scalar in value.lowercased().unicodeScalars {
            let isASCIILetter = scalar.value >= 97 && scalar.value <= 122
            let isDigit = scalar.value >= 48 && scalar.value <= 57
            if isASCIILetter || isDigit {
                scalars.append(scalar)
                previousWasSeparator = false
            } else if !previousWasSeparator, !scalars.isEmpty {
                scalars.append("-")
                previousWasSeparator = true
            }
        }

        let trimmed = String(String(scalars).prefix(max(1, limit)))
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "project" : trimmed
    }

    private static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        let raw = String(hash, radix: 16)
        return String(repeating: "0", count: max(0, 16 - raw.count)) + raw
    }

    private static func boundedIdentifier(_ value: String) -> String {
        String(value.prefix(maxProjectIdentifierLength))
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func boundedPath(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        guard limit > 1 else { return String(value.prefix(max(0, limit))) }
        return "..." + value.suffix(max(0, limit - 3))
    }

    private static func boundedText(_ value: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        guard value.count > limit else { return value }
        guard limit > 3 else { return String(value.prefix(limit)) }
        return value.prefix(limit - 3)
            .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}

private enum CompassWorkspaceError: LocalizedError {
    case lessonEditFailed(String)

    var errorDescription: String? {
        switch self {
        case let .lessonEditFailed(message):
            return message
        }
    }
}

private extension String {
    func nonOverlappingOccurrences(of needle: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var searchStart = startIndex
        while let range = range(of: needle, range: searchStart..<endIndex) {
            count += 1
            searchStart = range.upperBound
        }
        return count
    }
}
