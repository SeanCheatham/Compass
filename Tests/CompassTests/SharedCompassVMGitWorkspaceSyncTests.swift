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

  @Test func cloneOrUpdateCommandBracesBranchInFetchRefspecForZsh() throws {
    let command = SharedCompassVMGitWorkspaceSync.cloneOrUpdateCommand(
      quotedGuestPath: "/Users/compass/Compass/Repos/repo/worktree",
      quotedRemoteURL: "compass::00000000-0000-0000-0000-000000000000",
      quotedBranchName: "main"
    )

    try #require(
      command.contains(#""+refs/heads/${BRANCH}:refs/remotes/origin/${BRANCH}""#)
    )
    try #require(!command.contains("$BRANCH:refs"))
    try #require(command.contains(#""origin/${BRANCH}""#))
  }

  @Test func cloneOrUpdateCommandPreservesDirtyGuestWorktreeForRetry() throws {
    let command = SharedCompassVMGitWorkspaceSync.cloneOrUpdateCommand(
      quotedGuestPath: "/Users/compass/Compass/Repos/repo/worktree",
      quotedRemoteURL: "compass::00000000-0000-0000-0000-000000000000",
      quotedBranchName: "main"
    )

    let fetchRange = try #require(command.range(of: "git fetch origin"))
    let dirtyRange = try #require(command.range(of: "COMPASS_GIT_OUTCOME=dirty"))
    let checkoutRange = try #require(command.range(of: #"git checkout "$BRANCH""#))
    try #require(fetchRange.lowerBound < dirtyRange.lowerBound)
    try #require(dirtyRange.lowerBound < checkoutRange.lowerBound)
    try #require(!command.contains("guest worktree has uncommitted changes"))
    try #require(!command.contains("exit 3"))
  }
}
