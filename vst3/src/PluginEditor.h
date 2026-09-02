#pragma once

#include <array>
#include <memory>

#include <juce_gui_basics/juce_gui_basics.h>

#include "PluginProcessor.h"

class MKCrossfaderLookAndFeel final : public juce::LookAndFeel_V4 {
public:
    MKCrossfaderLookAndFeel();

    void drawLinearSlider(
        juce::Graphics& graphics,
        int x,
        int y,
        int width,
        int height,
        float sliderPosition,
        float minimumSliderPosition,
        float maximumSliderPosition,
        juce::Slider::SliderStyle style,
        juce::Slider& slider
    ) override;
};

class MKCrossfaderTargetRow final
    : public juce::Component,
      private juce::TextEditor::Listener {
public:
    MKCrossfaderTargetRow(MKCrossfaderProcessor& processor, int targetIndex);
    ~MKCrossfaderTargetRow() override;

    void paint(juce::Graphics& graphics) override;
    void resized() override;
    void setCustomScene(bool shouldUseCustomScene);

private:
    void textEditorReturnKeyPressed(juce::TextEditor& editor) override;
    void textEditorFocusLost(juce::TextEditor& editor) override;
    void commitLabel();

    MKCrossfaderProcessor& owner;
    const int index;
    juce::Label numberLabel;
    juce::TextEditor nameEditor;
    juce::ComboBox assignmentBox;
    juce::Slider leftSlider;
    juce::Slider rightSlider;
    bool customScene{false};
    std::unique_ptr<juce::AudioProcessorValueTreeState::ComboBoxAttachment>
        assignmentAttachment;
    std::unique_ptr<juce::AudioProcessorValueTreeState::SliderAttachment>
        leftAttachment;
    std::unique_ptr<juce::AudioProcessorValueTreeState::SliderAttachment>
        rightAttachment;
};

class MKCrossfaderEditor final
    : public juce::AudioProcessorEditor,
      private juce::Timer {
public:
    explicit MKCrossfaderEditor(MKCrossfaderProcessor& crossfaderProcessor);
    ~MKCrossfaderEditor() override;

    void paint(juce::Graphics& graphics) override;
    void resized() override;

private:
    void timerCallback() override;
    void updateRoleVisibility();
    void updateModeVisibility();
    void updateRouteVisibility();
    void updateStatus();
    void updateColours();
    int compactRouteCount() const;
    void cycleColour(const char* parameterId);
    void configureCombo(
        juce::ComboBox& box,
        const juce::StringArray& choices
    );
    void configureLabel(juce::Label& label, const juce::String& text);

    MKCrossfaderProcessor& owner;
    MKCrossfaderLookAndFeel lookAndFeel;
    juce::TooltipWindow tooltip{this, 500};

    juce::Label roleLabel;
    juce::ComboBox roleBox;
    juce::Label sessionLabel;
    juce::ComboBox sessionBox;
    juce::ToggleButton unityButton{ "UNITY" };
    juce::Label statusLabel;

    juce::Component controllerView;
    juce::Slider crossfaderSlider;
    juce::Label crossfaderValue;
    juce::Label sideALabel;
    juce::Label sideBLabel;
    juce::Label modeLabel;
    juce::ComboBox modeBox;
    juce::Label curveLabel;
    juce::ComboBox curveBox;
    juce::Label minimumLabel;
    juce::ComboBox minimumBox;
    juce::ToggleButton swapButton{ "SWAP A/B" };
    juce::ToggleButton flipButton{ "REVERSE" };
    juce::TextButton colourAButton{ "A" };
    juce::TextButton colourBButton{ "B" };
    juce::Label activeTargetsLabel;
    juce::Label routesLabel;
    juce::TextButton routeScopeButton{ "SHOW ALL" };
    juce::Label assignmentLabel;
    juce::Label leftLabel;
    juce::Label rightLabel;
    juce::Viewport routesViewport;
    juce::Component routesContent;
    std::array<std::unique_ptr<MKCrossfaderTargetRow>, mkxf::targetCount> rows;

    juce::Component targetView;
    juce::Label targetSlotLabel;
    juce::ComboBox targetSlotBox;
    juce::Label targetGainTitle;
    juce::Label targetGainValue;
    juce::Label targetNameValue;

    std::unique_ptr<juce::AudioProcessorValueTreeState::ComboBoxAttachment>
        roleAttachment;
    std::unique_ptr<juce::AudioProcessorValueTreeState::ComboBoxAttachment>
        sessionAttachment;
    std::unique_ptr<juce::AudioProcessorValueTreeState::ButtonAttachment>
        unityAttachment;
    std::unique_ptr<juce::AudioProcessorValueTreeState::SliderAttachment>
        crossfaderAttachment;
    std::unique_ptr<juce::AudioProcessorValueTreeState::ComboBoxAttachment>
        modeAttachment;
    std::unique_ptr<juce::AudioProcessorValueTreeState::ComboBoxAttachment>
        curveAttachment;
    std::unique_ptr<juce::AudioProcessorValueTreeState::ComboBoxAttachment>
        minimumAttachment;
    std::unique_ptr<juce::AudioProcessorValueTreeState::ButtonAttachment>
        swapAttachment;
    std::unique_ptr<juce::AudioProcessorValueTreeState::ButtonAttachment>
        flipAttachment;
    std::unique_ptr<juce::AudioProcessorValueTreeState::ComboBoxAttachment>
        targetSlotAttachment;

    int visibleRole{-1};
    int visibleMode{-1};
    int visibleRouteCount{-1};
    bool showAllRoutes{false};

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(MKCrossfaderEditor)
};
