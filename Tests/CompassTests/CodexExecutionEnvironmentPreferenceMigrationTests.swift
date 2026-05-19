import Foundation
@testable import Compass
import XCTest

/// Migration coverage for the Phase 5/6 pivot: the persisted record schema gained a
/// new `developSandbox` field while `codexExecutionEnvironmentPreference` retains its
/// existing meaning. Old records on disk must still decode cleanly, and the legacy
/// `devcontainer_preferred` raw value must NOT auto-enrol into the shared VM.
final class CodexExecutionEnvironmentPreferenceMigrationTests: XCTestCase {
    func testLegacyDevcontainerPreferredDecodesAsHostAndDevelopSandboxDefaultsToHost() throws {
        let record = try decodeRecord("""
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "path": "/tmp/legacy-devcontainer",
          "addedAt": 1,
          "lastOpenedAt": 2,
          "codexExecutionEnvironmentPreference": "devcontainer_preferred"
        }
        """)

        XCTAssertEqual(record.codexExecutionEnvironmentPreference, .host)
        XCTAssertEqual(record.developSandbox, .host)
    }

    func testNativeMacosRawValueDecodesAsHostPreference() throws {
        let record = try decodeRecord("""
        {
          "id": "22222222-2222-2222-2222-222222222222",
          "path": "/tmp/native-macos",
          "addedAt": 3,
          "lastOpenedAt": 4,
          "codexExecutionEnvironmentPreference": "native_macos"
        }
        """)

        XCTAssertEqual(record.codexExecutionEnvironmentPreference, .host)
    }

    func testSharedVMRawValueDecodesAsSharedVMPreference() throws {
        let record = try decodeRecord("""
        {
          "id": "33333333-3333-3333-3333-333333333333",
          "path": "/tmp/shared-vm",
          "addedAt": 5,
          "lastOpenedAt": 6,
          "codexExecutionEnvironmentPreference": "shared_vm"
        }
        """)

        XCTAssertEqual(record.codexExecutionEnvironmentPreference, .sharedVM)
    }

    func testRecordWithoutDevelopSandboxKeyDefaultsToHost() throws {
        let record = try decodeRecord("""
        {
          "id": "44444444-4444-4444-4444-444444444444",
          "path": "/tmp/no-develop-sandbox",
          "addedAt": 7,
          "lastOpenedAt": 8
        }
        """)

        XCTAssertEqual(record.developSandbox, .host)
    }

    func testRecordWithDevelopSandboxSharedVMDecodesCorrectly() throws {
        let record = try decodeRecord("""
        {
          "id": "55555555-5555-5555-5555-555555555555",
          "path": "/tmp/develop-sandbox-shared-vm",
          "addedAt": 9,
          "lastOpenedAt": 10,
          "developSandbox": "shared_vm"
        }
        """)

        XCTAssertEqual(record.developSandbox, .sharedVM)
    }

    func testRecordWithDevelopSandboxHostDecodesCorrectly() throws {
        let record = try decodeRecord("""
        {
          "id": "66666666-6666-6666-6666-666666666666",
          "path": "/tmp/develop-sandbox-host",
          "addedAt": 11,
          "lastOpenedAt": 12,
          "developSandbox": "host"
        }
        """)

        XCTAssertEqual(record.developSandbox, .host)
    }

    func testDevcontainerPreferredDoesNotImplicitlyEnrolDevelopSandboxIntoSharedVM() throws {
        // Critical pivot semantics: even though some users had selected the
        // pre-pivot "devcontainer_preferred" option, the migration MUST NOT
        // flip their per-project sandbox into the shared VM. Both fields land
        // on .host.
        let record = try decodeRecord("""
        {
          "id": "77777777-7777-7777-7777-777777777777",
          "path": "/tmp/no-implicit-enrolment",
          "addedAt": 13,
          "lastOpenedAt": 14,
          "codexExecutionEnvironmentPreference": "devcontainer_preferred"
        }
        """)

        XCTAssertEqual(record.developSandbox, .host, "Legacy devcontainer_preferred must NOT auto-enrol into shared VM")
        XCTAssertNotEqual(record.developSandbox, .sharedVM)
    }

    func testCodexExecutionEnvironmentPreferenceAndDevelopSandboxAreIndependent() throws {
        // A record may legitimately store .host for the env preference and
        // .sharedVM for developSandbox, or vice-versa.
        let envHostSandboxShared = try decodeRecord("""
        {
          "id": "88888888-8888-8888-8888-888888888888",
          "path": "/tmp/host-shared",
          "addedAt": 15,
          "lastOpenedAt": 16,
          "codexExecutionEnvironmentPreference": "native_macos",
          "developSandbox": "shared_vm"
        }
        """)
        XCTAssertEqual(envHostSandboxShared.codexExecutionEnvironmentPreference, .host)
        XCTAssertEqual(envHostSandboxShared.developSandbox, .sharedVM)

        let envSharedSandboxHost = try decodeRecord("""
        {
          "id": "99999999-9999-9999-9999-999999999999",
          "path": "/tmp/shared-host",
          "addedAt": 17,
          "lastOpenedAt": 18,
          "codexExecutionEnvironmentPreference": "shared_vm",
          "developSandbox": "host"
        }
        """)
        XCTAssertEqual(envSharedSandboxHost.codexExecutionEnvironmentPreference, .sharedVM)
        XCTAssertEqual(envSharedSandboxHost.developSandbox, .host)
    }

    private func decodeRecord(_ json: String) throws -> KnownProjectRecord {
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try JSONDecoder().decode(KnownProjectRecord.self, from: data)
    }
}
