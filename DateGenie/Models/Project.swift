import Foundation

struct Project: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var createdAt: Date
    var videoURL: URL?
    var thumbURL: URL?
}


