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
    private var runningStatus: UInt8?
    private var pendingData: [UInt8] = []
    private let parserLock = NSLock()

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

        parserLock.lock()
        runningStatus = nil
        pendingData.removeAll(keepingCapacity: true)
        parserLock.unlock()

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
        parserLock.lock()
        defer { parserLock.unlock() }

        var packet = packetList.pointee.packet

        for _ in 0..<packetList.pointee.numPackets {
            withUnsafeBytes(of: packet.data) { rawBuffer in
                let length = min(Int(packet.length), rawBuffer.count)
                process(bytes: rawBuffer.prefix(length))
            }
            packet = MIDIPacketNext(&packet).pointee
        }
    }

    private func process(bytes: Slice<UnsafeRawBufferPointer>) {
        for rawByte in bytes {
            let byte = UInt8(rawByte)

            if byte >= 0xF8 {
                continue
            }

            if byte & 0x80 != 0 {
                if byte < 0xF0 {
                    runningStatus = byte
                } else {
                    runningStatus = nil
                }
                pendingData.removeAll(keepingCapacity: true)
                continue
            }

            guard let status = runningStatus else {
                continue
            }

            pendingData.append(byte)
            let requiredLength = dataLength(for: status)
            guard requiredLength > 0, pendingData.count >= requiredLength else {
                continue
            }

            if status & 0xF0 == 0xB0 {
                onControlChange?(
                    MIDIControlChange(
                        channel: status & 0x0F,
                        controller: pendingData[0],
                        value: pendingData[1]
                    )
                )
            }

            pendingData.removeFirst(requiredLength)
        }
    }

    private func dataLength(for status: UInt8) -> Int {
        switch status & 0xF0 {
        case 0xC0, 0xD0:
            return 1
        case 0x80, 0x90, 0xA0, 0xB0, 0xE0:
            return 2
        default:
            return 0
        }
    }
}
