import CrossfaderCore

enum BuiltInCrossfadePreset: String, CaseIterable, Identifiable {
    case performanceAB
    case sceneMorph

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .performanceAB: return "Performance A/B"
        case .sceneMorph: return "Scene Morph"
        }
    }

    var summary: String {
        switch self {
        case .performanceAB:
            return "Active Level targets follow A/B with Full Centre and Kill. Parameter behaviours stay unchanged."
        case .sceneMorph:
            return "Every active target uses Range with its stored Left and Right values. Global shape becomes Smooth."
        }
    }

    var curve: CrossfadeCurve {
        switch self {
        case .performanceAB: return .fullCentre
        case .sceneMorph: return .smooth
        }
    }

    func applying(to targets: [CrossfadeTarget]) -> [CrossfadeTarget] {
        targets.map { target in
            guard target.participatesInOutput else { return target }
            var updated = target
            switch self {
            case .performanceAB:
                if updated.kind != .customMIDI {
                    updated.transition = .crossfade
                }
            case .sceneMorph:
                updated.transition = .range
            }
            return updated
        }
    }
}
