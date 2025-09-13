import SwiftUI
import AVFoundation

struct VideoEditorView: View {
    let url: URL
    let onCancel: () -> Void
    let onExport: (URL) -> Void

    @State private var overlayState = OverlayState()
    @State private var canvasRect: CGRect = .zero
    @FocusState private var activeTextOverlayID: UUID?
    @State private var player: AVPlayer = AVPlayer()
    @State private var renderSize: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { g in
                ZStack {
                    VideoPlayerLayerRepresentable(player: player)
                        .clipped()
                        .onAppear { setupPlayerIfNeeded() }

                    // Compute canvasRect using the video's render size fit into available space
                    Color.clear.preference(key: VideoCanvasRectKey.self, value: aspectFitRect(contentSize: renderSize == .zero ? g.size : renderSize, in: g.frame(in: .local)))

                    if canvasRect.width > 1 && canvasRect.height > 1 {
                        // Text overlays in canvas coordinate space
                        ForEach($overlayState.texts) { $item in
                            TextOverlayView(model: $item,
                                            isEditing: isEditing(item.id),
                                            onBeginEdit: {
                                                overlayState.mode = .textEdit(id: item.id)
                                                DispatchQueue.main.async { activeTextOverlayID = item.id }
                                            },
                                            onEndEdit: {
                                                overlayState.mode = .none
                                                DispatchQueue.main.async { activeTextOverlayID = nil }
                                            },
                                            activeTextId: $activeTextOverlayID,
                                            canvasSize: canvasRect.size)
                                .frame(width: canvasRect.width, height: canvasRect.height, alignment: .topLeading)
                                .position(x: canvasRect.minX, y: canvasRect.minY)
                                .coordinateSpace(name: "canvas")
                        }
                    }
                }
            }

            VStack {
                HStack {
                    Button(action: onCancel) {
                        Image("icon_preview_close").resizable().scaledToFit().frame(width: 28, height: 28).padding(10)
                    }
                    Spacer()
                    HStack(spacing: 16) {
                        Button(action: addText) {
                            Image("icon_preview_text").resizable().scaledToFit().frame(width: 28, height: 28).padding(6)
                        }
                    }
                }
                .padding(.top, 16).padding(.horizontal, 12)
                Spacer()
                HStack {
                    Button(action: exportVideo) {
                        HStack(spacing: 10) {
                            Text("Save").font(.vt323(24)).foregroundColor(.white)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Color(red: 242/255, green: 109/255, blue: 100/255))
                        .cornerRadius(100)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .onPreferenceChange(VideoCanvasRectKey.self) { rect in
            if !rectApproximatelyEqual(canvasRect, rect, epsilon: 0.5) { canvasRect = rect }
        }
    }

    private func setupPlayerIfNeeded() {
        guard player.currentItem == nil else { return }
        let asset = AVAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: item)
        player.play()
        renderSize = naturalRenderSize(for: asset)
    }

    private func naturalRenderSize(for asset: AVAsset) -> CGSize {
        guard let track = asset.tracks(withMediaType: .video).first else { return .zero }
        let t = track.preferredTransform
        let size = track.naturalSize.applying(t)
        return CGSize(width: abs(size.width), height: abs(size.height))
    }

    private func isEditing(_ id: UUID) -> Bool { if case let .textEdit(editId) = overlayState.mode { return editId == id } ; return false }

    private func addText() {
        guard canvasRect.width > 1 && canvasRect.height > 1 else { return }
        let center = CGPoint(x: canvasRect.width/2, y: canvasRect.height/2)
        var item = TextOverlay(string: "", position: center, zIndex: (overlayState.texts.map { $0.zIndex }.max() ?? 0) + 1)
        item.color = RGBAColor(overlayState.lastTextColor)
        overlayState.texts.append(item)
        overlayState.mode = .textEdit(id: item.id)
        DispatchQueue.main.async { activeTextOverlayID = item.id }
    }

    private func exportVideo() {
        VideoOverlayExporter.export(assetURL: url,
                                    texts: overlayState.texts,
                                    caption: overlayState.caption,
                                    canvasRect: canvasRect) { outURL in
            if let outURL = outURL { onExport(outURL) }
        }
    }
}

private func rectApproximatelyEqual(_ a: CGRect, _ b: CGRect, epsilon: CGFloat) -> Bool {
    abs(a.minX - b.minX) <= epsilon &&
    abs(a.minY - b.minY) <= epsilon &&
    abs(a.width - b.width) <= epsilon &&
    abs(a.height - b.height) <= epsilon
}

private struct VideoCanvasRectKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

private struct VideoPlayerLayerRepresentable: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerView { let v = PlayerView(); v.player = player; return v }
    func updateUIView(_ uiView: PlayerView, context: Context) { uiView.player = player }

    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        var player: AVPlayer? { get { playerLayer.player } set { playerLayer.player = newValue; playerLayer.videoGravity = .resizeAspect } }
    }
}


