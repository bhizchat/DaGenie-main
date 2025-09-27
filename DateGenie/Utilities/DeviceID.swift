import Foundation

final class DeviceID {
    static let shared = DeviceID()
    private let storageKey = "device_id"
    let id: String

    private init() {
        if let existing = UserDefaults.standard.string(forKey: storageKey), !existing.isEmpty {
            id = existing
        } else {
            let newId = UUID().uuidString
            UserDefaults.standard.set(newId, forKey: storageKey)
            id = newId
        }
    }
}


