import Foundation

struct SessionAuditEvent: Codable, Equatable {
  static let schemaVersion = 1

  var schemaVersion: Int = Self.schemaVersion
  var session: Int
  var sequence: Int
  var timestamp: Double
  var phase: String?
  var kind: String
  var level: String?
  var liveKind: String?
  var status: String?
  var correlationID: String?
  var text: String?
  var detail: String?
  var artifactPath: String?
  var metadata: [String: String]?

  init(
    session: Int,
    sequence: Int,
    timestamp: Date = Date(),
    phase: String? = nil,
    kind: String,
    level: String? = nil,
    liveKind: String? = nil,
    status: String? = nil,
    correlationID: String? = nil,
    text: String? = nil,
    detail: String? = nil,
    artifactPath: String? = nil,
    metadata: [String: String]? = nil
  ) {
    self.session = session
    self.sequence = sequence
    self.timestamp = timestamp.timeIntervalSince1970 * 1000
    self.phase = phase
    self.kind = kind
    self.level = level
    self.liveKind = liveKind
    self.status = status
    self.correlationID = correlationID
    self.text = Self.bounded(text)
    self.detail = Self.bounded(detail)
    self.artifactPath = artifactPath
    self.metadata = Self.cleanedMetadata(metadata)
  }

  private static func bounded(_ value: String?, limit: Int = 4_000) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    guard trimmed.count > limit else { return trimmed }
    return String(trimmed.prefix(limit - 3)) + "..."
  }

  private static func cleanedMetadata(_ metadata: [String: String]?) -> [String: String]? {
    guard let metadata else { return nil }
    let cleaned = metadata.reduce(into: [String: String]()) { result, pair in
      let value = pair.value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !pair.key.isEmpty, !value.isEmpty else { return }
      result[pair.key] = bounded(value, limit: 1_000)
    }
    return cleaned.isEmpty ? nil : cleaned
  }
}

struct SessionAuditArtifact: Codable, Equatable, Identifiable {
  var id: String { path }
  var path: String
  var kind: String
  var createdAt: Double
  var byteCount: UInt64
  var note: String?

  init(
    path: String,
    kind: String,
    byteCount: UInt64,
    note: String? = nil,
    createdAt: Date = Date()
  ) {
    self.path = path
    self.kind = kind
    self.createdAt = createdAt.timeIntervalSince1970 * 1000
    self.byteCount = byteCount
    let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
    self.note = trimmedNote?.isEmpty == false ? trimmedNote : nil
  }
}

struct SessionAuditManifest: Codable, Equatable {
  static let schemaVersion = 1

  var schemaVersion: Int = Self.schemaVersion
  var session: Int
  var createdAt: Double
  var updatedAt: Double
  var status: SessionStatus?
  var startedAt: Double?
  var endedAt: Double?
  var artifacts: [SessionAuditArtifact]

  init(
    session: Int,
    createdAt: Date = Date(),
    status: SessionStatus? = nil,
    startedAt: Double? = nil,
    endedAt: Double? = nil,
    artifacts: [SessionAuditArtifact] = []
  ) {
    let timestamp = createdAt.timeIntervalSince1970 * 1000
    self.session = session
    self.createdAt = timestamp
    self.updatedAt = timestamp
    self.status = status
    self.startedAt = startedAt
    self.endedAt = endedAt
    self.artifacts = artifacts
  }

  mutating func update(status: SessionStatus?, startedAt: Double?, endedAt: Double?) {
    if let status { self.status = status }
    if let startedAt { self.startedAt = startedAt }
    if let endedAt { self.endedAt = endedAt }
    updatedAt = Date().timeIntervalSince1970 * 1000
  }

  mutating func recordArtifact(_ artifact: SessionAuditArtifact) {
    if let index = artifacts.firstIndex(where: { $0.path == artifact.path }) {
      artifacts[index] = artifact
    } else {
      artifacts.append(artifact)
    }
    updatedAt = Date().timeIntervalSince1970 * 1000
  }
}
