import Foundation
import Testing
import CrossfaderCore
@testable import MKMIDICrossfader

@Suite @MainActor struct XYZTouchGateTests {
    @Test func releaseAndRetouchOrdering() async throws {
        let (model, engine, _) = try makeXYZ()
        #expect(model.setTouchGate(MIDICCBinding(channel: 0, controller: 23)))
        model.updateTargetReleasePolicy(id: model.targets[2].id, policy: .returnValue)
        for cc in 20...22 { engine.emit(channel: 0, controller: UInt8(cc), value: 64) }
        engine.emit(channel: 0, controller: 23, value: 0)
        await drainXYZ()
        #expect(!model.canActivate)
        engine.emit(channel: 0, controller: 23, value: 127)
        await drainXYZ()
        #expect(!model.canActivate)
        for cc in 20...22 { engine.emit(channel: 0, controller: UInt8(cc), value: 64) }
        await drainXYZ()
        #expect(model.canActivate)
        model.isEnabled = true
        engine.sentMessages.removeAll()
        engine.emit(channel: 0, controller: 23, value: 126)
        engine.emit(channel: 0, controller: 22, value: 0)
        await drainXYZ()
        #expect(model.canActivate)
        #expect(engine.sentMessages.map(\.value) == [0])
        engine.sentMessages.removeAll()
        engine.emit(channel: 0, controller: 23, value: 0)
        engine.emit(channel: 0, controller: 23, value: 0)
        for cc in 20...22 { engine.emit(channel: 0, controller: UInt8(cc), value: 127) }
        await drainXYZ()
        #expect(engine.sentMessages == [.init(value: 32, channel: 15, controller: 112)])
        model.curve = .smooth
        model.updateTargetSceneRight(id: model.targets[0].id, percent: 90)
        #expect(engine.sentMessages.count == 1)
        engine.sentMessages.removeAll()
        engine.emit(channel: 0, controller: 23, value: 127)
        engine.emit(channel: 0, controller: 20, value: 0)
        engine.emit(channel: 0, controller: 21, value: 0)
        await drainXYZ()
        #expect(engine.sentMessages.isEmpty)
        engine.emit(channel: 0, controller: 22, value: 127)
        await drainXYZ()
        #expect(engine.sentMessages.map(\.value) == [0, 0, 127])
    }
    @Test func missingGateAndDisableConfirmation() async throws {
        let (model, engine, _) = try makeXYZ(axes: [.z])
        #expect(!model.setTouchGate(MIDICCBinding(channel: 0, controller: 20)))
        #expect(model.setTouchGate(MIDICCBinding(channel: 0, controller: 23)))
        model.updateTargetReleasePolicy(id: model.targets[0].id, policy: .returnValue)
        #expect(!model.disableTouchGate(confirmPolicyReset: false))
        #expect(model.targets[0].releasePolicy == .returnValue)
        model.saveScene(name: "Return")
        #expect(model.disableTouchGate(confirmPolicyReset: true))
        #expect(model.targets[0].releasePolicy == .hold)
        model.loadScene(id: model.scenes[0].id)
        engine.emit(channel: 0, controller: 22, value: 64)
        await drainXYZ()
        #expect(!model.canActivate)
        #expect(model.statusDescription.contains("Touch Gate"))
        model.setInputMode(.single)
        engine.emit(channel: 0, controller: 20, value: 64)
        await drainXYZ()
        #expect(model.canActivate)
    }
    @Test func gateCancelsPendingLearnAndReleasedLearnRestores() async throws {
        let (model, engine, _) = try makeXYZ(axes: [.x])
        #expect(model.setTouchGate(MIDICCBinding(channel: 0, controller: 23)))
        engine.emit(channel: 0, controller: 23, value: 127)
        engine.emit(channel: 0, controller: 20, value: 64)
        await drainXYZ()
        model.isEnabled = true
        model.sendMappingMessage(to: model.targets[0].id)
        engine.emit(channel: 0, controller: 23, value: 0)
        await drainXYZ()
        let count = engine.sentMessages.count
        try await Task.sleep(for: .milliseconds(130))
        #expect(engine.sentMessages.count == count)
        model.sendMappingMessage(to: model.targets[0].id)
        try await Task.sleep(for: .milliseconds(130))
        #expect(engine.sentMessages.last?.value == 32)
    }
    @Test(arguments: [false, true])
    func completedLearnDoesNotSuppressIdenticalRetouch(whileWaitingForAxes: Bool) async throws {
        let (model, engine, _) = try makeXYZ(axes: [.x, .y])
        model.setTouchGate(MIDICCBinding(channel: 0, controller: 23))
        engine.emit(channel: 0, controller: 23, value: 127)
        for cc: UInt8 in [20, 21] { engine.emit(channel: 0, controller: cc, value: 64) }
        await drainXYZ()
        model.isEnabled = true
        engine.emit(channel: 0, controller: 23, value: 0)
        if whileWaitingForAxes {
            engine.emit(channel: 0, controller: 23, value: 127)
            engine.emit(channel: 0, controller: 20, value: 64)
        }
        await drainXYZ()
        model.sendMappingMessage(to: model.targets[0].id)
        try await Task.sleep(for: .milliseconds(150))
        #expect(engine.sentMessages.last?.value == 32)
        engine.sentMessages.removeAll()
        if !whileWaitingForAxes {
            engine.emit(channel: 0, controller: 23, value: 127)
            engine.emit(channel: 0, controller: 20, value: 64)
        }
        engine.emit(channel: 0, controller: 21, value: 64)
        await drainXYZ()
        #expect(engine.sentMessages == [.init(value: 64, channel: 15, controller: 110)])
    }
    @Test func outputChannelChangeWhileReleasedWaitsForRetouch() async throws {
        let (model, engine, _) = try makeXYZ(axes: [.x])
        model.setTouchGate(MIDICCBinding(channel: 0, controller: 23))
        engine.emit(channel: 0, controller: 23, value: 127)
        engine.emit(channel: 0, controller: 20, value: 64)
        await drainXYZ()
        model.isEnabled = true
        engine.emit(channel: 0, controller: 23, value: 0)
        await drainXYZ()
        engine.sentMessages.removeAll()
        model.outputChannel = 4
        #expect(engine.sentMessages == [.init(value: 32, channel: 15, controller: 110)])
        engine.sentMessages.removeAll()
        engine.emit(channel: 0, controller: 23, value: 127)
        engine.emit(channel: 0, controller: 20, value: 64)
        await drainXYZ()
        #expect(engine.sentMessages == [.init(value: 64, channel: 4, controller: 110)])
    }
    @Test func gateLearningAndReset() async throws {
        let (model, engine, _) = try makeXYZ()
        model.beginGateLearning()
        engine.emit(channel: 3, controller: 25, value: 127)
        await drainXYZ()
        #expect(model.confirmLearning())
        #expect(model.inputConfiguration.touchGate == MIDICCBinding(channel: 3, controller: 25))
        model.resetInputConfiguration()
        #expect(model.inputConfiguration == InputConfiguration())
        #expect(!model.canActivate)
    }
}
