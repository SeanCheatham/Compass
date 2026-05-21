import Foundation
@testable import Compass
import XCTest

/// Verifies that `AgentSharedVMFilesystem` builds the right SSH invocation,
/// pipes stdin where appropriate, and maps the remote script's exit code
/// back into a typed `AgentFilesystemError`. The tests stub out the remote
/// runner so no `ssh` subprocess is ever spawned.
final class AgentSharedVMFilesystemTests: XCTestCase {

    // MARK: - readFile

    func testReadFileBase64DecodesStdoutOnExit0() async throws {
        let payload = Data([0x68, 0x69, 0x21]) // "hi!"
        let recorder = RemoteRunnerRecorder(
            result: ProcessResult(exitCode: 0, stdout: payload.base64EncodedString(), stderr: "")
        )
        let fs = makeFilesystem(recorder: recorder)
        let url = URL(fileURLWithPath: "/opt/compass/workspaces/proj/file.txt")

        let data = try await fs.readFile(at: url)

        XCTAssertEqual(data, payload)
        XCTAssertEqual(recorder.calls.count, 1)
        let script = recorder.calls[0].arguments.last ?? ""
        XCTAssertTrue(script.contains("base64 <"), "Read should base64-encode the remote file: \(script)")
        // The path consists entirely of POSIX-safe characters so `posixQuote`
        // emits it bare. Asserting against the variable assignment is enough.
        XCTAssertTrue(
            script.contains("p=/opt/compass/workspaces/proj/file.txt"),
            "Read should bind the guest path to $p: \(script)"
        )
    }

    func testReadFileTranslatesNotFoundExit() async throws {
        let fs = makeFilesystem(
            recorder: RemoteRunnerRecorder(
                result: ProcessResult(exitCode: 64, stdout: "", stderr: "")
            )
        )
        let url = URL(fileURLWithPath: "/opt/compass/workspaces/proj/missing.txt")

        await assertThrowsFilesystemError(.notFound(url)) {
            _ = try await fs.readFile(at: url)
        }
    }

    func testReadFileTranslatesNotRegularFileExit() async throws {
        let fs = makeFilesystem(
            recorder: RemoteRunnerRecorder(
                result: ProcessResult(exitCode: 65, stdout: "", stderr: "")
            )
        )
        let url = URL(fileURLWithPath: "/opt/compass/workspaces/proj/Sources")

        await assertThrowsFilesystemError(.notRegularFile(url)) {
            _ = try await fs.readFile(at: url)
        }
    }

    func testReadFileTreatsSSHExit255AsTransportFailure() async throws {
        let fs = makeFilesystem(
            recorder: RemoteRunnerRecorder(
                result: ProcessResult(exitCode: 255, stdout: "", stderr: "kex_exchange_identification")
            )
        )
        let url = URL(fileURLWithPath: "/opt/compass/workspaces/proj/file.txt")

        do {
            _ = try await fs.readFile(at: url)
            XCTFail("expected transport failure")
        } catch let error as AgentFilesystemError {
            guard case let .transportFailure(detail) = error else {
                return XCTFail("expected .transportFailure, got \(error)")
            }
            XCTAssertTrue(detail.contains("kex_exchange_identification"))
        }
    }

    // MARK: - writeFile

    func testWriteFileSendsBase64OnStdinAndTargetsAtomicMv() async throws {
        let recorder = RemoteRunnerRecorder(
            result: ProcessResult(exitCode: 0, stdout: "", stderr: "")
        )
        let fs = makeFilesystem(recorder: recorder)
        let url = URL(fileURLWithPath: "/opt/compass/workspaces/proj/Subdir/out.txt")
        let payload = Data("hello world".utf8)

        try await fs.writeFile(payload, at: url)

        XCTAssertEqual(recorder.calls.count, 1)
        let call = recorder.calls[0]
        XCTAssertEqual(call.stdin, payload.base64EncodedString(), "stdin must be base64 of the requested bytes")
        let script = call.arguments.last ?? ""
        XCTAssertTrue(script.contains("base64 -d > \"$tmp\""), "Write must stage through a sibling tempfile: \(script)")
        XCTAssertTrue(script.contains("mv -- \"$tmp\" \"$p\""), "Write must commit atomically via mv: \(script)")
        XCTAssertTrue(script.contains("mkdir -p -- \"$parent\""), "Write must create intermediate directories: \(script)")
    }

    func testWriteFileRefusesWhenTargetIsADirectory() async throws {
        let fs = makeFilesystem(
            recorder: RemoteRunnerRecorder(
                result: ProcessResult(exitCode: 65, stdout: "", stderr: "")
            )
        )
        let url = URL(fileURLWithPath: "/opt/compass/workspaces/proj/Sources")

        await assertThrowsFilesystemError(.notRegularFile(url)) {
            try await fs.writeFile(Data("x".utf8), at: url)
        }
    }

    // MARK: - metadata

    func testMetadataParsesTypeSizeMtime() async throws {
        let fs = makeFilesystem(
            recorder: RemoteRunnerRecorder(
                result: ProcessResult(exitCode: 0, stdout: "f|1234|1700000000\n", stderr: "")
            )
        )
        let url = URL(fileURLWithPath: "/opt/compass/workspaces/proj/x.txt")

        let metadata = try await fs.metadata(of: url)

        XCTAssertNotNil(metadata)
        XCTAssertEqual(metadata?.size, 1234)
        XCTAssertEqual(metadata?.isRegularFile, true)
        XCTAssertEqual(metadata?.isDirectory, false)
        XCTAssertEqual(metadata?.modificationDate, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testMetadataReturnsNilOnNotFoundExit() async throws {
        let fs = makeFilesystem(
            recorder: RemoteRunnerRecorder(
                result: ProcessResult(exitCode: 64, stdout: "", stderr: "")
            )
        )
        let url = URL(fileURLWithPath: "/opt/compass/workspaces/proj/missing")
        let metadata = try await fs.metadata(of: url)
        XCTAssertNil(metadata)
    }

    // MARK: - listDirectory

    func testListDirectoryParsesTypeTabPathOutput() async throws {
        let stdout = """
        d\t/opt/compass/workspaces/proj/Sources
        d\t/opt/compass/workspaces/proj/Tests
        f\t/opt/compass/workspaces/proj/README.md
        f\t/opt/compass/workspaces/proj/.gitignore
        """
        let fs = makeFilesystem(
            recorder: RemoteRunnerRecorder(
                result: ProcessResult(exitCode: 0, stdout: stdout, stderr: "")
            )
        )
        let url = URL(fileURLWithPath: "/opt/compass/workspaces/proj")

        let entries = try await fs.listDirectory(at: url)

        XCTAssertEqual(entries.count, 4)
        XCTAssertEqual(entries.map(\.name).sorted(), [".gitignore", "README.md", "Sources", "Tests"])
        XCTAssertTrue(entries.first(where: { $0.name == "Sources" })?.isDirectory == true)
        XCTAssertTrue(entries.first(where: { $0.name == "README.md" })?.isDirectory == false)
    }

    func testListDirectoryTranslatesNotDirectoryExit() async throws {
        let fs = makeFilesystem(
            recorder: RemoteRunnerRecorder(
                result: ProcessResult(exitCode: 66, stdout: "", stderr: "")
            )
        )
        let url = URL(fileURLWithPath: "/opt/compass/workspaces/proj/README.md")

        await assertThrowsFilesystemError(.notDirectory(url)) {
            _ = try await fs.listDirectory(at: url)
        }
    }

    // MARK: - glob

    func testGlobFiltersStdoutAgainstPatternAndPreservesMtime() async throws {
        // Two .swift files at different mtimes plus a .md that must be filtered out.
        let stdout = """
        1700000000\t/opt/compass/workspaces/proj/Sources/Old.swift
        1700001000\t/opt/compass/workspaces/proj/Sources/New.swift
        1700002000\t/opt/compass/workspaces/proj/README.md
        """
        let fs = makeFilesystem(
            recorder: RemoteRunnerRecorder(
                result: ProcessResult(exitCode: 0, stdout: stdout, stderr: "")
            )
        )
        let root = URL(fileURLWithPath: "/opt/compass/workspaces/proj")

        let matches = try await fs.glob(pattern: "**/*.swift", under: root, walkCap: 1000)

        XCTAssertEqual(matches.count, 2)
        XCTAssertEqual(matches.map(\.url.path).sorted(), [
            "/opt/compass/workspaces/proj/Sources/New.swift",
            "/opt/compass/workspaces/proj/Sources/Old.swift"
        ])
        XCTAssertEqual(
            matches.first(where: { $0.url.path.hasSuffix("New.swift") })?.modificationDate,
            Date(timeIntervalSince1970: 1_700_001_000)
        )
    }

    func testGlobTreatsNotDirectoryExitAsTypedError() async throws {
        let fs = makeFilesystem(
            recorder: RemoteRunnerRecorder(
                result: ProcessResult(exitCode: 66, stdout: "", stderr: "")
            )
        )
        let root = URL(fileURLWithPath: "/opt/compass/workspaces/proj/README.md")

        await assertThrowsFilesystemError(.notDirectory(root)) {
            _ = try await fs.glob(pattern: "**/*.swift", under: root, walkCap: 100)
        }
    }

    // MARK: - grep

    func testGrepRoutesThroughSSHAndPassesThroughExitAndStdout() async throws {
        let recorder = RemoteRunnerRecorder(
            result: ProcessResult(exitCode: 0, stdout: "Sources/Foo.swift:10:needle", stderr: "")
        )
        let fs = makeFilesystem(recorder: recorder)
        let url = URL(fileURLWithPath: "/opt/compass/workspaces/proj")

        let result = try await fs.grep(
            pattern: "needle",
            in: url,
            glob: "*.swift",
            caseInsensitive: false,
            timeout: 5
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("needle"))
        let script = recorder.calls[0].arguments.last ?? ""
        XCTAssertTrue(
            script.contains("command -v rg"),
            "grep should prefer ripgrep when available on the guest: \(script)"
        )
        XCTAssertTrue(script.contains("--glob '*.swift'"), "grep should pass the glob through: \(script)")
        // Target path is POSIX-safe so it passes through bare.
        XCTAssertTrue(
            script.contains("/opt/compass/workspaces/proj"),
            "grep should target the requested guest path: \(script)"
        )
    }

    // MARK: - Helpers

    private func makeFilesystem(recorder: RemoteRunnerRecorder) -> AgentSharedVMFilesystem {
        AgentSharedVMFilesystem(
            route: SharedVMRoute(
                sshDestination: "compass@10.0.0.42",
                hostWorktreeURL: URL(fileURLWithPath: "/Users/sean/Library/Caches/Compass/Worktrees"),
                guestWorkspacePath: "/opt/compass/workspaces",
                identityFile: "/tmp/id_ed25519",
                knownHostsFile: "/tmp/known_hosts"
            ),
            remoteRunner: recorder.run
        )
    }

    private func assertThrowsFilesystemError(
        _ expected: AgentFilesystemError,
        _ block: () async throws -> Void
    ) async {
        do {
            try await block()
            XCTFail("expected \(expected) to be thrown")
        } catch let error as AgentFilesystemError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("expected AgentFilesystemError, got \(error)")
        }
    }
}

/// Records each `remoteRunner` invocation and returns a pre-supplied
/// ProcessResult. Mutable from the closure via a lock-free serial actor —
/// each test calls the runner one or two times.
private final class RemoteRunnerRecorder: @unchecked Sendable {
    struct Call: Equatable {
        var arguments: [String]
        var stdin: String?
        var timeout: TimeInterval
    }

    var calls: [Call] = []
    let result: ProcessResult

    init(result: ProcessResult) {
        self.result = result
    }

    func run(
        arguments: [String],
        stdin: String?,
        timeout: TimeInterval
    ) async throws -> ProcessResult {
        calls.append(Call(arguments: arguments, stdin: stdin, timeout: timeout))
        return result
    }
}
