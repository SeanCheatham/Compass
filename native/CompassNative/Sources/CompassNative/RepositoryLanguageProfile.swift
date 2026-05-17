import Foundation

enum RepositoryLanguage: String, CaseIterable, Codable, Equatable, Hashable {
    case typeScriptJavaScript
    case python
    case go
    case rust
    case swift
    case markdown
    case other
    case unknown

    var displayName: String {
        switch self {
        case .typeScriptJavaScript: return "TypeScript/JavaScript"
        case .python: return "Python"
        case .go: return "Go"
        case .rust: return "Rust"
        case .swift: return "Swift"
        case .markdown: return "Markdown"
        case .other: return "Other"
        case .unknown: return "Unknown"
        }
    }

    var sourceNoun: String {
        switch self {
        case .typeScriptJavaScript: return "TS/JS files"
        case .python: return "Python files"
        case .go: return "Go files"
        case .rust: return "Rust files"
        case .swift: return "Swift files"
        case .markdown: return "Markdown files"
        case .other: return "other files"
        case .unknown: return "files"
        }
    }
}

struct RepositoryLanguageCounts: Codable, Equatable {
    var typeScriptJavaScript = 0
    var python = 0
    var go = 0
    var rust = 0
    var swift = 0
    var markdown = 0
    var other = 0

    var total: Int {
        typeScriptJavaScript + python + go + rust + swift + markdown + other
    }

    subscript(language: RepositoryLanguage) -> Int {
        get {
            switch language {
            case .typeScriptJavaScript: return typeScriptJavaScript
            case .python: return python
            case .go: return go
            case .rust: return rust
            case .swift: return swift
            case .markdown: return markdown
            case .other: return other
            case .unknown: return 0
            }
        }
        set {
            switch language {
            case .typeScriptJavaScript:
                typeScriptJavaScript = newValue
            case .python:
                python = newValue
            case .go:
                go = newValue
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

    mutating func increment(_ language: RepositoryLanguage) {
        self[language] += 1
    }
}

enum RepositoryManifestHint: String, CaseIterable, Codable, Equatable, Hashable {
    case packageJSON = "package.json"
    case pyprojectToml = "pyproject.toml"
    case goMod = "go.mod"
    case cargoToml = "Cargo.toml"
    case packageSwift = "Package.swift"

    init?(fileName: String) {
        switch fileName {
        case Self.packageJSON.rawValue:
            self = .packageJSON
        case Self.pyprojectToml.rawValue:
            self = .pyprojectToml
        case Self.goMod.rawValue:
            self = .goMod
        case Self.cargoToml.rawValue:
            self = .cargoToml
        case Self.packageSwift.rawValue:
            self = .packageSwift
        default:
            return nil
        }
    }

    var language: RepositoryLanguage {
        switch self {
        case .packageJSON: return .typeScriptJavaScript
        case .pyprojectToml: return .python
        case .goMod: return .go
        case .cargoToml: return .rust
        case .packageSwift: return .swift
        }
    }
}

struct RepositoryLanguageProfile: Codable, Equatable {
    var counts: RepositoryLanguageCounts
    var manifestHints: [RepositoryManifestHint]
    var primaryLanguage: RepositoryLanguage
    var scannedFileCount: Int
    var scannedDirectoryCount: Int
    var wasTruncated: Bool

    static let empty = RepositoryLanguageProfile(
        counts: RepositoryLanguageCounts(),
        manifestHints: [],
        primaryLanguage: .unknown,
        scannedFileCount: 0,
        scannedDirectoryCount: 0,
        wasTruncated: false
    )

    var hudSummary: String? {
        guard primaryLanguage != .unknown else { return nil }

        let count = counts[primaryLanguage]
        let manifestNames = manifestHints
            .filter { $0.language == primaryLanguage }
            .map(\.rawValue)

        let sourceSummary: String
        if count > 0 {
            sourceSummary = "\(count) \(primaryLanguage.sourceNoun)"
        } else if !manifestNames.isEmpty {
            sourceSummary = manifestNames.joined(separator: ", ")
        } else {
            sourceSummary = "\(scannedFileCount) scanned files"
        }

        let prefix: String
        switch primaryLanguage {
        case .swift:
            prefix = "Swift forge profile"
        case .typeScriptJavaScript:
            prefix = "TypeScript/JavaScript forge profile"
        case .python:
            prefix = "Python forge profile"
        case .go:
            prefix = "Go forge profile"
        case .rust:
            prefix = "Rust forge profile"
        case .markdown:
            prefix = "Markdown-heavy profile"
        case .other:
            prefix = "Repository profile"
        case .unknown:
            prefix = "Repository profile"
        }

        let suffix = wasTruncated ? " (bounded scan)" : ""
        return "\(prefix): \(sourceSummary)\(suffix)."
    }
}

enum RepositoryLanguageProfileService {
    static func scan(repoURL: URL) -> RepositoryLanguageProfile {
        RepositoryLanguageProfileScanner(repoURL: repoURL).scan()
    }
}

private struct RepositoryLanguageProfileScanner {
    private static let maxFiles = 12_000
    private static let maxDirectories = 2_000
    private static let ignoredDirectoryNames: Set<String> = [
        ".build",
        ".compass",
        ".git",
        ".hg",
        ".mypy_cache",
        ".next",
        ".pytest_cache",
        ".ruff_cache",
        ".svn",
        ".tox",
        ".venv",
        ".yarn",
        "__pycache__",
        "build",
        "coverage",
        "DerivedData",
        "dist",
        "env",
        "node_modules",
        "target",
        "venv"
    ]

    private let repoURL: URL
    private let fileManager = FileManager.default

    init(repoURL: URL) {
        self.repoURL = repoURL.standardizedFileURL
    }

    func scan() -> RepositoryLanguageProfile {
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

                let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
                if values?.isSymbolicLink == true {
                    continue
                }

                if values?.isDirectory == true {
                    guard !Self.ignoredDirectoryNames.contains(child.lastPathComponent) else { continue }
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
        let children = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants]
        )) ?? []
        return children.sorted { $0.path < $1.path }
    }

    private static func language(for fileURL: URL) -> RepositoryLanguage {
        switch fileURL.pathExtension.lowercased() {
        case "cjs", "cts", "js", "jsx", "mjs", "mts", "ts", "tsx":
            return .typeScriptJavaScript
        case "py", "pyi":
            return .python
        case "go":
            return .go
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
            .typeScriptJavaScript,
            .python,
            .go,
            .rust,
            .swift,
            .markdown
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
                return codeLanguages.firstIndex(of: lhs)! > codeLanguages.firstIndex(of: rhs)!
            }
            return left < right
        }

        guard let best, scores[best, default: 0] > 0 else {
            return counts.other > 0 ? .other : .unknown
        }
        return best
    }
}
