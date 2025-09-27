import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

/// Repository for the music video flow. This will later call Cloud Functions and Replicate.
@MainActor
final class MusicVideoRepository {
    static let shared = MusicVideoRepository()
    private init() {}

    private let db = Firestore.firestore()
    private let storage = Storage.storage()

    struct CreateProjectResult { let projectId: String; let audioGsPath: String; let referenceUrl: String }

    func createProjectAndUpload(userId: String, referenceImageData: Data, audioURL: URL) async throws -> CreateProjectResult {
        let projectId = UUID().uuidString
        let root = "users/\(userId)/musicVideos/\(projectId)"
        // Upload reference image (set correct content type)
        let refRef = storage.reference(withPath: "\(root)/reference.jpg")
        let imgMeta = StorageMetadata()
        imgMeta.contentType = "image/jpeg"
        _ = try await refRef.putDataAsync(referenceImageData, metadata: imgMeta)
        let refUrl = try await refRef.downloadURL().absoluteString
        // Upload audio with explicit content type (so server preflight sees audio/*)
        let ext = audioURL.pathExtension.isEmpty ? "m4a" : audioURL.pathExtension.lowercased()
        let audioRef = storage.reference(withPath: "\(root)/audio/track.\(ext)")
        let data = try Self.loadAudioData(from: audioURL)
        let audioMeta = StorageMetadata()
        // Basic mapping; extend if you support more formats
        audioMeta.contentType = (ext == "mp3" ? "audio/mpeg" : (ext == "wav" ? "audio/wav" : (ext == "aac" ? "audio/aac" : "audio/mp4")))
        _ = try await audioRef.putDataAsync(data, metadata: audioMeta)
        let audioGs = "gs://\(storage.reference().bucket)/\(audioRef.fullPath)"
        // Seed firestore doc
        try await db.collection("users").document(userId).collection("musicVideos").document(projectId).setData([
            "status": "created",
            "createdAt": FieldValue.serverTimestamp(),
            "referenceImage": refUrl,
            "audio": ["gs": audioGs],
        ])
        return CreateProjectResult(projectId: projectId, audioGsPath: audioGs, referenceUrl: refUrl)
    }
}

// MARK: - Avatar generation client
extension MusicVideoRepository {
    struct AvatarResult: Decodable { let avatarUrl: String }

    func generateAvatar(referenceImageUrl: String, prompt: String? = nil) async throws -> String {
        let gcp = (Bundle.main.object(forInfoDictionaryKey: "FirebaseProjectID") as? String) ?? "dategenie-dev"
        let url = URL(string: "https://us-central1-\(gcp).cloudfunctions.net/generateFluxAvatar")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["referenceImage": referenceImageUrl]
        if let p = prompt { body["prompt"] = p }
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "MusicVideoRepository", code: (resp as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? "avatar_failed"])
        }
        let obj = try JSONDecoder().decode(AvatarResult.self, from: data)
        return obj.avatarUrl
    }

    /// Convenience: send a UIImage as a data URI so backend can rehost and process
    func generateAvatar(from image: UIImage, prompt: String? = nil) async throws -> String {
        guard let data = image.pngData() else { throw NSError(domain: "MusicVideoRepository", code: -2, userInfo: [NSLocalizedDescriptionKey: "image_encoding_failed"]) }
        let b64 = data.base64EncodedString()
        let dataUri = "data:image/png;base64,\(b64)"
        return try await generateAvatar(referenceImageUrl: dataUri, prompt: prompt)
    }

    // MARK: - Helpers
    private static func loadAudioData(from url: URL) throws -> Data {
        var accessed = false
        if url.startAccessingSecurityScopedResource() { accessed = true }
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            return try Data(contentsOf: url)
        }
        // Attempt to copy to a stable temp location (iCloud/file-provider edge cases)
        let ext = url.pathExtension.isEmpty ? "m4a" : url.pathExtension
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("picked_audio_\(UUID().uuidString).\(ext)")
        do {
            try fm.copyItem(at: url, to: tmp)
            return try Data(contentsOf: tmp)
        } catch {
            throw NSError(domain: "MusicVideoRepository", code: -3, userInfo: [NSLocalizedDescriptionKey: "audio_file_unavailable: \(url.path)"])
        }
    }
}

// MARK: - Finishing pipeline client calls
extension MusicVideoRepository {
    func startMusicFinishing(uid: String, projectId: String, storyboardId: String, runId: String, audioGsPath: String, audioDurationSec: Double) async throws {
        let gcp = (Bundle.main.object(forInfoDictionaryKey: "FirebaseProjectID") as? String) ?? "dategenie-dev"
        let url = URL(string: "https://us-central1-\(gcp).cloudfunctions.net/startMusicFinishingV2")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "uid": uid,
            "projectId": projectId,
            "storyboardId": storyboardId,
            "runId": runId,
            "audioGsPath": audioGsPath,
            "audioDurationSec": audioDurationSec
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "MusicVideoRepository", code: (resp as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: "startMusicFinishing_failed"])
        }
    }

    func submitLipsync(uid: String, projectId: String, storyboardId: String, runId: String, videoUrlOverride: URL? = nil, audioUrlOverride: String? = nil) async throws {
        let gcp = (Bundle.main.object(forInfoDictionaryKey: "FirebaseProjectID") as? String) ?? "dategenie-dev"
        let url = URL(string: "https://us-central1-\(gcp).cloudfunctions.net/submitLipsyncV2")!
        var payload: [String: Any] = ["uid": uid, "projectId": projectId, "storyboardId": storyboardId, "runId": runId]
        if let v = videoUrlOverride { payload["videoUrl"] = v.absoluteString }
        if let a = audioUrlOverride, !a.isEmpty { payload["audioUrl"] = a }

        // Small transient retry with jitter
        var lastError: Error?
        for attempt in 0..<3 {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.addValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard let http = resp as? HTTPURLResponse else {
                    throw NSError(domain: "MusicVideoRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "submitLipsync_no_http_response"])
                }
                if (200..<300).contains(http.statusCode) {
                    // Success; optionally parse replayed flag
                    return
                }
                // 422 validation: decode server error body
                if http.statusCode == 422 {
                    if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let code = (obj["code"] as? String) ?? "validation_error"
                        let which = (obj["which"] as? String)
                        throw NSError(domain: "MusicVideoRepository", code: 422, userInfo: [NSLocalizedDescriptionKey: "submitLipsync_validation", "code": code, "which": which ?? ""])
                    }
                    throw NSError(domain: "MusicVideoRepository", code: 422, userInfo: [NSLocalizedDescriptionKey: "submitLipsync_validation"])
                }
                // Treat 5xx/timeout-like as transient and retry
                if http.statusCode >= 500 || http.statusCode == 408 || http.statusCode == 429 {
                    lastError = NSError(domain: "MusicVideoRepository", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "submitLipsync_transient_\(http.statusCode)"])
                } else {
                    throw NSError(domain: "MusicVideoRepository", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "submitLipsync_failed_\(http.statusCode)"])
                }
            } catch {
                lastError = error
            }
            // Backoff with jitter
            let baseMs = 300 * Int(pow(2.0, Double(attempt)))
            let jitter = Int.random(in: 0..<(baseMs))
            try? await Task.sleep(nanoseconds: UInt64((baseMs + jitter) * 1_000_000))
        }
        throw lastError ?? NSError(domain: "MusicVideoRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "submitLipsync_failed_after_retries"])
    }

    func muxAudioVideo(uid: String, projectId: String, storyboardId: String, runId: String) async throws {
        let gcp = (Bundle.main.object(forInfoDictionaryKey: "FirebaseProjectID") as? String) ?? "dategenie-dev"
        let url = URL(string: "https://us-central1-\(gcp).cloudfunctions.net/muxAudioVideo")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["uid": uid, "projectId": projectId, "storyboardId": storyboardId, "runId": runId]
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "MusicVideoRepository", code: (resp as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: "muxAudioVideo_failed"])
        }
    }
}


