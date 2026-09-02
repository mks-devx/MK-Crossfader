import CrossfaderCore
import Foundation

struct CrossfaderScenePreset: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var targets: [CrossfadeTarget]
    var mode: CrossfadeMode
    var curve: CrossfadeCurve
    var minimumLevel: CrossfadeMinimumLevel
    var isReversed: Bool
    var isTravelReversed: Bool

    init(
        id: UUID = UUID(),
        name: String,
        targets: [CrossfadeTarget],
        mode: CrossfadeMode,
        curve: CrossfadeCurve,
        minimumLevel: CrossfadeMinimumLevel,
        isReversed: Bool,
        isTravelReversed: Bool
    ) {
        self.id = id
        self.name = name
        self.targets = targets
        self.mode = mode
        self.curve = curve
        self.minimumLevel = minimumLevel
        self.isReversed = isReversed
        self.isTravelReversed = isTravelReversed
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case targets
        case mode
        case curve
        case minimumLevel
        case isReversed
        case isTravelReversed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Scene"
        targets = try container.decodeIfPresent(
            [CrossfadeTarget].self,
            forKey: .targets
        ) ?? []
        let decodedMode = (try? container.decode(String.self, forKey: .mode))
            .flatMap(CrossfadeMode.init(rawValue:)) ?? .standard
        if decodedMode == .customScene {
            targets = targets.map { target in
                var migrated = target
                if migrated.participatesInOutput {
                    migrated.transition = .range
                }
                return migrated
            }
            mode = .standard
        } else {
            mode = decodedMode
        }
        curve = (try? container.decode(String.self, forKey: .curve))
            .flatMap(CrossfadeCurve.init(rawValue:)) ?? .fullCentre
        minimumLevel = (
            try? container.decode(String.self, forKey: .minimumLevel)
        ).flatMap(CrossfadeMinimumLevel.init(rawValue:)) ?? .kill
        isReversed = try container.decodeIfPresent(
            Bool.self,
            forKey: .isReversed
        ) ?? false
        isTravelReversed = try container.decodeIfPresent(
            Bool.self,
            forKey: .isTravelReversed
        ) ?? false
    }
}
