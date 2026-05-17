import Foundation

enum CinematicCommitContext {
    static let subjectMaxCharacters = 48
    private static let recentSessionLimit = 8

    static func latestSubject(from sessions: [SessionRecord]) -> String? {
        let recentSessions = sessions
            .sorted { lhs, rhs in
                let lhsTime = outcomeTime(lhs)
                let rhsTime = outcomeTime(rhs)
                if lhsTime == rhsTime {
                    return lhs.session > rhs.session
                }
                return lhsTime > rhsTime
            }
            .prefix(recentSessionLimit)

        for session in recentSessions {
            for commit in session.commits.reversed() {
                if let subject = displaySubject(from: commit.subject) {
                    return subject
                }
            }
        }

        return nil
    }

    static func displaySubject(from rawSubject: String?) -> String? {
        guard let rawSubject else { return nil }

        let withoutURLs = normalizePlainText(rawSubject)
            .replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"www\.\S+"#, with: "", options: .regularExpression)
        let filtered = withoutURLs.reduce(into: "") { partial, character in
            if !"`{}[]#*_\"".contains(character) {
                partial.append(character)
            }
        }
        let cleaned = normalizePlainText(filtered)
            .trimmingCharacters(in: CharacterSet(charactersIn: " :;,.|-"))
        guard !cleaned.isEmpty else { return nil }

        let fitted = fittedPlainText(cleaned, maxCharacters: subjectMaxCharacters)
        return fitted.isEmpty ? nil : fitted
    }

    private static func outcomeTime(_ record: SessionRecord) -> Double {
        record.endedAt ?? record.startedAt
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

    private static func normalizePlainText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
