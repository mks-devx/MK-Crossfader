#include "CrossfadeEngine.h"

#include <algorithm>
#include <cmath>

namespace mkxf {
namespace {

constexpr float halfPi = 1.57079632679489661923f;

float clamp01(float value) noexcept {
    return std::clamp(value, 0.0f, 1.0f);
}

float smoothStep(float value) noexcept {
    const auto clamped = clamp01(value);
    return clamped * clamped * (3.0f - 2.0f * clamped);
}

SideGains rawSideGains(float position, Curve curve) noexcept {
    const auto p = clamp01(position);
    switch (curve) {
        case Curve::fullCentre: {
            constexpr auto leftCentre = 63.0f / 127.0f;
            constexpr auto rightCentre = 64.0f / 127.0f;
            return {
                p <= rightCentre ? 1.0f
                                 : (1.0f - p) / (1.0f - rightCentre),
                p >= leftCentre ? 1.0f : p / leftCentre
            };
        }
        case Curve::linear:
            return {1.0f - p, p};
        case Curve::smooth: {
            const auto blend = smoothStep(p);
            return {1.0f - blend, blend};
        }
        case Curve::wideBlend:
            return {std::cos(p * halfPi), std::sin(p * halfPi)};
        case Curve::fastCut:
            return {
                clamp01((1.0f - p) / 0.18f),
                clamp01(p / 0.18f)
            };
    }
    return {1.0f, 1.0f};
}

} // namespace

float minimumGain(Minimum minimum) noexcept {
    switch (minimum) {
        case Minimum::kill: return 0.0f;
        case Minimum::minus24: return std::pow(10.0f, -24.0f / 20.0f);
        case Minimum::minus18: return std::pow(10.0f, -18.0f / 20.0f);
        case Minimum::minus14: return std::pow(10.0f, -14.0f / 20.0f);
    }
    return 0.0f;
}

float sceneProgress(float position, Curve curve) noexcept {
    const auto p = clamp01(position);
    switch (curve) {
        case Curve::fullCentre:
        case Curve::linear:
            return p;
        case Curve::smooth:
            return smoothStep(p);
        case Curve::wideBlend: {
            const auto sine = std::sin(p * halfPi);
            return sine * sine;
        }
        case Curve::fastCut:
            return smoothStep((p - 0.41f) / 0.18f);
    }
    return p;
}

SideGains sideGains(
    float position,
    Mode mode,
    Curve curve,
    Minimum minimum,
    bool swapSides,
    bool flipTravel
) noexcept {
    const auto p = flipTravel ? 1.0f - clamp01(position) : clamp01(position);
    auto gains = rawSideGains(p, curve);

    switch (mode) {
        case Mode::standard:
        case Mode::customScene:
            break;
        case Mode::layerToB:
            gains.sideB = 1.0f;
            break;
        case Mode::layerToA:
            gains = {1.0f, gains.sideA};
            break;
        case Mode::pairFade:
            gains.sideB = gains.sideA;
            break;
    }

    const auto floor = minimumGain(minimum);
    gains.sideA = std::max(gains.sideA, floor);
    gains.sideB = std::max(gains.sideB, floor);

    if (swapSides) {
        std::swap(gains.sideA, gains.sideB);
    }
    return gains;
}

GainFrame renderFrame(
    float position,
    Mode mode,
    Curve curve,
    Minimum minimum,
    bool swapSides,
    bool flipTravel,
    const std::array<SlotConfig, targetCount>& slots
) noexcept {
    GainFrame frame{};
    if (mode == Mode::customScene) {
        const auto p = sceneProgress(
            flipTravel ? 1.0f - clamp01(position) : clamp01(position),
            curve
        );
        for (std::size_t i = 0; i < frame.size(); ++i) {
            const auto left = clamp01(slots[i].left);
            const auto right = clamp01(slots[i].right);
            frame[i] = left + ((right - left) * p);
        }
        return frame;
    }

    const auto gains = sideGains(
        position,
        mode,
        curve,
        minimum,
        swapSides,
        flipTravel
    );
    for (std::size_t i = 0; i < frame.size(); ++i) {
        switch (slots[i].assignment) {
            case Assignment::off: frame[i] = 1.0f; break;
            case Assignment::sideA: frame[i] = gains.sideA; break;
            case Assignment::sideB: frame[i] = gains.sideB; break;
        }
    }
    return frame;
}

} // namespace mkxf
