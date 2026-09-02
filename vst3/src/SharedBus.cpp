#include "SharedBus.h"

#include <array>
#include <atomic>
#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <new>
#include <string>
#include <sys/mman.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

namespace mkxf {
namespace {

constexpr std::uint32_t busMagic = 0x4d4b5846;
constexpr std::uint32_t busVersion = 1;
constexpr std::uint64_t staleAfterMs = 2000;

static_assert(std::atomic<std::uint32_t>::is_always_lock_free);
static_assert(std::atomic<std::uint64_t>::is_always_lock_free);

std::uint32_t floatBits(float value) noexcept {
    std::uint32_t bits = 0;
    static_assert(sizeof(bits) == sizeof(value));
    std::memcpy(&bits, &value, sizeof(bits));
    return bits;
}

float bitsFloat(std::uint32_t bits) noexcept {
    float value = 0.0f;
    std::memcpy(&value, &bits, sizeof(value));
    return value;
}

bool isFresh(std::uint64_t heartbeat, std::uint64_t now) noexcept {
    return heartbeat != 0 && now >= heartbeat && now - heartbeat <= staleAfterMs;
}

struct SharedState {
    std::atomic<std::uint32_t> magic{0};
    std::uint32_t version{busVersion};
    std::atomic<std::uint64_t> controllerToken{0};
    std::atomic<std::uint64_t> controllerHeartbeat{0};
    std::atomic<std::uint64_t> frameSequence{0};
    std::array<std::atomic<std::uint32_t>, targetCount> gainBits{};
    std::atomic<std::uint32_t> unityOverride{0};
    std::array<std::atomic<std::uint64_t>, targetCount> targetTokens{};
    std::array<std::atomic<std::uint64_t>, targetCount> targetHeartbeats{};
};

} // namespace

struct SharedBus::Impl {
    explicit Impl(int session, std::uint64_t tokenToUse)
        : token(tokenToUse) {
        const auto safeSession = session < 1 ? 1 : (session > 8 ? 8 : session);
        name = "/mk_crossfader_v1_" + std::to_string(getuid()) + "_"
            + std::to_string(safeSession);

        bool created = false;
        fd = shm_open(name.c_str(), O_RDWR | O_CREAT | O_EXCL, 0600);
        if (fd >= 0) {
            created = true;
            if (ftruncate(fd, static_cast<off_t>(sizeof(SharedState))) != 0) {
                close(fd);
                fd = -1;
                shm_unlink(name.c_str());
                return;
            }
        } else if (errno == EEXIST) {
            fd = shm_open(name.c_str(), O_RDWR, 0600);
        }

        if (fd < 0) {
            return;
        }

        void* mapped = mmap(
            nullptr,
            sizeof(SharedState),
            PROT_READ | PROT_WRITE,
            MAP_SHARED,
            fd,
            0
        );
        if (mapped == MAP_FAILED) {
            close(fd);
            fd = -1;
            return;
        }
        state = static_cast<SharedState*>(mapped);

        if (created) {
            new (state) SharedState();
            for (auto& gain : state->gainBits) {
                gain.store(floatBits(1.0f), std::memory_order_relaxed);
            }
            state->magic.store(busMagic, std::memory_order_release);
        } else {
            for (auto attempt = 0; attempt < 100; ++attempt) {
                if (state->magic.load(std::memory_order_acquire) == busMagic
                    && state->version == busVersion) {
                    return;
                }
                timespec delay{0, 1000000};
                nanosleep(&delay, nullptr);
            }
            munmap(state, sizeof(SharedState));
            state = nullptr;
            close(fd);
            fd = -1;
        }
    }

    ~Impl() {
        if (state != nullptr) {
            munmap(state, sizeof(SharedState));
        }
        if (fd >= 0) {
            close(fd);
        }
    }

    bool available() const noexcept {
        return state != nullptr
            && state->magic.load(std::memory_order_acquire) == busMagic
            && state->version == busVersion;
    }

    int fd{-1};
    std::string name;
    std::uint64_t token{0};
    SharedState* state{nullptr};
};

SharedBus::SharedBus(int session, std::uint64_t instanceToken)
    : impl(std::make_unique<Impl>(session, instanceToken)) {}

SharedBus::~SharedBus() {
    releaseController();
    for (std::size_t slot = 0; slot < targetCount; ++slot) {
        releaseTarget(slot);
    }
}

bool SharedBus::isAvailable() const noexcept {
    return impl != nullptr && impl->available();
}

ClaimResult SharedBus::claimController(std::uint64_t nowMs) noexcept {
    if (!isAvailable()) {
        return ClaimResult::unavailable;
    }
    auto& owner = impl->state->controllerToken;
    auto current = owner.load(std::memory_order_acquire);
    if (current == impl->token) {
        impl->state->controllerHeartbeat.store(nowMs, std::memory_order_release);
        return ClaimResult::owned;
    }
    const auto heartbeat = impl->state->controllerHeartbeat.load(
        std::memory_order_acquire
    );
    if (current != 0 && isFresh(heartbeat, nowMs)) {
        return ClaimResult::conflict;
    }
    if (owner.compare_exchange_strong(
            current,
            impl->token,
            std::memory_order_acq_rel,
            std::memory_order_acquire
        )) {
        impl->state->controllerHeartbeat.store(nowMs, std::memory_order_release);
        return ClaimResult::owned;
    }
    return ClaimResult::conflict;
}

void SharedBus::releaseController() noexcept {
    if (!isAvailable()) {
        return;
    }
    auto expected = impl->token;
    if (impl->state->controllerToken.compare_exchange_strong(
            expected,
            0,
            std::memory_order_acq_rel,
            std::memory_order_acquire
        )) {
        impl->state->controllerHeartbeat.store(0, std::memory_order_release);
    }
}

bool SharedBus::publish(
    const GainFrame& frame,
    bool unityOverride,
    std::uint64_t nowMs
) noexcept {
    if (!isAvailable()
        || impl->state->controllerToken.load(std::memory_order_acquire)
            != impl->token) {
        return false;
    }

    auto sequence = impl->state->frameSequence.load(std::memory_order_relaxed);
    if ((sequence & 1u) != 0u) {
        ++sequence;
    }
    impl->state->frameSequence.store(sequence + 1u, std::memory_order_release);
    for (std::size_t i = 0; i < frame.size(); ++i) {
        impl->state->gainBits[i].store(
            floatBits(frame[i]),
            std::memory_order_relaxed
        );
    }
    impl->state->unityOverride.store(
        unityOverride ? 1u : 0u,
        std::memory_order_relaxed
    );
    impl->state->frameSequence.store(sequence + 2u, std::memory_order_release);
    impl->state->controllerHeartbeat.store(nowMs, std::memory_order_release);
    return true;
}

FrameRead SharedBus::read(std::uint64_t nowMs) const noexcept {
    FrameRead result;
    result.gains.fill(1.0f);
    if (!isAvailable()) {
        return result;
    }

    const auto token = impl->state->controllerToken.load(std::memory_order_acquire);
    const auto heartbeat = impl->state->controllerHeartbeat.load(
        std::memory_order_acquire
    );
    if (token == 0 || !isFresh(heartbeat, nowMs)) {
        return result;
    }

    for (auto attempt = 0; attempt < 3; ++attempt) {
        const auto before = impl->state->frameSequence.load(
            std::memory_order_acquire
        );
        if ((before & 1u) != 0u) {
            continue;
        }
        for (std::size_t i = 0; i < result.gains.size(); ++i) {
            result.gains[i] = bitsFloat(
                impl->state->gainBits[i].load(std::memory_order_relaxed)
            );
        }
        result.unityOverride = impl->state->unityOverride.load(
            std::memory_order_relaxed
        ) != 0;
        const auto after = impl->state->frameSequence.load(
            std::memory_order_acquire
        );
        if (before == after && (after & 1u) == 0u) {
            result.connected = true;
            return result;
        }
    }
    return result;
}

ClaimResult SharedBus::claimTarget(
    std::size_t slot,
    std::uint64_t nowMs
) noexcept {
    if (!isAvailable() || slot >= targetCount) {
        return ClaimResult::unavailable;
    }
    auto& owner = impl->state->targetTokens[slot];
    auto current = owner.load(std::memory_order_acquire);
    if (current == impl->token) {
        impl->state->targetHeartbeats[slot].store(
            nowMs,
            std::memory_order_release
        );
        return ClaimResult::owned;
    }
    const auto heartbeat = impl->state->targetHeartbeats[slot].load(
        std::memory_order_acquire
    );
    if (current != 0 && isFresh(heartbeat, nowMs)) {
        return ClaimResult::conflict;
    }
    if (owner.compare_exchange_strong(
            current,
            impl->token,
            std::memory_order_acq_rel,
            std::memory_order_acquire
        )) {
        impl->state->targetHeartbeats[slot].store(
            nowMs,
            std::memory_order_release
        );
        return ClaimResult::owned;
    }
    return ClaimResult::conflict;
}

void SharedBus::releaseTarget(std::size_t slot) noexcept {
    if (!isAvailable() || slot >= targetCount) {
        return;
    }
    auto expected = impl->token;
    if (impl->state->targetTokens[slot].compare_exchange_strong(
            expected,
            0,
            std::memory_order_acq_rel,
            std::memory_order_acquire
        )) {
        impl->state->targetHeartbeats[slot].store(0, std::memory_order_release);
    }
}

int SharedBus::activeTargetCount(std::uint64_t nowMs) const noexcept {
    if (!isAvailable()) {
        return 0;
    }
    auto count = 0;
    for (std::size_t i = 0; i < targetCount; ++i) {
        const auto token = impl->state->targetTokens[i].load(
            std::memory_order_acquire
        );
        const auto heartbeat = impl->state->targetHeartbeats[i].load(
            std::memory_order_acquire
        );
        if (token != 0 && isFresh(heartbeat, nowMs)) {
            ++count;
        }
    }
    return count;
}

std::uint64_t SharedBus::monotonicMilliseconds() noexcept {
    timespec now{};
    clock_gettime(CLOCK_MONOTONIC, &now);
    return static_cast<std::uint64_t>(now.tv_sec) * 1000u
        + static_cast<std::uint64_t>(now.tv_nsec / 1000000u);
}

std::uint64_t SharedBus::makeInstanceToken(const void* address) noexcept {
    const auto now = monotonicMilliseconds();
    auto value = static_cast<std::uint64_t>(
        reinterpret_cast<std::uintptr_t>(address)
    );
    value ^= static_cast<std::uint64_t>(getpid()) << 32u;
    value ^= now + 0x9e3779b97f4a7c15ULL + (value << 6u) + (value >> 2u);
    return value == 0 ? 1 : value;
}

} // namespace mkxf
