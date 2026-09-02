#include <juce_audio_utils/juce_audio_utils.h>

#include <cmath>
#include <cstdlib>
#include <iostream>
#include <memory>
#include <string>

namespace {

void require(bool condition, const std::string& message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        std::exit(1);
    }
}

juce::AudioProcessorParameter* findParameter(
    juce::AudioProcessor& processor,
    const juce::String& name
) {
    for (auto* parameter : processor.getParameters()) {
        if (parameter != nullptr && parameter->getName(64) == name) {
            return parameter;
        }
    }
    return nullptr;
}

void fillWithOnes(juce::AudioBuffer<float>& buffer) {
    for (auto channel = 0; channel < buffer.getNumChannels(); ++channel) {
        for (auto sample = 0; sample < buffer.getNumSamples(); ++sample) {
            buffer.setSample(channel, sample, 1.0f);
        }
    }
}

void process(juce::AudioPluginInstance& instance, juce::AudioBuffer<float>& audio) {
    juce::MidiBuffer midi;
    fillWithOnes(audio);
    instance.processBlock(audio, midi);
}

} // namespace

int main(int argc, char** argv) {
    juce::ScopedJuceInitialiser_GUI juceInitialiser;
    require(argc == 2, "Expected the VST3 bundle path");
    const juce::File pluginBundle(argv[1]);
    require(pluginBundle.isDirectory(), "VST3 bundle does not exist");

    juce::VST3PluginFormat format;
    juce::OwnedArray<juce::PluginDescription> descriptions;
    format.findAllTypesForFile(descriptions, pluginBundle.getFullPathName());
    require(descriptions.size() == 1, "Host scan did not find exactly one type");
    require(descriptions[0]->name == "MK Crossfader", "Host scan returned the wrong name");

    juce::String controllerError;
    auto controller = format.createInstanceFromDescription(
        *descriptions[0], 48000.0, 1024, controllerError
    );
    require(controller != nullptr, "Host could not instantiate Controller: "
        + controllerError.toStdString());
    juce::String targetError;
    auto target = format.createInstanceFromDescription(
        *descriptions[0], 48000.0, 1024, targetError
    );
    require(target != nullptr, "Host could not instantiate Target: "
        + targetError.toStdString());

    for (auto* instance : { controller.get(), target.get() }) {
        require(instance->getTotalNumInputChannels() == 2, "VST3 lacks stereo input");
        require(instance->getTotalNumOutputChannels() == 2, "VST3 lacks stereo output");
        require(findParameter(*instance, "Role") != nullptr, "VST3 has no Role parameter");
        require(findParameter(*instance, "Session") != nullptr, "VST3 has no Session parameter");
        require(findParameter(*instance, "Crossfader") != nullptr, "VST3 has no Crossfader parameter");
        require(findParameter(*instance, "Target Slot") != nullptr, "VST3 has no Target Slot parameter");
        require(findParameter(*instance, "Unity Override") != nullptr, "VST3 has no Unity parameter");
    }

    findParameter(*target, "Role")->setValueNotifyingHost(1.0f);
    findParameter(*controller, "Session")->setValueNotifyingHost(1.0f);
    findParameter(*target, "Session")->setValueNotifyingHost(1.0f);
    findParameter(*controller, "Crossfader")->setValueNotifyingHost(1.0f);
    controller->prepareToPlay(48000.0, 1024);
    target->prepareToPlay(48000.0, 1024);
    juce::AudioBuffer<float> controllerAudio(2, 1024);
    juce::AudioBuffer<float> targetAudio(2, 1024);
    process(*controller, controllerAudio);
    require(
        std::abs(controllerAudio.getSample(0, 1023) - 1.0f) < 1.0e-5f,
        "Loaded Controller changed its audio"
    );
    process(*target, targetAudio);
    require(
        std::abs(targetAudio.getSample(0, 1023)) < 1.0e-5f,
        "Loaded Target did not receive the Controller gain"
    );

    require(controller->hasEditor(), "Loaded VST3 did not report an editor");
    std::unique_ptr<juce::AudioProcessorEditor> editor(
        controller->createEditorAndMakeActive()
    );
    require(editor != nullptr, "Loaded VST3 editor could not be created");
    require(editor->getWidth() == 820 && editor->getHeight() == 620, "Editor size changed");

    std::cout << "Loaded, linked and processed: "
              << pluginBundle.getFullPathName() << '\n';
    return 0;
}
