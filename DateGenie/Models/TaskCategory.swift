import Foundation

/// Simple keyword‐based categorisation of task text to map to an image asset name.
/// If the logic ever changes on the backend (e.g. you send an explicit category string),
/// swap the implementation of `imageName(for:)` to simply return that value.
struct TaskCategory {
    /// Returns the asset name (e.g. "task_arcade") for the provided task text.
    /// Returns nil when no keyword matched.
    static func imageName(for text: String) -> String? {
        let lower = text.lowercased()
        if matches(lower, anyOf: ["arcade", "tickets", "claw machine", "skee", "gaming"]) {
            return "task_arcade"
        }
        if matches(lower, anyOf: ["museum", "gallery", "artist", "sculpture", "artsy", "panorama"]) {
            return "task_artsy"
        }
        if matches(lower, anyOf: ["kiss", "romantic", "love", "titanic", "heart", "poem", "pick-up"]) {
            return "task_romantic"
        }
        if matches(lower, anyOf: ["hike", "trail", "outdoor", "bench", "grass", "leaves", "park"]){
            return "task_outdoorsy"
        }
        if matches(lower, anyOf: ["boba", "bubble tea", "milk tea"]){
            return "task_boba"
        }
        if matches(lower, anyOf: ["comfort", "burger", "pizza", "fries", "mac"]){
            return "task_comfort"
        }
        if matches(lower, anyOf: ["band", "concert", "music", "song", "guitar", "live"]){
            return "task_live_music"
        }
        if matches(lower, anyOf: ["bar", "drink", "cheers", "cocktail", "beer"]){
            return "task_bar"
        }
        return nil
    }

    private static func matches(_ lowercasedText: String, anyOf keywords: [String]) -> Bool {
        for k in keywords {
            // build word-boundary regex to avoid partial hits like "partner" containing "art"
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: k) + "\\b"
            if lowercasedText.range(of: pattern, options: [.regularExpression]) != nil {
                return true
            }
        }
        return false
    }
}
