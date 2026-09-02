import CrossfaderCore
import Foundation

enum BuiltInCrossfadePreset: String, CaseIterable, Identifiable {
    case akaiForce
    case octatrack

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .akaiForce:
            return "Akai Force - A/B Mix"
        case .octatrack:
            return "Octatrack - Scene Morph"
        }
    }

    var helpText: String {
        switch self {
        case .akaiForce:
            return "Classic A/B mixing for Level targets. Parameter ranges are preserved."
        case .octatrack:
            return "Morph every active target between its stored Left and Right values."
        }
    }

    var mode: CrossfadeMode {
        .standard
    }

    var curve: CrossfadeCurve {
        switch self {
        case .akaiForce:
            return .fullCentre
        case .octatrack:
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
            case .akaiForce:
                if updated.kind != .customMIDI {
                    updated.transition = .crossfade
                }
            case .octatrack:
                updated.transition = .range
            }
            return updated
        }
    }
}
