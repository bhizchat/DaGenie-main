import SwiftUI
import AVKit
import Photos

struct MediaPlayerView: View {
    let media: CapturedMedia
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            switch media.type {
            case .photo:
                PhotoContentView(url: media.localURL)
                    .ignoresSafeArea()
            case .video:
                VideoOverlayPreview(url: media.localURL)
                    .ignoresSafeArea()
            }

            VStack {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                            .padding()
                    }
                }
                Spacer()
            }
        }
        .background(Color.black)
    }
}

private struct VideoLoopPlayer: View {
    let url: URL
    @State private var player: AVPlayer = AVPlayer()

    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                player.replaceCurrentItem(with: AVPlayerItem(url: url))
                player.actionAtItemEnd = .none
                NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { _ in
                    player.seek(to: .zero)
                    player.play()
                }
                player.play()
            }
            .onDisappear {
                player.pause()
                NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: player.currentItem)
            }
    }
}

private struct PhotoContentView: View {
    let url: URL
    @State private var image: UIImage? = nil
    @State private var isLoading = false

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if url.scheme?.hasPrefix("http") == true {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView().tint(.white)
                    case .success(let img):
                        img.resizable().scaledToFit()
                    case .failure:
                        Color.black
                    @unknown default:
                        Color.black
                    }
                }
            } else {
                ZStack {
                    Color.black
                    ProgressView().tint(.white)
                }
            }
        }
        .onAppear {
            guard image == nil else { return }
            if url.scheme?.hasPrefix("http") == true {
                // handled by AsyncImage
                return
            }
            // Load local file off the main thread
            isLoading = true
            DispatchQueue.global(qos: .userInitiated).async {
                defer { isLoading = false }
                if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                    DispatchQueue.main.async { self.image = img }
                }
            }
        }
    }
}

// MARK: - Video overlay preview with text button
struct VideoOverlayPreview: View {
    let url: URL
    @State private var overlayState = OverlayState()
    @State private var canvasRect: CGRect = .zero
    @FocusState private var activeTextOverlayID: UUID?
    @State private var player: AVQueuePlayer = AVQueuePlayer()
    @State private var playerLooper: AVPlayerLooper? = nil
    @State private var renderSize: CGSize = .zero
    @State private var toast: ToastMessage? = nil
    @State private var pendingTextInsert: Bool = false

    var body: some View {
        ZStack {
            GeometryReader { g in
                ZStack {
                    // Use an AVPlayerLayer-backed view with aspect-fill so preview fills the screen
                    FillVideoPlayer(player: player)
                        .onAppear {
                            // Seamless loop using AVPlayerLooper
                            let item = AVPlayerItem(url: url)
                            player.removeAllItems()
                            playerLooper = AVPlayerLooper(player: player, templateItem: item)
                            player.play()
                        }
                        .onDisappear { player.pause(); playerLooper = nil }
                    Color.clear.preference(key: VideoCanvasRectKey.self,
                                            value: aspectFitRect(contentSize: renderSize == .zero ? g.size : renderSize,
                                                                 in: g.frame(in: .local)))

                    if canvasRect.width > 1 && canvasRect.height > 1 {
                        ForEach($overlayState.texts) { $item in
                            TextOverlayView(model: $item,
                                            isEditing: isEditing(item.id),
                                            onBeginEdit: {
                                                overlayState.mode = .textEdit(id: item.id)
                                                player.pause()
                                                DispatchQueue.main.async { activeTextOverlayID = item.id }
                                            },
                                            onEndEdit: {
                                                overlayState.mode = .none
                                                player.play()
                                                // Remove if left empty after editing
                                                let trimmed = overlayState.texts.first(where: { $0.id == item.id })?.string.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                                                if trimmed.isEmpty {
                                                    overlayState.texts.removeAll { $0.id == item.id }
                                                }
                                                DispatchQueue.main.async { activeTextOverlayID = nil }
                                            },
                                            activeTextId: $activeTextOverlayID,
                                            canvasSize: canvasRect.size)
                                .frame(width: canvasRect.width, height: canvasRect.height, alignment: .topLeading)
                                .position(x: canvasRect.midX, y: canvasRect.midY)
                                .coordinateSpace(name: "canvas")
                        }
                    }
                }
            }

            // Right-side tools (Text) — hidden for now
            if false {
                VStack(spacing: 18) {
                    Button(action: addText) {
                        Image("icon_preview_text")
                            .renderingMode(.original)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .padding(6)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.trailing, 12)
                .padding(.top, 76)
            }

            // Bottom bar with Download + Share (hidden during text editing)
            if !isEditingActive() {
                VStack {
                    Spacer()
                    HStack {
                        Button(action: saveToPhotos) {
                            ZStack {
                                Circle().fill(Color(red: 242/255, green: 109/255, blue: 100/255)).frame(width: 56, height: 56)
                                Image("icon_preview_download").renderingMode(.original).resizable().scaledToFit().frame(width: 32, height: 32)
                            }
                        }
                        Spacer()
                        Button(action: share) {
                            HStack(spacing: 10) {
                                Text("Share").font(.vt323(26)).foregroundColor(.white)
                                Image("icon_preview_share").renderingMode(.original).resizable().scaledToFit().frame(width: 28, height: 28)
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(Color(red: 242/255, green: 109/255, blue: 100/255))
                            .cornerRadius(100)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .background(Color.black.opacity(1.0).ignoresSafeArea(edges: .bottom))
                }
            }
        }
        .toast(message: $toast)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear { renderSize = naturalRenderSize(for: url) }
        .onPreferenceChange(VideoCanvasRectKey.self) { rect in
            if !rectApproximatelyEqual(canvasRect, rect, epsilon: 0.5) {
                canvasRect = rect
                if canvasRect.width > 1 && canvasRect.height > 1 && pendingTextInsert {
                    pendingTextInsert = false
                    createAndFocusCenteredText()
                }
                // Ensure any pre-existing overlays are centered if their positions were invalid
                recenterTextsIfNeeded()
            }
        }
    }

    private func naturalRenderSize(for url: URL) -> CGSize {
        let asset = AVAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else { return .zero }
        let t = track.preferredTransform
        let size = track.naturalSize.applying(t)
        return CGSize(width: abs(size.width), height: abs(size.height))
    }

    private func isEditing(_ id: UUID) -> Bool { if case let .textEdit(editId) = overlayState.mode { return editId == id } ; return false }
    private func isEditingActive() -> Bool { if case .textEdit = overlayState.mode { return true } ; return false }

    private func addText() {
        guard canvasRect.width > 1 && canvasRect.height > 1 else { pendingTextInsert = true; return }
        createAndFocusCenteredText()
    }

    private func createAndFocusCenteredText() {
        let center = CGPoint(x: canvasRect.width/2, y: canvasRect.height/2)
        var item = TextOverlay(string: "", position: center, zIndex: (overlayState.texts.map { $0.zIndex }.max() ?? 0) + 1)
        item.color = RGBAColor(overlayState.lastTextColor)
        overlayState.texts.append(item)
        overlayState.mode = .textEdit(id: item.id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { activeTextOverlayID = item.id }
    }

    private func recenterTextsIfNeeded() {
        guard canvasRect.width > 1 && canvasRect.height > 1 else { return }
        var changed = false
        for idx in overlayState.texts.indices {
            let p = overlayState.texts[idx].position
            if !p.x.isFinite || !p.y.isFinite || (abs(p.x) < 0.001 && abs(p.y) < 0.001) {
                overlayState.texts[idx].position = CGPoint(x: canvasRect.width/2, y: canvasRect.height/2)
                changed = true
            }
        }
        if changed { print("[VideoOverlayPreview] recentered text overlays with invalid positions") }
    }

    private func saveToPhotos() {
        VideoOverlayExporter.export(assetURL: url, texts: overlayState.texts, caption: overlayState.caption, canvasRect: canvasRect) { out in
            guard let out = out else { return }
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                guard status == .authorized || status == .limited else { return }
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: out)
                }, completionHandler: { _, _ in })
            }
        }
    }

    private func share() {
        VideoOverlayExporter.export(assetURL: url, texts: overlayState.texts, caption: overlayState.caption, canvasRect: canvasRect) { out in
            guard let out = out else { return }
            let av = UIActivityViewController(activityItems: [out], applicationActivities: nil)
            UIApplication.shared.topMostViewController()?.present(av, animated: true)
        }
    }
}

private struct VideoCanvasRectKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

// AVPlayerLayer-backed SwiftUI view that renders with aspect-fill (cropped/zoomed)
private struct FillVideoPlayer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerView { PlayerView() }
    func updateUIView(_ uiView: PlayerView, context: Context) { uiView.player = player }

    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        var player: AVPlayer? {
            get { playerLayer.player }
            set { playerLayer.player = newValue }
        }
        override init(frame: CGRect) {
            super.init(frame: frame)
            playerLayer.videoGravity = .resizeAspectFill
            backgroundColor = .black
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    }
}

private func rectApproximatelyEqual(_ a: CGRect, _ b: CGRect, epsilon: CGFloat) -> Bool {
    abs(a.minX - b.minX) <= epsilon &&
    abs(a.minY - b.minY) <= epsilon &&
    abs(a.width - b.width) <= epsilon &&
    abs(a.height - b.height) <= epsilon
}
