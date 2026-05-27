import Foundation
import Virtualization
import Testing

@testable import Compass

struct SharedCompassVMConfigurationTests {

  // MARK: - vsock

  @Test
  func testGuestAgentPortIsStableAcrossBuilds()  throws {
    // Both sides of the vsock conversation (host AgentVsockClient and
    // the in-guest CompassGuestAgent) reference this constant. Lock the
    // value so a refactor on either side can't silently rewire the port.
    #require(SharedCompassVMVsock.guestAgentPort == 0x4007_ACE5)
  }

  // MARK: - Console

  @Test
  func testConsoleAttachmentAcceptsNilReadHandleForOutputOnlyCapture() throws {
    let configuration = VZVirtualMachineConfiguration()
    let consoleDevice = VZVirtioConsoleDeviceConfiguration()
    let consolePort = VZVirtioConsolePortConfiguration()
    consoleDevice.ports[0] = consolePort
    configuration.consoleDevices = [consoleDevice]

    let pipe = Pipe()
    let attachment = VZFileHandleSerialPortAttachment(
      fileHandleForReading: nil,
      fileHandleForWriting: pipe.fileHandleForWriting
    )

    try SharedCompassVMConfiguration.replaceConsoleAttachment(attachment, on: configuration)

    #require(consolePort.attachment === attachment)
  }
}
