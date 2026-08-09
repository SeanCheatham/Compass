import Foundation

@MainActor
extension SharedCompassVM {
  /// Default / minimum guest disk capacity exposed to the Runtime UI (64 GiB).
  public static let defaultDiskCapacityBytes =
    SharedCompassVMImageInstaller.defaultDiskSizeInBytes

  /// Maximum grow target for the Runtime slider (512 GiB).
  public static let maximumDiskCapacityBytes: UInt64 = 512 * 1024 * 1024 * 1024

  /// Slider step (16 GiB).
  public static let diskCapacityStepBytes: UInt64 = 16 * 1024 * 1024 * 1024

  /// Logical size of `Disk.img` when present; otherwise `lastBundleSize` or
  /// the 64 GiB default.
  public var currentDiskCapacityBytes: UInt64 {
    if let size = try? SharedCompassVMImageInstaller.diskImageSizeInBytes(
      at: bundle.diskImageURL,
      fileManager: dependencies.fileManager
    ) {
      return size
    }
    let state =
      (try? bundle.loadState(fileManager: dependencies.fileManager))
      ?? SharedCompassVMBundle.State()
    return state.lastBundleSize ?? Self.defaultDiskCapacityBytes
  }

  /// Preferred capacity for the next install (and grow target watermark).
  /// Prefers persisted `lastBundleSize`, else the on-disk image size / default.
  public var preferredDiskCapacityBytes: UInt64 {
    let state =
      (try? bundle.loadState(fileManager: dependencies.fileManager))
      ?? SharedCompassVMBundle.State()
    if let preferred = state.lastBundleSize, preferred > 0 {
      return preferred
    }
    return currentDiskCapacityBytes
  }

  /// Whether a live Virtualization guest currently holds `Disk.img` open.
  public var isDiskCapacityLockedByRunningVM: Bool {
    if virtualMachine != nil { return true }
    switch readiness {
    case .starting, .downloadingIPSW, .installing, .guestPrepping, .provisioningDevTools:
      return true
    default:
      return false
    }
  }

  /// Whether the sparse guest disk image exists on disk (provisioned at least once).
  public var hasGuestDiskImage: Bool {
    dependencies.fileManager.fileExists(atPath: bundle.diskImageURL.path)
  }

  /// Grow-only: extend the host sparse image, boot the guest, then expand
  /// the APFS container into the new capacity. Leaves the VM running.
  ///
  /// When `toBytes` already matches the host image size, skips the host
  /// truncate and only re-runs the guest APFS resize (recovery path after a
  /// prior grow that enlarged `Disk.img` but failed inside the guest).
  public func growDisk(toBytes: UInt64) async throws {
    guard !isDiskCapacityLockedByRunningVM else {
      throw DiskGrowError.vmMustBeStopped
    }
    let current = currentDiskCapacityBytes
    guard toBytes >= current else {
      throw DiskGrowError.nothingToGrow(current: current, requested: toBytes)
    }
    guard toBytes <= Self.maximumDiskCapacityBytes else {
      throw DiskGrowError.aboveMaximum(requested: toBytes, maximum: Self.maximumDiskCapacityBytes)
    }
    guard dependencies.fileManager.fileExists(atPath: bundle.diskImageURL.path) else {
      throw SharedCompassVMImageInstaller.DiskCapacityError.diskImageMissing(
        path: bundle.diskImageURL.path
      )
    }

    if toBytes > current {
      appendDiagnostic(
        "Growing guest disk from \(Self.formatGiB(current)) to \(Self.formatGiB(toBytes))…",
        source: "host"
      )

      try SharedCompassVMImageInstaller.extendDiskImage(
        at: bundle.diskImageURL,
        toSizeInBytes: toBytes,
        fileManager: dependencies.fileManager
      )
      try bundle.mutateState(fileManager: dependencies.fileManager) {
        $0.lastBundleSize = toBytes
      }
    } else {
      appendDiagnostic(
        "Host disk already \(Self.formatGiB(current)); retrying guest APFS resize…",
        source: "host"
      )
    }

    // Guest APFS only sees the new capacity after a boot with the enlarged
    // virtio-blk attachment; resizeContainer claims the free space.
    try await start()
    let ready = try await AgentMacOSVMBashRunner.ensureReady()
    let result = try await ready.client.run(
      command: Self.guestAPFSResizeCommand,
      workingDirectory: URL(fileURLWithPath: "/"),
      timeout: 300
    )
    guard result.exitCode == 0 else {
      let detail = (result.stderr + "\n" + result.stdout)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      throw DiskGrowError.guestResizeFailed(detail: detail.isEmpty ? "exit \(result.exitCode)" : detail)
    }
    appendDiagnostic(
      "Guest APFS container resized to claim \(Self.formatGiB(toBytes)).",
      source: "host"
    )
  }

  /// Resolve the APFS container for `/` and claim all free space on the
  /// physical store. Prefer plist (`APFSContainerReference`); fall back to
  /// human `diskutil info` labels — sealed-system volumes print
  /// `APFS Container:` rather than the older `APFS Container Reference:`.
  static let guestAPFSResizeCommand = """
    CONTAINER=$(diskutil info -plist / 2>/dev/null | plutil -extract APFSContainerReference raw -o - - 2>/dev/null || true)
    if [ -z "$CONTAINER" ]; then
      CONTAINER=$(diskutil info / 2>/dev/null | sed -n -E 's/^[[:space:]]*APFS Container( Reference)?:[[:space:]]*//p' | head -1)
    fi
    if [ -z "$CONTAINER" ]; then
      CONTAINER=$(diskutil info / 2>/dev/null | sed -n -E 's/^[[:space:]]*Part of Whole:[[:space:]]*//p' | head -1)
    fi
    if [ -z "$CONTAINER" ]; then
      echo "Could not resolve APFS container for /" >&2
      diskutil info / >&2 || true
      exit 1
    fi
    echo "Resizing APFS container $CONTAINER to claim free space…"
    sudo diskutil apfs resizeContainer "$CONTAINER" 0
    """

  nonisolated public static func formatGiB(_ bytes: UInt64) -> String {
    let gib = Double(bytes) / Double(1024 * 1024 * 1024)
    if gib == gib.rounded() {
      return "\(Int(gib)) GiB"
    }
    return String(format: "%.1f GiB", gib)
  }

  public enum DiskGrowError: Error, LocalizedError, Equatable {
    case vmMustBeStopped
    case nothingToGrow(current: UInt64, requested: UInt64)
    case aboveMaximum(requested: UInt64, maximum: UInt64)
    case guestResizeFailed(detail: String)

    public var errorDescription: String? {
      switch self {
      case .vmMustBeStopped:
        return "Stop the VM before changing disk size."
      case .nothingToGrow(let current, let requested):
        return
          "Requested disk size (\(SharedCompassVM.formatGiB(requested))) is smaller than the current capacity (\(SharedCompassVM.formatGiB(current)))."
      case .aboveMaximum(let requested, let maximum):
        return
          "Requested disk size (\(SharedCompassVM.formatGiB(requested))) exceeds the maximum (\(SharedCompassVM.formatGiB(maximum)))."
      case .guestResizeFailed(let detail):
        return "Host disk grew but guest APFS resize failed: \(detail)"
      }
    }
  }
}
