import Foundation

struct SharedVMRoute: Equatable {
  var sshDestination: String
  var hostWorktreeURL: URL
  var guestWorkspacePath: String
  var environmentVariables: [String: String]
  var identityFile: String?
  var knownHostsFile: String?

  init(
    sshDestination: String,
    hostWorktreeURL: URL,
    guestWorkspacePath: String,
    environmentVariables: [String: String] = [:],
    identityFile: String? = nil,
    knownHostsFile: String? = nil
  ) {
    self.sshDestination = sshDestination
    self.hostWorktreeURL = hostWorktreeURL.standardizedFileURL
    self.guestWorkspacePath = guestWorkspacePath
    self.environmentVariables = environmentVariables
    self.identityFile = identityFile
    self.knownHostsFile = knownHostsFile
  }
}
