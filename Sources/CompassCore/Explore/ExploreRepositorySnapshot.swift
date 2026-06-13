import Foundation

/// ## Explore pipeline: repository snapshot
///
/// This file contains the data model, cache, loader, and tree builder that
/// together produce a reusable repository snapshot for change-inspection UI.
///
/// ### Composition
///
/// ``ExploreRepositorySnapshot`` is the immutable payload: a file tree
/// plus the indexed codemap entries for every source file.
///
/// ``ExploreRepositorySnapshotCache`` is a thread-safe in-memory cache keyed
/// by repo URL, preventing repeated rebuilds while the same repository is
/// inspected from Plan history or related views.
///
/// ``ExploreRepositorySnapshotLoader`` assembles a snapshot by delegating
/// to ``ExploreTreeBuilder`` (for the file tree) and ``CodemapStore`` (for
/// codemap entries).
///
/// ``ExploreTreeBuilder`` constructs the ``FileTreeNode`` hierarchy using
/// ``GitSourcePaths`` when `git ls-files` is available, or falling back to
/// ``CodemapFileSystem`` for a raw directory walk.
///
/// ## Pipeline position
///
/// 1. ``ExploreRepositorySnapshotLoader.load(repoURL:codemapDirectory:)`` is
///    called when a change-inspection surface needs a repository file tree.
/// 2. It builds the file tree (either via `git` or ``CodemapFileSystem``) and
///    loads codemap entries via ``CodemapStore``.
/// 3. The resulting ``ExploreRepositorySnapshot`` is stored in
///    ``ExploreRepositorySnapshotCache`` and consumed by repository-inspection UI.
///
/// ## Public types
///
/// | Type | Role |
/// |---|---|
/// | ``ExploreRepositorySnapshot`` | Immutable repository snapshot: file tree + codemap entries |
/// | ``ExploreRepositorySnapshotCache`` | Thread-safe in-memory cache keyed by repo URL |
/// | ``ExploreRepositorySnapshotLoader`` | Assembles a snapshot from ``ExploreTreeBuilder`` + ``CodemapStore`` |
/// | ``ExploreTreeBuilder`` | Builds the ``FileTreeNode`` hierarchy from `git ls-files` or ``CodemapFileSystem`` |

/// A node in a repository directory tree produced by `CodemapFileSystem` or
/// `ExploreTreeBuilder`.
package struct FileTreeNode: Identifiable, Equatable, Sendable {
  package let relativePath: String
  package let isDirectory: Bool
  package let language: CodemapLanguage?
  package var children: [FileTreeNode]

  package var id: String { relativePath }

  package var name: String {
    (relativePath as NSString).lastPathComponent
  }

  package var folderSummary: String? {
    guard isDirectory else { return nil }
    let fileCount = children.filter { !$0.isDirectory }.count
    guard fileCount > 0 else { return nil }
    return "\(fileCount) source file\(fileCount == 1 ? "" : "s") in this folder"
  }
}

/// Cached repository snapshot payload.
package struct ExploreRepositorySnapshot: Sendable, Equatable {
  package let fileTree: [FileTreeNode]
  package let codemapEntries: [String: CodemapEntry]
}

/// In-memory cache so repeated repository-inspection requests do not rebuild
/// the tree from scratch.
package final class ExploreRepositorySnapshotCache: @unchecked Sendable {
  package static let shared = ExploreRepositorySnapshotCache()

  private let lock = NSLock()
  private var storage: [String: ExploreRepositorySnapshot] = [:]

  package func snapshot(for repoURL: URL) -> ExploreRepositorySnapshot? {
    lock.lock()
    defer { lock.unlock() }
    return storage[repoURL.standardizedFileURL.path]
  }

  package func store(_ snapshot: ExploreRepositorySnapshot, for repoURL: URL) {
    lock.lock()
    defer { lock.unlock() }
    storage[repoURL.standardizedFileURL.path] = snapshot
  }
}

package enum ExploreRepositorySnapshotLoader {
  package static func load(repoURL: URL, codemapDirectory: URL) -> ExploreRepositorySnapshot {
    let fileTree = ExploreTreeBuilder.buildSourceTree(repoURL: repoURL)
    let store = CodemapStore(directory: codemapDirectory)
    let allPaths = ExploreTreeBuilder.allFilePaths(in: fileTree)
    var codemapEntries: [String: CodemapEntry] = [:]
    codemapEntries.reserveCapacity(allPaths.count)
    for path in allPaths {
      if let entry = store.loadEntry(forRelativePath: path) {
        codemapEntries[path] = entry
      }
    }
    return ExploreRepositorySnapshot(fileTree: fileTree, codemapEntries: codemapEntries)
  }
}

package enum ExploreTreeBuilder {
  package static func buildSourceTree(repoURL: URL) -> [FileTreeNode] {
    let paths = GitSourcePaths.sourcePaths(in: repoURL)
    if paths.isEmpty {
      return CodemapFileSystem(rootURL: repoURL).buildSourceTree()
    }
    return buildTree(fromSourcePaths: paths)
  }

  package static func buildTree(fromSourcePaths paths: [String]) -> [FileTreeNode] {
    var roots: [FileTreeNode] = []
    for path in paths.sorted(by: {
      $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
    }) {
      insert(path: path, into: &roots)
    }
    return sortNodes(roots)
  }

  package static func allFilePaths(in nodes: [FileTreeNode]) -> [String] {
    nodes.flatMap { node -> [String] in
      if node.isDirectory {
        return allFilePaths(in: node.children)
      }
      return [node.relativePath]
    }
  }

  private static func insert(path: String, into roots: inout [FileTreeNode]) {
    let components = path.split(separator: "/").map(String.init)
    guard !components.isEmpty else { return }
    insert(components: components, fullPath: path, into: &roots, prefix: "")
  }

  private static func insert(
    components: [String],
    fullPath: String,
    into siblings: inout [FileTreeNode],
    prefix: String
  ) {
    let name = components[0]
    let relativePath = prefix.isEmpty ? name : "\(prefix)/\(name)"

    if components.count == 1 {
      let file = FileTreeNode(
        relativePath: fullPath,
        isDirectory: false,
        language: CodemapLanguage.forRelativePath(fullPath),
        children: []
      )
      if let index = siblings.firstIndex(where: { $0.relativePath == fullPath }) {
        siblings[index] = file
      } else {
        siblings.append(file)
      }
      return
    }

    let directoryIndex: Int
    if let existing = siblings.firstIndex(where: {
      $0.relativePath == relativePath && $0.isDirectory
    }) {
      directoryIndex = existing
    } else {
      siblings.append(
        FileTreeNode(
          relativePath: relativePath,
          isDirectory: true,
          language: nil,
          children: []
        )
      )
      directoryIndex = siblings.count - 1
    }

    insert(
      components: Array(components.dropFirst()),
      fullPath: fullPath,
      into: &siblings[directoryIndex].children,
      prefix: relativePath
    )
  }

  private static func sortNodes(_ nodes: [FileTreeNode]) -> [FileTreeNode] {
    nodes.map { node in
      guard node.isDirectory else { return node }
      return FileTreeNode(
        relativePath: node.relativePath,
        isDirectory: true,
        language: nil,
        children: sortNodes(node.children)
      )
    }
    .sorted { lhs, rhs in
      if lhs.isDirectory != rhs.isDirectory {
        return lhs.isDirectory && !rhs.isDirectory
      }
      return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
  }
}

private enum GitSourcePaths {
  package static func sourcePaths(in repoURL: URL) -> [String] {
    guard let listing = runGitLsFiles(repoURL: repoURL) else { return [] }
    return
      listing
      .split(separator: "\0", omittingEmptySubsequences: true)
      .map(String.init)
      .filter {
        CodemapLanguage.forRelativePath($0) != nil
          && RepositoryWalkRules.shouldInclude(relativePath: $0)
      }
  }

  private static func runGitLsFiles(repoURL: URL) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["ls-files", "--cached", "--others", "--exclude-standard", "-z"]
    process.currentDirectoryURL = repoURL.standardizedFileURL
    let stdout = Pipe()
    process.standardOutput = stdout
    process.standardError = Pipe()
    do {
      try process.run()
    } catch {
      return nil
    }
    let data = stdout.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    return String(data: data, encoding: .utf8)
  }
}
