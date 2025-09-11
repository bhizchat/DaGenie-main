import SwiftUI
import PencilKit

struct PKCanvasRepresentable: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var isInteractive: Bool
    var tool: PKTool
    // When false, finger drawing is disabled (Pencil-only if available)
    var allowsFinger: Bool = true

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.isOpaque = false
        canvas.backgroundColor = .clear
        canvas.drawingPolicy = allowsFinger ? .anyInput : .pencilOnly
        canvas.tool = tool
        canvas.isUserInteractionEnabled = isInteractive
        canvas.allowsFingerDrawing = allowsFinger
        canvas.delegate = context.coordinator
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        // Keep drawing content up to date
        uiView.drawing = drawing
        // Always propagate the active tool so color/width changes take effect immediately
        uiView.tool = tool
        // Interactivity and input policy
        uiView.isUserInteractionEnabled = isInteractive
        uiView.allowsFingerDrawing = allowsFinger
        uiView.drawingPolicy = allowsFinger ? .anyInput : .pencilOnly
        if !isInteractive {
            // Ensure we are not capturing touches if disabled
            uiView.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PKCanvasRepresentable
        init(_ parent: PKCanvasRepresentable) { self.parent = parent }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
    }
}


