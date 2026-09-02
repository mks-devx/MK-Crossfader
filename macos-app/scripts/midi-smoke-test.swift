import AppKit
import CoreMIDI
import Darwin
import Foundation

let bundleID = "com.mk.midicrossfader"
let testSourceName = "MK Crossfader Test Input"
let scriptDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let appRoot = scriptDirectory.deletingLastPathComponent()
let defaultAppURL = appRoot
    .appendingPathComponent("build")
    .appendingPathComponent("MK MIDI Crossfader.app")
let appURL = CommandLine.arguments.dropFirst().first.map {
    URL(fileURLWithPath: $0)
} ?? defaultAppURL

let defaults = UserDefaults(suiteName: bundleID)!
let savedDomain = defaults.persistentDomain(forName: bundleID)

func terminateApp() {
    for application in NSRunningApplication.runningApplications(
        withBundleIdentifier: bundleID
    ) {
        application.terminate()
    }
    usleep(700_000)
}

func launchApp(activeForAutomation: Bool = false) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-na"]
    if activeForAutomation {
        process.arguments?.append(contentsOf: [
            "--env",
            "MK_CROSSFADER_AUTOMATION_START_ACTIVE=1",
        ])
    }
    process.arguments?.append(appURL.path)
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(domain: "MIDISmokeTest", code: 1)
    }
}

func endpointName(_ endpoint: MIDIEndpointRef) -> String {
    var unmanagedName: Unmanaged<CFString>?
    guard MIDIObjectGetStringProperty(
        endpoint,
        kMIDIPropertyDisplayName,
        &unmanagedName
    ) == noErr,
        let name = unmanagedName?.takeRetainedValue()
    else {
        return ""
    }
    return name as String
}

func source(named name: String) -> MIDIEndpointRef? {
    for index in 0..<MIDIGetNumberOfSources() {
        let endpoint = MIDIGetSource(index)
        if endpointName(endpoint) == name {
            return endpoint
        }
    }
    return nil
}

func sendCC(
    to source: MIDIEndpointRef,
    controller: UInt8,
    value: UInt8
) {
    let bytes: [UInt8] = [0xB0, controller, value]
    var packetList = MIDIPacketList()
    let packet = MIDIPacketListInit(&packetList)

    bytes.withUnsafeBufferPointer { buffer in
        _ = MIDIPacketListAdd(
            &packetList,
            MemoryLayout<MIDIPacketList>.size,
            packet,
            0,
            buffer.count,
            buffer.baseAddress!
        )
    }
    MIDIReceived(source, &packetList)
}

final class MessageStore {
    private let lock = NSLock()
    private var messages: [(controller: UInt8, value: UInt8)] = []

    func append(controller: UInt8, value: UInt8) {
        lock.lock()
        messages.append((controller, value))
        lock.unlock()
    }

    func snapshot() -> [(controller: UInt8, value: UInt8)] {
        lock.lock()
        defer { lock.unlock() }
        return messages
    }
}

func restorePreferencesAndRelaunch() {
    terminateApp()
    if let savedDomain {
        defaults.setPersistentDomain(savedDomain, forName: bundleID)
    } else {
        defaults.removePersistentDomain(forName: bundleID)
    }
    defaults.synchronize()
    try? launchApp()
}

var client: MIDIClientRef = 0
var testSource: MIDIEndpointRef = 0
var monitorPort: MIDIPortRef = 0
let messages = MessageStore()

guard MIDIClientCreate("MK Crossfader Smoke Test" as CFString, nil, nil, &client) == noErr,
    MIDISourceCreate(client, testSourceName as CFString, &testSource) == noErr
else {
    fputs("Could not create the test MIDI source.\n", stderr)
    exit(1)
}

var testSourceID: MIDIUniqueID = 0
guard MIDIObjectGetIntegerProperty(
    testSource,
    kMIDIPropertyUniqueID,
    &testSourceID
) == noErr else {
    fputs("Could not read the temporary MIDI source ID.\n", stderr)
    exit(1)
}

terminateApp()
defaults.set(Int(testSourceID), forKey: "selectedSourceID")
defaults.set(0, forKey: "inputChannel")
defaults.set(7, forKey: "inputController")
defaults.set(false, forKey: "enabled")
defaults.set(15, forKey: "outputChannel")
defaults.set(110, forKey: "controllerA")
defaults.set(111, forKey: "controllerB")
let targetData = try! JSONSerialization.data(
    withJSONObject: [
        [
            "id": UUID().uuidString,
            "name": "Group A",
            "controller": 110,
            "side": "a",
        ],
        [
            "id": UUID().uuidString,
            "name": "Group B",
            "controller": 111,
            "side": "b",
        ],
    ]
)
defaults.set(targetData, forKey: "targets")
defaults.set("standard", forKey: "mode")
defaults.set("fullCentre", forKey: "curve")
defaults.set(false, forKey: "reversed")
defaults.set("kill", forKey: "minimumLevel")
defaults.synchronize()

do {
    try launchApp(activeForAutomation: true)
} catch {
    restorePreferencesAndRelaunch()
    fputs("Could not launch the app.\n", stderr)
    exit(1)
}

usleep(1_000_000)

guard let outputSource = source(named: "MK Crossfader") else {
    restorePreferencesAndRelaunch()
    fputs("The MK Crossfader virtual source was not found.\n", stderr)
    exit(1)
}

MIDIInputPortCreateWithBlock(
    client,
    "Output Monitor" as CFString,
    &monitorPort
) { packetList, _ in
    var packet = packetList.pointee.packet
    for _ in 0..<packetList.pointee.numPackets {
        withUnsafeBytes(of: packet.data) { rawBuffer in
            let byteCount = min(Int(packet.length), rawBuffer.count)
            let bytes = Array(rawBuffer.prefix(byteCount))
            var index = 0
            while index + 2 < bytes.count {
                let status = UInt8(bytes[index])
                if status & 0xF0 == 0xB0 {
                    messages.append(
                        controller: UInt8(bytes[index + 1]),
                        value: UInt8(bytes[index + 2])
                    )
                }
                index += 3
            }
        }
        packet = MIDIPacketNext(&packet).pointee
    }
}

guard MIDIPortConnectSource(monitorPort, outputSource, nil) == noErr else {
    restorePreferencesAndRelaunch()
    fputs("Could not monitor the MK Crossfader output.\n", stderr)
    exit(1)
}

for value: UInt8 in [0, 63, 64, 127] {
    sendCC(to: testSource, controller: 7, value: value)
    usleep(180_000)
}

usleep(300_000)
let received = messages.snapshot()

let expected: [(UInt8, UInt8)] = [
    (110, 95), (111, 0),
    (110, 95), (111, 95),
    (110, 0), (111, 95)
]

let passed = expected.allSatisfy { expectedMessage in
    received.contains {
        $0.controller == expectedMessage.0 && $0.value == expectedMessage.1
    }
}

let dedupStart = messages.snapshot().count
for _ in 0..<100 {
    sendCC(to: testSource, controller: 7, value: 64)
}
usleep(300_000)
let deduplicatedOutputCount = messages.snapshot().count - dedupStart
let dedupPassed = deduplicatedOutputCount <= 2

for index in 0..<1024 {
    sendCC(
        to: testSource,
        controller: 7,
        value: UInt8(index % 128)
    )
}
usleep(1_500_000)
sendCC(to: testSource, controller: 7, value: 127)
usleep(500_000)

let stressMessages = messages.snapshot()
let finalExpected: [(UInt8, UInt8)] = [
    (110, 0), (111, 95)
]
let finalValuesPassed = finalExpected.allSatisfy { expectedMessage in
    stressMessages.last(where: { $0.controller == expectedMessage.0 })?.value
        == expectedMessage.1
}
let appSurvived = !NSRunningApplication.runningApplications(
    withBundleIdentifier: bundleID
).isEmpty

restorePreferencesAndRelaunch()

if passed, dedupPassed, finalValuesPassed, appSurvived {
    print("PASS: mapping, deduplication, and 1,024-message burst test matched.")
    exit(0)
}

print("Initial values passed: \(passed)")
print("Deduplication passed: \(dedupPassed)")
print("Final values passed: \(finalValuesPassed)")
print("App survived: \(appSurvived)")
fputs("FAIL: MIDI mapping or burst verification failed.\n", stderr)
exit(1)
