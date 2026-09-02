#include "CrossfadeEngine.h"
#include "PluginProcessor.h"
#include "SharedBus.h"

#include <cmath>
#include <cstdlib>
#include <iostream>
#include <string>

namespace {

void require(bool condition, const std::string& message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        std::exit(1);
    }
}

void requireNear(float actual, float expected, float tolerance, const std::string& message) {
    require(std::abs(actual - expected) <= tolerance, message);
}

void setPlainParameter(
    MKCrossfaderProcessor& processor,
    const char* id,
    float value
) {
    auto* parameter = processor.state.getParameter(id);
    require(parameter != nullptr, std::string("Missing parameter: ") + id);
    parameter->setValueNotifyingHost(parameter->convertTo0to1(value));
}

void fillWithOnes(juce::AudioBuffer<float>& buffer) {
    for (auto channel = 0; channel < buffer.getNumChannels(); ++channel) {
        for (auto sample = 0; sample < buffer.getNumSamples(); ++sample) {
            buffer.setSample(channel, sample, 1.0f);
        }
    }
}

void process(MKCrossfaderProcessor& processor, juce::AudioBuffer<float>& buffer) {
    juce::MidiBuffer midi;
    fillWithOnes(buffer);
    processor.processBlock(buffer, midi);
}

void writeSnapshot(juce::AudioProcessorEditor& editor, const char* path) {
    const auto image = editor.createComponentSnapshot(
        editor.getLocalBounds(),
        true,
        1.0f
    );
    juce::MemoryOutputStream encoded;
    juce::PNGImageFormat png;
    require(png.writeImageToStream(image, encoded), "Could not encode editor snapshot");
    require(
        juce::File(path).replaceWithData(encoded.getData(), encoded.getDataSize()),
        "Could not write editor snapshot"
    );
}

void testEngine() {
    std::array<mkxf::SlotConfig, mkxf::targetCount> slots{};
    slots[0].assignment = mkxf::Assignment::sideA;
    slots[1].assignment = mkxf::Assignment::sideB;

    const auto left = mkxf::renderFrame(
        0.0f,
        mkxf::Mode::standard,
        mkxf::Curve::fullCentre,
        mkxf::Minimum::kill,
        false,
        false,
        slots
    );
    requireNear(left[0], 1.0f, 1.0e-6f, "A was not unity at the left endpoint");
    requireNear(left[1], 0.0f, 1.0e-6f, "B was not killed at the left endpoint");

    const auto centre = mkxf::renderFrame(
        63.5f / 127.0f,
        mkxf::Mode::standard,
        mkxf::Curve::fullCentre,
        mkxf::Minimum::kill,
        false,
        false,
        slots
    );
    requireNear(centre[0], 1.0f, 1.0e-6f, "A was not unity at centre");
    requireNear(centre[1], 1.0f, 1.0e-6f, "B was not unity at centre");

    const auto layerToB = mkxf::renderFrame(
        0.0f,
        mkxf::Mode::layerToB,
        mkxf::Curve::linear,
        mkxf::Minimum::kill,
        false,
        false,
        slots
    );
    requireNear(layerToB[0], 1.0f, 1.0e-6f, "A+B to B changed A at left");
    requireNear(layerToB[1], 1.0f, 1.0e-6f, "A+B to B did not keep B at unity");

    const auto layerToA = mkxf::renderFrame(
        1.0f,
        mkxf::Mode::layerToA,
        mkxf::Curve::linear,
        mkxf::Minimum::kill,
        false,
        false,
        slots
    );
    requireNear(layerToA[0], 1.0f, 1.0e-6f, "A+B to A did not keep A at unity");
    requireNear(layerToA[1], 0.0f, 1.0e-6f, "A+B to A did not remove B at right");

    const auto pairFade = mkxf::renderFrame(
        1.0f,
        mkxf::Mode::pairFade,
        mkxf::Curve::linear,
        mkxf::Minimum::minus18,
        false,
        false,
        slots
    );
    requireNear(
        pairFade[0],
        mkxf::minimumGain(mkxf::Minimum::minus18),
        1.0e-6f,
        "Pair fade did not honour its minimum"
    );
    requireNear(pairFade[0], pairFade[1], 1.0e-6f, "Pair fade sides diverged");

    slots[2] = {mkxf::Assignment::off, 0.2f, 0.8f};
    const auto custom = mkxf::renderFrame(
        0.5f,
        mkxf::Mode::customScene,
        mkxf::Curve::linear,
        mkxf::Minimum::kill,
        false,
        false,
        slots
    );
    requireNear(custom[2], 0.5f, 1.0e-6f, "Custom Scene interpolation failed");

    const auto flipped = mkxf::renderFrame(
        0.0f,
        mkxf::Mode::standard,
        mkxf::Curve::linear,
        mkxf::Minimum::kill,
        false,
        true,
        slots
    );
    requireNear(flipped[0], 0.0f, 1.0e-6f, "Flip Travel did not reverse A");
    requireNear(flipped[1], 1.0f, 1.0e-6f, "Flip Travel did not reverse B");
}

void testSharedBus() {
    const auto now = mkxf::SharedBus::monotonicMilliseconds();
    mkxf::SharedBus controller(8, 0x11001);
    mkxf::SharedBus target(8, 0x22002);
    mkxf::SharedBus duplicate(8, 0x33003);
    require(controller.isAvailable(), "Controller shared bus was unavailable");
    require(target.isAvailable(), "Target shared bus was unavailable");
    require(
        controller.claimController(now) == mkxf::ClaimResult::owned,
        "Controller could not claim its session"
    );
    require(
        duplicate.claimController(now) == mkxf::ClaimResult::conflict,
        "Duplicate Controller was not rejected"
    );
    require(
        target.claimTarget(4, now) == mkxf::ClaimResult::owned,
        "Target could not claim its slot"
    );
    require(
        duplicate.claimTarget(4, now) == mkxf::ClaimResult::conflict,
        "Duplicate Target slot was not rejected"
    );

    mkxf::GainFrame frame{};
    frame.fill(1.0f);
    frame[4] = 0.25f;
    require(controller.publish(frame, false, now), "Controller frame was not published");
    const auto read = target.read(now);
    require(read.connected, "Target did not see the Controller frame");
    requireNear(read.gains[4], 0.25f, 1.0e-6f, "Shared gain changed in transit");

    require(controller.publish(frame, true, now), "Unity frame was not published");
    require(target.read(now).unityOverride, "Unity override did not cross the bus");
}

void testProcessorPair() {
    MKCrossfaderProcessor controller;
    MKCrossfaderProcessor target;
    MKCrossfaderProcessor duplicateTarget;
    setPlainParameter(target, "role", 1.0f);
    setPlainParameter(duplicateTarget, "role", 1.0f);
    for (auto* processor : { &controller, &target, &duplicateTarget }) {
        setPlainParameter(*processor, "session", 7.0f);
    }
    require(
        controller.configuredTargetCount() == 2,
        "Default Controller routes were not counted"
    );
    setPlainParameter(controller, "mode", 4.0f);
    require(
        controller.configuredTargetCount() == 2,
        "Default Custom Scene routes were not counted"
    );
    setPlainParameter(controller, "mode", 0.0f);

    controller.prepareToPlay(48000.0, 1024);
    target.prepareToPlay(48000.0, 1024);
    duplicateTarget.prepareToPlay(48000.0, 1024);
    juce::AudioBuffer<float> controllerAudio(2, 1024);
    juce::AudioBuffer<float> targetAudio(2, 1024);
    juce::AudioBuffer<float> duplicateAudio(2, 1024);

    setPlainParameter(controller, "crossfader", 1.0f);
    process(controller, controllerAudio);
    require(target.controllerAvailable(), "Target could not detect its Controller");
    requireNear(
        controllerAudio.getSample(0, 1023),
        1.0f,
        1.0e-6f,
        "Controller did not pass audio unchanged"
    );
    process(target, targetAudio);
    requireNear(
        targetAudio.getSample(0, 1023),
        0.0f,
        1.0e-5f,
        "Target did not reach silence for A at the right endpoint"
    );
    require(
        target.runtimeStatus() == MKCrossfaderProcessor::RuntimeStatus::targetConnected,
        "Target did not report connected"
    );

    process(duplicateTarget, duplicateAudio);
    require(
        duplicateTarget.runtimeStatus()
            == MKCrossfaderProcessor::RuntimeStatus::targetConflict,
        "Duplicate Target did not report a slot conflict"
    );
    requireNear(
        duplicateAudio.getSample(0, 1023),
        1.0f,
        1.0e-5f,
        "Duplicate Target did not remain at unity"
    );

    setPlainParameter(controller, "safeUnity", 1.0f);
    process(controller, controllerAudio);
    process(target, targetAudio);
    requireNear(
        targetAudio.getSample(0, 1023),
        1.0f,
        1.0e-5f,
        "Controller Unity override did not reach the Target"
    );
}

void testStateAndEditor() {
    MKCrossfaderProcessor processor;
    setPlainParameter(processor, "role", 1.0f);
    setPlainParameter(processor, "session", 2.0f);
    setPlainParameter(processor, "targetSlot", 6.0f);
    setPlainParameter(processor, "colourA", static_cast<float>(0x00ff4f68));
    processor.setSlotLabel(6, "Percussion Bus");
    juce::MemoryBlock savedState;
    processor.getStateInformation(savedState);

    MKCrossfaderProcessor restored;
    restored.setStateInformation(savedState.getData(), static_cast<int>(savedState.getSize()));
    requireNear(
        restored.state.getRawParameterValue("role")->load(),
        1.0f,
        1.0e-6f,
        "Role state was not restored"
    );
    requireNear(
        restored.state.getRawParameterValue("session")->load(),
        2.0f,
        1.0e-6f,
        "Session state was not restored"
    );
    require(restored.slotLabel(6) == "Percussion Bus", "Target label was not restored");

    std::unique_ptr<juce::AudioProcessorEditor> editor(restored.createEditor());
    require(editor != nullptr, "Editor was not created");
    require(editor->getWidth() == 820 && editor->getHeight() == 620, "Editor size changed");

    if (const auto* snapshotPath = std::getenv("MK_CROSSFADER_SNAPSHOT_PATH")) {
        writeSnapshot(*editor, snapshotPath);
    }
    if (const auto* snapshotPath = std::getenv(
            "MK_CROSSFADER_CONTROLLER_SNAPSHOT_PATH"
        )) {
        MKCrossfaderProcessor controller;
        std::unique_ptr<juce::AudioProcessorEditor> controllerEditor(
            controller.createEditor()
        );
        writeSnapshot(*controllerEditor, snapshotPath);
    }
    if (const auto* snapshotPath = std::getenv(
            "MK_CROSSFADER_CUSTOM_SNAPSHOT_PATH"
        )) {
        MKCrossfaderProcessor controller;
        setPlainParameter(controller, "mode", 4.0f);
        std::unique_ptr<juce::AudioProcessorEditor> controllerEditor(
            controller.createEditor()
        );
        writeSnapshot(*controllerEditor, snapshotPath);
    }
}

} // namespace

int main() {
    juce::ScopedJuceInitialiser_GUI juceInitialiser;
    testEngine();
    testSharedBus();
    testProcessorPair();
    testStateAndEditor();
    std::cout << "MK Crossfader tests passed\n";
    return 0;
}
