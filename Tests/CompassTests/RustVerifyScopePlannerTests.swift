import Foundation
import Testing

@testable import Compass

struct RustVerifyScopePlannerTests {
  @Test func scopesSingleCrateChanges() throws {
    let suggestion = RustVerifyScopePlanner.suggest(
      changedFiles: ["crates/app-core/src/lib.rs"],
      graph: snapshot()
    )

    #expect(suggestion.command == "cargo test -p app-core --all-features")
    #expect(!suggestion.needsVisualVerify)
  }

  @Test func desktopChangesRequestVisualVerifyNote() throws {
    let suggestion = RustVerifyScopePlanner.suggest(
      changedFiles: ["crates/app-desktop/src/main.rs"],
      graph: snapshot()
    )

    #expect(suggestion.command == "cargo test -p app-desktop --all-features")
    #expect(suggestion.needsVisualVerify)
  }

  @Test func rootCargoChangesUseFullWorkspace() throws {
    let suggestion = RustVerifyScopePlanner.suggest(changedFiles: ["Cargo.lock"], graph: snapshot())

    #expect(suggestion.command == "cargo test --workspace --all-features")
  }

  private func snapshot() -> CargoGraphSnapshot {
    CargoGraphSnapshot(
      contentFingerprint: "fingerprint",
      generatedAt: Date(timeIntervalSince1970: 0),
      graph: CargoGraphData(
        workspaceRoot: "Cargo.toml",
        members: [
          member("app-core", dir: "crates/app-core"),
          member("app-desktop", dir: "crates/app-desktop"),
        ],
        edges: []
      )
    )
  }

  private func member(_ name: String, dir: String) -> CargoGraphMember {
    CargoGraphMember(
      name: name,
      manifestPath: "\(dir)/Cargo.toml",
      kind: "lib",
      packageDir: dir,
      srcRoot: "\(dir)/src",
      dependencies: [],
      features: CargoGraphFeatures(default: [], named: [:])
    )
  }
}
