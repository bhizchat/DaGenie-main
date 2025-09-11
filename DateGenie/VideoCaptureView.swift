//
//  VideoCaptureView.swift
//  DateGenie
//
//  Presents the system camera UI for video, uploads the recording to Storage,
//  writes a Journey node in Firestore, and awards romance points.
//

import SwiftUI
import UIKit
import AVFoundation
import FirebaseAuth
@preconcurrency import FirebaseFunctions
import FirebaseStorage

struct VideoCaptureView: UIViewControllerRepresentable {
    let points: Int
    @Environment(\.dismiss) private var dismiss
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .video
        picker.videoQuality = .typeMedium
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    // MARK: - Coordinator
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: VideoCaptureView
        private let functions = Functions.functions(region: "us-central1")
        
        init(_ parent: VideoCaptureView) { self.parent = parent }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            // Expect a file URL for the movie
            let mediaURL = info[.mediaURL] as? URL
            picker.dismiss(animated: true) {
                guard let mediaURL = mediaURL else {
                    print("[VideoCaptureView] No mediaURL provided; awarding points only.")
                    self.awardPoints()
                    return
                }
                self.handleVideoAndPersist(fileURL: mediaURL)
            }
        }
        
        private func awardPoints() {
            Task {
                do {
                    let res = try await functions.httpsCallable("awardRomancePoints").call(["points": parent.points])
                    _ = res.data
                } catch {
                    print("[VideoCaptureView] Failed to award points: \(error.localizedDescription)")
                }
            }
            parent.dismiss()
        }
        
        private func handleVideoAndPersist(fileURL: URL) {
            // Ensure we have a UID
            guard let uid = Auth.auth().currentUser?.uid else {
                print("[VideoCaptureView] Missing Auth UID; awarding points only.")
                awardPoints()
                return
            }
            
            // Determine duration in seconds (use synchronous path; feature is currently deprioritized)
            let asset = AVURLAsset(url: fileURL)
            let durationSeconds = Int(CMTimeGetSeconds(asset.duration).rounded())
            
            // Upload to Storage
            let filename = UUID().uuidString + ".mov"
            let objectPath = "userMedia/\(uid)/videos/\(filename)"
            let ref = Storage.storage().reference().child(objectPath)
            let metadata = StorageMetadata()
            metadata.contentType = "video/quicktime"
            
            ref.putFile(from: fileURL, metadata: metadata) { _, error in
                if let error = error {
                    print("[VideoCaptureView] Storage upload failed: \(error.localizedDescription)")
                    self.awardPoints()
                    return
                }
                ref.downloadURL { url, err in
                    if let err = err {
                        print("[VideoCaptureView] Fetching downloadURL failed: \(err.localizedDescription)")
                        self.awardPoints()
                        return
                    }
                    guard let remoteURL = url else {
                        print("[VideoCaptureView] downloadURL is nil; awarding points only.")
                        self.awardPoints()
                        return
                    }
                    // Build CapturedMedia and persist a Journey node with durationSeconds
                    let media = CapturedMedia(localURL: fileURL, type: .video, caption: nil, remoteURL: remoteURL, uploadProgress: 1.0)
                    JourneyPersistence.shared.saveNode(step: "checkpoint", missionIndex: 0, media: media, durationSeconds: durationSeconds)
                    print("[VideoCaptureView] Persisted node for uploaded video: \(remoteURL.absoluteString) (\(durationSeconds)s)")
                    self.awardPoints()
                }
            }
        }
    }
}
