import Foundation

public enum CrossfadeParameterCurve: String, CaseIterable, Codable, Sendable {
    case inherit
    case linear
    case smooth
    case exponential
    case logarithmic

    public var displayName: String {
        switch self {
        case .inherit:
            return "Global"
        case .linear:
            return "Linear"
        case .smooth:
            return "Smooth"
        case .exponential:
            return "Exponential"
        case .logarithmic:
            return "Logarithmic"
        }
    }
}
