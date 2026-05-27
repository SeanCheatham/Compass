import CompassAgentRPC
import Foundation
import Testing

@testable import Compass

/// Round-trip tests for the host-side vsock client. A `StubTransport`
/// captures the framed request, plays a canned response, and signals EOF
/// so the framing decoder terminates — no VM, no sockets.
struct AgentVsockClientTests {

  // MARK: - Filesystem

  @Test func testReadFileDecodesBase64ResponseIntoBytes() async throws {
    let payload = Data([0x01, 0x02, 0x03, 0x04])
    let transport = StubTransport(
      responses: [makeFrame(.readFile(.init(dataBase64: payload.base64EncodedString())))]
    )
    let client = AgentVsockClient(transportFactory: { transport })

    let data = try await client.readFile(at: URL(fileURLWithPath: "/opt/x.bin"))

    #require(data == payload)
    #require(transport.writtenFrames.count == 1)
    let request = try AgentRPCFraming.decode(AgentRPCRequest.self, from: transport.writtenFrames[0])
    guard case .readFile(let args) = request else {
      #require(false, "expected readFile request, got \(request)")
      return
    }
    #require(args.path == "/opt/x.bin")
  }

  @Test func testReadFileMapsNotFoundErrorIntoTypedFilesystemError() async {
    let transport = StubTransport(
      responses: [makeFrame(.error(.init(kind: .notFound, detail: "/opt/missing")))]
    )
    let client = AgentVsockClient(transportFactory: { transport })

    do {
      _ = try await client.readFile(at: URL(fileURLWithPath: "/opt/missing"))
      #require(false, "expected notFound error")
    } catch let error as AgentFilesystemError {
      guard case .notFound = error else {
        #require(false, "expected .notFound, got \(error)")
        return
      }
    } catch {
      #require(false, "expected AgentFilesystemError, got \(error)")
    }
  }

  @Test func testWriteFileSendsBase64InRequest() async throws {
    let transport = StubTransport(responses: [makeFrame(.writeFile)])
    let client = AgentVsockClient(transportFactory: { transport })

    let payload = Data("hello".utf8)
    try await client.writeFile(payload, at: URL(fileURLWithPath: "/opt/out.txt"))

    let request = try AgentRPCFraming.decode(AgentRPCRequest.self, from: transport.writtenFrames[0])
    guard case .writeFile(let args) = request else {
      #require(false, "expected writeFile request, got \(request)")
      return
    }
    #require(args.path == "/opt/out.txt")
    #require(args.dataBase64 == payload.base64EncodedString())
  }

  @Test func testListDirectoryParsesEntries() async throws {
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

    #require(entries.count == 2)
    #require(entries.first?.name == "a.swift")
    #require(entries.first?.isDirectory == false)
    #require(entries.last?.name == "Sources")
    #require(entries.last?.isDirectory == true)
  }

  @Test func testGlobReturnsMatchesWithDates() async throws {
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

    #require(matches.count == 2)
    #require(matches[0].url.path == "/opt/x/a.swift")
    #require(matches[0].modificationDate == Date(timeIntervalSince1970: 1_700_000_000))
    #require(matches[1].modificationDate == nil)
  }

  @Test func testStatReturnsNilWhenMetadataIsNil() async throws {
    let transport = StubTransport(responses: [makeFrame(.stat(.init(metadata: nil)))])
    let client = AgentVsockClient(transportFactory: { transport })

    let metadata = try await client.metadata(of: URL(fileURLWithPath: "/opt/x"))
    #require(metadata == nil)
  }

  // MARK: - Bash runner

  @Test func testRunPassesCommandAndCwdInRequest() async throws {
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

    #require(result.exitCode == 0)
    #require(result.stdout == "hi\n")

    let request = try AgentRPCFraming.decode(AgentRPCRequest.self, from: transport.writtenFrames[0])
    guard case .bash(let args) = request else {
      #require(false, "expected bash request, got \(request)")
      return
    }
    #require(args.command == "echo hi")
    #require(args.workingDirectory == "/opt/cwd")
    #require(args.timeoutSeconds == 5)
  }

  // MARK: - Transport-level errors

  @Test func testTransportConnectFailureSurfacesAsTransportError() async {
    struct ConnectFailure: Error {}
    let client = AgentVsockClient(transportFactory: { throw ConnectFailure() })

    do {
      _ = try await client.readFile(at: URL(fileURLWithPath: "/opt/x"))
      #require(false, "expected transport failure")
    } catch let error as AgentFilesystemError {
      guard case .transportFailure = error else {
        #require(false, "expected .transportFailure, got \(error)")
        return
      }
    } catch {
      #require(false, "expected AgentFilesystemError, got \(error)")
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