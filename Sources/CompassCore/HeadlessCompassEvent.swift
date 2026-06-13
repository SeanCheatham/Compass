import Foundation

public struct HeadlessCompassEvent: Codable, Equatable, Sendable {
  public var timestamp: String
  public var kind: String
  public var level: String
  public var status: String?
  public var phase: String?
  public var message: String
  public var detail: String?
  public var metadata: [String: String]?

  public init(
    kind: String,
    level: String = "info",
    status: String? = nil,
    phase: String? = nil,
    message: String,
    detail: String? = nil,
    metadata: [String: String]? = nil,
    timestamp: Date = Date()
  ) {
    self.timestamp = HeadlessCompassEvent.timestampFormatter.string(from: timestamp)
    self.kind = kind
    self.level = level
    self.status = status
    self.phase = phase
    self.message = message
    self.detail = detail
    self.metadata = metadata
  }

  private static let timestampFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()
}

package extension HeadlessCompassEvent {
  init(live event: LiveEvent, phase: AgentPhase) {
    let metadata = event.metadata
    let mappedKind: String
    if event.kind == .agentMessage, event.text == "Assistant JSON" {
      mappedKind = "assistant_json"
    } else if event.kind == .agentMessage, event.status == .completed,
      event.text.hasSuffix("_submit")
    {
      mappedKind = "submit_accepted"
    } else if event.kind == .agentMessage, event.status == .failed {
      mappedKind = event.text.contains("rejected") ? "submit_rejected" : "continuation_repair"
    } else if metadata?["tool"] != nil {
      mappedKind = event.status == .running ? "tool_start" : "tool_end"
    } else {
      mappedKind = event.kind.jsonName
    }

    self.init(
      kind: mappedKind,
      level: event.level.jsonName,
      status: event.status.jsonName,
      phase: phase.rawValue,
      message: event.text,
      detail: event.detail,
      metadata: metadata
    )
  }
}

package extension LiveLine.Level {
  var jsonName: String {
    switch self {
    case .info: return "info"
    case .success: return "success"
    case .warning: return "warning"
    case .error: return "error"
    case .raw: return "raw"
    }
  }
}

package extension LiveLine.Kind {
  var jsonName: String {
    switch self {
    case .message: return "message"
    case .lifecycle: return "lifecycle"
    case .command: return "command"
    case .agentMessage: return "agent_message"
    case .fileChange: return "file_change"
    }
  }
}

package extension LiveLine.Status {
  var jsonName: String? {
    switch self {
    case .none: return nil
    case .running: return "running"
    case .completed: return "completed"
    case .failed: return "failed"
    }
  }
}
