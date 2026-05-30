import Foundation

/// Cached Explore tab payload for a repository.
struct ExploreRepositorySnapshot: Sendable, Equatable {
  let fileTree: [FileTreeNode]
  let codemapEntries: [String: CodemapEntry]
}

/// In-memory cache so switching away from the Explore tab does not rebuild
/// the tree from scratch on every visit.
final class ExploreRepositorySnapshotCache: @unchecked Sendable {
  static let shared = ExploreRepositorySnapshotCache()

  private let lock = NSLock()
  private var storage: [String: ExploreRepositorySnapshot] = [:]

  func snapshot(for repoURL: URL) -> ExploreRepositorySnapshot? {
    lock.lock()
    defer { lock.unlock() }
    return storage[repoURL.standardizedFileURL.path]
  }

  func store(_ snapshot: ExploreRepositorySnapshot, for repoURL: URL) {
    lock.lock()
    defer { lock.unlock() }
    storage[repoURL.standardizedFileURL.path] = snapshot
  }
}

enum ExploreRepositorySnapshotLoader {
  static func load(repoURL: URL, codemapDirectory: URL) -> ExploreRepositorySnapshot {
    let fileTree = ExploreTreeBuilder.buildSourceTree(repoURL: repoURL)
    let store = CodemapStore(directory: codemapDirectory)
    var codemapEntries: [String: CodemapEntry] = [:]
    codemapEntries.reserveCapacity(fileTree.count * 2)
    for path in ExploreTreeBuilder.allFilePaths(in: fileTree) {
      if let entry = store.loadEntry(forRelativePath: path) {
        codemapEntries[path] = entry
      }
    }
    return ExploreRepositorySnapshot(fileTree: fileTree, codemapEntries: codemapEntries)
  }
}

enum ExploreTreeBuilder {
  static func buildSourceTree(repoURL: URL) -> [FileTreeNode] {
    let paths = GitSourcePaths.sourcePaths(in: repoURL)
    if paths.isEmpty {
      return CodemapFileSystem(rootURL: repoURL).buildSourceTree()
    }
    return buildTree(fromSourcePaths: paths)
  }

  static func buildTree(fromSourcePaths paths: [String]) -> [FileTreeNode] {
    var roots: [FileTreeNode] = []
    for path in paths.sorted(by: {
      $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
    }) {
      insert(path: path, into: &roots)
    }
    return sortNodes(roots)
  }

  static func allFilePaths(in nodes: [FileTreeNode]) -> [String] {
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
    if let existing = siblings.firstIndex(where: { $0.relativePath == relativePath && $0.isDirectory })
    {
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
  static func sourcePaths(in repoURL: URL) -> [String] {
    guard let listing = runGitLsFiles(repoURL: repoURL) else { return [] }
    return listing
      .split(separator: "\0", omittingEmptySubsequences: true)
      .map(String.init)
      .filter { CodemapLanguage.forRelativePath($0) != nil }
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
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    return String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
  }
}
