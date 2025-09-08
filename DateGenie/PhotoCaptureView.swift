//
//  PhotoCaptureView.swift
//  DateGenie
//
//  Presents the system camera UI, captures an image, and awards romance points
//  by calling the Cloud Function `awardRomancePoints`.
//
//  NOTE: Ensure you have added the key "NSCameraUsageDescription" to Info.plist.
//

import SwiftUI
import UIKit
@preconcurrency import FirebaseFunctions
import FirebaseAuth
import FirebaseStorage
import FirebaseFirestore
import FirebaseAnalytics

struct PhotoCaptureView: UIViewControllerRepresentable {
    let points: Int
    @Environment(\.dismiss) private var dismiss
    @State private var isUploading = false
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        AnalyticsManager.shared.logEvent("camera_opened", parameters: [
            "source": "system"
        ])
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    // MARK: - Coordinator
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: PhotoCaptureView
        private let functions = Functions.functions(region: "us-central1")
        private let points: Int
        
        init(_ parent: PhotoCaptureView) { self.parent = parent; self.points = parent.points }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            // Persist the captured image: upload to Storage and write a node doc, then award points.
            let image = (info[.originalImage] as? UIImage)
            picker.dismiss(animated: true) {
                guard let image = image else {
                    print("[PhotoCaptureView] No image found in picker info; awarding points only.")
                    self.awardPoints()
                    return
                }
                AnalyticsManager.shared.logEvent("shutter_photo", parameters: [
                    "source": "system",
                    "mode": "standard"
                ])
                self.handleCaptureAndPersist(image: image)
            }
        }
        
        private func awardPoints() {
            Task {
                do {
                    let res = try await functions.httpsCallable("awardRomancePoints").call(["points": points])
                    _ = res.data // unwrap to avoid crossing actor boundary with result object
                } catch {
                    print("Failed to award points: \(error.localizedDescription)")
                }
            }
            parent.dismiss()
        }

        private func handleCaptureAndPersist(image: UIImage) {
            // Compress to JPEG
            guard let data = image.jpegData(compressionQuality: 0.8) else {
                print("[PhotoCaptureView] Failed to create JPEG data; awarding points only.")
                awardPoints()
                return
            }
            // Ensure we have an authenticated user (anonymous is fine)
            guard let uid = Auth.auth().currentUser?.uid else {
                print("[PhotoCaptureView] Missing Auth UID; awarding points only.")
                awardPoints()
                return
            }

            // Create a temporary local URL (used by CapturedMedia and in case of offline use)
            let filename = UUID().uuidString + ".jpg"
            let tmpUrl = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            do { try data.write(to: tmpUrl) } catch {
                print("[PhotoCaptureView] Failed to write temp image: \(error.localizedDescription)")
            }

            // Upload to Firebase Storage under the owner path
            let storage = Storage.storage()
            let objectPath = "userMedia/\(uid)/photos/\(filename)"
            let ref = storage.reference().child(objectPath)
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"

            parent.isUploading = true
            ref.putData(data, metadata: metadata) { _, error in
                if let error = error {
                    print("[PhotoCaptureView] Storage upload failed: \(error.localizedDescription)")
                    self.parent.isUploading = false
                    self.awardPoints()
                    return
                }
                ref.downloadURL { url, err in
                    self.parent.isUploading = false
                    if let err = err {
                        print("[PhotoCaptureView] Fetching downloadURL failed: \(err.localizedDescription)")
                        self.awardPoints()
                        return
                    }
                    guard let remoteURL = url else {
                        print("[PhotoCaptureView] downloadURL is nil; awarding points only.")
                        self.awardPoints()
                        return
                    }
                    // Build CapturedMedia and persist a Journey node. We use step "checkpoint" and missionIndex 0.
                    let media = CapturedMedia(localURL: tmpUrl, type: .photo, caption: nil, remoteURL: remoteURL, uploadProgress: 1.0, cameraSource: .system)
                    JourneyPersistence.shared.saveNode(step: "checkpoint", missionIndex: 0, media: media, durationSeconds: nil)
                    print("[PhotoCaptureView] Persisted node for uploaded photo: \(remoteURL.absoluteString)")
                    self.awardPoints()
                }
            }
        }
    }
}

// Simple overlay to show while uploading (future use)
struct CameraUploadingOverlay: View {
    var body: some View {
        VStack {
            ProgressView()
            Text("Awarding Points...")
        }
        .padding(24)
        .background(.thinMaterial)
        .cornerRadius(12)
    }
}
