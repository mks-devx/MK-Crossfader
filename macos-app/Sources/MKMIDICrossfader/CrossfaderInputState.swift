import Foundation

/// Runtime input values are deliberately never encoded in settings or presets.
enum TouchGateTransition { case began, ended, unchanged }

struct CrossfaderInputState {
    private var values: [InputAxis: UInt8] = [:]
    private(set) var freshAxes: Set<InputAxis> = []
    private(set) var gateState: Bool?
    private(set) var receivedSinceTouch: Set<InputAxis> = []
    mutating func reset() {
        values.removeAll(); freshAxes.removeAll()
        gateState = nil; receivedSinceTouch.removeAll()
    }
    mutating func receiveGate(_ value: UInt8) -> TouchGateTransition {
        let touched = value > 0
        guard gateState != touched else { return .unchanged }
        gateState = touched
        receivedSinceTouch.removeAll()
        return touched ? .began : .ended
    }
    func canEmit(requiredAxes: Set<InputAxis>, gateEnabled: Bool) -> Bool {
        isReady(requiredAxes: requiredAxes) && (!gateEnabled ||
            (gateState == true && requiredAxes.isSubset(of: receivedSinceTouch)))
    }
    mutating func receiveAxis(_ axis: InputAxis, value: UInt8) {
        guard value <= 127 else { return }
        values[axis] = value
        freshAxes.insert(axis)
        if gateState == true { receivedSinceTouch.insert(axis) }
    }
    func value(for axis: InputAxis) -> UInt8? { values[axis] }
    func isReady(requiredAxes: Set<InputAxis>) -> Bool {
        !requiredAxes.isEmpty && requiredAxes.isSubset(of: freshAxes)
    }
}

/// MIDI callbacks run off the main thread. Tag queued messages so a configuration
/// reset cannot accidentally use an earlier message as fresh input.
final class MIDIInputEpoch: @unchecked Sendable {
    private let lock = NSLock()
    private var value = UUID()
    var current: UUID { lock.withLock { value } }
    func invalidate() { lock.withLock { value = UUID() } }
}
