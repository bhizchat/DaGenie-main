import Foundation
import FirebaseAuth
import FirebaseStorage
import UIKit

struct UploadedImage: Codable, Identifiable, Equatable {
    let id: String
    let url: String
}

@MainActor
final class UploadRepository: ObservableObject {
    static let shared = UploadRepository()
    private init() {}

    @Published var isUploading: Bool = false

    /// Compresses to max 1080px and uploads to Firebase Storage. Returns an id and public URL.
    func uploadUserReference(_ image: UIImage) async throws -> UploadedImage {
        guard let uid = Auth.auth().currentUser?.uid else { throw NSError(domain: "Upload", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user"]) }
        let resized = await Self.resize(image: image, maxSide: 1080)
        guard let data = resized.jpegData(compressionQuality: 0.85) else { throw NSError(domain: "Upload", code: -2, userInfo: [NSLocalizedDescriptionKey: "Encode failed"]) }
        let storage = Storage.storage()
        let sessionId = UUID().uuidString
        let objectPath = "user-references/\(uid)/\(sessionId)/ref.jpg"
        let ref = storage.reference(withPath: objectPath)
        let metadata = StorageMetadata(); metadata.contentType = "image/jpeg"
        isUploading = true
        defer { isUploading = false }
        _ = try await ref.putDataAsync(data, metadata: metadata)
        let url = try await ref.downloadURL()
        let id = UUID().uuidString
        return UploadedImage(id: id, url: url.absoluteString)
    }

    private static func resize(image: UIImage, maxSide: CGFloat) async -> UIImage {
        let size = image.size
        let maxCurrentSide = max(size.width, size.height)
        guard maxCurrentSide > maxSide else { return image }
        let scale = maxSide / maxCurrentSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let renderer = UIGraphicsImageRenderer(size: newSize)
                let img = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
                cont.resume(returning: img)
            }
        }
    }
}


