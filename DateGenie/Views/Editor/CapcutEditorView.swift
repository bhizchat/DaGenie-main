import SwiftUI
import AVFoundation
import FirebaseAuth

struct CapcutEditorView: View {
    let url: URL

    @StateObject private var state: EditorState
    @State private var canvasRect: CGRect = .zero
    @State private var showTextPanel: Bool = false
    @State private var showCaptionPanel: Bool = false
    @State private var showAspectSheet: Bool = false
    @State private var showEditBar: Bool = false

    init(url: URL) {
        self.url = url
        _state = StateObject(wrappedValue: EditorState(asset: AVURLAsset(url: url)))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar (close · time · play · Export)
                HStack {
                    Button(action: { UIApplication.shared.topMostViewController()?.dismiss(animated: true) }) {
                        Image("icon_preview_close")
                            .renderingMode(.original)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 130)
                            .padding(10)
                    }
                    Spacer()
                    HStack(spacing: 16) {
                        Button(action: export) {
                            Text("Export")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color(red: 247/255, green: 180/255, blue: 81/255))
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, max(0, safeTopInset() - 36))
                .offset(y: -50) // raise X/Export vertically by ~50pt

                // Track canvas
                EditorTrackArea(player: state.player)
                    .frame(height: 280)
                    .padding(.top, -50)   // move canvas up by 50pt
                    .padding(.bottom, 50) // compensate so overall layout height stays the same
                    .padding(.horizontal, 0)

                // Middle controls (play + time) centered in free space between canvas and bottom toolbar
                Spacer()
                    .overlay(alignment: .center) {
                        VStack(spacing: 40) {
                            Button(action: { state.isPlaying ? state.pause() : state.play() }) {
                                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 28, weight: .bold))
                            }
                            HStack {
                                Text(timeLabel(state.currentTime, duration: state.duration))
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 24)
                            .offset(y: -50) // lift timecode to sit just under play button
                        }
                        .offset(y: -30) // move play button/time group up ~30pt
                    }

            }
            // Expand to full height so the overlay anchors to screen bottom
            .frame(maxHeight: .infinity, alignment: .top)
            // Bottom overlay: timeline above toolbar
            .overlay(alignment: .bottom) {
                VStack(spacing: 0) {
                    TimelineContainer(state: state)
                        .frame(height: 72 + 8 + 32 + 80)
                    if showEditBar {
                        EditToolsBar(state: state, onClose: { withAnimation(.easeInOut(duration: 0.2)) { showEditBar = false } })
                            .transition(AnyTransition.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        EditorBottomToolbar(
                            onEdit: { withAnimation(.easeInOut(duration: 0.2)) { showEditBar = true } },
                            onAudio: {},
                            onText: { showTextPanel = true },
                            onOverlay: {},
                            onAspect: { showAspectSheet = true },
                            onEffects: {}
                        )
                            .transition(AnyTransition.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
        .onAppear {
            print("[CapcutEditorView] open with url=\(url.lastPathComponent)")
            AnalyticsManager.shared.logEvent("capcut_editor_opened", parameters: [
                "url_last_path": url.lastPathComponent
            ])
            state.preparePlayer()
        }
        .sheet(isPresented: $showTextPanel) { TextToolPanel(state: state, canvasRect: canvasRect) }
        .sheet(isPresented: $showCaptionPanel) { CaptionToolPanel(state: state, canvasRect: canvasRect) }
        .actionSheet(isPresented: $showAspectSheet) {
            ActionSheet(title: Text("Aspect Ratio"), buttons: [
                .default(Text("9:16")) { state.renderConfig.aspect = .nineBySixteen },
                .default(Text("4:5")) { state.renderConfig.aspect = .fourByFive },
                .default(Text("1:1")) { state.renderConfig.aspect = .oneByOne },
                .cancel()
            ])
        }
    }

    private func timeLabel(_ t: CMTime, duration: CMTime) -> String {
        func fmt(_ time: CMTime) -> String {
            guard time.isNumeric else { return "00:00" }
            let total = CMTimeGetSeconds(duration)
            let current = CMTimeGetSeconds(time)
            let clamped = max(0.0, min(current, max(0.0, total)))
            let secs = Int(clamped)
            let m = secs / 60
            let s = secs % 60
            return String(format: "%02d:%02d", m, s)
        }
        return fmt(t) + " / " + fmt(duration)
    }

    private func safeTopInset() -> CGFloat {
        guard let w = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
            .first else { return 0 }
        return w.safeAreaInsets.top
    }

    private func export() {
        VideoOverlayExporter.export(assetURL: url,
                                    timedTexts: state.textOverlays,
                                    timedCaptions: state.captions,
                                    renderConfig: state.renderConfig,
                                    audioTracks: state.audioTracks,
                                    canvasRect: canvasRect) { out in
            guard let out = out else { return }
            // Save thumbnail + project persistence if available
            if let img = ThumbnailGenerator.firstFrame(for: out),
               let uid = Auth.auth().currentUser?.uid {
                Task {
                    if let project = await ProjectsRepository.shared.create(userId: uid, name: "Project \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none))") {
                        await ProjectsRepository.shared.attachVideo(userId: uid, projectId: project.id, localURL: out)
                        await ProjectsRepository.shared.uploadThumbnail(userId: uid, projectId: project.id, image: img)
                    }
                }
            }
            let av = UIActivityViewController(activityItems: [out], applicationActivities: nil)
            UIApplication.shared.topMostViewController()?.present(av, animated: true)
        }
    }
}

// EditorTrackArea is defined in Views/Editor/Tracks/EditorTrackArea.swift

// MARK: - EditorState (minimal for playback)
final class EditorState: ObservableObject {
    let asset: AVAsset
    let player: AVPlayer = AVPlayer()
    private var composition: AVMutableComposition = AVMutableComposition()

    @Published var duration: CMTime = .zero
    @Published var currentTime: CMTime = .zero
    @Published var isPlaying: Bool = false
    @Published var renderConfig: VideoRenderConfig = VideoRenderConfig()
    @Published var textOverlays: [TimedTextOverlay] = []
    @Published var captions: [TimedCaption] = []
    @Published var audioTracks: [AudioTrack] = []
    // Multi-clip timeline
    @Published var clips: [Clip] = []
    // Legacy single-filmstrip fields are unused by the new multi-clip UI but kept for compatibility
    @Published var thumbnails: [UIImage] = []
    @Published var thumbnailTimes: [CMTime] = []
    @Published var pixelsPerSecond: CGFloat = 60
    @Published var isScrubbing: Bool = false
    @Published var selectedClipId: UUID? = nil

    private var timeObserver: Any?

    init(asset: AVAsset) {
        self.asset = asset
    }

    func preparePlayer() {
        // Seed the timeline with the initial asset as the first clip
        let first = Clip(url: (asset as? AVURLAsset)?.url ?? URL(fileURLWithPath: "/dev/null"), asset: asset, duration: asset.duration)
        clips = [first]
        Task {
            await rebuildComposition()
            await generateThumbnails(forClipAt: 0)
        }
        installTimeObserver()
        pause()
    }

    func play() {
        guard !isPlaying else { return }
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func seek(to time: CMTime, precise: Bool = false) {
        if precise {
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        } else {
            player.seek(to: time)
        }
    }

    var totalDuration: CMTime {
        clips.reduce(.zero) { $0 + $1.duration }
    }

    // Append a new clip and rebuild the composition + thumbnails
    @MainActor
    func appendClip(url: URL) async {
        let asset = AVURLAsset(url: url)
        let clip = Clip(url: url, asset: asset, duration: asset.duration)
        clips.append(clip)
        await rebuildComposition()
        let index = clips.count - 1
        await generateThumbnails(forClipAt: index)
        // Generate waveform and detect original audio availability
        let hasAudio = asset.tracks(withMediaType: .audio).first != nil
        if clips.indices.contains(index) {
            clips[index].hasOriginalAudio = hasAudio
        }
        if hasAudio {
            let samples = await WaveformGenerator.loadOrGenerate(for: asset)
            await MainActor.run { if self.clips.indices.contains(index) { self.clips[index].waveformSamples = samples } }
        }
    }

    // Build a single AVMutableComposition that concatenates all clips
    @MainActor
    private func rebuildComposition() async {
        let comp = AVMutableComposition()
        guard !clips.isEmpty else {
            player.replaceCurrentItem(with: nil)
            duration = .zero
            composition = comp
            return
        }

        let videoTrack = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let audioTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

        var cursor: CMTime = .zero
        for clip in clips {
            if let v = clip.asset.tracks(withMediaType: .video).first {
                try? videoTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: clip.duration), of: v, at: cursor)
            }
            if clip.hasOriginalAudio, let a = clip.asset.tracks(withMediaType: .audio).first {
                try? audioTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: clip.duration), of: a, at: cursor)
            }
            cursor = cursor + clip.duration
        }

        composition = comp
        let item = AVPlayerItem(asset: composition)
        player.replaceCurrentItem(with: item)
        duration = totalDuration
    }

    // Generate filmstrip thumbnails for a single clip
    private func generateThumbnails(forClipAt index: Int) async {
        guard clips.indices.contains(index) else { return }
        let clip = clips[index]
        let total = CMTimeGetSeconds(clip.duration)
        guard total.isFinite && total > 0 else { return }
        // Derive density from current pixelsPerSecond; cap for perf
        let density = max(4, min(80, Int(ceil(self.pixelsPerSecond / 12))))
        let count = max(4, min(18 * density / 5, Int(ceil(total)) * density))
        let times: [CMTime] = (0..<count).map { i in
            let t = Double(i) / Double(max(count-1, 1)) * total
            return CMTime(seconds: t, preferredTimescale: 600)
        }
        let gen = AVAssetImageGenerator(asset: clip.asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 240, height: 240)

        DispatchQueue.global(qos: .userInitiated).async {
            var images: [UIImage] = []
            for t in times {
                if let cg = try? gen.copyCGImage(at: t, actualTime: nil) {
                    images.append(UIImage(cgImage: cg))
                }
            }
            DispatchQueue.main.async {
                if self.clips.indices.contains(index) {
                    self.clips[index].thumbnails = images
                    self.clips[index].thumbnailTimes = times
                    self.clips[index].thumbnailPPS = self.pixelsPerSecond
                }
            }
        }
    }

    private func installTimeObserver() {
        removeTimeObserver()
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            self.currentTime = time
            // If zoom level changed significantly, regenerate thumbnails for fidelity
            for idx in self.clips.indices {
                let prev = self.clips[idx].thumbnailPPS
                if abs(prev - self.pixelsPerSecond) > 12 {
                    Task { await self.generateThumbnails(forClipAt: idx) }
                }
            }
        }
    }

    private func removeTimeObserver() {
        if let t = timeObserver {
            player.removeTimeObserver(t)
            timeObserver = nil
        }
    }

    deinit { removeTimeObserver() }

    // Legacy generateThumbnails retained by name; not used in multi-clip flow
    private func generateThumbnails() { }

    // Convenience for adding an external audio track (duration probed automatically)
    @MainActor
    func addAudio(url: URL, at start: CMTime, volume: Float = 1.0) async {
        let aAsset = AVURLAsset(url: url)
        let dur = aAsset.duration
        let track = AudioTrack(url: url, start: start, duration: dur, volume: volume)
        audioTracks.append(track)
    }
}

// MARK: - UI helpers
private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> PlayerView { PlayerView() }
    func updateUIView(_ uiView: PlayerView, context: Context) { uiView.player = player }

    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        var player: AVPlayer? {
            get { playerLayer.player }
            set { playerLayer.player = newValue; playerLayer.videoGravity = .resizeAspect }
        }
        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .black
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    }
}

private struct ToolbarButton: View {
    let title: String
    let system: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: system)
                    .foregroundColor(.white)
                Text(title)
                    .foregroundColor(.white)
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(6)
        }
    }
}


