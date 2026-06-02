import AppKit
import Foundation

@MainActor
extension CompassProject {
  func startSession() -> Int {
    let storeMax = workspace?.maxSessionNumber() ?? 0
    let memoryMax = sessions.map(\.session).max() ?? 0
    let nextNumber = max(storeMax, memoryMax) + 1
    sessions.append(.started(nextNumber))
    try? persistSessions()
    let index = sessions.count - 1
    activateSessionAudit(sessionIndex: index)
    appendAuditEvent(
      kind: "session_started",
      status: sessions[index].status.rawValue,
      text: "Session #\(nextNumber) started."
    )
    return index
  }

  func endSession(_ index: Int, status: SessionStatus) {
    guard sessions.indices.contains(index) else { return }
    sessions[index].status = status
    sessions[index].endedAt = Date().timeIntervalSince1970 * 1000
    activateSessionAudit(sessionIndex: index)
    try? workspace?.updateSessionAuditManifest(
      session: sessions[index].session,
      status: status,
      startedAt: sessions[index].startedAt,
      endedAt: sessions[index].endedAt
    )
    appendAuditEvent(
      kind: "session_ended",
      status: status.rawValue,
      text: "Session #\(sessions[index].session) ended with status \(status.rawValue)."
    )
    try? persistSessions()
    deactivateSessionAuditIfCurrent(session: sessions[index].session)
  }

  func appendSessionNote(_ note: String, to index: Int) {
    let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, sessions.indices.contains(index) else { return }
    if sessions[index].notes.last != trimmed {
      sessions[index].notes.append(trimmed)
      let previousAuditSession = activeAuditSessionNumber
      let previousAuditSequence = activeAuditEventSequence
      activateSessionAudit(sessionIndex: index)
      appendAuditEvent(
        kind: "session_note",
        status: sessions[index].status.rawValue,
        text: trimmed
      )
      if previousAuditSession != sessions[index].session {
        activeAuditSessionNumber = previousAuditSession
        activeAuditEventSequence = previousAuditSequence
      }
    }
    try? persistSessions()
  }

  func logLessonEdits(_ count: Int) {
    guard count > 0 else { return }
    let noun = count == 1 ? "edit" : "edits"
    log("Applied \(count) lesson \(noun).", level: .success)
  }

  func previousFeedback(excluding session: Int) -> String {
    if let feedback = workspace?.previousSessionFeedback(
      excluding: session,
      activeSessions: sessions
    ), !feedback.isEmpty {
      return feedback
    }
    return
      sessions
      .filter { $0.session != session && $0.endedAt != nil }
      .sorted { $0.startedAt > $1.startedAt }
      .compactMap { $0.feedback?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty } ?? ""
  }

  func persistSessions() throws {
    try workspace?.writeSessions(sessions)
  }

  func performSessionErrorCleanup(sessionIndex: Int, error: Error?) {
    if stopRequested {
      stopRequested = false
      appendSessionNote("Stopped by user.", to: sessionIndex)
      endSession(sessionIndex, status: .cancelled)
      phase = .cancelled
      log("Run stopped.", level: .warning)
      feedback(.stopped)
    } else {
      let failedStatus: SessionStatus
      if let error = error as? AppModelError, case .rejectedPlan = error {
        failedStatus = .rejectedByPlan
      } else {
        failedStatus = .failed
      }
      appendSessionNote(error?.localizedDescription ?? "Unknown error", to: sessionIndex)
      endSession(sessionIndex, status: failedStatus)
      phase = .failed
      fail(error ?? AppModelError.internalInvariant("Unknown error in session cleanup."))
    }
    isRunning = false
    executor = nil
  }

  func latestAwaitingDevelopSessionIndex() -> Int? {
    sessions.indices
      .filter { sessions[$0].status == .awaitingApproval && sessions[$0].endedAt == nil }
      .max { sessions[$0].session < sessions[$1].session }
  }
}
