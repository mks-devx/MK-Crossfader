import Foundation
import Testing
import CrossfaderCore
@testable import MKMIDICrossfader

@Suite struct XYZPresetTests {
    @Test func legacyAndCorruptNewFields() throws {
        let old = Data(#"{"name":"Old","controller":110,"side":"a","kind":"maschineLevel"}"#.utf8)
        let target = try JSONDecoder().decode(CrossfadeTarget.self, from: old)
        #expect(target.inputAxis == .x)
        #expect(target.releasePolicy == .hold)
        let bad = Data(#"{"name":"Old","controller":110,"inputAxis":3,"releasePolicy":"future"}"#.utf8)
        let decoded = try JSONDecoder().decode(CrossfadeTarget.self, from: bad)
        #expect(decoded.inputAxis == .x)
        #expect(decoded.releasePolicy == .hold)
        let scene = try JSONDecoder().decode(CrossfaderScenePreset.self, from: Data(#"{"name":"Old"}"#.utf8))
        #expect(scene.inputMode == .single)
    }
    @Test func presetRoundTripAndBuiltInsKeepRouting() throws {
        var target = CrossfadeTarget(name: "Pressure", controller: 112, side: .b, kind: .customMIDI)
        target.inputAxis = .z
        target.releasePolicy = .returnValue
        for preset in BuiltInCrossfadePreset.allCases {
            let result = preset.applying(to: [target])[0]
            #expect(result.inputAxis == .z)
            #expect(result.releasePolicy == .returnValue)
        }
        let scene = CrossfaderScenePreset(name: "XYZ", targets: [target], mode: .standard, curve: .linear, minimumLevel: .kill, isReversed: false, isTravelReversed: false, inputMode: .xyz)
        let data = try JSONEncoder().encode(scene)
        #expect(try JSONDecoder().decode(CrossfaderScenePreset.self, from: data) == scene)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["selectedSourceID"] == nil)
        #expect(object["inputConfiguration"] == nil)
    }
}
