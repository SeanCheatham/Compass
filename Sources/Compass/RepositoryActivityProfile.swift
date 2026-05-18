import Foundation

enum RepositoryWorktreePressureLevel: String, Codable, Equatable {
    case clean
    case light
    case moderate
    case heavy
}

struct RepositoryWorktreeChangeCounts: Codable, Equatable {
    var added = 0
    var modified = 0
    var deleted = 0
    var renamed = 0
    var untracked = 0
    var conflicted = 0
    var other = 0

    var total: Int {
        added + modified + deleted + renamed + untracked + conflicted + other
    }

    var isDirty: Bool {
        total > 0
    }

    var pressureLevel: RepositoryWorktreePressureLevel {
        if total == 0 { return .clean }
        if conflicted > 0 || total >= 16 { return .heavy }
        if total >= 6 { return .moderate }
        return .light
    }

    var hudSummary: String {
        guard isDirty else { return "Clean worktree" }

        let details = [
            countLabel(added, "added"),
            countLabel(modified, "modified"),
            countLabel(deleted, "deleted"),
            countLabel(renamed, "renamed"),
            countLabel(untracked, "untracked"),
            countLabel(conflicted, "conflicted"),
            countLabel(other, "other")
        ]
        .compactMap { $0 }
        .prefix(2)
        .joined(separator: ", ")

        let plural = total == 1 ? "change" : "changes"
        if details.isEmpty {
            return "\(total) pending \(plural)"
        }
        return "\(total) pending \(plural): \(details)"
    }

    private func countLabel(_ count: Int, _ label: String) -> String? {
        count > 0 ? "\(count) \(label)" : nil
    }
}

struct RepositoryActivityProfile: Codable, Equatable {
    var isAvailable: Bool
    var worktreeChanges: RepositoryWorktreeChangeCounts
    var recentSessionCount: Int
    var recentSucceededCount: Int
    var recentFailedCount: Int
    var recentCommitCount: Int
    var lastTerminalStatus: SessionStatus?
    var lastSuccessfulSession: Int?
    var lastFailedSession: Int?
    var successStreak: Int
    var failureStreak: Int
    var recoveredFromFailure: Bool

    static let empty = RepositoryActivityProfile(
        isAvailable: false,
        worktreeChanges: RepositoryWorktreeChangeCounts(),
        recentSessionCount: 0,
        recentSucceededCount: 0,
        recentFailedCount: 0,
        recentCommitCount: 0,
        lastTerminalStatus: nil,
        lastSuccessfulSession: nil,
        lastFailedSession: nil,
        successStreak: 0,
        failureStreak: 0,
        recoveredFromFailure: false
    )

    var isEmpty: Bool {
        !isAvailable
    }

    var pressureLevel: RepositoryWorktreePressureLevel {
        worktreeChanges.pressureLevel
    }

    var pressureScore: Int {
        let worktreeScore = worktreeChanges.total
            + worktreeChanges.conflicted * 4
            + worktreeChanges.untracked
        let outcomeScore = failureStreak * 5
        return worktreeScore + outcomeScore
    }

    var hudSummary: String? {
        guard !isEmpty else { return nil }

        var parts = [worktreeChanges.hudSummary]
        if recentCommitCount > 0 {
            let plural = recentCommitCount == 1 ? "commit" : "commits"
            parts.append("\(recentCommitCount) recent \(plural)")
        }

        if failureStreak > 0 {
            let plural = failureStreak == 1 ? "run" : "runs"
            parts.append("\(failureStreak) failed \(plural) in a row")
        } else if recoveredFromFailure {
            parts.append(successStreak > 1 ? "\(successStreak)-run recovery streak" : "recovered after last failure")
        } else if successStreak > 1 {
            parts.append("\(successStreak)-run success streak")
        } else if lastTerminalStatus == .succeeded {
            parts.append("last run succeeded")
        } else if lastTerminalStatus == .failed {
            parts.append("last run failed")
        } else if recentSessionCount == 0 {
            parts.append("no recent sessions")
        }

        return parts.prefix(3).joined(separator: " - ") + "."
    }
}

struct RepositoryActivitySourceSnapshot: Equatable {
    static let maxSessionsFileBytes: UInt64 = 2 * 1024 * 1024

    enum SourceAvailability: String, Equatable {
        case available
        case noRepository = "no-repository"
        case notScanned = "not-scanned"
        case storageRootMissing = "storage-root-missing"
        case sessionsRecordMissing = "sessions-record-missing"
        case sessionsRecordOversized = "sessions-record-oversized"
        case sessionsRecordUnreadable = "sessions-record-unreadable"
    }

    enum RepoLocalSessionsState: String, Equatable {
        case activeSource = "active-source"
        case ignoredMissing = "ignored-missing"
        case ignoredCompatible = "ignored-compatible"
        case ignoredOversized = "ignored-oversized"
        case ignoredUnreadable = "ignored-unreadable"
    }

    var activeStorage: KnownProjectActiveStorage
    var storageRootURL: URL?
    var sessionsRecordURL: URL?
    var sourceAvailability: SourceAvailability
    var repoLocalSessionsRecordURL: URL?
    var repoLocalSessionsState: RepoLocalSessionsState

    var activeStorageIdentifier: String { activeStorage.rawValue }
    var sourceAvailabilityIdentifier: String { sourceAvailability.rawValue }
    var repoLocalSessionsStateIdentifier: String { repoLocalSessionsState.rawValue }

    var ignoresRepoLocalSessions: Bool {
        switch repoLocalSessionsState {
        case .activeSource:
            return false
        case .ignoredMissing,
             .ignoredCompatible,
             .ignoredOversized,
             .ignoredUnreadable:
            return true
        }
    }

    var repoLocalSessionsIgnoredIdentifier: String {
        ignoresRepoLocalSessions ? "ignored" : "active"
    }

    var identifier: String {
        [
            "storage:\(activeStorageIdentifier)",
            "root:\(storageRootURL?.standardizedFileURL.path ?? "none")",
            "sessions:\(sessionsRecordURL?.standardizedFileURL.path ?? "none")",
            "availability:\(sourceAvailabilityIdentifier)",
            "repo-local:\(repoLocalSessionsStateIdentifier)",
            "repo-local-mode:\(repoLocalSessionsIgnoredIdentifier)"
        ].joined(separator: "|")
    }

    static func notScanned(activeStorage: KnownProjectActiveStorage = .repoLocal) -> Self {
        Self(
            activeStorage: activeStorage,
            storageRootURL: nil,
            sessionsRecordURL: nil,
            sourceAvailability: .notScanned,
            repoLocalSessionsRecordURL: nil,
            repoLocalSessionsState: activeStorage == .repoLocal ? .activeSource : .ignoredMissing
        )
    }

    static func noRepository(activeStorage: KnownProjectActiveStorage) -> Self {
        Self(
            activeStorage: activeStorage,
            storageRootURL: nil,
            sessionsRecordURL: nil,
            sourceAvailability: .noRepository,
            repoLocalSessionsRecordURL: nil,
            repoLocalSessionsState: activeStorage == .repoLocal ? .activeSource : .ignoredMissing
        )
    }

    static func snapshot(
        activeStorage: KnownProjectActiveStorage,
        workspace: CompassWorkspace,
        fileManager: FileManager = .default
    ) -> Self {
        let storageRootURL = workspace.compassURL.standardizedFileURL
        let sessionsRecordURL = workspace.sessionsRecordURL.standardizedFileURL
        let repoLocalSessionsRecordURL = workspace.repoLocalCompassURL
            .appending(path: "sessions.json")
            .standardizedFileURL
        let sourceAvailability = availability(
            storageRootURL: storageRootURL,
            sessionsRecordURL: sessionsRecordURL,
            fileManager: fileManager
        )
        let repoLocalSessionsState = Self.repoLocalSessionsState(
            activeStorage: activeStorage,
            repoLocalStorageRootURL: workspace.repoLocalCompassURL,
            repoLocalSessionsRecordURL: repoLocalSessionsRecordURL,
            fileManager: fileManager
        )

        return Self(
            activeStorage: activeStorage,
            storageRootURL: storageRootURL,
            sessionsRecordURL: sessionsRecordURL,
            sourceAvailability: sourceAvailability,
            repoLocalSessionsRecordURL: repoLocalSessionsRecordURL,
            repoLocalSessionsState: repoLocalSessionsState
        )
    }

    private static func repoLocalSessionsState(
        activeStorage: KnownProjectActiveStorage,
        repoLocalStorageRootURL: URL,
        repoLocalSessionsRecordURL: URL,
        fileManager: FileManager
    ) -> RepoLocalSessionsState {
        guard activeStorage != .repoLocal else { return .activeSource }

        switch availability(
            storageRootURL: repoLocalStorageRootURL,
            sessionsRecordURL: repoLocalSessionsRecordURL,
            fileManager: fileManager
        ) {
        case .available:
            return .ignoredCompatible
        case .sessionsRecordOversized:
            return .ignoredOversized
        case .sessionsRecordUnreadable:
            return .ignoredUnreadable
        case .storageRootMissing,
             .sessionsRecordMissing,
             .noRepository,
             .notScanned:
            return .ignoredMissing
        }
    }

    private static func availability(
        storageRootURL: URL,
        sessionsRecordURL: URL,
        fileManager: FileManager
    ) -> SourceAvailability {
        guard directoryExists(storageRootURL, fileManager: fileManager) else {
            return .storageRootMissing
        }
        guard fileExists(sessionsRecordURL, fileManager: fileManager) else {
            return .sessionsRecordMissing
        }
        guard let attributes = try? fileManager.attributesOfItem(atPath: sessionsRecordURL.path),
              let size = attributes[.size] as? NSNumber else {
            return .sessionsRecordUnreadable
        }
        guard size.uint64Value <= maxSessionsFileBytes else {
            return .sessionsRecordOversized
        }
        guard let data = try? Data(contentsOf: sessionsRecordURL) else {
            return .sessionsRecordUnreadable
        }
        guard !data.isEmpty else { return .available }
        guard (try? JSONDecoder().decode([SessionRecord].self, from: data)) != nil else {
            return .sessionsRecordUnreadable
        }
        return .available
    }

    private static func directoryExists(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory = ObjCBool(false)
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func fileExists(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory = ObjCBool(false)
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }
}

enum RepositoryActivityProfileService {
    static func scan(repoURL: URL) async -> RepositoryActivityProfile {
        let scanner = RepositoryActivityProfileScanner(
            repoURL: repoURL,
            sessionsRecordURL: CompassWorkspace(repoURL: repoURL).sessionsRecordURL
        )
        return await scanner.scan()
    }

    static func scan(workspace: CompassWorkspace) async -> RepositoryActivityProfile {
        let scanner = RepositoryActivityProfileScanner(
            repoURL: workspace.repoURL,
            sessionsRecordURL: workspace.sessionsRecordURL
        )
        return await scanner.scan()
    }
}

enum RepositoryActivityProfileDeriver {
    private static let recentSessionLimit = 8

    static func profile(
        from sessions: [SessionRecord],
        worktreeChanges: RepositoryWorktreeChangeCounts
    ) -> RepositoryActivityProfile {
        let terminalSessions = sessions
            .filter { $0.endedAt != nil }
            .sorted { outcomeTime($0) > outcomeTime($1) }
        let recentSessions = Array(terminalSessions.prefix(Self.recentSessionLimit))
        let lastSuccess = terminalSessions.first { $0.status == .succeeded }
        let lastFailure = terminalSessions.first { $0.status == .failed }
        let lastStatus = terminalSessions.first?.status
        let successStreak = streak(in: terminalSessions, status: .succeeded)
        let failureStreak = streak(in: terminalSessions, status: .failed)
        let recoveredFromFailure = lastStatus == .succeeded
            && lastFailure != nil
            && outcomeTime(lastSuccess) > outcomeTime(lastFailure)

        return RepositoryActivityProfile(
            isAvailable: true,
            worktreeChanges: worktreeChanges,
            recentSessionCount: recentSessions.count,
            recentSucceededCount: recentSessions.filter { $0.status == .succeeded }.count,
            recentFailedCount: recentSessions.filter { $0.status == .failed }.count,
            recentCommitCount: recentSessions.reduce(0) { $0 + $1.commits.count },
            lastTerminalStatus: lastStatus,
            lastSuccessfulSession: lastSuccess?.session,
            lastFailedSession: lastFailure?.session,
            successStreak: successStreak,
            failureStreak: failureStreak,
            recoveredFromFailure: recoveredFromFailure
        )
    }

    static func worktreeChanges(fromPorcelainStatus output: String) -> RepositoryWorktreeChangeCounts {
        var counts = RepositoryWorktreeChangeCounts()
        for line in output.split(whereSeparator: \.isNewline) {
            guard line.count >= 2 else {
                counts.other += 1
                continue
            }

            let x = line[line.startIndex]
            let y = line[line.index(after: line.startIndex)]

            if x == "?" && y == "?" {
                counts.untracked += 1
            } else if isConflict(x, y) {
                counts.conflicted += 1
            } else if x == "R" || y == "R" || x == "C" || y == "C" {
                counts.renamed += 1
            } else if x == "D" || y == "D" {
                counts.deleted += 1
            } else if x == "A" || y == "A" {
                counts.added += 1
            } else if x == "M" || y == "M" || x == "T" || y == "T" {
                counts.modified += 1
            } else {
                counts.other += 1
            }
        }
        return counts
    }

    private static func outcomeTime(_ record: SessionRecord?) -> Double {
        guard let record else { return -Double.infinity }
        return record.endedAt ?? record.startedAt
    }

    private static func streak(in records: [SessionRecord], status: SessionStatus) -> Int {
        var count = 0
        for record in records {
            guard record.status == status else { break }
            count += 1
        }
        return count
    }

    private static func isConflict(_ x: Character, _ y: Character) -> Bool {
        x == "U" || y == "U" || (x == "A" && y == "A") || (x == "D" && y == "D")
    }
}

private struct RepositoryActivityProfileScanner {
    private static let gitStatusTimeout: TimeInterval = 2
    private static let maxSessionsFileBytes: UInt64 = 2 * 1024 * 1024

    private let repoURL: URL
    private let sessionsRecordURL: URL
    private let fileManager = FileManager.default

    init(repoURL: URL, sessionsRecordURL: URL) {
        self.repoURL = repoURL.standardizedFileURL
        self.sessionsRecordURL = sessionsRecordURL.standardizedFileURL
    }

    func scan() async -> RepositoryActivityProfile {
        guard let sessions = loadSessions() else {
            return .empty
        }
        guard let worktreeChanges = await loadWorktreeChanges() else {
            return .empty
        }

        return RepositoryActivityProfileDeriver.profile(
            from: sessions,
            worktreeChanges: worktreeChanges
        )
    }

    private func loadSessions() -> [SessionRecord]? {
        guard fileManager.fileExists(atPath: sessionsRecordURL.path),
              let attributes = try? fileManager.attributesOfItem(atPath: sessionsRecordURL.path),
              let size = attributes[.size] as? NSNumber,
              size.uint64Value <= Self.maxSessionsFileBytes,
              let data = try? Data(contentsOf: sessionsRecordURL) else {
            return nil
        }

        if data.isEmpty {
            return []
        }
        return try? JSONDecoder().decode([SessionRecord].self, from: data)
    }

    private func loadWorktreeChanges() async -> RepositoryWorktreeChangeCounts? {
        guard let result = try? await ProcessRunner.runEnv(
            "git",
            ["status", "--porcelain", "--untracked-files=normal"],
            workingDirectory: repoURL,
            timeout: Self.gitStatusTimeout
        ), result.exitCode == 0 else {
            return nil
        }
        return RepositoryActivityProfileDeriver.worktreeChanges(fromPorcelainStatus: result.stdout)
    }
}
