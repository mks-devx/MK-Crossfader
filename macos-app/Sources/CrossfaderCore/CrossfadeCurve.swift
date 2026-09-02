import Foundation

public enum CrossfadeCurve: String, CaseIterable, Codable, Sendable {
    case fullCentre
    case linear
    case smooth
    case equalPower
    case fastCut

    public var displayName: String {
        switch self {
        case .fullCentre:
            return "Full Centre"
        case .linear:
            return "Linear"
        case .smooth:
            return "Smooth"
        case .equalPower:
            return "Wide Blend"
        case .fastCut:
            return "Fast Cut"
        }
    }
}
