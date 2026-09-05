#include "SharedBus.h"

#include <array>
#include <algorithm>
#include <atomic>
#include <cstring>
#include <limits>
#include <new>
#include <string>

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#else
#include <cerrno>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#endif

namespace mkxf {
namespace {

constexpr std::uint32_t busMagic = 0x4d4b5846;
constexpr std::uint32_t busVersion = 2;
constexpr std::uint64_t staleAfterMs = 2000;
#if defined(MK_CROSSFADER_TEST_BUS)
constexpr char busName[] = "mk_crossfader_test_v2_";
#else
constexpr char busName[] = "mk_crossfader_v2_";
#endif

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

std::uint32_t ownerId(std::uint64_t value) noexcept {
    return static_cast<std::uint32_t>(value >> 32u);
}

std::uint64_t tagged(std::uint32_t owner, std::uint32_t value) noexcept {
    return (static_cast<std::uint64_t>(owner) << 32u) | value;
}

bool isFresh(std::uint64_t lease, std::uint64_t now) noexcept {
    const auto age = static_cast<std::uint32_t>(now) - static_cast<std::uint32_t>(lease);
    // A newer heartbeat can be observed after a callback captures its time.
    // Unsigned subtraction also handles the 32-bit millisecond clock wrapping.
    return ownerId(lease) != 0
        && (age <= staleAfterMs || age >= 0xffffffffu - staleAfterMs);
}

bool renewLease(std::atomic<std::uint64_t>& lease, std::uint32_t id, std::uint64_t now) noexcept {
    auto current = lease.load();
    if (id == 0 || ownerId(current) != id) { return false; }
    now = std::max(now, SharedBus::monotonicMilliseconds());
    const auto age = static_cast<std::uint32_t>(now) - static_cast<std::uint32_t>(current);
    const auto time = age >= 0xffffffffu - staleAfterMs
        ? static_cast<std::uint32_t>(current) : static_cast<std::uint32_t>(now);
    return lease.compare_exchange_strong(current, tagged(id, time));
}

ClaimResult claimLease(
    std::atomic<std::uint64_t>& lease,
    std::atomic<std::uint64_t>& nextId,
    std::uint32_t& localId,
    std::uint64_t now
) noexcept {
    auto current = lease.load();
    now = std::max(now, SharedBus::monotonicMilliseconds());
    if (ownerId(current) != 0 && ownerId(current) == localId) {
        return renewLease(lease, localId, now)
            ? ClaimResult::owned : ClaimResult::conflict;
    }
    if (isFresh(current, now)) { return ClaimResult::conflict; }
    const auto candidate = nextId.fetch_add(1);
    if (candidate > std::numeric_limits<std::uint32_t>::max()) {
        return ClaimResult::unavailable;
    }
    const auto id = static_cast<std::uint32_t>(candidate);
    if (!lease.compare_exchange_strong(current, tagged(id, static_cast<std::uint32_t>(now)))) {
        return ClaimResult::conflict;
    }
    localId = id;
    return ClaimResult::owned;
}

void releaseLease(std::atomic<std::uint64_t>& lease, std::uint32_t& localId) noexcept {
    auto current = lease.load();
    if (localId != 0 && ownerId(current) == localId) {
        lease.compare_exchange_strong(current, 0);
    }
    localId = 0;
}

void waitForInitialization() noexcept {
#if defined(_WIN32)
    Sleep(1);
#else
    timespec delay{0, 1000000};
    nanosleep(&delay, nullptr);
#endif
}

struct SharedState {
    std::atomic<std::uint32_t> magic{0};
    std::uint32_t version{busVersion};
    std::atomic<std::uint64_t> nextClaimId{1};
    std::atomic<std::uint64_t> controllerLease{0};
    std::atomic<std::uint64_t> frameSequence{0};
    std::array<std::atomic<std::uint64_t>, targetCount> gainBits{};
    std::atomic<std::uint64_t> unityOverride{0};
    std::array<std::atomic<std::uint64_t>, targetCount> targetLeases{};
};

} // namespace

struct SharedBus::Impl {
    explicit Impl(int session) {
        const auto safeSession = session < 1 ? 1 : (session > 8 ? 8 : session);

#if defined(_WIN32)
        name = L"Local\\" + std::wstring(busName, busName + std::strlen(busName))
            + std::to_wstring(safeSession);
        mapping = CreateFileMappingW(
            INVALID_HANDLE_VALUE,
            nullptr,
            PAGE_READWRITE,
            0,
            static_cast<DWORD>(sizeof(SharedState)),
            name.c_str()
        );
        if (mapping == nullptr) {
            return;
        }
        const auto created = GetLastError() != ERROR_ALREADY_EXISTS;
        void* mapped = MapViewOfFile(
            mapping,
            FILE_MAP_ALL_ACCESS,
            0,
            0,
            sizeof(SharedState)
        );
        if (mapped == nullptr) {
            CloseHandle(mapping);
            mapping = nullptr;
            return;
        }
#else
        name = std::string("/") + busName + std::to_string(getuid()) + "_"
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

        // Another process may have created the object but not sized it yet.
        struct stat info{};
        for (auto attempt = 0; attempt < 100; ++attempt) {
            if (fstat(fd, &info) == 0 && info.st_size >= static_cast<off_t>(sizeof(SharedState))) {
                break;
            }
            waitForInitialization();
        }
        if (info.st_size < static_cast<off_t>(sizeof(SharedState))) {
            close(fd);
            fd = -1;
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
#endif

#if defined(_WIN32)
        state = static_cast<SharedState*>(mapped);
#endif

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
                waitForInitialization();
            }
#if defined(_WIN32)
            UnmapViewOfFile(state);
            state = nullptr;
            CloseHandle(mapping);
            mapping = nullptr;
#else
            munmap(state, sizeof(SharedState));
            state = nullptr;
            close(fd);
            fd = -1;
#endif
        }
    }

    ~Impl() {
        if (state != nullptr) {
#if defined(_WIN32)
            UnmapViewOfFile(state);
#else
            munmap(state, sizeof(SharedState));
#endif
        }
#if defined(_WIN32)
        if (mapping != nullptr) {
            CloseHandle(mapping);
        }
#else
        if (fd >= 0) {
            close(fd);
        }
#endif
    }

    bool available() const noexcept {
        return state != nullptr
            && state->magic.load(std::memory_order_acquire) == busMagic
            && state->version == busVersion;
    }

#if defined(_WIN32)
    HANDLE mapping{nullptr};
    std::wstring name;
#else
    int fd{-1};
    std::string name;
#endif
    std::uint32_t controllerId{0};
    std::uint32_t frameNumber{0};
    std::array<std::uint32_t, targetCount> targetIds{};
    SharedState* state{nullptr};
};

SharedBus::SharedBus(int session)
    : impl(std::make_unique<Impl>(session)) {}

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
    return claimLease(impl->state->controllerLease, impl->state->nextClaimId,
        impl->controllerId, nowMs);
}

void SharedBus::releaseController() noexcept {
    if (!isAvailable()) {
        return;
    }
    releaseLease(impl->state->controllerLease, impl->controllerId);
}

bool SharedBus::publish(
    const GainFrame& frame,
    bool unityOverride,
    std::uint64_t nowMs
) noexcept {
    if (!isAvailable() || impl->controllerId == 0
        || ownerId(impl->state->controllerLease.load()) != impl->controllerId) {
        return false;
    }
    const auto id = impl->controllerId;
    impl->frameNumber += 2u;
    // Tag every cell as well as the sequence. A stalled former publisher may
    // resume after takeover; its writes must never be accepted as the new frame.
    impl->state->frameSequence.store(tagged(id, impl->frameNumber - 1u));
    for (std::size_t i = 0; i < frame.size(); ++i) {
        impl->state->gainBits[i].store(tagged(id, floatBits(frame[i])));
    }
    impl->state->unityOverride.store(tagged(id, unityOverride ? 1u : 0u));
    impl->state->frameSequence.store(tagged(id, impl->frameNumber));
    return renewLease(impl->state->controllerLease, id, nowMs);
}

FrameRead SharedBus::read(std::uint64_t nowMs) const noexcept {
    FrameRead result;
    result.gains.fill(1.0f);
    if (!isAvailable()) {
        return result;
    }

    for (auto attempt = 0; attempt < 3; ++attempt) {
        const auto lease = impl->state->controllerLease.load();
        const auto id = ownerId(lease);
        const auto before = impl->state->frameSequence.load();
        if (!isFresh(lease, nowMs) || ownerId(before) != id || (before & 1u) != 0u) {
            continue;
        }
        auto valid = true;
        for (std::size_t i = 0; i < result.gains.size(); ++i) {
            const auto gain = impl->state->gainBits[i].load();
            valid = valid && ownerId(gain) == id;
            result.gains[i] = bitsFloat(static_cast<std::uint32_t>(gain));
        }
        const auto unity = impl->state->unityOverride.load();
        result.unityOverride = static_cast<std::uint32_t>(unity) != 0;
        const auto after = impl->state->frameSequence.load();
        const auto finalLease = impl->state->controllerLease.load();
        if (valid && ownerId(unity) == id && before == after
            && ownerId(finalLease) == id && isFresh(finalLease, nowMs)) {
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
    return claimLease(impl->state->targetLeases[slot], impl->state->nextClaimId,
        impl->targetIds[slot], nowMs);
}

void SharedBus::releaseTarget(std::size_t slot) noexcept {
    if (!isAvailable() || slot >= targetCount) {
        return;
    }
    releaseLease(impl->state->targetLeases[slot], impl->targetIds[slot]);
}

int SharedBus::activeTargetCount(std::uint64_t nowMs) const noexcept {
    if (!isAvailable()) {
        return 0;
    }
    auto count = 0;
    for (std::size_t i = 0; i < targetCount; ++i) {
        if (isFresh(impl->state->targetLeases[i].load(), nowMs)) {
            ++count;
        }
    }
    return count;
}

std::uint64_t SharedBus::monotonicMilliseconds() noexcept {
#if defined(_WIN32)
    return static_cast<std::uint64_t>(GetTickCount64());
#else
    timespec now{};
    clock_gettime(CLOCK_MONOTONIC, &now);
    return static_cast<std::uint64_t>(now.tv_sec) * 1000u
        + static_cast<std::uint64_t>(now.tv_nsec / 1000000u);
#endif
}

} // namespace mkxf
