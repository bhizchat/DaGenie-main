import Foundation
import AVFoundation
import ARKit

// MARK: - PhotoDelegate
// Captures AVCapturePhoto results and writes them to a temporary JPEG file.
// When capture finishes, the completion handler returns the file URL or nil on failure.
final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let onFinish: (URL?) -> Void

    init(onFinish: @escaping (URL?) -> Void) {
        self.onFinish = onFinish
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error = error { print("[PhotoDelegate] error:", error.localizedDescription) }
        guard error == nil,
              let data = photo.fileDataRepresentation() else {
            print("[PhotoDelegate] fileDataRepresentation nil")
            onFinish(nil)
            return
        }
        // Write to a temp JPEG
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("dg_cam_\(UUID().uuidString).jpg")
        do {
            try data.write(to: url)
            print("[PhotoDelegate] wrote photo=\(url.lastPathComponent) bytes=\(data.count)")
            onFinish(url)
        } catch {
            print("[PhotoDelegate] write error:", error.localizedDescription)
            onFinish(nil)
        }
    }
}

// MARK: - ARSessionDelegateProxy
// Because ARSessionDelegate requires an NSObject (class) conformer, we bridge
// delegate callbacks to SwiftUI via a lightweight proxy.
final class ARSessionDelegateProxy: NSObject, ARSessionDelegate {
    private let onTrackingStateChange: (ARCamera.TrackingState) -> Void

    init(onTrackingStateChange: @escaping (ARCamera.TrackingState) -> Void) {
        self.onTrackingStateChange = onTrackingStateChange
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        onTrackingStateChange(camera.trackingState)
    }
}
