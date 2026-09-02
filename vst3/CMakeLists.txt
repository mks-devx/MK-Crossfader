cmake_minimum_required(VERSION 3.22)

if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Darwin" AND NOT CMAKE_OSX_ARCHITECTURES)
    set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64" CACHE STRING
        "macOS architectures to build")
endif()
if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Darwin" AND NOT CMAKE_OSX_DEPLOYMENT_TARGET)
    set(CMAKE_OSX_DEPLOYMENT_TARGET "13.0" CACHE STRING
        "Oldest supported macOS version")
endif()

project(MK_Crossfader VERSION 0.2.8 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include(FetchContent)
FetchContent_Declare(
    JUCE
    GIT_REPOSITORY https://github.com/juce-framework/JUCE.git
    GIT_TAG        8.0.15
    GIT_SHALLOW    TRUE
)
FetchContent_MakeAvailable(JUCE)

enable_testing()

set(MK_CROSSFADER_CORE
    src/CrossfadeEngine.cpp
    src/CrossfadeEngine.h
    src/SharedBus.cpp
    src/SharedBus.h
)

juce_add_plugin(MK_Crossfader
    COMPANY_NAME             "MK-Tools"
    BUNDLE_ID                "com.mk-tools.crossfader"
    PLUGIN_MANUFACTURER_CODE Mktl
    PLUGIN_CODE              MkXf
    FORMATS                  VST3
    PRODUCT_NAME             "MK Crossfader"
    IS_SYNTH                 FALSE
    NEEDS_MIDI_INPUT         FALSE
    NEEDS_MIDI_OUTPUT        FALSE
    IS_MIDI_EFFECT           FALSE
    EDITOR_WANTS_KEYBOARD_FOCUS TRUE
    COPY_PLUGIN_AFTER_BUILD  FALSE
    VST3_CATEGORIES          Fx Tools
    HARDENED_RUNTIME_ENABLED TRUE
)

target_sources(MK_Crossfader PRIVATE
    ${MK_CROSSFADER_CORE}
    src/PluginEditor.cpp
    src/PluginEditor.h
    src/PluginProcessor.cpp
    src/PluginProcessor.h
)

target_compile_definitions(MK_Crossfader PUBLIC
    JUCE_WEB_BROWSER=0
    JUCE_USE_CURL=0
    JUCE_VST3_CAN_REPLACE_VST2=0
)

target_link_libraries(MK_Crossfader PRIVATE
    juce::juce_audio_processors
    juce::juce_gui_basics
    juce::juce_recommended_config_flags
    juce::juce_recommended_lto_flags
    juce::juce_recommended_warning_flags
)

add_executable(MK_Crossfader_Tests
    tests/PluginTests.cpp
)
target_include_directories(MK_Crossfader_Tests PRIVATE src)
target_link_libraries(MK_Crossfader_Tests PRIVATE
    MK_Crossfader
    juce::juce_audio_processors
    juce::juce_gui_basics
)
add_test(NAME MK_Crossfader_Tests COMMAND MK_Crossfader_Tests)

add_executable(MK_Crossfader_ProcessLinkTests
    tests/ProcessLinkTests.cpp
    src/CrossfadeEngine.cpp
    src/SharedBus.cpp
)
target_include_directories(MK_Crossfader_ProcessLinkTests PRIVATE src)
target_link_libraries(MK_Crossfader_ProcessLinkTests PRIVATE
    juce::juce_recommended_config_flags
    juce::juce_recommended_warning_flags
)
add_test(
    NAME MK_Crossfader_ProcessLinkTests
    COMMAND MK_Crossfader_ProcessLinkTests
)

add_executable(MK_Crossfader_HostValidation
    tests/HostValidation.cpp
)
target_compile_definitions(MK_Crossfader_HostValidation PRIVATE
    JUCE_PLUGINHOST_VST3=1
    JUCE_WEB_BROWSER=0
    JUCE_USE_CURL=0
)
target_link_libraries(MK_Crossfader_HostValidation PRIVATE
    juce::juce_audio_processors
    juce::juce_gui_basics
)
add_dependencies(MK_Crossfader_HostValidation MK_Crossfader_VST3)
add_test(
    NAME MK_Crossfader_HostValidation
    COMMAND MK_Crossfader_HostValidation
        "$<TARGET_BUNDLE_DIR:MK_Crossfader_VST3>"
)

if(APPLE)
    add_custom_command(TARGET MK_Crossfader_VST3 POST_BUILD
        COMMAND /usr/bin/codesign --force --deep --sign -
            "$<TARGET_BUNDLE_DIR:MK_Crossfader_VST3>"
        COMMENT "Ad-hoc signing MK Crossfader VST3"
        VERBATIM
    )
endif()
