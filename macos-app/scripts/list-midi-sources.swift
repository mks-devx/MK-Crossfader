import CoreMIDI
import Foundation

func endpointName(_ endpoint: MIDIEndpointRef) -> String {
    var unmanagedName: Unmanaged<CFString>?
    guard MIDIObjectGetStringProperty(
        endpoint,
        kMIDIPropertyDisplayName,
        &unmanagedName
    ) == noErr,
        let name = unmanagedName?.takeRetainedValue()
    else {
        return "MIDI Source"
    }
    return name as String
}

for index in 0..<MIDIGetNumberOfSources() {
    let endpoint = MIDIGetSource(index)
    var uniqueID: MIDIUniqueID = 0
    MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID)
    print("\(endpointName(endpoint)) · ID \(uniqueID)")
}
