import XCTest
@testable import Compass

/// Coverage for `SharedCompassVMCodexAuthBridge.wrapRemoteCommandWithPATH`.
/// The wrapper is the load-bearing defence against the macOS sshd quirk
/// where non-interactive remote commands run with
/// `PATH=/usr/bin:/bin:/usr/sbin:/sbin` — no `/usr/local/bin`, so a bare
/// `command -v codex` can't see the binary the bootstrap script installed.
/// Earlier this failure mode short-circuited the auth pipeline to
/// `.indeterminate` and starved the `copyHostCodexCredentialsToGuest`
/// fallback before it ever ran.
final class SharedCompassVMCodexAuthBridgePATHWrapTests: XCTestCase {
    func testWrapPrependsUsrLocalBinExportAndPreservesCommand() {
        let wrapped = SharedCompassVMCodexAuthBridge.wrapRemoteCommandWithPATH("command -v codex")
        XCTAssertEqual(
            wrapped,
            #"export PATH="/usr/local/bin:$PATH"; command -v codex"#
        )
    }

    func testWrapKeepsRemotePATHReferenceEscapedForRemoteShellExpansion() {
        // Critical: the `$PATH` reference inside the wrapper must
        // reach the remote shell as a literal `$PATH` so it expands
        // there (against the guest's environment), NOT in any
        // intermediate host-side string interpolation. If a refactor
        // accidentally collapsed `$PATH` against an empty host env
        // var, the wrapper would set PATH to just `/usr/local/bin:`
        // and effectively wipe the rest of the search path inside
        // the guest.
        let wrapped = SharedCompassVMCodexAuthBridge.wrapRemoteCommandWithPATH("true")
        XCTAssertTrue(wrapped.contains("$PATH"), "remote $PATH ref must survive into the SSH payload verbatim")
        XCTAssertFalse(wrapped.contains("$PATH${"), "no accidental Swift-style brace expansion")
    }

    func testWrapComposesCleanlyWithCompoundShellExpressions() {
        // The wrapper must compose with `if/then/fi` and pipelines so
        // it can wrap any of the three probe commands without
        // breaking them. A bare `PATH=… <command>` prefix wouldn't —
        // `PATH=… if [ -s … ]; then …` is a shell syntax error. The
        // wrapper uses `export …;` so it's a complete statement and
        // the next statement starts fresh.
        let wrapped = SharedCompassVMCodexAuthBridge.wrapRemoteCommandWithPATH(
            "if [ -s \"$HOME/.codex/auth.json\" ]; then echo present; else echo absent; fi"
        )
        XCTAssertTrue(wrapped.hasPrefix(#"export PATH="/usr/local/bin:$PATH"; "#))
        XCTAssertTrue(wrapped.contains("if [ -s \"$HOME/.codex/auth.json\" ]; then echo present;"))
    }
}
