import SwiftUI
import CoreMIDI

struct InputConfigurationView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Picker("MIDI controller", selection: $model.selectedSourceID) {
                    Text("No Controller").tag(MIDIUniqueID(0))
                    ForEach(model.sources) { source in Text(source.name).tag(source.id) }
                }
                .disabled(model.isEnabled)
                Button { model.refreshSources() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Refresh MIDI controllers")
                Text("Input mode").fixedSize()
                Picker("Input mode", selection: Binding(get: { model.inputConfiguration.mode }, set: { model.setInputMode($0) })) {
                    Text("Single").tag(InputMode.single)
                    Text("XYZ").tag(InputMode.xyz)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 145)
                .disabled(model.isEnabled)
            }
            if model.inputConfiguration.mode == .single {
                AxisInputRow(model: model, axis: .x)
                Text("All targets follow the single input. Stored Y/Z assignments are retained.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(InputAxis.allCases, id: \.self) { axis in
                    AxisInputRow(model: model, axis: axis)
                }
                Text("Assign each target to X, Y or Z. Pause before changing inputs or routing.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(model.inputIssues, id: \.self) { issue in
                Text(issue).font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A nil axis edits the dedicated touch gate rather than a coordinate.
struct AxisInputRow: View {
    @ObservedObject var model: AppModel
    let axis: InputAxis?
    @State private var showsEditor = false
    @State private var channel = 1
    @State private var controller = 0

    private var label: String { axis?.label ?? "Touch Gate" }
    private var binding: MIDICCBinding? {
        if let axis { return model.inputConfiguration.binding(for: axis) }
        return model.inputConfiguration.touchGate
    }
    private var learning: Bool {
        model.isLearning && (axis == nil ? model.isLearningGate : !model.isLearningGate && model.learningAxis == axis)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(label).font(.headline).frame(width: axis == nil ? 90 : 24, alignment: .leading)
                Text(binding?.description ?? "Not learned")
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 165, alignment: .leading)
                if let axis {
                    Text(model.inputState.value(for: axis).map { String($0) } ?? "—")
                        .monospacedDigit().foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .trailing)
                        .accessibilityLabel("\(label) input value")
                }
                Spacer(minLength: 4)
                Button("Edit") {
                    showsEditor = true
                }
                .buttonStyle(LearnActionButtonStyle())
                .disabled(model.isEnabled || model.isLearning)
                .help(model.isEnabled ? "Pause before editing input bindings" : model.isLearning
                    ? "Finish or cancel learning before editing input bindings"
                    : "Enter the MIDI channel and CC for \(label)")
                .accessibilityLabel("Edit \(label) MIDI input")
                .popover(isPresented: $showsEditor) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("\(label) MIDI input").font(.headline)
                        Stepper("Channel \(channel)", value: $channel, in: 1...16)
                        Stepper("CC \(controller)", value: $controller, in: 0...127)
                        Text("Use the CC and channel configured on your controller.")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("Cancel") { showsEditor = false }
                                .buttonStyle(LearnActionButtonStyle())
                            Spacer()
                            Button("Apply") {
                                let proposed = MIDICCBinding(channel: channel - 1, controller: controller)
                                let accepted = axis.map { model.setInputBinding(proposed, for: $0) } ?? model.setTouchGate(proposed)
                                if accepted { showsEditor = false }
                            }
                            .buttonStyle(LearnActionButtonStyle(primary: true))
                            .keyboardShortcut(.defaultAction)
                        }
                        if let issue = model.inputIssues.first {
                            Text(issue).font(.caption).foregroundStyle(.orange)
                        }
                    }
                    .padding(20).frame(width: 300)
                    .onAppear {
                        // Seed the presented content after SwiftUI installs its state.
                        channel = (binding?.channel ?? 0) + 1
                        controller = binding?.controller ?? 0
                    }
                }
                Button {
                    if learning { model.cancelLearning() }
                    else if let axis { model.beginLearning(axis: axis) }
                    else { model.beginGateLearning() }
                } label: {
                    Label(learning ? "Cancel Learn" : "MIDI Learn",
                          systemImage: learning ? "xmark.circle" : "dot.radiowaves.left.and.right")
                }
                .buttonStyle(LearnActionButtonStyle(primary: true))
                .disabled(model.isEnabled || !model.isConnected)
                .help(model.isEnabled ? "Pause before learning input bindings" : !model.isConnected
                    ? "Connect and select a MIDI controller first"
                    : learning ? "Cancel learning and keep the current binding"
                    : "Move only \(label), then confirm the detected MIDI CC")
                .accessibilityLabel(learning ? "Cancel \(label) input learning" : "Learn \(label) MIDI input")
            }
            if learning {
                HStack(spacing: 12) {
                    if let candidate = model.learningCandidate {
                        Text("\(candidate.description) · Value \(model.learningCandidateValue ?? 0)")
                            .font(.system(.callout, design: .monospaced))
                        Spacer()
                        Button("Use for \(label)") { model.confirmLearning() }
                            .buttonStyle(LearnActionButtonStyle(primary: true))
                        Button("Try Again") {
                            if let axis { model.beginLearning(axis: axis) } else { model.beginGateLearning() }
                        }
                        .buttonStyle(LearnActionButtonStyle())
                    } else {
                        Text("Move only \(label). Check the detected CC before confirming.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct TouchGateEditor: View {
    @ObservedObject var model: AppModel
    @State private var confirmsDisable = false
    @State private var confirmsReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.inputConfiguration.mode == .xyz {
                AxisInputRow(model: model, axis: nil)
                Text("Optional: a dedicated CC sends 0 on release and 1–127 on touch. Send fresh axis values after touch-on.")
                    .font(.caption).foregroundStyle(.secondary)
                if model.inputConfiguration.touchGate != nil {
                    Button("Disable Touch Gate") {
                        if !model.disableTouchGate(confirmPolicyReset: false) { confirmsDisable = true }
                    }.disabled(model.isEnabled)
                }
            }
            Button("Reset Input Settings…") { confirmsReset = true }
                .disabled(model.isEnabled)
                .help("Clear input bindings and return to Single mode; target MIDI assignments stay in place")
        }
        .alert("Disable Touch Gate?", isPresented: $confirmsDisable) {
            Button("Cancel", role: .cancel) {}
            Button("Disable and Use Hold", role: .destructive) { model.disableTouchGate(confirmPolicyReset: true) }
        } message: { Text("Targets using Return Value on release will change to Hold.") }
        .alert("Reset Input Settings?", isPresented: $confirmsReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { model.resetInputConfiguration() }
        } message: { Text("This clears learned inputs and Touch Gate, and returns to Single mode. Target mappings and saved presets are kept. Learn an input again before activating.") }
    }
}
