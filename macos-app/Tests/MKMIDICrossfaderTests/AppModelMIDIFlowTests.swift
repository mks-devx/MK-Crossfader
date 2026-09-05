import CoreMIDI
import Foundation
import ServiceManagement
import Testing
@testable import MKMIDICrossfader

private final class RecordingMIDIEngine: MIDIEngineProtocol {
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
        exposesSource ? [source] : []
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
private final class FakeLaunchAtLoginService: LaunchAtLoginServicing {
    var status: SMAppService.Status = .notRegistered
    var registerCallCount = 0
    var unregisterCallCount = 0

    func register() throws {
        registerCallCount += 1
        status = .enabled
    }

    func unregister() throws {
        unregisterCallCount += 1
        status = .notRegistered
    }
}

@MainActor
private func makeDefaults() -> UserDefaults {
    let name = "MKMIDICrossfaderTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    defaults.set(1, forKey: "selectedSourceID")
    defaults.set(13, forKey: "inputChannel")
    defaults.set(48, forKey: "inputController")
    return defaults
}

@MainActor
private func drainMainQueue() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async {
            continuation.resume()
        }
    }
}

@Test("A missing controller selection falls back to the first available source")
@MainActor
func missingControllerSelectionUsesFirstSource() {
    let defaults = makeDefaults()
    defaults.set(999, forKey: "selectedSourceID")

    let model = AppModel(
        engine: RecordingMIDIEngine(),
        defaults: defaults
    )

    #expect(model.selectedSourceID == 1)
    #expect(model.selectedSourceName == "Test Controller")
    #expect(model.isConnected)
}

@Test("Activation waits for the physical fader position")
@MainActor
func activationWaitsForInput() async {
    let engine = RecordingMIDIEngine()
    let model = AppModel(engine: engine, defaults: makeDefaults())

    #expect(model.isConnected)
    #expect(!model.hasReceivedInput)
    #expect(!model.canActivate)
    #expect(model.statusDescription == "Move crossfader once")

    model.isEnabled = true
    #expect(!model.isEnabled)
    #expect(engine.sentMessages.isEmpty)

    engine.emit(channel: 13, controller: 48, value: 0)
    await drainMainQueue()

    #expect(model.hasReceivedInput)
    #expect(model.canActivate)
    model.isEnabled = true
    #expect(model.isEnabled)
    #expect(engine.sentMessages.count == 2)
    #expect(engine.sentMessages[0].value == 95)
    #expect(engine.sentMessages[1].value == 0)
}

@Test("Dock icon is visible by default and the preference is respected")
@MainActor
func dockIconPreference() {
    let defaults = makeDefaults()

    #expect(AppActivationPolicy.shouldShowDockIcon(defaults: defaults))
    #expect(AppActivationPolicy.policy(showDockIcon: true) == .regular)

    defaults.set(false, forKey: AppActivationPolicy.showDockIconDefaultsKey)
    #expect(!AppActivationPolicy.shouldShowDockIcon(defaults: defaults))
    #expect(AppActivationPolicy.policy(showDockIcon: false) == .accessory)
}

@Test("Menu-bar artwork is a correctly sized template image")
@MainActor
func menuBarArtwork() {
    let icon = BrandAssets.menuBarIcon

    #expect(icon.isTemplate)
    #expect(icon.size.width == 20)
    #expect(icon.size.height == 13)
    #expect(icon.accessibilityDescription == "MK Crossfader")
}

@Test("Launch at Login follows the macOS service status")
@MainActor
func launchAtLoginStatus() {
    let service = FakeLaunchAtLoginService()
    let controller = LaunchAtLoginController(service: service)

    #expect(!controller.isEnabled)
    #expect(controller.statusMessage == nil)

    controller.setEnabled(true)
    #expect(controller.isEnabled)
    #expect(service.registerCallCount == 1)

    controller.setEnabled(false)
    #expect(!controller.isEnabled)
    #expect(service.unregisterCallCount == 1)

    service.status = .requiresApproval
    controller.refresh()
    #expect(!controller.isEnabled)
    #expect(controller.isAvailable)
    #expect(controller.requiresApproval)
    #expect(controller.statusMessage?.contains("approval") == true)

    service.status = .notFound
    controller.refresh()
    #expect(!controller.isAvailable)
    #expect(!controller.requiresApproval)
}

@Test("Range output follows the fader and pause sends the Return Value")
@MainActor
func rangeOutputAndReturnValue() async throws {
    let engine = RecordingMIDIEngine()
    let defaults = makeDefaults()
    let target = CrossfadeTarget(
        name: "Filter",
        controller: 112,
        side: .b,
        kind: .customMIDI,
        transition: .range,
        customLeftPercent: 0,
        customRightPercent: 80,
        parameterCurve: .linear,
        restorePercent: 25
    )
    defaults.set(
        try JSONEncoder().encode([target]),
        forKey: "targets"
    )
    let model = AppModel(engine: engine, defaults: defaults)

    engine.emit(channel: 13, controller: 48, value: 127)
    await drainMainQueue()
    model.isEnabled = true

    #expect(engine.sentMessages.last?.controller == 112)
    #expect(engine.sentMessages.last?.value == 102)

    model.updateTargetRestore(id: target.id, percent: 90)
    model.isEnabled = false

    #expect(engine.sentMessages.last?.controller == 112)
    #expect(engine.sentMessages.last?.value == 32)
}

@Test("Parameter Return Value uses the full MIDI range")
func parameterReturnValueUsesFullMIDIRange() {
    var target = CrossfadeTarget(
        name: "Filter",
        controller: 112,
        side: .b,
        kind: .customMIDI,
        transition: .range,
        restorePercent: 25
    )

    #expect(target.restoreOutput == 32)
    target.restorePercent = 100
    #expect(target.restoreOutput == 127)
}

@Test("Removing a target sends its Return Value")
@MainActor
func removingTargetSendsReturnValue() throws {
    let engine = RecordingMIDIEngine()
    let defaults = makeDefaults()
    let target = CrossfadeTarget(
        name: "Filter",
        controller: 112,
        side: .b,
        kind: .customMIDI,
        transition: .range,
        restorePercent: 25
    )
    defaults.set(try JSONEncoder().encode([target]), forKey: "targets")
    let model = AppModel(engine: engine, defaults: defaults)

    model.removeTarget(id: target.id)

    #expect(engine.sentMessages == [
        .init(value: 32, channel: 15, controller: 112)
    ])
    #expect(model.targets.isEmpty)
}

@Test("Changing a target CC returns the old mapping")
@MainActor
func changingTargetCCReturnsOldMapping() throws {
    let engine = RecordingMIDIEngine()
    let defaults = makeDefaults()
    let target = CrossfadeTarget(
        name: "Filter",
        controller: 112,
        side: .b,
        kind: .customMIDI,
        transition: .range,
        restorePercent: 25
    )
    defaults.set(try JSONEncoder().encode([target]), forKey: "targets")
    let model = AppModel(engine: engine, defaults: defaults)

    model.updateTargetController(id: target.id, controller: 113)

    #expect(engine.sentMessages == [
        .init(value: 32, channel: 15, controller: 112)
    ])
    #expect(model.targets.first?.controller == 113)
}

@Test("Changing target type returns using the old target range")
@MainActor
func changingTargetTypeUsesOldRange() throws {
    let engine = RecordingMIDIEngine()
    let defaults = makeDefaults()
    let target = CrossfadeTarget(
        name: "Group",
        controller: 112,
        side: .a,
        kind: .maschineLevel,
        restorePercent: 100
    )
    defaults.set(try JSONEncoder().encode([target]), forKey: "targets")
    let model = AppModel(engine: engine, defaults: defaults)

    model.updateTargetKind(id: target.id, kind: .customMIDI)

    #expect(engine.sentMessages == [
        .init(value: 95, channel: 15, controller: 112)
    ])
    #expect(model.targets.first?.kind == .customMIDI)
}

@Test("Changing output channel returns targets on the old channel")
@MainActor
func changingOutputChannelReturnsOldChannel() throws {
    let engine = RecordingMIDIEngine()
    let defaults = makeDefaults()
    let target = CrossfadeTarget(
        name: "Filter",
        controller: 112,
        side: .b,
        kind: .customMIDI,
        transition: .range,
        restorePercent: 25
    )
    defaults.set(try JSONEncoder().encode([target]), forKey: "targets")
    let model = AppModel(engine: engine, defaults: defaults)

    model.outputChannel = 4

    #expect(engine.sentMessages == [
        .init(value: 32, channel: 15, controller: 112)
    ])
}

@Test("Normal termination returns active targets exactly once")
@MainActor
func terminationReturnsActiveTargetsOnce() async throws {
    let engine = RecordingMIDIEngine()
    let defaults = makeDefaults()
    let target = CrossfadeTarget(
        name: "Filter",
        controller: 112,
        side: .b,
        kind: .customMIDI,
        transition: .range,
        restorePercent: 25
    )
    defaults.set(try JSONEncoder().encode([target]), forKey: "targets")
    let model = AppModel(engine: engine, defaults: defaults)
    engine.emit(channel: 13, controller: 48, value: 64)
    await drainMainQueue()
    model.isEnabled = true
    engine.sentMessages.removeAll()

    model.prepareForTermination()
    model.prepareForTermination()

    #expect(engine.sentMessages == [
        .init(value: 32, channel: 15, controller: 112)
    ])
}

@Test("Controller disconnect returns active targets")
@MainActor
func controllerDisconnectReturnsActiveTargets() async throws {
    let engine = RecordingMIDIEngine()
    let defaults = makeDefaults()
    let target = CrossfadeTarget(
        name: "Filter",
        controller: 112,
        side: .b,
        kind: .customMIDI,
        transition: .range,
        restorePercent: 25
    )
    defaults.set(try JSONEncoder().encode([target]), forKey: "targets")
    let model = AppModel(engine: engine, defaults: defaults)
    engine.emit(channel: 13, controller: 48, value: 64)
    await drainMainQueue()
    model.isEnabled = true
    engine.sentMessages.removeAll()

    engine.exposesSource = false
    model.refreshSources()

    #expect(!model.isEnabled)
    #expect(engine.sentMessages == [
        .init(value: 32, channel: 15, controller: 112)
    ])
}

@Test("Loading a saved preset while paused sends no MIDI")
@MainActor
func pausedPresetLoadingIsSilent() throws {
    let engine = RecordingMIDIEngine()
    let defaults = makeDefaults()
    let preset = CrossfaderScenePreset(
        name: "Saved",
        targets: [
            CrossfadeTarget(name: "Saved A", controller: 110, side: .a)
        ],
        mode: .standard,
        curve: .smooth,
        minimumLevel: .kill,
        isReversed: false,
        isTravelReversed: false
    )
    defaults.set(
        try JSONEncoder().encode([preset]),
        forKey: "scenesV1"
    )
    let model = AppModel(engine: engine, defaults: defaults)

    model.loadScene(id: preset.id)
    #expect(engine.sentMessages.isEmpty)
    #expect(model.targets.map(\.name) == ["Saved A"])
}

@Test("Quick-add workflows preserve targets and allocate unused CCs")
@MainActor
func quickAddWorkflowsAreAdditive() throws {
    let engine = RecordingMIDIEngine()
    let defaults = makeDefaults()
    let existing = CrossfadeTarget(
        name: "Filter",
        controller: 112,
        side: .b,
        kind: .customMIDI,
        transition: .range,
        customLeftPercent: 15,
        customRightPercent: 72
    )
    defaults.set(try JSONEncoder().encode([existing]), forKey: "targets")
    let model = AppModel(engine: engine, defaults: defaults)

    model.addCrossfadePair()
    model.addParameterTarget()

    #expect(model.targets.count == 4)
    #expect(model.targets[0] == existing)
    #expect(model.targets.map(\.controller) == [112, 110, 111, 113])
    #expect(model.targets.map(\.behavior) == [.range, .sideA, .sideB, .range])
    #expect(model.targets[3].kind == .customMIDI)
    #expect(model.targets[3].customLeftPercent == 0)
    #expect(model.targets[3].customRightPercent == 100)
    #expect(engine.sentMessages.isEmpty)
}

@Test("Built-in presets preserve saved snapshots and routing, and persist silently",
      arguments: BuiltInCrossfadePreset.allCases)
@MainActor
func builtInPresetPersistence(preset: BuiltInCrossfadePreset) {
    let engine = RecordingMIDIEngine()
    let defaults = makeDefaults()
    let model = AppModel(engine: engine, defaults: defaults)
    model.addParameterTarget()
    model.mode = .pairFade
    model.curve = .fastCut
    model.minimumLevel = .minus18DB
    model.isReversed = true
    model.isTravelReversed = true
    model.outputChannel = 4
    let original = model.targets
    model.saveScene(name: "Before applying")
    let saved = model.scenes
    engine.sentMessages.removeAll()

    model.applyBuiltInPreset(preset)

    #expect(model.targets == preset.applying(to: original))
    #expect(model.scenes == saved)
    #expect(model.mode == .standard)
    #expect(model.curve == preset.curve)
    #expect(model.minimumLevel == .kill)
    #expect(!model.isReversed && !model.isTravelReversed && !model.isEnabled)
    #expect(model.outputChannel == 4)
    #expect(model.selectedSourceID == 1)
    #expect(model.learnedChannel == 13 && model.learnedController == 48)
    #expect(engine.sentMessages.isEmpty)

    let reloaded = AppModel(engine: RecordingMIDIEngine(), defaults: defaults)
    #expect(reloaded.targets == model.targets)
    #expect(reloaded.curve == preset.curve)
    #expect(reloaded.mode == .standard && reloaded.minimumLevel == .kill)
    #expect(!reloaded.isReversed && !reloaded.isTravelReversed)
    #expect(reloaded.scenes == saved)

    model.loadScene(id: saved[0].id)
    #expect(model.targets == original)
    #expect(model.mode == .pairFade && model.curve == .fastCut)
    #expect(model.minimumLevel == .minus18DB)
    #expect(model.isReversed && model.isTravelReversed)
}

@Test("Built-in presets cannot change an active setup",
      arguments: BuiltInCrossfadePreset.allCases)
@MainActor
func builtInPresetActiveGuard(preset: BuiltInCrossfadePreset) async {
    let engine = RecordingMIDIEngine()
    let model = AppModel(engine: engine, defaults: makeDefaults())
    model.mode = .pairFade
    model.curve = .fastCut
    let original = model.targets
    engine.emit(channel: 13, controller: 48, value: 64)
    await drainMainQueue()
    model.isEnabled = true
    engine.sentMessages.removeAll()

    #expect(!model.canApplyBuiltInPreset)
    model.applyBuiltInPreset(preset)

    #expect(model.targets == original)
    #expect(model.mode == .pairFade && model.curve == .fastCut)
    #expect(model.isEnabled)
    #expect(engine.sentMessages.isEmpty)
}

@Test("Built-in presets reject empty or all-Off setups without consuming saved slots")
@MainActor
func builtInPresetAvailability() {
    let model = AppModel(engine: RecordingMIDIEngine(), defaults: makeDefaults())
    for index in 0..<16 { model.saveScene(name: "Saved \(index)") }
    let saved = model.scenes
    #expect(!model.canSaveScene)
    #expect(model.canApplyBuiltInPreset)
    model.applyBuiltInPreset(.sceneMorph)
    #expect(model.scenes == saved)
    for target in model.targets {
        model.updateTargetBehavior(id: target.id, behavior: .off)
    }
    #expect(!model.canApplyBuiltInPreset)
    model.applyBuiltInPreset(.performanceAB)
    #expect(model.curve == .smooth)
    for target in model.targets { model.removeTarget(id: target.id) }
    #expect(!model.canApplyBuiltInPreset)
    model.applyBuiltInPreset(.performanceAB)
    #expect(model.targets.isEmpty && model.curve == .smooth)
    #expect(model.scenes == saved)
}

@Test("Built-in presets produce distinct A/B and Range MIDI output",
      arguments: BuiltInCrossfadePreset.allCases)
@MainActor
func builtInPresetMIDIOutput(preset: BuiltInCrossfadePreset) async {
    let engine = RecordingMIDIEngine()
    let model = AppModel(engine: engine, defaults: makeDefaults())
    model.applyBuiltInPreset(preset)
    engine.emit(channel: 13, controller: 48, value: 0)
    await drainMainQueue()
    model.isEnabled = true
    #expect(engine.sentMessages.map(\.value) == [95, 0])

    engine.sentMessages.removeAll()
    engine.emit(channel: 13, controller: 48, value: 64)
    await drainMainQueue()
    // Full Centre keeps A at 95, so only B needs a new message.
    let midpoint: [RecordingMIDIEngine.Message] = preset == .performanceAB
        ? [.init(value: 95, channel: 15, controller: 111)]
        : [.init(value: 47, channel: 15, controller: 110),
           .init(value: 48, channel: 15, controller: 111)]
    #expect(engine.sentMessages == midpoint)

    engine.sentMessages.removeAll()
    engine.emit(channel: 13, controller: 48, value: 127)
    await drainMainQueue()
    let right: [RecordingMIDIEngine.Message] = preset == .performanceAB
        ? [.init(value: 0, channel: 15, controller: 110)]
        : [.init(value: 0, channel: 15, controller: 110),
           .init(value: 95, channel: 15, controller: 111)]
    #expect(engine.sentMessages == right)
}

@Test("Send Learn emits movement and restores the active value")
@MainActor
func sendLearnPulse() async throws {
    let engine = RecordingMIDIEngine()
    let model = AppModel(engine: engine, defaults: makeDefaults())
    let groupB = model.targets[1]

    model.sendMappingMessage(to: groupB.id)
    #expect(engine.sentMessages == [
        .init(value: 94, channel: 15, controller: 111)
    ])

    try await Task.sleep(for: .milliseconds(150))
    #expect(engine.sentMessages == [
        .init(value: 94, channel: 15, controller: 111),
        .init(value: 95, channel: 15, controller: 111),
    ])

    engine.emit(channel: 13, controller: 48, value: 0)
    await drainMainQueue()
    model.isEnabled = true
    engine.sentMessages.removeAll()

    model.sendMappingMessage(to: groupB.id)
    try await Task.sleep(for: .milliseconds(150))

    #expect(engine.sentMessages == [
        .init(value: 94, channel: 15, controller: 111),
        .init(value: 95, channel: 15, controller: 111),
        .init(value: 0, channel: 15, controller: 111),
    ])
}

@Test("Send Learn cannot strand a target above its Return Value")
@MainActor
func sendLearnReturnSafety() async throws {
    let engine = RecordingMIDIEngine()
    let defaults = makeDefaults()
    let target = CrossfadeTarget(
        name: "Filter",
        controller: 112,
        side: .b,
        kind: .customMIDI,
        transition: .range,
        customLeftPercent: 0,
        customRightPercent: 80,
        restorePercent: 25
    )
    defaults.set(try JSONEncoder().encode([target]), forKey: "targets")
    let model = AppModel(engine: engine, defaults: defaults)

    model.sendMappingMessage(to: target.id)
    try await Task.sleep(for: .milliseconds(150))
    #expect(engine.sentMessages == [
        .init(value: 126, channel: 15, controller: 112),
        .init(value: 127, channel: 15, controller: 112),
        .init(value: 32, channel: 15, controller: 112),
    ])

    engine.emit(channel: 13, controller: 48, value: 64)
    await drainMainQueue()
    model.isEnabled = true
    engine.sentMessages.removeAll()

    model.sendMappingMessage(to: target.id)
    model.isEnabled = false
    try await Task.sleep(for: .milliseconds(150))
    #expect(engine.sentMessages.last == .init(
        value: 32,
        channel: 15,
        controller: 112
    ))
}

@Test("Mapping lifecycle changes cancel pending Learn messages", arguments: [
    "route", "kind", "behavior", "return", "channel", "source", "disconnect",
    "remove", "preset", "performanceAB", "sceneMorph", "pause", "terminate",
])
@MainActor
func pendingLearnCancellation(action: String) async throws {
    let engine = RecordingMIDIEngine()
    let defaults = makeDefaults()
    let target = CrossfadeTarget(
        name: "Filter", controller: 112, side: .b, kind: .customMIDI,
        transition: .range, restorePercent: 25
    )
    defaults.set(try JSONEncoder().encode([target]), forKey: "targets")
    let model = AppModel(engine: engine, defaults: defaults)
    model.saveScene(name: "Saved")
    model.sendMappingMessage(to: target.id)
    switch action {
    case "route": model.updateTargetController(id: target.id, controller: 113)
    case "kind": model.updateTargetKind(id: target.id, kind: .maschineLevel)
    case "behavior": model.updateTargetBehavior(id: target.id, behavior: .off)
    case "return": model.updateTargetRestore(id: target.id, percent: 0)
    case "channel": model.outputChannel = 4
    case "source": model.selectedSourceID = 999
    case "disconnect":
        engine.exposesSource = false
        model.refreshSources()
    case "remove": model.removeTarget(id: target.id)
    case "preset": model.loadScene(id: model.scenes[0].id)
    case "performanceAB": model.applyBuiltInPreset(.performanceAB)
    case "sceneMorph": model.applyBuiltInPreset(.sceneMorph)
    case "pause": model.restoreAndPause()
    case "terminate": model.prepareForTermination()
    default: Issue.record("Unknown lifecycle action")
    }
    #expect(engine.sentMessages.last == .init(value: 32, channel: 15, controller: 112))
    let checkpoint = engine.sentMessages
    try await Task.sleep(for: .milliseconds(160))
    #expect(engine.sentMessages == checkpoint)
}

@Test("Preset replacement returns a removed target during Send Learn")
@MainActor
func presetReplacementDuringLearn() async throws {
    let engine = RecordingMIDIEngine()
    let model = AppModel(engine: engine, defaults: makeDefaults())
    model.saveScene(name: "Before mapping")
    model.addParameterTarget()
    let target = model.targets.last!
    model.updateTargetRestore(id: target.id, percent: 0)
    model.sendMappingMessage(to: target.id)
    model.loadScene(id: model.scenes[0].id)
    let checkpoint = engine.sentMessages
    #expect(checkpoint.last == .init(value: 0, channel: 15, controller: UInt8(target.controller)))
    try await Task.sleep(for: .milliseconds(160))
    #expect(engine.sentMessages == checkpoint)
}

@Test("Repeated Send Learn cancels the earlier pulse")
@MainActor
func repeatedSendLearn() async throws {
    let engine = RecordingMIDIEngine()
    let model = AppModel(engine: engine, defaults: makeDefaults())
    let id = model.targets[0].id
    model.sendMappingMessage(to: id)
    model.sendMappingMessage(to: id)
    try await Task.sleep(for: .milliseconds(160))
    #expect(engine.sentMessages.map(\.value) == [94, 95, 94, 95])
}

@Test("Normal termination cancels Learn on Off targets and rejects later pulses")
@MainActor
func offTargetLearnTermination() async throws {
    let engine = RecordingMIDIEngine()
    let model = AppModel(engine: engine, defaults: makeDefaults())
    let id = model.targets[0].id
    model.updateTargetBehavior(id: id, behavior: .off)
    model.sendMappingMessage(to: id)
    model.prepareForTermination()
    model.prepareForTermination()
    model.sendMappingMessage(to: id)
    try await Task.sleep(for: .milliseconds(160))
    #expect(engine.sentMessages.map(\.value) == [94, 95])
}

@Test("Changing Shape recomputes the output and Pause sends the chosen Return Value")
@MainActor
func shapeAndReturnAtMidpoint() async throws {
    let engine = RecordingMIDIEngine()
    let defaults = makeDefaults()
    let target = CrossfadeTarget(
        name: "Filter", controller: 112, side: .b, kind: .customMIDI,
        transition: .range, customLeftPercent: 24, customRightPercent: 64,
        parameterCurve: .linear, restorePercent: 18
    )
    defaults.set(try JSONEncoder().encode([target]), forKey: "targets")
    let model = AppModel(engine: engine, defaults: defaults)
    engine.emit(channel: 13, controller: 48, value: 64)
    await drainMainQueue()
    model.isEnabled = true
    #expect(engine.sentMessages.last?.value == 56)
    model.updateTargetParameterCurve(id: target.id, curve: .exponential)
    #expect(engine.sentMessages.last?.value == 43)
    model.updateTargetParameterCurve(id: target.id, curve: .logarithmic)
    #expect(engine.sentMessages.last?.value == 66)
    model.restoreAndPause()
    #expect(engine.sentMessages.last?.value == 23)
}

@Test("Renaming an active target does not interrupt its Learn pulse or change the sound")
@MainActor
func renameDuringLearn() async throws {
    let engine = RecordingMIDIEngine()
    let model = AppModel(engine: engine, defaults: makeDefaults())
    engine.emit(channel: 13, controller: 48, value: 0)
    await drainMainQueue()
    model.isEnabled = true
    engine.sentMessages.removeAll()
    let id = model.targets[1].id
    model.sendMappingMessage(to: id)
    model.updateTargetName(id: id, name: "Renamed")
    #expect(engine.sentMessages.map(\.value) == [94])
    try await Task.sleep(for: .milliseconds(160))
    #expect(engine.sentMessages.map(\.value) == [94, 95, 0])
}
