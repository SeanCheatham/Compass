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
