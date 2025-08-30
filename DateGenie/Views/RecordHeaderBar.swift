import SwiftUI
import AVFoundation

struct RecordHeaderBar: View {
    let level: Int
    @State private var items: [JourneyPersistence.MediaItem] = []
    @State private var isEditingOrder: Bool = false
    @State private var showPlayer: Bool = false
    @State private var selectedItem: JourneyPersistence.MediaItem? = nil
    @State private var selectedNodeId: String? = nil
    @State private var showShare = false
    private let maxBubbles: Int = 5

    var body: some View {
        HStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Existing media bubbles. Photos and videos both show a thumbnail image.
                    ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                            ZStack {
                                Circle().fill(Color.white).frame(width: 50, height: 50)
                                if item.type == .photo {
                                    AsyncImage(url: item.remoteURL) { phase in
                                        if case .success(let img) = phase { img.resizable().scaledToFill() }
                                        else { Color.gray.opacity(0.2) }
                                    }
                                    .frame(width: 50, height: 50)
                                    .clipShape(Circle())
                                } else {
                                VideoThumbBubble(url: item.remoteURL)
                                    .frame(width: 50, height: 50)
                                    .clipShape(Circle())
                            }
                            }
                            .onTapGesture { selectedItem = item; selectedNodeId = item.id; showPlayer = true }
                            .gesture(DragGesture()
                                .onEnded { value in
                                    let threshold: CGFloat = 60
                                    if abs(value.translation.width) > threshold {
                                        var newIndex = idx + (value.translation.width > 0 ? 1 : -1)
                                        newIndex = max(0, min(items.count - 1, newIndex))
                                        var copy = items
                                        let moved = copy.remove(at: idx)
                                        copy.insert(moved, at: newIndex)
                                        items = copy
                                    }
                                })
                        }
                    // Camera bubble: always appears immediately after the last media
                    Button(action: openCameraForNewMedia) {
                        ZStack {
                            Circle().fill(Color.white).frame(width: 50, height: 50)
                            Image("icon_camera_round")
                                .renderingMode(.original)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                        }
                    }
                }
                .padding(.leading, 12)
            }
            Spacer(minLength: 8)
            Button(action: generateReel) {
                ZStack {
                    Circle().fill(Color.white).frame(width: 60, height: 60)
                    Text("Generate\nReel")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.black)
                }
            }
            .padding(.trailing, 12)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: 72)
        .background(Color.black)
        .ignoresSafeArea(edges: .bottom)
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("missionProgressUpdated"))) { _ in reload() }
        .sheet(isPresented: $showPlayer, onDismiss: { selectedItem = nil; selectedNodeId = nil }) {
            if let item = selectedItem {
                VStack(spacing: 0) {
                    CapcutEditorView(url: item.remoteURL)
                        .overlay(alignment: .bottomTrailing) {
                            Button(action: deleteSelected) {
                                Image(systemName: "trash.circle.fill")
                                    .foregroundColor(.red)
                                    .font(.system(size: 36))
                                    .padding(16)
                            }
                        }
                }
            }
        }
    }

    private var currentRunId: String? { RunManager.shared.currentRunId }

    private func deleteSelected() {
        guard let nodeId = selectedNodeId, let runId = currentRunId else { return }
        let level = LevelStore.shared.currentLevel
        JourneyPersistence.shared.deleteNode(level: level, runId: runId, nodeId: nodeId) { ok in
            if ok {
                showPlayer = false
                reload()
            }
        }
    }

    private func reload() {
        guard let runId = currentRunId else { items = []; return }
        JourneyPersistence.shared.loadAllMediaForRun(level: level, runId: runId) { arr in
            self.items = arr
        }
    }

    private func generateReel() {
        guard let runId = currentRunId else { return }
        LoadingOverlay.show(text: "Generating reel…")
        HighlightReelBuilder.shared.buildReel(level: level, runId: runId) { res in
            switch res {
            case .failure(let err):
                DispatchQueue.main.async {
                    LoadingOverlay.hide()
                }
                print("[RecordHeaderBar] export error: \(err)")
            case .success(let exportURL):
                // Hide overlay immediately, then present preview on main
                DispatchQueue.main.async {
                    // Dismiss overlay first, then present preview to avoid presenting over a disappearing VC
                    LoadingOverlay.hide {
                        let previewVC = UIHostingController(rootView: CapcutEditorView(url: exportURL))
                        previewVC.modalPresentationStyle = .overFullScreen
                        previewVC.isModalInPresentation = true
                        previewVC.view.backgroundColor = .black
                        UIApplication.shared.topMostViewController()?.present(previewVC, animated: true)
                    }
                }

                // Save highlight (fire-and-forget)
                Task.detached { [level] in
                    do {
                        let asset = AVURLAsset(url: exportURL)
                        let gen = AVAssetImageGenerator(asset: asset)
                        gen.appliesPreferredTrackTransform = true
                        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
                        let imageRef = try? gen.copyCGImage(at: time, actualTime: nil)
                        let jpegData = imageRef.flatMap { UIImage(cgImage: $0).jpegData(compressionQuality: 0.8) } ?? Data()
                        let title = "Level \(level) Highlight Reel"
                        let model = try await HighlightReelRepository.shared.create(fromExportURL: exportURL, thumbnail: jpegData, level: level, runId: runId, title: title, cameraSource: nil)
                        print("[RecordHeaderBar] highlight saved id=\(model.id)")
                    } catch {
                        print("[RecordHeaderBar] highlight save error: \(error)")
                    }
                }
            }
        }
    }

    private func openCameraForNewMedia() {
        guard currentRunId != nil else { return }
        let vc = UIHostingController(rootView: CameraSheet { media in
            guard let media = media else { return }
            let stepKey = "date_plan"
            var duration: Int? = nil
            if media.type == .video {
                let asset = AVURLAsset(url: media.localURL)
                duration = Int(CMTimeGetSeconds(asset.duration).rounded())
            }
            _ = MediaUploadManager.shared.upload(media: media, step: stepKey, progress: { _ in }, completion: { result in
                if case .success(let url) = result {
                    let persisted = CapturedMedia(localURL: media.localURL, type: media.type, caption: media.caption, remoteURL: url, uploadProgress: 1.0)
                    let missionIndex = items.count
                    JourneyPersistence.shared.saveNode(step: stepKey, missionIndex: missionIndex, media: persisted, durationSeconds: duration)
                    NotificationCenter.default.post(name: Notification.Name("missionProgressUpdated"), object: nil)
                    reload()
                }
            })
        })
        UIApplication.shared.topMostViewController()?.present(vc, animated: true)
    }
}


// Thumbnail view for video bubbles using first-second frame
fileprivate struct VideoThumbBubble: View {
    let url: URL
    @State private var image: UIImage? = nil
    var body: some View {
        Group {
            if let img = image { Image(uiImage: img).resizable().scaledToFill() }
            else { Color.gray.opacity(0.2) }
        }
        .onAppear { generateThumb() }
    }
    private func generateThumb() {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 1, preferredTimescale: 600)
        DispatchQueue.global(qos: .userInitiated).async {
            if let cg = try? gen.copyCGImage(at: time, actualTime: nil) {
                let img = UIImage(cgImage: cg)
                DispatchQueue.main.async { self.image = img }
            }
        }
    }
}

