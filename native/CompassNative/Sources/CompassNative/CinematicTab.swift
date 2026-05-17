import AppKit
import SwiftUI

struct CinematicTab: View {
    @ObservedObject var project: CompassProject

    var body: some View {
        GeometryReader { proxy in
            let caption = CinematicCaption(project: project)

            ZStack(alignment: .bottomLeading) {
                CinematicSceneView(
                    projectID: project.id,
                    lines: project.liveLog,
                    phase: project.phase,
                    isActive: project.isRunning || project.isAutoPlaying
                )
                .frame(width: proxy.size.width, height: proxy.size.height)

                LinearGradient(
                    colors: [.black.opacity(0), .black.opacity(0.52)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: max(160, proxy.size.height * 0.28))
                .frame(maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)

                CinematicHUD(caption: caption)
                    .padding(18)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white.opacity(0.08))
            }
        }
        .frame(minHeight: 520)
    }
}

private struct CinematicHUD: View {
    var caption: CinematicCaption

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: caption.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(caption.color)
                Text(caption.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(caption.phase)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.76))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.12), in: Capsule())
            }

            Text(caption.detail)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 620, alignment: .leading)
        .background(.black.opacity(0.36), in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(caption.color)
                .frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: 2))
        }
    }
}

private struct CinematicCaption {
    var title: String
    var detail: String
    var phase: String
    var systemImage: String
    var color: Color

    @MainActor
    init(project: CompassProject) {
        let latest = project.liveLog.last
        let currentPhase = project.isPaused ? LoopPhase.paused : project.phase
        phase = currentPhase.rawValue

        if (project.isRunning || project.isAutoPlaying) && Self.isThinking(project: project) {
            title = "The robot wizard is holding the line"
            detail = "Codex is thinking while wards slow the wave."
            systemImage = "brain.head.profile"
            color = .blue
            return
        }

        guard let latest else {
            title = "The arena is quiet"
            detail = "Start a run to wake the dark expedition."
            systemImage = "moon.stars"
            color = .secondary
            return
        }

        let spell = SpellSchool(line: latest)
        color = spell.swiftUIColor
        systemImage = spell.systemImage

        switch latest.status {
        case .running:
            title = "\(spell.name) is being cast"
            detail = Self.detail(for: latest) ?? "An enemy is closing in."
        case .completed:
            title = "\(spell.name) landed"
            detail = Self.detail(for: latest) ?? "The wave breaks for a moment."
        case .failed:
            title = "The spell backfired"
            detail = Self.detail(for: latest) ?? "The arena flashes red."
        case .none:
            title = latest.text.isEmpty ? "The expedition advances" : latest.text
            detail = Self.detail(for: latest) ?? "The wizard watches the next gate."
        }
    }

    @MainActor
    private static func isThinking(project: CompassProject) -> Bool {
        !project.liveLog.contains {
            $0.status == .running && ($0.kind == .command || $0.kind == .fileChange)
        }
    }

    private static func detail(for line: LiveLine) -> String? {
        if let detail = line.detail?.trimmingCharacters(in: .whitespacesAndNewlines),
           !detail.isEmpty {
            return detail
                .split(whereSeparator: \.isNewline)
                .first
                .map(String.init)
        }
        return line.text.isEmpty ? nil : line.text
    }
}


enum SpellSchool: Equatable {
    case scan
    case shell
    case edit
    case git
    case verify
    case insight
    case lifecycle
    case pressure
    case failure

    init(line: LiveLine) {
        if line.status == .failed || line.level == .error {
            self = .failure
            return
        }

        switch line.kind {
        case .command:
            self = SpellSchool.command(line.detail ?? line.text)
        case .fileChange:
            self = .edit
        case .agentMessage:
            self = .insight
        case .lifecycle:
            self = .lifecycle
        case .message:
            self = .shell
        }
    }

    var name: String {
        switch self {
        case .scan: return "Search spell"
        case .shell: return "Shell spell"
        case .edit: return "Forge spell"
        case .git: return "History spell"
        case .verify: return "Seal spell"
        case .insight: return "Insight spell"
        case .lifecycle: return "Gate spell"
        case .pressure: return "Pressure"
        case .failure: return "Backlash"
        }
    }

    var systemImage: String {
        switch self {
        case .scan: return "magnifyingglass"
        case .shell: return "terminal"
        case .edit: return "hammer"
        case .git: return "point.3.connected.trianglepath.dotted"
        case .verify: return "checkmark.seal"
        case .insight: return "sparkles"
        case .lifecycle: return "circle.hexagongrid"
        case .pressure: return "flame"
        case .failure: return "exclamationmark.triangle"
        }
    }

    var nsColor: NSColor {
        switch self {
        case .scan:
            return NSColor(calibratedRed: 0.18, green: 0.64, blue: 1.0, alpha: 1)
        case .shell:
            return NSColor(calibratedRed: 0.58, green: 0.44, blue: 1.0, alpha: 1)
        case .edit:
            return NSColor(calibratedRed: 0.15, green: 0.96, blue: 0.72, alpha: 1)
        case .git:
            return NSColor(calibratedRed: 0.46, green: 0.95, blue: 0.3, alpha: 1)
        case .verify:
            return NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.2, alpha: 1)
        case .insight:
            return NSColor(calibratedRed: 0.86, green: 0.52, blue: 1.0, alpha: 1)
        case .lifecycle:
            return NSColor(calibratedRed: 0.32, green: 0.84, blue: 1.0, alpha: 1)
        case .pressure:
            return NSColor(calibratedRed: 1.0, green: 0.22, blue: 0.18, alpha: 1)
        case .failure:
            return NSColor(calibratedRed: 1.0, green: 0.12, blue: 0.18, alpha: 1)
        }
    }

    var swiftUIColor: Color {
        Color(nsColor)
    }

    var enemyGlow: NSColor {
        nsColor.withAlphaComponent(0.38)
    }

    private static func command(_ detail: String) -> SpellSchool {
        let lowercased = detail.lowercased()
        if lowercased.contains("swift test")
            || lowercased.contains("swift build")
            || lowercased.contains("npm test")
            || lowercased.contains("pytest")
            || lowercased.contains("cargo test")
            || lowercased.contains("verify") {
            return .verify
        }
        if lowercased.contains("git ") {
            return .git
        }
        if lowercased.contains("rg ")
            || lowercased.contains("grep")
            || lowercased.contains("find ")
            || lowercased.contains("ls ")
            || lowercased.contains("sed ")
            || lowercased.contains("cat ") {
            return .scan
        }
        return .shell
    }
}
