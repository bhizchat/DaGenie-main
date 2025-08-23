import SwiftUI
import AVFoundation

/// Container that drives the 3-step modal flow for a node: Game → Task → Check-point Photo.
struct MissionFlowView: View {
    enum Step: String {
        case game
        case task
        case checkpoint
    }

    // MARK: Input
    let missionIndex: Int
    let isReplay: Bool
    let gameDescription: String
    let taskText: String
    let checkpointPrompt: String
    let imageName: String?
    let onFinish: () -> Void

    // MARK: State
    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .game
    @State private var gameMedia: CapturedMedia?
    @State private var taskMedia: CapturedMedia?
    @State private var checkpointMedia: CapturedMedia?

    @State private var showingCamera = false
    @State private var showingPlayer = false
    @State private var cameraForStep: Step = .game
    @State private var playerMedia: CapturedMedia?
    @State private var pendingMedia: CapturedMedia?
    @State private var showPhotoEditor = false
    @State private var showVideoCaption = false
    @State private var showQuitAlert = false

    @ObservedObject private var runManager = RunManager.shared

    // MARK: - Actions
    // MARK: - Toolbar
    private var backToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button(action: { print("[MissionFlow] Back tapped"); showQuitAlert = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
            }
        }
    }

    // MARK: - Actions
    private func quitAdventure() {
        let level = LevelStore.shared.currentLevel
        RunManager.shared.cancelCurrentRun(level: level) { _ in
            AnalyticsManager.shared.logEvent("adventure_quit", parameters: ["level": level])
            dismiss()
        }
    }

    var body: some View {
        content
            .navigationBarBackButtonHidden(true) // hide system back always
            .toolbar { backToolbar }
            .interactiveDismissDisabled(true)
            .background(DisableBackSwipe().frame(width: 0, height: 0))
            .alert("Quit adventure?", isPresented: $showQuitAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Quit", role: .destructive) { quitAdventure() }
            } message: {
                Text("If you go back now, your current adventure's progress will not be saved.")
            }
    }

    // Extracted main content to avoid modifier churn
    private var content: some View {
        // Renders the current step's view
        Group {
            switch step {
            case .game:
                GameToPlayView(
                    gameText: gameDescription,
                    imageName: imageName,
                    isCompleted: gameMedia != nil,
                    uploadProgress: gameMedia?.uploadProgress,
                    hasRemote: (gameMedia?.remoteURL != nil),
                    onOpenCamera: { openCamera(for: .game) },
                    onPlay: gameMedia == nil ? nil : { play(media: gameMedia!) },
                    onComplete: { step = .task }
                )
            case .task:
                TaskView(
                    taskText: taskText,
                    onBack: { step = .game },
                    imageName: TaskCategory.imageName(for: taskText),
                    isCompleted: taskMedia != nil,
                    uploadProgress: taskMedia?.uploadProgress,
                    hasRemote: (taskMedia?.remoteURL != nil),
                    onOpenCamera: { openCamera(for: .task) },
                    onPlay: taskMedia == nil ? nil : { play(media: taskMedia!) },
                    onNext: { step = .checkpoint }
                )
            case .checkpoint:
                CheckpointPhotoView(
                    promptText: checkpointPrompt,
                    isCompleted: checkpointMedia != nil,
                    uploadProgress: checkpointMedia?.uploadProgress,
                    hasRemote: (checkpointMedia?.remoteURL != nil),
                    onOpenCamera: { openCamera(for: .checkpoint) },
                    onPlay: checkpointMedia == nil ? nil : { play(media: checkpointMedia!) },
                    onBack: { step = .task },
                    onFinish: {
                        if isReplay {
                            // Do not advance progress during replay
                            dismiss()
                        } else {
                            onFinish()
                            dismiss()
                        }
                    }
                )
            }
        }
        .onAppear {
            // Ensure we have a runId for this level; if user is resuming progress, restore it
            let level = LevelStore.shared.currentLevel
            if runManager.currentRunId == nil {
                _ = runManager.resumeLastRun(level: level)
                // If nothing to resume, create a fresh run so progress can be tracked
                if runManager.currentRunId == nil {
                    _ = runManager.startNewRun(level: level)
                    print("[MissionFlowView] started new runId for level: \(level)")
                }
            }
            // Load media for this specific mission
            JourneyPersistence.shared.loadFor(level: level, missionIndex: missionIndex) { g, t, c in
                // Do NOT fallback to other missions; keep nodes distinct.
                self.gameMedia = g
                self.taskMedia = t
                self.checkpointMedia = c
            }
        }
        .onChange(of: missionIndex) { _ in
            // When switching to a different mission, clear any prior media state
            self.gameMedia = nil
            self.taskMedia = nil
            self.checkpointMedia = nil
            let level = LevelStore.shared.currentLevel
            JourneyPersistence.shared.loadFor(level: level, missionIndex: missionIndex) { g, t, c in
                self.gameMedia = g
                self.taskMedia = t
                self.checkpointMedia = c
            }
        }
        .onChange(of: runManager.currentRunId) { _ in
            // When starting or switching adventures, clear and reload strictly for new run
            self.gameMedia = nil
            self.taskMedia = nil
            self.checkpointMedia = nil
            let level = LevelStore.shared.currentLevel
            JourneyPersistence.shared.loadFor(level: level, missionIndex: missionIndex) { g, t, c in
                self.gameMedia = g
                self.taskMedia = t
                self.checkpointMedia = c
            }
        }
        .onChange(of: gameMedia) { _ in notifyPointsUpdate() }
        .onChange(of: taskMedia) { _ in notifyPointsUpdate() }
        .onChange(of: checkpointMedia) { _ in notifyPointsUpdate() }
        
        .sheet(isPresented: $showingCamera) {
            CameraSheet { media in
                guard let media = media else { return }
                // Hold while we route to editor/caption
                pendingMedia = media
                if media.type == .photo {
                    showPhotoEditor = true
                } else {
                    showVideoCaption = true
                }
            }
        }
        .sheet(isPresented: $showingPlayer, onDismiss: { playerMedia = nil }) {
            if let media = playerMedia {
                MediaPlayerView(media: media)
            }
        }
        .fullScreenCover(isPresented: $showPhotoEditor, onDismiss: { pendingMedia = nil }) {
            if let pending = pendingMedia, pending.type == .photo {
                PhotoEditorView(originalURL: pending.localURL, onCancel: {
                    showPhotoEditor = false
                }, onExport: { editedURL in
                    let finalized = CapturedMedia(localURL: editedURL, type: .photo, cameraSource: pending.cameraSource)
                    assignMedia(finalized)
                    showPhotoEditor = false
                })
            }
        }
        .sheet(isPresented: $showVideoCaption, onDismiss: { pendingMedia = nil }) {
            if let pending = pendingMedia, pending.type == .video {
                VideoCaptionSheet(onCancel: { showVideoCaption = false }, onSave: { caption in
                    var finalized = CapturedMedia(localURL: pending.localURL, type: .video, caption: caption)
                    assignMedia(finalized)
                    showVideoCaption = false
                })
            }
        }
    }

    private func openCamera(for step: Step) {
        cameraForStep = step
        showingCamera = true
        AnalyticsManager.shared.logEvent("camera_opened", parameters: [
            "step": step.rawValue,
            "camera": "back"
        ])
    }

    private func play(media: CapturedMedia) {
        playerMedia = media
        showingPlayer = true
        AnalyticsManager.shared.logEvent("media_play", parameters: [
            "type": media.type == .photo ? "photo" : "video"
        ])
    }

    private func assignMedia(_ media: CapturedMedia) {
        // assign locally
        switch cameraForStep {
        case .game: gameMedia = media
        case .task: taskMedia = media
        case .checkpoint: checkpointMedia = media
        }
        // Log capture after finalization (post editor/caption)
        var params: [String: Any] = [
            "type": media.type == .photo ? "photo" : "video",
            "step": cameraForStep.rawValue
        ]
        if media.type == .video {
            let asset = AVURLAsset(url: media.localURL)
            let dur = CMTimeGetSeconds(asset.duration)
            params["duration"] = Int(dur.rounded())
        }
        if let caption = media.caption { params["caption_present"] = !caption.isEmpty }
        AnalyticsManager.shared.logEvent("media_captured", parameters: params)

        // Start background upload
        let stepKey = cameraForStep.rawValue
        _ = MediaUploadManager.shared.upload(media: media, step: stepKey, progress: { pct in
            // update progress into the step media
            switch cameraForStep {
            case .game: gameMedia?.uploadProgress = pct
            case .task: taskMedia?.uploadProgress = pct
            case .checkpoint: checkpointMedia?.uploadProgress = pct
            }
        }, completion: { result in
            if case .success(let url) = result {
                // Update UI state media with remote URL
                switch cameraForStep {
                case .game: gameMedia?.remoteURL = url
                case .task: taskMedia?.remoteURL = url
                case .checkpoint: checkpointMedia?.remoteURL = url
                }
                // Build a media object that includes the remote URL for persistence
                let persisted = CapturedMedia(localURL: media.localURL, type: media.type, caption: media.caption, remoteURL: url, uploadProgress: 1.0)
                var duration: Int? = nil
                if media.type == .video {
                    let asset = AVURLAsset(url: media.localURL)
                    duration = Int(CMTimeGetSeconds(asset.duration).rounded())
                }
                JourneyPersistence.shared.saveNode(step: stepKey, missionIndex: missionIndex, media: persisted, durationSeconds: duration)
                notifyPointsUpdate()
            }
        })
    }

    private func notifyPointsUpdate() {
        NotificationCenter.default.post(name: Notification.Name("missionProgressUpdated"), object: nil)
    }
}
