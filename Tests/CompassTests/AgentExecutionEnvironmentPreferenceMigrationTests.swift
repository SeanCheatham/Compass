import Foundation
@testable import Compass
import XCTest

/// Migration coverage for the legacy `codexExecutionEnvironmentPreference` JSON key.
/// The field is no longer stored on `KnownProjectRecord` — `developSandbox` is the
/// only persisted sandbox preference. When the new key is absent on disk, the legacy
/// raw value seeds `developSandbox` so a user who picked "Shared VM" before the
/// rename carries that choice forward. The pre-pivot `devcontainer_preferred` raw
/// value must NOT auto-enrol a project into the shared VM.
final class AgentExecutionEnvironmentPreferenceMigrationTests: XCTestCase {
    func testLegacyDevcontainerPreferredSeedsDevelopSandboxAsHost() throws {
        let record = try decodeRecord("""
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "path": "/tmp/legacy-devcontainer",
          "addedAt": 1,
          "lastOpenedAt": 2,
          "codexExecutionEnvironmentPreference": "devcontainer_preferred"
        }
        """)

        XCTAssertEqual(record.developSandbox, .host)
    }

    func testLegacyNativeMacosSeedsDevelopSandboxAsHost() throws {
        let record = try decodeRecord("""
        {
          "id": "22222222-2222-2222-2222-222222222222",
          "path": "/tmp/native-macos",
          "addedAt": 3,
          "lastOpenedAt": 4,
          "codexExecutionEnvironmentPreference": "native_macos"
        }
        """)

        XCTAssertEqual(record.developSandbox, .host)
    }

    func testLegacySharedVMSeedsDevelopSandboxAsSharedVM() throws {
        // Carries a user's pre-rename "Shared VM" selection forward into the
        // authoritative developSandbox field.
        let record = try decodeRecord("""
        {
          "id": "33333333-3333-3333-3333-333333333333",
          "path": "/tmp/shared-vm",
          "addedAt": 5,
          "lastOpenedAt": 6,
          "codexExecutionEnvironmentPreference": "shared_vm"
        }
        """)

        XCTAssertEqual(record.developSandbox, .sharedVM)
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
        // flip their per-project sandbox into the shared VM.
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
    }

    func testNewDevelopSandboxKeyTakesPrecedenceOverLegacyKey() throws {
        // When both keys are present, `developSandbox` wins — the legacy key is
        // a one-way fallback for records written before the field existed.
        let newWinsOverHost = try decodeRecord("""
        {
          "id": "88888888-8888-8888-8888-888888888888",
          "path": "/tmp/host-shared",
          "addedAt": 15,
          "lastOpenedAt": 16,
          "codexExecutionEnvironmentPreference": "native_macos",
          "developSandbox": "shared_vm"
        }
        """)
        XCTAssertEqual(newWinsOverHost.developSandbox, .sharedVM)

        let newWinsOverShared = try decodeRecord("""
        {
          "id": "99999999-9999-9999-9999-999999999999",
          "path": "/tmp/shared-host",
          "addedAt": 17,
          "lastOpenedAt": 18,
          "codexExecutionEnvironmentPreference": "shared_vm",
          "developSandbox": "host"
        }
        """)
        XCTAssertEqual(newWinsOverShared.developSandbox, .host)
    }

    func testEncodeDropsTheLegacyKey() throws {
        // After the round trip we no longer write the legacy on-disk key —
        // `developSandbox` is the only persisted sandbox preference.
        let record = KnownProjectRecord(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            path: "/tmp/round-trip",
            addedAt: 0,
            lastOpenedAt: 0,
            developSandbox: .sharedVM
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(record)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("codexExecutionEnvironmentPreference"))
        XCTAssertTrue(json.contains("\"developSandbox\":\"shared_vm\""))
    }

    private func decodeRecord(_ json: String) throws -> KnownProjectRecord {
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try JSONDecoder().decode(KnownProjectRecord.self, from: data)
    }
}
