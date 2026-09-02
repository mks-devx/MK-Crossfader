#include "PluginEditor.h"

#include <array>
#include <cmath>

namespace {

constexpr auto background = 0xff121212;
constexpr auto surface = 0xff1d1d1d;
constexpr auto surfaceRaised = 0xff272727;
constexpr auto line = 0xff3a3838;
constexpr auto text = 0xfff1eeee;
constexpr auto secondaryText = 0xffaaa4a4;
constexpr auto brandRed = 0xffe5484d;
constexpr auto success = 0xff54d68b;
constexpr auto warning = 0xffffc857;
constexpr auto danger = 0xffff5d67;
constexpr int routeRowHeight = 42;
constexpr int compactRouteMinimum = 4;

float rawParameter(
    const juce::AudioProcessorValueTreeState& state,
    juce::StringRef id
) {
    return state.getRawParameterValue(id)->load(std::memory_order_relaxed);
}

juce::StringArray numberedChoices(int count) {
    juce::StringArray choices;
    for (auto value = 1; value <= count; ++value) {
        choices.add(juce::String(value));
    }
    return choices;
}

juce::Colour parameterColour(
    const juce::AudioProcessorValueTreeState& state,
    const char* id
) {
    const auto rgb = static_cast<juce::uint32>(
        juce::roundToInt(rawParameter(state, id))
    ) & 0x00ffffffu;
    return juce::Colour(0xff000000u | rgb);
}

} // namespace

MKCrossfaderLookAndFeel::MKCrossfaderLookAndFeel() {
    setColour(juce::ComboBox::backgroundColourId, juce::Colour(surfaceRaised));
    setColour(juce::ComboBox::outlineColourId, juce::Colour(line));
    setColour(juce::ComboBox::textColourId, juce::Colour(text));
    setColour(juce::ComboBox::arrowColourId, juce::Colour(secondaryText));
    setColour(juce::PopupMenu::backgroundColourId, juce::Colour(surfaceRaised));
    setColour(juce::PopupMenu::textColourId, juce::Colour(text));
    setColour(juce::PopupMenu::highlightedBackgroundColourId, juce::Colour(0xff404040));
    setColour(juce::TextButton::buttonColourId, juce::Colour(surfaceRaised));
    setColour(juce::TextButton::textColourOffId, juce::Colour(text));
    setColour(juce::ToggleButton::textColourId, juce::Colour(text));
    setColour(juce::Slider::textBoxTextColourId, juce::Colour(text));
    setColour(juce::Slider::textBoxBackgroundColourId, juce::Colour(surfaceRaised));
    setColour(juce::Slider::textBoxOutlineColourId, juce::Colour(line));
    setColour(juce::TextEditor::backgroundColourId, juce::Colour(surface));
    setColour(juce::TextEditor::textColourId, juce::Colour(text));
    setColour(juce::TextEditor::outlineColourId, juce::Colour(line));
    setColour(juce::TextEditor::focusedOutlineColourId, juce::Colour(secondaryText));
    setDefaultSansSerifTypefaceName("Avenir Next");
}

void MKCrossfaderLookAndFeel::drawLinearSlider(
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
) {
    juce::ignoreUnused(minimumSliderPosition, maximumSliderPosition);
    if (style != juce::Slider::LinearHorizontal) {
        LookAndFeel_V4::drawLinearSlider(
            graphics,
            x,
            y,
            width,
            height,
            sliderPosition,
            minimumSliderPosition,
            maximumSliderPosition,
            style,
            slider
        );
        return;
    }

    const auto centreY = static_cast<float>(y + height / 2);
    const auto startX = static_cast<float>(x + 7);
    const auto endX = static_cast<float>(x + width - 7);
    graphics.setColour(juce::Colour(line));
    graphics.fillRoundedRectangle(startX, centreY - 3.0f, endX - startX, 6.0f, 3.0f);

    if (static_cast<bool>(slider.getProperties()["mkCrossfader"])) {
        const auto centreX = (startX + endX) * 0.5f;
        graphics.setColour(juce::Colour(secondaryText).withAlpha(0.55f));
        graphics.fillRect(centreX - 0.5f, centreY - 8.0f, 1.0f, 16.0f);
        graphics.setColour(slider.findColour(juce::Slider::thumbColourId));
        graphics.fillEllipse(
            sliderPosition - 9.0f,
            centreY - 9.0f,
            18.0f,
            18.0f
        );
        graphics.setColour(juce::Colour(background));
        graphics.drawEllipse(
            sliderPosition - 5.0f,
            centreY - 5.0f,
            10.0f,
            10.0f,
            1.0f
        );
        return;
    }

    const auto accent = slider.findColour(juce::Slider::trackColourId);
    graphics.setColour(accent.withAlpha(0.75f));
    graphics.fillRoundedRectangle(
        startX,
        centreY - 3.0f,
        juce::jmax(0.0f, sliderPosition - startX),
        6.0f,
        3.0f
    );
    graphics.setColour(slider.findColour(juce::Slider::thumbColourId));
    graphics.fillEllipse(sliderPosition - 8.0f, centreY - 8.0f, 16.0f, 16.0f);
}

MKCrossfaderTargetRow::MKCrossfaderTargetRow(
    MKCrossfaderProcessor& processor,
    int targetIndex
) : owner(processor), index(targetIndex) {
    numberLabel.setText(juce::String(index + 1).paddedLeft('0', 2), juce::dontSendNotification);
    numberLabel.setJustificationType(juce::Justification::centredLeft);
    numberLabel.setColour(juce::Label::textColourId, juce::Colour(secondaryText));
    addAndMakeVisible(numberLabel);

    nameEditor.setText(owner.slotLabel(index), false);
    nameEditor.setSelectAllWhenFocused(true);
    nameEditor.setInputRestrictions(24);
    nameEditor.setTitle("Target name");
    nameEditor.setTooltip("Name for this target slot");
    nameEditor.addListener(this);
    addAndMakeVisible(nameEditor);

    assignmentBox.addItemList({ "Off", "A", "B" }, 1);
    assignmentBox.setTitle("Target side");
    assignmentBox.setTooltip("Assign this target to side A, side B, or Off");
    addAndMakeVisible(assignmentBox);

    for (auto* slider : { &leftSlider, &rightSlider }) {
        slider->setSliderStyle(juce::Slider::LinearHorizontal);
        slider->setTextBoxStyle(juce::Slider::TextBoxRight, false, 48, 22);
        slider->setRange(0.0, 100.0, 1.0);
        slider->setTextValueSuffix("%");
        slider->setNumDecimalPlacesToDisplay(0);
        slider->setColour(juce::Slider::trackColourId, juce::Colour(secondaryText));
        slider->setColour(juce::Slider::thumbColourId, juce::Colour(text));
        addAndMakeVisible(*slider);
    }
    leftSlider.setTitle("Left endpoint gain");
    rightSlider.setTitle("Right endpoint gain");
    leftSlider.setTooltip("Target gain at the left end of Custom Scene");
    rightSlider.setTooltip("Target gain at the right end of Custom Scene");
    leftSlider.setVisible(false);
    rightSlider.setVisible(false);

    assignmentAttachment = std::make_unique<
        juce::AudioProcessorValueTreeState::ComboBoxAttachment
    >(
        owner.state,
        MKCrossfaderProcessor::slotParameterId(index, "Assignment"),
        assignmentBox
    );
    leftAttachment = std::make_unique<
        juce::AudioProcessorValueTreeState::SliderAttachment
    >(
        owner.state,
        MKCrossfaderProcessor::slotParameterId(index, "Left"),
        leftSlider
    );
    rightAttachment = std::make_unique<
        juce::AudioProcessorValueTreeState::SliderAttachment
    >(
        owner.state,
        MKCrossfaderProcessor::slotParameterId(index, "Right"),
        rightSlider
    );
}

MKCrossfaderTargetRow::~MKCrossfaderTargetRow() {
    nameEditor.removeListener(this);
}

void MKCrossfaderTargetRow::paint(juce::Graphics& graphics) {
    graphics.setColour(juce::Colour(index % 2 == 0 ? surface : 0xff1b1b1b));
    graphics.fillRect(getLocalBounds());
    graphics.setColour(juce::Colour(line));
    graphics.drawHorizontalLine(getHeight() - 1, 0.0f, static_cast<float>(getWidth()));
}

void MKCrossfaderTargetRow::resized() {
    auto bounds = getLocalBounds().reduced(8, 5);
    numberLabel.setBounds(bounds.removeFromLeft(34));
    if (customScene) {
        auto right = bounds.removeFromRight(170);
        bounds.removeFromRight(8);
        auto left = bounds.removeFromRight(170);
        bounds.removeFromRight(10);
        nameEditor.setBounds(bounds);
        leftSlider.setBounds(left);
        rightSlider.setBounds(right);
    } else {
        auto assignment = bounds.removeFromRight(112);
        bounds.removeFromRight(10);
        nameEditor.setBounds(bounds);
        assignmentBox.setBounds(assignment);
    }
}

void MKCrossfaderTargetRow::setCustomScene(bool shouldUseCustomScene) {
    if (customScene == shouldUseCustomScene) {
        return;
    }
    customScene = shouldUseCustomScene;
    assignmentBox.setVisible(!customScene);
    leftSlider.setVisible(customScene);
    rightSlider.setVisible(customScene);
    resized();
}

void MKCrossfaderTargetRow::textEditorReturnKeyPressed(juce::TextEditor&) {
    commitLabel();
    giveAwayKeyboardFocus();
}

void MKCrossfaderTargetRow::textEditorFocusLost(juce::TextEditor&) {
    commitLabel();
}

void MKCrossfaderTargetRow::commitLabel() {
    owner.setSlotLabel(index, nameEditor.getText());
    nameEditor.setText(owner.slotLabel(index), false);
}

MKCrossfaderEditor::MKCrossfaderEditor(
    MKCrossfaderProcessor& crossfaderProcessor
) : AudioProcessorEditor(crossfaderProcessor), owner(crossfaderProcessor) {
    setLookAndFeel(&lookAndFeel);
    setSize(820, 620);
    setResizable(true, false);
    setResizeLimits(760, 560, 1040, 820);

    configureLabel(roleLabel, "ROLE");
    configureLabel(sessionLabel, "SESSION");
    configureCombo(roleBox, { "Controller", "Target" });
    configureCombo(sessionBox, numberedChoices(8));
    roleBox.setTitle("Role");
    sessionBox.setTitle("Session");
    roleBox.setTooltip("Choose one Controller or a linked Target");
    sessionBox.setTooltip("Linked instances must use the same session");
    addAndMakeVisible(roleLabel);
    addAndMakeVisible(roleBox);
    addAndMakeVisible(sessionLabel);
    addAndMakeVisible(sessionBox);
    addAndMakeVisible(unityButton);
    addAndMakeVisible(statusLabel);
    unityButton.setTooltip("Bypass all crossfade gain and return to exact unity");
    unityButton.setTitle("Unity override");
    unityButton.setColour(
        juce::ToggleButton::tickColourId,
        juce::Colour(brandRed)
    );
    statusLabel.setJustificationType(juce::Justification::centredRight);
    statusLabel.setFont(juce::FontOptions(12.0f, juce::Font::bold));

    addAndMakeVisible(controllerView);
    crossfaderSlider.setSliderStyle(juce::Slider::LinearHorizontal);
    crossfaderSlider.setTextBoxStyle(juce::Slider::NoTextBox, false, 0, 0);
    crossfaderSlider.setRange(0.0, 1.0, 0.0001);
    crossfaderSlider.getProperties().set("mkCrossfader", true);
    crossfaderSlider.setTitle("Crossfader");
    crossfaderSlider.setTooltip("Crossfader");
    controllerView.addAndMakeVisible(crossfaderSlider);
    controllerView.addAndMakeVisible(crossfaderValue);
    controllerView.addAndMakeVisible(sideALabel);
    controllerView.addAndMakeVisible(sideBLabel);
    sideALabel.setText("A", juce::dontSendNotification);
    sideBLabel.setText("B", juce::dontSendNotification);
    sideALabel.setJustificationType(juce::Justification::centredLeft);
    sideBLabel.setJustificationType(juce::Justification::centredRight);
    sideALabel.setFont(juce::FontOptions(22.0f, juce::Font::bold));
    sideBLabel.setFont(juce::FontOptions(22.0f, juce::Font::bold));
    crossfaderValue.setJustificationType(juce::Justification::centred);
    crossfaderValue.setFont(juce::FontOptions(15.0f, juce::Font::bold));

    configureLabel(modeLabel, "MODE");
    configureLabel(curveLabel, "CURVE");
    configureLabel(minimumLabel, "FLOOR");
    configureCombo(modeBox, {
        "A to B", "A+B to B", "A+B to A", "A+B to Floor", "Custom Scene"
    });
    configureCombo(curveBox, {
        "Full at Centre", "Linear", "Smooth", "Wide Blend", "Fast Cut"
    });
    configureCombo(minimumBox, { "Kill", "-24 dB", "-18 dB", "-14 dB" });
    modeBox.setTitle("Transition mode");
    curveBox.setTitle("Transition curve");
    minimumBox.setTitle("Minimum gain");
    modeBox.setTooltip("Choose how A and B change across the fader");
    curveBox.setTooltip("Choose the transition response");
    minimumBox.setTooltip("Lowest gain used by the faded side");
    for (auto* component : {
             static_cast<juce::Component*>(&modeLabel),
             static_cast<juce::Component*>(&modeBox),
             static_cast<juce::Component*>(&curveLabel),
             static_cast<juce::Component*>(&curveBox),
             static_cast<juce::Component*>(&minimumLabel),
             static_cast<juce::Component*>(&minimumBox),
             static_cast<juce::Component*>(&swapButton),
             static_cast<juce::Component*>(&flipButton),
             static_cast<juce::Component*>(&colourAButton),
             static_cast<juce::Component*>(&colourBButton),
             static_cast<juce::Component*>(&activeTargetsLabel),
             static_cast<juce::Component*>(&routesLabel),
             static_cast<juce::Component*>(&routeScopeButton),
             static_cast<juce::Component*>(&assignmentLabel),
             static_cast<juce::Component*>(&leftLabel),
             static_cast<juce::Component*>(&rightLabel),
             static_cast<juce::Component*>(&routesViewport) }) {
        controllerView.addAndMakeVisible(component);
    }
    swapButton.setTooltip("Exchange the A and B outputs");
    flipButton.setTooltip("Reverse the physical fader direction");
    colourAButton.setTooltip("Change A colour");
    colourBButton.setTooltip("Change B colour");
    colourAButton.onClick = [this] { cycleColour("colourA"); };
    colourBButton.onClick = [this] { cycleColour("colourB"); };
    routeScopeButton.setTooltip("Show or hide unused target slots");
    routeScopeButton.onClick = [this] {
        showAllRoutes = !showAllRoutes;
        updateRouteVisibility();
        resized();
    };
    activeTargetsLabel.setJustificationType(juce::Justification::centredRight);
    activeTargetsLabel.setColour(juce::Label::textColourId, juce::Colour(secondaryText));
    configureLabel(routesLabel, "TARGET ROUTES");
    configureLabel(assignmentLabel, "SIDE");
    configureLabel(leftLabel, "LEFT");
    configureLabel(rightLabel, "RIGHT");
    routesViewport.setScrollBarsShown(true, false);
    routesViewport.setViewedComponent(&routesContent, false);
    routesContent.setSize(744, static_cast<int>(mkxf::targetCount) * 38);
    for (auto index = 0; index < static_cast<int>(mkxf::targetCount); ++index) {
        rows[static_cast<std::size_t>(index)] =
            std::make_unique<MKCrossfaderTargetRow>(owner, index);
        routesContent.addAndMakeVisible(*rows[static_cast<std::size_t>(index)]);
    }

    addAndMakeVisible(targetView);
    configureLabel(targetSlotLabel, "TARGET SLOT");
    configureCombo(targetSlotBox, numberedChoices(16));
    targetSlotBox.setTitle("Target slot");
    targetSlotBox.setTooltip("Match this slot to a Controller target route");
    configureLabel(targetGainTitle, "CURRENT GAIN");
    targetGainValue.setJustificationType(juce::Justification::centred);
    targetGainValue.setFont(juce::FontOptions(48.0f, juce::Font::bold));
    targetNameValue.setJustificationType(juce::Justification::centred);
    targetNameValue.setFont(juce::FontOptions(18.0f, juce::Font::bold));
    targetNameValue.setColour(juce::Label::textColourId, juce::Colour(secondaryText));
    for (auto* component : {
             static_cast<juce::Component*>(&targetSlotLabel),
             static_cast<juce::Component*>(&targetSlotBox),
             static_cast<juce::Component*>(&targetGainTitle),
             static_cast<juce::Component*>(&targetGainValue),
             static_cast<juce::Component*>(&targetNameValue) }) {
        targetView.addAndMakeVisible(component);
    }

    roleAttachment = std::make_unique<
        juce::AudioProcessorValueTreeState::ComboBoxAttachment
    >(owner.state, "role", roleBox);
    sessionAttachment = std::make_unique<
        juce::AudioProcessorValueTreeState::ComboBoxAttachment
    >(owner.state, "session", sessionBox);
    unityAttachment = std::make_unique<
        juce::AudioProcessorValueTreeState::ButtonAttachment
    >(owner.state, "safeUnity", unityButton);
    crossfaderAttachment = std::make_unique<
        juce::AudioProcessorValueTreeState::SliderAttachment
    >(owner.state, "crossfader", crossfaderSlider);
    modeAttachment = std::make_unique<
        juce::AudioProcessorValueTreeState::ComboBoxAttachment
    >(owner.state, "mode", modeBox);
    curveAttachment = std::make_unique<
        juce::AudioProcessorValueTreeState::ComboBoxAttachment
    >(owner.state, "curve", curveBox);
    minimumAttachment = std::make_unique<
        juce::AudioProcessorValueTreeState::ComboBoxAttachment
    >(owner.state, "minimum", minimumBox);
    swapAttachment = std::make_unique<
        juce::AudioProcessorValueTreeState::ButtonAttachment
    >(owner.state, "swap", swapButton);
    flipAttachment = std::make_unique<
        juce::AudioProcessorValueTreeState::ButtonAttachment
    >(owner.state, "flip", flipButton);
    targetSlotAttachment = std::make_unique<
        juce::AudioProcessorValueTreeState::ComboBoxAttachment
    >(owner.state, "targetSlot", targetSlotBox);

    roleBox.onChange = [this] { updateRoleVisibility(); };
    updateRoleVisibility();
    updateModeVisibility();
    updateRouteVisibility();
    resized();
    updateColours();
    updateStatus();
    startTimerHz(20);
}

MKCrossfaderEditor::~MKCrossfaderEditor() {
    stopTimer();
    routesViewport.setViewedComponent(nullptr, false);
    setLookAndFeel(nullptr);
}

void MKCrossfaderEditor::paint(juce::Graphics& graphics) {
    graphics.fillAll(juce::Colour(background));
    graphics.setColour(juce::Colour(brandRed));
    graphics.setFont(juce::FontOptions(19.0f, juce::Font::bold));
    graphics.drawText(
        "MK",
        24,
        15,
        32,
        30,
        juce::Justification::centredLeft,
        false
    );
    graphics.setColour(juce::Colour(text));
    graphics.setFont(juce::FontOptions(21.0f, juce::Font::bold));
    graphics.drawText(
        "CROSSFADER",
        60,
        15,
        240,
        30,
        juce::Justification::centredLeft,
        false
    );
    graphics.setColour(juce::Colour(line));
    graphics.drawHorizontalLine(55, 24.0f, static_cast<float>(getWidth() - 24));
    graphics.drawHorizontalLine(109, 24.0f, static_cast<float>(getWidth() - 24));
}

void MKCrossfaderEditor::resized() {
    roleLabel.setBounds(24, 67, 45, 28);
    roleBox.setBounds(70, 65, 130, 32);
    sessionLabel.setBounds(220, 67, 68, 28);
    sessionBox.setBounds(290, 65, 70, 32);
    unityButton.setBounds(380, 65, 90, 32);
    statusLabel.setBounds(getWidth() - 300, 65, 276, 32);

    const auto content = juce::Rectangle<int>(
        24,
        122,
        getWidth() - 48,
        getHeight() - 140
    );
    controllerView.setBounds(content);
    targetView.setBounds(content);

    auto controllerBounds = controllerView.getLocalBounds();
    auto faderArea = controllerBounds.removeFromTop(104);
    sideALabel.setBounds(faderArea.removeFromLeft(35));
    sideBLabel.setBounds(faderArea.removeFromRight(35));
    crossfaderValue.setBounds(
        faderArea.getCentreX() - 45,
        0,
        90,
        28
    );
    crossfaderSlider.setBounds(faderArea.withTrimmedTop(24).reduced(4, 12));

    auto controls = controllerBounds.removeFromTop(72);
    const auto customScene = visibleMode == static_cast<int>(mkxf::Mode::customScene);
    const auto controlColumns = customScene ? 2 : 3;
    const auto columnWidth = juce::jmax(
        145,
        (controls.getWidth() - (controlColumns - 1) * 12) / controlColumns
    );
    auto modeArea = controls.removeFromLeft(columnWidth);
    controls.removeFromLeft(12);
    auto curveArea = controls.removeFromLeft(columnWidth);
    juce::Rectangle<int> minimumArea;
    if (!customScene) {
        controls.removeFromLeft(12);
        minimumArea = controls;
    }
    modeLabel.setBounds(modeArea.removeFromTop(20));
    modeBox.setBounds(modeArea.removeFromTop(34));
    curveLabel.setBounds(curveArea.removeFromTop(20));
    curveBox.setBounds(curveArea.removeFromTop(34));
    if (!customScene) {
        minimumLabel.setBounds(minimumArea.removeFromTop(20));
        minimumBox.setBounds(minimumArea.removeFromTop(34));
    }

    auto switches = controllerBounds.removeFromTop(48);
    swapButton.setBounds(switches.removeFromLeft(115));
    flipButton.setBounds(switches.removeFromLeft(130));
    colourAButton.setBounds(switches.removeFromLeft(42).reduced(3, 7));
    colourBButton.setBounds(switches.removeFromLeft(42).reduced(3, 7));
    activeTargetsLabel.setBounds(switches);

    auto routeHeader = controllerBounds.removeFromTop(28);
    routesLabel.setBounds(routeHeader.removeFromLeft(128));
    routeScopeButton.setBounds(routeHeader.removeFromLeft(92).reduced(0, 3));
    if (customScene) {
        rightLabel.setBounds(routeHeader.removeFromRight(170));
        routeHeader.removeFromRight(8);
        leftLabel.setBounds(routeHeader.removeFromRight(170));
    } else {
        assignmentLabel.setBounds(routeHeader.removeFromRight(112));
    }
    routesViewport.setBounds(controllerBounds);
    routesContent.setSize(
        juce::jmax(744, routesViewport.getWidth() - 14),
        juce::jmax(1, visibleRouteCount) * routeRowHeight
    );
    for (auto index = 0; index < static_cast<int>(mkxf::targetCount); ++index) {
        if (auto* row = rows[static_cast<std::size_t>(index)].get()) {
            row->setBounds(
                0,
                index * routeRowHeight,
                routesContent.getWidth(),
                routeRowHeight
            );
        }
    }

    auto targetBounds = targetView.getLocalBounds();
    auto top = targetBounds.removeFromTop(68);
    targetSlotLabel.setBounds(top.removeFromTop(22).withSizeKeepingCentre(160, 22));
    targetSlotBox.setBounds(top.withSizeKeepingCentre(160, 34));
    targetBounds.removeFromTop(72);
    targetNameValue.setBounds(targetBounds.removeFromTop(34));
    targetGainTitle.setBounds(targetBounds.removeFromTop(30).withSizeKeepingCentre(200, 24));
    targetGainValue.setBounds(targetBounds.removeFromTop(90));
}

void MKCrossfaderEditor::timerCallback() {
    updateRoleVisibility();
    updateModeVisibility();
    updateRouteVisibility();
    updateStatus();
    updateColours();
}

void MKCrossfaderEditor::updateRoleVisibility() {
    const auto role = juce::roundToInt(rawParameter(owner.state, "role"));
    if (role == visibleRole) {
        return;
    }
    visibleRole = role;
    controllerView.setVisible(role == 0);
    targetView.setVisible(role == 1);
    repaint();
}

void MKCrossfaderEditor::updateModeVisibility() {
    const auto mode = juce::roundToInt(rawParameter(owner.state, "mode"));
    if (mode == visibleMode) {
        return;
    }
    visibleMode = mode;
    const auto customScene = mode == static_cast<int>(mkxf::Mode::customScene);
    for (auto& row : rows) {
        row->setCustomScene(customScene);
    }
    assignmentLabel.setVisible(!customScene);
    leftLabel.setVisible(customScene);
    rightLabel.setVisible(customScene);
    minimumLabel.setVisible(!customScene);
    minimumBox.setVisible(!customScene);
    swapButton.setVisible(!customScene);
    swapButton.setEnabled(mode != static_cast<int>(mkxf::Mode::pairFade));
    resized();
}

int MKCrossfaderEditor::compactRouteCount() const {
    const auto customScene = visibleMode == static_cast<int>(mkxf::Mode::customScene);
    auto highestConfigured = 0;
    for (auto index = 0; index < static_cast<int>(mkxf::targetCount); ++index) {
        auto configured = false;
        if (customScene) {
            const auto leftId = MKCrossfaderProcessor::slotParameterId(index, "Left");
            const auto rightId = MKCrossfaderProcessor::slotParameterId(index, "Right");
            configured = std::abs(rawParameter(owner.state, leftId) - 100.0f) > 0.01f
                || std::abs(rawParameter(owner.state, rightId) - 100.0f) > 0.01f;
        } else {
            const auto assignmentId = MKCrossfaderProcessor::slotParameterId(
                index,
                "Assignment"
            );
            configured = juce::roundToInt(rawParameter(owner.state, assignmentId))
                != static_cast<int>(mkxf::Assignment::off);
        }
        if (configured) {
            highestConfigured = index + 1;
        }
    }
    return juce::jlimit(
        compactRouteMinimum,
        static_cast<int>(mkxf::targetCount),
        highestConfigured
    );
}

void MKCrossfaderEditor::updateRouteVisibility() {
    const auto compactCount = compactRouteCount();
    const auto nextCount = showAllRoutes
        ? static_cast<int>(mkxf::targetCount)
        : compactCount;
    routeScopeButton.setButtonText(showAllRoutes ? "SHOW LESS" : "SHOW ALL");
    routeScopeButton.setVisible(
        showAllRoutes || compactCount < static_cast<int>(mkxf::targetCount)
    );
    if (nextCount == visibleRouteCount) {
        return;
    }
    visibleRouteCount = nextCount;
    for (auto index = 0; index < static_cast<int>(mkxf::targetCount); ++index) {
        rows[static_cast<std::size_t>(index)]->setVisible(index < visibleRouteCount);
    }
    resized();
}

void MKCrossfaderEditor::updateStatus() {
    const auto runtime = owner.runtimeStatus();
    const auto role = juce::roundToInt(rawParameter(owner.state, "role"));
    juce::String statusText;
    auto statusColour = juce::Colour(secondaryText);
    switch (runtime) {
        case MKCrossfaderProcessor::RuntimeStatus::waiting:
            if (role == 0) {
                statusText = "READY";
            } else {
                statusText = owner.controllerAvailable()
                    ? "IDLE - NO AUDIO"
                    : "WAITING FOR CONTROLLER";
            }
            break;
        case MKCrossfaderProcessor::RuntimeStatus::controllerActive:
            statusText = "ACTIVE";
            statusColour = juce::Colour(success);
            break;
        case MKCrossfaderProcessor::RuntimeStatus::targetConnected:
            statusText = "CONNECTED";
            statusColour = juce::Colour(success);
            break;
        case MKCrossfaderProcessor::RuntimeStatus::unityOverride:
            statusText = "UNITY OVERRIDE";
            statusColour = juce::Colour(warning);
            break;
        case MKCrossfaderProcessor::RuntimeStatus::staleHold:
            statusText = "HOLDING LAST LEVEL";
            statusColour = juce::Colour(warning);
            break;
        case MKCrossfaderProcessor::RuntimeStatus::controllerConflict:
            statusText = "CONTROLLER CONFLICT";
            statusColour = juce::Colour(danger);
            break;
        case MKCrossfaderProcessor::RuntimeStatus::targetConflict:
            statusText = "TARGET SLOT CONFLICT";
            statusColour = juce::Colour(danger);
            break;
        case MKCrossfaderProcessor::RuntimeStatus::busUnavailable:
            statusText = "CONNECTION UNAVAILABLE";
            statusColour = juce::Colour(danger);
            break;
    }
    statusLabel.setText(statusText, juce::dontSendNotification);
    statusLabel.setColour(juce::Label::textColourId, statusColour);

    const auto percent = juce::roundToInt(rawParameter(owner.state, "crossfader") * 100.0f);
    crossfaderValue.setText(juce::String(percent) + "%", juce::dontSendNotification);
    const auto configured = owner.configuredTargetCount();
    const auto online = owner.connectedTargetCount();
    activeTargetsLabel.setText(
        juce::String(configured) + " ROUTES  |  "
            + juce::String(online) + " ONLINE",
        juce::dontSendNotification
    );

    const auto gain = owner.currentGain();
    const auto gainText = gain <= 0.000001f
        ? juce::String("-inf dB")
        : (std::abs(gain - 1.0f) < 0.00001f
               ? juce::String("0.0 dB")
               : juce::String(juce::Decibels::gainToDecibels(gain), 1) + " dB");
    targetGainValue.setText(gainText, juce::dontSendNotification);
    const auto targetSlot = juce::roundToInt(rawParameter(owner.state, "targetSlot"));
    targetNameValue.setText(
        "SLOT " + juce::String(targetSlot + 1).paddedLeft('0', 2),
        juce::dontSendNotification
    );
}

void MKCrossfaderEditor::updateColours() {
    const auto colourA = parameterColour(owner.state, "colourA");
    const auto colourB = parameterColour(owner.state, "colourB");
    sideALabel.setColour(juce::Label::textColourId, colourA);
    sideBLabel.setColour(juce::Label::textColourId, colourB);
    const auto blend = static_cast<float>(rawParameter(owner.state, "crossfader"));
    const auto faderColour = colourA.interpolatedWith(colourB, blend);
    crossfaderSlider.setColour(juce::Slider::trackColourId, faderColour);
    crossfaderSlider.setColour(juce::Slider::thumbColourId, faderColour);

    for (const auto pair : {
             std::pair<juce::TextButton*, juce::Colour>{ &colourAButton, colourA },
             std::pair<juce::TextButton*, juce::Colour>{ &colourBButton, colourB } }) {
        pair.first->setColour(juce::TextButton::buttonColourId, pair.second);
        pair.first->setColour(
            juce::TextButton::textColourOffId,
            pair.second.getPerceivedBrightness() > 0.62f
                ? juce::Colours::black
                : juce::Colours::white
        );
    }
}

void MKCrossfaderEditor::cycleColour(const char* id) {
    static constexpr std::array<int, 8> palette{
        0xe5484d,
        0xc5c7ca,
        0xf2f2f2,
        0x73777d,
        0x8f252b,
        0x32c5ff,
        0x54d68b,
        0xb482ff
    };
    const auto current = juce::roundToInt(rawParameter(owner.state, id)) & 0x00ffffff;
    auto next = palette.front();
    for (std::size_t index = 0; index < palette.size(); ++index) {
        if (palette[index] == current) {
            next = palette[(index + 1) % palette.size()];
            break;
        }
    }
    if (auto* parameter = owner.state.getParameter(id)) {
        parameter->beginChangeGesture();
        parameter->setValueNotifyingHost(
            parameter->convertTo0to1(static_cast<float>(next))
        );
        parameter->endChangeGesture();
    }
    updateColours();
}

void MKCrossfaderEditor::configureCombo(
    juce::ComboBox& box,
    const juce::StringArray& choices
) {
    box.addItemList(choices, 1);
    box.setJustificationType(juce::Justification::centredLeft);
}

void MKCrossfaderEditor::configureLabel(
    juce::Label& label,
    const juce::String& labelText
) {
    label.setText(labelText, juce::dontSendNotification);
    label.setJustificationType(juce::Justification::centredLeft);
    label.setFont(juce::FontOptions(10.0f, juce::Font::bold));
    label.setColour(juce::Label::textColourId, juce::Colour(secondaryText));
}
