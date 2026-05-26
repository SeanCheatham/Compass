import AppKit
import Foundation
import Virtualization

@MainActor
extension CompassProject {
  func log(_ text: String, level: LiveLine.Level) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    let line = LiveLine(level: level, text: trimmed)
    liveLog.append(line)
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
    } else {
      let line = LiveLine(
        level: event.level,
        text: title,
        detail: detail?.isEmpty == false ? detail : nil,
        kind: event.kind,
        status: event.status,
        correlationID: event.correlationID
      )
      liveLog.append(line)
    }

    trimLiveLog()
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
    log(error.localizedDescription, level: .error)
  }

  func tail(_ text: String, max: Int) -> String {
    guard text.count > max else { return text }
    let prefix = "...(truncated)...\n"
    return prefix + String(text.suffix(max - prefix.count))
  }
}
