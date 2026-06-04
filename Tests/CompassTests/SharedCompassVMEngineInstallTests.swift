import Testing

@testable import Compass

struct SharedCompassVMEngineInstallTests {
  @Test func installCommandVerifiesPingAndWritesSentinel() throws {
    let command = SharedCompassVMEngineInstall.sshInstallCommand(
      temporaryGuestPath: "/tmp/compass-engine-test"
    )

    #expect(command.contains("/usr/local/bin/compass-engine"))
    #expect(command.contains("ping --repo \"$HOME\" --format json"))
    #expect(command.contains("/var/db/compass/engine-installed.version"))
  }
}
