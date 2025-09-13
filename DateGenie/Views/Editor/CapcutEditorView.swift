import SwiftUI
import AVFoundation
import UIKit
import FirebaseAuth
import UniformTypeIdentifiers
import PhotosUI

struct CapcutEditorView: View {
    let url: URL
    let initialGenerating: Bool
    // Storyboard context
    let storyboardId: String?
    let currentSceneIndex: Int?
    let totalScenes: Int?

    @StateObject private var state: EditorState
    @State private var isGeneratingAd: Bool
    @State private var canvasRect: CGRect = .zero
    // Removed AddClipChoice sheet; plus button is now inert
    @State private var showTextPanel: Bool = false
    @State private var showCaptionPanel: Bool = false
    @State private var showAspectSheet: Bool = false // deprecated; kept until dock fully replaces
    @State private var showRatioDock: Bool = false
    @State private var showEditBar: Bool = false
    @State private var showOverlayBar: Bool = false
    @State private var showOverlayPicker: Bool = false
    @State private var overlayPickerPresenting: Bool = false
    @State private var overlayPickerItems: [PhotosPickerItem] = []
    // Logo picker state
    @State private var showLogoPicker: Bool = false
    @State private var logoPickerItems: [PhotosPickerItem] = []
    // Audio importer presentation state
    @State private var showAudioImporter: Bool = false
    // Phase 2B: typing dock state
    @State private var isTyping: Bool = false
    @FocusState private var dockFocused: Bool
    @StateObject private var keyboard = KeyboardObserver()
    @State private var activeProjectId: String? = nil
    @State private var lastAutosaveAt: CFTimeInterval = 0
    // Volume dock state
    @State private var showVolumeDock: Bool = false
    @State private var volumeSliderValue: Double = 50
    // Speed dock state
    @State private var showSpeedDock: Bool = false
    @State private var speedSliderUnit: Double = 0 // 0..1 mapped to 0.2..100
    @State private var preservePitchToggle: Bool = true
    // Logo error alert
    @State private var logoErrorMessage: String? = nil
    @State private var sceneGenMessage: String? = nil
    

    init(url: URL, initialGenerating: Bool = false, storyboardId: String? = nil, currentSceneIndex: Int? = nil, totalScenes: Int? = nil) {
        self.url = url
        self.initialGenerating = initialGenerating
        self.storyboardId = storyboardId
        self.currentSceneIndex = currentSceneIndex
        self.totalScenes = totalScenes
        let asset: AVAsset = {
            if url.isFileURL, url.path == "/dev/null" { return AVMutableComposition() }
            return AVURLAsset(url: url)
        }()
        _state = StateObject(wrappedValue: EditorState(asset: asset))
        _isGeneratingAd = State(initialValue: initialGenerating || (url.isFileURL && url.path == "/dev/null"))
    }

    // MARK: - Next Scene Generation
    private func generateNextScene(storyboardId: String, nextIndex: Int) async {
        await MainActor.run { sceneGenMessage = "Starting generation for scene \(nextIndex)…" }
        do {
            // For now, reuse placeholder empty composition and append a dummy clip.
            // TODO: wire to backend single-scene generation and replace url below with returned URL.
            try await Task.sleep(nanoseconds: 800_000_000) // brief simulated delay
            let dummyURL = URL(fileURLWithPath: "/dev/null")
            let clip = Clip(url: dummyURL, asset: AVMutableComposition(), duration: CMTime(seconds: 5, preferredTimescale: 600))
            await MainActor.run {
                state.clips.append(clip)
                sceneGenMessage = "Scene \(nextIndex) added."
            }
        } catch {
            await MainActor.run { sceneGenMessage = "Failed to generate scene \(nextIndex)." }
        }
    }

    // MARK: - Debounced autosave
    private func debouncedSaveProgress() async {
        let now = CACurrentMediaTime()
        if now - lastAutosaveAt < 0.7 { return }
        lastAutosaveAt = now
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let fallbackId = await MainActor.run { ProjectsRepository.shared.projects.first?.id }
        guard let pid = activeProjectId ?? fallbackId else { return }
        if let duration = await state.currentDurationSecondsOptional() {
            await ProjectsRepository.shared.updateProgress(userId: uid, projectId: pid, durationSec: duration, clipCount: await state.clipCount())
        }
    }

    // MARK: - Overlay media import
    @MainActor
    private func handlePickedOverlays() async {
        guard !overlayPickerItems.isEmpty else { return }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        for item in overlayPickerItems {
            do {
                if item.supportedContentTypes.contains(where: { $0.conforms(to: .image) }) {
                    if let data = try await item.loadTransferable(type: Data.self) {
                        let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                        let dest = docs.appendingPathComponent("overlay_\(UUID().uuidString).\(ext)")
                        try data.write(to: dest, options: .atomic)
                        // Center on current canvas
                        let center = CGPoint(x: canvasRect.width/2, y: canvasRect.height/2)
                        state.addPhotoOverlay(imageURL: dest, at: state.displayTime, position: center)
                    }
                } else if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
                    if let data = try await item.loadTransferable(type: Data.self) {
                        let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "mov"
                        let dest = docs.appendingPathComponent("overlay_\(UUID().uuidString).\(ext)")
                        try data.write(to: dest, options: .atomic)
                        let center = CGPoint(x: canvasRect.width/2, y: canvasRect.height/2)
                        state.addVideoOverlay(videoURL: dest, at: state.displayTime, position: center)
                    }
                }
            } catch {
                print("[OverlayPicker] error: \(error.localizedDescription)")
            }
        }
        overlayPickerItems.removeAll()
        showOverlayPicker = false
        // Ensure overlay lane becomes visible
        withAnimation(.easeInOut(duration: 0.2)) { }
        // Close the Overlay toolbar and open the Edit toolbar focused on the new selection
        withAnimation(.easeInOut(duration: 0.2)) {
            showOverlayBar = false
            showEditBar = true
        }
    }

    // Helper to find selected text index
    private func selectedTextIndex() -> Int? {
        guard let id = state.selectedTextId else { return nil }
        return state.textOverlays.firstIndex(where: { $0.id == id })
    }

    // MARK: - Logo insertion helpers
    @MainActor
    private func insertPersistedLogoOrPrompt() {
        // Use the persisted transparent PNG from onboarding if available
        if let url = UserRepository.shared.brandLogoLocalURL() {
            insertLogo(from: url)
            return
        }
        // No persisted logo yet; prompt the user to upload a transparent PNG
        logoErrorMessage = "No onboarding logo found. Please upload a transparent PNG with alpha."
        logoPickerItems = []
        showLogoPicker = true
    }

    @MainActor
    private func handlePickedLogoIfNeeded() async {
        guard let item = logoPickerItems.first else { return }
        defer { logoPickerItems.removeAll() }
        do {
            if let data = try await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                // Enforce transparency: reject if image lacks alpha channel
                if !imageHasAlpha(img) {
                    await MainActor.run { logoErrorMessage = "Selected image has no transparency. Please choose a PNG with alpha." }
                    return
                }
                // Persist the transparent PNG and insert
                Task { @MainActor in
                    if let url = await UserRepository.shared.saveBrandLogoPNG(img) {
                        insertLogo(from: url)
                    }
                }
            }
        } catch { print("[LogoPicker] error: \(error.localizedDescription)") }
        showLogoPicker = false
    }

    @MainActor
    private func insertLogo(from url: URL) {
        // Default position near bottom center; clamp within canvas if not measured yet
        let pos = CGPoint(x: max(0, canvasRect.width/2), y: max(0, canvasRect.height * 0.86))
        state.addPhotoOverlay(imageURL: url, at: state.displayTime, position: pos)
        withAnimation(.easeInOut(duration: 0.2)) { showOverlayBar = false; showEditBar = true }
    }

    // Small helper to render the logo preview if cached
    private func currentLogoPreview() -> UIImage? {
        if let url = UserRepository.shared.brandLogoLocalURL() {
            return UIImage(contentsOfFile: url.path)
        }
        return nil
    }

    private func imageHasAlpha(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return false }
        let a = cg.alphaInfo
        return !(a == .none || a == .noneSkipFirst || a == .noneSkipLast)
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
                .offset(y: -42) // lowered by an additional 10pt

                // Track canvas + generating overlay
                ZStack {
                    EditorTrackArea(state: state, canvasRect: $canvasRect)
                    if isGeneratingAd && state.clips.isEmpty {
                        VStack(spacing: 10) {
                            GIFView(dataAssetName: "kettle_thinking")
                                .frame(width: 160, height: 160)
                            HStack(spacing: 6) {
                                Text("Animating")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                ThreeDotsLoading()
                            }
                        }
                        .allowsHitTesting(false)
                        .transition(.opacity)
                    }
                }
                .frame(height: 280)
                .padding(.top, -75)
                .padding(.bottom, 75)
                .padding(.horizontal, 0)

                // Middle controls (play + time) centered in free space between canvas and bottom toolbar
                Spacer()
                    .overlay(alignment: .center) {
                        VStack(spacing: 40) {
                            Button(action: { state.isPlaying ? state.pause() : state.play() }) {
                                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 18, weight: .bold))
                            }
                            .offset(y: 10) // moved play button ~30pt lower
                            HStack {
                                Text(timeLabel(state.displayTime, duration: state.duration))
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 24)
                            .offset(y: -95) // lowered by ~15pt
                        }
                        .offset(y: -95) // move play button/time group up by ~35pt
                    }

            }
            // Expand to full height so the overlay anchors to screen bottom
            .frame(maxHeight: .infinity, alignment: .top)
            // Bottom overlay: timeline above toolbar (keyboard should cover this)
            .overlay(alignment: .bottom) {
                VStack(spacing: 0) {
                    ZStack(alignment: .leading) {
                        TimelineContainer(state: state,
                                          onAddAudio: { showAudioImporter = true },
                                          onAddText: {
                                              state.insertCenteredTextAndSelect(canvasRect: canvasRect)
                                              isTyping = true
                                              dockFocused = true
                                              withAnimation(.easeInOut(duration: 0.2)) { showEditBar = true }
                                          },
                                          onAddEnding: nil,
                                          onPlusTapped: { })
                        // Timeline no longer shows the generating pill; canvas overlay handles it
                    }
                    .frame(height: dynamicTimelineHeight())
                    // Inline Volume dock sits between timeline and toolbar to avoid intercepting timeline gestures
                    if showVolumeDock {
                        HStack(spacing: 12) {
                            Text("Volume")
                                .foregroundColor(.white)
                                .font(.system(size: 14, weight: .semibold))
                            Slider(value: $volumeSliderValue, in: 0...100, step: 1)
                                .tint(.white)
                                .onChange(of: volumeSliderValue) { newVal in
                                    let v = Float(max(0, min(100, newVal)) / 100.0)
                                    if let id = state.selectedAudioId,
                                       let idx = state.audioTracks.firstIndex(where: { $0.id == id }) {
                                        state.audioTracks[idx].volume = v
                                        Task { await state.rebuildCompositionForPreview() }
                                    } else if let id = state.selectedClipId,
                                              let idx = state.clips.firstIndex(where: { $0.id == id }) {
                                        state.clips[idx].originalAudioVolume = v
                                        Task { await state.rebuildCompositionForPreview() }
                                    }
                                }
                            Text("\(Int(volumeSliderValue))")
                                .foregroundColor(.white.opacity(0.9))
                                .font(.system(size: 13, weight: .medium))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 12)
                        .transition(AnyTransition.move(edge: .bottom).combined(with: .opacity))
                    }
                    // Inline Speed dock (Standard)
                    if showSpeedDock {
                        SpeedDockView(
                            speedUnit: $speedSliderUnit,
                            preservePitch: $preservePitchToggle,
                            onApply: {
                                let speed = unitToRate(speedSliderUnit)
                                if let id = state.selectedClipId, let i = state.clips.firstIndex(where: { $0.id == id }) {
                                    state.clips[i].speed = speed
                                    state.clips[i].preserveOriginalPitch = preservePitchToggle
                                } else if let id = state.selectedAudioId, let i = state.audioTracks.firstIndex(where: { $0.id == id }) {
                                    state.audioTracks[i].speed = speed
                                    state.audioTracks[i].preservePitch = preservePitchToggle
                                }
                                withAnimation(.easeInOut(duration: 0.2)) { showSpeedDock = false }
                                Task { await state.rebuildCompositionForPreview() }
                                DispatchQueue.main.async {
                                    NotificationCenter.default.post(name: Notification.Name("ResetTimelineDragGate"), object: nil)
                                }
                            }
                        )
                        .padding(.horizontal, 12)
                        .transition(AnyTransition.move(edge: .bottom).combined(with: .opacity))
                    }
                    if showEditBar {
                        EditToolsBar(state: state, onClose: {
                            withAnimation(.easeInOut(duration: 0.2)) { showEditBar = false; showVolumeDock = false }
                            // Ensure timeline scroll is re-enabled after closing tools
                            DispatchQueue.main.async {
                                NotificationCenter.default.post(name: Notification.Name("ResetTimelineDragGate"), object: nil)
                            }
                        }, onVolume: {
                            // Toggle the volume dock
                            if showVolumeDock {
                                withAnimation(.easeInOut(duration: 0.2)) { showVolumeDock = false }
                                DispatchQueue.main.async {
                                    NotificationCenter.default.post(name: Notification.Name("ResetTimelineDragGate"), object: nil)
                                }
                            } else {
                                if let id = state.selectedAudioId, let i = state.audioTracks.firstIndex(where: { $0.id == id }) {
                                    volumeSliderValue = Double(state.audioTracks[i].volume * 100.0)
                                } else if let id = state.selectedClipId, let i = state.clips.firstIndex(where: { $0.id == id }) {
                                    volumeSliderValue = Double(state.clips[i].originalAudioVolume * 100.0)
                                } else {
                                    volumeSliderValue = 50
                                }
                                withAnimation(.easeInOut(duration: 0.2)) { showVolumeDock = true; showSpeedDock = false }
                                DispatchQueue.main.async {
                                    NotificationCenter.default.post(name: Notification.Name("ResetTimelineDragGate"), object: nil)
                                }
                            }
                        }, onSpeed: {
                            // Toggle speed dock
                            if showSpeedDock {
                                withAnimation(.easeInOut(duration: 0.2)) { showSpeedDock = false }
                                DispatchQueue.main.async {
                                    NotificationCenter.default.post(name: Notification.Name("ResetTimelineDragGate"), object: nil)
                                }
                            } else {
                                // Seed values from selection
                                if let id = state.selectedClipId, let i = state.clips.firstIndex(where: { $0.id == id }) {
                                    speedSliderUnit = rateToUnit(state.clips[i].speed)
                                    preservePitchToggle = state.clips[i].preserveOriginalPitch
                                } else if let id = state.selectedAudioId, let i = state.audioTracks.firstIndex(where: { $0.id == id }) {
                                    speedSliderUnit = rateToUnit(state.audioTracks[i].speed)
                                    preservePitchToggle = state.audioTracks[i].preservePitch
                                } else {
                                    speedSliderUnit = rateToUnit(1.0)
                                    preservePitchToggle = true
                                }
                                withAnimation(.easeInOut(duration: 0.2)) { showSpeedDock = true; showVolumeDock = false }
                                DispatchQueue.main.async {
                                    NotificationCenter.default.post(name: Notification.Name("ResetTimelineDragGate"), object: nil)
                                }
                            }
                        })
                            .transition(AnyTransition.move(edge: .bottom).combined(with: .opacity))
                    } else if showOverlayBar {
                        OverlayToolsBar(state: state,
                                        onClose: { withAnimation(.easeInOut(duration: 0.2)) { showOverlayBar = false } },
                                        onAddMedia: {
                                            if !overlayPickerPresenting {
                                                overlayPickerPresenting = true
                                                showOverlayPicker = true
                                            }
                                        })
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
                            onAspect: {
                                // Toggle the new Ratio dock
                                withAnimation(.easeInOut(duration: 0.2)) { showRatioDock.toggle() }
                            }
                        )
                            .transition(AnyTransition.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }
            .alert("Generating next scene", isPresented: Binding(get: { sceneGenMessage != nil }, set: { _ in sceneGenMessage = nil })) {
                Button("OK", role: .cancel) { sceneGenMessage = nil }
            } message: {
                Text(sceneGenMessage ?? "")
            }
            // Volume dock overlay removed from global overlay to avoid intercepting timeline scroll
            // Typing dock rides above the keyboard without altering parent layout
            .overlay(alignment: .bottom) {
                Group {
                    if showRatioDock {
                        RatioDock(selected: Binding(get: { state.renderConfig.aspect }, set: { newVal in
                            state.renderConfig.aspect = newVal
                            Task { await state.rebuildCompositionForPreview() }
                        }), onDismiss: {
                            withAnimation(.easeInOut(duration: 0.2)) { showRatioDock = false }
                        })
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
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
        .alert("Logo Issue", isPresented: Binding(get: { logoErrorMessage != nil }, set: { v in if !v { logoErrorMessage = nil } })) {
            Button("OK", role: .cancel) { logoErrorMessage = nil }
        } message: {
            Text(logoErrorMessage ?? "")
        }
        .photosPicker(isPresented: $showOverlayPicker,
                       selection: $overlayPickerItems,
                       maxSelectionCount: 5,
                       matching: .any(of: [.images, .videos]))
        .onChange(of: overlayPickerItems) { _ in
            Task { await handlePickedOverlays() }
        }
        // Dedicated Logo picker
        .photosPicker(isPresented: $showLogoPicker,
                       selection: $logoPickerItems,
                       maxSelectionCount: 1,
                       matching: .images)
        .onChange(of: logoPickerItems) { _ in
            Task { await handlePickedLogoIfNeeded() }
        }
        .onChange(of: showOverlayPicker) { open in
            if !open { overlayPickerPresenting = false }
        }
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
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenTypingDockForSelectedText")).receive(on: RunLoop.main)) { _ in
            isTyping = true
            dockFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CloseEditToolbarForDeselection")).receive(on: RunLoop.main)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { showEditBar = false }
        }
        // New: AI ad generation lifecycle
        .onReceive(NotificationCenter.default.publisher(for: .AdGenBegin).receive(on: RunLoop.main)) { _ in
            isGeneratingAd = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .AdGenComplete).receive(on: RunLoop.main)) { note in
            if let u = (note.userInfo?["url"] as? URL) {
                Task { @MainActor in
                    await state.appendClip(url: u)
                    // Hide overlay once the first clip lands
                    isGeneratingAd = state.clips.isEmpty
                    if let uid = Auth.auth().currentUser?.uid,
                       let duration = await state.currentDurationSecondsOptional() {
                        let fallbackId = ProjectsRepository.shared.projects.first?.id
                        let chosenId = activeProjectId ?? fallbackId
                        if let pid = chosenId {
                            await ProjectsRepository.shared.updateProgress(userId: uid, projectId: pid, durationSec: duration, clipCount: await state.clipCount())
                        }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .ActiveProjectIdCreated)) { note in
            if let pid = note.object as? String { activeProjectId = pid }
        }
        // Debounced autosave of progress on timeline changes
        .onChange(of: state.clips) { _ in
            Task { await debouncedSaveProgress() }
        }
        // Removed AddClipChoice full-screen cover per request
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
                // Do not auto-open volume dock; only open via Volume button
            } else if state.selectedAudioId == nil && state.selectedTextId == nil {
                withAnimation(.easeInOut(duration: 0.2)) { showEditBar = false }
                withAnimation(.easeInOut(duration: 0.2)) { showVolumeDock = false }
            }
        }
        .onChange(of: state.selectedAudioId) { newValue in
            if newValue != nil {
                withAnimation(.easeInOut(duration: 0.2)) { showEditBar = true }
                // Do not auto-open volume dock; only open via Volume button
            } else if state.selectedClipId == nil && state.selectedTextId == nil {
                withAnimation(.easeInOut(duration: 0.2)) { showEditBar = false }
                withAnimation(.easeInOut(duration: 0.2)) { showVolumeDock = false }
            }
        }
        .onChange(of: state.selectedTextId) { newValue in
            if newValue != nil {
                withAnimation(.easeInOut(duration: 0.2)) { showEditBar = true }
                withAnimation(.easeInOut(duration: 0.2)) { showVolumeDock = false }
            } else if state.selectedClipId == nil && state.selectedAudioId == nil {
                withAnimation(.easeInOut(duration: 0.2)) { showEditBar = false }
                isTyping = false
                dockFocused = false
            }
        }
        // Auto-open/close Edit toolbar when media overlay selection changes
        .onChange(of: state.selectedMediaId) { newValue in
            if newValue != nil {
                withAnimation(.easeInOut(duration: 0.2)) { showEditBar = true }
            } else if state.selectedClipId == nil && state.selectedAudioId == nil && state.selectedTextId == nil {
                withAnimation(.easeInOut(duration: 0.2)) { showEditBar = false }
            }
        }
        .sheet(isPresented: $showTextPanel) { TextToolPanel(state: state, canvasRect: canvasRect) }
        .sheet(isPresented: $showCaptionPanel) { CaptionToolPanel(state: state, canvasRect: canvasRect) }
        // Legacy aspect sheet removed in favor of RatioDock
        .onDisappear {
            // Deactivate playback session if it was activated for preview
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }

    private func dynamicTimelineHeight() -> CGFloat {
        // Base height components: filmstrip + ruler + spacing + toolbar allowance
        let base: CGFloat = 72 + 8 + 32 + 120
        if let ar = state.renderConfig.aspect.value {
            // If portrait (w/h < 1), drop the timeline to reveal more canvas like CapCut
            return ar < 1.0 ? (base - 60) : base
        }
        return base
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
        // Export from the current preview composition (already retimed), with overlays
        let exportAsset = state.player.currentItem?.asset ?? state.asset
        let mix = state.player.currentItem?.audioMix
        VideoOverlayExporter.export(from: exportAsset,
                                    audioMix: mix,
                                    timedTexts: state.textOverlays,
                                    timedCaptions: state.captions,
                                    timedMedia: state.mediaOverlays,
                                    canvasRect: canvasRect) { out in
            guard let out = out else { return }
            // Save thumbnail + project persistence if available
            if let img = ThumbnailGenerator.firstFrame(for: out),
               let uid = Auth.auth().currentUser?.uid {
                Task {
                    if let project = await ProjectsRepository.shared.create(userId: uid, name: "Project \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none))") {
                        await ProjectsRepository.shared.attachVideo(userId: uid, projectId: project.id, localURL: out)
                        await ProjectsRepository.shared.uploadThumbnail(userId: uid, projectId: project.id, image: img)
                        // Persist storyboard linkage if present
                        if let sid = storyboardId, let cur = currentSceneIndex, let total = totalScenes {
                            await ProjectsRepository.shared.attachStoryboardContext(userId: uid, projectId: project.id, storyboardId: sid, currentSceneIndex: cur, totalScenes: total)
                        }
                    }
                }
            }
            // Present share sheet on main thread only
            DispatchQueue.main.async {
                let av = UIActivityViewController(activityItems: [out], applicationActivities: nil)
                UIApplication.shared.topMostViewController()?.present(av, animated: true)
            }
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

// MARK: - Aspect-fit helper for composition
private func transform(for track: AVAssetTrack, renderSize: CGSize, mode: ContentMode) -> CGAffineTransform {
    let preferred = track.preferredTransform
    let natural = track.naturalSize
    let orientedRect = CGRect(origin: .zero, size: natural).applying(preferred)
    var oriented = CGSize(width: abs(orientedRect.width), height: abs(orientedRect.height))
    var target = CGSize(width: max(1, renderSize.width), height: max(1, renderSize.height))
    if !oriented.width.isFinite || oriented.width <= 0 { oriented.width = 1 }
    if !oriented.height.isFinite || oriented.height <= 0 { oriented.height = 1 }
    if !target.width.isFinite || target.width <= 0 { target.width = 1 }
    if !target.height.isFinite || target.height <= 0 { target.height = 1 }
    let fitScale = min(target.width / oriented.width, target.height / oriented.height)
    let fillScale = max(target.width / oriented.width, target.height / oriented.height)
    let scale = (mode == .fit) ? fitScale : fillScale
    if !scale.isFinite || scale <= 0 {
        return preferred
    }
    let scaledW = oriented.width * scale
    let scaledH = oriented.height * scale
    let tx = (target.width - scaledW) / 2.0
    let ty = (target.height - scaledH) / 2.0
    var t = preferred
    t = t.concatenating(CGAffineTransform(scaleX: scale, y: scale))
    t = t.concatenating(CGAffineTransform(translationX: tx.isFinite ? tx : 0, y: ty.isFinite ? ty : 0))
    return t
}

// Simple three-dot loading indicator (white)
private struct ThreeDotsLoading: View {
    @State private var phase: Int = 0
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Color.white).frame(width: 5, height: 5).opacity(phase == 0 ? 1 : 0.3)
            Circle().fill(Color.white).frame(width: 5, height: 5).opacity(phase == 1 ? 1 : 0.3)
            Circle().fill(Color.white).frame(width: 5, height: 5).opacity(phase == 2 ? 1 : 0.3)
        }
        .onReceive(timer) { _ in phase = (phase + 1) % 3 }
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
    @Published var renderConfig: VideoRenderConfig = VideoRenderConfig(aspect: .fourByThree, mode: .fill)
    @Published var textOverlays: [TimedTextOverlay] = []
    @Published var mediaOverlays: [TimedMediaOverlay] = []
    @Published var captions: [TimedCaption] = []
    @Published var audioTracks: [AudioTrack] = []
    // (Reverted) Extracted audio lane not implemented yet; research pending
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
    @Published var selectedMediaId: UUID? = nil

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

    // MARK: - Frame quantization helpers
    /// Approximate frame duration in seconds based on the first video track's nominal frame rate.
    /// Falls back to 1/30s if the track does not expose a positive frame rate.
    func frameDurationSeconds() -> Double {
        if let track = player.currentItem?.asset.tracks(withMediaType: .video).first,
           track.nominalFrameRate > 0 {
            return 1.0 / Double(track.nominalFrameRate)
        }
        return 1.0 / 30.0
    }

    @MainActor
    func clipCount() async -> Int { clips.count }

    @MainActor
    func currentDurationSecondsOptional() async -> Double? {
        if let item = player.currentItem { return CMTimeGetSeconds(item.asset.duration) }
        return clips.first?.duration.seconds
    }

    /// Quantize a time value in seconds to the nearest frame based on `frameDurationSeconds`.
    func quantizeToFrame(_ seconds: Double) -> Double {
        let step = frameDurationSeconds()
        guard step > 0 else { return seconds }
        return (seconds / step).rounded() * step
    }

    func preparePlayer() {
        // Seed timeline only if asset has duration (> 0). Placeholder uses empty composition.
        if let urlAsset = asset as? AVURLAsset, CMTimeGetSeconds(urlAsset.duration) > 0.0001 {
            let first = Clip(url: urlAsset.url, asset: asset, duration: asset.duration)
            clips = [first]
        } else {
            clips = []
        }
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
        // During active playback, keep the playhead centered so the filmstrip scrolls
        // continuously under the fixed playhead line.
        followMode = .center
        startDisplayLink()
    }

    func pause() {
        player.pause()
        isPlaying = false
        followMode = .off
        stopDisplayLink()
    }

    // MARK: - Trim session for text overlays (gesture-scoped)
    struct TrimSession {
        var baseStart: Double
        var baseDuration: Double
        var baseLeft: Double
        var baseRight: Double
        var minLen: Double = 0.03
        var eps: Double = 1.0 / 240.0
    }

    @Published var activeTextTrimSession: TrimSession? = nil
    @Published var activeAudioTrimSession: TrimSession? = nil
    @Published var activeMediaTrimSession: TrimSession? = nil
    @Published var activeClipTrimSession: TrimSession? = nil

    /// Begin a trim session for the currently selected text overlay.
    @MainActor
    func beginTextTrimGesture() {
        guard let id = selectedTextId, let i = textOverlays.firstIndex(where: { $0.id == id }) else { return }
        let t = textOverlays[i]
        activeTextTrimSession = TrimSession(
            baseStart: max(0, CMTimeGetSeconds(t.start)),
            baseDuration: max(0, CMTimeGetSeconds(t.duration)),
            baseLeft: max(0, CMTimeGetSeconds(t.trimStart)),
            baseRight: max(0, CMTimeGetSeconds(t.trimEnd ?? t.duration))
        )
    }

    // MARK: - Media overlay add/move helpers
    @MainActor
    func addPhotoOverlay(imageURL: URL, at start: CMTime, defaultSeconds: Double = 3.0, position: CGPoint? = nil) {
        let pos = position ?? CGPoint(x: 0.5, y: 0.5)
        let item = TimedMediaOverlay(url: imageURL,
                                     kind: .photo,
                                     position: pos,
                                     scale: 1.0,
                                     rotation: 0,
                                     start: start,
                                     duration: CMTime(seconds: defaultSeconds, preferredTimescale: 600))
        mediaOverlays.append(item)
        selectedMediaId = item.id
        selectedTextId = nil
        selectedAudioId = nil
        selectedClipId = nil
    }

    @MainActor
    func addVideoOverlay(videoURL: URL, at start: CMTime, position: CGPoint? = nil) {
        let asset = AVURLAsset(url: videoURL)
        let d = asset.duration
        var item = TimedMediaOverlay(url: videoURL,
                                     kind: .video,
                                     position: position ?? CGPoint(x: 0.5, y: 0.5),
                                     scale: 1.0,
                                     rotation: 0,
                                     start: start,
                                     duration: d)
        item.trimEnd = d
        mediaOverlays.append(item)
        selectedMediaId = item.id
        selectedTextId = nil
        selectedAudioId = nil
        selectedClipId = nil
    }

    @MainActor
    func moveMedia(id: UUID, toStartSeconds seconds: Double) {
        guard let i = mediaOverlays.firstIndex(where: { $0.id == id }) else { return }
        let visibleLen = max(0, CMTimeGetSeconds(mediaOverlays[i].trimmedDuration))
        let project = max(0, CMTimeGetSeconds(totalDuration))
        let clamped = min(max(0, seconds), max(0, project - visibleLen))
        mediaOverlays[i].start = CMTime(seconds: clamped, preferredTimescale: 600)
    }

    /// Apply incremental trim changes during a drag gesture. Does not rebuild the composition.
    @MainActor
    func trimTextDuringGesture(id: UUID, leftDeltaSeconds: Double? = nil, rightDeltaSeconds: Double? = nil) {
        guard var s = activeTextTrimSession,
              let i = textOverlays.firstIndex(where: { $0.id == id }) else { return }

        var start = s.baseStart
        var dur   = s.baseDuration
        var left  = s.baseLeft
        var right = s.baseRight
        let project = max(0, CMTimeGetSeconds(totalDuration))
        let frame = max(frameDurationSeconds(), s.minLen)
        let minLen = max(s.minLen, frame)

        if let dx = leftDeltaSeconds {
            var targetLeft = quantizeToFrame(left + dx)
            if targetLeft >= 0 {
                left = min(max(0, targetLeft), max(0, right - minLen))
            } else {
                let extend = -targetLeft
                let allowed = min(extend, start)
                start -= allowed
                dur   += allowed
                left = 0
            }
        }

        if let dx = rightDeltaSeconds {
            let targetRight = quantizeToFrame(right + dx)
            if dx <= 0 {
                right = max(left + minLen, min(dur, targetRight))
            } else {
                if targetRight >= (dur - s.eps) {
                    let maxDur = max(0, project - start)
                    dur = min(maxDur, max(dur, targetRight))
                }
                right = min(dur, max(left + minLen, targetRight))
            }
        }

        // Clamp overall duration against project tail
        let maxDur = max(0, project - start)
        if dur > maxDur { dur = maxDur; right = min(right, dur) }
        // Final frame-quantized normalization
        start = quantizeToFrame(start)
        dur   = max(minLen, quantizeToFrame(dur))
        left  = max(0, min(quantizeToFrame(left), max(0, dur - minLen)))
        right = max(left + minLen, min(quantizeToFrame(right), dur))

        textOverlays[i].start     = CMTime(seconds: start, preferredTimescale: 600)
        textOverlays[i].duration  = CMTime(seconds: dur,   preferredTimescale: 600)
        textOverlays[i].trimStart = CMTime(seconds: left,  preferredTimescale: 600)
        textOverlays[i].trimEnd   = CMTime(seconds: right, preferredTimescale: 600)

        // Advance session baselines to make deltas cumulative-robust
        s.baseStart = start
        s.baseDuration = dur
        s.baseLeft = left
        s.baseRight = right
        activeTextTrimSession = s
    }

    /// End a trim session and rebuild the preview composition once.
    @MainActor
    func endTextTrimGesture() {
        guard activeTextTrimSession != nil else { return }
        activeTextTrimSession = nil
        Task { await rebuildCompositionForPreview() }
    }

    // MARK: - Media trim session (photo/video behaviors)
    @MainActor
    func beginMediaTrimGesture() {
        guard let id = selectedMediaId, let i = mediaOverlays.firstIndex(where: { $0.id == id }) else { return }
        let m = mediaOverlays[i]
        activeMediaTrimSession = TrimSession(
            baseStart: max(0, CMTimeGetSeconds(m.start)),
            baseDuration: max(0, CMTimeGetSeconds(m.duration)),
            baseLeft: max(0, CMTimeGetSeconds(m.trimStart)),
            baseRight: max(0, CMTimeGetSeconds(m.trimEnd ?? m.duration))
        )
    }

    @MainActor
    func trimMediaDuringGesture(id: UUID, leftDeltaSeconds: Double? = nil, rightDeltaSeconds: Double? = nil) {
        guard var s = activeMediaTrimSession,
              let i = mediaOverlays.firstIndex(where: { $0.id == id }) else { return }

        var m = mediaOverlays[i]
        let isPhoto = (m.kind == .photo)

        var start = s.baseStart
        var dur   = s.baseDuration
        var left  = s.baseLeft
        var right = s.baseRight

        let project = max(0, CMTimeGetSeconds(totalDuration))
        let frame   = max(frameDurationSeconds(), s.minLen)
        let minLen  = max(s.minLen, frame)

        // LEFT edge (cumulative)
        if let dx = leftDeltaSeconds {
            var targetLeft = quantizeToFrame(left + dx)
            if targetLeft >= 0 {
                left = min(max(0, targetLeft), max(0, right - minLen))
            } else {
                // Allow extend-left by growing scheduling window (photo & video)
                let extend  = -targetLeft
                let allowed = min(extend, start)
                start -= allowed
                dur   += allowed
                left = 0
            }
        }

        // RIGHT edge
        if let dx = rightDeltaSeconds {
            let targetRight = quantizeToFrame(right + dx)
            if isPhoto {
                // Photos may grow duration like Text
                if dx <= 0 {
                    right = max(left + minLen, min(dur, targetRight))
                } else {
                    if targetRight >= (dur - s.eps) {
                        let maxDur = max(0, project - start)
                        dur = min(maxDur, max(dur, targetRight))
                    }
                    right = min(dur, max(left + minLen, targetRight))
                }
            } else {
                // Videos cannot grow beyond source duration
                let srcDur = max(0, s.baseDuration) // baseDuration == media duration
                right = min(srcDur, max(left + minLen, targetRight))
            }
        }

        // Clamp against project tail
        let maxDur = max(0, project - start)
        if dur > maxDur { dur = maxDur; right = min(right, dur) }

        // Quantize
        start = quantizeToFrame(start)
        dur   = max(minLen, quantizeToFrame(dur))
        left  = max(0, min(quantizeToFrame(left),  max(0, dur - minLen)))
        right = max(left + minLen, min(quantizeToFrame(right), dur))

        // Write back
        m.start     = CMTime(seconds: start, preferredTimescale: 600)
        m.duration  = CMTime(seconds: dur,   preferredTimescale: 600)
        m.trimStart = CMTime(seconds: left,  preferredTimescale: 600)
        m.trimEnd   = CMTime(seconds: right, preferredTimescale: 600)
        mediaOverlays[i] = m

        // Advance baselines
        s.baseStart    = start
        s.baseDuration = dur
        s.baseLeft     = left
        s.baseRight    = right
        activeMediaTrimSession = s
    }

    @MainActor
    func endMediaTrimGesture() {
        guard activeMediaTrimSession != nil else { return }
        activeMediaTrimSession = nil
        Task { await rebuildCompositionForPreview() }
    }

    // MARK: - Trim session for audio (gesture-scoped)
    @MainActor
    func beginAudioTrimGesture() {
        guard let id = selectedAudioId, let i = audioTracks.firstIndex(where: { $0.id == id }) else { return }
        let t = audioTracks[i]
        activeAudioTrimSession = TrimSession(
            baseStart: max(0, CMTimeGetSeconds(t.start)),
            baseDuration: max(0, CMTimeGetSeconds(t.duration)),
            baseLeft: max(0, CMTimeGetSeconds(t.trimStart)),
            baseRight: max(0, CMTimeGetSeconds(t.trimEnd ?? t.duration))
        )
    }

    @MainActor
    func trimAudioDuringGesture(id: UUID, leftDeltaSeconds: Double? = nil, rightDeltaSeconds: Double? = nil) {
        guard var s = activeAudioTrimSession,
              let i = audioTracks.firstIndex(where: { $0.id == id }) else { return }

        var left  = s.baseLeft
        var right = s.baseRight
        let dur   = s.baseDuration
        let frame = max(frameDurationSeconds(), s.minLen)
        let minLen = max(s.minLen, frame)

        // LEFT edge (cumulative, frame-quantized)
        if let dx = leftDeltaSeconds {
            let targetLeft = quantizeToFrame(left + dx)
            left = min(max(0, targetLeft), max(0, right - minLen))
        }
        // RIGHT edge (cumulative, frame-quantized; clamped to source duration)
        if let dx = rightDeltaSeconds {
            let targetRight = quantizeToFrame(right + dx)
            right = min(dur, max(left + minLen, targetRight))
        }

        // Write back
        audioTracks[i].trimStart = CMTime(seconds: max(0, quantizeToFrame(left)), preferredTimescale: 600)
        audioTracks[i].trimEnd   = CMTime(seconds: min(dur, quantizeToFrame(right)), preferredTimescale: 600)

        // Advance baselines for rolling updates
        s.baseLeft = max(0, left)
        s.baseRight = min(dur, right)
        activeAudioTrimSession = s
    }

    @MainActor
    func endAudioTrimGesture() {
        guard activeAudioTrimSession != nil else { return }
        activeAudioTrimSession = nil
        Task { await rebuildCompositionForPreview() }
    }

    // MARK: - Trim session for video clips (gesture-scoped)
    @MainActor
    func beginClipTrimGesture() {
        guard let id = selectedClipId, let i = clips.firstIndex(where: { $0.id == id }) else { return }
        let c = clips[i]
        activeClipTrimSession = TrimSession(
            baseStart: 0, // not used for clips (no scheduling growth)
            baseDuration: max(0, CMTimeGetSeconds(c.duration)),
            baseLeft: max(0, CMTimeGetSeconds(c.trimStart)),
            baseRight: max(0, CMTimeGetSeconds(c.trimEnd ?? c.duration))
        )
    }

    @MainActor
    func trimClipDuringGesture(id: UUID, leftDeltaSeconds: Double? = nil, rightDeltaSeconds: Double? = nil) {
        guard var s = activeClipTrimSession,
              let i = clips.firstIndex(where: { $0.id == id }) else { return }

        var left  = s.baseLeft
        var right = s.baseRight
        let dur   = s.baseDuration
        // Ensure minimum length respects frame duration
        let frame = max(frameDurationSeconds(), s.minLen)
        let minLen = max(s.minLen, frame)

        if let dx = leftDeltaSeconds {
            let targetLeft = quantizeToFrame(left + dx)
            left = min(max(0, targetLeft), max(0, right - minLen))
        }
        if let dx = rightDeltaSeconds {
            let targetRight = quantizeToFrame(right + dx)
            right = min(dur, max(left + minLen, targetRight))
        }

        clips[i].trimStart = CMTime(seconds: max(0, quantizeToFrame(left)), preferredTimescale: 600)
        clips[i].trimEnd   = CMTime(seconds: min(dur, quantizeToFrame(right)), preferredTimescale: 600)

        // Advance baselines so deltas are cumulative-robust
        s.baseLeft = max(0, left)
        s.baseRight = min(dur, right)
        activeClipTrimSession = s
    }

    @MainActor
    func endClipTrimGesture() async {
        guard activeClipTrimSession != nil, let id = selectedClipId, let idx = clips.firstIndex(where: { $0.id == id }) else { activeClipTrimSession = nil; return }
        activeClipTrimSession = nil
        await rebuildCompositionForPreview()
        await generateThumbnails(forClipAt: idx)
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
        clips.reduce(.zero) { $0 + $1.effectiveDuration }
    }

    // Append a new clip and rebuild the composition + thumbnails
    @MainActor
    func appendClip(url: URL) async {
        let asset = AVURLAsset(url: url)
        let clip = Clip(url: url, asset: asset, duration: asset.duration)
        clips.append(clip)
        // Auto-select aspect on first import or when portrait is added later
        await MainActor.run {
            if clips.count == 1 {
                if let t = asset.tracks(withMediaType: .video).first {
                    let r = CGRect(origin: .zero, size: t.naturalSize).applying(t.preferredTransform)
                    let w = abs(r.width), h = abs(r.height)
                    if h > w { self.renderConfig.aspect = .nineBySixteen } else { self.renderConfig.aspect = .sixteenByNine }
                }
            } else if self.renderConfig.aspect == .sixteenByNine || self.renderConfig.aspect == .original {
                if let t = asset.tracks(withMediaType: .video).first {
                    let r = CGRect(origin: .zero, size: t.naturalSize).applying(t.preferredTransform)
                    let w = abs(r.width), h = abs(r.height)
                    if h > w { self.renderConfig.aspect = .nineBySixteen }
                }
            }
        }
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

        // Prepare one layer instruction for the concatenated track; we will set a transform at each segment start
        let vLayerInstruction = videoTrack.map { AVMutableVideoCompositionLayerInstruction(assetTrack: $0) }
        var projectFPS: Float = 30
        // Determine target render size from selected aspect ratio
        let renderSize: CGSize = {
            // Try to compute from selected aspect or fall back to first clip natural size
            if let ar = renderConfig.aspect.value {
                // Use 1080 on the short edge for preview quality
                let short: CGFloat = 1080
                if ar < 1.0 {
                    // Portrait: width/height = ar → width = short, height = short / ar
                    return CGSize(width: short, height: round(short / max(ar, 0.0001)))
                } else {
                    // Landscape / square
                    return CGSize(width: round(short * ar), height: short)
                }
            } else {
                // .original – use oriented natural size of first video track
                if let firstTrack = clips.first?.asset.tracks(withMediaType: .video).first {
                    let pt = firstTrack.preferredTransform
                    let rect = CGRect(origin: .zero, size: firstTrack.naturalSize).applying(pt)
                    return CGSize(width: abs(rect.width), height: abs(rect.height))
                }
                return CGSize(width: 1080, height: 1920)
            }
        }()

        var cursor: CMTime = .zero
        // Collect audio mix params for both original clip audio and user-added audio tracks
        var mixParams: [AVMutableAudioMixInputParameters] = []
        for clip in clips {
            let srcRange = CMTimeRange(start: clip.trimStart, duration: clip.trimmedDuration)
            let outDur = clip.effectiveDuration
            if let v = clip.asset.tracks(withMediaType: .video).first, let vdst = videoTrack {
                try? vdst.insertTimeRange(srcRange, of: v, at: cursor)
                // Retime the just-inserted segment to match speed
                vdst.scaleTimeRange(CMTimeRange(start: cursor, duration: srcRange.duration), toDuration: outDur)
                // Track fps to choose a sensible frameDuration
                if v.nominalFrameRate > 0 { projectFPS = v.nominalFrameRate }
                // Per-segment transform based on selected content mode (fill/fit)
                if let layer = vLayerInstruction {
                    let t = transform(for: v, renderSize: renderSize, mode: renderConfig.mode)
                    layer.setTransform(t, at: cursor)
                }
            }
            if clip.hasOriginalAudio && !clip.muteOriginalAudio,
               let aSrc = clip.asset.tracks(withMediaType: .audio).first,
               let aDst = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                // Insert original clip audio without retiming; truncate to outDur instead of scaling
                let insertRange = CMTimeRange(start: srcRange.start, duration: outDur)
                try? aDst.insertTimeRange(insertRange, of: aSrc, at: cursor)
                let p = AVMutableAudioMixInputParameters(track: aDst)
                p.setVolume(clip.originalAudioVolume, at: .zero)
                p.audioTimePitchAlgorithm = clip.preserveOriginalPitch ? .spectral : .varispeed
                mixParams.append(p)
            }
            cursor = cursor + outDur
        }
        // Include user-added audio tracks for preview
        for t in audioTracks {
            let aAsset = AVURLAsset(url: t.url)
            if let aSrc = aAsset.tracks(withMediaType: .audio).first,
               let aDst = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                // Trim-aware insertion from source time range
                let srcRange = CMTimeRange(start: t.trimStart, duration: t.trimmedDuration)
                // Desired output duration (no speed change) clamped to project tail
                let maxOut = max(.zero, totalDuration - (t.start))
                let outDur = CMTimeMinimum(t.effectiveTrimmedDuration, maxOut)
                // Insert only as much as fits without retiming (truncate instead of scaling)
                let insertRange = CMTimeRange(start: srcRange.start, duration: outDur)
                try? aDst.insertTimeRange(insertRange, of: aSrc, at: t.start)
                let p = AVMutableAudioMixInputParameters(track: aDst)
                p.setVolume(t.volume, at: .zero)
                p.audioTimePitchAlgorithm = t.preservePitch ? .spectral : .varispeed
                mixParams.append(p)
            }
        }

        // Compose overlay video tracks (PIP) into composition for preview
        for m in mediaOverlays where m.kind == .video {
            let asset = AVURLAsset(url: m.url)
            guard let src = asset.tracks(withMediaType: .video).first,
                  let dst = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            let srcRange = CMTimeRange(start: m.trimStart, duration: m.trimmedDuration)
            let maxOut = max(.zero, totalDuration - m.start)
            let outDur = CMTimeMinimum(srcRange.duration, maxOut)
            try? dst.insertTimeRange(CMTimeRange(start: srcRange.start, duration: outDur), of: src, at: m.start)
        }

        // Build video composition with our render size and layer instruction
        let vcomp = AVMutableVideoComposition()
        vcomp.renderSize = renderSize
        vcomp.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, Int32(round(projectFPS)))))
        if let layer = vLayerInstruction {
            let instr = AVMutableVideoCompositionInstruction()
            instr.timeRange = CMTimeRange(start: .zero, duration: comp.duration)
            instr.backgroundColor = CGColor(gray: 0, alpha: 1)
            instr.layerInstructions = [layer]
            vcomp.instructions = [instr]
        }

        composition = comp
        let item = AVPlayerItem(asset: composition)
        item.videoComposition = vcomp
        // Global default: if any retimed audio requests pitch preservation, prefer spectral
        let wantsPitch = (clips.contains { $0.speed != 1.0 && $0.preserveOriginalPitch }) ||
                         (audioTracks.contains { $0.speed != 1.0 && $0.preservePitch })
        item.audioTimePitchAlgorithm = wantsPitch ? .spectral : .varispeed
        if !mixParams.isEmpty {
            let mix = AVMutableAudioMix(); mix.inputParameters = mixParams
            item.audioMix = mix
        }
        // Swap player item and seek back. Prefer avoiding stalls during swap.
        player.automaticallyWaitsToMinimizeStalling = true
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
        let total = CMTimeGetSeconds(clip.effectiveDuration)
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
        await MainActor.run {
            if let existing = imageGenerators[clip.id] {
                existing.cancelAllCGImageGeneration()
            }
        }

        // Create a new generator configured for filmstrip speed (non-zero tolerances)
        let gen = AVAssetImageGenerator(asset: clip.asset)
        gen.appliesPreferredTrackTransform = true
        gen.apertureMode = .cleanAperture
        gen.maximumSize = CGSize(width: 0, height: TimelineStyle.videoRowHeight * UIScreen.main.scale)
        let tol = CMTime(value: 1, timescale: 30) // ~33ms tolerance for speed
        gen.requestedTimeToleranceBefore = tol
        gen.requestedTimeToleranceAfter  = tol
        await MainActor.run {
            imageGenerators[clip.id] = gen
        }
        let token = UUID()
        await MainActor.run { thumbnailGenTokens[clip.id] = token }

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
    func addAudio(url: URL, at start: CMTime, volume: Float = 0.5, displayName: String? = nil) async {
        let aAsset = AVURLAsset(url: url)
        let dur = aAsset.duration
        // Load or generate waveform samples off-main; then update model on main
        let samples = await WaveformGenerator.loadOrGenerate(for: aAsset)
        var track = AudioTrack(url: url, start: start, duration: dur, volume: volume)
        track.waveformSamples = samples
        track.titleOverride = displayName
        audioTracks.append(track)
    }

    // Extract original audio from the selected clip into audioTracks (periwinkle lane below video)
    @MainActor
    func extractOriginalAudioFromSelectedClip(undoManager: UndoManager?) async {
        guard let clip = selectedClip else { return }
        guard clip.hasOriginalAudio else { return }
        guard let assetURL = (clip.asset as? AVURLAsset)?.url else { return }
        let absStart = CMTime(seconds: selectedClipStartSeconds ?? 0, preferredTimescale: 600)
        let range = CMTimeRange(start: clip.trimStart, duration: clip.trimmedDuration)

        // Waveform samples (reuse cached per-asset samples). Slicing can be done at draw-time.
        let samples = await WaveformGenerator.loadOrGenerate(for: clip.asset)

        var track = AudioTrack(url: assetURL, start: absStart, duration: clip.duration, volume: 0.5)
        track.trimStart = range.start
        track.trimEnd   = range.start + range.duration
        track.waveformSamples = samples
        track.titleOverride = "Extracted audio"
        track.isExtracted = true
        track.sourceClipId = clip.id
        audioTracks.append(track)

        // Mute the original audio from the video clip to avoid doubling
        if let i = clips.firstIndex(where: { $0.id == clip.id }) {
            clips[i].muteOriginalAudio = true
        }

        await rebuildCompositionForPreview()

        // Undo registration
        undoManager?.registerUndo(withTarget: self) { target in
            if let idx = target.audioTracks.firstIndex(where: { $0.id == track.id }) {
                target.audioTracks.remove(at: idx)
            }
            if let ci = target.clips.firstIndex(where: { $0.id == clip.id }) {
                target.clips[ci].muteOriginalAudio = false
            }
            Task { await target.rebuildCompositionForPreview() }
        }
        undoManager?.setActionName("Extract audio")
    }

    // (Reverted) extractOriginalAudioFromSelectedClip pending research

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

    // Move text start time with clamping based on trimmed length
    @MainActor
    func moveText(id: UUID, toStartSeconds seconds: Double) {
        guard let i = textOverlays.firstIndex(where: { $0.id == id }) else { return }
        let visibleLen = max(0, CMTimeGetSeconds(textOverlays[i].trimmedDuration))
        let totalS = max(0, CMTimeGetSeconds(totalDuration))
        let clamped = min(max(0, seconds), max(0, totalS - visibleLen))
        textOverlays[i].start = CMTime(seconds: clamped, preferredTimescale: 600)
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
        // Fall back to half of the project frame duration (defaults to 30fps → 1/60s)
        return CMTime(seconds: 0.5 * frameDurationSeconds(), preferredTimescale: 600)
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
    
    // MARK: - Insert clip at playhead (with split)
    @MainActor
    func insertClipAtPlayhead(url: URL) async {
        await insertClip(url: url, at: displayTime)
    }

    @MainActor
    private func insertClip(url: URL, at timelineTime: CMTime) async {
        let asset = AVURLAsset(url: url)
        var newClip = Clip(url: url, asset: asset, duration: asset.duration)
        // Detect original audio presence immediately
        let hasAudio = asset.tracks(withMediaType: .audio).first != nil
        newClip.hasOriginalAudio = hasAudio

        // Determine insertion index and whether we are inside a clip
        let tolerance = halfFrameTolerance()
        var accumulated: CMTime = .zero
        var insertIndex: Int = clips.count
        var splitLocal: CMTime? = nil

        for i in clips.indices {
            let dur = clips[i].trimmedDuration
            let start = accumulated
            let end = accumulated + dur

            if timelineTime <= start + tolerance {
                insertIndex = i
                break
            }
            if timelineTime < end - tolerance {
                // inside clip i
                let local = timelineTime - start
                // boundary checks
                if local <= tolerance {
                    insertIndex = i
                } else if (end - timelineTime) <= tolerance {
                    insertIndex = i + 1
                } else {
                    insertIndex = i
                    splitLocal = local
                }
                break
            }
            accumulated = end
        }

        // Perform split if needed
        if let local = splitLocal {
            // First split the host into left/right with fresh identities
            await splitClip(at: insertIndex, localTime: local)
            // After split, clips[insertIndex] = left, clips[insertIndex+1] = right
            let right = clips.remove(at: insertIndex + 1)
            // Insert new clip between left and right
            clips.insert(newClip, at: insertIndex + 1)
            clips.insert(right, at: insertIndex + 2)

            await rebuildComposition()
            await generateThumbnails(forClipAt: insertIndex)       // left
            await generateThumbnails(forClipAt: insertIndex + 1)   // new
            await generateThumbnails(forClipAt: insertIndex + 2)   // right
            selectedClipId = newClip.id
        } else {
            // No split; just insert
            clips.insert(newClip, at: insertIndex)
            await rebuildComposition()
            await generateThumbnails(forClipAt: insertIndex)
            selectedClipId = newClip.id
        }

        // Generate waveform for audio if present
        if hasAudio {
            let samples = await WaveformGenerator.loadOrGenerate(for: asset)
            await MainActor.run {
                if let idx = clips.firstIndex(where: { $0.id == newClip.id }) {
                    clips[idx].waveformSamples = samples
                }
            }
        }

        // Keep the inserted region visible
        followMode = .keepVisible
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

    // MARK: - Media overlay selection helpers
    var selectedMedia: TimedMediaOverlay? { mediaOverlays.first { $0.id == selectedMediaId } }
    var selectedMediaStartSeconds: Double? {
        guard let m = selectedMedia else { return nil }
        return max(0, CMTimeGetSeconds(m.effectiveStart))
    }
    var selectedMediaEndSeconds: Double? {
        guard let m = selectedMedia else { return nil }
        return max(0, CMTimeGetSeconds(m.effectiveStart + m.trimmedDuration))
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

        var start = max(0, CMTimeGetSeconds(t.start))
        var dur   = max(0, CMTimeGetSeconds(t.duration))
        var left  = max(0, CMTimeGetSeconds(t.trimStart))
        var right = max(0, CMTimeGetSeconds(t.trimEnd ?? t.duration))
        let project = max(0, CMTimeGetSeconds(totalDuration))
        let minLen: Double = 0.03
        let eps: Double = 1.0 / 240.0

        if let dx = leftDeltaSeconds {
            if dx >= 0 {
                left = min(max(0, left + dx), max(0, right - minLen))
            } else {
                let extend = -dx
                if left >= extend {
                    left -= extend
                } else {
                    let extra = extend - left
                    left = 0
                    let allowed = min(extra, start)
                    start -= allowed
                    dur += allowed
                }
            }
        }

        if let dx = rightDeltaSeconds {
            if dx <= 0 {
                right = max(left + minLen, min(dur, right + dx))
            } else {
                var newRight = right + dx
                // If approaching current duration boundary within tolerance, treat as an extension
                if newRight > (dur - eps) {
                    let room = max(0, project - start - dur)
                    let grow = min(max(0, newRight - dur), room)
                    dur += grow
                }
                right = min(dur, newRight)
                right = max(right, left + minLen)
            }
        }

        let maxDur = max(0, project - start)
        if dur > maxDur { dur = maxDur; right = min(right, dur) }

        t.start     = CMTime(seconds: start, preferredTimescale: 600)
        t.duration  = CMTime(seconds: dur,   preferredTimescale: 600)
        t.trimStart = CMTime(seconds: left,  preferredTimescale: 600)
        t.trimEnd   = CMTime(seconds: right, preferredTimescale: 600)
        textOverlays[i] = t
        // Keep preview state coherent when text overlays change timing
        Task { await rebuildCompositionForPreview() }
    }

    // MARK: - Delete selection from timeline (clip, audio, or text)
    @MainActor
    func deleteSelected() async {
        if let textId = selectedTextId {
            if let idx = textOverlays.firstIndex(where: { $0.id == textId }) {
                textOverlays.remove(at: idx)
            }
            selectedTextId = nil
            return
        }
        if let mediaId = selectedMediaId {
            if let idx = mediaOverlays.firstIndex(where: { $0.id == mediaId }) {
                mediaOverlays.remove(at: idx)
            }
            selectedMediaId = nil
            // Rebuild preview if any video overlay might be affected
            await rebuildCompositionForPreview()
            return
        }
        if let audioId = selectedAudioId {
            if let idx = audioTracks.firstIndex(where: { $0.id == audioId }) {
                audioTracks.remove(at: idx)
            }
            selectedAudioId = nil
            await rebuildCompositionForPreview()
            return
        }
        if let clipId = selectedClipId {
            if let idx = clips.firstIndex(where: { $0.id == clipId }) {
                // Clean up thumbnail state for the clip being deleted
                imageGenerators[clips[idx].id]?.cancelAllCGImageGeneration()
                imageGenerators.removeValue(forKey: clips[idx].id)
                thumbnailGenTokens.removeValue(forKey: clips[idx].id)
                clips.remove(at: idx)
                selectedClipId = nil
                await rebuildComposition()
                return
            }
        }
    }

    /// Duplicate the currently selected item and place the copy immediately to the right on the same lane/track.
    @MainActor
    func duplicateSelected() async {
        // TEXT overlay duplication
        if let tid = selectedTextId, let i = textOverlays.firstIndex(where: { $0.id == tid }) {
            let src = textOverlays[i]
            // Compute new placement so visible start = source visible end
            let sourceEnd = src.effectiveStart + src.trimmedDuration
            let newStart = max(.zero, sourceEnd - src.trimStart)
            // Create a brand new base with a new id (since base.id is let)
            let newBase = TextOverlay(
                id: UUID(),
                string: src.base.string,
                fontName: src.base.fontName,
                style: src.base.style,
                color: src.base.color,
                position: CGPoint(x: src.base.position.x + 16, y: src.base.position.y + 16),
                scale: src.base.scale,
                rotation: src.base.rotation,
                zIndex: src.base.zIndex + 1
            )
            var dup = TimedTextOverlay(base: newBase, start: newStart, duration: src.duration)
            dup.trimStart = src.trimStart
            dup.trimEnd   = src.trimEnd
            textOverlays.append(dup)
            selectedTextId = dup.id
            await rebuildCompositionForPreview()
            followMode = .keepVisible
            // Center timeline near the duplicate's start for immediate accessibility
            displayTime = CMTime(seconds: max(0, CMTimeGetSeconds(dup.effectiveStart)), preferredTimescale: 600)
            return
        }

        // MEDIA overlay duplication (unify with EditorTrackArea behavior: duplicate in place + nudge)
        if let mid = selectedMediaId, let i = mediaOverlays.firstIndex(where: { $0.id == mid }) {
            let src = mediaOverlays[i]
            let dup = TimedMediaOverlay(
                url: src.url,
                kind: src.kind,
                position: CGPoint(x: src.position.x + 16, y: src.position.y + 16),
                scale: src.scale,
                rotation: src.rotation,
                alpha: src.alpha,
                zIndex: src.zIndex + 1,
                start: src.start,
                duration: src.duration,
                trimStart: src.trimStart,
                trimEnd: src.trimEnd
            )
            mediaOverlays.append(dup)
            selectedMediaId = dup.id
            await rebuildCompositionForPreview()
            followMode = .keepVisible
            displayTime = CMTime(seconds: max(0, CMTimeGetSeconds(dup.effectiveStart)), preferredTimescale: 600)
            return
        }

        // AUDIO duplication
        if let aid = selectedAudioId, let i = audioTracks.firstIndex(where: { $0.id == aid }) {
            let src = audioTracks[i]
            var dup = src
            // Assign new identity via reinit
            dup = AudioTrack(url: src.url, start: src.start, duration: src.duration, volume: src.volume)
            dup.waveformSamples = src.waveformSamples
            dup.titleOverride = src.titleOverride
            dup.trimStart = src.trimStart
            dup.trimEnd = src.trimEnd
            dup.isExtracted = src.isExtracted
            dup.sourceClipId = src.sourceClipId
            // Place so visible start equals source visible end
            let visibleEnd = src.start + src.trimStart + src.trimmedDuration
            dup.start = max(.zero, visibleEnd - src.trimStart)
            audioTracks.append(dup)
            selectedAudioId = dup.id
            await rebuildCompositionForPreview()
            followMode = .keepVisible
            displayTime = CMTime(seconds: max(0, CMTimeGetSeconds(dup.start + dup.trimStart)), preferredTimescale: 600)
            return
        }

        // CLIP duplication
        if let cid = selectedClipId, let idx = clips.firstIndex(where: { $0.id == cid }) {
            let src = clips[idx]
            var dup = src
            // New identity and reset transient visuals so they regenerate
            dup = Clip(url: src.url, asset: src.asset, duration: src.duration)
            dup.hasOriginalAudio = src.hasOriginalAudio
            dup.waveformSamples = src.waveformSamples
            dup.muteOriginalAudio = src.muteOriginalAudio
            dup.originalAudioVolume = src.originalAudioVolume
            dup.trimStart = src.trimStart
            dup.trimEnd = src.trimEnd
            let insertIndex = idx + 1
            clips.insert(dup, at: insertIndex)
            await rebuildComposition()
            await generateThumbnails(forClipAt: insertIndex)
            selectedClipId = dup.id
            followMode = .keepVisible
            displayTime = CMTime(seconds: max(0, CMTimeGetSeconds(dup.trimStart)), preferredTimescale: 600)
            return
        }
    }

    // MARK: - Internal split helper (fresh identities, thumbnail cleanup)
    @MainActor
    fileprivate func splitClip(at index: Int, localTime: CMTime) async {
        guard clips.indices.contains(index) else { return }
        let host = clips[index]
        let splitPoint = host.trimStart + localTime

        // Construct brand-new left/right clips with copied properties and fresh UUIDs
        var left = Clip(url: host.url, asset: host.asset, duration: host.duration)
        left.hasOriginalAudio = host.hasOriginalAudio
        left.waveformSamples = host.waveformSamples
        left.muteOriginalAudio = host.muteOriginalAudio
        left.originalAudioVolume = host.originalAudioVolume
        left.speed = host.speed
        left.preserveOriginalPitch = host.preserveOriginalPitch
        left.smoothInterpolation = host.smoothInterpolation
        left.trimStart = host.trimStart
        left.trimEnd = splitPoint

        var right = Clip(url: host.url, asset: host.asset, duration: host.duration)
        right.hasOriginalAudio = host.hasOriginalAudio
        right.waveformSamples = host.waveformSamples
        right.muteOriginalAudio = host.muteOriginalAudio
        right.originalAudioVolume = host.originalAudioVolume
        right.speed = host.speed
        right.preserveOriginalPitch = host.preserveOriginalPitch
        right.smoothInterpolation = host.smoothInterpolation
        right.trimStart = splitPoint
        right.trimEnd = host.trimEnd

        // Remove original and insert left/right
        clips.remove(at: index)
        clips.insert(contentsOf: [left, right], at: index)

        // Cleanup thumbnail generators and tokens for the old host id
        imageGenerators[host.id]?.cancelAllCGImageGeneration()
        imageGenerators.removeValue(forKey: host.id)
        thumbnailGenTokens.removeValue(forKey: host.id)

        await rebuildComposition()
        await generateThumbnails(forClipAt: index)
        await generateThumbnails(forClipAt: index + 1)

        // Auto-select right half
        selectedClipId = clips[index + 1].id
        followMode = .keepVisible
    }

    // MARK: - Split AUDIO at playhead
    @MainActor
    func splitSelectedAudioAtPlayhead() async {
        guard let aid = selectedAudioId, let index = audioTracks.firstIndex(where: { $0.id == aid }) else { return }
        let t = audioTracks[index]
        let absSplit = displayTime

        let visibleStartAbs = t.start + t.trimStart
        let visibleEndAbs = t.start + (t.trimEnd ?? t.duration)
        let tol = halfFrameTolerance()
        if absSplit <= visibleStartAbs + tol { return }
        if absSplit >= visibleEndAbs - tol { return }

        let deltaTimeline = absSplit - visibleStartAbs
        let speed = t.speed != 0 ? t.speed : 1.0
        let deltaSource = CMTimeMultiplyByFloat64(deltaTimeline, multiplier: speed)

        // Build left track
        var left = AudioTrack(url: t.url, start: t.start, duration: t.duration, volume: t.volume)
        left.waveformSamples = t.waveformSamples
        left.titleOverride = t.titleOverride
        left.trimStart = t.trimStart
        left.trimEnd = t.trimStart + deltaSource
        left.speed = t.speed
        left.preservePitch = t.preservePitch
        left.isExtracted = t.isExtracted
        left.sourceClipId = t.sourceClipId

        // Build right track
        var right = AudioTrack(url: t.url, start: absSplit, duration: t.duration, volume: t.volume)
        right.waveformSamples = t.waveformSamples
        right.titleOverride = t.titleOverride
        right.trimStart = t.trimStart + deltaSource
        right.trimEnd = t.trimEnd
        right.speed = t.speed
        right.preservePitch = t.preservePitch
        right.isExtracted = t.isExtracted
        right.sourceClipId = t.sourceClipId

        audioTracks.remove(at: index)
        audioTracks.insert(contentsOf: [left, right], at: index)

        await rebuildCompositionForPreview()
        selectedAudioId = right.id
        followMode = .keepVisible
    }

    // MARK: - Split TEXT at playhead
    @MainActor
    func splitSelectedTextAtPlayhead() async {
        guard let tid = selectedTextId, let index = textOverlays.firstIndex(where: { $0.id == tid }) else { return }
        let o = textOverlays[index]
        // Quantize playhead to the nearest frame to avoid sub-frame slivers
        let absSplit = CMTime(seconds: quantizeToFrame(max(0, CMTimeGetSeconds(displayTime))), preferredTimescale: 600)

        let visibleStartAbs = o.start + o.trimStart
        let visibleEndAbs = visibleStartAbs + o.trimmedDuration
        let tol = halfFrameTolerance()
        if absSplit <= visibleStartAbs + tol { return }
        if absSplit >= visibleEndAbs - tol { return }

        let delta = absSplit - visibleStartAbs
        // Enforce minimum segment length: max(1 frame, 0.03s)
        let minLenSec = max(frameDurationSeconds(), 0.03)
        let leftLenSec = max(0, CMTimeGetSeconds(delta))
        let rightLenSec = max(0, CMTimeGetSeconds((visibleEndAbs - absSplit)))
        if leftLenSec < minLenSec || rightLenSec < minLenSec { return }

        // Clone bases with fresh identities
        let base = o.base
        let leftBase = TextOverlay(id: UUID(), string: base.string, fontName: base.fontName, style: base.style, color: base.color, position: base.position, scale: base.scale, rotation: base.rotation, zIndex: base.zIndex)
        let rightBase = TextOverlay(id: UUID(), string: base.string, fontName: base.fontName, style: base.style, color: base.color, position: base.position, scale: base.scale, rotation: base.rotation, zIndex: base.zIndex)

        var left = TimedTextOverlay(base: leftBase, start: o.start, duration: o.duration)
        left.trimStart = o.trimStart
        left.trimEnd = o.trimStart + delta

        var right = TimedTextOverlay(base: rightBase, start: o.start, duration: o.duration)
        right.trimStart = o.trimStart + delta
        right.trimEnd = o.trimEnd

        textOverlays.remove(at: index)
        textOverlays.insert(contentsOf: [left, right], at: index)

        await rebuildCompositionForPreview()
        selectedTextId = right.id
        followMode = .keepVisible
    }

    // MARK: - Split selected clip at current playhead
    @MainActor
    func splitSelectedClipAtPlayhead() async {
        guard let cid = selectedClipId,
              let idx = clips.firstIndex(where: { $0.id == cid }) else { return }

        let absStart = CMTime(seconds: startSeconds(for: cid) ?? 0, preferredTimescale: 600)
        let play = displayTime
        guard play >= absStart else { return }
        let local = play - absStart
        let tol = halfFrameTolerance()
        if local <= tol { return }
        if local >= (clips[idx].trimmedDuration - tol) { return }

        await splitClip(at: idx, localTime: local)
    }
}

// MARK: - UI helpers
// Log-scale mapping helpers used by the Speed dock
private func unitToRate(_ t: Double) -> Double {
    let minRate: Double = 0.2
    let maxRate: Double = 100.0
    let a = log10(minRate)
    let b = log10(maxRate)
    return pow(10, a + (b - a) * max(0, min(1, t)))
}
private func rateToUnit(_ r: Double) -> Double {
    let minRate: Double = 0.2
    let maxRate: Double = 100.0
    let clamped = max(minRate, min(maxRate, r))
    let a = log10(minRate)
    let b = log10(maxRate)
    return (log10(clamped) - a) / (b - a)
}
private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> PlayerView { PlayerView() }
    func updateUIView(_ uiView: PlayerView, context: Context) { uiView.player = player }

    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        var player: AVPlayer? {
            get { playerLayer.player }
            set { playerLayer.player = newValue; playerLayer.videoGravity = .resizeAspectFill }
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

// MARK: - Speed Dock (Standard)
private struct SpeedDockView: View {
    @Binding var speedUnit: Double // 0..1 mapped to 0.2..100
    @Binding var preservePitch: Bool
    let onApply: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Standard")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white)
                    .foregroundColor(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Spacer()
                Button(action: onApply) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 4)

            // Speed readout and slider
            VStack(spacing: 8) {
                Text(String(format: "%.2f×", unitToRate(speedUnit)))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                Slider(value: $speedUnit, in: 0...1)
                    .tint(Color(red: 247/255, green: 180/255, blue: 81/255))
                HStack {
                    Text("0.2"); Spacer(); Text("1"); Spacer(); Text("2"); Spacer(); Text("10"); Spacer(); Text("100")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
            }

            HStack {
                Spacer()
                Button(action: { preservePitch.toggle() }) {
                    HStack(spacing: 8) {
                        Image(systemName: preservePitch ? "largecircle.fill.circle" : "circle")
                        Text("Original Pitch")
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}


