import AppKit
import Foundation

@MainActor
extension CompassProject {
  func startSession() -> Int {
    let nextNumber = (sessions.map(\.session).max() ?? 0) + 1
    sessions.append(.started(nextNumber))
    try? persistSessions()
    return sessions.count - 1
  }

  func endSession(_ index: Int, status: SessionStatus) {
    guard sessions.indices.contains(index) else { return }
    sessions[index].status = status
    sessions[index].endedAt = Date().timeIntervalSince1970 * 1000
    try? persistSessions()
  }

  func appendSessionNote(_ note: String, to index: Int) {
    let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, sessions.indices.contains(index) else { return }
    if sessions[index].notes.last != trimmed {
      sessions[index].notes.append(trimmed)
    }
    try? persistSessions()
  }

  func logLessonEdits(_ count: Int) {
    guard count > 0 else { return }
    let noun = count == 1 ? "edit" : "edits"
    log("Applied \(count) lesson \(noun).", level: .success)
  }

  func previousFeedback(excluding session: Int) -> String {
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
      appendSessionNote(error?.localizedDescription ?? "Unknown error", to: sessionIndex)
      endSession(sessionIndex, status: .failed)
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
