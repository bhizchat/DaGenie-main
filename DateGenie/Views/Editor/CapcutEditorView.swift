import SwiftUI
import AVFoundation
import FirebaseAuth
import UniformTypeIdentifiers

struct CapcutEditorView: View {
    let url: URL

    @StateObject private var state: EditorState
    @State private var canvasRect: CGRect = .zero
    @State private var showTextPanel: Bool = false
    @State private var showCaptionPanel: Bool = false
    @State private var showAspectSheet: Bool = false
    @State private var showEditBar: Bool = false
    // Audio importer presentation state
    @State private var showAudioImporter: Bool = false
    // Phase 2B: typing dock state
    @State private var isTyping: Bool = false
    @FocusState private var dockFocused: Bool
    @StateObject private var keyboard = KeyboardObserver()
    

    init(url: URL) {
        self.url = url
        _state = StateObject(wrappedValue: EditorState(asset: AVURLAsset(url: url)))
    }

    // Helper to find selected text index
    private func selectedTextIndex() -> Int? {
        guard let id = state.selectedTextId else { return nil }
        return state.textOverlays.firstIndex(where: { $0.id == id })
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
                EditorTrackArea(state: state, canvasRect: $canvasRect)
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
                                Text(timeLabel(state.displayTime, duration: state.duration))
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
            // Bottom overlay: timeline above toolbar (keyboard should cover this)
            .overlay(alignment: .bottom) {
                VStack(spacing: 0) {
                    TimelineContainer(state: state,
                                      onAddAudio: { showAudioImporter = true },
                                      onAddText: {
                                          state.insertCenteredTextAndSelect(canvasRect: canvasRect)
                                          isTyping = true
                                          dockFocused = true
                                          withAnimation(.easeInOut(duration: 0.2)) { showEditBar = true }
                                      })
                        .frame(height: 72 + 8 + 32 + 80)
                    if showEditBar {
                        EditToolsBar(state: state, onClose: { withAnimation(.easeInOut(duration: 0.2)) { showEditBar = false } })
                            .transition(AnyTransition.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        EditorBottomToolbar(
                            onEdit: { withAnimation(.easeInOut(duration: 0.2)) { showEditBar = true } },
                            onAudio: { showAudioImporter = true },
                            onText: {
                                state.insertCenteredTextAndSelect(canvasRect: canvasRect)
                                isTyping = true
                                dockFocused = true
                            },
                            onOverlay: {},
                            onAspect: { showAspectSheet = true },
                            onEffects: {}
                        )
                            .transition(AnyTransition.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }
            // Typing dock rides above the keyboard without altering parent layout
            .overlay(alignment: .bottom) {
                Group {
                    if isTyping, let id = state.selectedTextId,
                       let binding = Binding(get: {
                           state.textOverlays.first(where: { $0.id == id })?.base.string ?? ""
                       }, set: { newValue in
                           if let i = state.textOverlays.firstIndex(where: { $0.id == id }) {
                               state.textOverlays[i].base.string = newValue
                           }
                       }) as Binding<String>? {
                        TypingDock(text: binding,
                                   onDone: { isTyping = false; dockFocused = false })
                            .focused($dockFocused)
                            .padding(.horizontal, 12)
                            .padding(.bottom, max(0, keyboard.height - 17))
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
        // Keep bottom UI static; allow keyboard to cover it
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear {
            print("[CapcutEditorView] open with url=\(url.lastPathComponent)")
            AnalyticsManager.shared.logEvent("capcut_editor_opened", parameters: [
                "url_last_path": url.lastPathComponent
            ])
            configureAudioSessionForPreview()
            state.preparePlayer()
        }
        // Tap handling from canvas for selected text: first tap dismisses keyboard, second tap clears selection
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CanvasTapOnSelectedText"))) { _ in
            if dockFocused || isTyping {
                // First tap: dismiss keyboard
                isTyping = false
                dockFocused = false
            } else {
                // Second tap: remove rectangle by clearing selection
                state.selectedTextId = nil
            }
        }
        // Open Edit toolbar if any selection event requests it (e.g., selecting a text strip)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenEditToolbarForSelection"))) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { showEditBar = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenTypingDockForSelectedText"))) { _ in
            isTyping = true
            dockFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CloseEditToolbarForDeselection"))) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { showEditBar = false }
        }
        // Device audio file importer
        .fileImporter(isPresented: $showAudioImporter,
                      allowedContentTypes: [.audio],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                Task { await importPickedAudio(urls: urls) }
            case .failure(let err):
                print("[AudioImport] error: \(err.localizedDescription)")
            }
        }
        // Auto-open/close Edit toolbar when selections change
        .onChange(of: state.selectedClipId) { newValue in
            if newValue != nil {
                withAnimation(.easeInOut(duration: 0.2)) { showEditBar = true }
            } else if state.selectedAudioId == nil && state.selectedTextId == nil {
                withAnimation(.easeInOut(duration: 0.2)) { showEditBar = false }
            }
        }
        .onChange(of: state.selectedAudioId) { newValue in
            if newValue != nil {
                withAnimation(.easeInOut(duration: 0.2)) { showEditBar = true }
            } else if state.selectedClipId == nil && state.selectedTextId == nil {
                withAnimation(.easeInOut(duration: 0.2)) { showEditBar = false }
            }
        }
        .onChange(of: state.selectedTextId) { newValue in
            if newValue != nil {
                withAnimation(.easeInOut(duration: 0.2)) { showEditBar = true }
            } else if state.selectedClipId == nil && state.selectedAudioId == nil {
                withAnimation(.easeInOut(duration: 0.2)) { showEditBar = false }
                isTyping = false
                dockFocused = false
            }
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
        .onDisappear {
            // Deactivate playback session if it was activated for preview
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }

    @MainActor
    private func importPickedAudio(urls: [URL]) async {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let start = state.displayTime
        for src in urls {
            var accessed = src.startAccessingSecurityScopedResource()
            defer { if accessed { src.stopAccessingSecurityScopedResource() } }
            let ext = src.pathExtension.isEmpty ? "m4a" : src.pathExtension
            let dest = docs.appendingPathComponent("audio_\(UUID().uuidString).\(ext)")
            do {
                if FileManager.default.fileExists(atPath: dest.path) { try? FileManager.default.removeItem(at: dest) }
                try FileManager.default.copyItem(at: src, to: dest)
                let displayLabel = preferredDisplayNameForAudio(at: src)
                await state.addAudio(url: dest, at: start, volume: 1.0, displayName: displayLabel)
                // Rebuild composition to include newly added audio for preview
                await state.rebuildCompositionForPreview()
            } catch {
                print("[AudioImport] copy failed: \(error.localizedDescription)")
            }
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

    // Preferred label for an audio source: AV metadata Title -> Files name -> basename
    private func preferredDisplayNameForAudio(at src: URL) -> String {
        let asset = AVURLAsset(url: src)
        if let titleItem = AVMetadataItem.metadataItems(
            from: asset.commonMetadata,
            withKey: AVMetadataKey.commonKeyTitle,
            keySpace: .common
        ).first,
           let title = titleItem.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return title
        }
        if let values = try? src.resourceValues(forKeys: [.localizedNameKey, .nameKey]),
           let name = (values.localizedName ?? values.name), !name.isEmpty {
            return (name as NSString).deletingPathExtension
        }
        return src.deletingPathExtension().lastPathComponent
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

    // MARK: - Audio session for preview
    private func configureAudioSessionForPreview() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
        } catch {
            print("[Editor] Audio session error: \(error)")
        }
    }
}

// EditorTrackArea is defined in Views/Editor/Tracks/EditorTrackArea.swift

// MARK: - EditorState (minimal for playback)
final class EditorState: ObservableObject {
    enum FollowMode: String { case off, keepVisible, center }
    let asset: AVAsset
    let player: AVPlayer = AVPlayer()
    private var composition: AVMutableComposition = AVMutableComposition()
    // Progressive thumbnail generation state
    private var imageGenerators: [UUID: AVAssetImageGenerator] = [:]
    private var thumbnailGenTokens: [UUID: UUID] = [:]

    @Published var duration: CMTime = .zero
    // Player-backed time (updated by display link in playback)
    @Published var playerTime: CMTime = .zero
    // Authoritative UI time (scrubTime if present, else playerTime)
    @Published var displayTime: CMTime = .zero
    // Live only during user scroll/drag/deceleration
    @Published var scrubTime: CMTime? = nil
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
    @Published var followMode: FollowMode = .off
    @Published var selectedClipId: UUID? = nil
    @Published var selectedAudioId: UUID? = nil
    // Text selection for on-canvas and timeline linking
    @Published var selectedTextId: UUID? = nil

    private var timeObserver: Any?
    private var displayLink: CADisplayLink?
    // Gate playback-driven UI updates until a precise seek commits
    @Published var waitingForSeekCommit: Bool = false
    private var lastScrubbedTime: CMTime? = nil
    private var lastScrubSeekAt: CFTimeInterval = 0
    // Prevent display-linked writes and follow during composition swaps
    private var rebuildingComposition: Bool = false
    // Track playback/follow state during interactive scrubs
    private var wasPlayingBeforeScrub: Bool = false
    private var followBeforeScrub: FollowMode? = nil
    // Live-scrub pacing via display link
    private var scrubDisplayLink: CADisplayLink?
    private var pendingScrubTime: CMTime?
    private var lastSeekedDuringScrub: CMTime = .invalid

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
        displayTime = .zero
    }

    func play() {
        guard !isPlaying else { return }
        player.play()
        isPlaying = true
        followMode = .keepVisible
        startDisplayLink()
    }

    func pause() {
        player.pause()
        isPlaying = false
        followMode = .off
        stopDisplayLink()
    }

    func seek(to time: CMTime, precise: Bool = false) {
        // Always update UI time immediately; player may settle asynchronously
        displayTime = time
        if precise {
            commitSeek(to: time, precise: true)
        } else {
            player.seek(to: time)
        }
    }

    // MARK: - Display-linked playhead updates
    @objc private func displayLinkFired(_ link: CADisplayLink) {
        // Only let playback drive UI time when not scrubbing
        guard isPlaying, scrubTime == nil, waitingForSeekCommit == false, rebuildingComposition == false else { return }
        let t = self.player.currentTime()
        self.playerTime = t
        self.displayTime = t
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let dl = CADisplayLink(target: self, selector: #selector(displayLinkFired(_:)))
        dl.preferredFramesPerSecond = 0 // adopt device refresh rate (60/120Hz)
        dl.add(to: .main, forMode: .common)
        displayLink = dl
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
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
    fileprivate func rebuildComposition() async {
        let comp = AVMutableComposition()
        // Preserve UI time and playback state; treat as a settle
        let keepTime = displayTime
        let wasPlaying = isPlaying
        rebuildingComposition = true
        stopDisplayLink()
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

        // Include user-added audio tracks for preview
        var mixParams: [AVMutableAudioMixInputParameters] = []
        for t in audioTracks {
            let aAsset = AVURLAsset(url: t.url)
            if let aSrc = aAsset.tracks(withMediaType: .audio).first,
               let aDst = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                // Trim-aware insertion from source time range
                let srcRange = CMTimeRange(start: t.trimStart, duration: t.trimmedDuration)
                // Clamp to available project space
                let maxDur = max(.zero, totalDuration - (t.start))
                let dur = min(srcRange.duration, maxDur)
                try? aDst.insertTimeRange(CMTimeRange(start: srcRange.start, duration: dur), of: aSrc, at: t.start)
                let p = AVMutableAudioMixInputParameters(track: aDst)
                p.setVolume(t.volume, at: .zero)
                mixParams.append(p)
            }
        }

        composition = comp
        let item = AVPlayerItem(asset: composition)
        if !mixParams.isEmpty {
            let mix = AVMutableAudioMix(); mix.inputParameters = mixParams
            item.audioMix = mix
        }
        player.replaceCurrentItem(with: item)
        duration = totalDuration
        // Seek new item back to kept time precisely, then resume
        let keepSeconds = max(0.0, min(CMTimeGetSeconds(keepTime), max(0.0, CMTimeGetSeconds(duration))))
        let target = CMTime(seconds: keepSeconds, preferredTimescale: 600)
        waitingForSeekCommit = true
        player.currentItem?.cancelPendingSeeks()
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            guard let self = self else { return }
            self.playerTime = target
            self.displayTime = target
            self.waitingForSeekCommit = false
            self.rebuildingComposition = false
            if wasPlaying { self.player.play() }
            self.startDisplayLink()
        }
    }

    // Generate filmstrip thumbnails for a single clip (progressive & cancellable)
    private func generateThumbnails(forClipAt index: Int) async {
        guard clips.indices.contains(index) else { return }
        let clip = clips[index]
        let total = CMTimeGetSeconds(clip.duration)
        guard total.isFinite && total > 0 else { return }
        // Determine number of tiles needed to span the clip's on-screen width at current zoom
        let tileWidth = max(24, self.pixelsPerSecond)
        let clipWidthPoints = CGFloat(total) * self.pixelsPerSecond
        let count = max(1, Int(ceil(clipWidthPoints / tileWidth)))
        let times: [CMTime] = (0..<count).map { i in
            let t = Double(i) / Double(max(count - 1, 1)) * total
            return CMTime(seconds: t, preferredTimescale: 600)
        }

        // Cancel any in-flight generation for this clip
        if let existing = imageGenerators[clip.id] {
            existing.cancelAllCGImageGeneration()
        }

        // Create a new generator configured for filmstrip speed (non-zero tolerances)
        let gen = AVAssetImageGenerator(asset: clip.asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 240, height: 240)
        let tol = CMTime(value: 1, timescale: 30) // ~33ms tolerance for speed
        gen.requestedTimeToleranceBefore = tol
        gen.requestedTimeToleranceAfter  = tol
        imageGenerators[clip.id] = gen
        let token = UUID()
        thumbnailGenTokens[clip.id] = token

        // Pre-size thumbnails so the UI renders full strip immediately
        await MainActor.run {
            if self.clips.indices.contains(index) {
                self.clips[index].thumbnails = Array(repeating: UIImage(), count: count)
                self.clips[index].thumbnailTimes = times
                self.clips[index].thumbnailPPS = self.pixelsPerSecond
            }
        }

        // Map requested time to index for stable placement
        var timeIndex: [Double: Int] = [:]
        for (i, t) in times.enumerated() { timeIndex[CMTimeGetSeconds(t)] = i }
        let nsTimes: [NSValue] = times.map { NSValue(time: $0) }

        gen.generateCGImagesAsynchronously(forTimes: nsTimes) { [weak self] requestedTime, cgImage, _, result, _ in
            guard let self = self else { return }
            // Ensure result is for the latest request
            guard self.thumbnailGenTokens[clip.id] == token else { return }
            guard result == .succeeded, let cg = cgImage else { return }
            let key = CMTimeGetSeconds(requestedTime)
            guard let i = timeIndex[key] else { return }
            let ui = UIImage(cgImage: cg)
            DispatchQueue.main.async {
                guard self.clips.indices.contains(index) else { return }
                if i < self.clips[index].thumbnails.count {
                    self.clips[index].thumbnails[i] = ui
                }
            }
        }
    }

    private func installTimeObserver() {
        removeTimeObserver()
        // Lower cadence observer; displayLink handles UI time smoothly
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            guard let self = self else { return }
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
    func addAudio(url: URL, at start: CMTime, volume: Float = 1.0, displayName: String? = nil) async {
        let aAsset = AVURLAsset(url: url)
        let dur = aAsset.duration
        // Load or generate waveform samples off-main; then update model on main
        let samples = await WaveformGenerator.loadOrGenerate(for: aAsset)
        var track = AudioTrack(url: url, start: start, duration: dur, volume: volume)
        track.waveformSamples = samples
        track.titleOverride = displayName
        audioTracks.append(track)
    }

    // Public wrapper to rebuild composition after mutations that affect preview
    @MainActor
    func rebuildCompositionForPreview() async {
        await rebuildComposition()
    }

    // Move audio start time with clamping to timeline
    @MainActor
    func moveAudio(id: UUID, toStartSeconds seconds: Double) {
        guard let idx = audioTracks.firstIndex(where: { $0.id == id }) else { return }
        let durS = max(0, CMTimeGetSeconds(audioTracks[idx].duration))
        let totalS = max(0, CMTimeGetSeconds(totalDuration))
        let clamped = min(max(0, seconds), max(0, totalS - durS))
        audioTracks[idx].start = CMTime(seconds: clamped, preferredTimescale: 600)
    }
}

// MARK: - Selection and clip timing helpers
extension EditorState {
    // MARK: - Scrub lifecycle and seek commit gating
    private func halfFrameTolerance() -> CMTime {
        if let track = player.currentItem?.asset.tracks(withMediaType: .video).first,
           track.nominalFrameRate > 0 {
            let fps = Double(track.nominalFrameRate)
            return CMTime(seconds: 0.5 / fps, preferredTimescale: 600)
        }
        return CMTime(seconds: 1.0 / 120.0, preferredTimescale: 600)
    }

    private func startScrubDisplayLink() {
        guard scrubDisplayLink == nil else { return }
        let dl = CADisplayLink(target: self, selector: #selector(scrubDisplayLinkFired(_:)))
        dl.preferredFramesPerSecond = 0 // pace at device refresh (60/120Hz)
        dl.add(to: .main, forMode: .common)
        scrubDisplayLink = dl
    }

    private func stopScrubDisplayLink() {
        scrubDisplayLink?.invalidate()
        scrubDisplayLink = nil
    }

    @objc private func scrubDisplayLinkFired(_ link: CADisplayLink) {
        guard let t = pendingScrubTime else { return }
        let tol = halfFrameTolerance()
        if lastSeekedDuringScrub.isValid == false ||
            abs(CMTimeGetSeconds(t) - CMTimeGetSeconds(lastSeekedDuringScrub)) > CMTimeGetSeconds(tol) {
            player.currentItem?.cancelPendingSeeks()
            player.seek(to: t, toleranceBefore: tol, toleranceAfter: tol)
            lastSeekedDuringScrub = t
        }
    }

    func beginScrub() {
        if scrubTime == nil {
            wasPlayingBeforeScrub = isPlaying
            if wasPlayingBeforeScrub { pause() }
            scrubTime = displayTime
            followBeforeScrub = followMode
            followMode = .off
            // be more responsive during interaction
            player.automaticallyWaitsToMinimizeStalling = false
        }
        pendingScrubTime = scrubTime
        startScrubDisplayLink()
        waitingForSeekCommit = false
    }

    func scrub(to time: CMTime) {
        scrubTime = time
        displayTime = time
        // Defer actual seeks to the display link; just record the most recent intention.
        pendingScrubTime = time
        lastScrubbedTime = time
    }

    func endScrub() {
        stopScrubDisplayLink()
        lastSeekedDuringScrub = .invalid
        let target = pendingScrubTime ?? lastScrubbedTime
        guard let t = target else {
            scrubTime = nil
            waitingForSeekCommit = false
            if let prev = followBeforeScrub { followMode = prev }
            followBeforeScrub = nil
            player.automaticallyWaitsToMinimizeStalling = true
            return
        }
        // Keep scrubTime non-nil so display link stays gated until the precise seek lands
        commitSeek(to: t, precise: true)
        pendingScrubTime = nil
        lastScrubbedTime = nil
        // restore eager-behavior back to default after commit (also guarded in commit completion)
        player.automaticallyWaitsToMinimizeStalling = true
    }

    private func commitSeek(to time: CMTime, precise: Bool) {
        waitingForSeekCommit = true
        player.currentItem?.cancelPendingSeeks()
        let before: CMTime = precise ? .zero : .positiveInfinity
        let after: CMTime  = precise ? .zero : .positiveInfinity
        let requested = time
        func attempt(_ retriesLeft: Int) {
            player.seek(to: requested, toleranceBefore: before, toleranceAfter: after) { [weak self] _ in
                guard let self = self else { return }
                let landed = self.player.currentTime()
                let delta = abs(CMTimeGetSeconds(landed) - CMTimeGetSeconds(requested))
                let landedZero = CMTimeGetSeconds(landed) < 0.002
                let requestedNonZero = CMTimeGetSeconds(requested) > 0.25
                if (delta > 0.12 || (landedZero && requestedNonZero)) && retriesLeft > 0 {
                    // One more precise attempt; AVPlayer sometimes reports an early time momentarily
                    attempt(retriesLeft - 1)
                    return
                }
                self.playerTime = landed
                self.displayTime = requested // prefer requested to avoid minor rounding drift
                self.waitingForSeekCommit = false
                // Now allow playback-driven updates again
                self.scrubTime = nil
                // Restore follow mode and playback if it was active before scrub
                if let prev = self.followBeforeScrub { self.followMode = prev }
                self.followBeforeScrub = nil
                if self.wasPlayingBeforeScrub { self.play() }
                self.wasPlayingBeforeScrub = false
            }
        }
        attempt(1)
    }
    // MARK: - Text insertion (centered) used by toolbar and +Add text
    @MainActor
    func insertCenteredTextAndSelect(canvasRect: CGRect) {
        let center = CGPoint(x: canvasRect.width/2, y: canvasRect.height/2)
        var base = TextOverlay(string: "Enter text", position: center)
        base.color = RGBAColor(r: 1, g: 1, b: 1, a: 1)
        let item = TimedTextOverlay(base: base,
                                    start: displayTime,
                                    duration: CMTime(seconds: 2.0, preferredTimescale: 600))
        textOverlays.append(item)
        selectedTextId = item.id
    }
    /// Absolute start time (in seconds) of a clip in the concatenated timeline.
    /// Uses only previous clips' trimmed durations. The selected clip's trimStart
    /// does not shift its position on the concatenated timeline.
    func startSeconds(for clipId: UUID) -> Double? {
        var acc: Double = 0
        for c in clips {
            if c.id == clipId {
                return acc
            }
            acc += max(0, CMTimeGetSeconds(c.trimmedDuration))
        }
        return nil
    }

    var selectedClip: Clip? { clips.first { $0.id == selectedClipId } }

    /// Trim-aware absolute start seconds for the selected clip
    var selectedClipStartSeconds: Double? {
        guard let clip = selectedClip else { return nil }
        return startSeconds(for: clip.id)
    }

    /// Trim-aware duration seconds for the selected clip
    var selectedClipDurationSeconds: Double? {
        guard let clip = selectedClip else { return nil }
        return max(0, CMTimeGetSeconds(clip.trimmedDuration))
    }

    /// Trim-aware absolute end seconds for the selected clip
    var selectedClipEndSeconds: Double? {
        guard let s = selectedClipStartSeconds,
              let d = selectedClipDurationSeconds else { return nil }
        return s + d
    }

    // MARK: - Audio/Text selection helpers
    var selectedAudio: AudioTrack? { audioTracks.first { $0.id == selectedAudioId } }
    var selectedText: TimedTextOverlay? { textOverlays.first { $0.id == selectedTextId } }

    var selectedAudioStartSeconds: Double? {
        guard let a = selectedAudio else { return nil }
        return max(0, CMTimeGetSeconds(a.start + a.trimStart))
    }
    var selectedAudioEndSeconds: Double? {
        guard let a = selectedAudio else { return nil }
        return max(0, CMTimeGetSeconds(a.start + a.trimStart + a.trimmedDuration))
    }

    var selectedTextStartSeconds: Double? {
        guard let t = selectedText else { return nil }
        return max(0, CMTimeGetSeconds(t.effectiveStart))
    }
    var selectedTextEndSeconds: Double? {
        guard let t = selectedText else { return nil }
        return max(0, CMTimeGetSeconds(t.effectiveStart + t.trimmedDuration))
    }

    // MARK: - Trimming mutators
    @MainActor
    func trimAudio(id: UUID, leftDeltaSeconds: Double? = nil, rightDeltaSeconds: Double? = nil) async {
        guard let i = audioTracks.firstIndex(where: { $0.id == id }) else { return }
        var track = audioTracks[i]
        let durS = max(0, CMTimeGetSeconds(track.duration))
        var left = max(0, CMTimeGetSeconds(track.trimStart))
        var right = max(0, CMTimeGetSeconds(track.trimEnd ?? track.duration))
        if let dx = leftDeltaSeconds { left = min(max(0, left + dx), max(0, right - 0.03)) }
        if let dx = rightDeltaSeconds {
            right = max(0, min(durS, right + dx))
            right = max(right, left + 0.03)
        }
        track.trimStart = CMTime(seconds: left, preferredTimescale: 600)
        track.trimEnd   = CMTime(seconds: right, preferredTimescale: 600)
        audioTracks[i] = track
        await rebuildCompositionForPreview()
    }

    @MainActor
    func trimText(id: UUID, leftDeltaSeconds: Double? = nil, rightDeltaSeconds: Double? = nil) {
        guard let i = textOverlays.firstIndex(where: { $0.id == id }) else { return }
        var t = textOverlays[i]
        let durS = max(0, CMTimeGetSeconds(t.duration))
        var left = max(0, CMTimeGetSeconds(t.trimStart))
        var right = max(0, CMTimeGetSeconds(t.trimEnd ?? t.duration))
        if let dx = leftDeltaSeconds { left = min(max(0, left + dx), max(0, right - 0.03)) }
        if let dx = rightDeltaSeconds {
            right = max(0, min(durS, right + dx))
            right = max(right, left + 0.03)
        }
        t.trimStart = CMTime(seconds: left, preferredTimescale: 600)
        t.trimEnd   = CMTime(seconds: right, preferredTimescale: 600)
        textOverlays[i] = t
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

// MARK: - Typing Dock (Phase 2B)
private struct TypingDock: View {
    @Binding var text: String
    let onDone: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            TextField("Enter text", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.sentences)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(.vertical, 8)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done", action: onDone)
            }
        }
    }
}


