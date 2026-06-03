import Foundation
import Testing

@testable import Compass

struct RustDesktopVisualVerifierTests {
  @Test func discoveryRecognizesPresentScaffold() throws {
    let result = ProcessResult(exitCode: 0, stdout: "PRESENT\n", stderr: "")
    try #require(RustDesktopVisualVerification.isPresent(result))
  }

  @Test func discoveryRejectsMissingScaffold() throws {
    let result = ProcessResult(exitCode: 0, stdout: "MISSING\n", stderr: "")
    try #require(!RustDesktopVisualVerification.isPresent(result))
  }

  @Test func parsesScreenshotDataBetweenMarkers() throws {
    let bytes = Data([0x89, 0x50, 0x4E, 0x47])
    let encoded = bytes.base64EncodedString()
    let output = """
      before
      \(RustDesktopVisualVerification.screenshotBeginMarker)
      \(encoded)
      \(RustDesktopVisualVerification.screenshotEndMarker)
      after
      """

    try #require(RustDesktopVisualVerification.screenshotData(from: output) == bytes)
  }

  @Test func redactsScreenshotBase64FromLogs() throws {
    let output = """
      \(RustDesktopVisualVerification.screenshotBeginMarker)
      abc123
      \(RustDesktopVisualVerification.screenshotEndMarker)
      """

    let redacted = RustDesktopVisualVerification.redactedOutput(output)
    try #require(!redacted.contains("abc123"))
    try #require(redacted.contains("<base64 screenshot omitted>"))
  }
}
