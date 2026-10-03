import Foundation

/// Keeps application settings injectable without creating persistent test domains.
protocol SettingsStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
}

extension SettingsStore {
    func integer(forKey key: String) -> Int {
        if let number = object(forKey: key) as? NSNumber { return number.intValue }
        if let string = object(forKey: key) as? String { return (string as NSString).integerValue }
        return 0
    }
    func bool(forKey key: String) -> Bool {
        if let number = object(forKey: key) as? NSNumber { return number.boolValue }
        if let string = object(forKey: key) as? String { return (string as NSString).boolValue }
        return false
    }
    func string(forKey key: String) -> String? { object(forKey: key) as? String }
    func data(forKey key: String) -> Data? { object(forKey: key) as? Data }
}

extension UserDefaults: SettingsStore {}

final class MemorySettingsStore: SettingsStore {
    private var values: [String: Any] = [:]
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values[key] = nil }
}
