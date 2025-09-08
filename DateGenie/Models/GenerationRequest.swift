import Foundation

struct GenerationRequest: Codable {
    let characterId: String
    let ideaText: String
    let userReferenceImageIds: [String]
    // Optional richer background/persona to guide prompts
    let characterBackground: String?
    // Optional direct URLs for backend planner (preferred over IDs)
    let userReferenceImageUrls: [String]?

    init(
        characterId: String,
        ideaText: String,
        userReferenceImageIds: [String],
        characterBackground: String? = nil,
        userReferenceImageUrls: [String]? = nil
    ) {
        self.characterId = characterId
        self.ideaText = ideaText
        self.userReferenceImageIds = userReferenceImageIds
        self.characterBackground = characterBackground
        self.userReferenceImageUrls = userReferenceImageUrls
    }
}




