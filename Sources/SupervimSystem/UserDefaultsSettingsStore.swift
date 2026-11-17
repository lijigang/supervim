import Foundation
import SupervimCore

/// Stores one settings document in an injected defaults suite.
///
/// The initializer uses only the object it is given. It does not register a login item.
/// Task 13 should pass a suite named `UserDefaultsSettingsStore.applicationSuiteName`.
public final class UserDefaultsSettingsStore: SettingsStore, @unchecked Sendable {
    public static let applicationSuiteName = "com.lijigang.supervim"
    public static let storageKey = "com.lijigang.supervim.settings"

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults, key: String = UserDefaultsSettingsStore.storageKey) {
        self.defaults = defaults
        self.key = key
    }

    public func read() throws -> Data? {
        guard defaults.object(forKey: key) != nil else {
            return nil
        }
        guard let data = defaults.data(forKey: key) else {
            throw SettingsError.unreadableDocument
        }
        return data
    }

    public func write(_ data: Data) throws {
        defaults.set(data, forKey: key)
    }
}
