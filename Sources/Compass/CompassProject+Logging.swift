import AppKit
import CompassCore
import Foundation

@MainActor
extension CompassProject {
  func log(_ text: String, level: LiveLine.Level) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    let line = LiveLine(level: level, text: trimmed)
    liveLog.append(line)
    appendAuditEvent(
      kind: "live_line",
      level: level.auditIdentifier,
      liveKind: LiveLine.Kind.message.auditIdentifier,
      status: LiveLine.Status.none.auditIdentifier,
      text: trimmed
    )
    trimLiveLog()
  }

  func log(_ event: LiveEvent) {
    let title = event.text.trimmingCharacters(in: .whitespacesAndNewlines)
    let detail = event.detail?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty || !(detail?.isEmpty ?? true) else { return }

    if event.status == .completed || event.status == .failed,
      let correlationID = event.correlationID,
      let index = liveLog.lastIndex(where: {
        $0.correlationID == correlationID && $0.status == .running
      })
    {
      liveLog[index].level = event.level
      liveLog[index].text = title.isEmpty ? liveLog[index].text : title
      liveLog[index].detail = detail?.isEmpty == false ? detail : liveLog[index].detail
      liveLog[index].kind = event.kind
      liveLog[index].status = event.status
      liveLog[index].completedAt = Date()
      if let payload = event.payload {
        liveLog[index].payload = payload
      }
      studioState.apply(liveLog[index])
    } else {
      let line = LiveLine(
        level: event.level,
        text: title,
        detail: detail?.isEmpty == false ? detail : nil,
        kind: event.kind,
        status: event.status,
        correlationID: event.correlationID,
        payload: event.payload
      )
      liveLog.append(line)
      studioState.apply(line)
    }

    appendAuditEvent(
      kind: "live_event",
      level: event.level.auditIdentifier,
      liveKind: event.kind.auditIdentifier,
      status: event.status.auditIdentifier,
      correlationID: event.correlationID,
      text: title,
      detail: detail,
      metadata: event.metadata
    )
    trimLiveLog()
  }

  func activateSessionAudit(sessionIndex: Int) {
    guard sessions.indices.contains(sessionIndex) else { return }
    let session = sessions[sessionIndex]
    activeAuditSessionNumber = session.session
    activeAuditEventSequence = workspace?.sessionAuditEventCount(session: session.session) ?? 0
    try? workspace?.updateSessionAuditManifest(
      session: session.session,
      status: session.status,
      startedAt: session.startedAt,
      endedAt: session.endedAt
    )
  }

  func deactivateSessionAuditIfCurrent(session: Int) {
    guard activeAuditSessionNumber == session else { return }
    activeAuditSessionNumber = nil
    activeAuditEventSequence = 0
  }

  func appendAuditEvent(
    kind: String,
    sessionOverride: Int? = nil,
    level: String? = nil,
    liveKind: String? = nil,
    status: String? = nil,
    correlationID: String? = nil,
    text: String? = nil,
    detail: String? = nil,
    artifactPath: String? = nil,
    metadata: [String: String]? = nil
  ) {
    guard let session = sessionOverride ?? activeAuditSessionNumber, let workspace else { return }
    let sequence: Int
    if activeAuditSessionNumber == session {
      activeAuditEventSequence += 1
      sequence = activeAuditEventSequence
    } else {
      sequence = workspace.sessionAuditEventCount(session: session) + 1
    }
    let event = SessionAuditEvent(
      session: session,
      sequence: sequence,
      phase: phase.rawValue,
      kind: kind,
      level: level,
      liveKind: liveKind,
      status: status,
      correlationID: correlationID,
      text: text,
      detail: detail,
      artifactPath: artifactPath,
      metadata: metadata
    )
    try? workspace.appendSessionAuditEvent(event)
  }

  func recordSessionAuditArtifactEvent(
    session: Int,
    kind: String,
    artifactURL: URL,
    note: String? = nil,
    metadata: [String: String]? = nil
  ) {
    guard let workspace else { return }
    let path = workspace.sessionAuditRelativePath(
      session: session,
      fileName: artifactURL.lastPathComponent
    )
    appendAuditEvent(
      kind: kind,
      sessionOverride: session,
      status: "completed",
      text: note,
      artifactPath: path,
      metadata: metadata
    )
  }

  func trimLiveLog() {
    if liveLog.count > 800 {
      liveLog.removeFirst(liveLog.count - 800)
    }
  }

  func firstLine(_ text: String?) -> String? {
    text?
      .split(whereSeparator: \.isNewline)
      .first
      .map(String.init)
  }

  func fail(_ error: Error) {
    errorMessage = error.localizedDescription
    log(Self.detailedDescription(of: error), level: .error)
  }

  /// `Error.localizedDescription` collapses every `DecodingError` to a useless
  /// "The data couldn't be read…" string. Surface the coding path and reason so
  /// a schema-mismatched JSON file (e.g. a missing key in state.json) is
  /// actually diagnosable from the event log.
  static func detailedDescription(of error: Error) -> String {
    guard let decodingError = error as? DecodingError else {
      return error.localizedDescription
    }
    func location(_ context: DecodingError.Context) -> String {
      let path = context.codingPath.map(\.stringValue).joined(separator: ".")
      return path.isEmpty ? "root" : path
    }
    switch decodingError {
    case .keyNotFound(let key, let context):
      return "Decode failed: missing key '\(key.stringValue)' at \(location(context))."
    case .valueNotFound(_, let context):
      return "Decode failed: missing value at \(location(context)). \(context.debugDescription)"
    case .typeMismatch(_, let context):
      return "Decode failed: type mismatch at \(location(context)). \(context.debugDescription)"
    case .dataCorrupted(let context):
      return "Decode failed: corrupted data at \(location(context)). \(context.debugDescription)"
    @unknown default:
      return decodingError.localizedDescription
    }
  }

  func tail(_ text: String, max: Int) -> String {
    guard text.count > max else { return text }
    let prefix = "...(truncated)...\n"
    return prefix + String(text.suffix(max - prefix.count))
  }
}

extension LiveLine.Level {
  var auditIdentifier: String {
    switch self {
    case .info: return "info"
    case .success: return "success"
    case .warning: return "warning"
    case .error: return "error"
    case .raw: return "raw"
    }
  }
}

extension LiveLine.Kind {
  var auditIdentifier: String {
    switch self {
    case .message: return "message"
    case .lifecycle: return "lifecycle"
    case .command: return "command"
    case .agentMessage: return "agent_message"
    case .fileChange: return "file_change"
    }
  }
}

extension LiveLine.Status {
  var auditIdentifier: String {
    switch self {
    case .none: return "none"
    case .running: return "running"
    case .completed: return "completed"
    case .failed: return "failed"
    }
  }
}
