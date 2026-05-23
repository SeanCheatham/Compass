import CompassAgentRPC
import Darwin
import Foundation

// Compass guest-side helper. Runs as a LaunchAgent under the auto-logged-in
// `compass` user so it inherits the GUI session's TCC profile and can
// read/write the VirtioFS-mounted worktree (something sshd-spawned
// processes can't do).
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
