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
                cancelPendingMappings()
                cancelLearning()
                resetInputState()
                if isEnabled {
                    isEnabled = false
                }
            }
            defaults.set(Int(selectedSourceID), forKey: Keys.sourceID)
            connectSelectedSource()
        }
    }
    @Published private(set) var inputConfiguration: InputConfiguration
    @Published private(set) var inputState = CrossfaderInputState()
    @Published private(set) var inputIssues: [String] = []
    @Published private(set) var isLearning = false
    @Published private(set) var learningAxis: InputAxis?
    @Published private(set) var learningCandidate: MIDICCBinding?
    @Published private(set) var learningCandidateValue: UInt8?
    @Published private(set) var isLearningGate = false
    private let inputEpoch = MIDIInputEpoch()
    private var inputConfigurationWritable: Bool
    var learnedChannel: Int { inputConfiguration.x?.channel ?? -1 }
    var learnedController: Int { inputConfiguration.x?.controller ?? -1 }
    @Published var isEnabled: Bool {
        didSet {
            if isEnabled {
                guard canActivate else {
                    suppressRestoreOnDisable = true
                    isEnabled = false
                    suppressRestoreOnDisable = false
                    return
                }
                cancelPendingMappings()
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
    private let defaults: any SettingsStore
    private var lastSentValues: [UUID: UInt8] = [:]
    private var terminationCancellable: AnyCancellable?
    private var didRestoreForTermination = false
    private var suppressRestoreOnDisable = false
    private struct PendingMapping {
        let generation: UUID
        let channel: UInt8
        let controller: UInt8
        let returnValue: UInt8
    }
    private var pendingMappings: [UUID: PendingMapping] = [:]

    var selectedSourceName: String {
        sources.first(where: { $0.id == selectedSourceID })?.name ?? "No Controller"
    }

    var learnedControlDescription: String {
        guard learnedController >= 0, learnedChannel >= 0 else {
            return "Not Learned"
        }
        return "CC \(learnedController) · Ch \(learnedChannel + 1)"
    }

    var requiredInputAxes: Set<InputAxis> {
        if inputConfiguration.mode == .single { return [.x] }
        return Set(targets.filter(\.participatesInOutput).map(\.inputAxis))
    }

    func effectiveAxis(for target: CrossfadeTarget) -> InputAxis {
        inputConfiguration.mode == .single ? .x : target.inputAxis
    }

    var statusDescription: String {
        if isLearning { return learningCandidate == nil ? "Move the selected input" : "Confirm the learned input" }
        if !inputConfigurationWritable { return inputIssues.first ?? "Reset input settings" }
        if !engine.hasOutputEndpoint { return "MIDI output unavailable" }
        if !isConnected { return "Controller disconnected" }
        if hasMissingGatePolicy { return "Configure Touch Gate or choose Hold" }
        if usesTouchGate, inputState.gateState != true { return "Touch the controller to continue" }
        if requiredInputAxes.isEmpty { return "Add or enable a target" }
        for axis in InputAxis.allCases where requiredInputAxes.contains(axis) {
            if inputConfiguration.binding(for: axis) == nil { return "Learn input \(axis.label)" }
            if !inputState.freshAxes.contains(axis) || (usesTouchGate && !inputState.receivedSinceTouch.contains(axis)) { return inputConfiguration.mode == .single ? "Move crossfader once" : "Move input \(axis.label) once" }
        }
        return isEnabled ? "Active" : "Paused"
    }

    var usesTouchGate: Bool { inputConfiguration.mode == .xyz && inputConfiguration.touchGate != nil }
    private var hasMissingGatePolicy: Bool {
        inputConfiguration.mode == .xyz && inputConfiguration.touchGate == nil &&
            targets.contains { $0.participatesInOutput && $0.releasePolicy == .returnValue }
    }

    var canToggleOutput: Bool { isEnabled || canActivate }

    var canActivate: Bool {
        engine.hasOutputEndpoint && isConnected && !isLearning && inputConfigurationWritable
            && requiredInputAxes.allSatisfy { inputConfiguration.binding(for: $0) != nil }
            && !hasMissingGatePolicy
            && inputState.canEmit(requiredAxes: requiredInputAxes, gateEnabled: usesTouchGate)
    }

    var canAddTarget: Bool {
        targets.count < 128
    }

    var canAddCrossfadePair: Bool {
        targets.count <= 126
            && Set(targets.map(\.controller)).count <= 126
    }

    var canSaveScene: Bool {
        scenes.count < 16
    }

    var canApplyBuiltInPreset: Bool {
        !isEnabled && targets.contains(where: \.participatesInOutput)
    }

    var hasCrossfadeTargets: Bool {
        targets.contains { target in
            target.participatesInOutput
                && target.transition == .crossfade
        }
    }

    init(
        engine: MIDIEngineProtocol = MIDIEngine(),
        defaults: any SettingsStore = UserDefaults.standard
    ) {
        self.engine = engine
        self.defaults = defaults
        selectedSourceID = MIDIUniqueID(defaults.integer(forKey: Keys.sourceID))
        let inputLoad = InputConfigurationStore.load(from: defaults)
        inputConfiguration = inputLoad.configuration
        inputConfigurationWritable = inputLoad.isWritable
        inputIssues = inputLoad.issues
        isEnabled = false
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

        let epoch = inputEpoch
        engine.onControlChange = { [weak self] message in
            let receivedEpoch = epoch.current
            DispatchQueue.main.async {
                guard epoch.current == receivedEpoch else { return }
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
            let firstSource = sources.first
        {
            selectedSourceID = firstSource.id
            return
        }

        connectSelectedSource()
    }

    func beginLearning() { beginLearning(axis: .x) }

    func beginLearning(axis: InputAxis) {
        guard !isEnabled, isConnected, inputConfigurationWritable else { return }
        cancelPendingMappings()
        resetInputState()
        inputIssues = []
        isLearningGate = false
        learningAxis = axis
        learningCandidate = nil
        learningCandidateValue = nil
        isLearning = true
    }

    func cancelLearning() {
        isLearning = false
        isLearningGate = false
        learningAxis = nil
        learningCandidate = nil
        learningCandidateValue = nil
        if inputConfigurationWritable { inputIssues = [] }
    }

    @discardableResult
    func confirmLearning() -> Bool {
        guard isLearning, let binding = learningCandidate else { return false }
        let accepted: Bool
        if isLearningGate { accepted = setTouchGate(binding) }
        else if let axis = learningAxis { accepted = setInputBinding(binding, for: axis) }
        else { return false }
        guard accepted else { return false }
        cancelLearning()
        return true
    }

    func beginGateLearning() {
        beginLearning(axis: .x)
        guard isLearning else { return }
        learningAxis = nil
        isLearningGate = true
    }

    @discardableResult
    func setTouchGate(_ binding: MIDICCBinding?) -> Bool {
        if binding == nil { return disableTouchGate(confirmPolicyReset: false) }
        var next = inputConfiguration
        next.touchGate = binding
        return applyInputConfiguration(next)
    }

    @discardableResult
    func disableTouchGate(confirmPolicyReset: Bool) -> Bool {
        guard !isEnabled else { return false }
        if targets.contains(where: { $0.releasePolicy == .returnValue }), !confirmPolicyReset {
            inputIssues = ["Disabling Touch Gate changes release behaviour to Hold. Confirm to continue."]
            return false
        }
        var next = inputConfiguration
        next.touchGate = nil
        guard applyInputConfiguration(next) else { return false }
        targets = targets.map { target in
            var updated = target; updated.releasePolicy = .hold; return updated
        }
        return true
    }

    func updateTargetReleasePolicy(id: UUID, policy: TouchReleasePolicy) {
        guard !isEnabled, policy == .hold || inputConfiguration.touchGate != nil else { return }
        updateTarget(id: id) { $0.releasePolicy = policy }
    }

    @discardableResult
    func setInputBinding(_ binding: MIDICCBinding?, for axis: InputAxis) -> Bool {
        var next = inputConfiguration
        next.setBinding(binding, for: axis)
        return applyInputConfiguration(next)
    }

    func setInputMode(_ mode: InputMode) {
        guard mode != inputConfiguration.mode else { return }
        var next = inputConfiguration
        next.mode = mode
        if applyInputConfiguration(next) { cancelLearning() }
    }

    @discardableResult
    private func applyInputConfiguration(_ next: InputConfiguration) -> Bool {
        guard !isEnabled, inputConfigurationWritable else { return false }
        let issues = next.validate()
        guard issues.isEmpty else { inputIssues = issues; return false }
        guard InputConfigurationStore.save(next, to: defaults) else { return false }
        cancelPendingMappings()
        inputConfiguration = next
        inputIssues = []
        resetInputState()
        return true
    }

    /// Explicit recovery only: never overwrite unreadable or newer settings on load.
    func resetInputConfiguration() {
        guard !isEnabled else { return }
        cancelPendingMappings()
        defaults.removeObject(forKey: InputConfigurationStore.key)
        inputConfigurationWritable = true
        _ = applyInputConfiguration(InputConfiguration())
        cancelLearning()
    }

    private func resetInputState() {
        inputEpoch.invalidate()
        inputState.reset()
        hasReceivedInput = false
        lastSentValues.removeAll()
    }

    func updateTargetInputAxis(id: UUID, axis: InputAxis) {
        guard !isEnabled else { return }
        updateTarget(id: id) { $0.inputAxis = axis }
        resetInputState()
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

    func addCrossfadePair() {
        guard !isEnabled,
            canAddCrossfadePair,
            let controllerA = nextAvailableController(startingAt: 110),
            let controllerB = nextAvailableController(
                startingAt: controllerA + 1,
                reserving: [controllerA]
            )
        else {
            return
        }

        targets.append(contentsOf: [
            CrossfadeTarget(
                name: uniqueTargetName("Group A"),
                controller: controllerA,
                side: .a
            ),
            CrossfadeTarget(
                name: uniqueTargetName("Group B"),
                controller: controllerB,
                side: .b
            ),
        ])
    }

    func addParameterTarget() {
        guard !isEnabled,
            canAddTarget,
            let controller = nextAvailableController(startingAt: 112)
        else {
            return
        }

        targets.append(
            CrossfadeTarget(
                name: uniqueTargetName("Parameter"),
                controller: controller,
                side: .b,
                kind: .customMIDI,
                transition: .range,
                customLeftPercent: 0,
                customRightPercent: 100
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
        guard let index = targets.firstIndex(where: { $0.id == id }) else { return }
        targets[index].name = name
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

        let oldTarget = targets[index]
        restoreTargetIfNeeded(oldTarget)
        targets[index].kind = kind
        if kind == .customMIDI {
            targets[index].transition = .range
        }
        lastSentValues[id] = nil
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
        guard !didRestoreForTermination,
            let target = targets.first(where: { $0.id == id }) else {
            return
        }

        cancelPendingMapping(id)
        let maximum = target.kind.maximumMIDIValue
        let pulseStart = maximum > 0 ? maximum - 1 : maximum
        let restoreValue = target.restoreOutput
        let channel = UInt8(clamping: outputChannel)
        let controller = UInt8(clamping: target.controller)
        let pending = PendingMapping(
            generation: UUID(), channel: channel, controller: controller,
            returnValue: restoreValue
        )
        pendingMappings[id] = pending
        // Mapping pulses change the host independently of normal live output.
        lastSentValues[id] = nil

        engine.sendControlChange(
            value: pulseStart,
            channel: channel,
            controller: controller
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self,
                self.pendingMappings[id]?.generation == pending.generation
            else {
                return
            }
            self.pendingMappings[id] = nil
            self.lastSentValues[id] = nil
            self.engine.sendControlChange(
                value: maximum,
                channel: channel,
                controller: controller
            )
            if self.isEnabled && self.canActivate {
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
            isTravelReversed: isTravelReversed,
            inputMode: inputConfiguration.mode
        )
        scenes.append(scene)
    }

    func applyBuiltInPreset(_ preset: BuiltInCrossfadePreset) {
        guard canApplyBuiltInPreset else { return }
        cancelPendingMappings()
        lastSentValues.removeAll()
        cancelLearning()
        resetInputState()
        targets = preset.applying(to: targets)
        mode = .standard
        curve = preset.curve
        minimumLevel = .kill
        isReversed = false
        isTravelReversed = false
    }

    func loadScene(id: UUID) {
        guard !isEnabled,
            let scene = scenes.first(where: { $0.id == id })
        else {
            return
        }
        cancelPendingMappings()
        lastSentValues.removeAll()
        cancelLearning()
        setInputMode(scene.inputMode)
        resetInputState()
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
            resetInputState()
        }
        if !isConnected {
            cancelPendingMappings()
            cancelLearning()
            if isEnabled {
                isEnabled = false
            }
        }
    }

    private func receive(_ message: MIDIControlChange) {
        guard isConnected, !didRestoreForTermination, message.value <= 127 else { return }
        if isLearning {
            if learningCandidate == nil {
                learningCandidate = MIDICCBinding(channel: Int(message.channel), controller: Int(message.controller))
            }
            if learningCandidate?.matches(message) == true { learningCandidateValue = message.value }
            return
        }
        if usesTouchGate, inputConfiguration.touchGate?.matches(message) == true {
            let transition = inputState.receiveGate(message.value)
            if transition != .unchanged {
                let returned = cancelPendingMappings()
                if transition == .ended, isEnabled {
                    for target in targets where target.participatesInOutput && target.releasePolicy == .returnValue && !returned.contains(target.id) {
                        send(value: target.restoreOutput, to: target)
                    }
                }
            }
            return
        }
        if usesTouchGate, inputState.gateState != true { return }
        let wasReady = inputState.canEmit(requiredAxes: requiredInputAxes, gateEnabled: usesTouchGate)
        guard let axis = InputAxis.allCases.first(where: { inputConfiguration.binding(for: $0)?.matches(message) == true }),
              inputConfiguration.mode == .xyz || axis == .x else { return }
        inputState.receiveAxis(axis, value: message.value)
        if axis == .x { hasReceivedInput = true; lastInput = message.value }
        updateCurrentOutput(changedAxis: usesTouchGate && !wasReady ? nil : axis)
    }

    private func updateCurrentOutput(changedAxis: InputAxis? = nil) {
        lastOutput = crossfadeOutput(for: .maschineLevel, input: inputState.value(for: .x) ?? lastInput)
        guard isEnabled, !didRestoreForTermination, canActivate else { return }
        for target in targets {
            if let changedAxis, effectiveAxis(for: target) != changedAxis { continue }
            if let value = outputValue(for: target), lastSentValues[target.id] != value {
                send(value: value, to: target)
            }
        }
    }

    private func sendCurrentValue(to id: UUID) {
        guard isEnabled, !didRestoreForTermination, canActivate,
              let target = targets.first(where: { $0.id == id }) else { return }
        let value = canActivate ? outputValue(for: target) : nil
        send(value: value ?? target.restoreOutput, to: target)
    }

    private func crossfadeOutput(for kind: CrossfadeTargetKind, input: UInt8) -> CrossfadeOutput {
        CrossfaderTransform.output(
            for: input, mode: mode, curve: curve,
            reversed: isReversed, travelReversed: isTravelReversed,
            endpointKill: minimumLevel == .kill,
            minimumOutput: kind.minimumMIDIValue(for: minimumLevel),
            maximumOutput: kind.maximumMIDIValue
        )
    }

    private func outputValue(for target: CrossfadeTarget) -> UInt8? {
        guard target.participatesInOutput,
              let input = inputState.value(for: effectiveAxis(for: target)) else { return nil }
        if mode == .customScene || target.transition == .range {
            return CrossfaderTransform.parameterValue(
                for: input,
                leftOutput: target.sceneOutput(at: target.customLeftPercent),
                rightOutput: target.sceneOutput(at: target.customRightPercent),
                curve: target.parameterCurve, inheritedCurve: curve,
                travelReversed: isTravelReversed,
                maximumOutput: target.kind.maximumMIDIValue
            )
        }
        return CrossfadeRouting.value(for: target.side, output: crossfadeOutput(for: target.kind, input: input))
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
        let returned = cancelPendingMappings()
        let restoreChannel = UInt8(clamping: channel ?? outputChannel)
        for target in targets where target.participatesInOutput && !returned.contains(target.id) {
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
        if cancelPendingMapping(target.id) { return }
        guard target.participatesInOutput else {
            return
        }
        engine.sendControlChange(
            value: target.restoreOutput,
            channel: UInt8(clamping: outputChannel),
            controller: UInt8(clamping: controller ?? target.controller)
        )
    }

    func prepareForTermination() {
        guard !didRestoreForTermination else {
            return
        }
        didRestoreForTermination = true
        guard isEnabled else {
            cancelPendingMappings()
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
        cancelPendingMapping(id)
        change(&targets[index])
    }

    @discardableResult
    private func cancelPendingMapping(_ id: UUID) -> Bool {
        guard let pending = pendingMappings.removeValue(forKey: id) else {
            return false
        }
        engine.sendControlChange(
            value: pending.returnValue,
            channel: pending.channel,
            controller: pending.controller
        )
        lastSentValues[id] = nil
        return true
    }

    @discardableResult
    private func cancelPendingMappings() -> Set<UUID> {
        let ids = Set(pendingMappings.keys)
        for id in ids { cancelPendingMapping(id) }
        return ids
    }

    private func nextAvailableController(
        startingAt start: Int,
        excludingID: UUID? = nil,
        reserving reservedControllers: Set<Int> = []
    ) -> Int? {
        let normalizedStart = min(127, max(0, start))
        let order = Array(normalizedStart...127) + Array(0..<normalizedStart)
        return order.first(where: {
            !reservedControllers.contains($0) && !controllerIsUsed(
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

    private func uniqueTargetName(_ proposed: String) -> String {
        guard targets.contains(where: {
            $0.name.localizedCaseInsensitiveCompare(proposed) == .orderedSame
        }) else {
            return proposed
        }
        var suffix = 2
        while targets.contains(where: {
            $0.name.localizedCaseInsensitiveCompare("\(proposed) \(suffix)")
                == .orderedSame
        }) {
            suffix += 1
        }
        return "\(proposed) \(suffix)"
    }

    private static func loadTargets(from defaults: any SettingsStore) -> [CrossfadeTarget] {
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
        from defaults: any SettingsStore
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
