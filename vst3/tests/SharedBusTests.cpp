#include "SharedBus.h"

#include <atomic>
#include <cstdlib>
#include <iostream>
#include <thread>

namespace {
void require(bool condition, const char* message) {
    if (!condition) { std::cerr << message << '\n'; std::exit(1); }
}

void ownershipAndHandover() {
    mkxf::SharedBus first(8), second(8), target(8);
    require(first.isAvailable() && second.isAvailable(), "Shared memory unavailable");
    const auto now = mkxf::SharedBus::monotonicMilliseconds() + 100;
    require(first.claimController(now + 1) == mkxf::ClaimResult::owned, "Initial Controller claim failed");
    require(second.claimController(now) == mkxf::ClaimResult::conflict, "Newer Controller heartbeat was stolen");
    require(first.claimTarget(0, now + 1) == mkxf::ClaimResult::owned, "Initial Target claim failed");
    require(second.claimTarget(0, now) == mkxf::ClaimResult::conflict, "Newer Target heartbeat was stolen");
    require(target.activeTargetCount(now) == 1, "Newer Target heartbeat was hidden");
    mkxf::GainFrame frame{};
    frame.fill(0.12f);
    require(first.publish(frame, false, now + 1), "Initial publish failed");
    require(target.read(now).connected, "Newer frame heartbeat was hidden");
    first.releaseController();
    require(second.claimController(now + 2) == mkxf::ClaimResult::owned, "Replacement claim failed");
    require(!target.read(now + 2).connected, "Replacement exposed a former owner's frame");
    require(!first.publish(frame, true, now + 2), "Former owner published after release");
    first.releaseController();
    frame.fill(0.75f);
    require(second.publish(frame, true, now + 2), "Replacement publish failed");
    const auto read = target.read(now + 2);
    require(read.connected && read.gains[0] == 0.75f && read.unityOverride, "Replacement frame was incorrect");
    second.releaseController();
    require(second.claimController(now + 3) == mkxf::ClaimResult::owned, "Same-instance reacquisition failed");
    require(!target.read(now + 3).connected, "Reacquisition exposed its previous frame");
    require(first.claimTarget(0, now + 3000) == mkxf::ClaimResult::owned, "Target renewal failed");
    require(second.claimTarget(0, now + 3001) == mkxf::ClaimResult::conflict, "Renewed Target was stolen");
    require(second.claimTarget(0, now + 6000) == mkxf::ClaimResult::owned, "Stale Target was not recovered");
    first.releaseTarget(0);
    require(target.activeTargetCount(now + 6000) == 1, "Former owner cleared the replacement Target");
    require(first.claimController(now + 6000) == mkxf::ClaimResult::owned, "Stale Controller was not recovered");
    second.releaseController();
    require(first.publish(frame, false, now + 6000), "Former owner cleared replacement Controller");
}

void clockWrap() {
    mkxf::SharedBus first(8), second(8);
    const std::uint64_t wrap = 0x100000000ULL;
    require(first.claimController(wrap - 10) == mkxf::ClaimResult::owned, "Pre-wrap claim failed");
    require(second.claimController(wrap + 10) == mkxf::ClaimResult::conflict, "Clock wrap stole a fresh lease");
    require(second.claimController(wrap + 2010) == mkxf::ClaimResult::owned, "Expired wrapped lease was not recovered");
    second.releaseController();
    require(first.claimController(wrap + 3000) == mkxf::ClaimResult::owned, "Lease setup failed");
    require(second.claimController(wrap + 0x90000000ULL) == mkxf::ClaimResult::owned, "Long-idle lease was mistaken for a future heartbeat");
}

void concurrentTransfers() {
    mkxf::SharedBus first(8), second(8), reader(8);
    std::atomic<bool> start{false};
    std::atomic<int> finished{0}, failures{0}, received{0};
    auto publish = [&](mkxf::SharedBus& bus, float gain) {
        while (!start.load()) { std::this_thread::yield(); }
        mkxf::GainFrame frame{};
        frame.fill(gain);
        for (int i = 0; i < 20000; ++i) {
            const auto now = mkxf::SharedBus::monotonicMilliseconds();
            if (bus.claimController(now) == mkxf::ClaimResult::owned) {
                if (!bus.publish(frame, gain == 0.75f, now)) { ++failures; }
                if (i % 4 == 0) { bus.releaseController(); }
            }
        }
        bus.releaseController();
        ++finished;
    };
    std::thread a(publish, std::ref(first), 0.25f);
    std::thread b(publish, std::ref(second), 0.75f);
    start.store(true);
    while (finished.load() != 2) {
        const auto frame = reader.read(mkxf::SharedBus::monotonicMilliseconds());
        if (!frame.connected) { continue; }
        ++received;
        const auto expected = frame.unityOverride ? 0.75f : 0.25f;
        for (const auto gain : frame.gains) {
            if (gain != expected) { ++failures; }
        }
    }
    a.join(); b.join();
    require(received.load() > 0, "Concurrent test did not observe any frames");
    require(failures.load() == 0, "Concurrent ownership or frame integrity failed");
}
}

int main() {
    ownershipAndHandover();
    clockWrap();
    concurrentTransfers();
    std::cout << "Shared bus ownership, handover, clock wrap and concurrency passed\n";
}
