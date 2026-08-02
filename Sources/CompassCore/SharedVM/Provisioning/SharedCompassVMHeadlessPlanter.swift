import Foundation

/// Host-side disk planter for the Compass shared VM's headless first-boot
/// pipeline.
///
/// Runs **once** between `VZMacOSInstaller.install` completing and the very
/// first `VZVirtualMachine.start` call. Mounts the just-installed Disk.img
/// on the host, writes the LaunchDaemon plist + bootstrap script + sudoers
/// fragment + supporting payload into the Data volume, then unmounts. The
/// guest's first boot then runs the planted LaunchDaemon, which creates the
/// `compass` admin user, authorises Compass's SSH key, and enables sshd —
/// all without Setup Assistant ever appearing.
///
/// Architecture:
///   * `Planter.plant(...)` is the imperative entry point invoked from
///     `SharedCompassVM.provisionIfNeeded`.
///   * Discovery (find the Data volume devnode inside the disk image) runs
///     **unprivileged** — `hdiutil attach -nomount` and `diskutil apfs list`
///     don't need root.
///   * Mounting + writing root-owned files runs **once-elevated** via a
///     single `osascript do shell script ... with administrator privileges`
///     prompt. The user sees one Mac authentication dialog per install.
///   * The elevated portion is a small bash script (rendered by
///     `renderElevatedScript`) so the privileged step set is reviewable
///     and unit-testable.
enum SharedCompassVMHeadlessPlanter {
  // MARK: - Stage names

  /// Filenames Compass writes into the host staging directory. The
  /// elevated script reads them by these well-known names; renaming any
  /// of them breaks both sides in lockstep.
  enum StagedFile {
    static let launchDaemonPlist = "launchd.plist"
    static let bootstrapScript = "bootstrap.sh"
    static let sudoersFragment = "sudoers"
    static let appleSetupDoneMarker = "apple-setup-done"
    static let publicKey = "id_ed25519.pub"
    static let passwordFile = "user.password"
    static let elevatedScript = "planter.sh"
    /// The CompassGuestAgent binary, copied verbatim from the host's
    /// build output into the guest's `/usr/local/libexec/`.
    static let guestAgentBinary = "compass-guest-agent"
    /// The LaunchDaemon plist that loads the guest agent at boot in
    /// the system context (dropping to the compass user via UserName).
    static let guestAgentLaunchDaemonPlist = "com.seancheatham.Compass.guest-agent.plist"
    static let autoLoginScript = "compass-autologin.sh"
    static let autoLoginLaunchDaemonPlist = "com.seancheatham.Compass.autologin.plist"
  }

  // MARK: - Errors

  enum Error: Swift.Error, CustomStringConvertible, LocalizedError {
    case toolMissing(path: String)
    case toolFailed(tool: String, exitCode: Int32, output: String)
    case dataVolumeNotFound(diagnostics: String)
    case attachOutputUnparseable(detail: String)
    case userCancelledElevation
    case elevationFailed(detail: String)

    var description: String {
      switch self {
      case .toolMissing(let path):
        return "Required host tool is missing: \(path)"
      case .toolFailed(let tool, let code, let output):
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(tool) exited \(code): \(trimmed)"
      case .dataVolumeNotFound(let diagnostics):
        return "Could not locate the Data APFS volume in the attached disk image. \(diagnostics)"
      case .attachOutputUnparseable(let detail):
        return "hdiutil attach output could not be parsed: \(detail)"
      case .userCancelledElevation:
        return
          "The macOS administrator-authentication prompt was dismissed; headless first-boot was not planted."
      case .elevationFailed(let detail):
        return "Elevated planter script failed: \(detail)"
      }
    }

    /// `LocalizedError.errorDescription` — surfaced by `NSError`'s
    /// `localizedDescription`, which is what
    /// `SharedCompassVMAvailabilityCheck.describeVerbose` renders into
    /// the Sandbox UI. Without this conformance the UI fell back to
    /// Swift's generic "The operation couldn't be completed. (Domain
    /// error N.)" and the captured tool stderr was invisible.
    var errorDescription: String? { description }
  }

  // MARK: - Public API

  struct Report: Equatable {
    var dataVolumeDeviceNode: String
    var stagingDirectoryURL: URL
    var elevatedScriptOutput: String
  }

  /// Drives the full plant lifecycle for `payload` against `diskImageURL`.
  /// Cleans up the host staging dir before returning. Surfaces a
  /// `Report` describing what landed for diagnostics.
  static func plant(
    payload: SharedCompassVMHeadlessFirstBoot.Payload,
    diskImageURL: URL,
    dependencies: Dependencies = .live(),
    fileManager: FileManager = .default
  ) async throws -> Report {
    // 1. Discover the Data volume devnode (no elevation required).
    //
    // `hdiutil attach -nomount` returns the physical devnodes — the
    // whole disk (e.g. /dev/disk4) plus its slices (e.g.
    // /dev/disk4s2 = Apple_APFS). The kernel auto-synthesizes a
    // separate APFS container at a *different* diskN (often several
    // higher, e.g. /dev/disk9) whose `PhysicalStores` references our
    // Apple_APFS slice. `diskutil apfs list` rejects the physical
    // slice — it only knows about synthesized containers — so we have
    // to enumerate all containers system-wide and match by physical
    // store. Detach still targets the whole-disk devnode.
    let attachment = try await dependencies.diskAttacher.attachWithoutMount(
      diskImageURL: diskImageURL
    )
    defer {
      Task {
        try? await dependencies.diskAttacher.detach(deviceNode: attachment.wholeDiskDeviceNode)
      }
    }
    let dataVolume = try await dependencies.dataVolumeLocator.locateDataVolume(
      matchingPhysicalStore: attachment.apfsPhysicalStoreIdentifier
    )

    // 2. Materialize all the payload artifacts in a host staging dir.
    let stagingDir = try makeStagingDirectory(fileManager: fileManager)
    do {
      try stagePayload(payload, into: stagingDir, fileManager: fileManager)

      // 3. Render + write the elevated planter script.
      let elevatedScript = renderElevatedScript(
        payload: payload,
        stagingDirectoryHostPath: stagingDir.path,
        dataVolumeDeviceNode: dataVolume
      )
      let scriptURL = stagingDir.appendingPathComponent(
        StagedFile.elevatedScript, isDirectory: false)
      try Data(elevatedScript.utf8).write(to: scriptURL, options: [.atomic])
      try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

      // 4. Run once with administrator privileges. One auth prompt.
      let output = try await dependencies.elevator.runElevatedScript(at: scriptURL)

      try? fileManager.removeItem(at: stagingDir)
      return Report(
        dataVolumeDeviceNode: dataVolume,
        stagingDirectoryURL: stagingDir,
        elevatedScriptOutput: output
      )
    } catch {
      try? fileManager.removeItem(at: stagingDir)
      throw error
    }
  }

  // MARK: - Staging

  /// Allocates a fresh staging directory under `NSTemporaryDirectory()`.
  /// The directory name embeds a UUID so concurrent provisions (which
  /// shouldn't happen in practice) cannot stomp each other.
  static func makeStagingDirectory(fileManager: FileManager = .default) throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("Compass-HeadlessFirstBoot-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  /// Writes every payload artifact into `stagingDir` using the well-known
  /// `StagedFile` filenames. The elevated planter script reads them from
  /// these locations.
  static func stagePayload(
    _ payload: SharedCompassVMHeadlessFirstBoot.Payload,
    into stagingDir: URL,
    fileManager: FileManager = .default
  ) throws {
    try fileManager.createDirectory(at: stagingDir, withIntermediateDirectories: true)

    let writes: [(String, Data)] = [
      (StagedFile.launchDaemonPlist, payload.launchDaemonPlist),
      (StagedFile.bootstrapScript, Data(payload.bootstrapScript.utf8)),
      (StagedFile.sudoersFragment, Data(payload.sudoersFragment.utf8)),
      (StagedFile.appleSetupDoneMarker, Data()),
      (StagedFile.publicKey, payload.stagedPublicKey),
      (StagedFile.passwordFile, Data(payload.stagedPassword.utf8)),
      (StagedFile.guestAgentBinary, payload.guestAgentBinary),
      (StagedFile.guestAgentLaunchDaemonPlist, payload.guestAgentLaunchDaemonPlist),
      (StagedFile.autoLoginScript, Data(payload.autoLoginScript.utf8)),
      (StagedFile.autoLoginLaunchDaemonPlist, payload.autoLoginLaunchDaemonPlist),
    ]
    for (name, contents) in writes {
      let url = stagingDir.appendingPathComponent(name, isDirectory: false)
      try contents.write(to: url, options: [.atomic])
    }

    // Password file mode is tightened both here and by the elevated
    // script when it lands inside the guest. Belt-and-braces.
    let passwordURL = stagingDir.appendingPathComponent(StagedFile.passwordFile, isDirectory: false)
    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: passwordURL.path)
  }

  // MARK: - Elevated script rendering

  /// Renders the bash script that runs once with administrator privileges.
  /// Pure — exposed for unit tests so the privileged step set can be locked
  /// in without invoking osascript.
  ///
  /// The script:
  ///   1. Mounts the Data volume to a host-private mountpoint.
  ///   2. `install -o root -g wheel -m <mode>` each artifact to its final
  ///      guest path (relative to the mountpoint).
  ///   3. Unmounts the volume.
  ///
  /// Container devnode detach happens in the unprivileged caller (via
  /// `Dependencies.diskAttacher.detach`) so a script failure leaves a
  /// detachable disk rather than a wedged one.
  static func renderElevatedScript(
    payload: SharedCompassVMHeadlessFirstBoot.Payload,
    stagingDirectoryHostPath: String,
    dataVolumeDeviceNode: String
  ) -> String {
    let profile = payload.profile
    return """
      #!/bin/bash
      #
      # Compass headless first-boot planter (elevated portion). Invoked once
      # by SharedCompassVMHeadlessPlanter via osascript with administrator
      # privileges. Mounts the just-installed guest Data volume, plants the
      # first-boot artifacts as root, and unmounts.
      #
      set -euo pipefail

      STAGING_DIR="\(stagingDirectoryHostPath)"
      DATA_DEV="\(dataVolumeDeviceNode)"

      MOUNT_POINT=$(mktemp -d /tmp/compass-firstboot-mount.XXXXXX)
      cleanup() {
        diskutil unmount "$MOUNT_POINT" >/dev/null 2>&1 || true
        rmdir "$MOUNT_POINT" >/dev/null 2>&1 || true
      }
      trap cleanup EXIT

      # Mount the Data volume. Two-tier strategy:
      #
      #   1. Prefer `diskutil mount` (it sets up the standard mount
      #      options + browse hint we want).
      #   2. If diskutil refuses, fall back to the underlying
      #      `mount_apfs` syscall. We've observed diskutil failing with
      #      "Volume on diskNsM failed to mount (code 1)" indefinitely
      #      on freshly-installed VZ disk images even though nothing
      #      has the volume open (lsof empty, no mounts, no VZ helpers
      #      alive). The most likely cause is a diskutil/DA policy
      #      check that doesn't apply when we bypass straight to the
      #      kernel mount path.
      #
      # On failure of both, dump host-side state so the planter's
      # surfaced output names the actual cause.
      mount_attempt=0
      mount_max_attempts=5
      mount_stderr_log=$(mktemp /tmp/compass-firstboot-mount.stderr.XXXXXX)
      mounted=0
      while [ "$mount_attempt" -lt "$mount_max_attempts" ]; do
        if diskutil mount -mountPoint "$MOUNT_POINT" -nobrowse "$DATA_DEV" 2>"$mount_stderr_log"; then
          mounted=1
          break
        fi
        mount_attempt=$((mount_attempt + 1))
        sleep 1
      done

      if [ "$mounted" -eq 0 ]; then
        echo "diskutil mount refused after $mount_max_attempts attempts; trying mount_apfs syscall directly" >&2
        # mount_apfs needs an empty existing directory, same as
        # diskutil with -mountPoint. -o nobrowse keeps Finder out.
        if mount_apfs -o nobrowse "$DATA_DEV" "$MOUNT_POINT" 2>>"$mount_stderr_log"; then
          mounted=1
          echo "mount_apfs succeeded where diskutil refused" >&2
        fi
      fi

      if [ "$mounted" -eq 0 ]; then
        echo "ERROR: both diskutil mount and mount_apfs failed for $DATA_DEV" >&2
        echo "--- accumulated mount stderr ---" >&2
        cat "$mount_stderr_log" >&2 || true
        echo "--- diskutil info $DATA_DEV ---" >&2
        diskutil info "$DATA_DEV" 2>&1 | head -40 >&2 || true
        echo "--- current mounts referencing the data volume ---" >&2
        mount | grep -F "$DATA_DEV" >&2 || echo "  (none)" >&2
        echo "--- lsof on $DATA_DEV (best effort) ---" >&2
        lsof "$DATA_DEV" 2>&1 | head -20 >&2 || true
        echo "--- VZ-related processes still alive ---" >&2
        pgrep -lf 'Compass|com\\.apple\\.Virtualization' >&2 || echo "  (none)" >&2
        rm -f "$mount_stderr_log"
        exit 1
      fi
      rm -f "$mount_stderr_log"

      # .AppleSetupDone — empty marker, root:wheel 0644. Skips Setup
      # Assistant on first boot.
      install -d -o root -g wheel -m 0755 "$MOUNT_POINT\(profile.appleSetupDoneGuestPath.directoryComponent)"
      install -o root -g wheel -m 0644 \\
        "$STAGING_DIR/\(StagedFile.appleSetupDoneMarker)" \\
        "$MOUNT_POINT\(profile.appleSetupDoneGuestPath)"

      # LaunchDaemon plist — root:wheel 0644. launchd refuses non-root
      # plists, so ownership is non-negotiable.
      install -d -o root -g wheel -m 0755 "$MOUNT_POINT\(profile.launchDaemonGuestPath.directoryComponent)"
      install -o root -g wheel -m 0644 \\
        "$STAGING_DIR/\(StagedFile.launchDaemonPlist)" \\
        "$MOUNT_POINT\(profile.launchDaemonGuestPath)"

      # Bootstrap script — root:wheel 0755.
      install -d -o root -g wheel -m 0755 "$MOUNT_POINT\(profile.bootstrapScriptGuestPath.directoryComponent)"
      install -o root -g wheel -m 0755 \\
        "$STAGING_DIR/\(StagedFile.bootstrapScript)" \\
        "$MOUNT_POINT\(profile.bootstrapScriptGuestPath)"

      # sudoers fragment — root:wheel 0440. sudo refuses fragments that
      # are group- or world-writable.
      install -d -o root -g wheel -m 0755 "$MOUNT_POINT\(profile.sudoersFragmentGuestPath.directoryComponent)"
      install -o root -g wheel -m 0440 \\
        "$STAGING_DIR/\(StagedFile.sudoersFragment)" \\
        "$MOUNT_POINT\(profile.sudoersFragmentGuestPath)"

      # Staging payload (public key, password file). Lives under
      # /Users/Shared/compass-firstboot/, root:wheel — the bootstrap script
      # tightens ownership as it consumes each file.
      install -d -o root -g wheel -m 0700 "$MOUNT_POINT\(profile.stagingDirectoryGuestPath)"
      install -o root -g wheel -m 0644 \\
        "$STAGING_DIR/\(StagedFile.publicKey)" \\
        "$MOUNT_POINT\(profile.stagingDirectoryGuestPath)/\(profile.stagedPublicKeyName)"
      install -o root -g wheel -m 0600 \\
        "$STAGING_DIR/\(StagedFile.passwordFile)" \\
        "$MOUNT_POINT\(profile.stagingDirectoryGuestPath)/\(profile.stagedPasswordFileName)"

      # CompassGuestAgent binary — root:wheel 0755. The LaunchDaemon (next
      # install) references this path; permissions match what launchd expects
      # for an executable it will run as the compass user.
      install -d -o root -g wheel -m 0755 "$MOUNT_POINT\(profile.guestAgentBinaryGuestPath.directoryComponent)"
      install -o root -g wheel -m 0755 \\
        "$STAGING_DIR/\(StagedFile.guestAgentBinary)" \\
        "$MOUNT_POINT\(profile.guestAgentBinaryGuestPath)"

      # Guest agent LaunchDaemon plist — root:wheel 0644.
      # /Library/LaunchDaemons is loaded by launchd at boot in the system
      # context (no user session prerequisite — macOS-26 auto-login is
      # unreliable). The plist's UserName key drops the daemon to UID 501
      # so worktree files land with the right ownership.
      install -d -o root -g wheel -m 0755 "$MOUNT_POINT\(profile.guestAgentLaunchDaemonGuestPath.directoryComponent)"
      install -o root -g wheel -m 0644 \\
        "$STAGING_DIR/\(StagedFile.guestAgentLaunchDaemonPlist)" \\
        "$MOUNT_POINT\(profile.guestAgentLaunchDaemonGuestPath)"

      # Auto-login helper — root:wheel 0755 script + 0644 LaunchDaemon.
      # Runs at every boot to re-apply /etc/kcpassword once the guest
      # user and console password file exist.
      install -d -o root -g wheel -m 0755 "$MOUNT_POINT\(profile.autoLoginScriptGuestPath.directoryComponent)"
      install -o root -g wheel -m 0755 \\
        "$STAGING_DIR/\(StagedFile.autoLoginScript)" \\
        "$MOUNT_POINT\(profile.autoLoginScriptGuestPath)"
      install -d -o root -g wheel -m 0755 "$MOUNT_POINT\(profile.autoLoginLaunchDaemonGuestPath.directoryComponent)"
      install -o root -g wheel -m 0644 \\
        "$STAGING_DIR/\(StagedFile.autoLoginLaunchDaemonPlist)" \\
        "$MOUNT_POINT\(profile.autoLoginLaunchDaemonGuestPath)"

      sync
      echo "[compass-planter] done."
      """
  }

  // MARK: - SharedCompassVM injection adapter

  /// Façade exposed to `SharedCompassVM.Dependencies` so the orchestrator
  /// can call into the planter without importing
  /// `SharedCompassVMHeadlessPlanter` directly at the type level. Lets
  /// tests substitute a no-op planter (real planting needs osascript and
  /// is unsuited to unit tests).
  typealias Runner = HeadlessPlanterRunning

  // MARK: - Dependencies (injection seam)

  /// Bag of injectable adapters for the three external operations the
  /// planter performs. `Dependencies.live()` returns the production-wired
  /// concrete types; tests substitute fakes.
  struct Dependencies {
    var diskAttacher: HostDiskAttaching
    var dataVolumeLocator: DataVolumeLocating
    var elevator: AdminElevating

    static func live() -> Dependencies {
      Dependencies(
        diskAttacher: HDIUtilDiskAttacher(),
        dataVolumeLocator: DiskUtilDataVolumeLocator(),
        elevator: OSAScriptAdminElevator()
      )
    }
  }
}

// MARK: - Path helper

extension String {
  /// Returns the directory portion of an absolute file path, e.g.
  /// `/Library/LaunchDaemons/foo.plist` -> `/Library/LaunchDaemons`. Used by
  /// the elevated script renderer to emit `install -d` calls for each
  /// destination's parent dir without paying a runtime `dirname` shell-out.
  fileprivate var directoryComponent: String {
    (self as NSString).deletingLastPathComponent
  }
}

// MARK: - HeadlessPlanterRunning (orchestrator-facing protocol)

/// Narrow façade `SharedCompassVM.Dependencies` injects to drive the
/// planter without coupling to the namespace enum's static API. Lets unit
/// tests substitute an in-memory fake that captures the payload and skips
/// the real osascript prompt + hdiutil dance.
protocol HeadlessPlanterRunning {
  func plant(
    payload: SharedCompassVMHeadlessFirstBoot.Payload,
    diskImageURL: URL
  ) async throws -> SharedCompassVMHeadlessPlanter.Report
}

/// Production planter — delegates straight to the namespace enum's
/// static `plant(...)` API.
struct DefaultHeadlessPlanter: HeadlessPlanterRunning {
  func plant(
    payload: SharedCompassVMHeadlessFirstBoot.Payload,
    diskImageURL: URL
  ) async throws -> SharedCompassVMHeadlessPlanter.Report {
    try await SharedCompassVMHeadlessPlanter.plant(
      payload: payload,
      diskImageURL: diskImageURL
    )
  }
}

// MARK: - HostDiskAttaching

/// Wraps `hdiutil attach -nomount` + `hdiutil detach`.
protocol HostDiskAttaching {
  /// Attaches the disk image without mounting any volumes. Returns the
  /// attached devnode (e.g. `/dev/disk5`) plus the raw plist output for
  /// diagnostics.
  func attachWithoutMount(diskImageURL: URL) async throws -> HostDiskAttachment

  /// Detaches the previously-attached device node.
  func detach(deviceNode: String) async throws
}

struct HostDiskAttachment: Equatable {
  /// Whole-disk device node, e.g. `/dev/disk5`. Use this for
  /// `hdiutil detach` — it tears down the entire attachment, including
  /// every synthesized APFS container that flowed from this disk image.
  var wholeDiskDeviceNode: String
  /// Apple_APFS physical-store *identifier* (no `/dev/` prefix), e.g.
  /// `disk5s2`. Matches the `DeviceIdentifier` strings inside
  /// `diskutil apfs list`'s `Containers[].PhysicalStores[]` array, so
  /// the data-volume locator can find the synthesized container that
  /// belongs to our just-attached disk image rather than some other
  /// APFS container on the host.
  var apfsPhysicalStoreIdentifier: String
  /// Full plist payload returned by `hdiutil attach`. Useful in test
  /// failures and rare "no recognised volumes" diagnostics.
  var rawPlist: String
}

struct HDIUtilDiskAttacher: HostDiskAttaching {
  let hdiutilPath: String

  init(hdiutilPath: String = "/usr/bin/hdiutil") {
    self.hdiutilPath = hdiutilPath
  }

  func attachWithoutMount(diskImageURL: URL) async throws -> HostDiskAttachment {
    let result = try await HeadlessPlanterProcessRunner.runCapture(
      executable: hdiutilPath,
      arguments: ["attach", "-nomount", "-plist", "-nobrowse", diskImageURL.path]
    )
    let wholeDiskDeviceNode = try Self.parseContainerDeviceNode(fromPlist: result.standardOutput)
    let apfsPhysicalStoreIdentifier = try Self.parseAPFSPhysicalStoreIdentifier(
      fromPlist: result.standardOutput
    )
    return HostDiskAttachment(
      wholeDiskDeviceNode: wholeDiskDeviceNode,
      apfsPhysicalStoreIdentifier: apfsPhysicalStoreIdentifier,
      rawPlist: result.standardOutput
    )
  }

  func detach(deviceNode: String) async throws {
    _ = try await HeadlessPlanterProcessRunner.runCapture(
      executable: hdiutilPath,
      arguments: ["detach", deviceNode]
    )
  }

  /// Parses `hdiutil attach -plist` output and returns the first
  /// `dev-entry` whose `content-hint` indicates the whole-disk container.
  /// Falls back to the first numbered `/dev/diskN` entry when no clear
  /// container hint is present (some images are simple single-partition).
  static func parseContainerDeviceNode(fromPlist plistString: String) throws -> String {
    guard let data = plistString.data(using: .utf8) else {
      throw SharedCompassVMHeadlessPlanter.Error.attachOutputUnparseable(detail: "non-UTF8 plist")
    }
    let parsed: Any
    do {
      parsed = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    } catch {
      throw SharedCompassVMHeadlessPlanter.Error.attachOutputUnparseable(
        detail: "PropertyListSerialization: \(error.localizedDescription)"
      )
    }
    guard
      let root = parsed as? [String: Any],
      let systemEntities = root["system-entities"] as? [[String: Any]],
      !systemEntities.isEmpty
    else {
      throw SharedCompassVMHeadlessPlanter.Error.attachOutputUnparseable(
        detail: "missing or empty system-entities array"
      )
    }
    // Prefer the whole-disk container devnode (path matches /dev/diskN
    // with no trailing slice). The slice entries (e.g. /dev/disk5s1)
    // also appear but we want the parent for detach.
    let entries = systemEntities.compactMap { $0["dev-entry"] as? String }
    let wholeDisk = entries.first { entry in
      entry.range(of: #"^/dev/disk\d+$"#, options: .regularExpression) != nil
    }
    if let wholeDisk { return wholeDisk }
    if let first = entries.first { return first }
    throw SharedCompassVMHeadlessPlanter.Error.attachOutputUnparseable(
      detail: "no dev-entry strings in system-entities"
    )
  }

  /// Parses `hdiutil attach -plist` output and returns the
  /// `DeviceIdentifier` (no `/dev/` prefix) of the slice carrying the
  /// main APFS physical store — the one whose `content-hint` is
  /// `Apple_APFS` (we explicitly reject `Apple_APFS_ISC` and
  /// `Apple_APFS_Recovery`, which represent iBoot / Recovery physical
  /// stores rather than the bootable macOS volume group). This string
  /// matches against entries in `diskutil apfs list -plist`'s
  /// `Containers[].PhysicalStores[].DeviceIdentifier`.
  static func parseAPFSPhysicalStoreIdentifier(fromPlist plistString: String) throws -> String {
    guard let data = plistString.data(using: .utf8) else {
      throw SharedCompassVMHeadlessPlanter.Error.attachOutputUnparseable(detail: "non-UTF8 plist")
    }
    let parsed: Any
    do {
      parsed = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    } catch {
      throw SharedCompassVMHeadlessPlanter.Error.attachOutputUnparseable(
        detail: "PropertyListSerialization: \(error.localizedDescription)"
      )
    }
    guard
      let root = parsed as? [String: Any],
      let systemEntities = root["system-entities"] as? [[String: Any]]
    else {
      throw SharedCompassVMHeadlessPlanter.Error.attachOutputUnparseable(
        detail: "missing system-entities array"
      )
    }
    // `Apple_APFS` is exact-match (we reject `Apple_APFS_ISC` and
    // `Apple_APFS_Recovery`). The slice's dev-entry has the form
    // `/dev/diskNsM`; we strip the `/dev/` prefix to match diskutil's
    // identifier format.
    for entity in systemEntities {
      guard
        let hint = entity["content-hint"] as? String,
        hint == "Apple_APFS",
        let devEntry = entity["dev-entry"] as? String
      else { continue }
      if devEntry.hasPrefix("/dev/") {
        return String(devEntry.dropFirst("/dev/".count))
      }
      return devEntry
    }
    throw SharedCompassVMHeadlessPlanter.Error.attachOutputUnparseable(
      detail: "no Apple_APFS slice in system-entities (only _ISC / _Recovery present?)"
    )
  }
}

// MARK: - DataVolumeLocating

/// Wraps `diskutil apfs list -plist` and identifies the Data volume by
/// APFS role.
protocol DataVolumeLocating {
  /// Returns the devnode for the Data-role APFS volume inside the
  /// synthesized container whose physical store matches
  /// `physicalStoreIdentifier` (e.g. `disk4s2`). Resolves to a devnode
  /// like `/dev/disk9s5`.
  func locateDataVolume(matchingPhysicalStore physicalStoreIdentifier: String) async throws
    -> String
}

struct DiskUtilDataVolumeLocator: DataVolumeLocating {
  let diskutilPath: String

  init(diskutilPath: String = "/usr/sbin/diskutil") {
    self.diskutilPath = diskutilPath
  }

  func locateDataVolume(matchingPhysicalStore physicalStoreIdentifier: String) async throws
    -> String
  {
    // No-arg form lists every APFS container on the host. We then
    // filter for the one whose physical store is on our just-attached
    // disk image. Querying the synthesized container devnode directly
    // would work too, but we don't have it — `hdiutil attach` only
    // surfaces physical devnodes, and the synthesized container's
    // diskN number is allocated by the kernel after attach with no
    // direct way to ask "what synthesized container did you make for
    // my physical store?". The system-wide query + filter is the
    // shortest reliable path.
    let result = try await HeadlessPlanterProcessRunner.runCapture(
      executable: diskutilPath,
      arguments: ["apfs", "list", "-plist"]
    )
    return try Self.parseDataVolumeDeviceNode(
      fromPlist: result.standardOutput,
      matchingPhysicalStore: physicalStoreIdentifier
    )
  }

  /// Walks the `Containers[]` array and returns the devnode of the
  /// Data-role volume inside the container whose `PhysicalStores[]`
  /// references `physicalStoreIdentifier`. Apple's macOS installer
  /// always emits exactly one Data volume per container.
  static func parseDataVolumeDeviceNode(
    fromPlist plistString: String,
    matchingPhysicalStore physicalStoreIdentifier: String
  ) throws -> String {
    guard let data = plistString.data(using: .utf8) else {
      throw SharedCompassVMHeadlessPlanter.Error.dataVolumeNotFound(diagnostics: "non-UTF8 plist")
    }
    let parsed: Any
    do {
      parsed = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    } catch {
      throw SharedCompassVMHeadlessPlanter.Error.dataVolumeNotFound(
        diagnostics: "PropertyListSerialization: \(error.localizedDescription)"
      )
    }
    guard let root = parsed as? [String: Any] else {
      throw SharedCompassVMHeadlessPlanter.Error.dataVolumeNotFound(
        diagnostics: "root is not a dict")
    }
    let containers = root["Containers"] as? [[String: Any]] ?? []
    for container in containers {
      let stores = container["PhysicalStores"] as? [[String: Any]] ?? []
      let storeMatches = stores.contains { store in
        (store["DeviceIdentifier"] as? String) == physicalStoreIdentifier
      }
      guard storeMatches else { continue }
      let volumes = container["Volumes"] as? [[String: Any]] ?? []
      for volume in volumes {
        let roles = volume["Roles"] as? [String] ?? []
        if roles.contains("Data"), let deviceIdentifier = volume["DeviceIdentifier"] as? String {
          return "/dev/" + deviceIdentifier
        }
      }
      throw SharedCompassVMHeadlessPlanter.Error.dataVolumeNotFound(
        diagnostics:
          "container matching physical store \(physicalStoreIdentifier) has no Data-role volume"
      )
    }
    throw SharedCompassVMHeadlessPlanter.Error.dataVolumeNotFound(
      diagnostics:
        "no APFS container references physical store \(physicalStoreIdentifier) (checked \(containers.count) containers)"
    )
  }
}

// MARK: - AdminElevating

/// Wraps the one-time administrator-authentication prompt that runs the
/// elevated planter script.
protocol AdminElevating {
  /// Runs `/bin/bash <scriptURL>` once with administrator privileges and
  /// returns the captured stdout. Throws `userCancelledElevation` if the
  /// user dismisses the auth prompt.
  func runElevatedScript(at scriptURL: URL) async throws -> String
}

/// Production elevator. Invokes NSAppleScript with
/// `do shell script "..." with administrator privileges`. Implementation
/// hops to a detached task because NSAppleScript is synchronous, blocks the
/// calling thread on the auth prompt, and must not be invoked on
/// `@MainActor`.
struct OSAScriptAdminElevator: AdminElevating {
  func runElevatedScript(at scriptURL: URL) async throws -> String {
    try await Task.detached(priority: .userInitiated) {
      try Self.runSynchronously(scriptPath: scriptURL.path)
    }.value
  }

  private static func runSynchronously(scriptPath: String) throws -> String {
    // The AppleScript here invokes /bin/bash on the rendered planter
    // script. We single-quote the path so spaces or special characters
    // can't break out (the staging dir's UUID component is plain
    // alphanumerics + hyphens, but defence in depth costs nothing).
    let escapedPath = scriptPath.replacingOccurrences(of: "'", with: "'\\''")
    let source = """
      do shell script "/bin/bash '\(escapedPath)' 2>&1" with administrator privileges
      """
    guard let script = NSAppleScript(source: source) else {
      throw SharedCompassVMHeadlessPlanter.Error.elevationFailed(
        detail: "could not construct NSAppleScript")
    }
    var errorInfo: NSDictionary?
    let output = script.executeAndReturnError(&errorInfo)
    if let errorInfo {
      let code = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? 0
      if code == -128 {
        throw SharedCompassVMHeadlessPlanter.Error.userCancelledElevation
      }
      let message =
        (errorInfo[NSAppleScript.errorMessage] as? String) ?? "unknown AppleScript error"
      throw SharedCompassVMHeadlessPlanter.Error.elevationFailed(
        detail: "\(message) (code \(code))")
    }
    return output.stringValue ?? ""
  }
}

// MARK: - HeadlessPlanterProcessRunner shim

/// Small `Process` wrapper used by the host-side discovery steps. Lives in
/// the planter module rather than reaching for the existing
/// `Compass.ProcessRunner` because that type is shaped for the agent
/// runtime's streaming tool calls and offers behaviour Compass doesn't
/// need here. Disambiguated by name from `Compass.ProcessRunner`.
enum HeadlessPlanterProcessRunner {
  /// Local result type using the field names expected by call sites.
  struct CaptureResult {
    var exitCode: Int32
    var standardOutput: String
    var standardError: String

    var combinedOutput: String {
      let trimmedOut = standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
      let trimmedErr = standardError.trimmingCharacters(in: .whitespacesAndNewlines)
      switch (trimmedOut.isEmpty, trimmedErr.isEmpty) {
      case (true, true):
        return ""
      case (true, false):
        return trimmedErr
      case (false, true):
        return trimmedOut
      case (false, false):
        return trimmedOut + "\n" + trimmedErr
      }
    }
  }

  /// Delegates to `ProcessRunner.run`, mapping to the planter's own `Error`.
  static func runCapture(executable: String, arguments: [String]) async throws -> CaptureResult {
    guard FileManager.default.isExecutableFile(atPath: executable) else {
      throw SharedCompassVMHeadlessPlanter.Error.toolMissing(path: executable)
    }
    let result = try await ProcessRunner.run(executable: executable, arguments: arguments)
    guard result.exitCode == 0 else {
      let cap = CaptureResult(
        exitCode: result.exitCode, standardOutput: result.stdout, standardError: result.stderr)
      throw SharedCompassVMHeadlessPlanter.Error.toolFailed(
        tool: executable, exitCode: result.exitCode, output: cap.combinedOutput
      )
    }
    return CaptureResult(
      exitCode: result.exitCode,
      standardOutput: result.stdout,
      standardError: result.stderr
    )
  }
}
