import SwiftUI
import AVKit
import Photos
import StoreKit

struct ReelPreviewView: View {
    let url: URL
    @State private var player: AVPlayer = AVPlayer()
    @State private var isPlaying: Bool = true
    @Environment(\.dismiss) private var dismiss
    @State private var toast: ToastMessage? = nil
    @State private var showPaywall: Bool = false
    @StateObject private var sub = SubscriptionManager.shared
    @State private var pendingAction: PendingAction? = nil

    enum PendingAction { case save, share }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Reuse the overlay-capable preview so the T button appears
            VideoOverlayPreview(url: url)
                .ignoresSafeArea()

            // Top-left close
            VStack {
                HStack {
                    Button(action: { VideoPreviewPresenter.shared.dismiss() }) {
                        Image("icon_preview_close")
                            .renderingMode(.original)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .padding(10)
                    }
                    Spacer()
                }
                .padding(.top, 16)
                .padding(.leading, 12)
                Spacer()
            }
        }
        .toast(message: $toast)
        .sheet(isPresented: $showPaywall, onDismiss: {
            print("[ReelPreviewView] paywall dismissed; isSubscribed=\(sub.isSubscribed)")
            if !sub.isSubscribed {
                print("[ReelPreviewView] setting requiresSubscriptionForGeneration=true after dismiss")
                Task { await SubscriptionGate.setRequireForGenerationTrue() }
            }
        }) {
            PaywallView()
                .onAppear { print("[ReelPreviewView] presenting PaywallView (pending=\(String(describing: pendingAction)))") }
        }
        .onChange(of: sub.isSubscribed) { ok in
            guard ok, showPaywall else { return }
            switch pendingAction {
            case .save: saveToPhotos()
            case .share: share()
            case .none: break
            }
            pendingAction = nil
            showPaywall = false
        }
    }

    private func togglePlay() {
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
    }

    private func saveToPhotos() {
        guard sub.isSubscribed else { pendingAction = .save; showPaywall = true; print("[ReelPreviewView] gating save → showPaywall=true"); return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    toast = ToastMessage(text: "Permission needed to save. Enable Photos access in Settings.", style: .error)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { toast = nil }
                }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }, completionHandler: { success, error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("[ReelPreviewView] saveToPhotos error: \(error)")
                        toast = ToastMessage(text: "Couldn't save to Photos. Try again.", style: .error)
                    } else {
                        print("[ReelPreviewView] saved to Photos")
                        toast = ToastMessage(text: "Saved to Photos", style: .success)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { toast = nil }
                }
            })
        }
    }

    private func share() {
        guard sub.isSubscribed else { pendingAction = .share; showPaywall = true; print("[ReelPreviewView] gating share → showPaywall=true"); return }
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        UIApplication.shared.topMostViewController()?.present(av, animated: true)
    }

    private var brandRed: Color { Color(red: 242/255, green: 109/255, blue: 100/255) }
}

// MARK: - AVPlayerLayer-backed view to respect orientation properly
fileprivate final class PlayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }
    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.videoGravity = .resizeAspect
        backgroundColor = .black
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

fileprivate struct PlayerContainer: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> PlayerView { PlayerView() }
    func updateUIView(_ uiView: PlayerView, context: Context) { uiView.player = player }
}


