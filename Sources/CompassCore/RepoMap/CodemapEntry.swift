import CryptoKit
import Foundation

/// The on-disk representation of a single file in the codemap. One JSON
/// document lives at `.compass/codemap/<sha256(relativePath)>.json` so adds
/// and removals don't conflict with concurrent writes.
public struct CodemapEntry: Codable, Sendable, Equatable {
  /// Path relative to the repo root, with `/` separators. The key under
  /// which this entry is filed (filename = sha256(relativePath)). Persisted
  /// alongside the rest so the disk layout is self-describing.
  public var relativePath: String
  /// Source language at the time of indexing. Stored as the
  /// `CodemapLanguage` raw value so changing the enum case names is a
  /// migration we can detect.
  public var language: CodemapLanguage
  /// SHA-256 of the file's UTF-8 bytes, hex-lowercase. Primary freshness
  /// key — the indexer skips re-parsing when this matches.
  public var contentHash: String
  /// File size in bytes at parse time. Cached so re-stats can short-circuit
  /// before reading content.
  public var sizeBytes: Int
  /// Symbols emitted by `SymbolExtractor`, sorted by line.
  public var symbols: [CodemapSymbol]
  /// Imports emitted by `SymbolExtractor`, sorted by line.
  public var imports: [CodemapImport]
  /// One-paragraph LLM summary of what the file does. Populated by Phase 3;
  /// absent for entries written by the symbol-only indexing pass.
  public var summary: String?
  /// Model identifier that produced `summary`. Used by the refresher to
  /// decide whether to regenerate when the user switches models.
  public var summaryModel: String?
  /// `contentHash` at the time `summary` was generated. Carrying it
  /// separately means the symbol cache can be invalidated without losing a
  /// still-valid summary, and vice versa.
  public var summaryContentHash: String?
  /// Whether this file is generated (e.g., by a build tool or code generator)
  /// rather than hand-written. Populated by heuristics in the codemapper
  /// (e.g., file extension not recognized as source, or path under a known
  /// generated-sources directory). Used by Explore to add "why generated"
  /// context when explaining files.
  public var isGenerated: Bool
}

public enum CodemapHash {
  /// Lowercase hex SHA-256 of the supplied bytes. Used both for content
  /// freshness and for the filename of each per-file entry.
  public static func sha256Hex(_ data: Data) -> String {
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  /// Convenience for hashing a String as UTF-8.
  public static func sha256Hex(_ string: String) -> String {
    sha256Hex(Data(string.utf8))
  }
}
