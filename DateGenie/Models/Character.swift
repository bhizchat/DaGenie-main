import Foundation

struct GenCharacter: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let defaultImageUrl: String
    let assetImageUrls: [String]
    // Optional: name of bundled asset in the app to use as a header image
    // This allows characters to render immediately without needing a remote URL
    let localAssetName: String?
    // Optional bio/description for user-created characters
    let bio: String?

    init(id: String, name: String, defaultImageUrl: String, assetImageUrls: [String], localAssetName: String? = nil, bio: String? = nil) {
        self.id = id
        self.name = name
        self.defaultImageUrl = defaultImageUrl
        self.assetImageUrls = assetImageUrls
        self.localAssetName = localAssetName
        self.bio = bio
    }
}


