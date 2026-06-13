import Foundation

/// ## Explore pipeline: file-system scanner
///
/// ``CodemapFileSystem`` walks the repository tree and produces a
/// ``FileTreeNode`` hierarchy that mirrors the source directory layout.
/// It is the low-level scanning engine used by ``ExploreTreeBuilder`` when
/// ``GitSourcePaths`` cannot enumerate source files via `git ls-files`
/// (e.g. in a fresh or sparse checkout).  Its output feeds directly into the
/// cached ``ExploreRepositorySnapshot``.
///
/// ## Responsibilities
///
/// - Recursively enumerate the repo root, respecting ``RepositoryWalkRules``.
/// - Produce both a full tree (``buildTree()``) and a source-only tree
///   (``buildSourceTree()``) filtered to files with a known ``CodemapLanguage``.
/// - Reject symbolic links and hidden entries.
///
/// ``CodemapFileSystem`` is a private implementation detail of repository
/// snapshot loading; callers should use ``ExploreTreeBuilder`` instead.

/// Reads `repoURL` and produces a tree of `FileTreeNode`s mirroring the
/// source directory layout under `rootURL`.
package struct CodemapFileSystem {
  package let rootURL: URL
  private let fileManager = FileManager.default

  /// Build the full tree from the repo root.
  package func buildTree() -> [FileTreeNode] {
    let keys = topLevelKeys()
    let nodes = keys.map { buildNode(relativePath: $0) }
    return sortNodes(nodes)
  }

  /// Build a tree containing only supported source files and their parent folders.
  package func buildSourceTree() -> [FileTreeNode] {
    pruneSourceNodes(buildTree())
  }

  private func pruneSourceNodes(_ nodes: [FileTreeNode]) -> [FileTreeNode] {
    nodes.compactMap { node in
      if node.isDirectory {
        let children = pruneSourceNodes(node.children)
        guard !children.isEmpty else { return nil }
        return FileTreeNode(
          relativePath: node.relativePath,
          isDirectory: true,
          language: nil,
          children: children
        )
      }
      guard CodemapLanguage.forRelativePath(node.relativePath) != nil else { return nil }
      return node
    }
  }

  /// Top-level relative paths immediately under the repo root.
  private func topLevelKeys() -> [String] {
    childRelativePaths(
      under: "",
      url: rootURL,
      isTopLevel: true
    )
  }

  private func buildNode(relativePath: String) -> FileTreeNode {
    let url = rootURL.appendingPathComponent(relativePath)
    guard let entry = directoryEntry(at: url) else {
      return FileTreeNode(
        relativePath: relativePath,
        isDirectory: false,
        language: CodemapLanguage.forRelativePath(relativePath),
        children: []
      )
    }

    if entry.isDirectory {
      let childKeys = childRelativePaths(under: relativePath, url: url)
      let children = childKeys.map { buildNode(relativePath: $0) }
      return FileTreeNode(
        relativePath: relativePath,
        isDirectory: true,
        language: nil,
        children: sortNodes(children)
      )
    }

    return FileTreeNode(
      relativePath: relativePath,
      isDirectory: false,
      language: CodemapLanguage.forRelativePath(relativePath),
      children: []
    )
  }

  private func childRelativePaths(
    under parent: String,
    url: URL,
    isTopLevel: Bool = false
  ) -> [String] {
    guard
      let contents = try? fileManager.contentsOfDirectory(
        at: url,
        includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return []
    }

    return contents.compactMap { childURL in
      guard let entry = directoryEntry(at: childURL) else { return nil }
      let name = childURL.lastPathComponent
      guard
        RepositoryWalkRules.shouldInclude(
          name: name,
          isDirectory: entry.isDirectory,
          isTopLevel: isTopLevel
        )
      else {
        return nil
      }
      return parent.isEmpty ? name : "\(parent)/\(name)"
    }
  }

  private func directoryEntry(at url: URL) -> (isDirectory: Bool, isSymbolicLink: Bool)? {
    guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    else {
      return nil
    }
    if values.isSymbolicLink == true {
      return nil
    }
    return (values.isDirectory == true, false)
  }

  private func sortNodes(_ nodes: [FileTreeNode]) -> [FileTreeNode] {
    let dirs = nodes.filter { $0.isDirectory }.sorted {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
    let files = nodes.filter { !$0.isDirectory }.sorted {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
    return dirs + files
  }
}
