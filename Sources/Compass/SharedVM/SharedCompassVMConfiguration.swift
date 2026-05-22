import Foundation
import Virtualization

/// Pure builder for `VZVirtualMachineConfiguration`.
///
/// Side-effect free: this type does not touch disk, talk to the network, or
/// create any VZ runtime objects. It just packages the data and asks
/// Virtualization.framework to compose a config from it. The resulting
/// configuration is returned without `validate()` being called — callers
/// are responsible for invoking validation on the main thread before
/// passing the config to `VZVirtualMachine.init`.
///
/// VZ-specific note: `VZVirtualMachineConfiguration` and the device
/// configuration objects are not annotated `Sendable`. Although this builder
/// produces them in a synchronous, single-thread context, callers must keep
/// the resulting config on the main thread.
struct SharedCompassVMConfiguration {
    /// Inputs that uniquely determine a configuration. All paths must already
    /// exist on disk for the resulting configuration to validate — the
    /// installer/provisioner is responsible for materialising them first.
    struct Inputs {
        var bundle: SharedCompassVMBundle
        var cpuCount: Int
        var memorySize: UInt64
        /// Optional MAC address (e.g. `52:8a:01:02:03:04`) to pin on the
        /// virtio network device so the guest's DHCP-assigned IP can be
        /// discovered host-side. Nil → VZ assigns a random MAC each boot.
        var guestMACAddress: String?

        /// Default config: 4 vCPUs, 8 GiB RAM, no VirtioFS shares —
        /// see the long note on `makeShareDevices` below for why.
        static func standard(
            bundle: SharedCompassVMBundle,
            cpuCount: Int = 4,
            memorySize: UInt64 = 8 * 1024 * 1024 * 1024,
            guestMACAddress: String? = nil
        ) -> Inputs {
            Inputs(
                bundle: bundle,
                cpuCount: cpuCount,
                memorySize: memorySize,
                guestMACAddress: guestMACAddress
            )
        }
    }

    enum BuildError: Error, CustomStringConvertible {
        case missingHardwareModel
        case malformedHardwareModel
        case missingMachineIdentifier
        case malformedMachineIdentifier
        case unsupportedHardwareModel
        case underlying(Error)

        var description: String {
            switch self {
            case .missingHardwareModel:
                return "HardwareModel artifact missing from VM bundle"
            case .malformedHardwareModel:
                return "HardwareModel artifact is malformed"
            case .missingMachineIdentifier:
                return "MachineIdentifier artifact missing from VM bundle"
            case .malformedMachineIdentifier:
                return "MachineIdentifier artifact is malformed"
            case .unsupportedHardwareModel:
                return "HardwareModel is not supported on this host"
            case .underlying(let error):
                return "VM configuration build failed: \(error)"
            }
        }
    }

    /// Builds a configuration suitable for booting a previously-installed bundle.
    /// Assumes Disk.img, AuxiliaryStorage, HardwareModel, and MachineIdentifier
    /// already exist in `inputs.bundle`. For pre-install configurations (used
    /// during `VZMacOSInstaller`), use `makeInstallationConfiguration` instead.
    static func makeConfiguration(
        for inputs: Inputs,
        fileManager: FileManager = .default
    ) throws -> VZVirtualMachineConfiguration {
        let configuration = VZVirtualMachineConfiguration()
        configuration.cpuCount = inputs.cpuCount
        configuration.memorySize = inputs.memorySize

        configuration.platform = try makePlatform(bundle: inputs.bundle, fileManager: fileManager)
        configuration.bootLoader = VZMacOSBootLoader()
        configuration.graphicsDevices = [makeGraphicsDevice()]
        configuration.storageDevices = [try makeStorageDevice(bundle: inputs.bundle)]
        configuration.networkDevices = [makeNetworkDevice(macAddress: inputs.guestMACAddress)]
        configuration.directorySharingDevices = []
        configuration.serialPorts = []
        configuration.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]
        configuration.memoryBalloonDevices = [VZVirtioTraditionalMemoryBalloonDeviceConfiguration()]
        configuration.socketDevices = [makeSocketDevice()]
        configuration.keyboards = [VZMacKeyboardConfiguration()]
        configuration.pointingDevices = [VZMacTrackpadConfiguration()]
        configuration.audioDevices = []
        configuration.consoleDevices = [makeConsoleDevice()]

        return configuration
    }

    /// Builds a configuration to hand to `VZMacOSInstaller`. The disk image
    /// and auxiliary storage URLs are expected to exist (pre-allocated and
    /// pre-created respectively); the hardware model and machine identifier
    /// come from the supplied `VZMacOSConfigurationRequirements`.
    static func makeInstallationConfiguration(
        for inputs: Inputs,
        requirements: VZMacOSConfigurationRequirements,
        fileManager: FileManager = .default
    ) throws -> VZVirtualMachineConfiguration {
        let configuration = VZVirtualMachineConfiguration()
        // Honor the restore image's minimums.
        configuration.cpuCount = max(inputs.cpuCount, requirements.minimumSupportedCPUCount)
        configuration.memorySize = max(inputs.memorySize, requirements.minimumSupportedMemorySize)

        let platform = VZMacPlatformConfiguration()
        let auxiliaryStorage = try VZMacAuxiliaryStorage(
            creatingStorageAt: inputs.bundle.auxiliaryStorageURL,
            hardwareModel: requirements.hardwareModel,
            options: [.allowOverwrite]
        )
        platform.auxiliaryStorage = auxiliaryStorage
        platform.hardwareModel = requirements.hardwareModel
        platform.machineIdentifier = VZMacMachineIdentifier()
        configuration.platform = platform

        configuration.bootLoader = VZMacOSBootLoader()
        configuration.graphicsDevices = [makeGraphicsDevice()]
        configuration.storageDevices = [try makeStorageDevice(bundle: inputs.bundle)]
        configuration.networkDevices = [makeNetworkDevice(macAddress: inputs.guestMACAddress)]
        configuration.directorySharingDevices = []
        configuration.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]
        configuration.memoryBalloonDevices = [VZVirtioTraditionalMemoryBalloonDeviceConfiguration()]
        configuration.socketDevices = [makeSocketDevice()]
        configuration.keyboards = [VZMacKeyboardConfiguration()]
        configuration.pointingDevices = [VZMacTrackpadConfiguration()]
        configuration.consoleDevices = [makeConsoleDevice()]

        // Persist hardware model + machine identifier so subsequent boots use them.
        try platform.hardwareModel.dataRepresentation.write(to: inputs.bundle.hardwareModelURL, options: .atomic)
        try platform.machineIdentifier.dataRepresentation.write(to: inputs.bundle.machineIdentifierURL, options: .atomic)

        return configuration
    }

    /// Re-exposes the file-share tag validator so callers can validate share
    /// tags without reaching into `SharedCompassVMFileShare` directly.
    static func validatedTag(_ tag: String) -> Result<String, SharedCompassVMFileShare.TagValidationError> {
        SharedCompassVMFileShare.validatedTag(tag)
    }

    /// Errors produced by `replaceConsoleAttachment`.
    enum ConsoleAttachmentError: Error, CustomStringConvertible {
        case noConsoleDevice
        case noConsolePorts

        var description: String {
            switch self {
            case .noConsoleDevice:
                return "Configuration has no virtio console device"
            case .noConsolePorts:
                return "Console device has no ports configured"
            }
        }
    }

    /// Replaces the first virtio console device's first port attachment in
    /// place. Used by the first-boot pipeline to swap the default `nil`
    /// attachment for a `VZFileHandleSerialPortAttachment` backed by a
    /// host-owned `Pipe()` so Compass can read the guest's IP-reporting
    /// output line by line.
    ///
    /// Per Apple's docs, `VZFileHandleSerialPortAttachment.fileHandleForReading`
    /// is what VZ reads from (data going *into* the guest) and
    /// `fileHandleForWriting` is what VZ writes guest output to. To capture
    /// guest output only, wire it like this:
    ///
    /// ```swift
    /// let pipe = Pipe()
    /// let attachment = VZFileHandleSerialPortAttachment(
    ///     fileHandleForReading: nil,
    ///     fileHandleForWriting: pipe.fileHandleForWriting
    /// )
    /// // Read guest output from pipe.fileHandleForReading.
    /// try SharedCompassVMConfiguration.replaceConsoleAttachment(attachment, on: configuration)
    /// ```
    ///
    /// The configuration retains the attachment reference, so callers must
    /// keep the `Pipe` alive for the lifetime of the running VM.
    static func replaceConsoleAttachment(
        _ attachment: VZSerialPortAttachment,
        on configuration: VZVirtualMachineConfiguration
    ) throws {
        guard let device = configuration.consoleDevices.first as? VZVirtioConsoleDeviceConfiguration else {
            throw ConsoleAttachmentError.noConsoleDevice
        }
        guard let port = device.ports[0] else {
            throw ConsoleAttachmentError.noConsolePorts
        }
        port.attachment = attachment
    }

    // MARK: - Component builders

    private static func makePlatform(
        bundle: SharedCompassVMBundle,
        fileManager: FileManager
    ) throws -> VZMacPlatformConfiguration {
        guard fileManager.fileExists(atPath: bundle.hardwareModelURL.path) else {
            throw BuildError.missingHardwareModel
        }
        guard fileManager.fileExists(atPath: bundle.machineIdentifierURL.path) else {
            throw BuildError.missingMachineIdentifier
        }

        let hardwareModelData = try Data(contentsOf: bundle.hardwareModelURL)
        guard let hardwareModel = VZMacHardwareModel(dataRepresentation: hardwareModelData) else {
            throw BuildError.malformedHardwareModel
        }
        if !hardwareModel.isSupported {
            throw BuildError.unsupportedHardwareModel
        }

        let machineIdentifierData = try Data(contentsOf: bundle.machineIdentifierURL)
        guard let machineIdentifier = VZMacMachineIdentifier(dataRepresentation: machineIdentifierData) else {
            throw BuildError.malformedMachineIdentifier
        }

        let auxiliaryStorage = VZMacAuxiliaryStorage(url: bundle.auxiliaryStorageURL)

        let platform = VZMacPlatformConfiguration()
        platform.hardwareModel = hardwareModel
        platform.machineIdentifier = machineIdentifier
        platform.auxiliaryStorage = auxiliaryStorage
        return platform
    }

    private static func makeGraphicsDevice() -> VZMacGraphicsDeviceConfiguration {
        let device = VZMacGraphicsDeviceConfiguration()
        device.displays = [
            VZMacGraphicsDisplayConfiguration(widthInPixels: 1920, heightInPixels: 1200, pixelsPerInch: 220)
        ]
        return device
    }

    private static func makeStorageDevice(bundle: SharedCompassVMBundle) throws -> VZVirtioBlockDeviceConfiguration {
        let attachment: VZDiskImageStorageDeviceAttachment
        do {
            attachment = try VZDiskImageStorageDeviceAttachment(
                url: bundle.diskImageURL,
                readOnly: false,
                cachingMode: .automatic,
                synchronizationMode: .full
            )
        } catch {
            throw BuildError.underlying(error)
        }
        return VZVirtioBlockDeviceConfiguration(attachment: attachment)
    }

    private static func makeNetworkDevice(macAddress: String? = nil) -> VZVirtioNetworkDeviceConfiguration {
        let network = VZVirtioNetworkDeviceConfiguration()
        network.attachment = VZNATNetworkDeviceAttachment()
        if let macAddress, let parsed = VZMACAddress(string: macAddress) {
            network.macAddress = parsed
        }
        return network
    }

    /// Virtio-vsock device. This is the transport the Compass guest agent
    /// uses to receive tool-call RPCs from the host without going through
    /// sshd. sshd-spawned processes on macOS guests are TCC-blocked from
    /// reading the VirtioFS-mounted worktree (confirmed via live testing
    /// against the running guest — see Phase R's commit), so the agent
    /// has to run inside the user GUI session via a LaunchAgent and the
    /// host has to reach it via a transport that doesn't involve sshd.
    /// vsock fits: it's a kernel-level socket that bypasses the network
    /// and TCC entirely. The host opens a connection via
    /// `VZVirtualMachine.socketDevices.first?.connect(toPort:)`.
    private static func makeSocketDevice() -> VZVirtioSocketDeviceConfiguration {
        VZVirtioSocketDeviceConfiguration()
    }

    /// Console device used by the guest's first-boot IP-reporting script.
    /// Pre-attached to a discardable null attachment; consumers that need to
    /// read the guest's stdout can re-attach a pipe at runtime.
    private static func makeConsoleDevice() -> VZVirtioConsoleDeviceConfiguration {
        let console = VZVirtioConsoleDeviceConfiguration()
        let port = VZVirtioConsolePortConfiguration()
        port.name = "compass.guest.report"
        port.attachment = nil
        console.ports[0] = port
        return console
    }

    // Note: directory sharing (VirtioFS) was removed in phase 10.
    // macOS guests TCC-block `AppleVirtIOFS` reads from every process —
    // including LaunchAgents inside the GUI session and even root via
    // LaunchDaemon. The in-guest Compass agent therefore can't read the
    // share regardless of which TCC profile we put it in. Repo contents
    // are copied into and out of the guest via vsock-streamed tar
    // through `SharedCompassVMWorktreeSync` instead. The
    // `SharedCompassVMFileShare` helpers stay in the tree to validate
    // share tags should we ever reattach a share for an unrelated
    // purpose, but no VirtioFS device is configured on the running VM.
}
