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

    /// Maps a host filesystem URL into the guest's workspace path, if
    /// the URL lives under `hostWorktreeURL` (the host repo root for
    /// this route). Returns nil for URLs outside that subtree.
    func guestPath(forHostURL hostURL: URL) -> String? {
        let root = hostWorktreeURL.standardizedFileURL
        let target = hostURL.standardizedFileURL
        let rootPath = root.path
        let targetPath = target.path

        if targetPath == rootPath {
            return guestWorkspacePath
        }

        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard targetPath.hasPrefix(rootPrefix) else {
            return nil
        }

        let relativePath = String(targetPath.dropFirst(rootPrefix.count))
        guard !relativePath.isEmpty else { return guestWorkspacePath }
        let workspacePrefix = guestWorkspacePath.hasSuffix("/") ? guestWorkspacePath : guestWorkspacePath + "/"
        return "\(workspacePrefix)\(relativePath)"
    }
}
