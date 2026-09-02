#include "SharedBus.h"

#include <cmath>
#include <cstdlib>
#include <iostream>
#include <sys/wait.h>
#include <unistd.h>

namespace {

[[noreturn]] void fail(const char* message) {
    std::cerr << "FAIL: " << message << '\n';
    std::exit(1);
}

} // namespace

int main() {
    int readyPipe[2]{};
    int resultPipe[2]{};
    if (pipe(readyPipe) != 0 || pipe(resultPipe) != 0) {
        fail("Could not create process-link pipes");
    }

    const auto child = fork();
    if (child < 0) {
        fail("Could not fork Target process");
    }

    if (child == 0) {
        close(readyPipe[1]);
        close(resultPipe[0]);
        char signal = 0;
        if (read(readyPipe[0], &signal, 1) != 1) {
            _exit(2);
        }
        mkxf::SharedBus target(7, 0x707002);
        const auto now = mkxf::SharedBus::monotonicMilliseconds();
        const auto claim = target.claimTarget(3, now);
        const auto frame = target.read(now);
        const auto passed = claim == mkxf::ClaimResult::owned
            && frame.connected
            && std::abs(frame.gains[3] - 0.37f) < 1.0e-6f;
        const char result = passed ? 1 : 0;
        static_cast<void>(write(resultPipe[1], &result, 1));
        _exit(passed ? 0 : 3);
    }

    close(readyPipe[0]);
    close(resultPipe[1]);
    mkxf::SharedBus controller(7, 0x707001);
    const auto now = mkxf::SharedBus::monotonicMilliseconds();
    if (controller.claimController(now) != mkxf::ClaimResult::owned) {
        fail("Parent Controller could not claim session 7");
    }
    mkxf::GainFrame frame{};
    frame.fill(1.0f);
    frame[3] = 0.37f;
    if (!controller.publish(frame, false, now)) {
        fail("Parent Controller could not publish its frame");
    }

    const char signal = 1;
    if (write(readyPipe[1], &signal, 1) != 1) {
        fail("Could not wake Target process");
    }
    char result = 0;
    if (read(resultPipe[0], &result, 1) != 1) {
        fail("Target process returned no result");
    }
    int childStatus = 0;
    if (waitpid(child, &childStatus, 0) != child) {
        fail("Could not collect Target process");
    }
    if (!WIFEXITED(childStatus) || WEXITSTATUS(childStatus) != 0 || result != 1) {
        fail("Target process did not receive the Controller frame");
    }

    std::cout << "Cross-process Controller/Target link passed\n";
    return 0;
}
