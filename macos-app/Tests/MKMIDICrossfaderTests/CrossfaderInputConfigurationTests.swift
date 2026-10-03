import Foundation
import Testing
@testable import MKMIDICrossfader

@Suite struct CrossfaderInputConfigurationTests {
    @Test func migrationAndValidation() throws {
        let store = MemorySettingsStore()
        store.set(13, forKey: "inputChannel")
        store.set(48, forKey: "inputController")
        let result = InputConfigurationStore.load(from: store)
        #expect(result.isWritable)
        #expect(result.configuration.x == MIDICCBinding(channel: 13, controller: 48))
        #expect(result.configuration.mode == .single)
        #expect(result.configuration.y == nil)
        #expect(MIDICCBinding(channel: 16, controller: 0) == nil)
        #expect(MIDICCBinding(channel: 0, controller: 128) == nil)
        #expect(MIDICCBinding(channel: -1, controller: 0) == nil)
        var config = result.configuration
        config.y = config.x
        #expect(!config.validate().isEmpty)
        config.y = MIDICCBinding(channel: 0, controller: 21)
        config.touchGate = config.y
        #expect(!config.validate().isEmpty)
        config.touchGate = MIDICCBinding(channel: 0, controller: 23)
        config.mode = .xyz
        #expect(config.validate().isEmpty)
        #expect(try JSONDecoder().decode(InputConfiguration.self, from: JSONEncoder().encode(config)) == config)
        #expect(InputConfigurationStore.load(from: MemorySettingsStore()).configuration.x == nil)
    }
    @Test func malformedAndNewerStorageIsPreserved() {
        for data in [Data("invalid".utf8), Data(#"{"schemaVersion":2,"mode":"xyz"}"#.utf8), Data(#"{"schemaVersion":1,"mode":"xyz","x":{"channel":33,"controller":1}}"#.utf8)] {
            let store = MemorySettingsStore()
            store.set(data, forKey: InputConfigurationStore.key)
            let result = InputConfigurationStore.load(from: store)
            #expect(!result.isWritable)
            #expect(!result.issues.isEmpty)
            #expect(!InputConfigurationStore.save(InputConfiguration(), to: store))
            #expect(store.data(forKey: InputConfigurationStore.key) == data)
        }
    }
    @Test func savingAndReloadingIsIdempotent() {
        let store = MemorySettingsStore()
        var config = InputConfiguration()
        config.x = MIDICCBinding(channel: 0, controller: 20)
        #expect(InputConfigurationStore.save(config, to: store))
        #expect(store.integer(forKey: "inputController") == 20)
        #expect(InputConfigurationStore.load(from: store).configuration == config)
    }
}
