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
  }
}
