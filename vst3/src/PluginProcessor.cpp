#include "PluginProcessor.h"
#include "PluginEditor.h"

#include <cmath>

#include <juce_audio_utils/juce_audio_utils.h>

namespace {

juce::ParameterID parameterId(const juce::String& id) {
    return { id, 1 };
}

} // namespace

MKCrossfaderProcessor::MKCrossfaderProcessor()
    : AudioProcessor(
          BusesProperties()
              .withInput("Input", juce::AudioChannelSet::stereo(), true)
              .withOutput("Output", juce::AudioChannelSet::stereo(), true)
      ),
      state(*this, nullptr, "MKCrossfaderState", createParameters()),
      instanceToken(mkxf::SharedBus::makeInstanceToken(this)) {
    roleParameter = state.getRawParameterValue("role");
    sessionParameter = state.getRawParameterValue("session");
    targetSlotParameter = state.getRawParameterValue("targetSlot");
    safeUnityParameter = state.getRawParameterValue("safeUnity");
    crossfaderParameter = state.getRawParameterValue("crossfader");
    modeParameter = state.getRawParameterValue("mode");
    curveParameter = state.getRawParameterValue("curve");
    minimumParameter = state.getRawParameterValue("minimum");
    swapParameter = state.getRawParameterValue("swap");
    flipParameter = state.getRawParameterValue("flip");
    for (auto session = 0; session < static_cast<int>(buses.size()); ++session) {
        buses[static_cast<std::size_t>(session)] =
            std::make_unique<mkxf::SharedBus>(session + 1, instanceToken);
    }
    for (auto slot = 0; slot < static_cast<int>(mkxf::targetCount); ++slot) {
        slotParameters[static_cast<std::size_t>(slot)] = {
            state.getRawParameterValue(slotParameterId(slot, "Assignment")),
            state.getRawParameterValue(slotParameterId(slot, "Left")),
            state.getRawParameterValue(slotParameterId(slot, "Right"))
        };
        state.state.setProperty(
            "slotLabel" + juce::String(slot + 1),
            "Target " + juce::String(slot + 1),
            nullptr
        );
    }
}

MKCrossfaderProcessor::~MKCrossfaderProcessor() {
    releaseActiveClaim();
}

juce::AudioProcessorValueTreeState::ParameterLayout
MKCrossfaderProcessor::createParameters() {
    std::vector<std::unique_ptr<juce::RangedAudioParameter>> parameters;
    juce::StringArray sessions;
    juce::StringArray targetSlots;
    for (auto value = 1; value <= 16; ++value) {
        if (value <= 8) {
            sessions.add(juce::String(value));
        }
        targetSlots.add(juce::String(value));
    }
    parameters.push_back(std::make_unique<juce::AudioParameterChoice>(
        parameterId("role"),
        "Role",
        juce::StringArray{ "Controller", "Target" },
        0
    ));
    parameters.push_back(std::make_unique<juce::AudioParameterChoice>(
        parameterId("session"), "Session", sessions, 0
    ));
    parameters.push_back(std::make_unique<juce::AudioParameterChoice>(
        parameterId("targetSlot"), "Target Slot", targetSlots, 0
    ));
    parameters.push_back(std::make_unique<juce::AudioParameterBool>(
        parameterId("safeUnity"), "Unity Override", false
    ));
    parameters.push_back(std::make_unique<juce::AudioParameterFloat>(
        parameterId("crossfader"),
        "Crossfader",
        juce::NormalisableRange<float>(0.0f, 1.0f, 0.0001f),
        0.0f
    ));
    parameters.push_back(std::make_unique<juce::AudioParameterChoice>(
        parameterId("mode"),
        "Mode",
        juce::StringArray{
            "A to B", "A+B to B", "A+B to A", "A+B to Floor", "Custom Scene"
        },
        0
    ));
    parameters.push_back(std::make_unique<juce::AudioParameterChoice>(
        parameterId("curve"),
        "Curve",
        juce::StringArray{
            "Full at Centre", "Linear", "Smooth", "Wide Blend", "Fast Cut"
        },
        0
    ));
    parameters.push_back(std::make_unique<juce::AudioParameterChoice>(
        parameterId("minimum"),
        "Floor",
        juce::StringArray{ "Kill", "-24 dB", "-18 dB", "-14 dB" },
        0
    ));
    parameters.push_back(std::make_unique<juce::AudioParameterBool>(
        parameterId("swap"), "Swap A/B", false
    ));
    parameters.push_back(std::make_unique<juce::AudioParameterBool>(
        parameterId("flip"), "Flip Travel", false
    ));
    parameters.push_back(std::make_unique<juce::AudioParameterInt>(
        parameterId("colourA"), "A Colour", 0, 0x00ffffff, 0x00e5484d
    ));
    parameters.push_back(std::make_unique<juce::AudioParameterInt>(
        parameterId("colourB"), "B Colour", 0, 0x00ffffff, 0x00c5c7ca
    ));

    for (auto slot = 0; slot < static_cast<int>(mkxf::targetCount); ++slot) {
        const auto assignment = slot == 0 ? 1 : (slot == 1 ? 2 : 0);
        const auto left = slot == 1 ? 0.0f : 100.0f;
        const auto right = slot == 0 ? 0.0f : 100.0f;
        parameters.push_back(std::make_unique<juce::AudioParameterChoice>(
            parameterId(slotParameterId(slot, "Assignment")),
            "Target " + juce::String(slot + 1) + " Side",
            juce::StringArray{ "Off", "A", "B" },
            assignment
        ));
        parameters.push_back(std::make_unique<juce::AudioParameterFloat>(
            parameterId(slotParameterId(slot, "Left")),
            "Target " + juce::String(slot + 1) + " Left",
            juce::NormalisableRange<float>(0.0f, 100.0f, 1.0f),
            left,
            juce::AudioParameterFloatAttributes().withLabel("%")
        ));
        parameters.push_back(std::make_unique<juce::AudioParameterFloat>(
            parameterId(slotParameterId(slot, "Right")),
            "Target " + juce::String(slot + 1) + " Right",
            juce::NormalisableRange<float>(0.0f, 100.0f, 1.0f),
            right,
            juce::AudioParameterFloatAttributes().withLabel("%")
        ));
    }
    return { parameters.begin(), parameters.end() };
}

void MKCrossfaderProcessor::prepareToPlay(
    double sampleRate,
    int maximumExpectedSamplesPerBlock
) {
    juce::ignoreUnused(maximumExpectedSamplesPerBlock);
    gainSmoother.reset(sampleRate, 0.015);
    gainSmoother.setCurrentAndTargetValue(1.0f);
    displayedGain.store(1.0f, std::memory_order_relaxed);
    hasConnected = false;
    lastConnectedGain = 1.0f;
}

void MKCrossfaderProcessor::releaseResources() {
    releaseActiveClaim();
}

bool MKCrossfaderProcessor::isBusesLayoutSupported(
    const BusesLayout& layouts
) const {
    const auto input = layouts.getMainInputChannelSet();
    return input == layouts.getMainOutputChannelSet()
        && (input == juce::AudioChannelSet::mono()
            || input == juce::AudioChannelSet::stereo());
}

void MKCrossfaderProcessor::processBlock(
    juce::AudioBuffer<float>& buffer,
    juce::MidiBuffer& midi
) {
    juce::ScopedNoDenormals noDenormals;
    juce::ignoreUnused(midi);

    const auto inputChannels = getTotalNumInputChannels();
    const auto outputChannels = getTotalNumOutputChannels();
    const auto samples = buffer.getNumSamples();
    for (auto channel = inputChannels; channel < outputChannels; ++channel) {
        buffer.clear(channel, 0, samples);
    }

    const auto role = juce::roundToInt(roleParameter->load(std::memory_order_relaxed));
    const auto session = juce::jlimit(
        1,
        8,
        juce::roundToInt(sessionParameter->load(std::memory_order_relaxed)) + 1
    );
    const auto slot = juce::jlimit(
        0,
        static_cast<int>(mkxf::targetCount) - 1,
        juce::roundToInt(targetSlotParameter->load(std::memory_order_relaxed))
    );
    const auto unity = safeUnityParameter->load(std::memory_order_relaxed) >= 0.5f;
    auto& bus = *buses[static_cast<std::size_t>(session - 1)];
    const auto now = mkxf::SharedBus::monotonicMilliseconds();

    if (role != claimedRole || session != claimedSession
        || (role == 1 && slot != claimedSlot)) {
        releaseActiveClaim();
        hasConnected = false;
        lastConnectedGain = 1.0f;
    }

    auto targetGain = 1.0f;
    if (role == 0) {
        const auto claim = bus.claimController(now);
        claimedRole = 0;
        claimedSession = session;
        claimedSlot = -1;
        activeTargets.store(bus.activeTargetCount(now), std::memory_order_relaxed);

        if (claim == mkxf::ClaimResult::owned) {
            const auto frame = mkxf::renderFrame(
                crossfaderParameter->load(std::memory_order_relaxed),
                static_cast<mkxf::Mode>(
                    juce::roundToInt(modeParameter->load(std::memory_order_relaxed))
                ),
                static_cast<mkxf::Curve>(
                    juce::roundToInt(curveParameter->load(std::memory_order_relaxed))
                ),
                static_cast<mkxf::Minimum>(
                    juce::roundToInt(minimumParameter->load(std::memory_order_relaxed))
                ),
                swapParameter->load(std::memory_order_relaxed) >= 0.5f,
                flipParameter->load(std::memory_order_relaxed) >= 0.5f,
                readSlots()
            );
            bus.publish(frame, unity, now);
            status.store(
                static_cast<int>(unity ? RuntimeStatus::unityOverride
                                       : RuntimeStatus::controllerActive),
                std::memory_order_relaxed
            );
        } else {
            status.store(
                static_cast<int>(
                    claim == mkxf::ClaimResult::conflict
                        ? RuntimeStatus::controllerConflict
                        : RuntimeStatus::busUnavailable
                ),
                std::memory_order_relaxed
            );
        }
    } else {
        const auto claim = bus.claimTarget(static_cast<std::size_t>(slot), now);
        claimedRole = 1;
        claimedSession = session;
        claimedSlot = slot;
        activeTargets.store(0, std::memory_order_relaxed);

        if (claim == mkxf::ClaimResult::owned) {
            const auto frame = bus.read(now);
            if (unity) {
                targetGain = 1.0f;
                status.store(
                    static_cast<int>(RuntimeStatus::unityOverride),
                    std::memory_order_relaxed
                );
            } else if (frame.connected) {
                targetGain = frame.unityOverride
                    ? 1.0f
                    : juce::jlimit(0.0f, 1.0f, frame.gains[static_cast<std::size_t>(slot)]);
                hasConnected = true;
                lastConnectedGain = targetGain;
                status.store(
                    static_cast<int>(
                        frame.unityOverride ? RuntimeStatus::unityOverride
                                            : RuntimeStatus::targetConnected
                    ),
                    std::memory_order_relaxed
                );
            } else if (hasConnected) {
                targetGain = lastConnectedGain;
                status.store(
                    static_cast<int>(RuntimeStatus::staleHold),
                    std::memory_order_relaxed
                );
            } else {
                targetGain = 1.0f;
                status.store(
                    static_cast<int>(RuntimeStatus::waiting),
                    std::memory_order_relaxed
                );
            }
        } else {
            targetGain = 1.0f;
            status.store(
                static_cast<int>(
                    claim == mkxf::ClaimResult::conflict
                        ? RuntimeStatus::targetConflict
                        : RuntimeStatus::busUnavailable
                ),
                std::memory_order_relaxed
            );
        }
    }

    gainSmoother.setTargetValue(role == 0 ? 1.0f : targetGain);
    const auto channels = juce::jmin(inputChannels, buffer.getNumChannels());
    for (auto sample = 0; sample < samples; ++sample) {
        const auto gain = gainSmoother.getNextValue();
        for (auto channel = 0; channel < channels; ++channel) {
            buffer.setSample(
                channel,
                sample,
                buffer.getSample(channel, sample) * gain
            );
        }
    }
    displayedGain.store(gainSmoother.getCurrentValue(), std::memory_order_relaxed);
}

void MKCrossfaderProcessor::getStateInformation(
    juce::MemoryBlock& destinationData
) {
    if (const auto xml = state.copyState().createXml()) {
        copyXmlToBinary(*xml, destinationData);
    }
}

void MKCrossfaderProcessor::setStateInformation(
    const void* data,
    int sizeInBytes
) {
    if (const auto xml = getXmlFromBinary(data, sizeInBytes)) {
        const auto restored = juce::ValueTree::fromXml(*xml);
        if (restored.isValid() && restored.hasType(state.state.getType())) {
            state.replaceState(restored);
        }
    }
}

juce::String MKCrossfaderProcessor::slotLabel(int slot) const {
    const auto safeSlot = juce::jlimit(0, static_cast<int>(mkxf::targetCount) - 1, slot);
    return state.state.getProperty(
        "slotLabel" + juce::String(safeSlot + 1),
        "Target " + juce::String(safeSlot + 1)
    ).toString();
}

int MKCrossfaderProcessor::configuredTargetCount() const noexcept {
    const auto customScene = juce::roundToInt(
        modeParameter->load(std::memory_order_relaxed)
    ) == static_cast<int>(mkxf::Mode::customScene);
    auto configured = 0;
    for (const auto& slot : slotParameters) {
        if (customScene) {
            const auto left = slot.left->load(std::memory_order_relaxed);
            const auto right = slot.right->load(std::memory_order_relaxed);
            if (std::abs(left - 100.0f) > 0.01f
                || std::abs(right - 100.0f) > 0.01f) {
                ++configured;
            }
        } else if (juce::roundToInt(
                       slot.assignment->load(std::memory_order_relaxed)
                   ) != static_cast<int>(mkxf::Assignment::off)) {
            ++configured;
        }
    }
    return configured;
}

bool MKCrossfaderProcessor::controllerAvailable() const noexcept {
    const auto session = juce::jlimit(
        1,
        8,
        juce::roundToInt(sessionParameter->load(std::memory_order_relaxed)) + 1
    );
    return buses[static_cast<std::size_t>(session - 1)]->read(
        mkxf::SharedBus::monotonicMilliseconds()
    ).connected;
}

void MKCrossfaderProcessor::setSlotLabel(
    int slot,
    const juce::String& label
) {
    const auto safeSlot = juce::jlimit(0, static_cast<int>(mkxf::targetCount) - 1, slot);
    const auto clean = label.trim().substring(0, 24);
    state.state.setProperty(
        "slotLabel" + juce::String(safeSlot + 1),
        clean.isEmpty() ? "Target " + juce::String(safeSlot + 1) : clean,
        nullptr
    );
}

juce::String MKCrossfaderProcessor::slotParameterId(
    int slot,
    const char* suffix
) {
    return "slot" + juce::String(slot + 1) + suffix;
}

void MKCrossfaderProcessor::releaseActiveClaim() noexcept {
    if (claimedSession < 1 || claimedSession > 8) {
        claimedRole = -1;
        claimedSession = -1;
        claimedSlot = -1;
        return;
    }
    auto& bus = *buses[static_cast<std::size_t>(claimedSession - 1)];
    if (claimedRole == 0) {
        bus.releaseController();
    } else if (claimedRole == 1 && claimedSlot >= 0) {
        bus.releaseTarget(static_cast<std::size_t>(claimedSlot));
    }
    claimedRole = -1;
    claimedSession = -1;
    claimedSlot = -1;
}

std::array<mkxf::SlotConfig, mkxf::targetCount>
MKCrossfaderProcessor::readSlots() const noexcept {
    std::array<mkxf::SlotConfig, mkxf::targetCount> slots{};
    for (auto slot = 0; slot < static_cast<int>(slots.size()); ++slot) {
        const auto& parameters = slotParameters[static_cast<std::size_t>(slot)];
        slots[static_cast<std::size_t>(slot)] = {
            static_cast<mkxf::Assignment>(juce::roundToInt(
                parameters.assignment->load(std::memory_order_relaxed)
            )),
            parameters.left->load(std::memory_order_relaxed) / 100.0f,
            parameters.right->load(std::memory_order_relaxed) / 100.0f
        };
    }
    return slots;
}

juce::AudioProcessorEditor* MKCrossfaderProcessor::createEditor() {
    return new MKCrossfaderEditor(*this);
}

juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter() {
    return new MKCrossfaderProcessor();
}
