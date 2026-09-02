import CrossfaderCore
import Foundation
import Testing
@testable import MKMIDICrossfader

@Test("Legacy targets decode with compatible defaults")
func legacyTargetDefaults() throws {
    let id = UUID()
    let data = Data(
        """
        {
          "id": "\(id.uuidString)",
          "name": "Legacy A",
          "controller": 110,
          "side": "a",
          "kind": "maschineLevel"
        }
        """.utf8
    )

    let target = try JSONDecoder().decode(CrossfadeTarget.self, from: data)

    #expect(target.id == id)
    #expect(target.transition == .crossfade)
    #expect(target.customLeftPercent == 100)
    #expect(target.customRightPercent == 0)
    #expect(target.parameterCurve == .inherit)
    #expect(target.restorePercent == 100)
}

@Test("One behaviour maps cleanly to the stored routing model")
func targetBehaviorMapping() {
    var target = CrossfadeTarget(
        name: "Target",
        controller: 112,
        side: .off
    )

    #expect(target.behavior == .off)
    #expect(target.participatesInOutput == false)

    target.apply(.sideA)
    #expect(target.behavior == .sideA)
    #expect(target.side == .a)
    #expect(target.transition == .crossfade)

    target.apply(.sideB)
    #expect(target.behavior == .sideB)
    #expect(target.side == .b)
    #expect(target.transition == .crossfade)

    target.apply(.off)
    #expect(target.behavior == .off)
    #expect(target.participatesInOutput == false)
}

@Test("A fresh range starts across the full fader travel")
func freshRangeDefaults() {
    var target = CrossfadeTarget(
        name: "Parameter",
        controller: 112,
        side: .off
    )

    target.apply(.range)

    #expect(target.behavior == .range)
    #expect(target.customLeftPercent == 0)
    #expect(target.customRightPercent == 100)
}

@Test("Akai Force preset restores A/B mixing without changing parameters")
func akaiForcePreset() {
    let targets = [
        CrossfadeTarget(
            name: "Group A",
            controller: 110,
            side: .a,
            transition: .range,
            customLeftPercent: 82,
            customRightPercent: 17
        ),
        CrossfadeTarget(
            name: "Filter",
            controller: 112,
            side: .b,
            kind: .customMIDI,
            transition: .range,
            customLeftPercent: 4,
            customRightPercent: 63
        ),
        CrossfadeTarget(name: "Off", controller: 113, side: .off),
    ]

    let result = BuiltInCrossfadePreset.akaiForce.applying(to: targets)

    #expect(result[0].behavior == .sideA)
    #expect(result[0].customLeftPercent == 82)
    #expect(result[0].customRightPercent == 17)
    #expect(result[1].behavior == .range)
    #expect(result[1].customLeftPercent == 4)
    #expect(result[1].customRightPercent == 63)
    #expect(result[2].behavior == .off)
    #expect(result.map(\.controller) == [110, 112, 113])
    #expect(result.map(\.name) == ["Group A", "Filter", "Off"])
    #expect(BuiltInCrossfadePreset.akaiForce.curve == .fullCentre)
}

@Test("Octatrack preset morphs every active target using stored endpoints")
func octatrackPreset() {
    let targets = [
        CrossfadeTarget(name: "A", controller: 110, side: .a),
        CrossfadeTarget(name: "B", controller: 111, side: .b),
        CrossfadeTarget(name: "Off", controller: 112, side: .off),
    ]

    let result = BuiltInCrossfadePreset.octatrack.applying(to: targets)

    #expect(result[0].behavior == .range)
    #expect(result[0].customLeftPercent == 100)
    #expect(result[0].customRightPercent == 0)
    #expect(result[1].behavior == .range)
    #expect(result[1].customLeftPercent == 0)
    #expect(result[1].customRightPercent == 100)
    #expect(result[2].behavior == .off)
    #expect(BuiltInCrossfadePreset.octatrack.curve == .smooth)
}

@Test("Target initializer clamps every percentage")
func targetInitializerClampsPercentages() {
    let target = CrossfadeTarget(
        name: "Range",
        controller: 112,
        customLeftPercent: -20,
        customRightPercent: 140,
        restorePercent: 120
    )

    #expect(target.customLeftPercent == 0)
    #expect(target.customRightPercent == 100)
    #expect(target.restorePercent == 100)
}

@Test("Unknown stored target values fall back without losing the mapping")
func unknownTargetEnumFallbacks() throws {
    let data = Data(
        """
        {
          "name": "Future Target",
          "controller": 112,
          "side": "future-side",
          "kind": "future-kind",
          "transition": "future-transition",
          "customLeftPercent": -20,
          "customRightPercent": 140,
          "parameterCurve": "future-curve",
          "restorePercent": 150
        }
        """.utf8
    )

    let target = try JSONDecoder().decode(CrossfadeTarget.self, from: data)

    #expect(target.controller == 112)
    #expect(target.side == .off)
    #expect(target.kind == .maschineLevel)
    #expect(target.transition == .crossfade)
    #expect(target.customLeftPercent == 0)
    #expect(target.customRightPercent == 100)
    #expect(target.parameterCurve == .inherit)
    #expect(target.restorePercent == 100)
}

@Test("Target sanitizing removes unsafe and ambiguous mappings")
func targetSanitizing() {
    let sharedID = UUID()
    let candidates = [
        CrossfadeTarget(id: sharedID, name: "A", controller: 110),
        CrossfadeTarget(name: "Duplicate CC", controller: 110),
        CrossfadeTarget(id: sharedID, name: "Duplicate ID", controller: 111),
        CrossfadeTarget(name: "Invalid low", controller: -1),
        CrossfadeTarget(name: "Invalid high", controller: 128),
        CrossfadeTarget(name: "B", controller: 111)
    ]

    let result = CrossfadeConfigurationSanitizer.targets(candidates)

    #expect(result.map(\.name) == ["A", "B"])
    #expect(result.map(\.controller) == [110, 111])
}

@Test("Sanitizing preserves an intentional flat range")
func flatRangeIsPreserved() {
    let target = CrossfadeTarget(
        name: "Always Full",
        controller: 112,
        side: .b,
        kind: .customMIDI,
        transition: .range,
        customLeftPercent: 100,
        customRightPercent: 100
    )

    let result = CrossfadeConfigurationSanitizer.targets([target])

    #expect(result.count == 1)
    #expect(result[0].customLeftPercent == 100)
    #expect(result[0].customRightPercent == 100)
}

@Test("Scenes decode future values safely and sanitize their targets")
func sceneFallbacksAndSanitizing() throws {
    let data = Data(
        """
        {
          "name": "   ",
          "targets": [
            {"name":"A","controller":110,"side":"a","kind":"maschineLevel"},
            {"name":"Duplicate","controller":110,"side":"b","kind":"maschineLevel"}
          ],
          "mode": "future-mode",
          "curve": "future-curve",
          "minimumLevel": "future-floor"
        }
        """.utf8
    )

    let decoded = try JSONDecoder().decode(
        CrossfaderScenePreset.self,
        from: data
    )
    let scenes = CrossfadeConfigurationSanitizer.scenes([decoded])

    #expect(scenes.count == 1)
    #expect(scenes[0].name == "Scene")
    #expect(scenes[0].mode == .standard)
    #expect(scenes[0].curve == .fullCentre)
    #expect(scenes[0].minimumLevel == .kill)
    #expect(scenes[0].isReversed == false)
    #expect(scenes[0].isTravelReversed == false)
    #expect(scenes[0].targets.map(\.name) == ["A"])
}

@Test("Legacy all-range scenes migrate to per-target ranges")
func legacyAllRangeSceneMigration() throws {
    let data = Data(
        """
        {
          "name": "Legacy Range Scene",
          "targets": [
            {"name":"A","controller":110,"side":"a","kind":"maschineLevel"},
            {"name":"Off","controller":111,"side":"off","kind":"customMIDI"}
          ],
          "mode": "customScene",
          "curve": "smooth",
          "minimumLevel": "kill"
        }
        """.utf8
    )

    let scene = try JSONDecoder().decode(CrossfaderScenePreset.self, from: data)

    #expect(scene.mode == .standard)
    #expect(scene.targets[0].behavior == .range)
    #expect(scene.targets[1].behavior == .off)
}
