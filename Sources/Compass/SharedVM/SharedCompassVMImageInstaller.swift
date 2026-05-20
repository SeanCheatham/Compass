import Foundation
import os
import Virtualization

extension OSLog {
    static let restoreImageFetch = OSLog(subsystem: "com.seancheatham.Compass", category: "RestoreImageFetch")
}

/// IPSW fetch + restore-image installation pipeline for the Compass shared VM.
///
/// The pipeline has two stages:
///
///   1. **Discover + download** the latest supported macOS restore image
///      (`VZMacOSRestoreImage.fetchLatestSupported` → `URLSession` download).
///   2. **Install** that image onto a freshly-prepared bundle
///      (`VZMacOSInstaller.install`).
///
/// Both stages stream progress as `AsyncStream<Double>` (0.0…1.0).
///
/// The components are split into protocols for unit testing:
/// `RestoreImageFetcher`, `IPSWDownloading`, and `InstallerRunning`.
/// `SharedCompassVMImageInstaller` composes them via constructor injection.
struct SharedCompassVMImageInstaller {
    let fetcher: RestoreImageFetcher
    let downloader: IPSWDownloading
    let installerRunner: InstallerRunning

    init(
        fetcher: RestoreImageFetcher = DefaultRestoreImageFetcher(),
        downloader: IPSWDownloading = DefaultIPSWDownloader(),
        installerRunner: InstallerRunning = DefaultInstallerRunner()
    ) {
        self.fetcher = fetcher
        self.downloader = downloader
        self.installerRunner = installerRunner
    }

    /// Combined high-level entry point: fetches the latest restore image
    /// URL, downloads it (or reuses an on-disk cache), prepares the bundle
    /// disk image, then runs `VZMacOSInstaller`.
    ///
    /// Progress is split into two phases:
    ///   * `downloadProgress` — IPSW download (0…1).
    ///   * `installProgress` — installer fractional progress (0…1).
    func install(
        into bundle: SharedCompassVMBundle,
        localIPSWURL: URL? = nil,
        diskSizeInBytes: UInt64 = 64 * 1024 * 1024 * 1024,
        downloadProgress: ProgressSink? = nil,
        installProgress: ProgressSink? = nil,
        fileManager: FileManager = .default
    ) async throws {
        try bundle.ensureExists(fileManager: fileManager)

        // Stage 1: locate the IPSW. If the caller supplied a local file,
        // skip the catalog fetch + download entirely — this is the fallback
        // for hosts where `fetchLatestSupported` fails (e.g. beta macOS).
        let restoreImageURL: URL
        if let localIPSWURL {
            restoreImageURL = localIPSWURL
            downloadProgress?.send(1.0)
        } else {
            let remoteURL = try await fetcher.fetchLatestSupportedURL()
            let version = Self.versionLabel(for: remoteURL)
            let cachedURL = bundle.restoreImageURL(forVersion: version)
            try await downloader.download(
                from: remoteURL,
                to: cachedURL,
                progress: downloadProgress,
                fileManager: fileManager
            )
            restoreImageURL = cachedURL
        }

        // Stage 2: allocate the disk image if necessary, then run the installer.
        try Self.allocateDiskImageIfNeeded(
            at: bundle.diskImageURL,
            sizeInBytes: diskSizeInBytes,
            fileManager: fileManager
        )

        try await installerRunner.runInstaller(
            bundle: bundle,
            restoreImageURL: restoreImageURL,
            progress: installProgress
        )
    }

    /// Allocates an empty sparse disk image at `url` if absent. Existing files
    /// are left alone — callers that want a clean slate must delete first.
    static func allocateDiskImageIfNeeded(
        at url: URL,
        sizeInBytes: UInt64,
        fileManager: FileManager = .default
    ) throws {
        if fileManager.fileExists(atPath: url.path) {
            return
        }
        guard fileManager.createFile(atPath: url.path, contents: nil) else {
            throw NSError(
                domain: "SharedCompassVMImageInstaller",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not create disk image at \(url.path)"]
            )
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: sizeInBytes)
    }

    /// Derives a stable version label from the IPSW URL's filename so that
    /// cached restore images are namespaced per version.
    static func versionLabel(for remoteURL: URL) -> String {
        let last = remoteURL.deletingPathExtension().lastPathComponent
        let trimmed = last.isEmpty ? "Unknown" : last
        var sanitized = ""
        for scalar in trimmed.unicodeScalars {
            if scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "." || scalar == "-" || scalar == "_") {
                sanitized.unicodeScalars.append(scalar)
            } else {
                sanitized.append("_")
            }
        }
        return sanitized
    }
}

// MARK: - Progress sink

extension SharedCompassVMImageInstaller {
    /// Continuation-based progress sink — pairs with `AsyncStream<Double>`
    /// constructed at the call site.
    struct ProgressSink {
        let send: @Sendable (Double) -> Void

        init(send: @escaping @Sendable (Double) -> Void) {
            self.send = send
        }

        /// Helper: build a `ProgressSink` + matching `AsyncStream<Double>`.
        static func makeStream() -> (ProgressSink, AsyncStream<Double>) {
            let (stream, continuation) = AsyncStream<Double>.makeStream()
            let sink = ProgressSink { value in
                continuation.yield(value)
            }
            return (sink, stream)
        }
    }
}

// MARK: - RestoreImageFetcher

protocol RestoreImageFetcher {
    /// Returns the remote URL of the latest macOS restore image supported
    /// by the host running Compass.
    func fetchLatestSupportedURL() async throws -> URL
}

struct DefaultRestoreImageFetcher: RestoreImageFetcher {
    func fetchLatestSupportedURL() async throws -> URL {
        os_log(.info, log: .restoreImageFetch, "Calling VZMacOSRestoreImage.fetchLatestSupported…")
        do {
            let url = try await withCheckedThrowingContinuation { continuation in
                VZMacOSRestoreImage.fetchLatestSupported { result in
                    switch result {
                    case .success(let image):
                        os_log(.info, log: .restoreImageFetch, "Catalog fetch succeeded: build %{public}@ URL %{public}@",
                               image.buildVersion, image.url.absoluteString)
                        continuation.resume(returning: image.url)
                    case .failure(let error):
                        Self.logFetchError(error)
                        continuation.resume(throwing: error)
                    }
                }
            }
            return url
        } catch {
            Self.logFetchError(error)
            throw error
        }
    }

    private static func logFetchError(_ error: Error) {
        let ns = error as NSError
        os_log(.error, log: .restoreImageFetch,
               "fetchLatestSupported failed — domain=%{public}@ code=%d description=%{public}@",
               ns.domain, ns.code, ns.localizedDescription)
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            os_log(.error, log: .restoreImageFetch,
                   "  underlying — domain=%{public}@ code=%d description=%{public}@",
                   underlying.domain, underlying.code, underlying.localizedDescription)
        }
        for (key, value) in ns.userInfo where key != NSUnderlyingErrorKey {
            os_log(.error, log: .restoreImageFetch,
                   "  userInfo[%{public}@] = %{public}@",
                   key, String(describing: value))
        }
    }
}

// MARK: - IPSW downloader

protocol IPSWDownloading {
    /// Downloads `remoteURL` to `destinationURL`. If the file already exists
    /// and matches the expected length advertised by HEAD, the download is
    /// skipped. Otherwise a partial file at `destinationURL` is resumed
    /// using HTTP Range requests where possible.
    func download(
        from remoteURL: URL,
        to destinationURL: URL,
        progress: SharedCompassVMImageInstaller.ProgressSink?,
        fileManager: FileManager
    ) async throws
}

struct DefaultIPSWDownloader: IPSWDownloading {
    let sessionConfiguration: URLSessionConfiguration

    init(sessionConfiguration: URLSessionConfiguration = .default) {
        self.sessionConfiguration = sessionConfiguration
    }

    func download(
        from remoteURL: URL,
        to destinationURL: URL,
        progress: SharedCompassVMImageInstaller.ProgressSink?,
        fileManager: FileManager
    ) async throws {
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Probe HEAD once to see whether a cached file is already complete.
        // We don't need a separate session for the HEAD — it's a single
        // request and we discard the session immediately after.
        let probeSession = URLSession(configuration: sessionConfiguration)
        defer { probeSession.finishTasksAndInvalidate() }
        let (totalSize, existingSize) = try await Self.probeSizes(
            remoteURL: remoteURL,
            destinationURL: destinationURL,
            session: probeSession,
            fileManager: fileManager
        )

        if totalSize > 0, existingSize == totalSize {
            progress?.send(1.0)
            return
        }

        // Use a delegate-driven download task: it streams bytes to a tempfile
        // via the URL loading system (no per-byte async overhead) and emits
        // chunked progress callbacks suitable for a 14 GB file. We move the
        // tempfile into place on completion. Range-resume across launches
        // is best-effort: if the partial file's size matches what the
        // server reports as `Content-Length`, we treat it as complete; we
        // do not yet stitch ranged bodies together, because the IPSW
        // download is short-lived per app session.
        let delegate = IPSWDownloadDelegate(
            progress: progress,
            destinationURL: destinationURL,
            fileManager: fileManager,
            existingSize: existingSize,
            totalSize: totalSize
        )
        let session = URLSession(
            configuration: sessionConfiguration,
            delegate: delegate,
            delegateQueue: nil
        )
        defer { session.finishTasksAndInvalidate() }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            delegate.continuation = continuation
            let task = session.downloadTask(with: remoteURL)
            task.resume()
        }
    }

    /// Returns (totalRemoteSize, existingLocalSize). Uses a HEAD request to
    /// probe the remote length; missing Content-Length is reported as 0.
    private static func probeSizes(
        remoteURL: URL,
        destinationURL: URL,
        session: URLSession,
        fileManager: FileManager
    ) async throws -> (UInt64, UInt64) {
        var existing: UInt64 = 0
        if fileManager.fileExists(atPath: destinationURL.path) {
            let attrs = try fileManager.attributesOfItem(atPath: destinationURL.path)
            existing = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        }

        var headRequest = URLRequest(url: remoteURL)
        headRequest.httpMethod = "HEAD"
        let (_, response) = try await session.data(for: headRequest)
        let total: UInt64
        if let httpResponse = response as? HTTPURLResponse, httpResponse.expectedContentLength > 0 {
            total = UInt64(httpResponse.expectedContentLength)
        } else {
            total = 0
        }
        return (total, existing)
    }
}

/// `URLSessionDownloadDelegate` adapter that bridges chunked download
/// progress to a `SharedCompassVMImageInstaller.ProgressSink` and resumes
/// a checked continuation on completion or failure.
///
/// Marked `@unchecked Sendable` because the delegate is exclusively driven
/// from URLSession's internal serial queue and `FileManager`'s methods we
/// call (`fileExists`, `moveItem`, `removeItem`) are thread-safe on the
/// shared default instance.
private final class IPSWDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let progress: SharedCompassVMImageInstaller.ProgressSink?
    let destinationURL: URL
    let fileManager: FileManager
    let existingSize: UInt64
    let totalSize: UInt64
    var continuation: CheckedContinuation<Void, Error>?

    init(
        progress: SharedCompassVMImageInstaller.ProgressSink?,
        destinationURL: URL,
        fileManager: FileManager,
        existingSize: UInt64,
        totalSize: UInt64
    ) {
        self.progress = progress
        self.destinationURL = destinationURL
        self.fileManager = fileManager
        self.existingSize = existingSize
        self.totalSize = totalSize
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        // Prefer the task's expected length, fall back to the HEAD-derived
        // total. A negative expected length means "unknown" — emit nothing
        // rather than divide-by-zero.
        let expected: Int64
        if totalBytesExpectedToWrite > 0 {
            expected = totalBytesExpectedToWrite
        } else if totalSize > 0 {
            expected = Int64(totalSize)
        } else {
            return
        }
        let fraction = max(0.0, min(1.0, Double(totalBytesWritten) / Double(expected)))
        progress?.send(fraction)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: location, to: destinationURL)
            progress?.send(1.0)
            continuation?.resume(returning: ())
            continuation = nil
        } catch {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

// MARK: - Installer runner

protocol InstallerRunning {
    /// Drives `VZMacOSInstaller` against the supplied bundle + restore image.
    /// Must be invoked from a context that does not assume any particular
    /// executor; the default implementation hops to `@MainActor` internally
    /// because VZ APIs require the main thread.
    func runInstaller(
        bundle: SharedCompassVMBundle,
        restoreImageURL: URL,
        progress: SharedCompassVMImageInstaller.ProgressSink?
    ) async throws
}

struct DefaultInstallerRunner: InstallerRunning {
    func runInstaller(
        bundle: SharedCompassVMBundle,
        restoreImageURL: URL,
        progress: SharedCompassVMImageInstaller.ProgressSink?
    ) async throws {
        let restoreImage = try await Self.loadRestoreImage(at: restoreImageURL)
        guard let requirements = restoreImage.mostFeaturefulSupportedConfiguration else {
            throw NSError(
                domain: "SharedCompassVMImageInstaller",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Restore image has no supported configuration on this host"]
            )
        }
        try await Self.runMainActor(
            bundle: bundle,
            restoreImageURL: restoreImageURL,
            requirements: requirements,
            progress: progress
        )
    }

    @MainActor
    private static func runMainActor(
        bundle: SharedCompassVMBundle,
        restoreImageURL: URL,
        requirements: VZMacOSConfigurationRequirements,
        progress: SharedCompassVMImageInstaller.ProgressSink?
    ) async throws {
        let inputs = SharedCompassVMConfiguration.Inputs(
            bundle: bundle,
            cpuCount: 4,
            memorySize: 8 * 1024 * 1024 * 1024,
            shareTargets: []
        )
        let configuration = try SharedCompassVMConfiguration.makeInstallationConfiguration(
            for: inputs,
            requirements: requirements
        )
        try configuration.validate()

        let machine = VZVirtualMachine(configuration: configuration)
        let installer = VZMacOSInstaller(virtualMachine: machine, restoringFromImageAt: restoreImageURL)

        // Bridge KVO on installer.progress.fractionCompleted into the AsyncStream.
        let observer = ProgressKVOForwarder(sink: progress)
        installer.progress.addObserver(observer, forKeyPath: "fractionCompleted", options: [.new, .initial], context: nil)
        defer {
            installer.progress.removeObserver(observer, forKeyPath: "fractionCompleted")
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            installer.install { result in
                switch result {
                case .success:
                    continuation.resume(returning: ())
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func loadRestoreImage(at url: URL) async throws -> VZMacOSRestoreImage {
        try await withCheckedThrowingContinuation { continuation in
            VZMacOSRestoreImage.load(from: url) { result in
                switch result {
                case .success(let image):
                    continuation.resume(returning: image)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

/// KVO bridge that forwards `Progress.fractionCompleted` changes into a
/// `SharedCompassVMImageInstaller.ProgressSink`. Held by the installer
/// runner for the duration of the install.
private final class ProgressKVOForwarder: NSObject {
    let sink: SharedCompassVMImageInstaller.ProgressSink?

    init(sink: SharedCompassVMImageInstaller.ProgressSink?) {
        self.sink = sink
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        guard let progress = object as? Progress else { return }
        sink?.send(progress.fractionCompleted)
    }
}
