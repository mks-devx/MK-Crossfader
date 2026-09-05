import CoreMIDI
import Foundation

struct MIDISourceDescriptor: Identifiable, Hashable {
    let id: MIDIUniqueID
    let endpoint: MIDIEndpointRef
    let name: String
}

struct MIDIControlChange: Sendable {
    let channel: UInt8
    let controller: UInt8
    let value: UInt8
}

protocol MIDIEngineProtocol: AnyObject {
    var onControlChange: ((MIDIControlChange) -> Void)? { get set }
    var onSetupChange: (() -> Void)? { get set }
    var hasOutputEndpoint: Bool { get }

    func availableSources() -> [MIDISourceDescriptor]
    @discardableResult
    func connect(to source: MIDISourceDescriptor?) -> Bool
    func sendControlChange(value: UInt8, channel: UInt8, controller: UInt8)
}

final class MIDIEngine: MIDIEngineProtocol {
    var onControlChange: ((MIDIControlChange) -> Void)?
    var onSetupChange: (() -> Void)?

    private(set) var virtualSource: MIDIEndpointRef = 0
    private var client: MIDIClientRef = 0
    private var inputPort: MIDIPortRef = 0
    private var connectedEndpoint: MIDIEndpointRef = 0
    private let parser = MIDIControlChangeParser()

    // A stable ID lets hosts retain their reference when the app relaunches.
    private static let virtualSourceUniqueID: MIDIUniqueID = 0x4D4B4358

    var hasOutputEndpoint: Bool {
        virtualSource != 0
    }

    init() {
        var newClient: MIDIClientRef = 0
        let clientStatus = MIDIClientCreateWithBlock(
            "MK MIDI Crossfader" as CFString,
            &newClient
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.onSetupChange?()
            }
        }
        guard clientStatus == noErr else {
            return
        }
        client = newClient

        var newInputPort: MIDIPortRef = 0
        let inputStatus = MIDIInputPortCreateWithBlock(
            client,
            "Controller Input" as CFString,
            &newInputPort
        ) { [weak self] packetList, _ in
            self?.handle(packetList: packetList)
        }
        guard inputStatus == noErr else {
            return
        }
        inputPort = newInputPort

        let sourceStatus = MIDISourceCreate(
            client,
            "MK Crossfader" as CFString,
            &virtualSource
        )
        if sourceStatus == noErr {
            _ = MIDIObjectSetIntegerProperty(
                virtualSource,
                kMIDIPropertyUniqueID,
                Self.virtualSourceUniqueID
            )
            _ = MIDIObjectSetStringProperty(
                virtualSource,
                kMIDIPropertyManufacturer,
                "MK Tools" as CFString
            )
            _ = MIDIObjectSetStringProperty(
                virtualSource,
                kMIDIPropertyModel,
                "MK MIDI Crossfader" as CFString
            )
        }
    }

    deinit {
        if connectedEndpoint != 0, inputPort != 0 {
            MIDIPortDisconnectSource(inputPort, connectedEndpoint)
        }
        if virtualSource != 0 {
            MIDIEndpointDispose(virtualSource)
        }
        if inputPort != 0 {
            MIDIPortDispose(inputPort)
        }
        if client != 0 {
            MIDIClientDispose(client)
        }
    }

    func availableSources() -> [MIDISourceDescriptor] {
        var sources: [MIDISourceDescriptor] = []

        for index in 0..<MIDIGetNumberOfSources() {
            let endpoint = MIDIGetSource(index)
            guard endpoint != 0, endpoint != virtualSource else {
                continue
            }

            var uniqueID: MIDIUniqueID = 0
            MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID)
            sources.append(
                MIDISourceDescriptor(
                    id: uniqueID,
                    endpoint: endpoint,
                    name: endpointName(endpoint)
                )
            )
        }

        return sources.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    @discardableResult
    func connect(to source: MIDISourceDescriptor?) -> Bool {
        if let source,
            source.endpoint == connectedEndpoint,
            inputPort != 0
        {
            return true
        }

        if connectedEndpoint != 0 {
            MIDIPortDisconnectSource(inputPort, connectedEndpoint)
            connectedEndpoint = 0
        }

        parser.reset()

        guard let source, inputPort != 0 else {
            return false
        }

        let status = MIDIPortConnectSource(inputPort, source.endpoint, nil)
        if status == noErr {
            connectedEndpoint = source.endpoint
            return true
        }
        return false
    }

    func sendControlChange(
        value: UInt8,
        channel: UInt8,
        controller: UInt8
    ) {
        guard virtualSource != 0 else {
            return
        }

        let bytes: [UInt8] = [
            UInt8(0xB0 | (channel & 0x0F)),
            min(controller, 127),
            min(value, 127),
        ]
        var packetList = MIDIPacketList()
        let packet = MIDIPacketListInit(&packetList)

        bytes.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return
            }
            _ = MIDIPacketListAdd(
                &packetList,
                MemoryLayout<MIDIPacketList>.size,
                packet,
                0,
                buffer.count,
                baseAddress
            )
        }
        MIDIReceived(virtualSource, &packetList)
    }

    private func endpointName(_ endpoint: MIDIEndpointRef) -> String {
        var unmanagedName: Unmanaged<CFString>?
        if MIDIObjectGetStringProperty(
            endpoint,
            kMIDIPropertyDisplayName,
            &unmanagedName
        ) == noErr,
            let name = unmanagedName?.takeRetainedValue()
        {
            return name as String
        }
        return "MIDI Source"
    }

    private func handle(packetList: UnsafePointer<MIDIPacketList>) {
        parser.handle(packetList: packetList) { [weak self] message in
            self?.onControlChange?(message)
        }
    }
}
