#include "SharedBus.h"

#include <cmath>
#include <cstdlib>
#include <iostream>

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <array>
#include <cwchar>
#include <process.h>
#include <windows.h>
#else
#include <sys/wait.h>
#include <unistd.h>
#endif

namespace {

[[noreturn]] void fail(const char* message) {
    std::cerr << "FAIL: " << message << '\n';
    std::exit(1);
}

int runTargetProcess() {
    mkxf::SharedBus target(7);
    const auto now = mkxf::SharedBus::monotonicMilliseconds();
    const auto claim = target.claimTarget(3, now);
    const auto frame = target.read(now);
    const auto passed = claim == mkxf::ClaimResult::owned
        && frame.connected
        && std::abs(frame.gains[3] - 0.37f) < 1.0e-6f;
    return passed ? 0 : 3;
}

void publishControllerFrame(mkxf::SharedBus& controller) {
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
}

} // namespace

#if defined(_WIN32)

int wmain(int argc, wchar_t** argv) {
    if (argc == 2 && std::wcscmp(argv[1], L"--target") == 0) {
        return runTargetProcess();
    }

    mkxf::SharedBus controller(7);
    publishControllerFrame(controller);

    std::array<wchar_t, 32768> executable{};
    const auto length = GetModuleFileNameW(
        nullptr,
        executable.data(),
        static_cast<DWORD>(executable.size())
    );
    if (length == 0
        || length == static_cast<DWORD>(executable.size())) {
        fail("Could not resolve the process-link test executable");
    }

    const wchar_t* childArguments[] = {
        executable.data(),
        L"--target",
        nullptr,
    };
    const auto childStatus = _wspawnv(
        _P_WAIT,
        executable.data(),
        childArguments
    );
    if (childStatus != 0) {
        fail("Target process did not receive the Controller frame");
    }

    std::cout << "Cross-process Controller/Target link passed\n";
    return 0;
}

#else

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
        const auto status = runTargetProcess();
        const char result = status == 0 ? 1 : 0;
        static_cast<void>(write(resultPipe[1], &result, 1));
        _exit(status);
    }

    close(readyPipe[0]);
    close(resultPipe[1]);
    mkxf::SharedBus controller(7);
    publishControllerFrame(controller);

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

#endif
