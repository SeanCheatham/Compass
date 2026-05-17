import Foundation

struct PlanWorkflowOverview: Equatable {
    static let defaultExcerptLimit = 220

    var completedCount: Int
    var immediate: Section
    var midTerm: Section
    var longTerm: Section

    var sections: [Section] {
        [immediate, midTerm, longTerm]
    }

    init(state: PlanState, excerptLimit: Int = Self.defaultExcerptLimit) {
        completedCount = state.completed.count
        immediate = Section(
            kind: .immediate,
            title: "Immediate Work",
            label: "Current",
            systemImage: "target",
            rawBody: state.immediate?.plan ?? "",
            emptyMessage: "No immediate plan. The factory is ready for the next scoped implementation.",
            verifyCommand: state.immediate?.verify,
            estimatedDifficulty: state.immediate?.estimatedDifficulty,
            completedCount: completedCount,
            excerptLimit: excerptLimit
        )
        midTerm = Section(
            kind: .midTerm,
            title: "Queued Direction",
            label: "Next Up",
            systemImage: "point.3.connected.trianglepath.dotted",
            rawBody: state.midTerm,
            emptyMessage: "No mid-term queue. Future planning has no staged direction yet.",
            completedCount: completedCount,
            excerptLimit: excerptLimit
        )
        longTerm = Section(
            kind: .longTerm,
            title: "Strategic Arc",
            label: "Destination",
            systemImage: "mountain.2.fill",
            rawBody: state.longTerm,
            emptyMessage: "No long-term arc. Add the larger product direction when it becomes clear.",
            completedCount: completedCount,
            excerptLimit: excerptLimit
        )
    }

    struct Section: Identifiable, Equatable {
        var kind: Kind
        var title: String
        var label: String
        var systemImage: String
        var body: String
        var excerpt: String?
        var emptyMessage: String
        var verifyCommand: String?
        var estimatedDifficulty: PlanNext.Difficulty?
        var completedCount: Int

        var id: Kind { kind }

        var isEmpty: Bool {
            body.isEmpty
        }

        var estimatedDifficultyLabel: String? {
            estimatedDifficulty?.rawValue.capitalized
        }

        init(
            kind: Kind,
            title: String,
            label: String,
            systemImage: String,
            rawBody: String,
            emptyMessage: String,
            verifyCommand: String? = nil,
            estimatedDifficulty: PlanNext.Difficulty? = nil,
            completedCount: Int,
            excerptLimit: Int
        ) {
            let body = PlanWorkflowOverview.normalizedMarkdownBody(rawBody)
            self.kind = kind
            self.title = title
            self.label = label
            self.systemImage = systemImage
            self.body = body
            self.excerpt = PlanWorkflowOverview.boundedExcerpt(for: body, limit: excerptLimit)
            self.emptyMessage = emptyMessage
            self.verifyCommand = verifyCommand?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            self.estimatedDifficulty = estimatedDifficulty
            self.completedCount = completedCount
        }
    }

    enum Kind: String, Equatable {
        case immediate
        case midTerm
        case longTerm
    }

    private static func normalizedMarkdownBody(_ rawBody: String) -> String {
        let normalizedNewlines = rawBody
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalizedNewlines.components(separatedBy: "\n")

        var normalizedLines: [String] = []
        var previousWasBlank = false

        for rawLine in lines {
            let line = collapsedHorizontalWhitespace(in: rawLine)
                .trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                if !normalizedLines.isEmpty, !previousWasBlank {
                    normalizedLines.append("")
                    previousWasBlank = true
                }
                continue
            }

            normalizedLines.append(line)
            previousWasBlank = false
        }

        while normalizedLines.last == "" {
            normalizedLines.removeLast()
        }

        return normalizedLines.joined(separator: "\n")
    }

    private static func boundedExcerpt(for body: String, limit: Int) -> String? {
        let denseBody = body
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !denseBody.isEmpty else {
            return nil
        }

        guard limit > 0, denseBody.count > limit else {
            return denseBody
        }

        guard limit > 3 else {
            return String(denseBody.prefix(limit))
        }

        let prefixLimit = max(0, limit - 3)
        let prefix = denseBody
            .prefix(prefixLimit)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(prefix)..."
    }

    private static func collapsedHorizontalWhitespace(in line: String) -> String {
        var result = ""
        var previousWasSpace = false

        for character in line {
            if character == " " || character == "\t" {
                if !previousWasSpace {
                    result.append(" ")
                    previousWasSpace = true
                }
            } else {
                result.append(character)
                previousWasSpace = false
            }
        }

        return result
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
