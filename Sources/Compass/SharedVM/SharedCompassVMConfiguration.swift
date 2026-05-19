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
        var shareTargets: [SharedCompassVMFileShare.ShareTarget]

        /// Default config: 4 vCPUs, 8 GiB RAM, the single permanent
        /// `compass-workspaces` share pointing at the supplied host root.
        static func standard(
            bundle: SharedCompassVMBundle,
            workspacesRootURL: URL,
            cpuCount: Int = 4,
            memorySize: UInt64 = 8 * 1024 * 1024 * 1024
        ) -> Inputs {
            Inputs(
                bundle: bundle,
                cpuCount: cpuCount,
                memorySize: memorySize,
                shareTargets: [
                    SharedCompassVMFileShare.ShareTarget(
                        tag: SharedCompassVMFileShare.defaultWorkspacesTag,
                        hostDirectoryURL: workspacesRootURL,
                        readOnly: false
                    )
                ]
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
        configuration.networkDevices = [makeNetworkDevice()]
        configuration.directorySharingDevices = try makeShareDevices(inputs.shareTargets)
        configuration.serialPorts = []
        configuration.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]
        configuration.memoryBalloonDevices = [VZVirtioTraditionalMemoryBalloonDeviceConfiguration()]
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
        configuration.networkDevices = [makeNetworkDevice()]
        configuration.directorySharingDevices = try makeShareDevices(inputs.shareTargets)
        configuration.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]
        configuration.memoryBalloonDevices = [VZVirtioTraditionalMemoryBalloonDeviceConfiguration()]
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

    private static func makeNetworkDevice() -> VZVirtioNetworkDeviceConfiguration {
        let network = VZVirtioNetworkDeviceConfiguration()
        network.attachment = VZNATNetworkDeviceAttachment()
        return network
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

    private static func makeShareDevices(
        _ targets: [SharedCompassVMFileShare.ShareTarget]
    ) throws -> [VZDirectorySharingDeviceConfiguration] {
        try targets.map { target in
            try SharedCompassVMFileShare.makeDeviceConfiguration(for: target)
        }
    }
}
