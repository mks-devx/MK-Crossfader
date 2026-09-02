import CrossfaderCore
import Foundation

enum BuiltInCrossfadePreset: String, CaseIterable, Identifiable {
    case performanceAB
    case sceneMorph

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .performanceAB:
            return "Performance A/B"
        case .sceneMorph:
            return "Scene Morph"
        }
    }

    var helpText: String {
        switch self {
        case .performanceAB:
            return "Classic A/B mixing for Level targets. Parameter ranges are preserved."
        case .sceneMorph:
            return "Morph every active target between its stored Left and Right values."
        }
    }

    var mode: CrossfadeMode {
        .standard
    }

    var curve: CrossfadeCurve {
        switch self {
        case .performanceAB:
            return .fullCentre
        case .sceneMorph:
            return .smooth
        }
    }

    var minimumLevel: CrossfadeMinimumLevel {
        .kill
    }

    func applying(to targets: [CrossfadeTarget]) -> [CrossfadeTarget] {
        targets.map { target in
            var updated = target
            guard updated.participatesInOutput else {
                return updated
            }

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
