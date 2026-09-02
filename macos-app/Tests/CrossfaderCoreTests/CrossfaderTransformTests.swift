import Testing
@testable import CrossfaderCore

@Test("Add/remove modes use explicit endpoint names")
func addRemoveModeNames() {
    #expect(CrossfadeMode.layerToB.displayName == "A+B to B")
    #expect(CrossfadeMode.layerToA.displayName == "A+B to A")
}

@Test("Full-centre curve reaches unity on both MIDI centre values")
func fullCentreUnity() {
    for input: UInt8 in [63, 64] {
        #expect(
            CrossfaderTransform.output(
                for: input,
                curve: .fullCentre,
                maximumOutput: 95
            ) == .init(groupA: 95, groupB: 95)
        )
    }
}

@Test("Full-centre curve preserves opposite endpoints")
func fullCentreEndpoints() {
    #expect(
        CrossfaderTransform.output(
            for: 0,
            curve: .fullCentre,
            maximumOutput: 95
        ) == .init(groupA: 95, groupB: 0)
    )
    #expect(
        CrossfaderTransform.output(
            for: 127,
            curve: .fullCentre,
            maximumOutput: 95
        ) == .init(groupA: 0, groupB: 95)
    )
}

@Test("Layer-to-B mode keeps B at unity across the fader")
func layerToBEndpoints() {
    #expect(
        CrossfaderTransform.output(
            for: 0,
            mode: .layerToB,
            curve: .linear,
            maximumOutput: 95
        ) == .init(groupA: 95, groupB: 95)
    )
    #expect(
        CrossfaderTransform.output(
            for: 127,
            mode: .layerToB,
            curve: .linear,
            maximumOutput: 95
        ) == .init(groupA: 0, groupB: 95)
    )
}

@Test("Layer-to-B mode fades only A through the midpoint")
func layerToBMidpoint() {
    let output = CrossfaderTransform.output(
        for: 64,
        mode: .layerToB,
        curve: .linear,
        maximumOutput: 95
    )
    #expect((47...48).contains(Int(output.groupA)))
    #expect(output.groupB == 95)
}

@Test("Reversing layer-to-B mode keeps A instead")
func reversedLayerToB() {
    #expect(
        CrossfaderTransform.output(
            for: 127,
            mode: .layerToB,
            curve: .linear,
            reversed: true,
            maximumOutput: 95
        ) == .init(groupA: 95, groupB: 0)
    )
}

@Test("Layer-to-A mode keeps A at unity across the fader")
func layerToAEndpoints() {
    #expect(
        CrossfaderTransform.output(
            for: 0,
            mode: .layerToA,
            curve: .linear,
            maximumOutput: 95
        ) == .init(groupA: 95, groupB: 95)
    )
    #expect(
        CrossfaderTransform.output(
            for: 127,
            mode: .layerToA,
            curve: .linear,
            maximumOutput: 95
        ) == .init(groupA: 95, groupB: 0)
    )
}

@Test("Layer-to-A mode fades only B through the midpoint")
func layerToAMidpoint() {
    let output = CrossfaderTransform.output(
        for: 64,
        mode: .layerToA,
        curve: .linear,
        maximumOutput: 95
    )
    #expect(output.groupA == 95)
    #expect((47...48).contains(Int(output.groupB)))
}

@Test("Reversing layer-to-A mode keeps B instead")
func reversedLayerToA() {
    #expect(
        CrossfaderTransform.output(
            for: 127,
            mode: .layerToA,
            curve: .linear,
            reversed: true,
            maximumOutput: 95
        ) == .init(groupA: 0, groupB: 95)
    )
}

@Test("Target routing selects the requested crossfader side")
func targetRouting() {
    let output = CrossfadeOutput(groupA: 23, groupB: 81)
    #expect(CrossfadeRouting.value(for: .a, output: output) == 23)
    #expect(CrossfadeRouting.value(for: .b, output: output) == 81)
    #expect(CrossfadeRouting.value(for: .off, output: output) == nil)
}

@Test("Linear curve has exact endpoints")
func linearEndpoints() {
    #expect(CrossfaderTransform.output(for: 0, curve: .linear) == .init(groupA: 127, groupB: 0))
    #expect(CrossfaderTransform.output(for: 127, curve: .linear) == .init(groupA: 0, groupB: 127))
}

@Test("Linear midpoint is balanced")
func linearMidpoint() {
    let output = CrossfaderTransform.output(for: 64, curve: .linear)
    #expect(abs(Int(output.groupA) - Int(output.groupB)) <= 1)
}

@Test("Wide-blend midpoint uses the equal-power control shape")
func wideBlendMidpoint() {
    let output = CrossfaderTransform.output(for: 64, curve: .equalPower)
    #expect((89...91).contains(Int(output.groupA)))
    #expect((89...91).contains(Int(output.groupB)))
}

@Test("Smooth curve eases the transition near both endpoints")
func smoothCurve() {
    #expect(
        CrossfaderTransform.output(for: 0, curve: .smooth)
            == .init(groupA: 127, groupB: 0)
    )
    #expect(
        CrossfaderTransform.output(for: 127, curve: .smooth)
            == .init(groupA: 0, groupB: 127)
    )

    let linear = CrossfaderTransform.output(for: 16, curve: .linear)
    let smooth = CrossfaderTransform.output(for: 16, curve: .smooth)
    #expect(smooth.groupA > linear.groupA)
    #expect(smooth.groupB < linear.groupB)
}

@Test("Flip travel mirrors the physical fader without swapping targets")
func flipTravel() {
    let normal = CrossfaderTransform.output(for: 20, curve: .smooth)
    let flipped = CrossfaderTransform.output(
        for: 107,
        curve: .smooth,
        travelReversed: true
    )
    #expect(flipped == normal)
}

@Test("Pair fade moves both sides from unity to the selected floor")
func pairFade() {
    #expect(
        CrossfaderTransform.output(
            for: 0,
            mode: .pairFade,
            curve: .smooth,
            maximumOutput: 95
        ) == .init(groupA: 95, groupB: 95)
    )
    #expect(
        CrossfaderTransform.output(
            for: 127,
            mode: .pairFade,
            curve: .smooth,
            endpointKill: false,
            minimumOutput: 35,
            maximumOutput: 95
        ) == .init(groupA: 35, groupB: 35)
    )
}

@Test("Reverse swaps the destinations")
func reverseSwapsDestinations() {
    let normal = CrossfaderTransform.output(for: 20, curve: .equalPower)
    let reversed = CrossfaderTransform.output(for: 20, curve: .equalPower, reversed: true)
    #expect(reversed.groupA == normal.groupB)
    #expect(reversed.groupB == normal.groupA)
}

@Test("Fast cut keeps both sides open around the centre")
func fastCutOverlap() {
    let output = CrossfaderTransform.output(for: 64, curve: .fastCut)
    #expect(output == .init(groupA: 127, groupB: 127))
}

@Test("Output ceiling limits both endpoints and curve values")
func outputCeiling() {
    #expect(
        CrossfaderTransform.output(
            for: 0,
            curve: .linear,
            maximumOutput: 95
        ) == .init(groupA: 95, groupB: 0)
    )
    #expect(
        CrossfaderTransform.output(
            for: 127,
            curve: .linear,
            maximumOutput: 95
        ) == .init(groupA: 0, groupB: 95)
    )
    let midpoint = CrossfaderTransform.output(
        for: 64,
        curve: .linear,
        maximumOutput: 95
    )
    #expect(midpoint.groupA <= 95)
    #expect(midpoint.groupB <= 95)
}

@Test("Minimum output keeps both sides above the selected floor")
func minimumOutputFloor() {
    #expect(
        CrossfaderTransform.output(
            for: 0,
            curve: .linear,
            endpointKill: false,
            minimumOutput: 50,
            maximumOutput: 95
        ) == .init(groupA: 95, groupB: 50)
    )
    #expect(
        CrossfaderTransform.output(
            for: 127,
            curve: .linear,
            endpointKill: false,
            minimumOutput: 50,
            maximumOutput: 95
        ) == .init(groupA: 50, groupB: 95)
    )
}

@Test("Minimum output applies to both one-sided transition modes")
func minimumOutputWithLayerModes() {
    #expect(
        CrossfaderTransform.output(
            for: 127,
            mode: .layerToB,
            curve: .linear,
            endpointKill: false,
            minimumOutput: 35,
            maximumOutput: 95
        ) == .init(groupA: 35, groupB: 95)
    )
    #expect(
        CrossfaderTransform.output(
            for: 127,
            mode: .layerToA,
            curve: .linear,
            endpointKill: false,
            minimumOutput: 35,
            maximumOutput: 95
        ) == .init(groupA: 95, groupB: 35)
    )
}

@Test("Minimum level presets use the calibrated Maschine values")
func minimumLevelPresetValues() {
    #expect(CrossfadeMinimumLevel.kill.midiValue(maximumOutput: 95) == 0)
    #expect(CrossfadeMinimumLevel.minus24DB.midiValue(maximumOutput: 95) == 35)
    #expect(CrossfadeMinimumLevel.minus18DB.midiValue(maximumOutput: 95) == 50)
    #expect(CrossfadeMinimumLevel.minus14DB.midiValue(maximumOutput: 95) == 60)
}

@Test("Linear-amplitude floors map exactly for the gain plug-in")
func gainPluginMinimumValues() {
    #expect(CrossfadeMinimumLevel.kill.linearAmplitudeMIDIValue(maximumOutput: 127) == 0)
    #expect(CrossfadeMinimumLevel.minus24DB.linearAmplitudeMIDIValue(maximumOutput: 127) == 8)
    #expect(CrossfadeMinimumLevel.minus18DB.linearAmplitudeMIDIValue(maximumOutput: 127) == 16)
    #expect(CrossfadeMinimumLevel.minus14DB.linearAmplitudeMIDIValue(maximumOutput: 127) == 25)
}

@Test("Custom scene interpolates bounded target endpoints")
func customSceneInterpolation() {
    #expect(
        CrossfaderTransform.sceneValue(
            for: 0,
            leftOutput: 95,
            rightOutput: 35,
            curve: .smooth,
            maximumOutput: 95
        ) == 95
    )
    #expect(
        CrossfaderTransform.sceneValue(
            for: 127,
            leftOutput: 95,
            rightOutput: 35,
            curve: .smooth,
            maximumOutput: 95
        ) == 35
    )
    #expect(
        CrossfaderTransform.sceneValue(
            for: 64,
            leftOutput: 0,
            rightOutput: 100,
            curve: .smooth,
            maximumOutput: 95
        ) == 48
    )
}

@Test("Per-target parameter curves preserve exact endpoints")
func parameterCurveEndpoints() {
    for curve in CrossfadeParameterCurve.allCases {
        #expect(
            CrossfaderTransform.parameterValue(
                for: 0,
                leftOutput: 18,
                rightOutput: 91,
                curve: curve,
                inheritedCurve: .smooth
            ) == 18
        )
        #expect(
            CrossfaderTransform.parameterValue(
                for: 127,
                leftOutput: 18,
                rightOutput: 91,
                curve: curve,
                inheritedCurve: .smooth
            ) == 91
        )
    }
}

@Test("Exponential and logarithmic target responses shape the midpoint")
func parameterCurveShapes() {
    let linear = CrossfaderTransform.parameterValue(
        for: 64,
        leftOutput: 0,
        rightOutput: 100,
        curve: .linear,
        inheritedCurve: .linear
    )
    let exponential = CrossfaderTransform.parameterValue(
        for: 64,
        leftOutput: 0,
        rightOutput: 100,
        curve: .exponential,
        inheritedCurve: .linear
    )
    let logarithmic = CrossfaderTransform.parameterValue(
        for: 64,
        leftOutput: 0,
        rightOutput: 100,
        curve: .logarithmic,
        inheritedCurve: .linear
    )
    #expect(exponential < linear)
    #expect(logarithmic > linear)
}

@Test("Every mode and curve remains within its MIDI ceiling")
func exhaustiveOutputBounds() {
    for mode in CrossfadeMode.allCases {
        for curve in CrossfadeCurve.allCases {
            for rawInput in 0...127 {
                let output = CrossfaderTransform.output(
                    for: UInt8(rawInput),
                    mode: mode,
                    curve: curve,
                    endpointKill: false,
                    minimumOutput: 35,
                    maximumOutput: 95
                )
                #expect((35...95).contains(Int(output.groupA)))
                #expect((35...95).contains(Int(output.groupB)))
            }
        }
    }
}

@Test("Standard crossfade curves remain monotonic across full travel")
func exhaustiveStandardMonotonicity() {
    for curve in CrossfadeCurve.allCases {
        var previous = CrossfaderTransform.output(
            for: 0,
            curve: curve,
            maximumOutput: 95
        )
        for rawInput in 1...127 {
            let output = CrossfaderTransform.output(
                for: UInt8(rawInput),
                curve: curve,
                maximumOutput: 95
            )
            #expect(output.groupA <= previous.groupA)
            #expect(output.groupB >= previous.groupB)
            previous = output
        }
    }
}

@Test("Parameter curves remain monotonic between arbitrary endpoints")
func exhaustiveParameterMonotonicity() {
    for curve in CrossfadeParameterCurve.allCases {
        var risingPrevious: UInt8 = 18
        var fallingPrevious: UInt8 = 91

        for rawInput in 0...127 {
            let input = UInt8(rawInput)
            let rising = CrossfaderTransform.parameterValue(
                for: input,
                leftOutput: 18,
                rightOutput: 91,
                curve: curve,
                inheritedCurve: .fastCut
            )
            let falling = CrossfaderTransform.parameterValue(
                for: input,
                leftOutput: 91,
                rightOutput: 18,
                curve: curve,
                inheritedCurve: .fastCut
            )

            #expect(rising >= risingPrevious)
            #expect(falling <= fallingPrevious)
            risingPrevious = rising
            fallingPrevious = falling
        }
    }
}

@Test("Per-target parameter response respects flipped travel")
func parameterCurveFlipTravel() {
    #expect(
        CrossfaderTransform.parameterValue(
            for: 0,
            leftOutput: 10,
            rightOutput: 80,
            curve: .linear,
            inheritedCurve: .linear,
            travelReversed: true
        ) == 80
    )
}
