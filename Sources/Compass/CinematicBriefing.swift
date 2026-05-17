import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct CinematicBriefing: Equatable, Sendable {
    var title: String
    var detail: String

    static let placeholder = CinematicBriefing(
        title: "Project briefing pending",
        detail: "Select or refresh a repository to stage the next expedition."
    )

    init(title: String, detail: String) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct CinematicBriefingEvent: Equatable, Sendable {
    var text: String
    var detail: String?
    var kind: String
    var status: String
    var level: String

    init(line: LiveLine) {
        text = line.text
        detail = line.detail
        kind = line.kind.briefingName
        status = line.status.briefingName
        level = line.level.briefingName
    }

    var promptText: String {
        [status, kind, text, firstLine(detail)]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " | ")
    }

    var shortText: String {
        let base = firstLine(detail) ?? text
        return CinematicBriefingService.fittedPlainText(base, maxCharacters: 72)
    }
}

struct CinematicBriefingInput: Equatable, Sendable {
    var repoName: String
    var currentPhase: String
    var immediatePlanTitle: String
    var completedCount: Int
    var latestEvent: CinematicBriefingEvent?
}

enum CinematicBriefingService {
    static func makeBriefing(input: CinematicBriefingInput) async -> CinematicBriefing {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if let generated = try? await FoundationModelCinematicBriefingGenerator.generate(input: input) {
                return generated
            }
        }
        #endif

        return deterministicBriefing(for: input)
    }

    static func deterministicBriefing(for input: CinematicBriefingInput) -> CinematicBriefing {
        let repo = fittedPlainText(
            input.repoName.isEmpty ? "Project" : input.repoName,
            maxCharacters: 30
        )
        let mission = missionTitle(from: input.immediatePlanTitle)
        let title = fittedPlainText("\(repo): \(mission)", maxCharacters: 68)

        let completed = input.completedCount == 1
            ? "1 completed milestone"
            : "\(input.completedCount) completed milestones"
        let eventClause: String
        if let latest = input.latestEvent?.shortText, !latest.isEmpty {
            eventClause = "Latest signal: \(latest)."
        } else {
            eventClause = "Awaiting the first live signal."
        }

        let detail = fittedPlainText(
            "\(input.currentPhase) with \(completed). \(eventClause)",
            maxCharacters: 150
        )
        return CinematicBriefing(title: title, detail: detail)
    }

    static func parseGeneratedBriefing(_ raw: String) -> CinematicBriefing? {
        if let briefing = parseJSONBriefing(raw) {
            return validateGenerated(title: briefing.title, detail: briefing.detail)
        }

        let lines = raw
            .replacingOccurrences(of: "\r", with: "\n")
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard lines.count <= 4 else { return nil }

        var title: String?
        var detail: String?
        for line in lines {
            let lowercased = line.lowercased()
            if lowercased.hasPrefix("title:") {
                guard title == nil else { return nil }
                title = stripLabel(from: line)
            } else if lowercased.hasPrefix("detail:") {
                guard detail == nil else { return nil }
                detail = stripLabel(from: line)
            }
        }

        if title == nil, let first = lines.first {
            title = stripLabel(from: first)
        }
        if detail == nil, lines.count > 1 {
            detail = stripLabel(from: lines[1])
        }

        guard let title, let detail else { return nil }
        return validateGenerated(title: title, detail: detail)
    }

    static func fittedPlainText(_ text: String, maxCharacters: Int) -> String {
        let normalized = normalizePlainText(text)
        guard normalized.count > maxCharacters else { return normalized }

        let prefix = normalized.prefix(maxCharacters)
        if let lastSpace = prefix.lastIndex(where: { $0 == " " }), lastSpace > prefix.startIndex {
            return String(prefix[..<lastSpace]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(prefix).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func missionTitle(from immediatePlanTitle: String) -> String {
        let plan = normalizePlainText(immediatePlanTitle)
        guard !plan.isEmpty, plan != "No immediate plan" else {
            return "Awaiting the next quest"
        }

        let trimmed = plan
            .replacingOccurrences(of: #"^(Implement|Add|Fix|Update|Create|Build|Refine)\s+"#,
                                  with: "",
                                  options: [.regularExpression, .caseInsensitive])
        let title = fittedPlainText(trimmed, maxCharacters: 42)
        return title.isEmpty ? "Active quest" : title
    }

    private static func validateGenerated(title: String, detail: String) -> CinematicBriefing? {
        let cleanTitle = normalizeGeneratedText(title)
        let cleanDetail = normalizeGeneratedText(detail)

        guard (4...72).contains(cleanTitle.count),
              (8...170).contains(cleanDetail.count),
              wordCount(cleanTitle) <= 10,
              wordCount(cleanDetail) <= 28,
              cleanTitle != cleanDetail,
              isUsableGeneratedText(cleanTitle),
              isUsableGeneratedText(cleanDetail) else {
            return nil
        }

        return CinematicBriefing(title: cleanTitle, detail: cleanDetail)
    }

    private static func parseJSONBriefing(_ raw: String) -> CinematicBriefing? {
        struct GeneratedBriefing: Decodable {
            var title: String
            var detail: String
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8) else { return nil }
        guard let decoded = try? JSONDecoder().decode(GeneratedBriefing.self, from: data) else {
            return nil
        }
        return CinematicBriefing(title: decoded.title, detail: decoded.detail)
    }

    private static func stripLabel(from line: String) -> String {
        guard let colon = line.firstIndex(of: ":") else { return line }
        return String(line[line.index(after: colon)...])
    }

    private static func normalizeGeneratedText(_ text: String) -> String {
        normalizePlainText(text)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'` "))
    }

    private static func normalizePlainText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    private static func isUsableGeneratedText(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        guard !lowercased.contains("```"),
              !lowercased.contains("http://"),
              !lowercased.contains("https://"),
              !text.contains("{"),
              !text.contains("}") else {
            return false
        }
        return true
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
private enum FoundationModelCinematicBriefingGenerator {
    static func generate(input: CinematicBriefingInput) async throws -> CinematicBriefing? {
        let model = SystemLanguageModel.default
        guard model.isAvailable else { return nil }

        let session = LanguageModelSession(instructions: """
        You write bounded cinematic quest HUD copy for a macOS software factory.
        Return exactly two short lines: "Title: ..." and "Detail: ...".
        The title must include the repository name or the plan topic.
        Do not invent files, outcomes, people, metrics, markdown, or JSON.
        """)

        let response = try await session.respond(
            to: """
            Repository: \(input.repoName)
            Phase: \(input.currentPhase)
            Immediate plan: \(input.immediatePlanTitle)
            Completed count: \(input.completedCount)
            Latest live event: \(input.latestEvent?.promptText ?? "none")

            Write a title under 10 words and a detail under 24 words.
            """,
            options: GenerationOptions(temperature: 0.55, maximumResponseTokens: 80)
        )

        return CinematicBriefingService.parseGeneratedBriefing(response.content)
    }
}
#endif

private func firstLine(_ text: String?) -> String? {
    text?
        .split(whereSeparator: \.isNewline)
        .first
        .map(String.init)
}

private extension LiveLine.Level {
    var briefingName: String {
        switch self {
        case .info: return "info"
        case .success: return "success"
        case .warning: return "warning"
        case .error: return "error"
        case .raw: return "raw"
        }
    }
}

private extension LiveLine.Kind {
    var briefingName: String {
        switch self {
        case .message: return "message"
        case .lifecycle: return "lifecycle"
        case .command: return "command"
        case .agentMessage: return "agent"
        case .fileChange: return "file change"
        }
    }
}

private extension LiveLine.Status {
    var briefingName: String {
        switch self {
        case .none: return "noted"
        case .running: return "running"
        case .completed: return "completed"
        case .failed: return "failed"
        }
    }
}
