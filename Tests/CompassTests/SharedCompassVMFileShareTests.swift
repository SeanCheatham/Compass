import Foundation
import XCTest

@testable import Compass

/// Coverage for `SharedCompassVMFileShare.validatedTag` — the VirtioFS tag is a
/// 36-byte ASCII identifier; getting this wrong silently corrupts the guest mount.
final class SharedCompassVMFileShareTests: XCTestCase {
  // MARK: - Accepted tags

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
        XCTAssertEqual(value, tag)
      case .failure(let error):
        XCTFail("Expected \(tag) to validate but got error \(error)")
      }
    }
  }

  func testDefaultWorkspacesTagValidates() {
    switch SharedCompassVMFileShare.validatedTag(SharedCompassVMFileShare.defaultWorkspacesTag) {
    case .success: break
    case .failure(let error):
      XCTFail("Default tag must validate; got \(error)")
    }
  }

  // MARK: - Rejected tags

  func testValidatedTagRejectsEmptyString() {
    switch SharedCompassVMFileShare.validatedTag("") {
    case .success:
      XCTFail("Expected empty tag to fail")
    case .failure(let error):
      XCTAssertEqual(error, .empty)
    }
  }

  func testValidatedTagRejectsTagLongerThan36Bytes() {
    let tooLong = String(repeating: "a", count: 37)
    switch SharedCompassVMFileShare.validatedTag(tooLong) {
    case .success:
      XCTFail("Expected 37-byte tag to fail")
    case .failure(let error):
      XCTAssertEqual(error, .tooLong(byteCount: 37))
    }
  }

  func testValidatedTagRejectsTagWithSpaces() {
    switch SharedCompassVMFileShare.validatedTag("has space") {
    case .success:
      XCTFail("Expected tag with space to fail")
    case .failure(let error):
      XCTAssertEqual(error, .containsWhitespace)
    }
  }

  func testValidatedTagRejectsTagWithTabs() {
    switch SharedCompassVMFileShare.validatedTag("has\ttab") {
    case .success:
      XCTFail("Expected tag with tab to fail")
    case .failure(let error):
      XCTAssertEqual(error, .containsWhitespace)
    }
  }

  func testValidatedTagRejectsTagWithNewline() {
    switch SharedCompassVMFileShare.validatedTag("line\nbreak") {
    case .success:
      XCTFail("Expected tag with newline to fail")
    case .failure(let error):
      XCTAssertEqual(error, .containsWhitespace)
    }
  }

  func testValidatedTagRejectsNonASCIITag() {
    // "compass-é" — has a non-ASCII scalar
    switch SharedCompassVMFileShare.validatedTag("compass-é") {
    case .success:
      XCTFail("Expected non-ASCII tag to fail")
    case .failure(let error):
      XCTAssertEqual(error, .nonASCII)
    }
  }

  func testValidatedTagRejectsEmojiTag() {
    switch SharedCompassVMFileShare.validatedTag("compass-\u{1F4A9}") {
    case .success:
      XCTFail("Expected emoji tag to fail")
    case .failure(let error):
      // Could be reported as either non-ASCII or too-long; we only require it
      // fails with an error that mentions ASCII or byte count.
      switch error {
      case .nonASCII, .tooLong:
        break
      default:
        XCTFail("Unexpected error for emoji tag: \(error)")
      }
    }
  }

  // MARK: - ensureValidTag throwing wrapper

  func testEnsureValidTagThrowsForEmpty() {
    XCTAssertThrowsError(try SharedCompassVMFileShare.ensureValidTag("")) { error in
      XCTAssertEqual(error as? SharedCompassVMFileShare.TagValidationError, .empty)
    }
  }

  func testEnsureValidTagReturnsValueOnSuccess() throws {
    let result = try SharedCompassVMFileShare.ensureValidTag("compass-test")
    XCTAssertEqual(result, "compass-test")
  }

  // MARK: - Error descriptions

  func testTagValidationErrorDescriptionsAreUserReadable() {
    XCTAssertFalse(SharedCompassVMFileShare.TagValidationError.empty.description.isEmpty)
    XCTAssertTrue(
      SharedCompassVMFileShare.TagValidationError.tooLong(byteCount: 99)
        .description.contains("99")
    )
    XCTAssertFalse(SharedCompassVMFileShare.TagValidationError.nonASCII.description.isEmpty)
    XCTAssertFalse(
      SharedCompassVMFileShare.TagValidationError.containsWhitespace.description.isEmpty)
  }
}
