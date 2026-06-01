import Foundation

struct FactorySettingsGuide: Equatable, Sendable {
  static let detailLimit = 280
  static let rowDetailLimit = 190
  static let identifierLimit = 1_600

  enum Tone: String, Equatable, Sendable {
    case ready
    case attention
    case empty
  }

  enum RowStatus: String, Equatable, Sendable {
    case ready
    case recommended
    case off
  }

  struct Project: Identifiable, Equatable, Sendable {
    var id: UUID
    var displayName: String
    var hostXcodeBuildTestEnabled: Bool
    var recommendsHostXcode: Bool
    var isSelected: Bool
  }

  struct Row: Identifiable, Equatable, Sendable {
    var id: String
    var label: String
    var detail: String
    var status: RowStatus
  }

  var title: String
  var detail: String
  var actionLabel: String
  var tone: Tone
  var systemImageName: String
  var rows: [Row]
  var narrationIdentifier: String

  init(projects: [Project]) {
    let sortedProjects = projects.sorted {
      $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
    }
    let recommendedOff = sortedProjects.filter {
      $0.recommendsHostXcode && !$0.hostXcodeBuildTestEnabled
    }
    let enabledCount = sortedProjects.filter(\.hostXcodeBuildTestEnabled).count

    if sortedProjects.isEmpty {
      title = "Add a Project"
      detail =
        "Add a Git repository from the sidebar before Compass can tune build and test routing."
      actionLabel = "No projects"
      tone = .empty
      systemImageName = "folder.badge.plus"
    } else if !recommendedOff.isEmpty {
      title =
        recommendedOff.count == 1
        ? "Factory Needs One Toggle"
        : "Factory Needs \(recommendedOff.count) Toggles"
      detail =
        "Swift and Xcode projects verify most reliably through full Xcode on this Mac. Enable Host Xcode Build/Test on recommended rows so agents use the right route."
      actionLabel = "\(recommendedOff.count) recommended"
      tone = .attention
      systemImageName = "hammer.circle"
    } else if enabledCount > 0 {
      title = "Factory Verification Ready"
      detail =
        "Host Xcode Build/Test is enabled for the projects that need full Xcode, while Develop still edits inside the private workspace."
      actionLabel = "Ready"
      tone = .ready
      systemImageName = "checkmark.seal.fill"
    } else {
      title = "Factory Defaults Ready"
      detail =
        "No current project looks like it needs full Xcode routing. Keep Host Xcode Build/Test off until Compass marks it recommended."
      actionLabel = "Ready"
      tone = .ready
      systemImageName = "checkmark.seal.fill"
    }

    detail = StringUtils.boundedText(detail, limit: Self.detailLimit)
    rows = Self.rows(for: sortedProjects)
    narrationIdentifier = Self.narrationIdentifier(
      title: title,
      detail: detail,
      actionLabel: actionLabel,
      tone: tone,
      systemImageName: systemImageName,
      rows: rows
    )
  }

  private static func rows(for projects: [Project]) -> [Row] {
    guard !projects.isEmpty else {
      return [
        Row(
          id: "projects",
          label: "Projects",
          detail: "Add a repository to configure factory routing.",
          status: .off
        )
      ]
    }

    return projects.map { project in
      Row(
        id: project.id.uuidString,
        label: label(for: project),
        detail: rowDetail(for: project),
        status: rowStatus(for: project)
      )
    }
  }

  private static func label(for project: Project) -> String {
    project.isSelected ? "\(project.displayName) (selected)" : project.displayName
  }

  private static func rowDetail(for project: Project) -> String {
    let detail: String
    if project.hostXcodeBuildTestEnabled {
      detail =
        "Host Xcode Build/Test is on; Swift and Xcode verify steps can use full Xcode on this Mac."
    } else if project.recommendsHostXcode {
      detail =
        "Recommended for this repo; enable it before agents plan Swift or Xcode build/test verification."
    } else {
      detail = "Off for this repo; no SwiftPM, Xcode project, or workspace signal was detected."
    }
    return StringUtils.boundedText(detail, limit: Self.rowDetailLimit)
  }

  private static func rowStatus(for project: Project) -> RowStatus {
    if project.hostXcodeBuildTestEnabled { return .ready }
    if project.recommendsHostXcode { return .recommended }
    return .off
  }

  private static func narrationIdentifier(
    title: String,
    detail: String,
    actionLabel: String,
    tone: Tone,
    systemImageName: String,
    rows: [Row]
  ) -> String {
    let raw = [
      "title:\(title)",
      "detail:\(detail)",
      "action:\(actionLabel)",
      "tone:\(tone.rawValue)",
      "image:\(systemImageName)",
      "rows:\(rows.map { "\($0.id):\($0.status.rawValue):\($0.detail)" }.joined(separator: ","))",
    ].joined(separator: "|")

    return StringUtils.boundedText(raw, limit: Self.identifierLimit)
  }
}

struct FactorySettingsClipboardPayload: Equatable, Sendable {
  static let textLimit = 3_200

  var text: String

  init(guide: FactorySettingsGuide) {
    var sections: [String] = [
      "Compass Factory Settings Handoff",
      "",
      "Recipient instructions:",
      "- Treat this packet as bounded factory-routing context. Do not invent projects, "
        + "repo paths, build commands, Xcode availability, verification results, or hidden toggles.",
      "- Host Xcode Build/Test changes the verification route only; agents still edit inside "
        + "the private workspace.",
      "- Recommended rows should be enabled before Swift or Xcode build/test verification is "
        + "planned. Off rows can stay off unless new repo evidence appears.",
      "",
      "Status: \(guide.title) (\(guide.tone.rawValue))",
      "Action: \(guide.actionLabel)",
      "Detail: \(guide.detail)",
      "Rows: \(Self.countSummary(guide.rows))",
      "",
      "Projects:",
    ]

    for row in guide.rows {
      sections.append("- [\(row.status.rawValue)] \(row.label): \(row.detail)")
    }

    text = FactorySettingsClipboardText.boundedMultilineText(
      sections.joined(separator: "\n"),
      limit: Self.textLimit
    )
  }

  var isEmpty: Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private static func countSummary(_ rows: [FactorySettingsGuide.Row]) -> String {
    let ready = rows.filter { $0.status == .ready }.count
    let recommended = rows.filter { $0.status == .recommended }.count
    let off = rows.filter { $0.status == .off }.count
    return "\(ready) ready, \(recommended) recommended, \(off) off"
  }
}

private enum FactorySettingsClipboardText {
  static func boundedMultilineText(_ text: String, limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard text.count > limit else { return text }
    guard limit > 3 else { return String(text.prefix(limit)) }

    return String(text.prefix(limit - 3))
      .trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }
}
