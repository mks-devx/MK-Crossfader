import Foundation
import Testing
@testable import MKMIDICrossfader

@Suite struct SettingsStoreTests {
    @Test func roundTripAndIsolation() {
        let a = MemorySettingsStore()
        let b = MemorySettingsStore()
        a.set(42, forKey: "int")
        a.set(true, forKey: "bool")
        a.set("value", forKey: "string")
        a.set(Data([0, 127]), forKey: "data")
        #expect(a.integer(forKey: "int") == 42)
        #expect(a.bool(forKey: "bool"))
        #expect(a.string(forKey: "string") == "value")
        #expect(a.data(forKey: "data") == Data([0, 127]))
        #expect(b.object(forKey: "int") == nil)
        #expect(b.integer(forKey: "missing") == 0)
        #expect(!b.bool(forKey: "missing"))
        a.removeObject(forKey: "int")
        #expect(a.object(forKey: "int") == nil)
    }
}
