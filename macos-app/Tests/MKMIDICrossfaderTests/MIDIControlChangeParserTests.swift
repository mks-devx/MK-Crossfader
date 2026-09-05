import CoreMIDI
import Testing
@testable import MKMIDICrossfader

private func parse(
    _ packets: [[UInt8]],
    using parser: MIDIControlChangeParser = MIDIControlChangeParser()
) -> [MIDIControlChange] {
    let size = 4096 + packets.reduce(0) { $0 + $1.count + 32 }
    let raw = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16)
    defer { raw.deallocate() }
    raw.initializeMemory(as: UInt8.self, repeating: 0, count: size)
    let list = raw.bindMemory(to: MIDIPacketList.self, capacity: 1)
    var packet = MIDIPacketListInit(list)
    for (index, bytes) in packets.enumerated() {
        packet = bytes.withUnsafeBufferPointer {
            MIDIPacketListAdd(list, size, packet, MIDITimeStamp(index + 1), $0.count, $0.baseAddress!)
        }
    }
    var result: [MIDIControlChange] = []
    parser.handle(packetList: UnsafePointer(list)) { result.append($0) }
    return result
}

@Test("Variable-length packets retain all controller messages")
func longMIDIPackets() {
    let values = (0..<1000).map { UInt8($0 % 128) }
    let messages = parse([values.flatMap { [0xB3, 39, $0] }])
    #expect(messages.map(\.value) == values)
    #expect(messages.allSatisfy { $0.channel == 3 && $0.controller == 39 })
}

@Test("Timestamped packet batches use the original packet list")
func batchedMIDIPackets() {
    let values = (0..<1000).map { UInt8($0 % 128) }
    #expect(parse(values.map { [0xB0, 39, $0] }).map(\.value) == values)
}

@Test("Empty packet lists produce no messages")
func emptyMIDIPacketList() {
    #expect(parse([]).isEmpty)
}

@Test("Running status and partial CC messages survive packet and callback boundaries")
func runningStatusAcrossMIDIPackets() {
    let parser = MIDIControlChangeParser()
    #expect(parse([[0xB2, 40]], using: parser).isEmpty)
    let result = parse([[12, 40], [13, 41, 14]], using: parser)
    #expect(result.map(\.controller) == [40, 40, 41])
    #expect(result.map(\.value) == [12, 13, 14])
    #expect(result.allSatisfy { $0.channel == 2 })
}

@Test("Realtime MIDI does not interrupt a controller message")
func realtimeMIDIMessages() {
    let result = parse([[0xB0, 39, 0xF8, 1, 0xFA, 39, 0xFE, 2, 0xFC]])
    #expect(result.map(\.value) == [1, 2])
}

@Test("Other channel messages and SysEx do not produce controller values")
func nonControllerMIDIMessages() {
    let result = parse([[
        0x90, 60, 100, 61, 100, 0xC0, 1, 2, 0xD0, 3,
        0xE0, 0, 64, 0xB0, 39, 1,
        0xF0, 39, 127, 0xF8, 39, 127, 0xF7, 39, 127,
        0xB0, 39, 2, 0xF1, 3, 39, 127, 0xB0, 39, 3,
    ]])
    #expect(result.map(\.value) == [1, 2, 3])
}

@Test("Changing MIDI sources clears partial messages and running status")
func resetMIDIParser() {
    let parser = MIDIControlChangeParser()
    #expect(parse([[0xB0, 39]], using: parser).isEmpty)
    parser.reset()
    #expect(parse([[127, 39, 127]], using: parser).isEmpty)
    #expect(parse([[0xB1, 40, 42]], using: parser).map(\.value) == [42])
}
