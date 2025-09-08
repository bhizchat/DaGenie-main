import Foundation
#if canImport(FirebaseStorage)
import FirebaseStorage
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

final class MediaUploadManager {
    static let shared = MediaUploadManager()
    private init() {}

    struct UploadHandle {
        let id: UUID
        let task: StorageUploadTask
    }

    @discardableResult
    func upload(media: CapturedMedia, step: String, progress: @escaping (Double) -> Void, completion: @escaping (Result<URL, Error>) -> Void) -> UploadHandle? {
        let storage = Storage.storage()
        let ext = media.type == .photo ? "jpg" : "mp4"
        let ownerId: String = {
            #if canImport(FirebaseAuth)
            return Auth.auth().currentUser?.uid ?? DeviceID.shared.id
            #else
            return DeviceID.shared.id
            #endif
        }()
        let path = "userMedia/\(ownerId)/\(step)/\(media.id.uuidString).\(ext)"
        let ref = storage.reference().child(path)

        let metadata = StorageMetadata()
        metadata.contentType = media.type == .photo ? "image/jpeg" : "video/mp4"

        guard let data = try? Data(contentsOf: media.localURL) else { return nil }
        let task = ref.putData(data, metadata: metadata) { _, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            ref.downloadURL { url, err in
                if let err = err { completion(.failure(err)); return }
                completion(.success(url!))
            }
        }

        let id = UUID()
        task.observe(.progress) { snapshot in
            let pct = Double(snapshot.progress?.fractionCompleted ?? 0)
            progress(pct)
        }
        task.observe(.success) { _ in
            AnalyticsManager.shared.logEvent("media_upload_success", parameters: [
                "type": media.type == .photo ? "photo" : "video",
                "step": step,
                "source": "unknown"
            ])
        }
        task.observe(.failure) { _ in
            AnalyticsManager.shared.logEvent("media_upload_failure", parameters: [
                "type": media.type == .photo ? "photo" : "video",
                "step": step,
                "source": "unknown"
            ])
        }
        return UploadHandle(id: id, task: task)
    }
}
#else
final class MediaUploadManager {
    static let shared = MediaUploadManager()
    private init() {}

    struct UploadHandle { let id: UUID }

    @discardableResult
    func upload(media: CapturedMedia, step: String, progress: @escaping (Double) -> Void, completion: @escaping (Result<URL, Error>) -> Void) -> UploadHandle? {
        // Firebase Storage not linked; simulate no-op
        AnalyticsManager.shared.logEvent("media_upload_skipped", parameters: [
            "reason": "FirebaseStorage_missing",
            "type": media.type == .photo ? "photo" : "video",
            "step": step
        ])
        return nil
    }
}
#endif
