import CoreMIDI
import Foundation

let requestedName = CommandLine.arguments.dropFirst().first ?? "Faderfox UC4"
let timeoutSeconds = 30

func endpointName(_ endpoint: MIDIEndpointRef) -> String {
    var unmanagedName: Unmanaged<CFString>?
    guard MIDIObjectGetStringProperty(
        endpoint,
        kMIDIPropertyDisplayName,
        &unmanagedName
    ) == noErr,
        let name = unmanagedName?.takeRetainedValue()
    else {
        return ""
    }
    return name as String
}

func matchingSource() -> MIDIEndpointRef? {
    for index in 0..<MIDIGetNumberOfSources() {
        let endpoint = MIDIGetSource(index)
        if endpointName(endpoint).localizedCaseInsensitiveContains(requestedName) {
            return endpoint
        }
    }
    return nil
}

struct ControlKey: Hashable {
    let channel: UInt8
    let controller: UInt8
}

struct ControlRange {
    var minimum: UInt8
    var maximum: UInt8
    var count: Int

    var span: Int { Int(maximum) - Int(minimum) }
}

final class CaptureStore {
    private let lock = NSLock()
    private var controls: [ControlKey: ControlRange] = [:]
    private let completion: DispatchSemaphore

    init(completion: DispatchSemaphore) {
        self.completion = completion
    }

    func record(channel: UInt8, controller: UInt8, value: UInt8) {
        lock.lock()
        let key = ControlKey(channel: channel, controller: controller)
        var range = controls[key] ?? ControlRange(
            minimum: value,
            maximum: value,
            count: 0
        )
        range.minimum = min(range.minimum, value)
        range.maximum = max(range.maximum, value)
        range.count += 1
        controls[key] = range
        let completedSweep = range.span >= 120 && range.count >= 3
        lock.unlock()

        if completedSweep {
            completion.signal()
        }
    }

    func strongestControl() -> (key: ControlKey, range: ControlRange)? {
        lock.lock()
        defer { lock.unlock() }
        guard let strongest = controls.max(by: {
            if $0.value.span == $1.value.span {
                return $0.value.count < $1.value.count
            }
            return $0.value.span < $1.value.span
        }) else {
            return nil
        }
        return (strongest.key, strongest.value)
    }

    func allControls() -> [(key: ControlKey, range: ControlRange)] {
        lock.lock()
        defer { lock.unlock() }
        return controls
            .map { ($0.key, $0.value) }
            .sorted {
                if $0.key.channel == $1.key.channel {
                    return $0.key.controller < $1.key.controller
                }
                return $0.key.channel < $1.key.channel
            }
    }
}

guard let source = matchingSource() else {
    fputs("No MIDI source matching \(requestedName) was found.\n", stderr)
    exit(1)
}

let completion = DispatchSemaphore(value: 0)
let store = CaptureStore(completion: completion)
var client: MIDIClientRef = 0
var inputPort: MIDIPortRef = 0

guard MIDIClientCreate("MK CC Detector" as CFString, nil, nil, &client) == noErr else {
    fputs("Could not create the MIDI client.\n", stderr)
    exit(1)
}

MIDIInputPortCreateWithBlock(
    client,
    "Faderfox Input" as CFString,
    &inputPort
) { packetList, _ in
    var packet = packetList.pointee.packet
    for _ in 0..<packetList.pointee.numPackets {
        withUnsafeBytes(of: packet.data) { rawBuffer in
            let byteCount = min(Int(packet.length), rawBuffer.count)
            let bytes = Array(rawBuffer.prefix(byteCount))
            var runningStatus: UInt8?
            var data: [UInt8] = []

            for rawByte in bytes {
                let byte = UInt8(rawByte)
                if byte >= 0xF8 {
                    continue
                }
                if byte & 0x80 != 0 {
                    runningStatus = byte < 0xF0 ? byte : nil
                    data.removeAll(keepingCapacity: true)
                    continue
                }
                guard let status = runningStatus else {
                    continue
                }
                data.append(byte)
                let requiredLength = (status & 0xF0 == 0xC0 || status & 0xF0 == 0xD0)
                    ? 1
                    : 2
                if data.count >= requiredLength {
                    if status & 0xF0 == 0xB0, data.count >= 2 {
                        store.record(
                            channel: status & 0x0F,
                            controller: data[0],
                            value: data[1]
                        )
                    }
                    data.removeFirst(requiredLength)
                }
            }
        }
        packet = MIDIPacketNext(&packet).pointee
    }
}

guard MIDIPortConnectSource(inputPort, source, nil) == noErr else {
    fputs("Could not connect to \(requestedName).\n", stderr)
    exit(1)
}

_ = completion.wait(timeout: .now() + .seconds(timeoutSeconds))

guard let result = store.strongestControl() else {
    fputs("No MIDI CC movement was received.\n", stderr)
    exit(2)
}

for item in store.allControls() {
    print(
        "channel=\(Int(item.key.channel) + 1) "
            + "cc=\(item.key.controller) "
            + "minimum=\(item.range.minimum) "
            + "maximum=\(item.range.maximum) "
            + "events=\(item.range.count)"
    )
}

if result.range.span < 120 {
    fputs("No full-range CC sweep was detected.\n", stderr)
    exit(3)
}
