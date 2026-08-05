import Foundation

public enum RepositoryLanguage: String, CaseIterable, Codable, Equatable, Hashable {
  case rust
  case swift
  case markdown
  case other
  case unknown

  public var displayName: String {
    switch self {
    case .rust: return "Rust"
    case .swift: return "Swift"
    case .markdown: return "Markdown"
    case .other: return "Other"
    case .unknown: return "Unknown"
    }
  }
}

public struct RepositoryLanguageCounts: Codable, Equatable {
  public var rust = 0
  public var swift = 0
  public var markdown = 0
  public var other = 0

  public var total: Int {
    rust + swift + markdown + other
  }

  public subscript(language: RepositoryLanguage) -> Int {
    get {
      switch language {
      case .rust: return rust
      case .swift: return swift
      case .markdown: return markdown
      case .other: return other
      case .unknown: return 0
      }
    }
    set {
      switch language {
      case .rust:
        rust = newValue
      case .swift:
        swift = newValue
      case .markdown:
        markdown = newValue
      case .other:
        other = newValue
      case .unknown:
        break
      }
    }
  }

  public mutating func increment(_ language: RepositoryLanguage) {
    self[language] += 1
  }
}

public enum RepositoryManifestHint: String, CaseIterable, Codable, Equatable, Hashable {
  case cargoToml = "Cargo.toml"
  case packageSwift = "Package.swift"

  public init?(fileName: String) {
    switch fileName {
    case Self.cargoToml.rawValue:
      self = .cargoToml
    case Self.packageSwift.rawValue:
      self = .packageSwift
    default:
      return nil
    }
  }

  public var language: RepositoryLanguage {
    switch self {
    case .cargoToml: return .rust
    case .packageSwift: return .swift
    }
  }
}

public struct RepositoryLanguageProfile: Codable, Equatable {
  public var counts: RepositoryLanguageCounts
  public var manifestHints: [RepositoryManifestHint]
  public var primaryLanguage: RepositoryLanguage
  public var scannedFileCount: Int
  public var scannedDirectoryCount: Int
  public var wasTruncated: Bool

  public static let empty = RepositoryLanguageProfile(
    counts: RepositoryLanguageCounts(),
    manifestHints: [],
    primaryLanguage: .unknown,
    scannedFileCount: 0,
    scannedDirectoryCount: 0,
    wasTruncated: false
  )
}

/// Shared rules for walking a repository tree without descending into
/// build artifacts, dependency caches, or other generated directories.
public enum RepositoryWalkRules {
  public static let ignoredDirectoryNames: Set<String> = [
    ".build",
    ".compass",
    ".git",
    ".hg",
    ".next",
    ".svn",
    ".yarn",
    "build",
    "coverage",
    "DerivedData",
    "dist",
    "env",
    "node_modules",
    "target",
  ]

  public static func shouldInclude(name: String, isDirectory: Bool, isTopLevel: Bool = false) -> Bool {
    if name.hasPrefix(".") { return false }
    if isTopLevel && name == "Compass" { return false }
    if isDirectory && name.hasSuffix(".xcodeproj") { return false }
    if isDirectory && ignoredDirectoryNames.contains(name) { return false }
    return true
  }

  public static func shouldInclude(relativePath: String) -> Bool {
    let components = relativePath.split(separator: "/").map(String.init)
    guard !components.isEmpty else { return false }
    for (index, component) in components.enumerated() {
      let isDirectory = index < components.count - 1
      guard
        shouldInclude(
          name: component,
          isDirectory: isDirectory,
          isTopLevel: index == 0
        )
      else {
        return false
      }
    }
    return true
  }
}

public enum RepositoryLanguageProfileService {
  public static func scan(repoURL: URL) -> RepositoryLanguageProfile {
    RepositoryLanguageProfileScanner(repoURL: repoURL).scan()
  }
}

private struct RepositoryLanguageProfileScanner {
  private static let maxFiles = 12_000
  private static let maxDirectories = 2_000

  private let repoURL: URL
  private let fileManager = FileManager.default

  public init(repoURL: URL) {
    self.repoURL = repoURL.standardizedFileURL
  }

  public func scan() -> RepositoryLanguageProfile {
    var counts = RepositoryLanguageCounts()
    var manifestHints = Set<RepositoryManifestHint>()
    var scannedFiles = 0
    var scannedDirectories = 0
    var wasTruncated = false
    var stack = [repoURL]

    while let directory = stack.popLast() {
      guard scannedDirectories < Self.maxDirectories else {
        wasTruncated = true
        break
      }
      scannedDirectories += 1

      let children = directoryChildren(directory)
      var childDirectories: [URL] = []

      for child in children {
        guard scannedFiles < Self.maxFiles else {
          wasTruncated = true
          break
        }

        let values = try? child.resourceValues(forKeys: [
          .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
        ])
        if values?.isSymbolicLink == true {
          continue
        }

        if values?.isDirectory == true {
          guard
            RepositoryWalkRules.shouldInclude(
              name: child.lastPathComponent,
              isDirectory: true
            )
          else { continue }
          childDirectories.append(child)
          continue
        }

        guard values?.isRegularFile != false else { continue }

        scannedFiles += 1
        if let hint = RepositoryManifestHint(fileName: child.lastPathComponent) {
          manifestHints.insert(hint)
        }
        counts.increment(Self.language(for: child))
      }

      if wasTruncated {
        break
      }

      stack.append(contentsOf: childDirectories.reversed())
    }

    let sortedHints = RepositoryManifestHint.allCases.filter { manifestHints.contains($0) }
    let primary = Self.primaryLanguage(counts: counts, manifestHints: sortedHints)
    return RepositoryLanguageProfile(
      counts: counts,
      manifestHints: sortedHints,
      primaryLanguage: primary,
      scannedFileCount: scannedFiles,
      scannedDirectoryCount: scannedDirectories,
      wasTruncated: wasTruncated
    )
  }

  private func directoryChildren(_ directory: URL) -> [URL] {
    let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
    let children =
      (try? fileManager.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: keys,
        options: [.skipsPackageDescendants]
      )) ?? []
    return children.sorted { $0.path < $1.path }
  }

  private static func language(for fileURL: URL) -> RepositoryLanguage {
    switch fileURL.pathExtension.lowercased() {
    case "rs":
      return .rust
    case "swift":
      return .swift
    case "markdown", "md", "mdx":
      return .markdown
    default:
      return .other
    }
  }

  private static func primaryLanguage(
    counts: RepositoryLanguageCounts,
    manifestHints: [RepositoryManifestHint]
  ) -> RepositoryLanguage {
    let codeLanguages: [RepositoryLanguage] = [
      .rust,
      .swift,
      .markdown,
    ]
    let manifestBoost = 7
    var scores = Dictionary(uniqueKeysWithValues: codeLanguages.map { ($0, counts[$0] * 10) })
    for hint in manifestHints {
      scores[hint.language, default: 0] += manifestBoost
    }

    let best = codeLanguages.max { lhs, rhs in
      let left = scores[lhs, default: 0]
      let right = scores[rhs, default: 0]
      if left == right {
        let lhsIndex = codeLanguages.firstIndex(of: lhs) ?? 0
        let rhsIndex = codeLanguages.firstIndex(of: rhs) ?? 0
        return lhsIndex > rhsIndex
      }
      return left < right
    }

    guard let best, scores[best, default: 0] > 0 else {
      return counts.other > 0 ? .other : .unknown
    }
    return best
  }
}
