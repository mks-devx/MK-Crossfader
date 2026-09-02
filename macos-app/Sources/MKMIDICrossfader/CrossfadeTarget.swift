import CrossfaderCore
import Foundation

enum CrossfadeTargetKind: String, CaseIterable, Codable {
    case maschineLevel
    case mkGain
    case customMIDI

    var displayName: String {
        switch self {
        case .maschineLevel:
            return "Level"
        case .mkGain:
            return "Legacy Gain"
        case .customMIDI:
            return "Parameter"
        }
    }

    static let setupCases: [Self] = [.maschineLevel, .customMIDI]

    var maximumMIDIValue: UInt8 {
        switch self {
        case .maschineLevel:
            return 95
        case .mkGain, .customMIDI:
            return 127
        }
    }

    func minimumMIDIValue(for level: CrossfadeMinimumLevel) -> UInt8 {
        switch self {
        case .maschineLevel:
            return level.midiValue(maximumOutput: maximumMIDIValue)
        case .mkGain:
            return level.linearAmplitudeMIDIValue(
                maximumOutput: maximumMIDIValue
            )
        case .customMIDI:
            return 0
        }
    }
}

enum CrossfadeTargetTransition: String, CaseIterable, Codable {
    case crossfade
    case range

    var displayName: String {
        switch self {
        case .crossfade:
            return "A/B"
        case .range:
            return "Range"
        }
    }
}

enum CrossfadeTargetBehavior: String, CaseIterable {
    case sideA
    case sideB
    case range
    case off

    var displayName: String {
        switch self {
        case .sideA:
            return "A"
        case .sideB:
            return "B"
        case .range:
            return "Range"
        case .off:
            return "Off"
        }
    }
}

struct CrossfadeTarget: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var controller: Int
    var side: CrossfadeSide
    var kind: CrossfadeTargetKind
    var transition: CrossfadeTargetTransition
    var customLeftPercent: Int
    var customRightPercent: Int
    var parameterCurve: CrossfadeParameterCurve
    var restorePercent: Int

    init(
        id: UUID = UUID(),
        name: String,
        controller: Int,
        side: CrossfadeSide = .off,
        kind: CrossfadeTargetKind = .maschineLevel,
        transition: CrossfadeTargetTransition? = nil,
        customLeftPercent: Int? = nil,
        customRightPercent: Int? = nil,
        parameterCurve: CrossfadeParameterCurve = .inherit,
        restorePercent: Int = 100
    ) {
        self.id = id
        self.name = name
        self.controller = controller
        self.side = side
        self.kind = kind
        self.transition = transition
            ?? (kind == .customMIDI ? .range : .crossfade)
        let defaults = Self.defaultSceneEndpoints(for: side)
        self.customLeftPercent = min(
            100,
            max(0, customLeftPercent ?? defaults.left)
        )
        self.customRightPercent = min(
            100,
            max(0, customRightPercent ?? defaults.right)
        )
        self.parameterCurve = parameterCurve
        self.restorePercent = min(100, max(0, restorePercent))
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case controller
        case side
        case kind
        case transition
        case customLeftPercent
        case customRightPercent
        case parameterCurve
        case restorePercent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Target"
        controller = try container.decodeIfPresent(Int.self, forKey: .controller) ?? -1
        side = (try? container.decode(String.self, forKey: .side))
            .flatMap(CrossfadeSide.init(rawValue:)) ?? .off
        kind = (try? container.decode(String.self, forKey: .kind))
            .flatMap(CrossfadeTargetKind.init(rawValue:)) ?? .maschineLevel
        transition = (try? container.decode(String.self, forKey: .transition))
            .flatMap(CrossfadeTargetTransition.init(rawValue:))
            ?? (kind == .customMIDI ? .range : .crossfade)
        let defaults = Self.defaultSceneEndpoints(for: side)
        customLeftPercent = try container.decodeIfPresent(
            Int.self,
            forKey: .customLeftPercent
        ) ?? defaults.left
        customRightPercent = try container.decodeIfPresent(
            Int.self,
            forKey: .customRightPercent
        ) ?? defaults.right
        parameterCurve = (
            try? container.decode(String.self, forKey: .parameterCurve)
        ).flatMap(CrossfadeParameterCurve.init(rawValue:)) ?? .inherit
        restorePercent = try container.decodeIfPresent(
            Int.self,
            forKey: .restorePercent
        ) ?? 100
        customLeftPercent = min(100, max(0, customLeftPercent))
        customRightPercent = min(100, max(0, customRightPercent))
        restorePercent = min(100, max(0, restorePercent))
    }

    func sceneOutput(at percent: Int) -> UInt8 {
        UInt8(
            (Double(min(100, max(0, percent)))
                * Double(kind.maximumMIDIValue) / 100.0).rounded()
        )
    }

    var restoreOutput: UInt8 {
        sceneOutput(at: restorePercent)
    }

    var behavior: CrossfadeTargetBehavior {
        guard side != .off else {
            return .off
        }
        if transition == .range {
            return .range
        }
        return side == .a ? .sideA : .sideB
    }

    var participatesInOutput: Bool {
        side != .off
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Target" : trimmed
    }

    mutating func apply(_ behavior: CrossfadeTargetBehavior) {
        let usesUntouchedOffRange = side == .off
            && customLeftPercent == 100
            && customRightPercent == 100

        switch behavior {
        case .sideA:
            transition = .crossfade
            side = .a
            if usesUntouchedOffRange {
                customLeftPercent = 100
                customRightPercent = 0
            }
        case .sideB:
            transition = .crossfade
            side = .b
            if usesUntouchedOffRange {
                customLeftPercent = 0
                customRightPercent = 100
            }
        case .range:
            transition = .range
            if side == .off {
                side = .b
                if usesUntouchedOffRange {
                    customLeftPercent = 0
                    customRightPercent = 100
                }
            }
        case .off:
            side = .off
        }
    }

    private static func defaultSceneEndpoints(
        for side: CrossfadeSide
    ) -> (left: Int, right: Int) {
        switch side {
        case .a:
            return (100, 0)
        case .b:
            return (0, 100)
        case .off:
            return (100, 100)
        }
    }
}
