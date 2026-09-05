#pragma once

#include "CrossfadeEngine.h"
#include "SharedBus.h"

#include <array>
#include <atomic>
#include <memory>

#include <juce_audio_processors/juce_audio_processors.h>

class MKCrossfaderProcessor final : public juce::AudioProcessor {
public:
    enum class RuntimeStatus : int {
        waiting = 0,
        controllerActive,
        targetConnected,
        unityOverride,
        staleHold,
        controllerConflict,
        targetConflict,
        busUnavailable
    };

    MKCrossfaderProcessor();
    ~MKCrossfaderProcessor() override;

    void prepareToPlay(double sampleRate, int maximumExpectedSamplesPerBlock) override;
    void releaseResources() override;
    bool isBusesLayoutSupported(const BusesLayout& layouts) const override;
    void processBlock(juce::AudioBuffer<float>& buffer, juce::MidiBuffer& midi) override;

    juce::AudioProcessorEditor* createEditor() override;
    bool hasEditor() const override { return true; }

    const juce::String getName() const override { return "MK Crossfader"; }
    bool acceptsMidi() const override { return false; }
    bool producesMidi() const override { return false; }
    bool isMidiEffect() const override { return false; }
    double getTailLengthSeconds() const override { return 0.0; }

    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String&) override {}

    void getStateInformation(juce::MemoryBlock& destinationData) override;
    void setStateInformation(const void* data, int sizeInBytes) override;

    [[nodiscard]] float currentGain() const noexcept {
        return displayedGain.load(std::memory_order_relaxed);
    }
    [[nodiscard]] RuntimeStatus runtimeStatus() const noexcept {
        return static_cast<RuntimeStatus>(status.load(std::memory_order_relaxed));
    }
    [[nodiscard]] int connectedTargetCount() const noexcept {
        return activeTargets.load(std::memory_order_relaxed);
    }
    [[nodiscard]] int configuredTargetCount() const noexcept;
    [[nodiscard]] bool controllerAvailable() const noexcept;
    [[nodiscard]] juce::String slotLabel(int slot) const;
    void setSlotLabel(int slot, const juce::String& label);

    static juce::String slotParameterId(int slot, const char* suffix);

    juce::AudioProcessorValueTreeState state;

private:
    struct SlotParameters {
        std::atomic<float>* assignment{nullptr};
        std::atomic<float>* left{nullptr};
        std::atomic<float>* right{nullptr};
    };

    static juce::AudioProcessorValueTreeState::ParameterLayout createParameters();
    void releaseActiveClaim() noexcept;
    std::array<mkxf::SlotConfig, mkxf::targetCount> readSlots() const noexcept;

    std::array<std::unique_ptr<mkxf::SharedBus>, 8> buses;
    std::atomic<float>* roleParameter{nullptr};
    std::atomic<float>* sessionParameter{nullptr};
    std::atomic<float>* targetSlotParameter{nullptr};
    std::atomic<float>* safeUnityParameter{nullptr};
    std::atomic<float>* crossfaderParameter{nullptr};
    std::atomic<float>* modeParameter{nullptr};
    std::atomic<float>* curveParameter{nullptr};
    std::atomic<float>* minimumParameter{nullptr};
    std::atomic<float>* swapParameter{nullptr};
    std::atomic<float>* flipParameter{nullptr};
    std::array<SlotParameters, mkxf::targetCount> slotParameters{};
    juce::SmoothedValue<float, juce::ValueSmoothingTypes::Linear> gainSmoother;
    std::atomic<float> displayedGain{1.0f};
    std::atomic<int> status{static_cast<int>(RuntimeStatus::waiting)};
    std::atomic<int> activeTargets{0};
    int claimedRole{-1};
    int claimedSession{-1};
    int claimedSlot{-1};
    bool hasConnected{false};
    float lastConnectedGain{1.0f};

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(MKCrossfaderProcessor)
};
