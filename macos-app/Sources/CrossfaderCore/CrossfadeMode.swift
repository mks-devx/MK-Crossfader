import Foundation

public enum CrossfadeMode: String, CaseIterable, Codable, Sendable {
    case standard
    case layerToB
    case layerToA
    case pairFade
    case customScene

    public var displayName: String {
        switch self {
        case .standard:
            return "Crossfade A to B"
        case .layerToB:
            return "A+B to B"
        case .layerToA:
            return "A+B to A"
        case .pairFade:
            return "Fade Both"
        case .customScene:
            return "All Target Ranges"
        }
    }

    public static let performanceCases: [Self] = [
        .standard,
        .layerToB,
        .layerToA,
        .pairFade,
    ]
}
