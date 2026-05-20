import Foundation
@testable import Compass
import Virtualization
import XCTest

final class SharedCompassVMConfigurationTests: XCTestCase {
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
