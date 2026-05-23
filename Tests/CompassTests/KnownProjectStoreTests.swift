import Foundation
import XCTest

@testable import Compass

final class KnownProjectStoreTestsRecordDecoding: XCTestCase {
  func testDecodingDefaultsFieldsAddedAfterOriginalRegistryFormat() throws {
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

    let record = try XCTUnwrap(records.first)
    XCTAssertEqual(record.activeStorage, .repoLocal)
    XCTAssertEqual(record.nativeFeedbackMode, .notifications)
  }

  func testNativeFeedbackAndExecutionEnvironmentDecodingDefaultsMissingAndFutureValues() throws {
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

    XCTAssertEqual(records.map(\.nativeFeedbackMode), [.notifications, .notifications])
  }

  func testDecodingClampsDefaultsAndFallsBackForUnknownValues() throws {
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

    XCTAssertEqual(records[0].activeStorage, .repoLocal)
    XCTAssertEqual(records[0].nativeFeedbackMode, .notifications)
    XCTAssertEqual(records[1].activeStorage, .applicationSupport)
    XCTAssertEqual(records[1].nativeFeedbackMode, .speechAndNotifications)
    XCTAssertEqual(records[2].activeStorage, .repoLocal)
    XCTAssertEqual(records[2].nativeFeedbackMode, .off)
  }

  private func decodeRecords(_ json: String) throws -> [KnownProjectRecord] {
    let data = try XCTUnwrap(json.data(using: .utf8))
    return try JSONDecoder().decode([KnownProjectRecord].self, from: data)
  }
}

final class KnownProjectStoreTests: XCTestCase {
  private var temporaryDirectories: [URL] = []

  override func tearDownWithError() throws {
    for url in temporaryDirectories {
      try? FileManager.default.removeItem(at: url)
    }
    temporaryDirectories.removeAll()
  }

  func testLoadPrefersCurrentCompassRegistryWhenBothCurrentAndLegacyExist() throws {
    let roots = try makeApplicationSupportRoots()
    let current = makeRecord(
      id: "55555555-5555-5555-5555-555555555555",
      path: "/tmp/current"
    )
    let legacy = makeRecord(
      id: "66666666-6666-6666-6666-666666666666",
      path: "/tmp/legacy"
    )
    try writeProjects([legacy], to: legacyProjectsURL(for: roots))
    try writeProjects([current], to: currentProjectsURL(for: roots))

    XCTAssertEqual(KnownProjectStore.load(applicationSupportRoots: roots), [current])
  }

  func testLoadFallsBackToLegacyCompassNativeRegistryWhenCurrentIsMissing() throws {
    let roots = try makeApplicationSupportRoots()
    let legacy = makeRecord(
      id: "77777777-7777-7777-7777-777777777777",
      path: "/tmp/legacy-only"
    )
    try writeProjects([legacy], to: legacyProjectsURL(for: roots))

    XCTAssertEqual(KnownProjectStore.load(applicationSupportRoots: roots), [legacy])
  }

  func testLoadTreatsMissingEmptyAndMalformedRegistryFilesAsEmpty() throws {
    let missingRoots = try makeApplicationSupportRoots()
    XCTAssertEqual(KnownProjectStore.load(applicationSupportRoots: missingRoots), [])

    let emptyCurrentRoots = try makeApplicationSupportRoots()
    try write("", to: currentProjectsURL(for: emptyCurrentRoots))
    try writeProjects(
      [makeRecord(id: "88888888-8888-8888-8888-888888888888", path: "/tmp/legacy")],
      to: legacyProjectsURL(for: emptyCurrentRoots)
    )
    XCTAssertEqual(KnownProjectStore.load(applicationSupportRoots: emptyCurrentRoots), [])

    let malformedCurrentRoots = try makeApplicationSupportRoots()
    try write("{", to: currentProjectsURL(for: malformedCurrentRoots))
    try writeProjects(
      [makeRecord(id: "99999999-9999-9999-9999-999999999999", path: "/tmp/legacy")],
      to: legacyProjectsURL(for: malformedCurrentRoots)
    )
    XCTAssertEqual(KnownProjectStore.load(applicationSupportRoots: malformedCurrentRoots), [])

    let malformedLegacyRoots = try makeApplicationSupportRoots()
    try write("{", to: legacyProjectsURL(for: malformedLegacyRoots))
    XCTAssertEqual(KnownProjectStore.load(applicationSupportRoots: malformedLegacyRoots), [])

    let emptyLegacyRoots = try makeApplicationSupportRoots()
    try write("", to: legacyProjectsURL(for: emptyLegacyRoots))
    XCTAssertEqual(KnownProjectStore.load(applicationSupportRoots: emptyLegacyRoots), [])
  }

  func testSaveWritesPrettySortedJSONOnlyToCurrentCompassDirectory() throws {
    let roots = try makeApplicationSupportRoots()
    let record = makeRecord(
      id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
      path: "/tmp/saved",
      activeStorage: .applicationSupport,
      nativeFeedbackMode: .speechAndNotifications
    )

    try KnownProjectStore.save([record], applicationSupportRoots: roots)

    XCTAssertTrue(FileManager.default.fileExists(atPath: currentProjectsURL(for: roots).path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: legacyProjectsURL(for: roots).path))
    XCTAssertEqual(KnownProjectStore.load(applicationSupportRoots: roots), [record])

    let saved = try read(currentProjectsURL(for: roots))
    XCTAssertTrue(saved.contains("\n  {\n"))
    assertSortedKeys(
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
    XCTAssertFalse(saved.contains("\"developSandbox\""))
    XCTAssertFalse(saved.contains("\"codexExecutionEnvironmentPreference\""))
  }

  func testSavePersistsNativeFeedbackModeRawValue() throws {
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
    XCTAssertTrue(saved.contains("\"nativeFeedbackMode\" : \"off\""))
    XCTAssertTrue(saved.contains("\"nativeFeedbackMode\" : \"speech_and_notifications\""))
    XCTAssertEqual(KnownProjectStore.load(applicationSupportRoots: roots), records)
  }

  func testSaveOmitsLegacySandboxPreferenceKeys() throws {
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
    XCTAssertFalse(saved.contains("\"developSandbox\""))
    XCTAssertFalse(saved.contains("\"codexExecutionEnvironmentPreference\""))
    XCTAssertEqual(KnownProjectStore.load(applicationSupportRoots: roots), records)
  }

  private func makeApplicationSupportRoots() throws -> KnownProjectStore.ApplicationSupportRoots {
    let base = FileManager.default.temporaryDirectory
      .appending(path: "KnownProjectStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    temporaryDirectories.append(base)
    return KnownProjectStore.ApplicationSupportRoots(
      current: base.appending(path: "CurrentSupport", directoryHint: .isDirectory),
      legacy: base.appending(path: "LegacySupport", directoryHint: .isDirectory)
    )
  }

  private func currentProjectsURL(for roots: KnownProjectStore.ApplicationSupportRoots) -> URL {
    roots.current
      .appending(path: "Compass", directoryHint: .isDirectory)
      .appending(path: "projects.json")
  }

  private func legacyProjectsURL(for roots: KnownProjectStore.ApplicationSupportRoots) -> URL {
    roots.legacy
      .appending(path: "CompassNative", directoryHint: .isDirectory)
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
    in json: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    var previousUpperBound = json.startIndex
    for key in keys {
      guard let range = json.range(of: key, range: previousUpperBound..<json.endIndex) else {
        XCTFail("Expected to find \(key) after previous sorted key.", file: file, line: line)
        return
      }
      previousUpperBound = range.upperBound
    }
  }
}
