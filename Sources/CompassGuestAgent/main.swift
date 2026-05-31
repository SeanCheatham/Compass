import CompassAgentRPC
import Darwin
import Foundation

if GitRemoteCompassHelper.shouldRun(arguments: CommandLine.arguments) {
  GitRemoteCompassHelper.run(arguments: CommandLine.arguments)
}

// Compass guest-side helper. Runs as a LaunchAgent under the auto-logged-in
// `compass` user inside the guest GUI session. Repo contents live in
// /Users/compass/Compass/Repos/<catalog-id>/worktree, normally as a real
// clone of the Compass exchange repo over vsock Git. sshd-spawned processes
// are TCC-blocked on macOS guests, so the agent must run in the user session
// and be reached via vsock.
//
// Listens on AF_VSOCK at the canonical Compass port, accepts one request
// per connection, dispatches it, writes the response frame, closes the fd.
// Loop runs forever; LaunchAgent restarts the binary if it ever exits.

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
