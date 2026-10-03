import CoreMIDI
import Foundation
@testable import MKMIDICrossfader

final class RecordingMIDIEngine: MIDIEngineProtocol {
    struct Message: Equatable {
        let value: UInt8
        let channel: UInt8
        let controller: UInt8
    }

    var onControlChange: ((MIDIControlChange) -> Void)?
    var onSetupChange: (() -> Void)?
    var hasOutputEndpoint = true
    var exposesSource = true
    var sentMessages: [Message] = []

    private let source = MIDISourceDescriptor(
        id: 1,
        endpoint: MIDIEndpointRef(1),
        name: "Test Controller"
    )

    func availableSources() -> [MIDISourceDescriptor] {
        exposesSource ? [source, MIDISourceDescriptor(id: 2, endpoint: 2, name: "Second Controller")] : []
    }

    func connect(to source: MIDISourceDescriptor?) -> Bool {
        source != nil
    }

    func sendControlChange(
        value: UInt8,
        channel: UInt8,
        controller: UInt8
    ) {
        sentMessages.append(
            Message(value: value, channel: channel, controller: controller)
        )
    }

    func emit(channel: UInt8, controller: UInt8, value: UInt8) {
        onControlChange?(
            MIDIControlChange(
                channel: channel,
                controller: controller,
                value: value
            )
        )
    }
}

@MainActor
func makeTestSettings() -> MemorySettingsStore {
    let defaults = MemorySettingsStore()
    defaults.set(1, forKey: "selectedSourceID")
    defaults.set(13, forKey: "inputChannel")
    defaults.set(48, forKey: "inputController")
    return defaults
}
