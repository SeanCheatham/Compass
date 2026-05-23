import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct LiveActivitySummary: Equatable, Sendable {
    var clusterKey: String
    var title: String
    var source: Source

    enum Source: String, Equatable, Sendable {
        case deterministic
        case generated
    }

    init(clusterKey: String, title: String, source: Source) {
        self.clusterKey = clusterKey
        self.title = LiveActivitySummaryService.fittedTitle(title)
        self.source = source
    }
}

struct LiveActivityCluster: Equatable, Identifiable {
    var key: String
    var lines: [LiveLine]
    var freezeReason: FreezeReason

    var id: String { key }

    enum FreezeReason: String, Equatable {
        case lifecycleBoundary
        case quietGap
    }

    init(lines: [LiveLine], freezeReason: FreezeReason) {
        self.lines = lines
        self.freezeReason = freezeReason
        key = Self.key(for: lines)
    }

    var startDate: Date? {
        lines.first?.date
    }

    var endDate: Date? {
        lines.last?.completedAt ?? lines.last?.date
    }

    static func key(for lines: [LiveLine]) -> String {
        var hasher = StableLiveActivityHasher()
        for line in lines {
            hasher.combine(line.id.uuidString)
            hasher.combine(eventFingerprint(for: line))
        }
        return "live-summary-v1-\(hasher.hexDigest)"
    }

    static func eventFingerprint(for line: LiveLine) -> String {
        [
            line.status.summaryName,
            line.kind.summaryName,
            line.level.summaryName,
            boundedFingerprintText(line.text),
            boundedFingerprintText(firstLine(line.detail) ?? "")
        ]
            .joined(separator: "|")
    }

    private static func boundedFingerprintText(_ text: String) -> String {
        let normalized = LiveActivitySummaryService.normalizedPlainText(text)
        guard normalized.count > 72 else { return normalized }
        return String(normalized.prefix(72))
    }
}

enum LiveActivitySummaryItem: Equatable, Identifiable {
    case frozenCluster(LiveActivityCluster)
    case line(LiveLine)

    var id: String {
        switch self {
        case .frozenCluster(let cluster):
            return "cluster-\(cluster.key)"
        case .line(let line):
            return "line-\(line.id.uuidString)"
        }
    }
}

struct LiveActivitySummaryPlan: Equatable {
    var items: [LiveActivitySummaryItem]
    var frozenClusters: [LiveActivityCluster]
}

enum LiveActivitySummaryPlanner {
    static let quietGap: TimeInterval = 2.0
    static let minimumFrozenRowCount = 5

    static func plan(
        lines: [LiveLine],
        now: Date = Date(),
        quietGap: TimeInterval = Self.quietGap,
        minimumFrozenRowCount: Int = Self.minimumFrozenRowCount
    ) -> LiveActivitySummaryPlan {
        let minimumFrozenRowCount = max(1, minimumFrozenRowCount)
        var items: [LiveActivitySummaryItem] = []
        var frozenClusters: [LiveActivityCluster] = []
        var pendingLines: [LiveLine] = []

        for index in lines.indices {
            let line = lines[index]
            pendingLines.append(line)

            guard pendingLines.count >= minimumFrozenRowCount,
                  pendingLines.allSatisfy({ $0.status != .running }) else {
                continue
            }

            let nextLine = lines.index(after: index) < lines.endIndex
                ? lines[lines.index(after: index)]
                : nil
            guard let freezeReason = freezeReason(
                endingWith: line,
                nextLine: nextLine,
                now: now,
                quietGap: quietGap
            ) else {
                continue
            }

            let cluster = LiveActivityCluster(
                lines: pendingLines,
                freezeReason: freezeReason
            )
            items.append(.frozenCluster(cluster))
            frozenClusters.append(cluster)
            pendingLines.removeAll()
        }

        items.append(contentsOf: pendingLines.map(LiveActivitySummaryItem.line))
        return LiveActivitySummaryPlan(items: items, frozenClusters: frozenClusters)
    }

    static func inputIdentifier(for lines: [LiveLine]) -> String {
        var hasher = StableLiveActivityHasher()
        for line in lines {
            hasher.combine(line.id.uuidString)
            hasher.combine(String(line.date.timeIntervalSince1970))
            hasher.combine(LiveActivityCluster.eventFingerprint(for: line))
        }
        return "live-input-v1-\(hasher.hexDigest)"
    }

    private static func freezeReason(
        endingWith line: LiveLine,
        nextLine: LiveLine?,
        now: Date,
        quietGap: TimeInterval
    ) -> LiveActivityCluster.FreezeReason? {
        if line.kind == .lifecycle, line.status != .running {
            return .lifecycleBoundary
        }

        let gap: TimeInterval
        if let nextLine {
            gap = nextLine.date.timeIntervalSince(line.date)
        } else {
            gap = now.timeIntervalSince(line.date)
        }

        return gap > quietGap ? .quietGap : nil
    }
}

struct LiveActivitySummaryCachePlan: Equatable {
    var requestedClusters: [LiveActivityCluster]
    var staleCacheKeys: Set<String>
    var staleInFlightKeys: Set<String>
}

enum LiveActivitySummaryCachePlanner {
    static func plan(
        clusters: [LiveActivityCluster],
        cachedKeys: Set<String>,
        inFlightKeys: Set<String>
    ) -> LiveActivitySummaryCachePlan {
        let activeKeys = Set(clusters.map(\.key))
        let requestedClusters = clusters.filter {
            !cachedKeys.contains($0.key) && !inFlightKeys.contains($0.key)
        }

        return LiveActivitySummaryCachePlan(
            requestedClusters: requestedClusters,
            staleCacheKeys: cachedKeys.subtracting(activeKeys),
            staleInFlightKeys: inFlightKeys.subtracting(activeKeys)
        )
    }
}

enum LiveActivitySummaryService {
    static let titleMaxCharacters = 78
    static let titleMaxWords = 12
    static let modelPromptMaxEvents = 32
    static let modelPromptEventMaxCharacters = 180

    static func makeSummary(for cluster: LiveActivityCluster) async -> LiveActivitySummary {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if let generated = try? await FoundationModelLiveActivitySummaryGenerator.generate(
                cluster: cluster
            ) {
                return generated
            }
        }
        #endif

        return deterministicSummary(for: cluster)
    }

    static func deterministicSummary(for cluster: LiveActivityCluster) -> LiveActivitySummary {
        let representativeLine = cluster.lines.last { line in
            !normalizedPlainText(line.detail ?? line.text).isEmpty
        }
        let representativeText = representativeLine.map {
            normalizedPlainText(firstLine($0.detail) ?? $0.text)
        } ?? ""

        let prefix: String
        if cluster.lines.contains(where: { $0.status == .failed || $0.level == .error }) {
            prefix = "Attention"
        } else if cluster.lines.contains(where: { $0.kind == .command }) {
            prefix = "Command batch"
        } else if cluster.lines.contains(where: { $0.kind == .fileChange }) {
            prefix = "File activity"
        } else if cluster.lines.contains(where: { $0.kind == .agentMessage }) {
            prefix = "Agent activity"
        } else if cluster.lines.contains(where: { $0.kind == .lifecycle }) {
            prefix = "Phase update"
        } else {
            prefix = "Live activity"
        }

        let title: String
        if representativeText.isEmpty {
            title = prefix
        } else {
            title = "\(prefix): \(representativeText)"
        }

        return LiveActivitySummary(
            clusterKey: cluster.key,
            title: fittedTitle(title),
            source: .deterministic
        )
    }

    static func parseGeneratedTitle(
        _ raw: String,
        cluster: LiveActivityCluster
    ) -> LiveActivitySummary? {
        let lines = raw
            .replacingOccurrences(of: "\r", with: "\n")
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard lines.count == 1 else { return nil }
        let line = lines[0]
        let title: String
        if line.lowercased().hasPrefix("title:") {
            title = stripLabel(from: line)
        } else {
            title = line
        }

        let cleanTitle = normalizeGeneratedText(title)
        guard validateGeneratedTitle(cleanTitle, cluster: cluster) else { return nil }
        return LiveActivitySummary(
            clusterKey: cluster.key,
            title: cleanTitle,
            source: .generated
        )
    }

    static func fittedTitle(_ text: String) -> String {
        let normalized = normalizedPlainText(text)
        let wordLimited = normalized
            .split(whereSeparator: \.isWhitespace)
            .prefix(titleMaxWords)
            .joined(separator: " ")
        return fittedPlainText(wordLimited, maxCharacters: titleMaxCharacters)
    }

    static func normalizedPlainText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func modelPromptLines(for cluster: LiveActivityCluster) -> [String] {
        boundedModelLines(cluster.lines).enumerated().map { index, line in
            let promptText = fittedPlainText(
                promptText(for: line),
                maxCharacters: modelPromptEventMaxCharacters
            )
            return "\(index + 1). \(promptText)"
        }
    }

    private static func promptText(for line: LiveLine) -> String {
        [statusName(line.status), kindName(line.kind), line.text, firstLine(line.detail)]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " | ")
    }

    private static func kindName(_ kind: LiveLine.Kind) -> String {
        switch kind {
        case .message:      return "message"
        case .lifecycle:    return "lifecycle"
        case .command:      return "command"
        case .agentMessage: return "agent"
        case .fileChange:   return "file change"
        }
    }

    private static func statusName(_ status: LiveLine.Status) -> String {
        switch status {
        case .none:      return "noted"
        case .running:   return "running"
        case .completed: return "completed"
        case .failed:    return "failed"
        }
    }

    private static func validateGeneratedTitle(
        _ title: String,
        cluster: LiveActivityCluster
    ) -> Bool {
        guard (3...titleMaxCharacters).contains(title.count),
              wordCount(title) <= titleMaxWords,
              isPlainGeneratedTitle(title),
              validateNoInvention(title: title, cluster: cluster) else {
            return false
        }
        return true
    }

    private static func validateNoInvention(
        title: String,
        cluster: LiveActivityCluster
    ) -> Bool {
        let source = normalizedPlainText(
            cluster.lines
                .map { promptText(for: $0) }
                .joined(separator: " ")
        )

        guard doesNotAddPatternMatches(
            from: title,
            source: source,
            pattern: #"(?<![A-Za-z0-9])#?\d[\d,]*(?:\.\d+)?%?(?![A-Za-z0-9])"#
        ) else {
            return false
        }

        guard doesNotAddPatternMatches(
            from: title,
            source: source,
            pattern: #"[A-Za-z0-9_./-]+\.(?:swift|ts|tsx|js|jsx|json|md|txt|yml|yaml|toml|lock|py|go|rs|sh|zsh|html|css|scss|plist|xcodeproj|xcworkspace|m|mm|h|hpp|cpp|c|sql)"#
        ) else {
            return false
        }

        guard doesNotAddPatternMatches(
            from: title,
            source: source,
            pattern: #"[A-Za-z0-9_-]+/[A-Za-z0-9_./-]+"#
        ) else {
            return false
        }

        guard doesNotAddPatternMatches(
            from: title,
            source: source,
            pattern: #"(?<![A-Za-z0-9_.-])(?:README|LICENSE|Makefile|Dockerfile|Gemfile|Podfile|Rakefile)(?![A-Za-z0-9_.-])"#
        ) else {
            return false
        }

        let guardedOutcomes = [
            "complete",
            "completed",
            "deployed",
            "done",
            "failed",
            "fixed",
            "finished",
            "green",
            "implemented",
            "merged",
            "passed",
            "passing",
            "ready",
            "resolved",
            "shipped",
            "success",
            "successful",
            "verified",
            "working"
        ]
        guard doesNotAddGuardedWords(guardedOutcomes, title: title, source: source) else {
            return false
        }

        let guardedNumberWords = [
            "zero",
            "one",
            "two",
            "three",
            "four",
            "five",
            "six",
            "seven",
            "eight",
            "nine",
            "ten",
            "eleven",
            "twelve"
        ]
        return doesNotAddGuardedWords(guardedNumberWords, title: title, source: source)
    }

    private static func isPlainGeneratedTitle(_ title: String) -> Bool {
        let lowercased = title.lowercased()
        guard !lowercased.contains("http://"),
              !lowercased.contains("https://"),
              !lowercased.contains("www."),
              !title.contains("```"),
              !title.contains("`"),
              !title.contains("{"),
              !title.contains("}"),
              !title.contains("["),
              !title.contains("]"),
              !title.contains("\""),
              !title.hasPrefix("#"),
              !title.hasPrefix("- "),
              !title.hasPrefix("* "),
              !title.hasPrefix(">") else {
            return false
        }
        return true
    }

    private static func normalizeGeneratedText(_ text: String) -> String {
        normalizedPlainText(text)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
    }

    private static func boundedModelLines(_ lines: [LiveLine]) -> [LiveLine] {
        guard lines.count > modelPromptMaxEvents else { return lines }
        let headCount = modelPromptMaxEvents / 2
        let tailCount = modelPromptMaxEvents - headCount
        return Array(lines.prefix(headCount)) + Array(lines.suffix(tailCount))
    }

    private static func fittedPlainText(_ text: String, maxCharacters: Int) -> String {
        let normalized = normalizedPlainText(text)
        guard normalized.count > maxCharacters else { return normalized }

        let prefix = normalized.prefix(maxCharacters)
        if let lastSpace = prefix.lastIndex(where: { $0 == " " }), lastSpace > prefix.startIndex {
            return String(prefix[..<lastSpace]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(prefix).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripLabel(from line: String) -> String {
        guard let colon = line.firstIndex(of: ":") else { return line }
        return String(line[line.index(after: colon)...])
    }

    private static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    private static func doesNotAddPatternMatches(
        from title: String,
        source: String,
        pattern: String
    ) -> Bool {
        let sourceTokens = Set(matches(in: source.lowercased(), pattern: pattern))
        for token in matches(in: title.lowercased(), pattern: pattern) {
            guard sourceTokens.contains(token) else { return false }
        }
        return true
    }

    private static func doesNotAddGuardedWords(
        _ words: [String],
        title: String,
        source: String
    ) -> Bool {
        let title = title.lowercased()
        let source = source.lowercased()
        for word in words {
            guard containsWord(word, in: title) else { continue }
            guard containsWord(word, in: source) else { return false }
        }
        return true
    }

    private static func matches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let tokenRange = Range(match.range, in: text) else { return nil }
            return String(text[tokenRange]).lowercased()
        }
    }

    private static func containsWord(_ word: String, in text: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: word)
        let pattern = #"(?<![A-Za-z0-9])"# + escaped + #"(?![A-Za-z0-9])"#
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
private enum FoundationModelLiveActivitySummaryGenerator {
    static func generate(cluster: LiveActivityCluster) async throws -> LiveActivitySummary? {
        let model = SystemLanguageModel.default
        guard model.isAvailable else { return nil }

        let session = LanguageModelSession(instructions: """
        You title a completed batch of Compass live activity for a macOS software factory.
        Return exactly one plain-text title line under 12 words.
        Use only facts present in the supplied events.
        Do not invent file names, paths, URLs, numbers, outcomes, markdown, JSON, or completion claims.
        """)

        let events = LiveActivitySummaryService.modelPromptLines(for: cluster)
            .joined(separator: "\n")

        let response = try await session.respond(
            to: """
            Events:
            \(events)

            Write one compact title for the batch.
            """,
            options: GenerationOptions(temperature: 0.35, maximumResponseTokens: 40)
        )

        return LiveActivitySummaryService.parseGeneratedTitle(
            response.content,
            cluster: cluster
        )
    }
}
#endif

private struct StableLiveActivityHasher {
    private var value: UInt64 = 14_695_981_039_346_656_037

    var hexDigest: String {
        String(value, radix: 16)
    }

    mutating func combine(_ string: String) {
        for byte in string.utf8 {
            value ^= UInt64(byte)
            value &*= 1_099_511_628_211
        }
        value ^= UInt64(0xff)
        value &*= 1_099_511_628_211
    }
}

private func firstLine(_ text: String?) -> String? {
    text?
        .split(whereSeparator: \.isNewline)
        .first
        .map(String.init)
}

private extension LiveLine.Level {
    var summaryName: String {
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
    var summaryName: String {
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
    var summaryName: String {
        switch self {
        case .none: return "noted"
        case .running: return "running"
        case .completed: return "completed"
        case .failed: return "failed"
        }
    }
}
