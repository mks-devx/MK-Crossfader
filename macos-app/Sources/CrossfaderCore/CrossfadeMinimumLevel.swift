import Foundation

public enum CrossfadeMinimumLevel: String, CaseIterable, Codable, Sendable {
    case kill
    case minus24DB
    case minus18DB
    case minus14DB

    public var displayName: String {
        switch self {
        case .kill:
            return "Kill"
        case .minus24DB:
            return "-24 dB"
        case .minus18DB:
            return "-18 dB"
        case .minus14DB:
            return "-14 dB"
        }
    }

    public func midiValue(maximumOutput: UInt8) -> UInt8 {
        let value: UInt8
        switch self {
        case .kill:
            value = 0
        case .minus24DB:
            value = 35
        case .minus18DB:
            value = 50
        case .minus14DB:
            value = 60
        }
        return min(value, maximumOutput)
    }

    public func linearAmplitudeMIDIValue(maximumOutput: UInt8) -> UInt8 {
        let amplitude: Double
        switch self {
        case .kill:
            amplitude = 0.0
        case .minus24DB:
            amplitude = pow(10.0, -24.0 / 20.0)
        case .minus18DB:
            amplitude = pow(10.0, -18.0 / 20.0)
        case .minus14DB:
            amplitude = pow(10.0, -14.0 / 20.0)
        }
        return UInt8((amplitude * Double(maximumOutput)).rounded())
    }
}
