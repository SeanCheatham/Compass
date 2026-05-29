import Foundation
import Testing

@testable import Compass

struct CodemapStoreTests {

  // MARK: - loadEntry

  @Test
  func loadEntry_forRelativePath_nonexistent_returnsNil() throws {
    let tempDir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let store = CodemapStore(directory: tempDir)
    let result = store.loadEntry(forRelativePath: "nonexistent.swift")
    #expect(result == nil)
  }

  @Test
  func saveEntry_and_loadEntry_roundtrip() throws {
    let tempDir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let store = CodemapStore(directory: tempDir)
    let entry = CodemapEntry(
      relativePath: "Sources/Foo.swift",
      language: .swift,
      contentHash: "abc123",
      sizeBytes: 10,
      symbols: [],
      imports: [],
      summary: nil,
      summaryModel: nil,
      summaryContentHash: nil,
      isGenerated: false
    )
    try store.saveEntry(entry)
    let loaded = store.loadEntry(forRelativePath: "Sources/Foo.swift")
    try #require(loaded != nil)
    #expect(loaded?.relativePath == entry.relativePath)
    #expect(loaded?.language == entry.language)
    #expect(loaded?.contentHash == entry.contentHash)
    #expect(loaded?.sizeBytes == entry.sizeBytes)
    #expect(loaded?.symbols == entry.symbols)
    #expect(loaded?.imports == entry.imports)
    #expect(loaded?.summary == entry.summary)
  }

  // MARK: - loadAllEntries

  @Test
  func loadAllEntries_emptyDirectory_returnsEmptyArray() throws {
    let tempDir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let store = CodemapStore(directory: tempDir)
    let result = store.loadAllEntries()
    #expect(result.isEmpty)
  }

  @Test
  func loadAllEntries_multipleEntries_returnsAll() throws {
    let tempDir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let store = CodemapStore(directory: tempDir)

    let entry1 = CodemapEntry(
      relativePath: "Sources/A.swift",
      language: .swift,
      contentHash: "abc",
      sizeBytes: 10,
      symbols: [],
      imports: [],
      summary: nil,
      summaryModel: nil,
      summaryContentHash: nil,
      isGenerated: false
    )
    let entry2 = CodemapEntry(
      relativePath: "Sources/B.swift",
      language: .swift,
      contentHash: "def",
      sizeBytes: 20,
      symbols: [],
      imports: [],
      summary: nil,
      summaryModel: nil,
      summaryContentHash: nil,
      isGenerated: false
    )
    let entry3 = CodemapEntry(
      relativePath: "Sources/C.swift",
      language: .typescript,
      contentHash: "ghi",
      sizeBytes: 30,
      symbols: [],
      imports: [],
      summary: nil,
      summaryModel: nil,
      summaryContentHash: nil,
      isGenerated: false
    )
    try store.saveEntry(entry1)
    try store.saveEntry(entry2)
    try store.saveEntry(entry3)

    let result = store.loadAllEntries()
    #expect(result.count == 3)
    let paths = result.map(\.relativePath).sorted()
    #expect(paths == ["Sources/A.swift", "Sources/B.swift", "Sources/C.swift"])
  }

  @Test
  func loadAllEntries_skipsUndecodableFiles() throws {
    let tempDir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let store = CodemapStore(directory: tempDir)

    // valid entry
    let validEntry = CodemapEntry(
      relativePath: "Sources/Valid.swift",
      language: .swift,
      contentHash: "abc",
      sizeBytes: 10,
      symbols: [],
      imports: [],
      summary: nil,
      summaryModel: nil,
      summaryContentHash: nil,
      isGenerated: false
    )
    try store.saveEntry(validEntry)

    // corrupt file (not valid JSON)
    let corruptURL = tempDir.appendingPathComponent("corrupt.json")
    try "not valid json".write(to: corruptURL, atomically: true, encoding: .utf8)

    let result = store.loadAllEntries()
    #expect(result.count == 1)
    #expect(result.first?.relativePath == "Sources/Valid.swift")
  }

  // MARK: - deleteEntry

  @Test
  func deleteEntry_removesFromDisk() throws {
    let tempDir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let store = CodemapStore(directory: tempDir)
    let entry = CodemapEntry(
      relativePath: "Sources/Foo.swift",
      language: .swift,
      contentHash: "abc123",
      sizeBytes: 10,
      symbols: [],
      imports: [],
      summary: nil,
      summaryModel: nil,
      summaryContentHash: nil,
      isGenerated: false
    )
    try store.saveEntry(entry)
    try store.deleteEntry(forRelativePath: "Sources/Foo.swift")
    let loaded = store.loadEntry(forRelativePath: "Sources/Foo.swift")
    #expect(loaded == nil)
  }

  @Test
  func deleteEntry_idempotent() throws {
    let tempDir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let store = CodemapStore(directory: tempDir)
    // should not throw
    try store.deleteEntry(forRelativePath: "nonexistent.swift")
  }

  // MARK: - entryURL / filename

  @Test
  func entryURL_forRelativePath_constructsCorrectPath() throws {
    let tempDir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let store = CodemapStore(directory: tempDir)
    let url = store.entryURL(forRelativePath: "Sources/Foo.swift")
    let expectedBasename = CodemapHash.sha256Hex("Sources/Foo.swift") + ".json"
    #expect(url.lastPathComponent == expectedBasename)
    #expect(url.path.hasPrefix(tempDir.path))
  }

  @Test
  func filename_for_relativePath_isDeterministic() throws {
    let tempDir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let store = CodemapStore(directory: tempDir)

    let result1 = store.filename(for: "Sources/Bar.swift")
    let result2 = store.filename(for: "Sources/Bar.swift")
    #expect(result1 == result2)
  }
}
