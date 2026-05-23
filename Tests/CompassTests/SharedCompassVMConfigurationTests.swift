import Foundation
import Virtualization
import XCTest

@testable import Compass

final class SharedCompassVMConfigurationTests: XCTestCase {
  // MARK: - vsock

  func testGuestAgentPortIsStableAcrossBuilds() {
    // Both sides of the vsock conversation (host AgentVsockClient and
    // the in-guest CompassGuestAgent) reference this constant. Lock the
    // value so a refactor on either side can't silently rewire the port.
    XCTAssertEqual(SharedCompassVMVsock.guestAgentPort, 0x4007_ACE5)
  }

  // MARK: - Console

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

    XCTAssertTrue(consolePort.attachment === attachment)
  }
}
