import Foundation

struct Project: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var createdAt: Date
    var videoURL: URL?
    var thumbURL: URL?
    // Draft/project lifecycle metadata
    var isDraft: Bool = true
    var lastEditedAt: Date? = nil
    // Local-only path for placeholder thumbnail when offline (not encoded to Firestore)
    var draftThumbnailLocalPath: String? = nil
    // Optional progress fields (mirrors Firestore fields if present)
    var durationSec: Double? = nil
    var clipCount: Int? = nil
    // Storyboard linkage so "+" can resume next scene
    var storyboardId: String? = nil
    var currentSceneIndex: Int? = nil
    var totalScenes: Int? = nil
}


