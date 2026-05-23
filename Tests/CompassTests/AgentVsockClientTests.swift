import CompassAgentRPC
import Foundation
import XCTest

@testable import Compass

/// Round-trip tests for the host-side vsock client. A `StubTransport`
/// captures the framed request, plays a canned response, and signals EOF
/// so the framing decoder terminates — no VM, no sockets.
final class AgentVsockClientTests: XCTestCase {

  // MARK: - Filesystem

  func testReadFileDecodesBase64ResponseIntoBytes() async throws {
    let payload = Data([0x01, 0x02, 0x03, 0x04])
    let transport = StubTransport(
      responses: [makeFrame(.readFile(.init(dataBase64: payload.base64EncodedString())))]
    )
    let client = AgentVsockClient(transportFactory: { transport })

    let data = try await client.readFile(at: URL(fileURLWithPath: "/opt/x.bin"))

    XCTAssertEqual(data, payload)
    XCTAssertEqual(transport.writtenFrames.count, 1)
    let request = try AgentRPCFraming.decode(AgentRPCRequest.self, from: transport.writtenFrames[0])
    guard case .readFile(let args) = request else {
      return XCTFail("expected readFile request, got \(request)")
    }
    XCTAssertEqual(args.path, "/opt/x.bin")
  }

  func testReadFileMapsNotFoundErrorIntoTypedFilesystemError() async {
    let transport = StubTransport(
      responses: [makeFrame(.error(.init(kind: .notFound, detail: "/opt/missing")))]
    )
    let client = AgentVsockClient(transportFactory: { transport })

    do {
      _ = try await client.readFile(at: URL(fileURLWithPath: "/opt/missing"))
      XCTFail("expected notFound error")
    } catch let error as AgentFilesystemError {
      guard case .notFound = error else {
        return XCTFail("expected .notFound, got \(error)")
      }
    } catch {
      XCTFail("expected AgentFilesystemError, got \(error)")
    }
  }

  func testWriteFileSendsBase64InRequest() async throws {
    let transport = StubTransport(responses: [makeFrame(.writeFile)])
    let client = AgentVsockClient(transportFactory: { transport })

    let payload = Data("hello".utf8)
    try await client.writeFile(payload, at: URL(fileURLWithPath: "/opt/out.txt"))

    let request = try AgentRPCFraming.decode(AgentRPCRequest.self, from: transport.writtenFrames[0])
    guard case .writeFile(let args) = request else {
      return XCTFail("expected writeFile request, got \(request)")
    }
    XCTAssertEqual(args.path, "/opt/out.txt")
    XCTAssertEqual(args.dataBase64, payload.base64EncodedString())
  }

  func testListDirectoryParsesEntries() async throws {
    let transport = StubTransport(responses: [
      makeFrame(
        .listDirectory(
          .init(entries: [
            .init(path: "/opt/x/a.swift", name: "a.swift", isDirectory: false),
            .init(path: "/opt/x/Sources", name: "Sources", isDirectory: true),
          ])))
    ])
    let client = AgentVsockClient(transportFactory: { transport })

    let entries = try await client.listDirectory(at: URL(fileURLWithPath: "/opt/x"))

    XCTAssertEqual(entries.count, 2)
    XCTAssertEqual(entries.first?.name, "a.swift")
    XCTAssertEqual(entries.first?.isDirectory, false)
    XCTAssertEqual(entries.last?.name, "Sources")
    XCTAssertEqual(entries.last?.isDirectory, true)
  }

  func testGlobReturnsMatchesWithDates() async throws {
    let transport = StubTransport(responses: [
      makeFrame(
        .glob(
          .init(matches: [
            .init(path: "/opt/x/a.swift", modificationDateEpoch: 1_700_000_000),
            .init(path: "/opt/x/b.swift", modificationDateEpoch: nil),
          ])))
    ])
    let client = AgentVsockClient(transportFactory: { transport })

    let matches = try await client.glob(
      pattern: "**/*.swift",
      under: URL(fileURLWithPath: "/opt/x"),
      walkCap: 100
    )

    XCTAssertEqual(matches.count, 2)
    XCTAssertEqual(matches[0].url.path, "/opt/x/a.swift")
    XCTAssertEqual(matches[0].modificationDate, Date(timeIntervalSince1970: 1_700_000_000))
    XCTAssertNil(matches[1].modificationDate)
  }

  func testStatReturnsNilWhenMetadataIsNil() async throws {
    let transport = StubTransport(responses: [makeFrame(.stat(.init(metadata: nil)))])
    let client = AgentVsockClient(transportFactory: { transport })

    let metadata = try await client.metadata(of: URL(fileURLWithPath: "/opt/x"))
    XCTAssertNil(metadata)
  }

  // MARK: - Bash runner

  func testRunPassesCommandAndCwdInRequest() async throws {
    let transport = StubTransport(responses: [
      makeFrame(
        .bash(
          .init(
            exitCode: 0,
            stdout: "hi\n",
            stderr: ""
          )))
    ])
    let client = AgentVsockClient(transportFactory: { transport })

    let result = try await client.run(
      command: "echo hi",
      workingDirectory: URL(fileURLWithPath: "/opt/cwd"),
      timeout: 5
    )

    XCTAssertEqual(result.exitCode, 0)
    XCTAssertEqual(result.stdout, "hi\n")

    let request = try AgentRPCFraming.decode(AgentRPCRequest.self, from: transport.writtenFrames[0])
    guard case .bash(let args) = request else {
      return XCTFail("expected bash request, got \(request)")
    }
    XCTAssertEqual(args.command, "echo hi")
    XCTAssertEqual(args.workingDirectory, "/opt/cwd")
    XCTAssertEqual(args.timeoutSeconds, 5)
  }

  // MARK: - Transport-level errors

  func testTransportConnectFailureSurfacesAsTransportError() async {
    struct ConnectFailure: Error {}
    let client = AgentVsockClient(transportFactory: { throw ConnectFailure() })

    do {
      _ = try await client.readFile(at: URL(fileURLWithPath: "/opt/x"))
      XCTFail("expected transport failure")
    } catch let error as AgentFilesystemError {
      guard case .transportFailure = error else {
        return XCTFail("expected .transportFailure, got \(error)")
      }
    } catch {
      XCTFail("expected AgentFilesystemError, got \(error)")
    }
  }

  // MARK: - Helpers

  private func makeFrame(_ response: AgentRPCResponse) -> Data {
    // swiftlint:disable:next force_try
    try! AgentRPCFraming.encode(response)
  }
}

/// Memory-backed `VsockTransport`. Each round trip drains `responses` head-
/// first. `read(wanted:)` returns the next response in one chunk and signals
/// EOF on the call after that, which is what the client's drain-until-EOF
/// loop expects.
private final class StubTransport: VsockTransport, @unchecked Sendable {
  var writtenFrames: [Data] = []
  private var responseQueue: [Data]
  private var emittedResponse = false

  init(responses: [Data]) {
    self.responseQueue = responses
  }

  func write(_ data: Data) async throws {
    writtenFrames.append(data)
  }

  func read(wanted: Int) async throws -> Data? {
    if emittedResponse { return nil }
    emittedResponse = true
    guard !responseQueue.isEmpty else { return nil }
    return responseQueue.removeFirst()
  }

  func close() async {
    // no-op
  }
}
