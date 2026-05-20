import Foundation
@testable import Compass
import XCTest

/// Coverage for the argv builders in `SharedCompassVMGuestBridge` plus the host->guest
/// path translation on `SharedVMRoute`. These are pure functions — no Process, no
/// network — so they're cheap and load-bearing.
final class SharedVMRouteSSHArgvTests: XCTestCase {
    // MARK: - sshArguments

    func testSSHArgumentsIncludeIdentityKnownHostsStrictBatchTAndDestination() {
        let options = SharedCompassVMGuestBridge.ConnectionOptions(
            identityFile: "/path/to/id_ed25519",
            knownHostsFile: "/path/to/known_hosts"
        )

        let args = SharedCompassVMGuestBridge.sshArguments(
            destination: "compass@10.0.0.42",
            remoteCommand: "true",
            options: options
        )

        // -i <identity>
        XCTAssertTrue(args.contains(["-i", "/path/to/id_ed25519"]))
        // -o UserKnownHostsFile="<file>" — value is inner-quoted so
        // ssh's parser treats paths-with-spaces as a single file.
        XCTAssertTrue(args.contains(["-o", #"UserKnownHostsFile="/path/to/known_hosts""#]))
        // -o StrictHostKeyChecking=yes
        XCTAssertTrue(args.contains(["-o", "StrictHostKeyChecking=yes"]))
        // -o BatchMode=yes
        XCTAssertTrue(args.contains(["-o", "BatchMode=yes"]))
        // -T (no PTY)
        XCTAssertTrue(args.contains("-T"))
        // destination + remoteCommand are the trailing two arguments.
        XCTAssertEqual(args.suffix(2), ["compass@10.0.0.42", "true"])
    }

    func testSSHArgumentsOmitIdentityAndKnownHostsWhenNil() {
        let options = SharedCompassVMGuestBridge.ConnectionOptions(
            identityFile: nil,
            knownHostsFile: nil
        )
        let args = SharedCompassVMGuestBridge.sshArguments(
            destination: "compass@10.0.0.1",
            remoteCommand: "echo hi",
            options: options
        )
        XCTAssertFalse(args.contains("-i"))
        XCTAssertFalse(args.contains { $0.hasPrefix("UserKnownHostsFile=") })
    }

    func testSSHArgumentsIncludeConnectTimeoutWhenSet() {
        let options = SharedCompassVMGuestBridge.ConnectionOptions(connectTimeoutSeconds: 7)
        let args = SharedCompassVMGuestBridge.sshArguments(
            destination: "compass@10.0.0.7",
            remoteCommand: "true",
            options: options
        )
        XCTAssertTrue(args.contains(["-o", "ConnectTimeout=7"]))
    }

    func testSSHArgumentsDoNotIncludeConnectTimeoutWhenNil() {
        let options = SharedCompassVMGuestBridge.ConnectionOptions()
        let args = SharedCompassVMGuestBridge.sshArguments(
            destination: "compass@10.0.0.7",
            remoteCommand: "true",
            options: options
        )
        XCTAssertFalse(args.contains { $0.hasPrefix("ConnectTimeout=") })
    }

    func testSSHArgumentsQuoteKnownHostsPathWithSpacesAsSingleToken() {
        // ssh's UserKnownHostsFile option treats unquoted whitespace
        // in its value as a separator between multiple files (per
        // `man ssh_config`). Compass's bundle lives under
        // `~/Library/Application Support/...` which contains a space.
        // If we emit the option unquoted, ssh splits the path into
        // two bogus files and `Host key verification failed` even
        // when known_hosts is correctly populated. The inner double
        // quotes here keep the path as a single file from ssh's
        // perspective. Locking this in so a well-meaning refactor
        // doesn't strip the quotes and silently reintroduce the
        // first-boot SSH deadlock.
        let options = SharedCompassVMGuestBridge.ConnectionOptions(
            knownHostsFile: "/Users/x/Library/Application Support/Compass/SharedVM/bundle.vmbundle/known_hosts"
        )
        let args = SharedCompassVMGuestBridge.sshArguments(
            destination: "compass@10.0.0.42",
            remoteCommand: "true",
            options: options
        )
        XCTAssertTrue(
            args.contains([
                "-o",
                #"UserKnownHostsFile="/Users/x/Library/Application Support/Compass/SharedVM/bundle.vmbundle/known_hosts""#
            ]),
            "known_hosts path with spaces must be inner-quoted so ssh sees one file, not many"
        )
    }

    func testSSHArgumentsHonorStrictHostKeyCheckingDisabled() {
        let options = SharedCompassVMGuestBridge.ConnectionOptions(strictHostKeyChecking: false)
        let args = SharedCompassVMGuestBridge.sshArguments(
            destination: "compass@host",
            remoteCommand: "true",
            options: options
        )
        XCTAssertTrue(args.contains(["-o", "StrictHostKeyChecking=no"]))
        XCTAssertFalse(args.contains(["-o", "StrictHostKeyChecking=yes"]))
    }

    func testDefaultExecutablePathIsUsrBinSSH() {
        XCTAssertEqual(SharedCompassVMGuestBridge.defaultSSHExecutablePath, "/usr/bin/ssh")
    }

    // MARK: - buildRemoteCodexCommand

    func testRemoteCommandIncludesCdWorkspaceAndCodexInvocation() {
        let cmd = SharedCompassVMGuestBridge.buildRemoteCodexCommand(
            guestWorkspacePath: "/Volumes/Compass/workspace",
            guestCodexPath: "/usr/local/bin/codex",
            environmentVariables: [:],
            codexArguments: ["exec", "--sandbox", "danger-full-access", "--cd", "."]
        )

        XCTAssertTrue(cmd.contains("cd /Volumes/Compass/workspace &&"), cmd)
        XCTAssertTrue(cmd.contains("/usr/local/bin/codex"), cmd)
        XCTAssertTrue(cmd.contains("exec"), cmd)
        XCTAssertTrue(cmd.contains("--sandbox"), cmd)
        XCTAssertTrue(cmd.contains("danger-full-access"), cmd)
    }

    func testRemoteCommandSortsEnvironmentVariablesDeterministically() {
        let cmd = SharedCompassVMGuestBridge.buildRemoteCodexCommand(
            guestWorkspacePath: "/work",
            guestCodexPath: "/usr/local/bin/codex",
            environmentVariables: [
                "B_VAR": "two",
                "A_VAR": "one",
                "C_VAR": "three"
            ],
            codexArguments: ["exec"]
        )

        // env A_VAR=one B_VAR=two C_VAR=three /usr/local/bin/codex exec
        XCTAssertTrue(cmd.contains("env A_VAR=one B_VAR=two C_VAR=three "), cmd)

        // A_VAR must appear before B_VAR which must appear before C_VAR
        guard
            let aRange = cmd.range(of: "A_VAR=one"),
            let bRange = cmd.range(of: "B_VAR=two"),
            let cRange = cmd.range(of: "C_VAR=three")
        else {
            XCTFail("Missing env entries in: \(cmd)")
            return
        }
        XCTAssertLessThan(aRange.lowerBound, bRange.lowerBound)
        XCTAssertLessThan(bRange.lowerBound, cRange.lowerBound)
    }

    func testRemoteCommandOmitsEnvPrefixWhenEnvironmentIsEmpty() {
        let cmd = SharedCompassVMGuestBridge.buildRemoteCodexCommand(
            guestWorkspacePath: "/work",
            guestCodexPath: "/usr/local/bin/codex",
            environmentVariables: [:],
            codexArguments: ["exec"]
        )
        XCTAssertFalse(cmd.contains(" env "), cmd)
        XCTAssertFalse(cmd.hasPrefix("env "), cmd)
    }

    func testRemoteCommandQuotesPathContainingSingleQuoteForShellSafety() {
        // POSIX single-quote escape rule: ' becomes '\'' inside a single-quoted string.
        // Verify that a workspace path with an embedded single quote (which would
        // otherwise let an attacker break out of the quoting context) is escaped.
        let cmd = SharedCompassVMGuestBridge.buildRemoteCodexCommand(
            guestWorkspacePath: "/work/it's tricky",
            guestCodexPath: "/usr/local/bin/codex",
            environmentVariables: [:],
            codexArguments: ["exec"]
        )

        // The escaped form must appear in the rendered command.
        XCTAssertTrue(cmd.contains(#"'\''"#), "Single quote was not POSIX-escaped: \(cmd)")
        // The original raw single quote sequence must NOT appear naked (i.e. without
        // the escape) — otherwise a user-supplied path could close the quoting and
        // inject shell syntax.
        XCTAssertFalse(cmd.contains("/work/it's tricky &&"), "Raw unescaped single quote leaked into shell command: \(cmd)")
    }

    func testRemoteCommandQuotesEnvValuesContainingShellMetacharacters() {
        let cmd = SharedCompassVMGuestBridge.buildRemoteCodexCommand(
            guestWorkspacePath: "/work",
            guestCodexPath: "/usr/local/bin/codex",
            environmentVariables: [
                "DANGER": "$(rm -rf /)"
            ],
            codexArguments: ["exec"]
        )
        // The substitution metacharacter must be enclosed in single quotes so the
        // remote shell does not interpret it.
        XCTAssertTrue(cmd.contains("DANGER='$(rm -rf /)'"), cmd)
    }

    func testPOSIXQuoteSafePathRequiresNoQuoting() {
        // Sanity check that the safe-character fast path doesn't add ceremony.
        let quoted = SharedCompassVMGuestBridge.posixQuote("/usr/local/bin/codex")
        XCTAssertEqual(quoted, "/usr/local/bin/codex")
    }

    func testPOSIXQuoteEmptyStringBecomesEmptyQuotes() {
        XCTAssertEqual(SharedCompassVMGuestBridge.posixQuote(""), "''")
    }

    func testPOSIXQuoteWhitespacePathIsWrappedInSingleQuotes() {
        XCTAssertEqual(SharedCompassVMGuestBridge.posixQuote("a b"), "'a b'")
    }

    // MARK: - SharedVMRoute.guestPath(forHostURL:)

    func testGuestPathMapsHostFileBeneathWorktreeRootIntoGuestWorkspace() {
        let route = makeRoute()
        let hostFile = URL(fileURLWithPath: "/Users/sean/Library/Caches/Compass/Worktrees/projectA/Sources/Main.swift")
        let guestPath = route.guestPath(forHostURL: hostFile)
        XCTAssertEqual(
            guestPath,
            "/Volumes/Compass/Worktrees/projectA/Sources/Main.swift"
        )
    }

    func testGuestPathReturnsWorkspaceRootForExactWorktreeRootURL() {
        let route = makeRoute()
        let hostRoot = URL(fileURLWithPath: "/Users/sean/Library/Caches/Compass/Worktrees")
        XCTAssertEqual(route.guestPath(forHostURL: hostRoot), "/Volumes/Compass/Worktrees")
    }

    func testGuestPathReturnsNilForURLOutsideWorktreeRoot() {
        let route = makeRoute()
        let outsideURL = URL(fileURLWithPath: "/tmp/elsewhere/file.txt")
        XCTAssertNil(route.guestPath(forHostURL: outsideURL))
    }

    func testGuestPathReturnsNilForSiblingWithSharedPrefixButDifferentBoundary() {
        // /Worktrees vs /Worktrees-other — prefix-similar but NOT under root.
        let route = makeRoute()
        let sibling = URL(fileURLWithPath: "/Users/sean/Library/Caches/Compass/Worktrees-other/projectB/file.swift")
        XCTAssertNil(route.guestPath(forHostURL: sibling))
    }

    private func makeRoute(
        guestWorkspacePath: String = "/Volumes/Compass/Worktrees"
    ) -> SharedVMRoute {
        SharedVMRoute(
            sshDestination: "compass@10.0.0.42",
            hostWorktreeURL: URL(fileURLWithPath: "/Users/sean/Library/Caches/Compass/Worktrees"),
            guestWorkspacePath: guestWorkspacePath,
            guestCodexPath: "/usr/local/bin/codex",
            environmentVariables: ["FOO": "bar"],
            identityFile: "/tmp/id_ed25519",
            knownHostsFile: "/tmp/known_hosts"
        )
    }
}

private extension Array where Element == String {
    /// Convenience: true if `subarray` appears as a contiguous slice.
    func contains(_ subarray: [Element]) -> Bool {
        guard !subarray.isEmpty, subarray.count <= self.count else { return false }
        for start in 0...(self.count - subarray.count) {
            if Array(self[start..<(start + subarray.count)]) == subarray {
                return true
            }
        }
        return false
    }
}
