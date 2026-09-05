import CrossfaderCore
import Testing
@testable import MKMIDICrossfader

@Test("Built-in presets use neutral names and the original curves")
func builtInPresetDefinitions() {
    #expect(BuiltInCrossfadePreset.allCases.map(\.displayName)
        == ["Performance A/B", "Scene Morph"])
    #expect(BuiltInCrossfadePreset.performanceAB.curve == .fullCentre)
    #expect(BuiltInCrossfadePreset.sceneMorph.curve == .smooth)
}

@Test("Built-in presets preserve all target data except the intended behaviour",
      arguments: BuiltInCrossfadePreset.allCases)
func builtInPresetsPreserveMappings(preset: BuiltInCrossfadePreset) {
    let targets = [
        CrossfadeTarget(
            name: "Level A", controller: 25, side: .a, transition: .range,
            customLeftPercent: 87, customRightPercent: 12,
            parameterCurve: .exponential, restorePercent: 60
        ),
        CrossfadeTarget(
            name: "Level B", controller: 26, side: .b, transition: .crossfade
        ),
        CrossfadeTarget(
            name: "Filter", controller: 90, side: .b, kind: .customMIDI,
            transition: .range, customLeftPercent: 24, customRightPercent: 64,
            parameterCurve: .logarithmic, restorePercent: 18
        ),
        CrossfadeTarget(
            name: "Parameter A", controller: 91, side: .a, kind: .customMIDI,
            transition: .crossfade
        ),
        CrossfadeTarget(name: "Off", controller: 92, side: .off),
        CrossfadeTarget(
            name: "Legacy", controller: 93, side: .b, kind: .mkGain,
            transition: .range
        ),
    ]
    let result = preset.applying(to: targets)
    #expect(result.count == targets.count)
    for (original, updated) in zip(targets, result) {
        var expected = original
        if original.participatesInOutput {
            if preset == .sceneMorph {
                expected.transition = .range
            } else if original.kind != .customMIDI {
                expected.transition = .crossfade
            }
        }
        #expect(updated == expected)
    }
    #expect(preset.applying(to: result) == result)
}

@Test("Built-in presets do not invent targets in an empty setup")
func emptyBuiltInPreset() {
    for preset in BuiltInCrossfadePreset.allCases {
        #expect(preset.applying(to: []).isEmpty)
    }
}
