import CoreMIDI
import Foundation

final class MIDIControlChangeParser {
    private var runningStatus: UInt8?
    private var pendingData: [UInt8] = []
    private let lock = NSLock()

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        runningStatus = nil
        pendingData.removeAll(keepingCapacity: true)
    }

    func handle(
        packetList: UnsafePointer<MIDIPacketList>,
        onControlChange: (MIDIControlChange) -> Void
    ) {
        lock.lock()
        defer { lock.unlock() }

        // CoreMIDI packets are variable-length records, not copies of the
        // fixed-size data tuple exposed by Swift's imported MIDIPacket type.
        var packet = UnsafeRawPointer(packetList)
            .advanced(by: MemoryLayout<MIDIPacketList>.offset(of: \.packet)!)
            .assumingMemoryBound(to: MIDIPacket.self)
        let count = Int(packetList.pointee.numPackets)
        for index in 0..<count {
            let data = UnsafeRawPointer(packet)
                .advanced(by: MemoryLayout<MIDIPacket>.offset(of: \.data)!)
            let bytes = UnsafeRawBufferPointer(
                start: data,
                count: Int(packet.pointee.length)
            )
            process(bytes: bytes, onControlChange: onControlChange)
            if index + 1 < count {
                packet = UnsafePointer(MIDIPacketNext(packet))
            }
        }
    }

    private func process(
        bytes: UnsafeRawBufferPointer,
        onControlChange: (MIDIControlChange) -> Void
    ) {
        for byte in bytes {
            if byte >= 0xF8 { continue }
            if byte & 0x80 != 0 {
                runningStatus = byte < 0xF0 ? byte : nil
                pendingData.removeAll(keepingCapacity: true)
                continue
            }
            guard let status = runningStatus else { continue }
            pendingData.append(byte)
            let requiredLength = (status & 0xF0 == 0xC0 || status & 0xF0 == 0xD0) ? 1 : 2
            guard pendingData.count == requiredLength else { continue }
            if status & 0xF0 == 0xB0 {
                onControlChange(.init(
                    channel: status & 0x0F,
                    controller: pendingData[0],
                    value: pendingData[1]
                ))
            }
            pendingData.removeAll(keepingCapacity: true)
        }
    }
}
