import Foundation
import Testing

@testable import Compass

struct KnownProjectStoreTestsRecordDecoding : ~Copyable {
  @Test func testDecodingDefaultsFieldsAddedAfterOriginalRegistryFormat() throws {
    let records = try decodeRecords(
      """
      [
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "path": "/tmp/original",
          "addedAt": 1,
          "lastOpenedAt": 2
        }
      ]
      """)

    let record = try #require(records.first)
    try #require(record.activeStorage == .repoLocal)
    try #require(record.nativeFeedbackMode == .notifications)
    #expect(!record.hostXcodeBuildTestEnabled)
  }

  @Test func testNativeFeedbackAndExecutionEnvironmentDecodingDefaultsMissingAndFutureValues() throws {
    let records = try decodeRecords(
      """
      [
        {
          "id": "12121212-1212-1212-1212-121212121212",
          "path": "/tmp/missing-native-feedback",
          "addedAt": 1,
          "lastOpenedAt": 2
        },
        {
          "id": "13131313-1313-1313-1313-131313131313",
          "path": "/tmp/future-native-feedback",
          "addedAt": 3,
          "lastOpenedAt": 4,
          "nativeFeedbackMode": "future_native_feedback_mode",
          "codexExecutionEnvironmentPreference": "future_execution_environment"
        }
      ]
      """)

    try #require(records.map(\.nativeFeedbackMode) == [.notifications, .notifications])
  }

  @Test func testDecodingClampsDefaultsAndFallsBackForUnknownValues() throws {
    let records = try decodeRecords(
      """
      [
        {
          "id": "22222222-2222-2222-2222-222222222222",
          "path": "/tmp/low",
          "addedAt": 1,
          "lastOpenedAt": 2,
          "activeStorage": "future_storage",
          "nativeFeedbackMode": "future_mode",
          "codexExecutionEnvironmentPreference": "future_execution_environment"
        },
        {
          "id": "33333333-3333-3333-3333-333333333333",
          "path": "/tmp/defaults",
          "addedAt": 3,
          "lastOpenedAt": 4,
          "activeStorage": "application_support",
          "nativeFeedbackMode": "speech_and_notifications",
          "codexExecutionEnvironmentPreference": "devcontainer_preferred"
        },
        {
          "id": "44444444-4444-4444-4444-444444444444",
          "path": "/tmp/high",
          "addedAt": 5,
          "lastOpenedAt": 6,
          "nativeFeedbackMode": "off"
        }
      ]
      """)

    try #require(records[0].activeStorage == .repoLocal)
    try #require(records[0].nativeFeedbackMode == .notifications)
    try #require(records[1].activeStorage == .applicationSupport)
    try #require(records[1].nativeFeedbackMode == .speechAndNotifications)
    try #require(records[2].activeStorage == .repoLocal)
    try #require(records[2].nativeFeedbackMode == .off)
  }

  private func decodeRecords(_ json: String) throws -> [KnownProjectRecord] {
    let data = try #require(json.data(using: .utf8))
    return try JSONDecoder().decode([KnownProjectRecord].self, from: data)
  }
}

final class KnownProjectStoreTests {
  private var temporaryDirectories: [URL] = []

  init() throws {}

  deinit {
    for url in temporaryDirectories {
      try? FileManager.default.removeItem(at: url)
    }
  }

  @Test func testLoadTreatsMissingEmptyAndMalformedRegistryFilesAsEmpty() throws {
    let missingRoots = try makeApplicationSupportRoots()
    try #require(KnownProjectStore.load(applicationSupportRoots: missingRoots) == [])

    let emptyCurrentRoots = try makeApplicationSupportRoots()
    try write("", to: currentProjectsURL(for: emptyCurrentRoots))
    try #require(KnownProjectStore.load(applicationSupportRoots: emptyCurrentRoots) == [])

    let malformedCurrentRoots = try makeApplicationSupportRoots()
    try write("{", to: currentProjectsURL(for: malformedCurrentRoots))
    try #require(KnownProjectStore.load(applicationSupportRoots: malformedCurrentRoots) == [])
  }

  @Test func testSaveWritesPrettySortedJSONToCurrentCompassDirectory() throws {
    let roots = try makeApplicationSupportRoots()
    let record = makeRecord(
      id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
      path: "/tmp/saved",
      activeStorage: .applicationSupport,
      nativeFeedbackMode: .speechAndNotifications
    )

    try KnownProjectStore.save([record], applicationSupportRoots: roots)

    try #require(FileManager.default.fileExists(atPath: currentProjectsURL(for: roots).path))
    try #require(KnownProjectStore.load(applicationSupportRoots: roots) == [record])

    let saved = try read(currentProjectsURL(for: roots))
    try #require(saved.contains("\n  {\n"))
    try assertSortedKeys(
      [
        "\"activeStorage\"",
        "\"addedAt\"",
        "\"id\"",
        "\"lastOpenedAt\"",
        "\"nativeFeedbackMode\"",
        "\"path\"",
      ],
      in: saved
    )
    try #require(!saved.contains("\"developSandbox\""))
    try #require(!saved.contains("\"codexExecutionEnvironmentPreference\""))
  }

  @Test func testSavePersistsNativeFeedbackModeRawValue() throws {
    let roots = try makeApplicationSupportRoots()
    let records = [
      makeRecord(
        id: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
        path: "/tmp/off",
        nativeFeedbackMode: .off
      ),
      makeRecord(
        id: "cccccccc-cccc-cccc-cccc-cccccccccccc",
        path: "/tmp/speech",
        nativeFeedbackMode: .speechAndNotifications
      ),
    ]

    try KnownProjectStore.save(records, applicationSupportRoots: roots)

    let saved = try read(currentProjectsURL(for: roots))
    try #require(saved.contains("\"nativeFeedbackMode\" : \"off\""))
    try #require(saved.contains("\"nativeFeedbackMode\" : \"speech_and_notifications\""))
    try #require(KnownProjectStore.load(applicationSupportRoots: roots) == records)
  }

  @Test func testSaveOmitsLegacySandboxPreferenceKeys() throws {
    let roots = try makeApplicationSupportRoots()
    let records = [
      makeRecord(
        id: "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee",
        path: "/tmp/one"
      ),
      makeRecord(
        id: "ffffffff-ffff-ffff-ffff-ffffffffffff",
        path: "/tmp/two"
      ),
    ]

    try KnownProjectStore.save(records, applicationSupportRoots: roots)

    let saved = try read(currentProjectsURL(for: roots))
    try #require(!saved.contains("\"developSandbox\""))
    try #require(!saved.contains("\"codexExecutionEnvironmentPreference\""))
    try #require(KnownProjectStore.load(applicationSupportRoots: roots) == records)
  }

  private func makeApplicationSupportRoots() throws -> KnownProjectStore.ApplicationSupportRoots {
    let base = FileManager.default.temporaryDirectory
      .appending(path: "KnownProjectStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    temporaryDirectories.append(base)
    return KnownProjectStore.ApplicationSupportRoots(
      current: base.appending(path: "CurrentSupport", directoryHint: .isDirectory)
    )
  }

  private func currentProjectsURL(for roots: KnownProjectStore.ApplicationSupportRoots) -> URL {
    roots.current
      .appending(path: "Compass", directoryHint: .isDirectory)
      .appending(path: "projects.json")
  }

  private func makeRecord(
    id: String,
    path: String,
    activeStorage: KnownProjectActiveStorage = .repoLocal,
    addedAt: Double = 10,
    lastOpenedAt: Double = 20,
    nativeFeedbackMode: NativeFeedbackMode = .notifications
  ) -> KnownProjectRecord {
    KnownProjectRecord(
      id: UUID(uuidString: id)!,
      path: path,
      activeStorage: activeStorage,
      addedAt: addedAt,
      lastOpenedAt: lastOpenedAt,
      nativeFeedbackMode: nativeFeedbackMode
    )
  }

  private func writeProjects(_ records: [KnownProjectRecord], to url: URL) throws {
    let encoder = JSONEncoder()
    let data = try encoder.encode(records)
    try createDirectory(url.deletingLastPathComponent())
    try data.write(to: url, options: .atomic)
  }

  private func write(_ contents: String, to url: URL) throws {
    try createDirectory(url.deletingLastPathComponent())
    try contents.write(to: url, atomically: true, encoding: .utf8)
  }

  private func read(_ url: URL) throws -> String {
    try String(contentsOf: url, encoding: .utf8)
  }

  private func createDirectory(_ url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  private func assertSortedKeys(
    _ keys: [String],
    in json: String
  ) throws {
    var previousUpperBound = json.startIndex
    for key in keys {
      guard let range = json.range(of: key, range: previousUpperBound..<json.endIndex) else {
        #expect(Bool(false), "Expected to find \(key) after previous sorted key.")
        return
      }
      previousUpperBound = range.upperBound
    }
  }
}
