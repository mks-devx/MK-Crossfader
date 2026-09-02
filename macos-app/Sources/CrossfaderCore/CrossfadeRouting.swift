import Foundation

public enum CrossfadeSide: String, CaseIterable, Codable, Sendable {
    case a
    case off
    case b

    public var displayName: String {
        switch self {
        case .a:
            return "A"
        case .off:
            return "Off"
        case .b:
            return "B"
        }
    }
}

public enum CrossfadeRouting {
    public static func value(
        for side: CrossfadeSide,
        output: CrossfadeOutput
    ) -> UInt8? {
        switch side {
        case .a:
            return output.groupA
        case .off:
            return nil
        case .b:
            return output.groupB
        }
    }
}
