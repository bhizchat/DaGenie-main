import SwiftUI
import RealityKit

/// Lightweight wrapper so SwiftUI can host ARView and we can bind the instance back to the parent view.
struct ARViewContainer: UIViewRepresentable {
    @Binding var arView: ARView?

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        // Brighten perceived camera feed if needed
        if #available(iOS 17.0, *) {
            view.environment.background = .cameraFeed(exposureCompensation: 1.0)
        }
        // Bind out so parent can access session & scene
        DispatchQueue.main.async { arView = view }
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        // Nothing to update dynamically yet
    }
}
