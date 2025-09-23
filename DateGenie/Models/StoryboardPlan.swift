import Foundation

struct StoryboardPlan: Codable {
    let character: PlanCharacter
    let settings: PlanSettings
    var scenes: [PlanScene]
    var referenceImageUrls: [String]? // up to 3 user-provided images for composition
}

struct PlanCharacter: Codable { let id: String }

struct PlanSettings: Codable {
    var aspectRatio: String
    var style: String
    var camera: String?
}

struct PlanScene: Codable, Identifiable {
    var id: Int { index }
    let index: Int
    let prompt: String
    var script: String
    let durationSec: Double?
    let wordsPerSec: Double?
    var wordBudget: Int?
    var imageUrl: String?
    // New structured fields for clearer editing
    var action: String?
    // "dialogue" or "narration" (simple string to keep Codable compatibility for now)
    var speechType: String?
    var speech: String?
    var animation: String?
    // Optional explicit speaker slot for bubbles: "char1" | "char2" | nil
    var speakerSlot: String?
}


