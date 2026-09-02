import Foundation

public struct CrossfadeOutput: Equatable, Sendable {
    public let groupA: UInt8
    public let groupB: UInt8

    public init(groupA: UInt8, groupB: UInt8) {
        self.groupA = groupA
        self.groupB = groupB
    }
}

public enum CrossfaderTransform {
    public static func output(
        for input: UInt8,
        mode: CrossfadeMode = .standard,
        curve: CrossfadeCurve,
        reversed: Bool = false,
        travelReversed: Bool = false,
        endpointKill: Bool = true,
        minimumOutput: UInt8 = 0,
        maximumOutput: UInt8 = 127
    ) -> CrossfadeOutput {
        let effectiveInput = travelReversed ? 127 - input : input
        let position = Double(effectiveInput) / 127.0
        var levels = normalizedLevels(at: position, curve: curve)

        switch mode {
        case .standard:
            break
        case .layerToB:
            levels.groupB = 1.0
        case .layerToA:
            levels = (groupA: 1.0, groupB: levels.groupA)
        case .pairFade:
            levels.groupB = levels.groupA
        case .customScene:
            break
        }

        var groupA = midiValue(levels.groupA, maximum: maximumOutput)
        var groupB = midiValue(levels.groupB, maximum: maximumOutput)
        let floor = min(minimumOutput, maximumOutput)
        groupA = max(groupA, floor)
        groupB = max(groupB, floor)

        if endpointKill, floor == 0 {
            switch mode {
            case .standard:
                if effectiveInput == 0 {
                    groupA = maximumOutput
                    groupB = 0
                } else if effectiveInput == 127 {
                    groupA = 0
                    groupB = maximumOutput
                }
            case .layerToB:
                if effectiveInput == 0 {
                    groupA = maximumOutput
                    groupB = maximumOutput
                } else if effectiveInput == 127 {
                    groupA = 0
                    groupB = maximumOutput
                }
            case .layerToA:
                if effectiveInput == 0 {
                    groupA = maximumOutput
                    groupB = maximumOutput
                } else if effectiveInput == 127 {
                    groupA = maximumOutput
                    groupB = 0
                }
            case .pairFade:
                if effectiveInput == 0 {
                    groupA = maximumOutput
                    groupB = maximumOutput
                } else if effectiveInput == 127 {
                    groupA = 0
                    groupB = 0
                }
            case .customScene:
                if effectiveInput == 0 {
                    groupA = maximumOutput
                    groupB = 0
                } else if effectiveInput == 127 {
                    groupA = 0
                    groupB = maximumOutput
                }
            }
        }

        if reversed {
            swap(&groupA, &groupB)
        }

        return CrossfadeOutput(groupA: groupA, groupB: groupB)
    }

    public static func sceneValue(
        for input: UInt8,
        leftOutput: UInt8,
        rightOutput: UInt8,
        curve: CrossfadeCurve,
        travelReversed: Bool = false,
        maximumOutput: UInt8 = 127
    ) -> UInt8 {
        parameterValue(
            for: input,
            leftOutput: leftOutput,
            rightOutput: rightOutput,
            curve: .inherit,
            inheritedCurve: curve,
            travelReversed: travelReversed,
            maximumOutput: maximumOutput
        )
    }

    public static func parameterValue(
        for input: UInt8,
        leftOutput: UInt8,
        rightOutput: UInt8,
        curve: CrossfadeParameterCurve,
        inheritedCurve: CrossfadeCurve,
        travelReversed: Bool = false,
        maximumOutput: UInt8 = 127
    ) -> UInt8 {
        let effectiveInput = travelReversed ? 127 - input : input
        let position = Double(effectiveInput) / 127.0
        let progress = parameterProgress(
            at: position,
            curve: curve,
            inheritedCurve: inheritedCurve
        )
        let left = Double(min(leftOutput, maximumOutput))
        let right = Double(min(rightOutput, maximumOutput))
        let value = left + ((right - left) * progress)
        return UInt8(min(Double(maximumOutput), max(0.0, value)).rounded())
    }

    private static func normalizedLevels(
        at position: Double,
        curve: CrossfadeCurve
    ) -> (groupA: Double, groupB: Double) {
        switch curve {
        case .fullCentre:
            // A 7-bit fader has two centre values. Keep the established side
            // at unity while the opposite side fades in, with 63 and 64 full.
            let leftCentre = 63.0 / 127.0
            let rightCentre = 64.0 / 127.0
            let groupA = position <= rightCentre
                ? 1.0
                : (1.0 - position) / (1.0 - rightCentre)
            let groupB = position >= leftCentre
                ? 1.0
                : position / leftCentre
            return (groupA, groupB)

        case .linear:
            return (1.0 - position, position)

        case .smooth:
            let blend = position * position * (3.0 - 2.0 * position)
            return (1.0 - blend, blend)

        case .equalPower:
            let angle = position * .pi / 2.0
            return (cos(angle), sin(angle))

        case .fastCut:
            let cutWidth = 0.18
            let groupA = min(1.0, max(0.0, (1.0 - position) / cutWidth))
            let groupB = min(1.0, max(0.0, position / cutWidth))
            return (groupA, groupB)
        }
    }

    private static func sceneProgress(
        at position: Double,
        curve: CrossfadeCurve
    ) -> Double {
        switch curve {
        case .fullCentre, .linear:
            return position
        case .smooth:
            return smoothStep(position)
        case .equalPower:
            let sine = sin(position * .pi / 2.0)
            return sine * sine
        case .fastCut:
            let transition = min(1.0, max(0.0, (position - 0.41) / 0.18))
            return smoothStep(transition)
        }
    }

    private static func parameterProgress(
        at position: Double,
        curve: CrossfadeParameterCurve,
        inheritedCurve: CrossfadeCurve
    ) -> Double {
        switch curve {
        case .inherit:
            return sceneProgress(at: position, curve: inheritedCurve)
        case .linear:
            return position
        case .smooth:
            return smoothStep(position)
        case .exponential:
            return position * position
        case .logarithmic:
            return sqrt(position)
        }
    }

    private static func smoothStep(_ value: Double) -> Double {
        value * value * (3.0 - 2.0 * value)
    }

    private static func midiValue(_ normalized: Double, maximum: UInt8) -> UInt8 {
        let clamped = min(1.0, max(0.0, normalized))
        return UInt8((clamped * Double(maximum)).rounded())
    }
}
