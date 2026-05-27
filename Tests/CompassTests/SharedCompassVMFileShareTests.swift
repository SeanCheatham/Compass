import Foundation
import Testing

@testable import Compass

/// Coverage for `SharedCompassVMFileShare.validatedTag` — the VirtioFS tag is a
/// 36-byte ASCII identifier; getting this wrong silently corrupts the guest mount.
struct SharedCompassVMFileShareTests {
  // MARK: - Accepted tags

  @Test
  func testValidatedTagAcceptsAlphanumericAndDashUnderscore() {
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
        #require(value == tag)
      case .failure(let error):
        #require(false, "Expected \(tag) to validate but got error \(error)")
      }
    }
  }

  @Test
  func testDefaultWorkspacesTagValidates() {
    switch SharedCompassVMFileShare.validatedTag(SharedCompassVMFileShare.defaultWorkspacesTag) {
    case .success: break
    case .failure(let error):
      #require(false, "Default tag must validate; got \(error)")
    }
  }

  // MARK: - Rejected tags

  @Test
  func testValidatedTagRejectsEmptyString() {
    switch SharedCompassVMFileShare.validatedTag("") {
    case .success:
      #require(false, "Expected empty tag to fail")
    case .failure(let error):
      #require(error == .empty)
    }
  }

  @Test
  func testValidatedTagRejectsTagLongerThan36Bytes() {
    let tooLong = String(repeating: "a", count: 37)
    switch SharedCompassVMFileShare.validatedTag(tooLong) {
    case .success:
      #require(false, "Expected 37-byte tag to fail")
    case .failure(let error):
      #require(error == .tooLong(byteCount: 37))
    }
  }

  @Test
  func testValidatedTagRejectsTagWithSpaces() {
    switch SharedCompassVMFileShare.validatedTag("has space") {
    case .success:
      #require(false, "Expected tag with space to fail")
    case .failure(let error):
      #require(error == .containsWhitespace)
    }
  }

  @Test
  func testValidatedTagRejectsTagWithTabs() {
    switch SharedCompassVMFileShare.validatedTag("has\ttab") {
    case .success:
      #require(false, "Expected tag with tab to fail")
    case .failure(let error):
      #require(error == .containsWhitespace)
    }
  }

  @Test
  func testValidatedTagRejectsTagWithNewline() {
    switch SharedCompassVMFileShare.validatedTag("line\nbreak") {
    case .success:
      #require(false, "Expected tag with newline to fail")
    case .failure(let error):
      #require(error == .containsWhitespace)
    }
  }

  @Test
  func testValidatedTagRejectsNonASCIITag() {
    // "compass-é" — has a non-ASCII scalar
    switch SharedCompassVMFileShare.validatedTag("compass-é") {
    case .success:
      #require(false, "Expected non-ASCII tag to fail")
    case .failure(let error):
      #require(error == .nonASCII)
    }
  }

  @Test
  func testValidatedTagRejectsEmojiTag() {
    switch SharedCompassVMFileShare.validatedTag("compass-\u{1F4A9}") {
    case .success:
      #require(false, "Expected emoji tag to fail")
    case .failure(let error):
      // Could be reported as either non-ASCII or too-long; we only require it
      // fails with an error that mentions ASCII or byte count.
      switch error {
      case .nonASCII, .tooLong:
        break
      default:
        #require(false, "Unexpected error for emoji tag: \(error)")
      }
    }
  }

  // MARK: - ensureValidTag throwing wrapper

  @Test
  func testEnsureValidTagThrowsForEmpty() {
    var threw = false
    var caught: Error?
    do {
      _ = try SharedCompassVMFileShare.ensureValidTag("")
    } catch {
      threw = true
      caught = error
    }
    #require(threw)
    #require(caught as? SharedCompassVMFileShare.TagValidationError == .empty)
  }

  @Test
  func testEnsureValidTagReturnsValueOnSuccess() throws {
    let result = try SharedCompassVMFileShare.ensureValidTag("compass-test")
    #require(result == "compass-test")
  }

  // MARK: - Error descriptions

  @Test
  func testTagValidationErrorDescriptionsAreUserReadable() {
    #require(!SharedCompassVMFileShare.TagValidationError.empty.description.isEmpty)
    #require(
      SharedCompassVMFileShare.TagValidationError.tooLong(byteCount: 99)
        .description.contains("99")
    )
    #require(!SharedCompassVMFileShare.TagValidationError.nonASCII.description.isEmpty)
    #require(
      !SharedCompassVMFileShare.TagValidationError.containsWhitespace.description.isEmpty)
  }
}