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
        name: "Faderfox Test"
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

@Test("Loading presets while paused sends no MIDI")
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

    model.applyBuiltInPreset(.sceneMorph)
    #expect(engine.sentMessages.isEmpty)
    #expect(model.targets[0].behavior == .range)
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
