import CompassAgentRPC
import Foundation
import XCTest

/// The wire format is shared between the host (`AgentVsockClient`) and the
/// in-guest `CompassGuestAgent`. These tests pin the framing + Codable
/// shape so neither side can drift silently — the agents share a Package
/// module but ship as separate binaries, so test coverage here is the
/// thing keeping them honest.
final class AgentRPCFramingTests: XCTestCase {

  // MARK: - Framing

  func testEncodeProducesBigEndianLengthPrefix() throws {
    let request = AgentRPCRequest.readFile(.init(path: "/x"))
    let frame = try AgentRPCFraming.encode(request)
    XCTAssertGreaterThanOrEqual(frame.count, 4)
    let length = frame.prefix(4).withUnsafeBytes { raw -> UInt32 in
      UInt32(bigEndian: raw.bindMemory(to: UInt32.self).baseAddress!.pointee)
    }
    XCTAssertEqual(Int(length), frame.count - 4)
  }

  func testEncodeThenDecodeRoundTripsRequest() throws {
    let original = AgentRPCRequest.writeFile(.init(path: "/a/b", dataBase64: "aGVsbG8="))
    let frame = try AgentRPCFraming.encode(original)
    let decoded = try AgentRPCFraming.decode(AgentRPCRequest.self, from: frame)
    XCTAssertEqual(decoded, original)
  }

  func testEncodeThenDecodeRoundTripsResponse() throws {
    let original = AgentRPCResponse.bash(.init(exitCode: 0, stdout: "hi", stderr: ""))
    let frame = try AgentRPCFraming.encode(original)
    let decoded = try AgentRPCFraming.decode(AgentRPCResponse.self, from: frame)
    XCTAssertEqual(decoded, original)
  }

  func testDecodeFailsOnTruncatedHeader() {
    let truncated = Data([0x00, 0x01])
    XCTAssertThrowsError(try AgentRPCFraming.decode(AgentRPCRequest.self, from: truncated)) {
      error in
      XCTAssertEqual(error as? AgentRPCFraming.FramingError, .lengthHeaderTooShort)
    }
  }

  func testDecodeFailsOnBodyShorterThanDeclared() {
    // Declared length = 64 bytes but only 2 bytes of body follow.
    var frame = Data(count: 4)
    frame.withUnsafeMutableBytes { buf in
      buf.bindMemory(to: UInt32.self).baseAddress!.pointee = UInt32(64).bigEndian
    }
    frame.append(Data([0x00, 0x00]))
    XCTAssertThrowsError(try AgentRPCFraming.decode(AgentRPCRequest.self, from: frame)) { error in
      guard
        case .bodyShorterThanDeclared(let declared, let actual) = error
          as? AgentRPCFraming.FramingError
      else {
        return XCTFail("expected .bodyShorterThanDeclared, got \(error)")
      }
      XCTAssertEqual(declared, 64)
      XCTAssertEqual(actual, 2)
    }
  }

  func testReadFrameStitchesShortReadsBackTogether() throws {
    // Stage a frame, then hand it out one byte at a time so the loop
    // has to call the reader many times — verifying the read-until-
    // satisfied loop actually loops instead of returning short data.
    let original = AgentRPCResponse.writeFile
    let frame = try AgentRPCFraming.encode(original)
    var cursor = 0
    let decoded: AgentRPCResponse = try AgentRPCFraming.readFrame(AgentRPCResponse.self) { _ in
      guard cursor < frame.count else { return nil }
      let chunk = frame.subdata(in: cursor..<(cursor + 1))
      cursor += 1
      return chunk
    }
    XCTAssertEqual(decoded, original)
  }

  // MARK: - Response surface

  func testErrorResponseRoundTrips() throws {
    let original = AgentRPCResponse.error(
      .init(kind: .notFound, detail: "/opt/missing")
    )
    let frame = try AgentRPCFraming.encode(original)
    let decoded = try AgentRPCFraming.decode(AgentRPCResponse.self, from: frame)
    XCTAssertEqual(decoded, original)
  }

  func testGlobResponseSerialisesMatchesWithMTime() throws {
    let original = AgentRPCResponse.glob(
      .init(matches: [
        .init(path: "/x/a.swift", modificationDateEpoch: 1_700_000_000),
        .init(path: "/x/b.swift", modificationDateEpoch: nil),
      ]))
    let frame = try AgentRPCFraming.encode(original)
    let decoded = try AgentRPCFraming.decode(AgentRPCResponse.self, from: frame)
    XCTAssertEqual(decoded, original)
  }
}
