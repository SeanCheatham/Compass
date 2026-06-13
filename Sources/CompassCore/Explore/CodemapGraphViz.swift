import Foundation

/// ## Change Inspection: Architecture Graph Visualization
///
/// `CodemapGraphViz` generates a shareable SVG architecture graph from a
/// `CodemapFileSystem` snapshot, exposing the output via
/// ``ArchitectureGraph/exportSVG(from:)``.
///
/// ``CodemapGraphViz`` is a thin wrapper that bridges codemap storage and the
/// import-graph renderer. It is used by
/// ``ArchitectureGraphPopover`` when the user requests a downloadable SVG
/// artifact of the codebase's import graph.
///
/// ## Usage
///
/// ```swift
/// let fs = CodemapFileSystem(rootURL: repoURL)
/// let tree = fs.buildSourceTree()
/// if let svg = ArchitectureGraph.exportSVG(from: codemapDirectory) {
///     try svg.write(to: repoURL.appendingPathComponent("codemap-overview.svg"),
///                   atomically: true, encoding: .utf8)
/// }
/// ```
package struct CodemapGraphViz {
  /// The repository root to generate the graph for.
  package let repoURL: URL

  /// The codemap directory that holds indexed file entries.
  package let codemapDirectory: URL

  /// Generates the SVG graph and writes it to `codemap-overview.svg` in the
  /// repo root. Returns the written URL on success, or `nil` if the codemap
  /// was empty (no files indexed).
  ///
  /// If the file already exists it is overwritten atomically.
  @discardableResult
  package func writeOverviewSVG() throws -> URL? {
    guard let svg = ArchitectureGraph.exportSVG(from: codemapDirectory) else {
      return nil
    }
    let outputURL = repoURL.appendingPathComponent("codemap-overview.svg")
    try svg.write(to: outputURL, atomically: true, encoding: .utf8)
    return outputURL
  }
}
