import Foundation
import Testing
import CrossfaderCore
@testable import MKMIDICrossfader

@MainActor
func drainXYZ() async {
    await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
}

@MainActor
func makeXYZ(axes: [InputAxis] = [.x, .y, .z]) throws -> (AppModel, RecordingMIDIEngine, MemorySettingsStore) {
    let store = makeTestSettings()
    var config = InputConfiguration()
    config.mode = .xyz
    config.x = MIDICCBinding(channel: 0, controller: 20)
    config.y = MIDICCBinding(channel: 0, controller: 21)
    config.z = MIDICCBinding(channel: 0, controller: 22)
    InputConfigurationStore.save(config, to: store)
    let targets = axes.enumerated().map { index, axis in
        CrossfadeTarget(name: axis.label, controller: 110 + index, side: .b, kind: .customMIDI, parameterCurve: .linear, restorePercent: 25, inputAxis: axis)
    }
    store.set(try JSONEncoder().encode(targets), forKey: "targets")
    let engine = RecordingMIDIEngine()
    return (AppModel(engine: engine, defaults: store), engine, store)
}

@Suite @MainActor struct XYZMIDIFlowTests {
    @Test func independentAxesAndReadiness() async throws {
        let (model, engine, _) = try makeXYZ()
        engine.emit(channel: 0, controller: 20, value: 0)
        engine.emit(channel: 0, controller: 21, value: 64)
        await drainXYZ()
        #expect(!model.canActivate)
        model.isEnabled = true
        #expect(!model.isEnabled)
        #expect(engine.sentMessages.isEmpty)
        engine.emit(channel: 0, controller: 22, value: 127)
        await drainXYZ()
        #expect(model.canActivate)
        model.isEnabled = true
        #expect(engine.sentMessages.map(\.value) == [0, 64, 127])
        engine.sentMessages.removeAll()
        engine.emit(channel: 0, controller: 21, value: 40)
        engine.emit(channel: 1, controller: 20, value: 100)
        engine.emit(channel: 0, controller: 30, value: 100)
        await drainXYZ()
        #expect(engine.sentMessages == [.init(value: 40, channel: 15, controller: 111)])
        #expect(!model.setInputBinding(MIDICCBinding(channel: 0, controller: 31), for: .x))
    }
    @Test func unusedAxesSingleAndReconnect() async throws {
        let (model, engine, _) = try makeXYZ(axes: [.y])
        #expect(model.setInputBinding(nil, for: .z))
        engine.emit(channel: 0, controller: 21, value: 50)
        await drainXYZ()
        #expect(model.canActivate)
        model.setInputMode(.single)
        #expect(!model.canActivate)
        #expect(model.targets[0].inputAxis == .y)
        engine.emit(channel: 0, controller: 20, value: 90)
        await drainXYZ()
        model.isEnabled = true
        #expect(engine.sentMessages.last?.value == 90)
        engine.exposesSource = false
        model.refreshSources()
        #expect(!model.isEnabled)
        engine.exposesSource = true
        model.refreshSources()
        #expect(!model.canActivate)
        #expect(!model.isEnabled)
    }
    @Test func confirmedLearningIsStableAndRejectsDuplicates() async throws {
        let (model, engine, _) = try makeXYZ()
        model.beginLearning(axis: .x)
        engine.emit(channel: 0, controller: 21, value: 40)
        engine.emit(channel: 0, controller: 24, value: 90)
        await drainXYZ()
        #expect(model.learningCandidate == MIDICCBinding(channel: 0, controller: 21))
        #expect(!model.confirmLearning())
        #expect(model.learnedController == 20)
        model.cancelLearning()
        model.beginLearning(axis: .x)
        engine.emit(channel: 2, controller: 24, value: 90)
        await drainXYZ()
        #expect(model.confirmLearning())
        #expect(model.learnedController == 24)
        #expect(model.learnedChannel == 2)
        #expect(!model.canActivate)
        model.beginLearning(axis: .y)
        engine.emit(channel: 0, controller: 30, value: 70)
        await drainXYZ()
        model.cancelLearning()
        #expect(model.inputConfiguration.y?.controller == 21)
    }
    @Test func presetLoadClearsFreshnessAndPreservesMachineBindings() async throws {
        let (model, engine, _) = try makeXYZ()
        model.saveScene(name: "XYZ")
        for cc in 20...22 { engine.emit(channel: 0, controller: UInt8(cc), value: 64) }
        await drainXYZ()
        #expect(model.canActivate)
        model.setInputMode(.single)
        model.loadScene(id: model.scenes[0].id)
        #expect(model.inputConfiguration.mode == .xyz)
        #expect(model.inputConfiguration.y?.controller == 21)
        #expect(!model.canActivate)
    }
    @Test func bindingChangeCancelsQueuedLearn() async throws {
        let (model, engine, _) = try makeXYZ()
        model.sendMappingMessage(to: model.targets[0].id)
        #expect(model.setInputBinding(MIDICCBinding(channel: 0, controller: 24), for: .x))
        let count = engine.sentMessages.count
        try await Task.sleep(for: .milliseconds(130))
        #expect(engine.sentMessages.count == count)
        #expect(engine.sentMessages.last?.value == 32)
    }
    @Test func singleLinearPairRetainsEveryValue() async {
        let engine = RecordingMIDIEngine()
        let model = AppModel(engine: engine, defaults: makeTestSettings())
        model.curve = .linear
        for i in 0...127 {
            engine.emit(channel: 13, controller: 48, value: UInt8(i))
            await drainXYZ()
            if !model.isEnabled { model.isEnabled = true }
            #expect(model.lastOutput.groupA == UInt8((Double(127-i) * 95 / 127).rounded()))
            #expect(model.lastOutput.groupB == UInt8((Double(i) * 95 / 127).rounded()))
        }
    }
    @Test func queuedInputCannotCrossConfigurationOrLearningBoundary() async throws {
        let (model, engine, _) = try makeXYZ(axes: [.x])
        engine.emit(channel: 0, controller: 20, value: 127)
        model.setInputMode(.single)
        await drainXYZ()
        #expect(!model.canActivate)
        #expect(model.inputState.value(for: .x) == nil)
        engine.emit(channel: 0, controller: 20, value: 64)
        model.beginLearning(axis: .y)
        await drainXYZ()
        #expect(model.learningCandidate == nil)
        engine.emit(channel: 0, controller: 25, value: 64)
        await drainXYZ()
        #expect(model.learningCandidate != nil)
        model.selectedSourceID = 2
        #expect(model.isConnected)
        #expect(!model.isLearning)
        #expect(model.learningCandidate == nil)
        #expect(!model.confirmLearning())
    }
    @Test func emptyXYZCannotActivate() throws {
        let (model, _, _) = try makeXYZ(axes: [])
        #expect(!model.canActivate)
    }
}
