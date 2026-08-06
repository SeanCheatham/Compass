import Foundation

public struct LiveLineRangeEdit: Equatable {
  public var startLine: Int
  public var endLine: Int
  public var replacementLines: [String]

  public init(startLine: Int, endLine: Int, replacementLines: [String]) {
    self.startLine = startLine
    self.endLine = endLine
    self.replacementLines = replacementLines
  }
}

public struct LiveStringReplaceEdit: Equatable {
  public var oldString: String
  public var newString: String
  public var replaceAll: Bool

  public init(oldString: String, newString: String, replaceAll: Bool) {
    self.oldString = oldString
    self.newString = newString
    self.replaceAll = replaceAll
  }
}

/// Structured tool-call payloads retained in memory for the Studio view.
/// `content`/`output` are nil on tool-start events and filled on tool end.
public enum LiveToolPayload: Equatable {
  case readFile(path: String, offset: Int?, limit: Int?, content: String?)
  case writeFile(path: String, content: String)
  case editFileLineRange(path: String, edits: [LiveLineRangeEdit])
  case editFileStringReplace(path: String, edits: [LiveStringReplaceEdit])
  case bash(command: String, cwd: String?, output: String?, isError: Bool?)
  /// Model chain-of-thought (`reasoning_content` / `<think>` blocks).
  case thinking(text: String, phase: AgentPhase)

  public var path: String? {
    switch self {
    case .readFile(let path, _, _, _),
      .writeFile(let path, _),
      .editFileLineRange(let path, _),
      .editFileStringReplace(let path, _):
      return path
    case .bash, .thinking:
      return nil
    }
  }
}

public struct LiveLine: Identifiable, Equatable {
  public var id = UUID()
  public var date = Date()
  public var level: Level
  public var text: String
  public var detail: String?
  public var kind: Kind = .message
  public var status: Status = .none
  public var correlationID: String?
  public var completedAt: Date?
  public var payload: LiveToolPayload?

  public init(
    id: UUID = UUID(),
    date: Date = Date(),
    level: Level,
    text: String,
    detail: String? = nil,
    kind: Kind = .message,
    status: Status = .none,
    correlationID: String? = nil,
    completedAt: Date? = nil,
    payload: LiveToolPayload? = nil
  ) {
    self.id = id
    self.date = date
    self.level = level
    self.text = text
    self.detail = detail
    self.kind = kind
    self.status = status
    self.correlationID = correlationID
    self.completedAt = completedAt
    self.payload = payload
  }

  public enum Level {
    case info
    case success
    case warning
    case error
    case raw
  }

  public enum Kind {
    case message
    case lifecycle
    case command
    case agentMessage
    case fileChange
  }

  public enum Status {
    case none
    case running
    case completed
    case failed
  }
}

public struct LiveEvent: Equatable {
  public var level: LiveLine.Level
  public var text: String
  public var detail: String?
  public var kind: LiveLine.Kind
  public var status: LiveLine.Status
  public var correlationID: String?
  public var metadata: [String: String]?
  public var payload: LiveToolPayload?

  public init(
    level: LiveLine.Level = .info,
    text: String,
    detail: String? = nil,
    kind: LiveLine.Kind = .message,
    status: LiveLine.Status = .none,
    correlationID: String? = nil,
    metadata: [String: String]? = nil,
    payload: LiveToolPayload? = nil
  ) {
    self.level = level
    self.text = text
    self.detail = detail
    self.kind = kind
    self.status = status
    self.correlationID = correlationID
    self.metadata = metadata
    self.payload = payload
  }
}

public enum PauseMode: String, Codable, CaseIterable, Identifiable {
  case immediate
  case afterIteration = "after_iteration"

  public var id: Self { self }

  public var label: String {
    switch self {
    case .immediate:
      return "Pause Now"
    case .afterIteration:
      return "Pause After Iteration"
    }
  }

  public var hint: String {
    switch self {
    case .immediate:
      return "Stop before the next phase gate."
    case .afterIteration:
      return "Let the current Plan and Develop finish first."
    }
  }
}

public enum LoopPhase: String, CaseIterable {
  case idle = "Idle"
  case planning = "Planning"
  case developing = "Developing"
  case verifying = "Verifying"
  case reviewing = "Reviewing"
  case paused = "Paused"
  case failed = "Failed"
  case succeeded = "Succeeded"
  case cancelled = "Cancelled"
}
