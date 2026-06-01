import Foundation
import Testing

@testable import Compass

final class SharedCompassVMHeadlessPlanterTests {
  private var temporaryDirectories: [URL] = []

  func cleanup() {
    for url in temporaryDirectories {
      try? FileManager.default.removeItem(at: url)
    }
    temporaryDirectories.removeAll()
  }

  // MARK: - hdiutil attach plist parsing

  @Test
  func testParseContainerDevnodeFromAttachPlistPicksTheWholeDiskNode() throws {
    let plist = """
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTD/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
          <key>system-entities</key>
          <array>
              <dict>
                  <key>dev-entry</key>
                  <string>/dev/disk7</string>
                  <key>content-hint</key>
                  <string>GUID_partition_scheme</string>
              </dict>
              <dict>
                  <key>dev-entry</key>
                  <string>/dev/disk7s1</string>
                  <key>content-hint</key>
                  <string>Apple_APFS</string>
              </dict>
              <dict>
                  <key>dev-entry</key>
                  <string>/dev/disk7s2</string>
                  <key>content-hint</key>
                  <string>Apple_APFS_ISC</string>
              </dict>
          </array>
      </dict>
      </plist>
      """
    let devnode = try HDIUtilDiskAttacher.parseContainerDeviceNode(fromPlist: plist)
    try #require(devnode == "/dev/disk7")
  }

  @Test
  func testParseContainerDevnodeFallsBackToFirstEntryWhenNoWholeDiskMatch() throws {
    let plist = """
      <?xml version="1.0" encoding="UTF-8"?>
      <plist version="1.0">
      <dict>
          <key>system-entities</key>
          <array>
              <dict>
                  <key>dev-entry</key>
                  <string>/dev/disk9s1</string>
              </dict>
          </array>
      </dict>
      </plist>
      """
    let devnode = try HDIUtilDiskAttacher.parseContainerDeviceNode(fromPlist: plist)
    try #require(devnode == "/dev/disk9s1")
  }

  @Test
  func testParseContainerDevnodeRejectsEmptySystemEntities() throws {
    let plist = """
      <?xml version="1.0" encoding="UTF-8"?>
      <plist version="1.0">
      <dict>
          <key>system-entities</key>
          <array/>
      </dict>
      </plist>
      """
    var threw = false
    do { _ = try HDIUtilDiskAttacher.parseContainerDeviceNode(fromPlist: plist) } catch {
      threw = true
    }
    try #require(threw)
  }

  @Test
  func testParseContainerDevnodeRejectsNonPlistInput() throws {
    var threw = false
    do { _ = try HDIUtilDiskAttacher.parseContainerDeviceNode(fromPlist: "garbage") } catch {
      threw = true
    }
    try #require(threw)
  }

  // MARK: - hdiutil attach: APFS physical-store identifier

  @Test
  func testParseAPFSPhysicalStoreIdentifierPicksTheAppleAPFSSlice() throws {
    let plist = """
      <?xml version="1.0" encoding="UTF-8"?>
      <plist version="1.0">
      <dict>
          <key>system-entities</key>
          <array>
              <dict>
                  <key>dev-entry</key>
                  <string>/dev/disk4</string>
                  <key>content-hint</key>
                  <string>GUID_partition_scheme</string>
              </dict>
              <dict>
                  <key>dev-entry</key>
                  <string>/dev/disk4s1</string>
                  <key>content-hint</key>
                  <string>Apple_APFS_ISC</string>
              </dict>
              <dict>
                  <key>dev-entry</key>
                  <string>/dev/disk4s2</string>
                  <key>content-hint</key>
                  <string>Apple_APFS</string>
              </dict>
              <dict>
                  <key>dev-entry</key>
                  <string>/dev/disk4s3</string>
                  <key>content-hint</key>
                  <string>Apple_APFS_Recovery</string>
              </dict>
          </array>
      </dict>
      </plist>
      """
    let identifier = try HDIUtilDiskAttacher.parseAPFSPhysicalStoreIdentifier(fromPlist: plist)
    try #require(identifier == "disk4s2")
  }

  @Test
  func testParseAPFSPhysicalStoreIdentifierThrowsWhenNoBareAppleAPFSPresent() throws {
    let plist = """
      <?xml version="1.0" encoding="UTF-8"?>
      <plist version="1.0">
      <dict>
          <key>system-entities</key>
          <array>
              <dict>
                  <key>dev-entry</key>
                  <string>/dev/disk4s1</string>
                  <key>content-hint</key>
                  <string>Apple_APFS_ISC</string>
              </dict>
              <dict>
                  <key>dev-entry</key>
                  <string>/dev/disk4s3</string>
                  <key>content-hint</key>
                  <string>Apple_APFS_Recovery</string>
              </dict>
          </array>
      </dict>
      </plist>
      """
    var threw = false
    do {
      _ = try HDIUtilDiskAttacher.parseAPFSPhysicalStoreIdentifier(fromPlist: plist)
    } catch { threw = true }
    try #require(threw)
  }

  // MARK: - diskutil apfs list plist parsing

  @Test
  func testParseDataVolumeDevnodeReturnsDataRoleVolumeForMatchingPhysicalStore() throws {
    let plist = """
      <?xml version="1.0" encoding="UTF-8"?>
      <plist version="1.0">
      <dict>
          <key>Containers</key>
          <array>
              <dict>
                  <key>PhysicalStores</key>
                  <array>
                      <dict>
                          <key>DeviceIdentifier</key>
                          <string>disk0s2</string>
                      </dict>
                  </array>
                  <key>Volumes</key>
                  <array>
                      <dict>
                          <key>DeviceIdentifier</key>
                          <string>disk3s5</string>
                          <key>Roles</key>
                          <array>
                              <string>Data</string>
                          </array>
                      </dict>
                  </array>
              </dict>
              <dict>
                  <key>PhysicalStores</key>
                  <array>
                      <dict>
                          <key>DeviceIdentifier</key>
                          <string>disk4s2</string>
                      </dict>
                  </array>
                  <key>Volumes</key>
                  <array>
                      <dict>
                          <key>DeviceIdentifier</key>
                          <string>disk9s1</string>
                          <key>Roles</key>
                          <array>
                              <string>System</string>
                          </array>
                      </dict>
                      <dict>
                          <key>DeviceIdentifier</key>
                          <string>disk9s5</string>
                          <key>Roles</key>
                          <array>
                              <string>Data</string>
                          </array>
                      </dict>
                  </array>
              </dict>
          </array>
      </dict>
      </plist>
      """
    let devnode = try DiskUtilDataVolumeLocator.parseDataVolumeDeviceNode(
      fromPlist: plist,
      matchingPhysicalStore: "disk4s2"
    )
    try #require(devnode == "/dev/disk9s5")
  }

  @Test
  func testParseDataVolumeDevnodeThrowsWhenNoContainerMatchesPhysicalStore() throws {
    let plist = """
      <?xml version="1.0" encoding="UTF-8"?>
      <plist version="1.0">
      <dict>
          <key>Containers</key>
          <array>
              <dict>
                  <key>PhysicalStores</key>
                  <array>
                      <dict>
                          <key>DeviceIdentifier</key>
                          <string>disk0s2</string>
                      </dict>
                  </array>
                  <key>Volumes</key>
                  <array>
                      <dict>
                          <key>DeviceIdentifier</key>
                          <string>disk3s5</string>
                          <key>Roles</key>
                          <array>
                              <string>Data</string>
                          </array>
                      </dict>
                  </array>
              </dict>
          </array>
      </dict>
      </plist>
      """
    var threw = false
    do {
      _ = try DiskUtilDataVolumeLocator.parseDataVolumeDeviceNode(
        fromPlist: plist,
        matchingPhysicalStore: "disk4s2"
      )
    } catch { threw = true }
    try #require(threw)
  }

  @Test
  func testParseDataVolumeDevnodeThrowsWhenMatchingContainerHasNoDataVolume() throws {
    let plist = """
      <?xml version="1.0" encoding="UTF-8"?>
      <plist version="1.0">
      <dict>
          <key>Containers</key>
          <array>
              <dict>
                  <key>PhysicalStores</key>
                  <array>
                      <dict>
                          <key>DeviceIdentifier</key>
                          <string>disk4s2</string>
                      </dict>
                  </array>
                  <key>Volumes</key>
                  <array>
                      <dict>
                          <key>DeviceIdentifier</key>
                          <string>disk9s1</string>
                          <key>Roles</key>
                          <array>
                              <string>System</string>
                          </array>
                      </dict>
                  </array>
              </dict>
          </array>
      </dict>
      </plist>
      """
    var threw = false
    do {
      _ = try DiskUtilDataVolumeLocator.parseDataVolumeDeviceNode(
        fromPlist: plist,
        matchingPhysicalStore: "disk4s2"
      )
    } catch { threw = true }
    try #require(threw)
  }

  // MARK: - Elevated script rendering

  @Test
  func testElevatedScriptInstallsLaunchDaemonAsRootWheel0644() throws {
    let script = renderStandardScript()
    try #require(script.contains("install -o root -g wheel -m 0644"))
    try #require(
      script.contains("$MOUNT_POINT/Library/LaunchDaemons/com.seancheatham.Compass.firstboot.plist")
    )
  }

  @Test
  func testElevatedScriptInstallsBootstrapScriptAsRootWheel0755() throws {
    let script = renderStandardScript()
    try #require(script.contains("install -o root -g wheel -m 0755"))
    try #require(script.contains("$STAGING_DIR/bootstrap.sh"))
    try #require(script.contains("$MOUNT_POINT/usr/local/libexec/compass-firstboot.sh"))
  }

  @Test
  func testElevatedScriptInstallsSudoersAsRootWheel0440() throws {
    let script = renderStandardScript()
    try #require(script.contains("install -o root -g wheel -m 0440"))
    try #require(script.contains("$MOUNT_POINT/private/etc/sudoers.d/compass"))
  }

  @Test
  func testElevatedScriptInstallsAppleSetupDoneMarker() throws {
    let script = renderStandardScript()
    try #require(script.contains("$MOUNT_POINT/private/var/db/.AppleSetupDone"))
  }

  @Test
  func testElevatedScriptStagesPublicKeyAndPassword() throws {
    let script = renderStandardScript()
    try #require(script.contains("$MOUNT_POINT/Users/Shared/compass-firstboot/id_ed25519.pub"))
    try #require(script.contains("$MOUNT_POINT/Users/Shared/compass-firstboot/user.password"))
    try #require(script.contains("install -o root -g wheel -m 0600"))
  }

  @Test
  func testElevatedScriptInstallsAutoLoginHelper() throws {
    let script = renderStandardScript()
    try #require(script.contains("$MOUNT_POINT/usr/local/libexec/compass-autologin.sh"))
    try #require(
      script.contains(
        "$MOUNT_POINT/Library/LaunchDaemons/com.seancheatham.Compass.autologin.plist")
    )
  }

  @Test
  func testElevatedScriptUnmountsViaTrapOnExit() throws {
    let script = renderStandardScript()
    try #require(script.contains("trap cleanup EXIT"))
    try #require(script.contains("diskutil unmount \"$MOUNT_POINT\""))
  }

  @Test
  func testElevatedScriptUsesDiskutilMountWithExplicitMountPoint() throws {
    let script = renderStandardScript()
    try #require(
      script.contains("diskutil mount -mountPoint \"$MOUNT_POINT\" -nobrowse \"$DATA_DEV\""))
  }

  @Test
  func testElevatedScriptRetriesDiskutilMountThenFallsBackToMountApfs() throws {
    let script = renderStandardScript()
    try #require(
      script.contains("diskutil mount -mountPoint"),
      "elevated script should try diskutil mount first"
    )
    try #require(
      script.contains("mount_max_attempts"),
      "elevated script should bound the diskutil retry budget so failures surface"
    )
    try #require(
      script.contains("mount_apfs -o nobrowse"),
      "elevated script should fall back to mount_apfs when diskutil refuses"
    )
    try #require(
      script.contains("both diskutil mount and mount_apfs failed"),
      "elevated script should explicitly report when both strategies failed"
    )
  }

  // MARK: - Staging

  @Test
  func testStagePayloadWritesAllArtifactsByWellKnownName() throws {
    let stagingDir = makeTempDir()
    let payload = makePayload()
    try SharedCompassVMHeadlessPlanter.stagePayload(payload, into: stagingDir)

    let fm = FileManager.default
    try #require(fm.fileExists(atPath: stagingDir.appendingPathComponent("launchd.plist").path))
    try #require(fm.fileExists(atPath: stagingDir.appendingPathComponent("bootstrap.sh").path))
    try #require(fm.fileExists(atPath: stagingDir.appendingPathComponent("sudoers").path))
    try #require(fm.fileExists(atPath: stagingDir.appendingPathComponent("apple-setup-done").path))
    try #require(fm.fileExists(atPath: stagingDir.appendingPathComponent("id_ed25519.pub").path))
    try #require(fm.fileExists(atPath: stagingDir.appendingPathComponent("user.password").path))
    try #require(
      fm.fileExists(atPath: stagingDir.appendingPathComponent("compass-autologin.sh").path))
    try #require(
      fm.fileExists(
        atPath: stagingDir.appendingPathComponent("com.seancheatham.Compass.autologin.plist").path
      ))
  }

  @Test
  func testStagePayloadTightensPasswordFilePermissionsTo0600() throws {
    let stagingDir = makeTempDir()
    let payload = makePayload()
    try SharedCompassVMHeadlessPlanter.stagePayload(payload, into: stagingDir)
    let attrs = try FileManager.default.attributesOfItem(
      atPath: stagingDir.appendingPathComponent("user.password").path
    )
    let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue
    try #require(perms == 0o600)
  }

  @Test
  func testMakeStagingDirectoryReturnsFreshUUIDPath() throws {
    let first = try SharedCompassVMHeadlessPlanter.makeStagingDirectory()
    temporaryDirectories.append(first)
    let second = try SharedCompassVMHeadlessPlanter.makeStagingDirectory()
    temporaryDirectories.append(second)
    try #require(first != second)
    try #require(first.lastPathComponent.hasPrefix("Compass-HeadlessFirstBoot-"))
  }

  // MARK: - plant(...) integration with mocked deps

  @Test
  func testPlantOrchestrationStagesPayloadInvokesElevatorAndDetachesContainer() async throws {
    let attacher = FakeAttacher()
    attacher.deviceNode = "/dev/disk7"
    attacher.apfsPhysicalStore = "disk7s2"
    let locator = FakeLocator()
    locator.dataVolume = "/dev/disk9s5"
    let elevator = FakeElevator()
    elevator.output = "[compass-planter] done.\n"

    let dependencies = SharedCompassVMHeadlessPlanter.Dependencies(
      diskAttacher: attacher,
      dataVolumeLocator: locator,
      elevator: elevator
    )

    let diskImageURL = makeTempDir().appendingPathComponent("Disk.img", isDirectory: false)
    FileManager.default.createFile(atPath: diskImageURL.path, contents: Data())

    let payload = makePayload()
    let report = try await SharedCompassVMHeadlessPlanter.plant(
      payload: payload,
      diskImageURL: diskImageURL,
      dependencies: dependencies
    )

    try #require(attacher.attachedURLs == [diskImageURL])
    try #require(locator.queriedPhysicalStores == ["disk7s2"])
    try #require(elevator.invokedScriptURLs.count == 1)
    try #require(report.dataVolumeDeviceNode == "/dev/disk9s5")
    try #require(report.elevatedScriptOutput == "[compass-planter] done.\n")

    let writtenScript = elevator.invokedScriptContents.first ?? ""
    try #require(writtenScript.contains("/dev/disk9s5"))
    try #require(writtenScript.contains("$STAGING_DIR/launchd.plist"))
    try #require(writtenScript.contains("$STAGING_DIR/bootstrap.sh"))
    try #require(writtenScript.contains("$STAGING_DIR/sudoers"))
    try #require(writtenScript.contains("$STAGING_DIR/user.password"))
    try #require(writtenScript.contains("$STAGING_DIR/id_ed25519.pub"))

    try await Task.sleep(nanoseconds: 100_000_000)
    try #require(attacher.detachedDeviceNodes == ["/dev/disk7"])

    try #require(!FileManager.default.fileExists(atPath: report.stagingDirectoryURL.path))
  }

  @Test
  func testPlantCleansUpStagingDirectoryEvenWhenElevatedScriptThrows() async throws {
    let attacher = FakeAttacher()
    attacher.deviceNode = "/dev/disk9"
    let locator = FakeLocator()
    locator.dataVolume = "/dev/disk9s1s2"
    let elevator = FakeElevator()
    elevator.errorToThrow = SharedCompassVMHeadlessPlanter.Error.userCancelledElevation

    let dependencies = SharedCompassVMHeadlessPlanter.Dependencies(
      diskAttacher: attacher,
      dataVolumeLocator: locator,
      elevator: elevator
    )
    let diskImageURL = makeTempDir().appendingPathComponent("Disk.img", isDirectory: false)
    FileManager.default.createFile(atPath: diskImageURL.path, contents: Data())

    let payload = makePayload()
    var threwExpected = false
    do {
      _ = try await SharedCompassVMHeadlessPlanter.plant(
        payload: payload,
        diskImageURL: diskImageURL,
        dependencies: dependencies
      )
    } catch SharedCompassVMHeadlessPlanter.Error.userCancelledElevation {
      threwExpected = true
    } catch {
      #expect(Bool(false), "unexpected error \(error)")
    }
    try #require(threwExpected, "plant should rethrow elevator failures")

    let stagingDirectory = try #require(elevator.invokedScriptURLs.first?.deletingLastPathComponent())
    try #require(
      !FileManager.default.fileExists(atPath: stagingDirectory.path),
      "plant leaked staging directory: \(stagingDirectory)"
    )
  }

  // MARK: - Test doubles

  private final class FakeAttacher: HostDiskAttaching, @unchecked Sendable {
    var deviceNode: String = "/dev/disk0"
    var apfsPhysicalStore: String = "disk0s2"
    var attachedURLs: [URL] = []
    var detachedDeviceNodes: [String] = []

    func attachWithoutMount(diskImageURL: URL) async throws -> HostDiskAttachment {
      attachedURLs.append(diskImageURL)
      return HostDiskAttachment(
        wholeDiskDeviceNode: deviceNode,
        apfsPhysicalStoreIdentifier: apfsPhysicalStore,
        rawPlist: ""
      )
    }

    func detach(deviceNode: String) async throws {
      detachedDeviceNodes.append(deviceNode)
    }
  }

  private final class FakeLocator: DataVolumeLocating, @unchecked Sendable {
    var dataVolume: String = "/dev/disk0s1s2"
    var queriedPhysicalStores: [String] = []

    func locateDataVolume(matchingPhysicalStore physicalStoreIdentifier: String) async throws
      -> String
    {
      queriedPhysicalStores.append(physicalStoreIdentifier)
      return dataVolume
    }
  }

  private final class FakeElevator: AdminElevating, @unchecked Sendable {
    var output: String = ""
    var errorToThrow: Error?
    var invokedScriptURLs: [URL] = []
    var invokedScriptContents: [String] = []

    func runElevatedScript(at scriptURL: URL) async throws -> String {
      invokedScriptURLs.append(scriptURL)
      if let contents = try? String(contentsOf: scriptURL, encoding: .utf8) {
        invokedScriptContents.append(contents)
      }
      if let errorToThrow {
        throw errorToThrow
      }
      return output
    }
  }

  // MARK: - Helpers

  private func makeTempDir() -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("CompassHeadlessPlanterTest-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    temporaryDirectories.append(url)
    return url
  }

  private func makePayload() -> SharedCompassVMHeadlessFirstBoot.Payload {
    let profile = SharedCompassVMHeadlessFirstBoot.Profile.standard(macOSMajor: 16)
    let inputs = SharedCompassVMHeadlessFirstBoot.RenderInputs.makeStandard(
      profile: profile,
      publicKeyData: Data("ssh-ed25519 AAAA fake".utf8),
      generatedPassword: "passwordforsure",
      guestAgentBinary: Data("agent-binary-bytes-fake".utf8)
    )
    return SharedCompassVMHeadlessFirstBoot.renderPayload(from: inputs)
  }

  private func renderStandardScript() -> String {
    let payload = makePayload()
    return SharedCompassVMHeadlessPlanter.renderElevatedScript(
      payload: payload,
      stagingDirectoryHostPath: "/tmp/Compass-HeadlessFirstBoot-xyz",
      dataVolumeDeviceNode: "/dev/disk7s1s2"
    )
  }
}
