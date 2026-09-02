import AppKit
import Combine
import CoreMIDI
import CrossfaderCore
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var sources: [MIDISourceDescriptor] = []
    @Published private(set) var isConnected = false
    @Published private(set) var hasReceivedInput = false
    @Published private(set) var lastInput: UInt8 = 64
    @Published private(set) var lastOutput = CrossfadeOutput(groupA: 64, groupB: 64)

    @Published var selectedSourceID: MIDIUniqueID {
        didSet {
            if selectedSourceID != oldValue {
                hasReceivedInput = false
                if isEnabled {
                    isEnabled = false
                }
            }
            defaults.set(Int(selectedSourceID), forKey: Keys.sourceID)
            connectSelectedSource()
        }
    }
    @Published var learnedChannel: Int {
        didSet { defaults.set(learnedChannel, forKey: Keys.inputChannel) }
    }
    @Published var learnedController: Int {
        didSet { defaults.set(learnedController, forKey: Keys.inputController) }
    }
    @Published var isLearning = false
    @Published var isEnabled: Bool {
        didSet {
            if isEnabled {
                guard canActivate else {
                    suppressRestoreOnDisable = true
                    isEnabled = false
                    suppressRestoreOnDisable = false
                    return
                }
                lastSentValues.removeAll()
                updateCurrentOutput()
            } else {
                guard !suppressRestoreOnDisable else {
                    return
                }
                restoreAllTargets()
                lastSentValues.removeAll()
            }
        }
    }
    @Published var outputChannel: Int {
        didSet {
            guard outputChannel != oldValue else {
                return
            }
            restoreAllTargets(channel: oldValue)
            defaults.set(outputChannel, forKey: Keys.outputChannel)
            lastSentValues.removeAll()
            updateCurrentOutput()
        }
    }
    @Published private(set) var targets: [CrossfadeTarget] {
        didSet { persistTargets() }
    }
    @Published private(set) var scenes: [CrossfaderScenePreset] {
        didSet { persistScenes() }
    }
    @Published var mode: CrossfadeMode {
        didSet {
            defaults.set(mode.rawValue, forKey: Keys.mode)
            updateCurrentOutput()
        }
    }
    @Published var curve: CrossfadeCurve {
        didSet {
            defaults.set(curve.rawValue, forKey: Keys.curve)
            updateCurrentOutput()
        }
    }
    @Published var isReversed: Bool {
        didSet {
            defaults.set(isReversed, forKey: Keys.reversed)
            updateCurrentOutput()
        }
    }
    @Published var isTravelReversed: Bool {
        didSet {
            defaults.set(isTravelReversed, forKey: Keys.travelReversed)
            updateCurrentOutput()
        }
    }
    @Published var minimumLevel: CrossfadeMinimumLevel {
        didSet {
            defaults.set(minimumLevel.rawValue, forKey: Keys.minimumLevel)
            updateCurrentOutput()
        }
    }
    @Published var sideAColorHex: String {
        didSet { defaults.set(sideAColorHex, forKey: Keys.sideAColor) }
    }
    @Published var sideBColorHex: String {
        didSet { defaults.set(sideBColorHex, forKey: Keys.sideBColor) }
    }

    private let engine: MIDIEngineProtocol
    private let defaults: UserDefaults
    private var lastSentValues: [UUID: UInt8] = [:]
    private var terminationCancellable: AnyCancellable?
    private var didRestoreForTermination = false
    private var suppressRestoreOnDisable = false

    var selectedSourceName: String {
        sources.first(where: { $0.id == selectedSourceID })?.name ?? "No Controller"
    }

    var learnedControlDescription: String {
        guard learnedController >= 0, learnedChannel >= 0 else {
            return "Not Learned"
        }
        return "CC \(learnedController) · Ch \(learnedChannel + 1)"
    }

    var statusDescription: String {
        if isLearning {
            return "Move the crossfader"
        }
        if !engine.hasOutputEndpoint {
            return "MIDI output unavailable"
        }
        if !isConnected {
            return "Controller disconnected"
        }
        if learnedController < 0 || learnedChannel < 0 {
            return "Input not learned"
        }
        if !hasReceivedInput {
            return "Move crossfader once"
        }
        return isEnabled ? "Active" : "Paused"
    }

    var canActivate: Bool {
        engine.hasOutputEndpoint
            && isConnected
            && learnedController >= 0
            && learnedChannel >= 0
            && hasReceivedInput
    }

    var canAddTarget: Bool {
        targets.count < 128
    }

    var canSaveScene: Bool {
        scenes.count < 16
    }

    var hasCrossfadeTargets: Bool {
        targets.contains { target in
            target.participatesInOutput
                && target.transition == .crossfade
        }
    }

    init(
        engine: MIDIEngineProtocol = MIDIEngine(),
        defaults: UserDefaults = .standard
    ) {
        self.engine = engine
        self.defaults = defaults
        selectedSourceID = MIDIUniqueID(defaults.integer(forKey: Keys.sourceID))
        learnedChannel = min(
            15,
            max(
                -1,
                defaults.object(forKey: Keys.inputChannel) == nil
                    ? -1
                    : defaults.integer(forKey: Keys.inputChannel)
            )
        )
        learnedController = min(
            127,
            max(
                -1,
                defaults.object(forKey: Keys.inputController) == nil
                    ? -1
                    : defaults.integer(forKey: Keys.inputController)
            )
        )
        isEnabled = ProcessInfo.processInfo.environment[
            "MK_CROSSFADER_AUTOMATION_START_ACTIVE"
        ] == "1"
        outputChannel = min(
            15,
            max(
                0,
                defaults.object(forKey: Keys.outputChannel) == nil
                    ? 15
                    : defaults.integer(forKey: Keys.outputChannel)
            )
        )
        let loadedTargets = Self.loadTargets(from: defaults)
        let loadedMode = CrossfadeMode(
            rawValue: defaults.string(forKey: Keys.mode) ?? ""
        ) ?? .standard
        if loadedMode == .customScene {
            targets = loadedTargets.map { target in
                var migrated = target
                if migrated.participatesInOutput {
                    migrated.transition = .range
                }
                return migrated
            }
            mode = .standard
        } else {
            targets = loadedTargets
            mode = loadedMode
        }
        scenes = Self.loadScenes(from: defaults)
        curve = CrossfadeCurve(
            rawValue: defaults.string(forKey: Keys.curve) ?? ""
        ) ?? .fullCentre
        isReversed = defaults.bool(forKey: Keys.reversed)
        isTravelReversed = defaults.bool(forKey: Keys.travelReversed)
        minimumLevel = CrossfadeMinimumLevel(
            rawValue: defaults.string(forKey: Keys.minimumLevel) ?? ""
        ) ?? .kill
        let shouldMigrateNeutralPalette = !defaults.bool(
            forKey: Keys.didMigrateNeutralPalette
        )
        sideAColorHex = shouldMigrateNeutralPalette
            ? "D92D2D"
            : defaults.string(forKey: Keys.sideAColor) ?? "D92D2D"
        sideBColorHex = shouldMigrateNeutralPalette
            ? "8A8F96"
            : defaults.string(forKey: Keys.sideBColor) ?? "8A8F96"
        defaults.set(false, forKey: Keys.enabled)
        if loadedMode == .customScene {
            defaults.set(mode.rawValue, forKey: Keys.mode)
        }
        if shouldMigrateNeutralPalette {
            defaults.set(sideAColorHex, forKey: Keys.sideAColor)
            defaults.set(sideBColorHex, forKey: Keys.sideBColor)
            defaults.set(true, forKey: Keys.didMigrateNeutralPalette)
        }

        engine.onControlChange = { [weak self] message in
            DispatchQueue.main.async {
                self?.receive(message)
            }
        }
        engine.onSetupChange = { [weak self] in
            self?.refreshSources()
        }
        terminationCancellable = NotificationCenter.default.publisher(
            for: NSApplication.willTerminateNotification
        ).sink { [weak self] _ in
            MainActor.assumeIsolated {
                self?.prepareForTermination()
            }
        }

        refreshSources()
        persistTargets()
        updateCurrentOutput()
    }

    func refreshSources() {
        sources = engine.availableSources()

        if !sources.contains(where: { $0.id == selectedSourceID }),
            let faderfox = sources.first(where: {
                $0.name.localizedCaseInsensitiveContains("Faderfox")
            })
        {
            selectedSourceID = faderfox.id
            return
        }

        connectSelectedSource()
    }

    func beginLearning() {
        guard !isEnabled, isConnected else {
            return
        }
        hasReceivedInput = false
        isLearning = true
    }

    func cancelLearning() {
        isLearning = false
    }

    func addTarget() {
        guard !isEnabled,
            canAddTarget,
            let controller = nextAvailableController(startingAt: 112)
        else {
            return
        }
        targets.append(
            CrossfadeTarget(
                name: "Target \(targets.count + 1)",
                controller: controller
            )
        )
    }

    func removeTarget(id: UUID) {
        guard !isEnabled,
            let index = targets.firstIndex(where: { $0.id == id })
        else {
            return
        }

        let target = targets[index]
        restoreTargetIfNeeded(target)
        lastSentValues[id] = nil
        targets.remove(at: index)
    }

    func updateTargetName(id: UUID, name: String) {
        updateTarget(id: id) { $0.name = name }
    }

    func updateTargetController(id: UUID, controller: Int) {
        guard !isEnabled,
            let index = targets.firstIndex(where: { $0.id == id })
        else {
            return
        }

        let oldTarget = targets[index]
        let oldController = oldTarget.controller
        let proposed = min(127, max(0, controller))
        let resolved = controllerIsUsed(proposed, excludingID: id)
            ? nextAvailableController(
                startingAt: proposed + 1,
                excludingID: id
            )
            : proposed

        guard let resolved else {
            return
        }
        guard resolved != oldController else {
            return
        }
        restoreTargetIfNeeded(oldTarget, controller: oldController)
        targets[index].controller = resolved
        lastSentValues[id] = nil
        sendCurrentValue(to: id)
    }

    func updateTargetBehavior(
        id: UUID,
        behavior: CrossfadeTargetBehavior
    ) {
        guard !isEnabled else {
            return
        }
        updateTarget(id: id) { $0.apply(behavior) }
        lastSentValues[id] = nil
        sendCurrentValue(to: id)
    }

    func updateTargetKind(id: UUID, kind: CrossfadeTargetKind) {
        guard !isEnabled,
            let index = targets.firstIndex(where: { $0.id == id }),
            targets[index].kind != kind
        else {
            return
        }

        targets[index].kind = kind
        if kind == .customMIDI {
            targets[index].transition = .range
        }
        lastSentValues[id] = nil
        restoreTargetIfNeeded(targets[index])
    }

    func updateTargetParameterCurve(
        id: UUID,
        curve: CrossfadeParameterCurve
    ) {
        updateTarget(id: id) { $0.parameterCurve = curve }
        lastSentValues[id] = nil
        sendCurrentValue(to: id)
    }

    func updateTargetRestore(id: UUID, percent: Int) {
        guard !isEnabled else {
            return
        }
        updateTarget(id: id) {
            $0.restorePercent = min(100, max(0, percent))
        }
    }

    func updateTargetSceneLeft(id: UUID, percent: Int) {
        updateTarget(id: id) {
            $0.customLeftPercent = min(100, max(0, percent))
        }
        sendCurrentValue(to: id)
    }

    func updateTargetSceneRight(id: UUID, percent: Int) {
        updateTarget(id: id) {
            $0.customRightPercent = min(100, max(0, percent))
        }
        sendCurrentValue(to: id)
    }

    func sendMappingMessage(to id: UUID) {
        guard let target = targets.first(where: { $0.id == id }) else {
            return
        }

        let maximum = target.kind.maximumMIDIValue
        let pulseStart = maximum > 0 ? maximum - 1 : maximum
        let restoreValue = target.restoreOutput
        let channel = UInt8(clamping: outputChannel)
        let controller = UInt8(clamping: target.controller)

        engine.sendControlChange(
            value: pulseStart,
            channel: channel,
            controller: controller
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self,
                self.targets.contains(where: { $0.id == id })
            else {
                return
            }
            self.engine.sendControlChange(
                value: maximum,
                channel: channel,
                controller: controller
            )
            if self.isEnabled {
                self.sendCurrentValue(to: id)
            } else if restoreValue != maximum {
                self.engine.sendControlChange(
                    value: restoreValue,
                    channel: channel,
                    controller: controller
                )
            }
        }
    }

    func saveScene(name: String) {
        guard canSaveScene else {
            return
        }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = cleanName.isEmpty ? "Preset \(scenes.count + 1)" : cleanName
        let scene = CrossfaderScenePreset(
            name: uniqueSceneName(baseName),
            targets: targets,
            mode: mode,
            curve: curve,
            minimumLevel: minimumLevel,
            isReversed: isReversed,
            isTravelReversed: isTravelReversed
        )
        scenes.append(scene)
    }

    func applyBuiltInPreset(_ preset: BuiltInCrossfadePreset) {
        guard !isEnabled else {
            return
        }
        lastSentValues.removeAll()
        targets = preset.applying(to: targets)
        mode = preset.mode
        curve = preset.curve
        minimumLevel = preset.minimumLevel
        isReversed = false
        updateCurrentOutput()
    }

    func loadScene(id: UUID) {
        guard !isEnabled,
            let scene = scenes.first(where: { $0.id == id })
        else {
            return
        }
        lastSentValues.removeAll()
        targets = scene.targets
        mode = scene.mode
        curve = scene.curve
        minimumLevel = scene.minimumLevel
        isReversed = scene.isReversed
        isTravelReversed = scene.isTravelReversed
    }

    func deleteScene(id: UUID) {
        guard !isEnabled else {
            return
        }
        scenes.removeAll(where: { $0.id == id })
    }

    func restoreAndPause() {
        if isEnabled {
            isEnabled = false
        } else {
            restoreAllTargets()
        }
    }

    func quit() {
        prepareForTermination()
        NSApplication.shared.terminate(nil)
    }

    private func connectSelectedSource() {
        let wasConnected = isConnected
        let selectedSource = sources.first(where: { $0.id == selectedSourceID })
        isConnected = engine.connect(to: selectedSource)
        if !isConnected || !wasConnected {
            hasReceivedInput = false
        }
        if !isConnected {
            isLearning = false
            if isEnabled {
                isEnabled = false
            }
        }
    }

    private func receive(_ message: MIDIControlChange) {
        if isLearning {
            learnedChannel = Int(message.channel)
            learnedController = Int(message.controller)
            isLearning = false
        }

        guard Int(message.channel) == learnedChannel,
            Int(message.controller) == learnedController
        else {
            return
        }

        hasReceivedInput = true
        lastInput = message.value
        updateCurrentOutput()
    }

    private func updateCurrentOutput() {
        let maschineOutput = crossfadeOutput(for: .maschineLevel)
        lastOutput = maschineOutput

        guard isEnabled else {
            return
        }

        for target in targets {
            let output = target.kind == .maschineLevel
                ? maschineOutput
                : crossfadeOutput(for: target.kind)
            if let value = outputValue(for: target, crossfadeOutput: output),
                lastSentValues[target.id] != value
            {
                send(value: value, to: target)
            }
        }
    }

    private func sendCurrentValue(to id: UUID) {
        guard isEnabled,
            let target = targets.first(where: { $0.id == id })
        else {
            return
        }

        let output = crossfadeOutput(for: target.kind)
        let value = outputValue(for: target, crossfadeOutput: output)
            ?? target.restoreOutput
        send(value: value, to: target)
    }

    private func crossfadeOutput(
        for kind: CrossfadeTargetKind
    ) -> CrossfadeOutput {
        CrossfaderTransform.output(
            for: lastInput,
            mode: mode,
            curve: curve,
            reversed: isReversed,
            travelReversed: isTravelReversed,
            endpointKill: minimumLevel == .kill,
            minimumOutput: kind.minimumMIDIValue(for: minimumLevel),
            maximumOutput: kind.maximumMIDIValue
        )
    }

    private func outputValue(
        for target: CrossfadeTarget,
        crossfadeOutput: CrossfadeOutput
    ) -> UInt8? {
        guard target.participatesInOutput else {
            return nil
        }

        if mode == .customScene || target.transition == .range {
            return CrossfaderTransform.parameterValue(
                for: lastInput,
                leftOutput: target.sceneOutput(at: target.customLeftPercent),
                rightOutput: target.sceneOutput(at: target.customRightPercent),
                curve: target.parameterCurve,
                inheritedCurve: curve,
                travelReversed: isTravelReversed,
                maximumOutput: target.kind.maximumMIDIValue
            )
        }

        return CrossfadeRouting.value(
            for: target.side,
            output: crossfadeOutput
        )
    }

    private func send(value: UInt8, to target: CrossfadeTarget) {
        engine.sendControlChange(
            value: value,
            channel: UInt8(clamping: outputChannel),
            controller: UInt8(clamping: target.controller)
        )
        lastSentValues[target.id] = value
    }

    private func restoreAllTargets(channel: Int? = nil) {
        let restoreChannel = UInt8(clamping: channel ?? outputChannel)
        for target in targets where target.participatesInOutput {
            engine.sendControlChange(
                value: target.restoreOutput,
                channel: restoreChannel,
                controller: UInt8(clamping: target.controller)
            )
        }
    }

    private func restoreTargetIfNeeded(
        _ target: CrossfadeTarget,
        controller: Int? = nil
    ) {
        guard target.participatesInOutput else {
            return
        }
        engine.sendControlChange(
            value: target.restoreOutput,
            channel: UInt8(clamping: outputChannel),
            controller: UInt8(clamping: controller ?? target.controller)
        )
    }

    private func prepareForTermination() {
        guard !didRestoreForTermination else {
            return
        }
        didRestoreForTermination = true
        guard isEnabled else {
            return
        }
        restoreAllTargets()
    }

    private func updateTarget(
        id: UUID,
        change: (inout CrossfadeTarget) -> Void
    ) {
        guard let index = targets.firstIndex(where: { $0.id == id }) else {
            return
        }
        change(&targets[index])
    }

    private func nextAvailableController(
        startingAt start: Int,
        excludingID: UUID? = nil
    ) -> Int? {
        let normalizedStart = min(127, max(0, start))
        let order = Array(normalizedStart...127) + Array(0..<normalizedStart)
        return order.first(where: {
            !controllerIsUsed(
                $0,
                excludingID: excludingID
            )
        })
    }

    private func controllerIsUsed(
        _ controller: Int,
        excludingID: UUID? = nil
    ) -> Bool {
        targets.contains { target in
            target.id != excludingID && target.controller == controller
        }
    }

    private func persistTargets() {
        guard let data = try? JSONEncoder().encode(targets) else {
            return
        }
        defaults.set(data, forKey: Keys.targets)
    }

    private func persistScenes() {
        guard let data = try? JSONEncoder().encode(scenes) else {
            return
        }
        defaults.set(data, forKey: Keys.scenes)
    }

    private func uniqueSceneName(_ proposed: String) -> String {
        guard scenes.contains(where: {
            $0.name.localizedCaseInsensitiveCompare(proposed) == .orderedSame
        }) else {
            return proposed
        }
        var suffix = 2
        while scenes.contains(where: {
            $0.name.localizedCaseInsensitiveCompare("\(proposed) \(suffix)")
                == .orderedSame
        }) {
            suffix += 1
        }
        return "\(proposed) \(suffix)"
    }

    private static func loadTargets(from defaults: UserDefaults) -> [CrossfadeTarget] {
        if let data = defaults.data(forKey: Keys.targets),
            let decoded = try? JSONDecoder().decode(
                [CrossfadeTarget].self,
                from: data
            )
        {
            return CrossfadeConfigurationSanitizer.targets(decoded)
        }

        let controllerA = min(
            127,
            max(
                0,
                defaults.object(forKey: Keys.controllerA) == nil
                    ? 110
                    : defaults.integer(forKey: Keys.controllerA)
            )
        )
        let requestedControllerB = min(
            127,
            max(
                0,
                defaults.object(forKey: Keys.controllerB) == nil
                    ? 111
                    : defaults.integer(forKey: Keys.controllerB)
            )
        )
        let controllerB = requestedControllerB == controllerA
            ? (controllerA + 1) % 128
            : requestedControllerB
        return [
            CrossfadeTarget(
                name: "Group A",
                controller: controllerA,
                side: .a
            ),
            CrossfadeTarget(
                name: "Group B",
                controller: controllerB,
                side: .b
            ),
        ]
    }

    private static func loadScenes(
        from defaults: UserDefaults
    ) -> [CrossfaderScenePreset] {
        guard let data = defaults.data(forKey: Keys.scenes),
            let decoded = try? JSONDecoder().decode(
                [CrossfaderScenePreset].self,
                from: data
            )
        else {
            return []
        }
        return CrossfadeConfigurationSanitizer.scenes(decoded)
    }

    private enum Keys {
        static let sourceID = "selectedSourceID"
        static let inputChannel = "inputChannel"
        static let inputController = "inputController"
        static let enabled = "enabled"
        static let outputChannel = "outputChannel"
        static let controllerA = "controllerA"
        static let controllerB = "controllerB"
        static let targets = "targets"
        static let scenes = "scenesV1"
        static let mode = "mode"
        static let curve = "curve"
        static let reversed = "reversed"
        static let travelReversed = "travelReversed"
        static let minimumLevel = "minimumLevel"
        static let sideAColor = "sideAColor"
        static let sideBColor = "sideBColor"
        static let didMigrateNeutralPalette = "didMigrateNeutralPaletteV1"
    }

}
