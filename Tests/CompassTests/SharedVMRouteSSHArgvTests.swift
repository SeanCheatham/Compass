import Foundation
import XCTest

@testable import Compass

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
      knownHostsFile:
        "/Users/x/Library/Application Support/Compass/SharedVM/bundle.vmbundle/known_hosts"
    )
    let args = SharedCompassVMGuestBridge.sshArguments(
      destination: "compass@10.0.0.42",
      remoteCommand: "true",
      options: options
    )
    XCTAssertTrue(
      args.contains([
        "-o",
        #"UserKnownHostsFile="/Users/x/Library/Application Support/Compass/SharedVM/bundle.vmbundle/known_hosts""#,
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

  // MARK: - ControlMaster multiplexing

  func testSSHArgumentsEnableControlMasterByDefault() {
    // Multiplexing is on by default so agent tool calls reuse a single
    // TCP/SSH session instead of paying ~100ms per spawn.
    let args = SharedCompassVMGuestBridge.sshArguments(
      destination: "compass@10.0.0.42",
      remoteCommand: "true"
    )
    XCTAssertTrue(args.contains(["-o", "ControlMaster=auto"]))
    XCTAssertTrue(
      args.contains([
        "-o", "ControlPath=\(SharedCompassVMGuestBridge.controlPathTemplate)",
      ]))
    XCTAssertTrue(args.contains(["-o", "ControlPersist=600"]))
  }

  func testSSHArgumentsHonorControlPersistOverride() {
    let options = SharedCompassVMGuestBridge.ConnectionOptions(controlPersistSeconds: 120)
    let args = SharedCompassVMGuestBridge.sshArguments(
      destination: "compass@10.0.0.42",
      remoteCommand: "true",
      options: options
    )
    XCTAssertTrue(args.contains(["-o", "ControlPersist=120"]))
    XCTAssertFalse(args.contains(["-o", "ControlPersist=600"]))
  }

  func testSSHArgumentsOmitControlMasterWhenDisabled() {
    let options = SharedCompassVMGuestBridge.ConnectionOptions(useControlMaster: false)
    let args = SharedCompassVMGuestBridge.sshArguments(
      destination: "compass@10.0.0.42",
      remoteCommand: "true",
      options: options
    )
    XCTAssertFalse(args.contains { $0.hasPrefix("ControlMaster=") })
    XCTAssertFalse(args.contains { $0.hasPrefix("ControlPath=") })
    XCTAssertFalse(args.contains { $0.hasPrefix("ControlPersist=") })
  }

  func testControlPathTemplateFitsUnixSocketLimit() {
    // sockaddr_un.sun_path is 104 bytes on macOS; ssh silently disables
    // multiplexing if the resolved socket path exceeds it. Worst-case
    // expansion: IPv6 host (39 chars) + 5-digit port + long user. Keep
    // the template short enough that we never approach the ceiling.
    let template = SharedCompassVMGuestBridge.controlPathTemplate
    let expanded =
      template
      .replacingOccurrences(of: "%h", with: "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff")
      .replacingOccurrences(of: "%p", with: "65535")
      .replacingOccurrences(of: "%r", with: String(repeating: "u", count: 32))
    XCTAssertLessThan(
      expanded.utf8.count, 104,
      "Worst-case ControlPath (\(expanded.utf8.count)B) must fit sockaddr_un.sun_path (104B)."
    )
  }

  // MARK: - closeControlMasterArguments

  func testCloseControlMasterArgumentsEndWithExitAndDestination() {
    let options = SharedCompassVMGuestBridge.ConnectionOptions(
      identityFile: "/path/to/id_ed25519",
      knownHostsFile: "/path/to/known_hosts"
    )
    let args = SharedCompassVMGuestBridge.closeControlMasterArguments(
      destination: "compass@10.0.0.42",
      options: options
    )
    XCTAssertTrue(args.contains(["-i", "/path/to/id_ed25519"]))
    XCTAssertTrue(
      args.contains([
        "-o", "ControlPath=\(SharedCompassVMGuestBridge.controlPathTemplate)",
      ]))
    XCTAssertTrue(args.contains(["-O", "exit"]))
    XCTAssertEqual(args.last, "compass@10.0.0.42")
  }

  func testCloseControlMasterArgumentsOmitRemoteCommand() {
    // `ssh -O exit` is a local control op. It must NOT include a remote
    // command argv — passing one makes ssh complain and the master
    // never gets torn down.
    let args = SharedCompassVMGuestBridge.closeControlMasterArguments(
      destination: "compass@10.0.0.42"
    )
    XCTAssertEqual(args.suffix(3), ["-O", "exit", "compass@10.0.0.42"])
  }

  func testPOSIXQuoteSafePathRequiresNoQuoting() {
    // Sanity check that the safe-character fast path doesn't add ceremony.
    let quoted = SharedCompassVMGuestBridge.posixQuote("/usr/local/bin/swift")
    XCTAssertEqual(quoted, "/usr/local/bin/swift")
  }

  func testPOSIXQuoteEmptyStringBecomesEmptyQuotes() {
    XCTAssertEqual(SharedCompassVMGuestBridge.posixQuote(""), "''")
  }

  func testPOSIXQuoteWhitespacePathIsWrappedInSingleQuotes() {
    XCTAssertEqual(SharedCompassVMGuestBridge.posixQuote("a b"), "'a b'")
  }

  private func makeRoute(
    guestWorkspacePath: String = "/Volumes/Compass/Worktrees"
  ) -> SharedVMRoute {
    SharedVMRoute(
      sshDestination: "compass@10.0.0.42",
      hostWorktreeURL: URL(fileURLWithPath: "/Users/sean/Library/Caches/Compass/Worktrees"),
      guestWorkspacePath: guestWorkspacePath,
      environmentVariables: ["FOO": "bar"],
      identityFile: "/tmp/id_ed25519",
      knownHostsFile: "/tmp/known_hosts"
    )
  }
}

extension Array where Element == String {
  /// Convenience: true if `subarray` appears as a contiguous slice.
  fileprivate func contains(_ subarray: [Element]) -> Bool {
    guard !subarray.isEmpty, subarray.count <= self.count else { return false }
    for start in 0...(self.count - subarray.count) {
      if Array(self[start..<(start + subarray.count)]) == subarray {
        return true
      }
    }
    return false
  }
}
