import Foundation

final class LevelStore {
    static let shared = LevelStore()
    private init() {}

    private let key = "current_level_number"

    var currentLevel: Int {
        get { max(1, UserDefaults.standard.integer(forKey: key)) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    func advanceLevel() {
        currentLevel = currentLevel + 1
    }
}
