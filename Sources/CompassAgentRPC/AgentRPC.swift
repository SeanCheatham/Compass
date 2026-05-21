import Foundation

/// Wire types for the Compass guest-agent RPC.
///
/// Both the host (`AgentVsockClient`) and the in-guest binary
/// (`CompassGuestAgent`) link this module so they can't drift on the
/// payload shape. The transport is one request + one response per vsock
/// connection — no multi-request framing, no streaming. That keeps the
/// codec trivial and makes connection-level failures clean (the host
/// just opens a fresh socket for the next call).
///
/// Binary file contents are base64 inside the JSON so we don't have to
/// invent a second framing scheme for raw bytes.
public enum AgentRPCRequest: Codable, Sendable, Equatable {
    case readFile(ReadFileArgs)
    case writeFile(WriteFileArgs)
    case stat(PathArgs)
    case listDirectory(PathArgs)
    case glob(GlobArgs)
    case grep(GrepArgs)
    case bash(BashArgs)

    public struct ReadFileArgs: Codable, Sendable, Equatable {
        public var path: String
        public init(path: String) { self.path = path }
    }

    public struct WriteFileArgs: Codable, Sendable, Equatable {
        public var path: String
        public var dataBase64: String
        public init(path: String, dataBase64: String) {
            self.path = path
            self.dataBase64 = dataBase64
        }
    }

    public struct PathArgs: Codable, Sendable, Equatable {
        public var path: String
        public init(path: String) { self.path = path }
    }

    public struct GlobArgs: Codable, Sendable, Equatable {
        public var pattern: String
        public var rootPath: String
        public var walkCap: Int
        public init(pattern: String, rootPath: String, walkCap: Int) {
            self.pattern = pattern
            self.rootPath = rootPath
            self.walkCap = walkCap
        }
    }

    public struct GrepArgs: Codable, Sendable, Equatable {
        public var pattern: String
        public var path: String
        public var glob: String?
        public var caseInsensitive: Bool
        public var timeoutSeconds: Double
        public init(
            pattern: String,
            path: String,
            glob: String?,
            caseInsensitive: Bool,
            timeoutSeconds: Double
        ) {
            self.pattern = pattern
            self.path = path
            self.glob = glob
            self.caseInsensitive = caseInsensitive
            self.timeoutSeconds = timeoutSeconds
        }
    }

    public struct BashArgs: Codable, Sendable, Equatable {
        public var command: String
        public var workingDirectory: String
        public var timeoutSeconds: Double
        public init(
            command: String,
            workingDirectory: String,
            timeoutSeconds: Double
        ) {
            self.command = command
            self.workingDirectory = workingDirectory
            self.timeoutSeconds = timeoutSeconds
        }
    }
}

public enum AgentRPCResponse: Codable, Sendable, Equatable {
    case readFile(ReadFileResult)
    case writeFile
    case stat(StatResult)
    case listDirectory(ListDirectoryResult)
    case glob(GlobResult)
    case grep(ProcessResult)
    case bash(ProcessResult)
    case error(Error)

    public struct ReadFileResult: Codable, Sendable, Equatable {
        public var dataBase64: String
        public init(dataBase64: String) { self.dataBase64 = dataBase64 }
    }

    public struct StatResult: Codable, Sendable, Equatable {
        public var metadata: FileMetadata?
        public init(metadata: FileMetadata?) { self.metadata = metadata }
    }

    public struct ListDirectoryResult: Codable, Sendable, Equatable {
        public var entries: [DirectoryEntry]
        public init(entries: [DirectoryEntry]) { self.entries = entries }
    }

    public struct GlobResult: Codable, Sendable, Equatable {
        public var matches: [GlobMatch]
        public init(matches: [GlobMatch]) { self.matches = matches }
    }

    /// Mirrors Compass's host-side `ProcessResult` shape so the host can
    /// shovel this straight into its existing tool formatting.
    public struct ProcessResult: Codable, Sendable, Equatable {
        public var exitCode: Int32
        public var stdout: String
        public var stderr: String
        public init(exitCode: Int32, stdout: String, stderr: String) {
            self.exitCode = exitCode
            self.stdout = stdout
            self.stderr = stderr
        }
    }

    public struct Error: Codable, Sendable, Equatable, Swift.Error {
        public var kind: ErrorKind
        public var detail: String
        public init(kind: ErrorKind, detail: String) {
            self.kind = kind
            self.detail = detail
        }
    }

    public enum ErrorKind: String, Codable, Sendable, Equatable {
        case notFound
        case notRegularFile
        case notDirectory
        case ioFailure
        case invalidArguments
        case internalError
    }

    public struct FileMetadata: Codable, Sendable, Equatable {
        public var path: String
        public var isDirectory: Bool
        public var isRegularFile: Bool
        public var size: Int?
        public var modificationDateEpoch: Double?
        public init(
            path: String,
            isDirectory: Bool,
            isRegularFile: Bool,
            size: Int?,
            modificationDateEpoch: Double?
        ) {
            self.path = path
            self.isDirectory = isDirectory
            self.isRegularFile = isRegularFile
            self.size = size
            self.modificationDateEpoch = modificationDateEpoch
        }
    }

    public struct DirectoryEntry: Codable, Sendable, Equatable {
        public var path: String
        public var name: String
        public var isDirectory: Bool
        public init(path: String, name: String, isDirectory: Bool) {
            self.path = path
            self.name = name
            self.isDirectory = isDirectory
        }
    }

    public struct GlobMatch: Codable, Sendable, Equatable {
        public var path: String
        public var modificationDateEpoch: Double?
        public init(path: String, modificationDateEpoch: Double?) {
            self.path = path
            self.modificationDateEpoch = modificationDateEpoch
        }
    }
}
