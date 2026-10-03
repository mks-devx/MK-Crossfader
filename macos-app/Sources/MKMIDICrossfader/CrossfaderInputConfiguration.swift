import Foundation

enum InputMode: String, Codable, CaseIterable { case single, xyz }
enum InputAxis: String, Codable, CaseIterable {
    case x, y, z
    var label: String { rawValue.uppercased() }
    var minimumLabel: String { self == .x ? "Left" : self == .y ? "Bottom" : "Minimum" }
    var maximumLabel: String { self == .x ? "Right" : self == .y ? "Top" : "Maximum" }
}
enum TouchReleasePolicy: String, Codable, CaseIterable {
    case hold, returnValue
    var label: String { self == .hold ? "Hold" : "Return Value" }
}

struct MIDICCBinding: Codable, Equatable, Hashable {
    let channel: Int
    let controller: Int
    init?(channel: Int, controller: Int) {
        guard (0...15).contains(channel), (0...127).contains(controller) else { return nil }
        self.channel = channel
        self.controller = controller
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let channel = try values.decode(Int.self, forKey: .channel)
        let controller = try values.decode(Int.self, forKey: .controller)
        guard let valid = Self(channel: channel, controller: controller) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid MIDI CC binding"))
        }
        self = valid
    }
    var description: String { "CC \(controller) · Ch \(channel + 1)" }
    func matches(_ message: MIDIControlChange) -> Bool {
        channel == Int(message.channel) && controller == Int(message.controller)
    }
}

struct InputConfiguration: Codable, Equatable {
    var schemaVersion = 1
    var mode: InputMode = .single
    var x: MIDICCBinding?
    var y: MIDICCBinding?
    var z: MIDICCBinding?
    var touchGate: MIDICCBinding?

    func binding(for axis: InputAxis) -> MIDICCBinding? {
        switch axis { case .x: return x; case .y: return y; case .z: return z }
    }
    mutating func setBinding(_ binding: MIDICCBinding?, for axis: InputAxis) {
        switch axis { case .x: x = binding; case .y: y = binding; case .z: z = binding }
    }
    func validate() -> [String] {
        guard schemaVersion == 1 else { return ["Input settings use an unsupported version. Reset input settings to continue."] }
        var assigned: [MIDICCBinding: String] = [:]
        for axis in InputAxis.allCases {
            guard let binding = binding(for: axis) else { continue }
            if let existing = assigned[binding] { return ["\(axis.label) and \(existing) use the same CC/channel. Choose different inputs."] }
            assigned[binding] = axis.label
        }
        if let touchGate, let existing = assigned[touchGate] {
            return ["Touch Gate and \(existing) use the same CC/channel. Choose a dedicated gate input."]
        }
        return []
    }
}

struct InputConfigurationLoadResult {
    let configuration: InputConfiguration
    let issues: [String]
    let isWritable: Bool
}

enum InputConfigurationStore {
    static let key = "inputConfigurationV1"
    static func load(from store: any SettingsStore) -> InputConfigurationLoadResult {
        if store.object(forKey: key) != nil {
            guard let data = store.data(forKey: key),
                  let config = try? JSONDecoder().decode(InputConfiguration.self, from: data),
                  config.validate().isEmpty else {
                return .init(configuration: InputConfiguration(), issues: ["Input settings are damaged or from a newer version. Reset input settings to continue."], isWritable: false)
            }
            return .init(configuration: config, issues: [], isWritable: true)
        }
        var config = InputConfiguration()
        if store.object(forKey: "inputChannel") != nil, store.object(forKey: "inputController") != nil {
            config.x = MIDICCBinding(channel: store.integer(forKey: "inputChannel"), controller: store.integer(forKey: "inputController"))
        }
        return .init(configuration: config, issues: [], isWritable: true)
    }
    @discardableResult
    static func save(_ configuration: InputConfiguration, to store: any SettingsStore) -> Bool {
        guard load(from: store).isWritable, configuration.validate().isEmpty,
              let data = try? JSONEncoder().encode(configuration) else { return false }
        store.set(data, forKey: key)
        store.set(configuration.x?.channel ?? -1, forKey: "inputChannel")
        store.set(configuration.x?.controller ?? -1, forKey: "inputController")
        return true
    }
}
