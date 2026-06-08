import Foundation

struct CompassDaemonRequest: Encodable {
  var schemaVersion = 1
  var id: String
  var method: String
  var params: [String: String] = [:]

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case id
    case method
    case params
  }
}

struct CompassDaemonJSONRequest<Params: Encodable>: Encodable {
  var schemaVersion = 1
  var id: String
  var method: String
  var params: Params

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case id
    case method
    case params
  }
}

struct CompassDaemonResponse<Result: Decodable>: Decodable {
  var schemaVersion: Int
  var id: String
  var ok: Bool
  var result: Result?
  var errors: [String]

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case id
    case ok
    case result
    case errors
  }
}

struct CompassDaemonPing: Decodable, Equatable {
  var compassdVersion: String
  var coreVersion: String
  var schemaVersion: Int
}

struct CompassDaemonCapabilities: Decodable, Equatable {
  var compassdVersion: String
  var coreVersion: String
  var schemaVersion: Int
  var methods: [String]
  var capabilities: [String]
}

struct CompassDaemonEmptyResult: Decodable, Equatable {}

struct CompassDaemonTournamentValidation: Decodable, Equatable {
  var ok: Bool
  var statePath: String
  var errors: [String]
}

struct CompassDaemonTournamentReadModel: Decodable, Equatable {
  var schemaVersion: Int
  var painTitle: String?
  var activeRoundID: String?
  var activeRoundTitle: String?
  var outcomeWinnerContenderID: String?
  var segmentCount: Int
  var alternativeCount: Int
  var contenderCount: Int
  var roundCount: Int
  var decisionCount: Int
  var contenders: [CompassDaemonTournamentContenderSummary]
  var rounds: [CompassDaemonTournamentRoundSummary]
  var validationErrors: [String]

  enum CodingKeys: String, CodingKey {
    case schemaVersion
    case painTitle
    case activeRoundID = "activeRoundId"
    case activeRoundTitle
    case outcomeWinnerContenderID = "outcomeWinnerContenderId"
    case segmentCount
    case alternativeCount
    case contenderCount
    case roundCount
    case decisionCount
    case contenders
    case rounds
    case validationErrors
  }
}

struct CompassDaemonTournamentContenderSummary: Decodable, Equatable {
  var id: String
  var title: String
  var lifecycle: String
}

struct CompassDaemonTournamentRoundSummary: Decodable, Equatable {
  var id: String
  var ordinal: Int
  var kind: String
  var title: String
  var lifecycle: String
  var contenderCount: Int
}

struct CompassDaemonAgentRunConfig: Encodable, Equatable {
  var repoPath: String
  var phase: String
  var systemPrompt: String
  var userPrompt: String
  var settings: [String: String] = [:]
  var tools: [String] = []
  var maxIterations: Int = 40
  var wallClockTimeoutSecs: Int = 3_600
}

struct CompassDaemonAgentRunStart: Decodable, Equatable {
  var runID: String

  enum CodingKeys: String, CodingKey {
    case runID = "runId"
  }
}

struct CompassDaemonAgentRunStatus: Decodable, Equatable {
  var runID: String
  var phase: String
  var status: String
  var iteration: Int
  var elapsedMs: Int
  var resultJson: String?

  enum CodingKeys: String, CodingKey {
    case runID = "runId"
    case phase
    case status
    case iteration
    case elapsedMs
    case resultJson
  }
}

struct CompassDaemonAgentRunCancel: Decodable, Equatable {
  var runID: String
  var cancelled: Bool

  enum CodingKeys: String, CodingKey {
    case runID = "runId"
    case cancelled
  }
}

struct CompassDaemonDiagnostics: Equatable {
  var isEnabled: Bool
  var binaryURL: URL?
  var socketURL: URL
  var logURL: URL
  var version: String?
  var coreVersion: String?
  var schemaVersion: Int?
  var lastError: String?

  var copyText: String {
    [
      "compassd-enabled: \(isEnabled)",
      "compassd-binary: \(binaryURL?.path ?? "unresolved")",
      "compassd-socket: \(socketURL.path)",
      "compassd-log: \(logURL.path)",
      "compassd-version: \(version ?? "unknown")",
      "compass-core-version: \(coreVersion ?? "unknown")",
      "compassd-schema-version: \(schemaVersion.map(String.init) ?? "unknown")",
      "compassd-last-error: \(lastError ?? "none")",
    ].joined(separator: "\n")
  }
}
