import Testing

@testable import Compass

struct SharedCompassVMGitWorkspaceSyncTests {
  @Test func remoteHelperInstallCommandUsesWrapperInsteadOfSymlink() throws {
    let command = SharedCompassVMGitWorkspaceSync.remoteHelperInstallCommand(
      guestAgentBinaryPath: "/usr/local/libexec/compass-guest-agent"
    )

    try #require(command.contains("/usr/local/bin/git-remote-compass"))
    try #require(command.contains("--git-remote-helper"))
    try #require(command.contains("git-remote-compass --version"))
    try #require(!command.contains("ln -sf"))
    let removeRange = try #require(command.range(of: "rm -f /usr/local/bin/git-remote-compass"))
    let teeRange = try #require(command.range(of: "tee /usr/local/bin/git-remote-compass"))
    try #require(removeRange.lowerBound < teeRange.lowerBound)
  }
}
