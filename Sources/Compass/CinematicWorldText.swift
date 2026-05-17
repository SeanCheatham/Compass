import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct CinematicWorldText: Equatable {
    var questLabel: String
    var arenaCallout: String
    var activityCallout: String

    static let placeholder = CinematicWorldText(
        questLabel: "Unknown gate: Idle watch",
        arenaCallout: "Unknown arena over Project",
        activityCallout: "Dim gate: 0 milestones"
    )

    init(questLabel: String, arenaCallout: String, activityCallout: String) {
        self.questLabel = questLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        self.arenaCallout = arenaCallout.trimmingCharacters(in: .whitespacesAndNewlines)
        self.activityCallout = activityCallout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct CinematicWorldTextInput: Equatable {
    var repoName: String
    var currentPhase: String
    var immediatePlanTitle: String
    var completedCount: Int
    var latestEvent: CinematicBriefingEvent?
    var languageProfile: RepositoryLanguageProfile
    var activityProfile: RepositoryActivityProfile
}

enum CinematicWorldTextService {
    static let questLabelMaxCharacters = 38
    static let arenaCalloutMaxCharacters = 46
    static let activityCalloutMaxCharacters = 54
    static let questLabelMaxWords = 6
    static let arenaCalloutMaxWords = 7
    static let activityCalloutMaxWords = 8

    static func makeWorldText(input: CinematicWorldTextInput) async -> CinematicWorldText {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if let generated = try? await FoundationModelCinematicWorldTextGenerator.generate(input: input) {
                return generated
            }
        }
        #endif

        return deterministicWorldText(for: input)
    }

    static func deterministicWorldText(for input: CinematicWorldTextInput) -> CinematicWorldText {
        let languageMotif = CinematicMotif.language(for: input.languageProfile)
        let activityMotif = CinematicMotif.activity(for: input.activityProfile)
        let questTopic = questTopic(from: input.immediatePlanTitle, phase: input.currentPhase)
        let repository = boundedDisplayText(
            input.repoName.isEmpty ? "Project" : input.repoName,
            maxCharacters: 18,
            fallback: "Project"
        )
        let eventCue = latestEventCue(
            event: input.latestEvent,
            phase: input.currentPhase,
            completedCount: input.completedCount
        )

        return CinematicWorldText(
            questLabel: boundedDisplayText(
                "\(questPrefix(for: languageMotif)): \(questTopic)",
                maxCharacters: Self.questLabelMaxCharacters,
                maxWords: Self.questLabelMaxWords,
                fallback: "Unknown gate: Idle watch"
            ),
            arenaCallout: boundedDisplayText(
                "\(arenaName(for: languageMotif)) over \(repository)",
                maxCharacters: Self.arenaCalloutMaxCharacters,
                maxWords: Self.arenaCalloutMaxWords,
                fallback: "Unknown arena over Project"
            ),
            activityCallout: boundedDisplayText(
                "\(activityPrefix(for: activityMotif)): \(eventCue)",
                maxCharacters: Self.activityCalloutMaxCharacters,
                maxWords: Self.activityCalloutMaxWords,
                fallback: "Dim gate: 0 milestones"
            )
        )
    }

    static func parseGeneratedWorldText(_ raw: String) -> CinematicWorldText? {
        let lines = raw
            .replacingOccurrences(of: "\r", with: "\n")
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard lines.count == 3 else { return nil }

        var questLabel: String?
        var arenaCallout: String?
        var activityCallout: String?

        for line in lines {
            let lowercased = line.lowercased()
            if lowercased.hasPrefix("quest:") {
                guard questLabel == nil else { return nil }
                questLabel = stripLabel(from: line)
            } else if lowercased.hasPrefix("arena:") {
                guard arenaCallout == nil else { return nil }
                arenaCallout = stripLabel(from: line)
            } else if lowercased.hasPrefix("activity:") {
                guard activityCallout == nil else { return nil }
                activityCallout = stripLabel(from: line)
            } else {
                return nil
            }
        }

        guard let questLabel, let arenaCallout, let activityCallout else { return nil }
        return validateGenerated(
            questLabel: questLabel,
            arenaCallout: arenaCallout,
            activityCallout: activityCallout
        )
    }

    private static func validateGenerated(
        questLabel: String,
        arenaCallout: String,
        activityCallout: String
    ) -> CinematicWorldText? {
        let cleanQuest = normalizeGeneratedText(questLabel)
        let cleanArena = normalizeGeneratedText(arenaCallout)
        let cleanActivity = normalizeGeneratedText(activityCallout)

        guard (4...Self.questLabelMaxCharacters).contains(cleanQuest.count),
              (6...Self.arenaCalloutMaxCharacters).contains(cleanArena.count),
              (6...Self.activityCalloutMaxCharacters).contains(cleanActivity.count),
              wordCount(cleanQuest) <= Self.questLabelMaxWords,
              wordCount(cleanArena) <= Self.arenaCalloutMaxWords,
              wordCount(cleanActivity) <= Self.activityCalloutMaxWords,
              Set([cleanQuest, cleanArena, cleanActivity]).count == 3,
              isUsableGeneratedText(cleanQuest),
              isUsableGeneratedText(cleanArena),
              isUsableGeneratedText(cleanActivity) else {
            return nil
        }

        return CinematicWorldText(
            questLabel: cleanQuest,
            arenaCallout: cleanArena,
            activityCallout: cleanActivity
        )
    }

    private static func questTopic(from immediatePlanTitle: String, phase: String) -> String {
        let plan = safeDisplayText(immediatePlanTitle)
        guard !plan.isEmpty, plan != "No immediate plan" else {
            let phaseName = safeDisplayText(phase).isEmpty ? "Idle" : safeDisplayText(phase)
            return boundedDisplayText("\(phaseName) watch", maxCharacters: 18, maxWords: 3, fallback: "Idle watch")
        }

        let trimmed = plan
            .replacingOccurrences(
                of: #"^(Implement|Add|Fix|Update|Create|Build|Refine|Thread|Display)\s+"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        return boundedDisplayText(trimmed, maxCharacters: 18, maxWords: 4, fallback: "Active quest")
    }

    private static func latestEventCue(
        event: CinematicBriefingEvent?,
        phase: String,
        completedCount: Int
    ) -> String {
        if let event {
            let cue = boundedDisplayText(event.shortText, maxCharacters: 30, maxWords: 5, fallback: "")
            if !cue.isEmpty {
                return cue
            }
        }

        let milestone = completedCount == 1 ? "1 milestone" : "\(max(0, completedCount)) milestones"
        let phaseName = boundedDisplayText(phase, maxCharacters: 16, fallback: "Idle")
        return "\(phaseName) \(milestone)"
    }

    private static func questPrefix(for motif: CinematicLanguageMotif) -> String {
        switch motif.style {
        case .swiftComet:
            return "Swift forge"
        case .scriptCircuit:
            return "Script circuit"
        case .pythonCoil:
            return "Python oracle"
        case .goCurrent:
            return "Go current"
        case .rustGear:
            return "Rust gear"
        case .markdownRune:
            return "Markdown archive"
        case .polyglotPrism:
            return "Polyglot prism"
        case .unknownGate:
            return "Unknown gate"
        }
    }

    private static func arenaName(for motif: CinematicLanguageMotif) -> String {
        switch motif.style {
        case .swiftComet:
            return "Comet forge"
        case .scriptCircuit:
            return "Circuit arena"
        case .pythonCoil:
            return "Oracle coil"
        case .goCurrent:
            return "Current gate"
        case .rustGear:
            return "Gearworks arena"
        case .markdownRune:
            return "Archive runes"
        case .polyglotPrism:
            return "Prism yard"
        case .unknownGate:
            return "Unknown arena"
        }
    }

    private static func activityPrefix(for motif: CinematicActivityMotif) -> String {
        switch motif.eventKind {
        case .unavailable:
            return "Dim gate"
        case .clean:
            return "Calm halo"
        case .dirty:
            return "Pressure shard"
        case .conflicted:
            return "Fracture cross"
        case .commit:
            return "History branch"
        case .success:
            return "Seal burst"
        case .recovery:
            return "Recovery arc"
        case .failure:
            return "Backlash spike"
        }
    }

    private static func boundedDisplayText(
        _ text: String,
        maxCharacters: Int,
        maxWords: Int? = nil,
        fallback: String
    ) -> String {
        let clean = safeDisplayText(text)
        let source = clean.isEmpty ? fallback : clean
        let wordLimited = limitWords(source, maxWords: maxWords)
        let fitted = fittedPlainText(wordLimited, maxCharacters: maxCharacters)
        return fitted.isEmpty ? fallback : fitted
    }

    private static func safeDisplayText(_ text: String) -> String {
        let withoutURLs = normalizePlainText(text)
            .replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"www\.\S+"#, with: "", options: .regularExpression)
        let filtered = withoutURLs.reduce(into: "") { partial, character in
            if !"`{}[]#*_\"".contains(character) {
                partial.append(character)
            }
        }
        return normalizePlainText(filtered)
            .trimmingCharacters(in: CharacterSet(charactersIn: " :;,.|-"))
    }

    private static func fittedPlainText(_ text: String, maxCharacters: Int) -> String {
        let normalized = normalizePlainText(text)
        guard normalized.count > maxCharacters else { return normalized }

        let prefix = normalized.prefix(maxCharacters)
        if let lastSpace = prefix.lastIndex(where: { $0 == " " }), lastSpace > prefix.startIndex {
            return String(prefix[..<lastSpace]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(prefix).trimmingCharacters(in: .whitespacesAndNewlines)
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

    private static func limitWords(_ text: String, maxWords: Int?) -> String {
        guard let maxWords, maxWords > 0 else { return text }
        let words = text.split(whereSeparator: \.isWhitespace)
        guard words.count > maxWords else { return text }
        return words.prefix(maxWords).joined(separator: " ")
    }

    private static func stripLabel(from line: String) -> String {
        guard let colon = line.firstIndex(of: ":") else { return line }
        return String(line[line.index(after: colon)...])
    }

    private static func isUsableGeneratedText(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        guard !lowercased.contains("```"),
              !lowercased.contains("http://"),
              !lowercased.contains("https://"),
              !lowercased.contains("www."),
              !lowercased.contains("questlabel"),
              !lowercased.contains("arenacallout"),
              !lowercased.contains("activitycallout"),
              !text.contains("{"),
              !text.contains("}"),
              !text.contains("["),
              !text.contains("]"),
              !text.contains("#"),
              !text.contains("*"),
              !text.contains("`"),
              !text.contains("\"") else {
            return false
        }
        return true
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
private enum FoundationModelCinematicWorldTextGenerator {
    static func generate(input: CinematicWorldTextInput) async throws -> CinematicWorldText? {
        let model = SystemLanguageModel.default
        guard model.isAvailable else { return nil }

        let languageMotif = CinematicMotif.language(for: input.languageProfile)
        let activityMotif = CinematicMotif.activity(for: input.activityProfile)
        let session = LanguageModelSession(instructions: """
        You write tiny cinematic HUD callouts for a macOS software factory.
        Return exactly three lines in this format:
        Quest: ...
        Arena: ...
        Activity: ...
        Keep each line plain text. No markdown, URLs, JSON, code, bullets, quotes, or invented files.
        Use only the supplied repository, phase, plan, language motif, activity motif, and live event.
        """)

        let response = try await session.respond(
            to: """
            Repository: \(input.repoName)
            Phase: \(input.currentPhase)
            Immediate plan: \(input.immediatePlanTitle)
            Completed count: \(input.completedCount)
            Latest live event: \(input.latestEvent?.promptText ?? "none")
            Language: \(input.languageProfile.primaryLanguage.displayName)
            Language motif: \(languageMotif.sigilIdentifier)
            Activity motif: \(activityMotif.sigilIdentifier)
            Activity state: \(activityMotif.eventKind.rawValue)
            Worktree pressure: \(input.activityProfile.pressureLevel.rawValue)

            Quest under \(CinematicWorldTextService.questLabelMaxWords) words.
            Arena under \(CinematicWorldTextService.arenaCalloutMaxWords) words.
            Activity under \(CinematicWorldTextService.activityCalloutMaxWords) words.
            """,
            options: GenerationOptions(temperature: 0.45, maximumResponseTokens: 90)
        )

        return CinematicWorldTextService.parseGeneratedWorldText(response.content)
    }
}
#endif
