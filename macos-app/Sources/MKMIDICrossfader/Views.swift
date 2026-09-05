import AppKit
import CoreMIDI
import CrossfaderCore
import SwiftUI

struct MenuBarContent: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updateChecker: AppUpdateChecker
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.selectedSourceName)
            .foregroundStyle(.secondary)
        if model.isLearning || !model.canActivate {
            Text(model.statusDescription)
                .foregroundStyle(.secondary)
        }

        Divider()

        Toggle(isOn: $model.isEnabled) {
            Label("Active", systemImage: "arrow.left.arrow.right")
        }
            .disabled(!model.canActivate)

        Button {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openWindow(id: "settings")
        } label: {
            Label("Settings", systemImage: "gearshape")
        }
        .keyboardShortcut(",")

        Button {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openWindow(id: "settings")
            Task {
                await updateChecker.checkForUpdates()
            }
        } label: {
            Label(
                updateChecker.state.isChecking
                    ? "Checking for Updates"
                    : "Check for Updates",
                systemImage: "arrow.triangle.2.circlepath"
            )
        }
        .disabled(updateChecker.state.isChecking)

        Divider()

        Button {
            model.restoreAndPause()
        } label: {
            Label("Return & Pause", systemImage: "arrow.counterclockwise")
        }

        Divider()

        Button(role: .destructive) {
            model.quit()
        } label: {
            Label("Quit", systemImage: "power")
        }
        .keyboardShortcut("q")
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updateChecker: AppUpdateChecker
    @AppStorage(AppActivationPolicy.showDockIconDefaultsKey)
    private var showDockIcon = true
    @StateObject private var launchAtLogin = LaunchAtLoginController()
    @State private var showsAdvanced = false
    @State private var selectedPresetID: UUID?
    @State private var showsSavePresetAlert = false
    @State private var presetName = ""
    @State private var presetPendingDeletion: UUID?
    @State private var showsUpdateResult = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                SettingsSection(title: "Controller") {
                    controllerSettings
                }

                Divider()

                SettingsSection(title: "Targets") {
                    targetSettings
                }

                Divider()

                SettingsSection(title: "Crossfade") {
                    crossfadeSettings
                }

                Divider()

                DisclosureGroup(isExpanded: $showsAdvanced) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 24) {
                            Stepper(
                                "Output channel · \(model.outputChannel + 1)",
                                value: $model.outputChannel,
                                in: 0...15
                            )
                            .disabled(model.isEnabled)
                            .frame(maxWidth: 230, alignment: .leading)
                            .help(
                                model.isEnabled
                                    ? "Pause before changing the output channel"
                                    : "MIDI channel used by all target mappings"
                            )

                            Spacer()
                        }

                        HStack(spacing: 28) {
                            Toggle(
                                "Reverse fader",
                                isOn: $model.isTravelReversed
                            )
                            .toggleStyle(.switch)
                            .disabled(model.isEnabled)
                            .help("Reverse the physical left and right direction")

                            Toggle("Show in Dock", isOn: $showDockIcon)
                                .toggleStyle(.switch)
                                .help("Show the app in the Dock and app switcher")

                            Toggle("Launch at Login", isOn: launchAtLoginBinding)
                                .toggleStyle(.switch)
                                .disabled(!launchAtLogin.isAvailable)
                                .help("Start the app when you sign in to macOS")

                            Spacer()
                        }

                        if let message = launchAtLogin.statusMessage {
                            HStack(spacing: 10) {
                                Label(message, systemImage: "info.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Spacer()

                                if launchAtLogin.requiresApproval {
                                    Button("Open Login Items") {
                                        launchAtLogin.openSystemSettings()
                                    }
                                    .controlSize(.small)
                                }
                            }
                        }

                        HStack(spacing: 18) {
                            ColorPicker(
                                "Side A",
                                selection: sideAColorBinding,
                                supportsOpacity: false
                            )
                            .fixedSize()
                            ColorPicker(
                                "Side B",
                                selection: sideBColorBinding,
                                supportsOpacity: false
                            )
                            .fixedSize()
                            Spacer()
                        }
                    }
                    .padding(.top, 12)
                } label: {
                    Label("Advanced", systemImage: "slider.horizontal.3")
                        .font(.headline)
                }

                updateStatus

                HStack(spacing: 3) {
                    Text("Made by")
                    Link(
                        "Mike Konstantinidis",
                        destination: URL(string: "https://konstantinidis.net/")!
                    )
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Open konstantinidis.net")
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(24)
        }
        .frame(width: 880, height: 780)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(Color(rgbHex: "747980"))
        .onAppear {
            launchAtLogin.refresh()
        }
        .onChange(of: showDockIcon) { _, isVisible in
            AppActivationPolicy.apply(showDockIcon: isVisible)
        }
        .onChange(of: updateChecker.state) { previous, current in
            if previous.isChecking && !current.isChecking {
                showsUpdateResult = true
            }
        }
        .alert("Save Preset", isPresented: $showsSavePresetAlert) {
            TextField("Preset name", text: $presetName)
            Button("Cancel", role: .cancel) {
                presetName = ""
            }
            Button("Save") {
                model.saveScene(name: presetName)
                selectedPresetID = nil
                presetName = ""
            }
        }
        .confirmationDialog(
            "Delete Preset?",
            isPresented: Binding(
                get: { presetPendingDeletion != nil },
                set: {
                    if !$0 {
                        presetPendingDeletion = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let presetPendingDeletion,
                let scene = model.scenes.first(where: {
                    $0.id == presetPendingDeletion
                })
            {
                Button("Delete \(scene.name)", role: .destructive) {
                    model.deleteScene(id: presetPendingDeletion)
                    selectedPresetID = nil
                    self.presetPendingDeletion = nil
                }
            }
            Button("Cancel", role: .cancel) {
                presetPendingDeletion = nil
            }
        } message: {
            Text("The saved preset will be removed permanently.")
        }
        .alert(updateResultTitle, isPresented: $showsUpdateResult) {
            Button(
                updateChecker.state.releaseURL == nil
                    ? "Open Releases"
                    : "View Release"
            ) {
                NSWorkspace.shared.open(
                    updateChecker.state.releaseURL
                        ?? AppUpdateChecker.releasesPageURL
                )
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(updateResultMessage)
        }
    }

    private var updateStatus: some View {
        HStack(spacing: 10) {
            Label(
                updateChecker.state.statusText,
                systemImage: updateChecker.state.systemImage
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()

            if let releaseURL = updateChecker.state.releaseURL {
                Link("View Release", destination: releaseURL)
                    .font(.caption)
            }

            Button {
                Task {
                    await updateChecker.checkForUpdates()
                }
            } label: {
                Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
            }
            .controlSize(.small)
            .disabled(updateChecker.state.isChecking)
            .help("Check the official GitHub Releases page")
        }
    }

    private var updateResultTitle: String {
        switch updateChecker.state {
        case .upToDate:
            return "MK Crossfader Is Up to Date"
        case .updateAvailable:
            return "MK Crossfader Update Available"
        case .noPublishedRelease:
            return "No Public Release Yet"
        case .failed:
            return "Update Check Failed"
        case .idle, .checking:
            return "Check for Updates"
        }
    }

    private var updateResultMessage: String {
        switch updateChecker.state {
        case .upToDate(let current):
            return "You are using the latest public version, \(current)."
        case .updateAvailable(let current, let latest, _):
            return "Version \(latest) is available. You are using \(current)."
        case .noPublishedRelease(let current):
            return "No public GitHub Release has been published yet. You are using version \(current)."
        case .failed:
            return "The app could not reach GitHub. Check your internet connection and try again."
        case .idle, .checking:
            return updateChecker.state.statusText
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            AppLogo()

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(model.statusDescription)
                        .font(.headline)
                }

                Text(model.selectedSourceName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                model.restoreAndPause()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .help("Send target Return Values and pause")
            .accessibilityLabel("Return and Pause")

            Divider()
                .frame(height: 24)

            Toggle("Active", isOn: $model.isEnabled)
                .toggleStyle(.switch)
                .disabled(!model.canActivate)
        }
    }

    private var presetSettings: some View {
        HStack(spacing: 10) {
            Text("Saved preset")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Saved preset", selection: $selectedPresetID) {
                Text("Select preset").tag(UUID?.none)
                ForEach(model.scenes) { preset in
                    Text(preset.name)
                        .tag(Optional(preset.id))
                }
            }
            .labelsHidden()
            .frame(width: 280, alignment: .leading)
            .help("Load a saved snapshot of targets and crossfade settings")

            Spacer(minLength: 0)

            Button {
                guard let selectedPresetID else {
                    return
                }
                model.loadScene(id: selectedPresetID)
                self.selectedPresetID = nil
            } label: {
                Label("Load", systemImage: "tray.and.arrow.down")
            }
            .disabled(model.isEnabled || selectedPresetID == nil)
            .help(model.isEnabled ? "Pause before loading a preset" : "Load preset")

            Button {
                presetName = ""
                showsSavePresetAlert = true
            } label: {
                Label("Save", systemImage: "plus")
            }
            .disabled(!model.canSaveScene)
            .help("Save current targets and crossfade settings")

            Button(role: .destructive) {
                guard let selectedPresetID else {
                    return
                }
                presetPendingDeletion = selectedPresetID
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .disabled(model.isEnabled || selectedPresetID == nil)
            .help(
                model.isEnabled
                    ? "Pause before deleting a preset"
                    : "Delete saved preset"
            )
            .accessibilityLabel("Delete saved preset")
        }
    }

    private var controllerSettings: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("MIDI controller")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    Picker("MIDI controller", selection: $model.selectedSourceID) {
                        Text("No Controller").tag(MIDIUniqueID(0))
                        ForEach(model.sources) { source in
                            Text(source.name).tag(source.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .disabled(model.isEnabled)

                    Button {
                        model.refreshSources()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh MIDI controllers")
                    .accessibilityLabel("Refresh MIDI controllers")
                }
            }
            .frame(width: 340, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text("Crossfader input")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(model.learnedControlDescription)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
            }
            .frame(width: 145, alignment: .leading)

            Spacer(minLength: 0)

            Button {
                if model.isLearning {
                    model.cancelLearning()
                } else {
                    model.beginLearning()
                }
            } label: {
                Label(
                    model.isLearning ? "Cancel" : "MIDI Learn",
                    systemImage: model.isLearning
                        ? "xmark.circle"
                        : "dot.radiowaves.left.and.right"
                )
            }
            .buttonStyle(LearnActionButtonStyle(primary: true))
            .disabled(model.isEnabled || !model.isConnected)
            .help(
                model.isEnabled
                    ? "Pause before learning the crossfader input"
                    : model.isConnected
                        ? "Move the physical fader or knob to learn its MIDI CC"
                        : "Connect and select a MIDI controller first"
            )
        }
    }

    private var targetSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.isEnabled {
                HStack(spacing: 8) {
                    Label("Routing locked", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Return & Edit") {
                        model.restoreAndPause()
                    }
                    .controlSize(.small)
                }
            }

            if model.targets.isEmpty {
                ContentUnavailableView(
                    "No Targets",
                    systemImage: "slider.horizontal.2.square",
                    description: Text("Add an A/B pair or a parameter to begin.")
                )
                .frame(height: 130)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(model.targets) { target in
                        TargetRow(target: target, model: model)
                    }
                }
            }

            Menu {
                Button {
                    model.addCrossfadePair()
                } label: {
                    Label("A/B Crossfade Pair", systemImage: "arrow.left.arrow.right")
                }
                .disabled(!model.canAddCrossfadePair)

                Button {
                    model.addParameterTarget()
                } label: {
                    Label("Parameter Range", systemImage: "slider.horizontal.3")
                }
                .disabled(!model.canAddTarget)

                Divider()

                Button {
                    model.addTarget()
                } label: {
                    Label("Level Target", systemImage: "speaker.wave.2")
                }
                .disabled(!model.canAddTarget)
            } label: {
                Label("Add Target", systemImage: "plus")
            }
            .disabled(model.isEnabled || !model.canAddTarget)
            .help(model.isEnabled ? "Pause before adding a target" : "Add target")
        }
    }

    private var crossfadeSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            presetSettings

            if model.hasCrossfadeTargets {
                Divider()

                HStack {
                    Text("Mode")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("Mode", selection: $model.mode) {
                        ForEach(CrossfadeMode.performanceCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 210, alignment: .trailing)
                    .help("Choose the A/B performance behaviour")
                }
            }

            if model.hasCrossfadeTargets || hasRangeTargetsUsingGlobalShape {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.hasCrossfadeTargets ? "Curve" : "Global shape")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Curve", selection: $model.curve) {
                        ForEach(CrossfadeCurve.allCases, id: \.self) { curve in
                            Text(curve.displayName).tag(curve)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            if model.hasCrossfadeTargets {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Fade floor")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Fade floor", selection: $model.minimumLevel) {
                        ForEach(CrossfadeMinimumLevel.allCases, id: \.self) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .help("Lowest level reached by fading A/B targets")
                }

                HStack(spacing: 24) {
                    LevelMeter(
                        label: "A",
                        value: model.lastOutput.groupA,
                        maximum: 95,
                        tint: sideAColor
                    )
                    LevelMeter(
                        label: "B",
                        value: model.lastOutput.groupB,
                        maximum: 95,
                        tint: sideBColor
                    )
                }
                .frame(height: 28)

                HStack {
                    Toggle("Swap A/B", isOn: $model.isReversed)
                        .disabled(model.mode == .pairFade)
                        .help("Exchange the A and B target assignments")
                    Spacer()
                }
                .toggleStyle(.switch)
            }
        }
    }

    private var hasRangeTargetsUsingGlobalShape: Bool {
        model.targets.contains { target in
            target.participatesInOutput
                && target.transition == .range
                && target.parameterCurve == .inherit
        }
    }

    private var sideAColor: Color {
        Color(rgbHex: model.sideAColorHex)
    }

    private var sideBColor: Color {
        Color(rgbHex: model.sideBColorHex)
    }

    private var sideAColorBinding: Binding<Color> {
        Binding(
            get: { sideAColor },
            set: { color in
                if let hex = color.rgbHex {
                    model.sideAColorHex = hex
                }
            }
        )
    }

    private var sideBColorBinding: Binding<Color> {
        Binding(
            get: { sideBColor },
            set: { color in
                if let hex = color.rgbHex {
                    model.sideBColorHex = hex
                }
            }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin.isEnabled },
            set: { launchAtLogin.setEnabled($0) }
        )
    }

    private var statusColor: Color {
        if model.isEnabled, model.canActivate {
            return Color(rgbHex: "F3F3F1")
        }
        if model.isLearning {
            return Color(rgbHex: "8A8F96")
        }
        return .secondary
    }
}

private struct TargetRow: View {
    let target: CrossfadeTarget
    @ObservedObject var model: AppModel
    @State private var showsMapping = false
    @State private var draftName: String
    @FocusState private var isNameFocused: Bool

    init(target: CrossfadeTarget, model: AppModel) {
        self.target = target
        self.model = model
        _draftName = State(initialValue: target.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: sideIcon)
                    .font(.title3)
                    .foregroundStyle(sideColor)
                    .frame(width: 22)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    TextField(
                        "Target name",
                        text: $draftName,
                        prompt: Text("Target")
                    )
                    .textFieldStyle(.plain)
                    .font(.headline)
                    .focused($isNameFocused)
                    .onSubmit(commitName)
                    .onChange(of: isNameFocused) { _, isFocused in
                        if isFocused {
                            selectAllName()
                        } else {
                            commitName()
                        }
                    }
                    .onChange(of: target.name) { _, name in
                        guard !isNameFocused else {
                            return
                        }
                        draftName = name
                    }
                    .help("Click and type to replace the target name")
                    Picker("Target type", selection: kindBinding) {
                        ForEach(selectableTargetKinds, id: \.self) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .fixedSize()
                    .disabled(model.isEnabled)
                    .help(
                        model.isEnabled
                            ? "Pause before changing the target type"
                            : "Maschine level or full-range MIDI parameter"
                    )
                }
                .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)

                Picker("Behaviour", selection: behaviorBinding) {
                    ForEach(CrossfadeTargetBehavior.allCases, id: \.self) { behavior in
                        Text(behavior.displayName).tag(behavior)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 220)
                .disabled(model.isEnabled)
                .help(
                    model.isEnabled
                        ? "Pause before changing target routing"
                        : "Follow side A, side B, a custom range, or stay off"
                )

                Button(role: .destructive) {
                    model.removeTarget(id: target.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .disabled(model.isEnabled)
                .help("Remove target")
                .accessibilityLabel("Remove \(target.displayName)")
            }

            HStack(spacing: 14) {
                Button {
                    model.sendMappingMessage(to: target.id)
                } label: {
                    Label("Send Learn", systemImage: "paperplane.fill")
                }
                .buttonStyle(LearnActionButtonStyle())
                .accessibilityLabel("Send MIDI Learn for \(target.displayName)")
                .help(
                    model.isEnabled
                        ? "Send a short MIDI Learn movement, then return to the current live value"
                        : "Send a short MIDI Learn movement, then send the Return Value"
                )

                DisclosureGroup(isExpanded: $showsMapping) {
                    Stepper(
                        "Output CC · \(target.controller)",
                        value: controllerBinding,
                        in: 0...127
                    )
                    .padding(.top, 8)
                } label: {
                    Text("Output CC \(target.controller)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 190, alignment: .leading)
                .disabled(model.isEnabled)

                Spacer()
            }

            if usesRangeControls {
                HStack(spacing: 18) {
                    SceneEndpointControl(
                        label: "Left",
                        value: sceneLeftBinding
                    )
                    SceneEndpointControl(
                        label: "Right",
                        value: sceneRightBinding
                    )
                }

                HStack(spacing: 18) {
                    LabeledContent("Shape") {
                        Picker("Shape", selection: parameterCurveBinding) {
                            ForEach(CrossfadeParameterCurve.allCases, id: \.self) { curve in
                                Text(curve.displayName).tag(curve)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 150)
                        .help(
                            "Shape used while moving from the Left value to the Right value"
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    LabeledContent("Return Value") {
                        HStack(spacing: 8) {
                            Slider(value: restoreBinding, in: 0...100, step: 1)
                                .accessibilityLabel("Return value")
                            Text("\(target.restorePercent)%")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .disabled(model.isEnabled)
                    .help(
                        model.isEnabled
                            ? "Pause before changing the Return Value"
                            : "Value sent on Pause, target removal, CC or output change, and normal Quit"
                    )
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.09), lineWidth: 1)
        }
    }

    private var sideIcon: String {
        switch target.behavior {
        case .sideA:
            return "a.circle.fill"
        case .sideB:
            return "b.circle.fill"
        case .range:
            return "slider.horizontal.3"
        case .off:
            return "minus.circle"
        }
    }

    private var usesRangeControls: Bool {
        target.behavior == .range
    }

    private var sideColor: Color {
        switch target.behavior {
        case .sideA:
            return Color(rgbHex: model.sideAColorHex)
        case .sideB:
            return Color(rgbHex: model.sideBColorHex)
        case .range:
            return Color(rgbHex: "8A8F96")
        case .off:
            return .secondary
        }
    }

    private func commitName() {
        let cleanName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            draftName = target.name
            return
        }
        draftName = cleanName
        if cleanName != target.name {
            model.updateTargetName(id: target.id, name: cleanName)
        }
    }

    private func selectAllName() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard isNameFocused else {
                return
            }
            NSApp.sendAction(
                #selector(NSText.selectAll(_:)),
                to: nil,
                from: nil
            )
        }
    }

    private var behaviorBinding: Binding<CrossfadeTargetBehavior> {
        Binding(
            get: { target.behavior },
            set: { model.updateTargetBehavior(id: target.id, behavior: $0) }
        )
    }

    private var kindBinding: Binding<CrossfadeTargetKind> {
        Binding(
            get: { target.kind },
            set: { model.updateTargetKind(id: target.id, kind: $0) }
        )
    }

    private var selectableTargetKinds: [CrossfadeTargetKind] {
        if CrossfadeTargetKind.setupCases.contains(target.kind) {
            return CrossfadeTargetKind.setupCases
        }
        return [target.kind] + CrossfadeTargetKind.setupCases
    }

    private var parameterCurveBinding: Binding<CrossfadeParameterCurve> {
        Binding(
            get: { target.parameterCurve },
            set: {
                model.updateTargetParameterCurve(id: target.id, curve: $0)
            }
        )
    }

    private var sceneLeftBinding: Binding<Double> {
        Binding(
            get: { Double(target.customLeftPercent) },
            set: {
                model.updateTargetSceneLeft(
                    id: target.id,
                    percent: Int($0.rounded())
                )
            }
        )
    }

    private var sceneRightBinding: Binding<Double> {
        Binding(
            get: { Double(target.customRightPercent) },
            set: {
                model.updateTargetSceneRight(
                    id: target.id,
                    percent: Int($0.rounded())
                )
            }
        )
    }

    private var restoreBinding: Binding<Double> {
        Binding(
            get: { Double(target.restorePercent) },
            set: {
                model.updateTargetRestore(
                    id: target.id,
                    percent: Int($0.rounded())
                )
            }
        )
    }

    private var controllerBinding: Binding<Int> {
        Binding(
            get: { target.controller },
            set: { model.updateTargetController(id: target.id, controller: $0) }
        )
    }
}

private struct AppLogo: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(rgbHex: "17191C"))

            RouteMark(
                leftColor: Color(rgbHex: "F3F3F1"),
                rightColor: Color(rgbHex: "88888C")
            )
            .frame(width: 31, height: 20)
        }
        .frame(width: 40, height: 40)
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content
        }
    }
}

private struct LevelMeter: View {
    let label: String
    let value: UInt8
    let maximum: UInt8
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(.body, design: .monospaced, weight: .semibold))
                .frame(width: 14)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)
                    Capsule()
                        .fill(tint)
                        .frame(
                            width: geometry.size.width
                                * CGFloat(value) / CGFloat(max(1, maximum))
                        )
                }
            }
            .frame(height: 8)
            Text("\(percent)%")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Side \(label) output")
        .accessibilityValue("\(percent) percent")
    }

    private var percent: Int {
        Int(
            (Double(value) / Double(max(1, maximum)) * 100).rounded()
        )
    }
}

private struct SceneEndpointControl: View {
    let label: String
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .frame(width: 36, alignment: .leading)
            Slider(value: $value, in: 0...100, step: 1)
                .accessibilityLabel("\(label) value")
            Text("\(Int(value.rounded()))%")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
    }
}

extension Color {
    init(rgbHex: String) {
        let cleaned = rgbHex.trimmingCharacters(
            in: CharacterSet.alphanumerics.inverted
        )
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0,
            opacity: 1.0
        )
    }

    var rgbHex: String? {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else {
            return nil
        }
        func byte(_ component: CGFloat) -> Int {
            Int((min(1.0, max(0.0, component)) * 255.0).rounded())
        }
        return String(
            format: "%02X%02X%02X",
            byte(color.redComponent),
            byte(color.greenComponent),
            byte(color.blueComponent)
        )
    }
}
