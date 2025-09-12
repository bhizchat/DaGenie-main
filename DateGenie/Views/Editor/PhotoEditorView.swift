import SwiftUI
import PencilKit

struct PhotoEditorView: View {
    let originalURL: URL
    let onCancel: () -> Void
    let onExport: (URL) -> Void

    @State private var canvasView = PKCanvasView()
    @State private var toolPicker = PKToolPicker()
    @State private var baseImage: UIImage?
    @State private var caption: String = ""
    @State private var showingKeyboard = false
    @State private var textOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let img = baseImage {
                GeometryReader { geo in
                    ZStack {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        CanvasOverlay(canvasView: $canvasView)

                        // Movable caption text
                        if !caption.isEmpty {
                            Text(caption)
                                .font(.system(size: 36, weight: .bold))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.8), radius: 4, x: 0, y: 2)
                                .padding(8)
                                .background(Color.black.opacity(0.2).blur(radius: 2))
                                .cornerRadius(6)
                                .offset(textOffset)
                                .gesture(
                                    DragGesture().onChanged { value in
                                        textOffset = value.translation
                                    }
                                )
                        }
                    }
                }
            }

            VStack {
                HStack {
                    Button(action: onCancel) {
                        Image("icon_close_red")
                            .resizable()
                            .frame(width: 28, height: 28)
                    }
                    Spacer()
                    Button(action: exportImage) {
                        Text("Save")
                            .font(.vt323(24))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.green.opacity(0.8))
                            .cornerRadius(6)
                    }
                }
                .padding()
                Spacer()

                // Caption entry bar
                HStack(spacing: 8) {
                    TextField("Add a caption", text: $caption)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(12)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(8)
                        .foregroundColor(.white)
                    Button(action: { caption = "" }) {
                        Text("Clear")
                            .font(.vt323(20))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.gray.opacity(0.6))
                            .cornerRadius(6)
                    }
                }
                .padding()
            }
        }
        .onAppear(perform: setup)
    }

    private func setup() {
        if baseImage == nil {
            if let data = try? Data(contentsOf: originalURL), let img = UIImage(data: data) {
                baseImage = img
            }
        }
        toolPicker.setVisible(true, forFirstResponder: canvasView)
        toolPicker.addObserver(canvasView)
        canvasView.becomeFirstResponder()
    }

    private func exportImage() {
        guard let base = baseImage else { return }

        // Render base image, drawing, and caption into single UIImage
        let renderer = UIGraphicsImageRenderer(size: base.size)
        let rendered = renderer.image { ctx in
            // draw base
            base.draw(in: CGRect(origin: .zero, size: base.size))

            // scale canvas drawing to image size
            if let drawing = canvasView.drawing.image(from: canvasView.drawing.bounds, scale: 1).cgImage {
                // Fit drawing bounds to image rect
                let drawRect = CGRect(origin: .zero, size: base.size)
                ctx.cgContext.draw(drawing, in: drawRect)
            }

            // Draw caption roughly centered + offset proportionally
            if !caption.isEmpty {
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 64),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: paragraph,
                    .strokeColor: UIColor.black,
                    .strokeWidth: -4
                ]
                let text = NSString(string: caption)
                let textSize = text.size(withAttributes: attrs)
                let center = CGPoint(x: base.size.width/2 + textOffset.width, y: base.size.height/2 + textOffset.height)
                let origin = CGPoint(x: center.x - textSize.width/2, y: center.y - textSize.height/2)
                text.draw(at: origin, withAttributes: attrs)
            }
        }

        if let data = rendered.jpegData(compressionQuality: 0.9) {
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dg_edited_\(UUID().uuidString).jpg")
            try? data.write(to: url)
            AnalyticsManager.shared.logEvent("editor_saved", parameters: [
                "type": "photo",
                "caption_present": !caption.isEmpty
            ])
            onExport(url)
        }
    }
}

private struct CanvasOverlay: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.isOpaque = false
        canvasView.backgroundColor = .clear
        canvasView.drawingPolicy = .anyInput
        canvasView.tool = PKInkingTool(.pen, color: .white, width: 8)
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}
}
