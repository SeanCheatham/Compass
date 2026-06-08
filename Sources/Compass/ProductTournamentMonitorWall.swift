import Foundation

struct ProductTournamentMonitorWall: Equatable {
  var tiles: [ProductTournamentMonitorTile]

  var isEmpty: Bool {
    tiles.isEmpty
  }

  var screenshotCount: Int {
    tiles.filter(\.isScreenshotBacked).count
  }

  var evidenceCount: Int {
    tiles.filter { $0.source == .evidenceRun || $0.source == .planEvaluation }.count
  }

  var sessionScreenshotCount: Int {
    tiles.filter { $0.source == .sessionVisualProof }.count
  }

  static func build(
    config: ProductTournamentConfig,
    evidenceIndex: ProductTournamentEvidenceIndex,
    workspace: CompassWorkspace?,
    sessions: [SessionRecord],
    limit: Int = 36
  ) -> ProductTournamentMonitorWall {
    let builder = ProductTournamentMonitorWallBuilder(
      config: config,
      evidenceIndex: evidenceIndex,
      workspace: workspace,
      sessions: sessions
    )
    return ProductTournamentMonitorWall(
      tiles: Array(builder.tiles().prefix(max(1, limit)))
    )
  }
}

struct ProductTournamentMonitorTile: Equatable, Identifiable {
  enum Source: String, Equatable {
    case evidenceRun
    case planEvaluation
    case sessionVisualProof
    case repositoryVisualProof

    var label: String {
      switch self {
      case .evidenceRun: return "Evidence run"
      case .planEvaluation: return "Plan proof"
      case .sessionVisualProof: return "Visual proof"
      case .repositoryVisualProof: return "Latest visual"
      }
    }
  }

  var id: String
  var source: Source
  var title: String
  var subtitle: String
  var detail: String
  var statusLabel: String
  var tone: ProductSignalTone
  var systemImage: String
  var imageURL: URL?
  var artifactPath: String?
  var experimentID: String?
  var contenderID: String?
  var runID: String?
  var planEvaluationID: String?
  var scenarioID: String?
  var personaID: String?
  var roundLabel: String?
  var branchLabel: String?
  var commitLabel: String?
  var timestamp: Double

  var isScreenshotBacked: Bool {
    imageURL != nil
  }
}

private struct ProductTournamentMonitorWallBuilder {
  var config: ProductTournamentConfig
  var evidenceIndex: ProductTournamentEvidenceIndex
  var workspace: CompassWorkspace?
  var sessions: [SessionRecord]

  private var experimentsByID: [String: ProductTournamentExperiment] {
    Dictionary(uniqueKeysWithValues: config.tournamentExperiments.map { ($0.id, $0) })
  }

  private var contendersByID: [String: ProductTournamentContender] {
    Dictionary(uniqueKeysWithValues: config.tournamentContenders.map { ($0.id, $0) })
  }

  private var contendersByExperimentID: [String: ProductTournamentContender] {
    Dictionary(
      uniqueKeysWithValues: config.tournamentContenders.compactMap { contender in
        contender.experimentID.map { ($0, contender) }
      }
    )
  }

  private var roundsByID: [String: ProductTournamentRound] {
    Dictionary(uniqueKeysWithValues: config.tournamentRounds.map { ($0.id, $0) })
  }

  private var scenariosByID: [String: ProductScenario] {
    Dictionary(uniqueKeysWithValues: config.scenarios.map { ($0.id, $0) })
  }

  func tiles() -> [ProductTournamentMonitorTile] {
    var seen = Set<String>()
    var result: [ProductTournamentMonitorTile] = []

    for tile in evidenceRunTiles() + planEvaluationTiles() + sessionScreenshotTiles()
      + repositoryVisualProofTiles()
    {
      let key = tile.imageURL?.standardizedFileURL.path ?? tile.id
      guard seen.insert(key).inserted else { continue }
      result.append(tile)
    }

    return result.sorted { lhs, rhs in
      if lhs.timestamp == rhs.timestamp { return lhs.id < rhs.id }
      return lhs.timestamp > rhs.timestamp
    }
  }

  private func evidenceRunTiles() -> [ProductTournamentMonitorTile] {
    evidenceIndex.summaries.map { summary in
      let record = try? workspace?.readProductTournamentEvidenceRecord(id: summary.runID)
      let contender =
        summary.contenderID.flatMap { contendersByID[$0] }
        ?? contendersByExperimentID[summary.experimentID]
      let experiment = experimentsByID[summary.experimentID]
      let scenario = scenariosByID[summary.scenarioID]
      let imageURL = runImageURL(runID: summary.runID, record: record)
      let title = contender?.title ?? experiment?.title ?? "Tournament run"
      let subtitle = scenario?.title ?? summary.scenarioID
      return ProductTournamentMonitorTile(
        id: "evidence:\(summary.runID)",
        source: .evidenceRun,
        title: bounded(title, limit: 90),
        subtitle: bounded(subtitle, limit: 120),
        detail: bounded(summary.summary, limit: 220),
        statusLabel: evidenceStatusLabel(summary),
        tone: tone(status: summary.status, verdict: summary.verdict),
        systemImage: summary.completedUseProof
          ? ProductIconRole.useProof.systemImage : "play.display",
        imageURL: imageURL,
        artifactPath: record?.summaryArtifactPath ?? record?.traceArtifactPath,
        experimentID: summary.experimentID,
        contenderID: contender?.id ?? summary.contenderID,
        runID: summary.runID,
        planEvaluationID: nil,
        scenarioID: summary.scenarioID,
        personaID: summary.personaID,
        roundLabel: roundLabel(roundID: summary.roundID),
        branchLabel: summary.branchName,
        commitLabel: shortCommit(summary.commitSha),
        timestamp: summary.endedAt
      )
    }
  }

  private func planEvaluationTiles() -> [ProductTournamentMonitorTile] {
    evidenceIndex.planEvaluationSummaries.map { summary in
      let contender = contendersByID[summary.contenderID]
      let imageURL = planEvaluationImageURL(evaluationID: summary.evaluationID)
      return ProductTournamentMonitorTile(
        id: "plan:\(summary.evaluationID)",
        source: .planEvaluation,
        title: bounded(contender?.title ?? "Plan proof", limit: 90),
        subtitle: bounded(summary.personaName, limit: 120),
        detail: bounded(summary.summary, limit: 220),
        statusLabel: evidenceStatusLabel(summary),
        tone: tone(status: summary.status, verdict: summary.verdict),
        systemImage: "person.2.wave.2",
        imageURL: imageURL,
        artifactPath: planEvaluationSummaryPath(evaluationID: summary.evaluationID),
        experimentID: summary.experimentID,
        contenderID: summary.contenderID,
        runID: nil,
        planEvaluationID: summary.evaluationID,
        scenarioID: nil,
        personaID: summary.personaID,
        roundLabel: roundLabel(roundID: summary.roundID),
        branchLabel: summary.experimentID.flatMap { experimentsByID[$0]?.branchName },
        commitLabel: summary.experimentID.flatMap { experimentsByID[$0]?.currentSha }.map(
          shortCommit),
        timestamp: summary.endedAt
      )
    }
  }

  private func sessionScreenshotTiles() -> [ProductTournamentMonitorTile] {
    guard let workspace else { return [] }
    let recentSessions =
      sessions
      .sorted { lhs, rhs in
        let lhsEnded = lhs.endedAt ?? lhs.startedAt
        let rhsEnded = rhs.endedAt ?? rhs.startedAt
        if lhsEnded == rhsEnded { return lhs.session > rhs.session }
        return lhsEnded > rhsEnded
      }
      .prefix(80)
    return recentSessions.flatMap { session -> [ProductTournamentMonitorTile] in
      guard let manifest = workspace.readSessionAuditManifest(session: session.session) else {
        return []
      }
      return manifest.artifacts.compactMap { artifact in
        guard isImagePath(artifact.path) else { return nil }
        let kind = artifact.kind.lowercased()
        guard kind.contains("screenshot") || kind.contains("visual") || kind.contains("image")
        else { return nil }
        let url = workspace.compassURL.appending(path: artifact.path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let experimentID = session.tournamentExperimentID
        let contender = experimentID.flatMap { contendersByExperimentID[$0] }
        return ProductTournamentMonitorTile(
          id: "session:\(session.session):\(artifact.path)",
          source: .sessionVisualProof,
          title: bounded(contender?.title ?? "Session \(session.session) visual proof", limit: 90),
          subtitle: bounded(artifact.note ?? artifact.kind, limit: 120),
          detail: bounded(
            session.plan ?? session.notes.first ?? "Captured visual verification artifact.",
            limit: 220),
          statusLabel: ProductPresentationLanguage.sessionStatusLabel(session.status),
          tone: sessionTone(session.status),
          systemImage: "display",
          imageURL: url,
          artifactPath: artifact.path,
          experimentID: experimentID,
          contenderID: contender?.id,
          runID: session.tournamentEvidenceRunIDs.first,
          planEvaluationID: nil,
          scenarioID: nil,
          personaID: nil,
          roundLabel: nil,
          branchLabel: session.tournamentExperimentBranchName,
          commitLabel: (session.tournamentExperimentAfterSha
            ?? session.tournamentExperimentCommitSha)
            .map(shortCommit),
          timestamp: artifact.createdAt / 1000
        )
      }
    }
  }

  private func repositoryVisualProofTiles() -> [ProductTournamentMonitorTile] {
    guard let workspace else { return [] }
    let candidates = [
      workspace.repoURL.appending(path: ".compass/visual-verify/latest.png"),
      workspace.repoURL.appending(path: ".compass/visual-verify/screenshot.png"),
      workspace.compassURL.appending(path: "visual-verify/latest.png"),
      workspace.compassURL.appending(path: "visual-verify/screenshot.png"),
    ]
    return candidates.compactMap { url in
      guard FileManager.default.fileExists(atPath: url.path) else { return nil }
      let timestamp =
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate])
        as? Date
      return ProductTournamentMonitorTile(
        id: "visual:\(url.standardizedFileURL.path)",
        source: .repositoryVisualProof,
        title: "Latest visual verification",
        subtitle: "Repository viewport screenshot",
        detail: "Most recent generated app screenshot captured by visual verification.",
        statusLabel: "Captured",
        tone: .progressing,
        systemImage: "display",
        imageURL: url,
        artifactPath: relativePath(url: url, workspace: workspace),
        experimentID: nil,
        contenderID: nil,
        runID: nil,
        planEvaluationID: nil,
        scenarioID: nil,
        personaID: nil,
        roundLabel: nil,
        branchLabel: nil,
        commitLabel: nil,
        timestamp: timestamp?.timeIntervalSince1970 ?? 0
      )
    }
  }

  private func runImageURL(
    runID: String,
    record: ProductTournamentEvidenceRecord?
  ) -> URL? {
    guard let workspace else { return nil }
    let runURL = workspace.productTournamentEvidenceStore.runsURL
      .appending(path: ProductTournamentEvidenceStore.safeRunID(runID), directoryHint: .isDirectory)
    return firstImageURL(in: runURL)
      ?? firstImageURL(
        from: [
          record?.summaryArtifactPath,
          record?.traceArtifactPath,
          record?.feedbackArtifactPath,
          record?.transcriptArtifactPath,
        ], workspace: workspace)
  }

  private func planEvaluationImageURL(evaluationID: String) -> URL? {
    guard let workspace else { return nil }
    let url = workspace.productTournamentEvidenceStore.planEvaluationsURL
      .appending(
        path: ProductTournamentEvidenceStore.safeRunID(evaluationID),
        directoryHint: .isDirectory
      )
    return firstImageURL(in: url)
  }

  private func planEvaluationSummaryPath(evaluationID: String) -> String? {
    guard let workspace,
      let record = try? workspace.readProductTournamentPlanEvaluationRecord(id: evaluationID)
    else { return nil }
    return record.summaryArtifactPath
  }

  private func firstImageURL(from paths: [String?], workspace: CompassWorkspace) -> URL? {
    for path in paths.compactMap(\.self) where isImagePath(path) {
      let url = workspace.compassURL.appending(path: path)
      if FileManager.default.fileExists(atPath: url.path) {
        return url
      }
    }
    return nil
  }

  private func firstImageURL(in directory: URL) -> URL? {
    guard
      let urls = try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: [.skipsHiddenFiles]
      )
    else { return nil }
    return
      urls
      .filter { isImagePath($0.path) }
      .sorted { lhs, rhs in
        let lhsDate =
          (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
          ?? .distantPast
        let rhsDate =
          (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
          ?? .distantPast
        if lhsDate == rhsDate { return lhs.lastPathComponent < rhs.lastPathComponent }
        return lhsDate > rhsDate
      }
      .first
  }

  private func roundLabel(roundID: String?) -> String? {
    guard let roundID, let round = roundsByID[roundID] else { return nil }
    return ProductPresentationLanguage.roundLabel(kind: round.kind, ordinal: round.ordinal)
  }

  private func evidenceStatusLabel(_ summary: ProductTournamentEvidenceSummary) -> String {
    summary.isCompleted ? summary.verdict.title : summary.status.rawValue
  }

  private func evidenceStatusLabel(_ summary: ProductTournamentPlanEvaluationSummary) -> String {
    summary.isCompleted ? summary.verdict.title : summary.status.rawValue
  }

  private func tone(
    status: ProductTournamentRunStatus,
    verdict: ProductTournamentEvidenceVerdict
  ) -> ProductSignalTone {
    guard status == .completed else { return .blocked }
    switch verdict {
    case .strongPull, .promising:
      return .strong
    case .unclear:
      return .progressing
    case .weak:
      return .risk
    case .rejected:
      return .blocked
    }
  }

  private func isImagePath(_ path: String) -> Bool {
    ["png", "jpg", "jpeg", "webp"].contains(URL(fileURLWithPath: path).pathExtension.lowercased())
  }

  private func sessionTone(_ status: SessionStatus) -> ProductSignalTone {
    switch status {
    case .succeeded:
      return .strong
    case .failed, .rejectedByPlan, .cancelled:
      return .blocked
    case .skipped:
      return .neutral
    case .planning, .awaitingApproval, .developing:
      return .progressing
    }
  }

  private func shortCommit(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed != "unknown" else { return "unknown" }
    return String(trimmed.prefix(8))
  }

  private func bounded(_ value: String, limit: Int) -> String {
    StringUtils.boundedText(value, limit: limit)
  }

  private func relativePath(url: URL, workspace: CompassWorkspace) -> String {
    let path = url.standardizedFileURL.path
    let compass = workspace.compassURL.standardizedFileURL.path + "/"
    let repo = workspace.repoURL.standardizedFileURL.path + "/"
    if path.hasPrefix(compass) {
      return String(path.dropFirst(compass.count))
    }
    if path.hasPrefix(repo) {
      return String(path.dropFirst(repo.count))
    }
    return path
  }
}

extension ProductTournamentEvidenceVerdict {
  fileprivate var title: String {
    switch self {
    case .strongPull:
      return "Strong pull"
    case .promising:
      return "Promising"
    case .unclear:
      return "Unclear"
    case .weak:
      return "Weak"
    case .rejected:
      return "Rejected"
    }
  }
}

extension ProductPresentationLanguage {
  fileprivate static func sessionStatusLabel(_ status: SessionStatus) -> String {
    switch status {
    case .planning:
      return "Planning"
    case .awaitingApproval:
      return "Awaiting approval"
    case .developing:
      return "Developing"
    case .succeeded:
      return "Succeeded"
    case .failed:
      return "Failed"
    case .cancelled:
      return "Cancelled"
    case .rejectedByPlan:
      return "Rejected"
    case .skipped:
      return "Skipped"
    }
  }
}
