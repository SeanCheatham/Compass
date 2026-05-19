import XCTest
@testable import Compass

final class SharedCompassVMFirstBootScriptTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
    }

    func testScriptContentWithCodexBlockIncludesInstallStep() {
        let body = SharedCompassVMFirstBootScript.scriptContent(includesCodex: true)
        XCTAssertTrue(body.contains("sudo install -m 755 \"$FIRSTBOOT_DIR/codex\" /usr/local/bin/codex"))
        XCTAssertTrue(body.contains("[4/4] Installing codex"))
        XCTAssertFalse(body.contains("No codex binary shipped"))
    }

    func testScriptContentWithoutCodexBlockSurfacesManualInstallNotice() {
        let body = SharedCompassVMFirstBootScript.scriptContent(includesCodex: false)
        XCTAssertTrue(body.contains("No codex binary shipped"))
        XCTAssertFalse(body.contains("sudo install -m 755"))
    }

    func testScriptContentAlwaysIncludesSSHKeyAndSymlinkAndRemoteLoginSteps() {
        for includesCodex in [true, false] {
            let body = SharedCompassVMFirstBootScript.scriptContent(includesCodex: includesCodex)
            XCTAssertTrue(body.contains("[1/4] Authorising Compass SSH key"))
            XCTAssertTrue(body.contains("[2/4] Creating /opt/compass/workspaces"))
            XCTAssertTrue(body.contains("[3/4] Enabling Remote Login"))
            XCTAssertTrue(body.contains("sudo systemsetup -setremotelogin on"))
            XCTAssertTrue(body.contains("sudo ln -s \"$SHARE_ROOT\" /opt/compass/workspaces"))
        }
    }

    func testScriptStartsWithBashShebangAndSetEUOPipefail() {
        let body = SharedCompassVMFirstBootScript.scriptContent(includesCodex: true)
        XCTAssertTrue(body.hasPrefix("#!/bin/bash"))
        XCTAssertTrue(body.contains("set -euo pipefail"))
    }

    func testMaterializeWritesScriptAndPublicKeyIntoFirstBootDirectory() throws {
        let (workspacesRoot, publicKey, _) = try makeFixtures()

        let layout = try SharedCompassVMFirstBootScript.materialize(
            workspacesRootURL: workspacesRoot,
            publicKeyURL: publicKey,
            codexBinaryPath: nil
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.scriptURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.publicKeyURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.codexBinaryURL.path))

        let scriptBody = try String(contentsOf: layout.scriptURL, encoding: .utf8)
        XCTAssertTrue(scriptBody.contains("No codex binary shipped"))

        let perms = try FileManager.default.attributesOfItem(atPath: layout.scriptURL.path)
        if let posix = perms[.posixPermissions] as? NSNumber {
            XCTAssertEqual(posix.intValue, 0o755)
        } else {
            XCTFail("expected posix permissions on the rendered script")
        }
    }

    func testMaterializeCopiesCodexBinaryAndRendersInstallBlock() throws {
        let (workspacesRoot, publicKey, codexPath) = try makeFixtures(stagingCodex: true)

        let layout = try SharedCompassVMFirstBootScript.materialize(
            workspacesRootURL: workspacesRoot,
            publicKeyURL: publicKey,
            codexBinaryPath: codexPath
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.codexBinaryURL.path))
        let scriptBody = try String(contentsOf: layout.scriptURL, encoding: .utf8)
        XCTAssertTrue(scriptBody.contains("[4/4] Installing codex"))
    }

    func testMaterializeRefreshesArtifactsIdempotently() throws {
        let (workspacesRoot, publicKey, codexPath) = try makeFixtures(stagingCodex: true)

        _ = try SharedCompassVMFirstBootScript.materialize(
            workspacesRootURL: workspacesRoot,
            publicKeyURL: publicKey,
            codexBinaryPath: codexPath
        )
        // Re-running with nil should drop the previously-staged codex copy.
        let layout = try SharedCompassVMFirstBootScript.materialize(
            workspacesRootURL: workspacesRoot,
            publicKeyURL: publicKey,
            codexBinaryPath: nil
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.codexBinaryURL.path))
        let scriptBody = try String(contentsOf: layout.scriptURL, encoding: .utf8)
        XCTAssertTrue(scriptBody.contains("No codex binary shipped"))
    }

    func testMaterializeSkipsDirectoryCodexPath() throws {
        let (workspacesRoot, publicKey, _) = try makeFixtures()
        // Point at a directory; helper must reject non-regular-file inputs.
        let dirAsCodex = workspacesRoot.appendingPathComponent("codex-dir", isDirectory: true)
        try FileManager.default.createDirectory(at: dirAsCodex, withIntermediateDirectories: true)

        let layout = try SharedCompassVMFirstBootScript.materialize(
            workspacesRootURL: workspacesRoot,
            publicKeyURL: publicKey,
            codexBinaryPath: dirAsCodex.path
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.codexBinaryURL.path))
        let scriptBody = try String(contentsOf: layout.scriptURL, encoding: .utf8)
        XCTAssertTrue(scriptBody.contains("No codex binary shipped"))
    }

    func testGuestRunCommandPointsAtTheStagedScriptPath() {
        XCTAssertEqual(
            SharedCompassVMFirstBootScript.guestRunCommand,
            #"bash "/Volumes/My Shared Files/compass-workspaces/.compass-firstboot/install.sh""#
        )
    }

    // MARK: - Fixtures

    private func makeFixtures(stagingCodex: Bool = false) throws -> (URL, URL, String) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CompassFirstBoot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        temporaryDirectories.append(root)

        let workspacesRoot = root.appendingPathComponent("workspaces", isDirectory: true)
        try FileManager.default.createDirectory(at: workspacesRoot, withIntermediateDirectories: true)

        let publicKey = root.appendingPathComponent("id_ed25519.pub", isDirectory: false)
        try "ssh-ed25519 AAAA fake-compass-key\n".write(to: publicKey, atomically: true, encoding: .utf8)

        let codexPath = root.appendingPathComponent("codex", isDirectory: false).path
        if stagingCodex {
            FileManager.default.createFile(
                atPath: codexPath,
                contents: Data("#!/bin/sh\necho fake\n".utf8),
                attributes: [.posixPermissions: 0o755]
            )
        }

        return (workspacesRoot, publicKey, codexPath)
    }
}
