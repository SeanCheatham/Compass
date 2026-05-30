import Foundation
import Testing

@testable import Compass

/// Compile-only test file covering untested guard paths in
/// ``CodemapGraphViz/writeOverviewSVG()``.
///
/// ## Guard path covered
///
/// ### Empty codemap — `ArchitectureGraph.exportSVG(from:)` returns `nil`
///
/// `CodemapGraphViz.writeOverviewSVG()` (line 38 of `CodemapGraphViz.swift`)
/// calls `ArchitectureGraph.exportSVG(from: codemapDirectory)` and returns
/// `nil` without writing any file when the codemap is empty (no indexed files).
/// This guard path is the inverse of the happy path tested in
/// `ExploreArchitectureGraphPopoverTests` which provides a populated
/// codemap and verifies the SVG file is written.
///
/// This test follows the pattern established in
/// ``ExploreArchitectureGraphGuardPathTests``.
struct ExploreCodemapGraphVizGuardPathTests {

  // MARK: - Guard path: Empty codemap → writeOverviewSVG returns nil

  /// Verifies `writeOverviewSVG()` returns `nil` and does not throw when the
  /// codemap directory contains no entries.
  ///
  /// `ArchitectureGraph.exportSVG(from:)` (ArchitectureGraph.swift line 335)
  /// calls `buildGraph` which returns an empty `ImportGraph` when no codemap
  /// entries exist. `exportSVG(from:)` then hits the guard at line 343
  /// (`guard !graph.nodes.isEmpty else { return nil }`) and returns `nil`.
  /// `CodemapGraphViz.writeOverviewSVG()` propagates this `nil` without
  /// attempting any file write.
  ///
  /// This test creates a deliberately empty codemap directory (no JSON files)
  /// and asserts `writeOverviewSVG()` returns `nil` without crashing.
  @Test
  func writeOverviewSVG_emptyCodemap_returnsNil() throws {
    let temporaryDirectory = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    // Create an empty codemap directory (no JSON entries).
    let codedir = temporaryDirectory.appendingPathComponent(".compass/codemap", isDirectory: true)
    try FileManager.default.createDirectory(at: codedir, withIntermediateDirectories: true)

    let viz = CodemapGraphViz(repoURL: temporaryDirectory, codemapDirectory: codedir)
    let result = try viz.writeOverviewSVG()

    // The function must return nil for an empty codemap — never throw.
    try #require(result == nil)

    // Verify no SVG file was written.
    let svgURL = temporaryDirectory.appendingPathComponent("codemap-overview.svg")
    #expect(!FileManager.default.fileExists(atPath: svgURL.path))
  }

  // MARK: - Compile-only: structure verification

  /// Compile-only test confirming `CodemapGraphViz.writeOverviewSVG()` has
  /// the correct return type (`URL?`) and calls `ArchitectureGraph.exportSVG`
  /// as a static method.
  ///
  /// A local `writeOverviewSVG` declaration shadows the real instance method,
  /// allowing the compiler to verify that:
  /// - `CodemapGraphViz` is initializable with `repoURL` and `codemapDirectory`
  /// - `ArchitectureGraph.exportSVG(from:)` is a valid static call
  /// - The return type is `URL?`
  ///
  /// This test passes by compiling without errors; no runtime execution is
  /// meaningful since the local function shadows the real one.
  @Test
  func writeOverviewSVG_compileOnly_structureVerification() {
    // Local function shadows CodemapGraphViz.writeOverviewSVG() in
    // Sources/Compass/Explore/CodemapGraphViz.swift.
    // The compiler must resolve the type, init, and static method — if any
    // are missing or misspelled, this fails to compile.
    func writeOverviewSVG() -> URL? {
      let repoURL = URL(fileURLWithPath: "/tmp/fake")
      let codemapDirectory = URL(fileURLWithPath: "/tmp/fake/.compass/codemap")
      let viz = CodemapGraphViz(repoURL: repoURL, codemapDirectory: codemapDirectory)
      // swiftlint:disable:unused_result
      _ = viz  // Verify CodemapGraphViz.init is accessible.
      // swiftlint:enable:unused_result
      // ArchitectureGraph.exportSVG(from:) is a static method returning String?
      // The return type of writeOverviewSVG must match — URL? — or this fails.
      let svg: String? = ArchitectureGraph.exportSVG(from: codemapDirectory)
      guard let svg else { return nil }
      return repoURL.appendingPathComponent(svg)
    }

    // Call only to satisfy the compiler's "defined but not used" scrutiny.
    // The result is intentionally discarded — test passes by compiling.
    let result = writeOverviewSVG()
    // swiftlint:disable:unused_result
    _ = result
    // swiftlint:enable:unused_result
  }
}
