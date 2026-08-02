import CompassAgentRPC
import Darwin
import Foundation

// Compass guest-side helper. Runs as a LaunchDaemon with UserName=compass.
// Repo contents live in /Users/compass/Compass/Repos/<catalog-id>/worktree,
// synced from the host over git-over-SSH (exchange repo) or vsock tar.
// Commands that need the desktop session enter
// the auto-logged-in user's GUI bootstrap explicitly via launchctl asuser.
//
// Listens on AF_VSOCK at the canonical Compass port, accepts one request
// per connection, dispatches it, writes the response frame, closes the fd.
// Loop runs forever; the LaunchDaemon restarts the binary if it ever exits.

let port: UInt32 = 0x4007_ACE5
FileHandle.standardError.write(
  Data(
    "compass-guest-agent: starting, listening on vsock port \(String(format: "0x%08X", port))\n"
      .utf8))

let listener = VsockListener(port: port)
do {
  try listener.start()
} catch {
  FileHandle.standardError.write(Data("compass-guest-agent: listen failed: \(error)\n".utf8))
  exit(1)
}

do {
  try listener.acceptLoop { fd in
    // Handle each connection on a detached background queue so a slow
    // op doesn't block subsequent accepts. Order between concurrent
    // ops is not guaranteed, which matches the host agent loop's
    // expectations (it serialises its own calls).
    DispatchQueue.global().async {
      AgentServer.handleConnection(fileDescriptor: fd)
    }
  }
} catch {
  FileHandle.standardError.write(
    Data("compass-guest-agent: accept loop terminated: \(error)\n".utf8))
  exit(1)
}
