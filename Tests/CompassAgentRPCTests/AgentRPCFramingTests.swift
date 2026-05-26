import CompassAgentRPC
import Foundation
import Testing

/// The wire format is shared between the host (`AgentVsockClient`) and the
/// in-guest `CompassGuestAgent`. These tests pin the framing + Codable
/// shape so neither side can drift silently — the agents share a Package
/// module but ship as separate binaries, so test coverage here is the
/// thing keeping them honest.
struct AgentRPCFramingTests {

  // MARK: - Framing

  @Test
  func encodeProducesBigEndianLengthPrefix() throws {
    let request = AgentRPCRequest.readFile(.init(path: "/x"))
    let frame = try AgentRPCFraming.encode(request)
    try #require(frame.count >= 4)
    let length = frame.prefix(4).withUnsafeBytes { raw -> UInt32 in
      UInt32(bigEndian: raw.bindMemory(to: UInt32.self).baseAddress!.pointee)
    }
    try #require(Int(length) == frame.count - 4)
  }

  @Test
  func encodeThenDecodeRoundTripsRequest() throws {
    let original = AgentRPCRequest.writeFile(.init(path: "/a/b", dataBase64: "aGVsbG8="))
    let frame = try AgentRPCFraming.encode(original)
    let decoded = try AgentRPCFraming.decode(AgentRPCRequest.self, from: frame)
    try #require(decoded == original)
  }

  @Test
  func encodeThenDecodeRoundTripsResponse() throws {
    let original = AgentRPCResponse.bash(.init(exitCode: 0, stdout: "hi", stderr: ""))
    let frame = try AgentRPCFraming.encode(original)
    let decoded = try AgentRPCFraming.decode(AgentRPCResponse.self, from: frame)
    try #require(decoded == original)
  }

  @Test
  func decodeFailsOnTruncatedHeader() {
    let truncated = Data([0x00, 0x01])
    do {
      try AgentRPCFraming.decode(AgentRPCRequest.self, from: truncated)
      Issue.record("Expected throwing, but it succeeded")
    } catch let error as AgentRPCFraming.FramingError {
      switch error {
      case .lengthHeaderTooShort:
        // expected
        break
      default:
        Issue.record("Wrong error case: \(error)")
      }
    } catch {
      Issue.record("Wrong error type: \(String(describing: error))")
    }
  }

  @Test
  func decodeFailsOnBodyShorterThanDeclared() {
    // Declared length = 64 bytes but only 2 bytes of body follow.
    var frame = Data(count: 4)
    frame.withUnsafeMutableBytes { buf in
      buf.bindMemory(to: UInt32.self).baseAddress!.pointee = UInt32(64).bigEndian
    }
    frame.append(Data([0x00, 0x00]))
    do {
      try AgentRPCFraming.decode(AgentRPCRequest.self, from: frame)
      Issue.record("Expected throwing, but it succeeded")
    } catch let error as AgentRPCFraming.FramingError {
      switch error {
      case .bodyShorterThanDeclared(let declared, let actual):
        if declared != 64 {
          Issue.record("declared != 64, got \(declared)")
        }
        if actual != 2 {
          Issue.record("actual != 2, got \(actual)")
        }
      default:
        Issue.record("Wrong error case: \(error)")
      }
    } catch {
      Issue.record("Wrong error type: \(String(describing: error))")
    }
  }

  @Test
  func readFrameStitchesShortReadsBackTogether() throws {
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
    try #require(decoded == original)
  }

  // MARK: - Response surface

  @Test
  func errorResponseRoundTrips() throws {
    let original = AgentRPCResponse.error(
      .init(kind: .notFound, detail: "/opt/missing")
    )
    let frame = try AgentRPCFraming.encode(original)
    let decoded = try AgentRPCFraming.decode(AgentRPCResponse.self, from: frame)
    try #require(decoded == original)
  }

  @Test
  func globResponseSerialisesMatchesWithMTime() throws {
    let original = AgentRPCResponse.glob(
      .init(matches: [
        .init(path: "/x/a.swift", modificationDateEpoch: 1_700_000_000),
        .init(path: "/x/b.swift", modificationDateEpoch: nil),
      ]))
    let frame = try AgentRPCFraming.encode(original)
    let decoded = try AgentRPCFraming.decode(AgentRPCResponse.self, from: frame)
    try #require(decoded == original)
  }
}
