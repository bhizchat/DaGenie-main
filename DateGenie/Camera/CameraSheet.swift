import SwiftUI
import UIKit
import AVFoundation
#if canImport(YPImagePicker)
import YPImagePicker
#endif

struct CameraSheet: UIViewControllerRepresentable {
    typealias Completion = (CapturedMedia?) -> Void
    let completion: Completion

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIViewController {
        if FeatureFlags.useCustomCamera {
            return UIHostingController(rootView: CustomCameraView())
        }
        #if canImport(YPImagePicker)
        var config = YPImagePickerConfiguration()
        // Only camera modes, no library
        config.screens = [.photo, .video]
        config.startOnScreen = .photo
        config.onlySquareImagesFromCamera = false
        config.showsPhotoFilters = true // enable basic filters; can disable later if undesired
        config.video.recordingTimeLimit = 30
        config.video.trimmerMaxDuration = 30
        config.video.libraryTimeLimit = 30
        config.isScrollToChangeModesEnabled = true
        config.usesFrontCamera = false // default to back camera

        let picker = YPImagePicker(configuration: config)
        picker.didFinishPicking { items, cancelled in
            if cancelled {
                picker.dismiss(animated: true) { completion(nil) }
                return
            }
            guard let item = items.first else {
                picker.dismiss(animated: true) { completion(nil) }
                return
            }
            var result: CapturedMedia?
            switch item {
            case .photo(let p):
                if let data = p.image.jpegData(compressionQuality: 0.9) {
                    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dg_\(UUID().uuidString).jpg")
                    try? data.write(to: tmp)
                    result = CapturedMedia(localURL: tmp, type: .photo, cameraSource: .system)
                }
            case .video(let v):
                result = CapturedMedia(localURL: v.url, type: .video, cameraSource: .system)
            }
            picker.dismiss(animated: true) {
                completion(result)
            }
        }
        return picker
        #else
        // Fallback to system picker if YPImagePicker isn't available
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = ["public.image", "public.movie"]
        picker.videoMaximumDuration = 30
        picker.cameraCaptureMode = .photo
        picker.cameraDevice = .rear
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
        #endif
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraSheet
        init(_ parent: CameraSheet) { self.parent = parent }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true) {
                self.parent.completion(nil)
            }
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            var result: CapturedMedia?
            if let url = info[.mediaURL] as? URL {
                result = CapturedMedia(localURL: url, type: .video, cameraSource: .system)
            } else if let image = info[.originalImage] as? UIImage,
                      let data = image.jpegData(compressionQuality: 0.9) {
                let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dg_\(UUID().uuidString).jpg")
                try? data.write(to: tmp)
                result = CapturedMedia(localURL: tmp, type: .photo, cameraSource: .system)
            }
            picker.dismiss(animated: true) {
                self.parent.completion(result)
            }
        }
    }
}
