#pragma once

#include <array>
#include <cstddef>

namespace mkxf {

constexpr std::size_t targetCount = 16;

enum class Mode : int {
    standard = 0,
    layerToB,
    layerToA,
    pairFade,
    customScene
};

enum class Curve : int {
    fullCentre = 0,
    linear,
    smooth,
    wideBlend,
    fastCut
};

enum class Minimum : int {
    kill = 0,
    minus24,
    minus18,
    minus14
};

enum class Assignment : int {
    off = 0,
    sideA,
    sideB
};

struct SlotConfig {
    Assignment assignment{Assignment::off};
    float left{1.0f};
    float right{1.0f};
};

using GainFrame = std::array<float, targetCount>;

struct SideGains {
    float sideA{1.0f};
    float sideB{1.0f};
};

float minimumGain(Minimum minimum) noexcept;
float sceneProgress(float position, Curve curve) noexcept;
SideGains sideGains(
    float position,
    Mode mode,
    Curve curve,
    Minimum minimum,
    bool swapSides,
    bool flipTravel
) noexcept;
GainFrame renderFrame(
    float position,
    Mode mode,
    Curve curve,
    Minimum minimum,
    bool swapSides,
    bool flipTravel,
    const std::array<SlotConfig, targetCount>& slots
) noexcept;

} // namespace mkxf
