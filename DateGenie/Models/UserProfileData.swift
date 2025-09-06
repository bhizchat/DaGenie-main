import Foundation

struct UserProfileData: Codable {
    var photoURL: String?
    var username: String?
    var firstName: String?
    var lastName: String?
    var displayName: String?
    // Local or remote URL string for the user's transparent brand logo PNG
    // Stored as a string to keep Firestore schema simple; prefer a local file URL when available
    var brandLogoURL: String?
}


