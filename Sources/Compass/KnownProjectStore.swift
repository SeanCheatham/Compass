import AppKit
import Foundation
import CompassCore

struct CompassProjectStorageResolver: Equatable {
  var repoURL: URL
  var activeStorage: KnownProjectActiveStorage
  var applicationSupportRoots: KnownProjectStore.ApplicationSupportRoots

  init(
    repoURL: URL,
    activeStorage: KnownProjectActiveStorage = .repoLocal,
    applicationSupportRoots: KnownProjectStore.ApplicationSupportRoots =
      KnownProjectStore.productionApplicationSupportRoots()
  ) {
    self.repoURL = repoURL.standardizedFileURL
    self.activeStorage = activeStorage
    self.applicationSupportRoots = applicationSupportRoots
  }

  var storageRootURL: URL {
    Self.storageRootURL(
      for: repoURL,
      activeStorage: activeStorage,
      applicationSupportRoots: applicationSupportRoots
    )
  }

  var workspace: CompassWorkspace {
    CompassWorkspace(repoURL: repoURL, storageRootURL: storageRootURL)
  }

  static func storageRootURL(
    for repoURL: URL,
    activeStorage: KnownProjectActiveStorage,
    applicationSupportRoots roots: KnownProjectStore.ApplicationSupportRoots
  ) -> URL {
    let standardizedRepoURL = repoURL.standardizedFileURL
    switch activeStorage {
    case .repoLocal:
      return CompassWorkspace.repoLocalStorageRootURL(for: standardizedRepoURL)
    case .applicationSupport:
      return CompassWorkspaceStorageAssessment.currentApplicationSupportCandidateURL(
        for: standardizedRepoURL,
        applicationSupportRoots: roots
      )
    }
  }
}

struct KnownProjectRecord: Codable, Identifiable, Equatable {
  var id: UUID
  var path: String
  var activeStorage: KnownProjectActiveStorage
  var addedAt: Double
  var lastOpenedAt: Double
  var nativeFeedbackMode: NativeFeedbackMode
  var studioThinkingNarrationEnabled: Bool

  enum CodingKeys: String, CodingKey {
    case id
    case path
    case activeStorage
    case addedAt
    case lastOpenedAt
    case nativeFeedbackMode
    case studioThinkingNarrationEnabled
  }

  init(
    id: UUID,
    path: String,
    activeStorage: KnownProjectActiveStorage = .repoLocal,
    addedAt: Double,
    lastOpenedAt: Double,
    nativeFeedbackMode: NativeFeedbackMode = .notifications,
    studioThinkingNarrationEnabled: Bool = false
  ) {
    self.id = id
    self.path = path
    self.activeStorage = activeStorage
    self.addedAt = addedAt
    self.lastOpenedAt = lastOpenedAt
    self.nativeFeedbackMode = nativeFeedbackMode
    self.studioThinkingNarrationEnabled = studioThinkingNarrationEnabled
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    path = try container.decode(String.self, forKey: .path)
    activeStorage =
      try container.decodeIfPresent(
        KnownProjectActiveStorage.self,
        forKey: .activeStorage
      ) ?? .repoLocal
    addedAt = try container.decode(Double.self, forKey: .addedAt)
    lastOpenedAt = try container.decode(Double.self, forKey: .lastOpenedAt)
    nativeFeedbackMode =
      try container.decodeIfPresent(
        NativeFeedbackMode.self,
        forKey: .nativeFeedbackMode
      ) ?? .notifications
    studioThinkingNarrationEnabled =
      try container.decodeIfPresent(
        Bool.self,
        forKey: .studioThinkingNarrationEnabled
      ) ?? false
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(path, forKey: .path)
    try container.encode(activeStorage, forKey: .activeStorage)
    try container.encode(addedAt, forKey: .addedAt)
    try container.encode(lastOpenedAt, forKey: .lastOpenedAt)
    try container.encode(nativeFeedbackMode, forKey: .nativeFeedbackMode)
    try container.encode(studioThinkingNarrationEnabled, forKey: .studioThinkingNarrationEnabled)
  }
}

extension CompassProject {
  convenience init(record: KnownProjectRecord) {
    self.init(
      id: record.id,
      repoURL: URL(fileURLWithPath: record.path).standardizedFileURL,
      activeStorage: record.activeStorage,
      addedAt: Date(timeIntervalSince1970: record.addedAt),
      lastOpenedAt: Date(timeIntervalSince1970: record.lastOpenedAt),
      nativeFeedbackMode: record.nativeFeedbackMode,
      studioThinkingNarrationEnabled: record.studioThinkingNarrationEnabled
    )
  }

  var record: KnownProjectRecord {
    KnownProjectRecord(
      id: id,
      path: repoURL.path,
      activeStorage: activeStorage,
      addedAt: addedAt.timeIntervalSince1970,
      lastOpenedAt: lastOpenedAt.timeIntervalSince1970,
      nativeFeedbackMode: nativeFeedbackMode,
      studioThinkingNarrationEnabled: studioThinkingNarrationEnabled
    )
  }

  func logProjectSelected() {
    log("Selected repo: \(repoURL.path)", level: .success)
    log("Compass workspace: \(compassPath)", level: .info)
  }
}

enum KnownProjectStore {
  struct ApplicationSupportRoots: Equatable {
    var current: URL
  }

  static func load() -> [KnownProjectRecord] {
    load(applicationSupportRoots: productionApplicationSupportRoots())
  }

  static func load(applicationSupportRoots roots: ApplicationSupportRoots) -> [KnownProjectRecord] {
    let sourceURL = projectsURL(in: roots.current)
    guard let data = try? Data(contentsOf: sourceURL), !data.isEmpty else {
      return []
    }
    return (try? JSONDecoder().decode([KnownProjectRecord].self, from: data)) ?? []
  }

  static func save(_ records: [KnownProjectRecord]) throws {
    try save(records, applicationSupportRoots: productionApplicationSupportRoots())
  }

  static func save(
    _ records: [KnownProjectRecord], applicationSupportRoots roots: ApplicationSupportRoots
  ) throws {
    let directoryURL = directoryURL(in: roots.current)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(records)
    try data.write(to: projectsURL(in: roots.current), options: .atomic)
  }

  private static func projectsURL(in currentApplicationSupportRoot: URL) -> URL {
    directoryURL(in: currentApplicationSupportRoot).appending(path: "projects.json")
  }

  static func directoryURL(in currentApplicationSupportRoot: URL) -> URL {
    currentApplicationSupportRoot.appending(path: "Compass", directoryHint: .isDirectory)
  }

  static func productionApplicationSupportRoots() -> ApplicationSupportRoots {
    let base =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.homeDirectoryForCurrentUser.appending(
        path: "Library/Application Support", directoryHint: .isDirectory)
    return ApplicationSupportRoots(current: base)
  }
}
