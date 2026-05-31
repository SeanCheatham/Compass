import Testing

@testable import Compass

struct SharedCompassVMGuestAgentInstallTests {
  @Test func remoteHelperInstallCommandRemovesExistingHelperBeforeWriting() throws {
    let command = SharedCompassVMGuestAgentInstall.remoteHelperInstallCommand(
      guestAgentBinaryPath: "/usr/local/libexec/compass-guest-agent",
      remoteHelperPath: "/usr/local/bin/git-remote-compass"
    )

    try #require(command.contains("--git-remote-helper"))
    try #require(!command.contains("ln -sf"))
    let removeRange = try #require(command.range(of: "rm -f /usr/local/bin/git-remote-compass"))
    let teeRange = try #require(command.range(of: "tee /usr/local/bin/git-remote-compass"))
    try #require(removeRange.lowerBound < teeRange.lowerBound)
  }

  @Test func sshRepairCommandReinstallsBinaryAndRestartsSystemLaunchDaemon() throws {
    let command = SharedCompassVMGuestAgentInstall.sshRepairCommand(
      temporaryGuestPath: "/tmp/CompassGuestAgent.repair",
      guestAgentBinaryPath: "/usr/local/libexec/compass-guest-agent",
      remoteHelperPath: "/usr/local/bin/git-remote-compass",
      launchDaemonGuestPath: "/Library/LaunchDaemons/com.seancheatham.Compass.guest-agent.plist",
      launchDaemonLabel: "com.seancheatham.Compass.guest-agent"
    )

    try #require(
      command.contains(
        "install -m 0755 -o root -g wheel /tmp/CompassGuestAgent.repair /usr/local/libexec/compass-guest-agent"
      ))
    try #require(command.contains("rm -f /usr/local/bin/git-remote-compass"))
    try #require(
      command.contains(
        "launchctl bootout system /Library/LaunchDaemons/com.seancheatham.Compass.guest-agent.plist"
      ))
    try #require(
      command.contains(
        "launchctl bootstrap system /Library/LaunchDaemons/com.seancheatham.Compass.guest-agent.plist"
      ))
    try #require(
      command.contains("launchctl kickstart -k system/com.seancheatham.Compass.guest-agent"))
  }
}
