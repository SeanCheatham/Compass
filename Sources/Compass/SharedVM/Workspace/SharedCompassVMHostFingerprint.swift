import CryptoKit
import Foundation

/// Content fingerprint of a host worktree, used by
/// `SharedCompassVMRepoWorkspaceSync` to detect out-of-band edits made
/// while Compass wasn't running.
///
/// The catalog records the fingerprint and the matching file set on
/// every successful push or pull (see
/// `SharedCompassVMGuestWorkspaceCatalog.recordSync`). On the next
/// `ensurePopulated` call, the fast-path is taken only when the freshly
/// recomputed host fingerprint matches the recorded value; otherwise
/// the guest is re-populated so the user's edits participate in the
/// session.
///
/// **Fingerprint format.** SHA-256 over a sorted, NUL-separated stream
/// of `<relative-path>\0<sha256(file-content-hex)>\0` records, scoped
/// to the same gitignore-respecting "tracked + untracked-not-ignored"
/// set the push tar uses. The hash covers content rather than mtime/size
/// because backups, restores, and `touch -r` can preserve timestamps
/// while changing bytes; a false negative on drift detection silently
/// throws away the user's edits, so the extra CPU is the cheaper side
/// of the trade.
enum SharedCompassVMHostFingerprint {

  enum FingerprintError: LocalizedError, CustomStringConvertible {
    case enumerationFailed(detail: String)
    case readFailed(path: String, detail: String)

    var description: String {
      switch self {
      case .enumerationFailed(let detail):
        return "host worktree enumeration failed: \(detail)"
      case .readFailed(let path, let detail):
        return "host file read failed (\(path)): \(detail)"
      }
    }
    var errorDescription: String? { description }
  }

  /// Computes the fingerprint and returns it alongside the file set
  /// that backs it. Both are persisted together — the file set scopes
  /// pull-side deletions to "files we pushed last time" so user-added
  /// files between sessions are preserved instead of being deleted by
  /// the `host_now − guest_now` cleanup step.
  static func compute(
    at worktreeURL: URL
  ) throws -> (fingerprint: String, fileSet: Set<String>) {
    let enumerated: Set<String>
    do {
      enumerated = try SharedCompassVMWorktreeSync.gitTrackedAndUntracked(in: worktreeURL)
    } catch {
      throw FingerprintError.enumerationFailed(detail: "\(error)")
    }
    // Match `buildHostTar`'s filter: paths that `git ls-files` knows
    // about but no longer exist on disk (deleted-but-still-staged
    // entries) are excluded from the tar, so they also have to be
    // excluded from the fingerprint or every push-then-rehash will
    // mismatch itself.
    let existing = enumerated.filter { relative in
      FileManager.default.fileExists(atPath: worktreeURL.appendingPathComponent(relative).path)
    }

    var pairs: [(path: String, hash: String)] = []
    pairs.reserveCapacity(existing.count)
    for relative in existing {
      let fileURL = worktreeURL.appendingPathComponent(relative)
      let contentHash = try hashFile(at: fileURL, relativePath: relative)
      pairs.append((relative, contentHash))
    }
    pairs.sort { $0.path < $1.path }

    var combined = Data()
    for (path, hash) in pairs {
      combined.append(Data(path.utf8))
      combined.append(0)
      combined.append(Data(hash.utf8))
      combined.append(0)
    }
    let fingerprint = CodemapHash.sha256Hex(combined)
    let fileSet = Set(pairs.map { $0.path })
    return (fingerprint, fileSet)
  }

  /// Streaming SHA-256 of a single file. Streamed (rather than
  /// `Data(contentsOf:)`) so a multi-GB binary in the worktree doesn't
  /// peak memory; the hasher only carries 256 bits of state.
  ///
  /// Symlinks and other non-regular entries are hashed by kind+payload
  /// instead of by opening the path. `git ls-files` happily emits a
  /// single entry for a symlink-to-directory (e.g. SPM's
  /// `.build/debug -> arm64-apple-macosx/debug`), and `InputStream`
  /// follows it and fails with EISDIR. Hashing the link target string
  /// also matches what tar puts on the wire (the link entry, not the
  /// resolved contents), so push and fingerprint cover the same shape.
  private static func hashFile(at url: URL, relativePath: String) throws -> String {
    var info = stat()
    if lstat(url.path, &info) != 0 {
      throw FingerprintError.readFailed(
        path: relativePath, detail: String(cString: strerror(errno)))
    }
    let kind = info.st_mode & S_IFMT
    if kind == S_IFLNK {
      let target: String
      do {
        target = try FileManager.default.destinationOfSymbolicLink(atPath: url.path)
      } catch {
        throw FingerprintError.readFailed(path: relativePath, detail: "symlink read: \(error)")
      }
      var hasher = SHA256()
      hasher.update(data: Data("symlink:".utf8))
      hasher.update(data: Data(target.utf8))
      return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
    if kind != S_IFREG {
      var hasher = SHA256()
      hasher.update(data: Data("non-regular:\(kind)".utf8))
      return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    guard let stream = InputStream(url: url) else {
      throw FingerprintError.readFailed(path: relativePath, detail: "could not open input stream")
    }
    stream.open()
    defer { stream.close() }
    if let openError = stream.streamError {
      throw FingerprintError.readFailed(path: relativePath, detail: "\(openError)")
    }

    var hasher = SHA256()
    let bufferSize = 1 << 16
    var buffer = [UInt8](repeating: 0, count: bufferSize)
    while stream.hasBytesAvailable {
      let read = buffer.withUnsafeMutableBufferPointer { ptr -> Int in
        guard let base = ptr.baseAddress else { return 0 }
        return stream.read(base, maxLength: ptr.count)
      }
      if read < 0 {
        let detail = stream.streamError.map { "\($0)" } ?? "unknown read error"
        throw FingerprintError.readFailed(path: relativePath, detail: detail)
      }
      if read == 0 { break }
      hasher.update(data: buffer.prefix(read))
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }
}
