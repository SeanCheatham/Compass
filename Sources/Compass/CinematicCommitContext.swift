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

struct CinematicCommitConstellationPlan: Equatable {
    static let maxCommitCount = 6
    static let positionXRange: ClosedRange<Float> = -3.2...3.2
    static let positionYRange: ClosedRange<Float> = 1.24...2.86
    static let positionZRange: ClosedRange<Float> = -6.15...(-5.05)

    static let empty = CinematicCommitConstellationPlan(
        identifier: "commit-constellation.empty",
        nodes: [],
        branchSegments: []
    )

    var identifier: String
    var nodes: [Node]
    var branchSegments: [BranchSegment]

    var count: Int { nodes.count }
    var newestSubject: String? { nodes.first?.subject }
    var isEmpty: Bool { nodes.isEmpty }
    var nodeIdentifiers: [String] { nodes.map(\.stableID) }
    var branchIdentifiers: [String] { branchSegments.map(\.stableID) }

    struct Node: Equatable {
        var stableID: String
        var commitIdentifier: String
        var shortHash: String
        var subject: String
        var label: String
        var position: SIMD3<Float>
        var radius: Float
        var rank: Int
    }

    struct BranchSegment: Equatable {
        var stableID: String
        var fromNodeID: String
        var toNodeID: String
        var label: String
        var startPosition: SIMD3<Float>
        var endPosition: SIMD3<Float>
    }

    init(sessions: [SessionRecord], hasRepository: Bool = true) {
        guard hasRepository else {
            self = Self.empty
            return
        }

        let commits = Self.recentDisplayCommits(from: sessions)
        guard !commits.isEmpty else {
            self = Self.empty
            return
        }

        let nodes = commits.enumerated().map { index, commit in
            Self.node(for: commit, rank: index)
        }
        let branches = Self.branchSegments(for: nodes)
        self = CinematicCommitConstellationPlan(
            identifier: Self.identifier(nodes: nodes, branches: branches),
            nodes: nodes,
            branchSegments: branches
        )
    }

    private init(identifier: String, nodes: [Node], branchSegments: [BranchSegment]) {
        self.identifier = identifier
        self.nodes = nodes
        self.branchSegments = branchSegments
    }

    private struct DisplayCommit: Equatable {
        var subject: String
        var stableCommitID: String
        var shortHash: String
    }

    private static let recentSessionLimit = 8
    private static let nodeSlots: [SIMD3<Float>] = [
        [0, 2.82, -5.12],
        [-1.52, 2.48, -5.48],
        [1.58, 2.18, -5.62],
        [-2.78, 1.82, -5.24],
        [2.92, 1.56, -5.36],
        [0.64, 1.28, -6.08]
    ]

    private static func recentDisplayCommits(from sessions: [SessionRecord]) -> [DisplayCommit] {
        var seen = Set<String>()
        var commits: [DisplayCommit] = []
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
                guard let subject = CinematicCommitContext.displaySubject(from: commit.subject) else {
                    continue
                }

                let stableCommitID = sanitizedCommitIdentifier(commit.sha)
                    ?? sanitizedCommitIdentifier(commit.short)
                    ?? "session\(session.session)-commit\(commits.count)"
                guard !seen.contains(stableCommitID) else { continue }

                seen.insert(stableCommitID)
                commits.append(
                    DisplayCommit(
                        subject: subject,
                        stableCommitID: stableCommitID,
                        shortHash: displayShortHash(commit)
                    )
                )

                if commits.count == maxCommitCount {
                    return commits
                }
            }
        }

        return commits
    }

    private static func node(for commit: DisplayCommit, rank: Int) -> Node {
        let position = nodeSlots[min(rank, nodeSlots.count - 1)]
        let label = [commit.shortHash, commit.subject]
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return Node(
            stableID: "commit-node-\(commit.stableCommitID)",
            commitIdentifier: commit.stableCommitID,
            shortHash: commit.shortHash,
            subject: commit.subject,
            label: label,
            position: [
                clamp(position.x, to: positionXRange),
                clamp(position.y, to: positionYRange),
                clamp(position.z, to: positionZRange)
            ],
            radius: rank == 0 ? 0.14 : 0.11,
            rank: rank
        )
    }

    private static func branchSegments(for nodes: [Node]) -> [BranchSegment] {
        guard nodes.count > 1 else { return [] }

        return (0..<(nodes.count - 1)).map { index in
            let newer = nodes[index]
            let older = nodes[index + 1]
            return BranchSegment(
                stableID: "commit-branch-\(older.commitIdentifier)-to-\(newer.commitIdentifier)",
                fromNodeID: older.stableID,
                toNodeID: newer.stableID,
                label: "\(older.shortHash)->\(newer.shortHash)",
                startPosition: older.position,
                endPosition: newer.position
            )
        }
    }

    private static func identifier(nodes: [Node], branches: [BranchSegment]) -> String {
        [
            "commit-constellation",
            "nodes:\(nodes.map(\.stableID).joined(separator: ","))",
            "branches:\(branches.map(\.stableID).joined(separator: ","))"
        ].joined(separator: "|")
    }

    private static func displayShortHash(_ commit: SessionCommit) -> String {
        let raw = commit.short.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty {
            return String(raw.prefix(10))
        }
        let sha = commit.sha.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(sha.prefix(10))
    }

    private static func sanitizedCommitIdentifier(_ raw: String) -> String? {
        let sanitized = raw
            .lowercased()
            .filter { character in
                character.isLetter || character.isNumber
            }
        guard !sanitized.isEmpty else { return nil }
        return String(sanitized.prefix(16))
    }

    private static func outcomeTime(_ record: SessionRecord) -> Double {
        record.endedAt ?? record.startedAt
    }

    private static func clamp(_ value: Float, to range: ClosedRange<Float>) -> Float {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
