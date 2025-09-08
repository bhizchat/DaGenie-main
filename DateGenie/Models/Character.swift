import Foundation

struct GenCharacter: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let defaultImageUrl: String
    let assetImageUrls: [String]
    // Optional: name of bundled asset in the app to use as a header image
    // This allows characters to render immediately without needing a remote URL
    let localAssetName: String?
}


