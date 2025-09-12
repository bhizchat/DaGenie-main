//
//  PointsPhotoCaptureView.swift
//  DateGenie
//
//  Presents the camera, previews the captured photo with the plan title, and lets the
//  user award romance points by calling the Cloud Function `awardRomancePoints`.
//

import SwiftUI
import UIKit
@preconcurrency import FirebaseFunctions

/// Top-level flow view shown in a sheet.
struct PointsPhotoCaptureView: View {
    let points: Int
    let planId: String
    let planTitle: String
    @Environment(\.dismiss) private var dismiss
    @State private var captured: UIImage?
    @State private var isUploading = false
    @State private var showCamera = true
    private let functions = Functions.functions(region: "us-central1")

    var body: some View {
        VStack {
            if let img = captured {
                VStack(spacing: 16) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 360)
                        .cornerRadius(12)
                    Text(planTitle)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    if isUploading {
                        ProgressView("Awarding Points…")
                    } else {
                        Button("Get \(points) Points") {
                            awardPoints()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.pink)
                    }
                }
                .padding()
                .overlay(alignment: .topTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.secondary)
                    }
                    .accessibilityLabel("Close")
                    .padding(8)
                }
            }
        }
        .interactiveDismissDisabled(true)
        .fullScreenCover(isPresented: $showCamera, onDismiss: { print("camera dismissed") }) {
            CameraCaptureView(
                onCapture: { image in
                    print("👀 captured set, presenting preview")
                    DispatchQueue.main.async { captured = image }
                },
                onCancel: {
                    dismiss()
                }
            )
            .ignoresSafeArea()
        }
    }

    private func awardPoints() {
        isUploading = true
        Task {
            do {
                let res = try await functions.httpsCallable("awardRomancePoints").call(["points": points, "planId": planId])
                _ = res.data
            } catch {
                print("Failed to award points: \(error.localizedDescription)")
            }
            isUploading = false
            UserDefaults.standard.set(true, forKey: "awarded_\(planId)")
            NotificationCenter.default.post(name: .pointsAwarded, object: planId)
            dismiss()
        }
    }
}

// MARK: - UIKit camera wrapper

// UIKit camera wrapper used inside fullScreenCover
private struct CameraCaptureView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraCaptureView
        init(parent: CameraCaptureView) { self.parent = parent }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss(); parent.onCancel()
        }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let img = (info[.originalImage] as? UIImage) {
                print("📸 got image size \(img.size)")
                parent.onCapture(img)
            }
            picker.dismiss(animated: true)
        }
    }
}
