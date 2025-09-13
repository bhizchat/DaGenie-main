import Foundation

enum JourneyStep: String, Codable {
    case game
    case task
    case checkpoint
    case date_plan
}

struct JourneyNodeMedia: Codable {
    let id: UUID
    let type: String // "photo" or "video"
    let caption: String?
    let remoteURL: String
    let localFilename: String?
    let durationSeconds: Int?
    let createdAt: Date
}

struct JourneyNode: Codable {
    let id: UUID
    let step: JourneyStep
    let level: Int
    let missionIndex: Int
    let runId: String?
    let media: JourneyNodeMedia
    let createdAt: Date
}

struct JourneyLevelHeader: Codable {
    let level: Int
    let createdAt: Date
    let coverImageURL: String?
    // Added for completed adventures stored in Journey
    let completedAt: Date?
    let completedRunId: String?
    let totalPoints: Int?
    let claimedAt: Date?
}
