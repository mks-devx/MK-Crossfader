import Foundation

enum CrossfadeConfigurationSanitizer {
    static func targets(
        _ candidates: [CrossfadeTarget],
        limit: Int = 128
    ) -> [CrossfadeTarget] {
        let resolvedLimit = max(0, limit)
        var ids = Set<UUID>()
        var controllers = Set<Int>()
        var result: [CrossfadeTarget] = []

        for target in candidates {
            guard result.count < resolvedLimit else {
                break
            }
            guard (0...127).contains(target.controller),
                ids.insert(target.id).inserted,
                controllers.insert(target.controller).inserted
            else {
                continue
            }
            result.append(target)
        }

        return result
    }

    static func scenes(
        _ candidates: [CrossfaderScenePreset],
        limit: Int = 16
    ) -> [CrossfaderScenePreset] {
        let resolvedLimit = max(0, limit)
        var ids = Set<UUID>()
        var result: [CrossfaderScenePreset] = []

        for candidate in candidates {
            guard result.count < resolvedLimit else {
                break
            }
            guard ids.insert(candidate.id).inserted else {
                continue
            }

            var scene = candidate
            let trimmedName = scene.name.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            scene.name = trimmedName.isEmpty ? "Scene" : trimmedName
            scene.targets = targets(scene.targets)
            result.append(scene)
        }

        return result
    }
}
