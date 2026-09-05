#pragma once

#include "CrossfadeEngine.h"

#include <cstdint>
#include <memory>

namespace mkxf {

enum class ClaimResult {
    owned,
    conflict,
    unavailable
};

struct FrameRead {
    GainFrame gains{};
    bool connected{false};
    bool unityOverride{false};
};

class SharedBus final {
public:
    explicit SharedBus(int session);
    ~SharedBus();

    SharedBus(const SharedBus&) = delete;
    SharedBus& operator=(const SharedBus&) = delete;

    [[nodiscard]] bool isAvailable() const noexcept;
    [[nodiscard]] ClaimResult claimController(std::uint64_t nowMs) noexcept;
    void releaseController() noexcept;
    bool publish(
        const GainFrame& frame,
        bool unityOverride,
        std::uint64_t nowMs
    ) noexcept;
    [[nodiscard]] FrameRead read(std::uint64_t nowMs) const noexcept;

    [[nodiscard]] ClaimResult claimTarget(
        std::size_t slot,
        std::uint64_t nowMs
    ) noexcept;
    void releaseTarget(std::size_t slot) noexcept;
    [[nodiscard]] int activeTargetCount(std::uint64_t nowMs) const noexcept;

    static std::uint64_t monotonicMilliseconds() noexcept;

private:
    struct Impl;
    std::unique_ptr<Impl> impl;
};

} // namespace mkxf
