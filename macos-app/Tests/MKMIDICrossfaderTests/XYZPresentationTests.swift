import Testing
@testable import MKMIDICrossfader

@Suite @MainActor struct XYZPresentationTests {
    @Test func activeReleasedSessionCanAlwaysPause() async throws {
        let (model, engine, _) = try makeXYZ(axes: [.x])
        model.setTouchGate(MIDICCBinding(channel: 0, controller: 23))
        engine.emit(channel: 0, controller: 23, value: 127)
        engine.emit(channel: 0, controller: 20, value: 64)
        await drainXYZ()
        model.isEnabled = true
        engine.emit(channel: 0, controller: 23, value: 0)
        await drainXYZ()
        #expect(!model.canActivate)
        #expect(model.canToggleOutput)
        model.isEnabled = false
        #expect(!model.isEnabled)
        #expect(!model.canToggleOutput)
    }
    @Test func targetPresentationUsesEffectiveAxis() throws {
        let (model, _, _) = try makeXYZ(axes: [.z])
        #expect(model.effectiveAxis(for: model.targets[0]).minimumLabel == "Minimum")
        #expect(model.inputConfiguration.x?.description == "CC 20 · Ch 1")
        model.setInputMode(.single)
        #expect(model.effectiveAxis(for: model.targets[0]).minimumLabel == "Left")
        #expect(model.targets[0].inputAxis == .z)
    }
}
