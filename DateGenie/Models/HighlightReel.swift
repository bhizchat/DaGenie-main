import Foundation

/// Metadata for a single highlight reel generated after finishing an adventure.
struct HighlightReel: Identifiable, Codable {
    let id: String
    let createdAt: Date
    let title: String
    let thumbnailURL: URL
    let videoURL: URL?
    let imageURL: URL?
    let mediaType: String // "video" or "photo"
    let sizeMB: Double
    // Storage paths for easy deletion
    let videoPath: String?
    let thumbnailPath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case title
        case thumbnailURL
        case videoURL
        case imageURL
        case mediaType
        case sizeMB
        case videoPath
        case thumbnailPath
    }
}
