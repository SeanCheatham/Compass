import Foundation
import Testing

@testable import Compass

/// Coverage for `SharedCompassVMFileShare.validatedTag` — the VirtioFS tag is a
/// 36-byte ASCII identifier; getting this wrong silently corrupts the guest mount.
struct SharedCompassVMFileShareTests {
  // MARK: - Accepted tags

  @Test
  func testValidatedTagAcceptsAlphanumericAndDashUnderscore() throws {
    let valid = [
      "compass-workspaces",
      "compass_workspaces",
      "a",
      "A1",
      "Z9-x_y",
      "abcdefghijklmnopqrstuvwxyz0123456789",  // 36 chars exactly
      "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",
    ]
    for tag in valid {
      switch SharedCompassVMFileShare.validatedTag(tag) {
      case .success(let value):
        try #require(value == tag)
      case .failure(let error):
        #expect(Bool(false), "Expected \(tag) to validate but got error \(error)")
      }
    }
  }

  @Test
  func testDefaultWorkspacesTagValidates() throws {
    switch SharedCompassVMFileShare.validatedTag(SharedCompassVMFileShare.defaultWorkspacesTag) {
    case .success: break
    case .failure(let error):
      #expect(Bool(false), "Default tag must validate; got \(error)")
    }
  }

  // MARK: - Rejected tags

  @Test
  func testValidatedTagRejectsEmptyString() throws {
    switch SharedCompassVMFileShare.validatedTag("") {
    case .success:
      #expect(Bool(false), "Expected empty tag to fail")
    case .failure(let error):
      try #require(error == .empty)
    }
  }

  @Test
  func testValidatedTagRejectsTagLongerThan36Bytes() throws {
    let tooLong = String(repeating: "a", count: 37)
    switch SharedCompassVMFileShare.validatedTag(tooLong) {
    case .success:
      #expect(Bool(false), "Expected 37-byte tag to fail")
    case .failure(let error):
      try #require(error == .tooLong(byteCount: 37))
    }
  }

  @Test
  func testValidatedTagRejectsTagWithSpaces() throws {
    switch SharedCompassVMFileShare.validatedTag("has space") {
    case .success:
      #expect(Bool(false), "Expected tag with space to fail")
    case .failure(let error):
      try #require(error == .containsWhitespace)
    }
  }

  @Test
  func testValidatedTagRejectsTagWithTabs() throws {
    switch SharedCompassVMFileShare.validatedTag("has\ttab") {
    case .success:
      #expect(Bool(false), "Expected tag with tab to fail")
    case .failure(let error):
      try #require(error == .containsWhitespace)
    }
  }

  @Test
  func testValidatedTagRejectsTagWithNewline() throws {
    switch SharedCompassVMFileShare.validatedTag("line\nbreak") {
    case .success:
      #expect(Bool(false), "Expected tag with newline to fail")
    case .failure(let error):
      try #require(error == .containsWhitespace)
    }
  }

  @Test
  func testValidatedTagRejectsNonASCIITag() throws {
    // "compass-é" — has a non-ASCII scalar
    switch SharedCompassVMFileShare.validatedTag("compass-é") {
    case .success:
      #expect(Bool(false), "Expected non-ASCII tag to fail")
    case .failure(let error):
      try #require(error == .nonASCII)
    }
  }

  @Test
  func testValidatedTagRejectsEmojiTag() throws {
    switch SharedCompassVMFileShare.validatedTag("compass-\u{1F4A9}") {
    case .success:
      #expect(Bool(false), "Expected emoji tag to fail")
    case .failure(let error):
      // Could be reported as either non-ASCII or too-long; we only require it
      // fails with an error that mentions ASCII or byte count.
      switch error {
      case .nonASCII, .tooLong:
        break
      default:
        #expect(Bool(false), "Unexpected error for emoji tag: \(error)")
      }
    }
  }

  // MARK: - ensureValidTag throwing wrapper

  @Test
  func testEnsureValidTagThrowsForEmpty() throws {
    var threw = false
    var caught: Error?
    do {
      _ = try SharedCompassVMFileShare.ensureValidTag("")
    } catch {
      threw = true
      caught = error
    }
    try #require(threw)
    try #require(caught as? SharedCompassVMFileShare.TagValidationError == .empty)
  }

  @Test
  func testEnsureValidTagReturnsValueOnSuccess() throws {
    let result = try SharedCompassVMFileShare.ensureValidTag("compass-test")
    try #require(result == "compass-test")
  }

  // MARK: - Error descriptions

  @Test
  func testTagValidationErrorDescriptionsAreUserReadable() throws {
    try #require(!SharedCompassVMFileShare.TagValidationError.empty.description.isEmpty)
    try #require(
      SharedCompassVMFileShare.TagValidationError.tooLong(byteCount: 99)
        .description.contains("99")
    )
    try #require(!SharedCompassVMFileShare.TagValidationError.nonASCII.description.isEmpty)
    try #require(
      !SharedCompassVMFileShare.TagValidationError.containsWhitespace.description.isEmpty)
  }
}