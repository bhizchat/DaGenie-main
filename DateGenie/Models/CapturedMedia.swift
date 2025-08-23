import Foundation

enum MediaType: String, Codable {
    case photo
    case video
}

enum CameraSource: String, Codable {
    case custom
    case system
}

struct CapturedMedia: Identifiable, Codable, Equatable {
    let id: UUID
    let localURL: URL
    let type: MediaType
    var caption: String?
    var remoteURL: URL?
    var uploadProgress: Double?
    var cameraSource: CameraSource?

    init(localURL: URL, type: MediaType, caption: String? = nil, remoteURL: URL? = nil, uploadProgress: Double? = nil, cameraSource: CameraSource? = nil) {
        self.id = UUID()
        self.localURL = localURL
        self.type = type
        self.caption = caption
        self.remoteURL = remoteURL
        self.uploadProgress = uploadProgress
        self.cameraSource = cameraSource
    }
}
