import Foundation
import FirebaseFirestore
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif
#if canImport(FirebaseStorage)
import FirebaseStorage
#endif
#if canImport(Photos)
import Photos
#endif

@MainActor
final class HighlightReelRepository: ObservableObject {
    static let shared = HighlightReelRepository()
    private init() {}

    @Published private(set) var reels: [HighlightReel] = []

    private let db = Firestore.firestore()

    private func userCollection() throws -> CollectionReference {
        #if canImport(FirebaseAuth)
        guard let uid = Auth.auth().currentUser?.uid else { throw NSError(domain: "HighlightReelRepository", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]) }
        return db.collection("users").document(uid).collection("highlightReels")
        #else
        return db.collection("highlightReels")
        #endif
    }

    func refresh() async {
        do {
            let col = try userCollection()
            let snap = try await col
                .order(by: "createdAt", descending: true)
                .getDocuments()
            let decoded: [HighlightReel] = snap.documents.compactMap { doc in
                // Manual decode to support backward compatibility (video-only docs)
                do {
                    let data = doc.data()
                    let id = data["id"] as? String ?? doc.documentID
                    let ts = data["createdAt"] as? Timestamp ?? Timestamp(date: Date())
                    let createdAt = ts.dateValue()
                    let title = data["title"] as? String ?? "Highlights"
                    let thumb = URL(string: data["thumbnailURL"] as? String ?? "")
                    let video = URL(string: data["videoURL"] as? String ?? "")
                    let image = URL(string: data["imageURL"] as? String ?? "")
                    let mediaType = (data["mediaType"] as? String) ?? (video != nil ? "video" : "photo")
                    let sizeMB = data["sizeMB"] as? Double ?? 0
                    let videoPath = data["videoPath"] as? String
                    let thumbnailPath = data["thumbnailPath"] as? String
                    let _ = data["cameraSource"] as? String // present but not in model yet
                    guard let thumbnailURL = thumb else { return nil }
                    return HighlightReel(id: id,
                                         createdAt: createdAt,
                                         title: title,
                                         thumbnailURL: thumbnailURL,
                                         videoURL: video,
                                         imageURL: image,
                                         mediaType: mediaType,
                                         sizeMB: sizeMB,
                                         videoPath: videoPath,
                                         thumbnailPath: thumbnailPath)
                } catch {
                    return try? doc.data(as: HighlightReel.self)
                }
            }
            self.reels = decoded
            print("[HighlightReelRepository] loaded reels count=\(decoded.count)")
        } catch {
            print("[HighlightReelRepository] failed to load: \(error)")
        }
    }

    // Uploads video + thumbnail to Storage and writes a Firestore doc. Returns the created model.
    func create(fromExportURL exportURL: URL, thumbnail: Data, level: Int, runId: String, title: String?, cameraSource: String? = nil) async throws -> HighlightReel {
        #if canImport(FirebaseAuth) && canImport(FirebaseStorage)
        guard let uid = Auth.auth().currentUser?.uid else { throw NSError(domain: "HighlightReelRepository", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]) }
        let reelId = UUID().uuidString
        let base = "userHighlights/\(uid)/\(reelId)"
        let storage = Storage.storage()

        // Upload video
        let videoRef = storage.reference().child("\(base)/reel.mp4")
        let videoData = try Data(contentsOf: exportURL)
        _ = try await videoRef.putDataAsync(videoData, metadata: { let m = StorageMetadata(); m.contentType = "video/mp4"; return m }())
        let videoURL = try await videoRef.downloadURL()

        // Upload thumbnail
        let thumbRef = storage.reference().child("\(base)/thumb.jpg")
        _ = try await thumbRef.putDataAsync(thumbnail, metadata: { let m = StorageMetadata(); m.contentType = "image/jpeg"; return m }())
        let thumbURL = try await thumbRef.downloadURL()

        // Compute sizeMB
        let attrs = try FileManager.default.attributesOfItem(atPath: exportURL.path)
        let bytes = (attrs[.size] as? NSNumber)?.doubleValue ?? 0
        let sizeMB = bytes / (1024 * 1024)

        // Determine default title: "Highlights N" with next available index
        let nextIndex: Int = {
            let nums = self.reels.compactMap { reel -> Int? in
                let t = reel.title.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("Highlights ") {
                    let s = t.dropFirst("Highlights ".count)
                    return Int(s)
                }
                return nil
            }
            return (nums.max() ?? 0) + 1
        }()
        let resolvedTitle = title ?? "Highlights \(nextIndex)"

        var doc: [String: Any] = [
            "id": reelId,
            "createdAt": Timestamp(date: Date()),
            "title": resolvedTitle,
            "thumbnailURL": thumbURL.absoluteString,
            "videoURL": videoURL.absoluteString,
            "mediaType": "video",
            "sizeMB": sizeMB,
            "level": level,
            "runId": runId,
            "videoPath": "\(base)/reel.mp4",
            "thumbnailPath": "\(base)/thumb.jpg"
        ]
        if let cameraSource { doc["cameraSource"] = cameraSource }
        let col = try userCollection()
        try await col.document(reelId).setData(doc, merge: true)

        let model = HighlightReel(id: reelId,
                                   createdAt: Date(),
                                   title: resolvedTitle,
                                   thumbnailURL: thumbURL,
                                   videoURL: videoURL,
                                   imageURL: nil,
                                   mediaType: "video",
                                   sizeMB: sizeMB,
                                   videoPath: "\(base)/reel.mp4",
                                   thumbnailPath: "\(base)/thumb.jpg")
        // Update local cache
        var copy = reels
        copy.insert(model, at: 0)
        self.reels = copy
        print("[HighlightReelRepository] created reel id=\(reelId) url=\(videoURL)")
        return model
        #else
        throw NSError(domain: "HighlightReelRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "FirebaseAuth/Storage not available"])
        #endif
    }
}

// MARK: - Management APIs (download + delete)
extension HighlightReelRepository {
    // Create a photo highlight from a local JPEG URL
    func createPhoto(fromLocalURL localURL: URL, level: Int, runId: String, title: String?, cameraSource: String? = nil) async throws -> HighlightReel {
        #if canImport(FirebaseAuth) && canImport(FirebaseStorage)
        guard let uid = Auth.auth().currentUser?.uid else { throw NSError(domain: "HighlightReelRepository", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]) }
        let reelId = UUID().uuidString
        let base = "userHighlights/\(uid)/\(reelId)"
        let storage = Storage.storage()

        // Upload image (original serves as both image and thumbnail)
        let imageRef = storage.reference().child("\(base)/image.jpg")
        let data = try Data(contentsOf: localURL)
        _ = try await imageRef.putDataAsync(data, metadata: { let m = StorageMetadata(); m.contentType = "image/jpeg"; return m }())
        let imageURL = try await imageRef.downloadURL()

        // Compute sizeMB
        let attrs = try FileManager.default.attributesOfItem(atPath: localURL.path)
        let bytes = (attrs[.size] as? NSNumber)?.doubleValue ?? 0
        let sizeMB = bytes / (1024 * 1024)

        let resolvedTitle = title ?? "Photo Highlight"

        var doc: [String: Any] = [
            "id": reelId,
            "createdAt": Timestamp(date: Date()),
            "title": resolvedTitle,
            "thumbnailURL": imageURL.absoluteString,
            "imageURL": imageURL.absoluteString,
            "mediaType": "photo",
            "sizeMB": sizeMB,
            "level": level,
            "runId": runId,
            "thumbnailPath": "\(base)/image.jpg"
        ]
        if let cameraSource { doc["cameraSource"] = cameraSource }
        let col = try userCollection()
        try await col.document(reelId).setData(doc, merge: true)

        let model = HighlightReel(id: reelId,
                                   createdAt: Date(),
                                   title: resolvedTitle,
                                   thumbnailURL: imageURL,
                                   videoURL: nil,
                                   imageURL: imageURL,
                                   mediaType: "photo",
                                   sizeMB: sizeMB,
                                   videoPath: nil,
                                   thumbnailPath: "\(base)/image.jpg")
        await MainActor.run {
            var copy = reels
            copy.insert(model, at: 0)
            self.reels = copy
        }
        return model
        #else
        throw NSError(domain: "HighlightReelRepository", code: 0, userInfo: [NSLocalizedDescriptionKey: "FirebaseAuth/Storage not available"])
        #endif
    }
    func rename(_ reel: HighlightReel, to newTitle: String) async throws {
        #if canImport(FirebaseAuth)
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let col = db.collection("users").document(uid).collection("highlightReels")
        try await col.document(reel.id).setData(["title": newTitle], merge: true)
        if let idx = reels.firstIndex(where: { $0.id == reel.id }) {
            var updated = reels[idx]
            // Rebuild struct with new title (immutability)
            updated = HighlightReel(id: updated.id,
                                    createdAt: updated.createdAt,
                                    title: newTitle,
                                    thumbnailURL: updated.thumbnailURL,
                                    videoURL: updated.videoURL,
                                    imageURL: updated.imageURL,
                                    mediaType: updated.mediaType,
                                    sizeMB: updated.sizeMB,
                                    videoPath: updated.videoPath,
                                    thumbnailPath: updated.thumbnailPath)
            reels[idx] = updated
        }
        #endif
    }
    func downloadAndSaveToPhotos(_ reel: HighlightReel) async throws {
        guard let url = reel.videoURL else { return }
        let (tempURL, _) = try await URLSession.shared.download(from: url)
        try await saveVideoToPhotos(tempURL: tempURL)
    }

    func downloadPhotoAndSaveToPhotos(_ reel: HighlightReel) async throws {
        guard let url = reel.imageURL else { return }
        let (tempURL, _) = try await URLSession.shared.download(from: url)
        try await saveImageToPhotos(tempURL: tempURL)
    }

    private func saveVideoToPhotos(tempURL: URL) async throws {
        #if canImport(Photos)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                guard status == .authorized || status == .limited else {
                    cont.resume(throwing: NSError(domain: "PhotosDenied", code: 1))
                    return
                }
                func performSave() {
                    PHPhotoLibrary.shared().performChanges({
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: tempURL)
                    }, completionHandler: { success, error in
                        if let e = error { cont.resume(throwing: e) } else { cont.resume(returning: ()) }
                    })
                }
                performSave()
            }
        }
        #else
        throw NSError(domain: "PhotosUnavailable", code: 0)
        #endif
    }

    private func saveImageToPhotos(tempURL: URL) async throws {
        #if canImport(Photos)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                guard status == .authorized || status == .limited else {
                    cont.resume(throwing: NSError(domain: "PhotosDenied", code: 1))
                    return
                }
                func performSave() {
                    PHPhotoLibrary.shared().performChanges({
                        PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: tempURL)
                    }, completionHandler: { success, error in
                        if let e = error { cont.resume(throwing: e) } else { cont.resume(returning: ()) }
                    })
                }
                performSave()
            }
        }
        #else
        throw NSError(domain: "PhotosUnavailable", code: 0)
        #endif
    }

    func delete(_ reel: HighlightReel) async throws {
        #if canImport(FirebaseAuth) && canImport(FirebaseStorage)
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let col = db.collection("users").document(uid).collection("highlightReels")
        let storage = Storage.storage()
        if let vp = reel.videoPath { try? await storage.reference(withPath: vp).delete() }
        if let tp = reel.thumbnailPath { try? await storage.reference(withPath: tp).delete() }
        try await col.document(reel.id).delete()
        await MainActor.run { self.reels.removeAll { $0.id == reel.id } }
        #endif
    }
}
