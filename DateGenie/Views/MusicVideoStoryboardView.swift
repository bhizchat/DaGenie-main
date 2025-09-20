import SwiftUI
import AVFoundation
import FirebaseFirestore
import FirebaseAuth

/// Lightweight variant of storyboard navigator tailored for music videos.
/// Shows the avatar preview (reference image for now), simple audio player, and a CTA to generate storyboard.
struct MusicVideoStoryboardView: View {
    let referenceImage: UIImage
    let audioURL: URL
    let settingId: String

    @EnvironmentObject var userRepo: UserRepository
    @State private var player: AVPlayer = AVPlayer()
    @State private var isGeneratingStoryboard: Bool = false
    @State private var storyboard: StoryboardPlan? = nil
    @State private var isUploading: Bool = false
    @State private var projectId: String? = nil
    @State private var storyboardId: String? = nil
    @State private var listener: ListenerRegistration? = nil
    @State private var avatarUrl: String? = nil
    @State private var isGeneratingAvatar: Bool = false
    @State private var openStoryboard: Bool = false
    @State private var openIdea: Bool = false
    @State private var audioGsPath: String? = nil
    @State private var referenceUrl: String? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ZStack {
                    HStack { Spacer() }
                    Text("CREATE MUSIC VIDEO")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundColor(.black)
                }

                // Avatar preview area
                if let a = avatarUrl, let url = URL(string: a) {
                    AsyncImage(url: url) { ph in
                        switch ph {
                        case .empty: Text("Rendering...").font(.system(size: 16, weight: .heavy)).foregroundColor(.black)
                        case .success(let img): img.resizable().scaledToFit()
                        case .failure: Image(uiImage: referenceImage).resizable().scaledToFit()
                        @unknown default: Image(uiImage: referenceImage).resizable().scaledToFit()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .cornerRadius(16)
                    .padding(.horizontal, 24)
                } else if isGeneratingAvatar {
                    Text("Rendering...")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 260)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.001)))
                        .padding(.horizontal, 24)
                } else {
                    Image(uiImage: referenceImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .cornerRadius(16)
                        .padding(.horizontal, 24)
                }

                // Simple audio scrubber
                VStack(alignment: .leading, spacing: 8) {
                    AudioScrubber(player: player)
                        .frame(height: 52)
                }
                .padding(.horizontal, 24)

                // NEXT button: go to Idea (assets ready first)
                Button(action: { Task { await ensureUploadsAndAvatarThenOpenIdea() } }) {
                    Text("NEXT")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                        .background(Color.black)
                        .cornerRadius(14)
                        .padding(.horizontal, 24)
                }

                // Hidden link driven by openIdea flag
                NavigationLink(isActive: $openIdea) {
                    if let uid = Auth.auth().currentUser?.uid,
                       let pid = projectId,
                       let audio = audioGsPath,
                       let ref = (avatarUrl ?? referenceUrl) {
                        MusicVideoIdeaView(
                            uid: uid,
                            projectId: pid,
                            settingId: settingId,
                            referenceImageUrl: ref,
                            audioGsPath: audio,
                            promptKit: promptKitFor(settingId: settingId)
                        )
                    } else { EmptyView() }
                } label: { EmptyView() }

                Spacer().frame(height: 16)
            }
        }
        .background(Color(hex: 0xF7B451).ignoresSafeArea())
        .onAppear {
            configurePlayer()
            // Kick off avatar generation immediately so the user lands on a stylized preview
            Task { await generateAvatarIfNeeded() }
        }
        .overlay(alignment: .center) {
            if isGeneratingStoryboard {
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    Text("Generating storyboard…")
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                }
            }
        }
    }

    private func configurePlayer() {
        player.replaceCurrentItem(with: AVPlayerItem(url: audioURL))
        player.pause()
    }

    private func generateStoryboard() async {
        guard !isGeneratingStoryboard else { return }
        isGeneratingStoryboard = true
        defer { isGeneratingStoryboard = false }
        do {
            guard let uid = Auth.auth().currentUser?.uid else { return }
            // Upload assets and create a project
            let imgData = referenceImage.jpegData(compressionQuality: 0.92) ?? Data()
            let created = try await MusicVideoRepository.shared.createProjectAndUpload(userId: uid, referenceImageData: imgData, audioURL: audioURL)
            projectId = created.projectId

            // Ensure we have an avatar; if onAppear failed to fetch, try once here
            if avatarUrl == nil {
                do {
                    let prompt = "make this a Highly stylized 3D render, cartoonish character portrait, exaggerated features, with a bold high-contrast color scheme, smooth CGI animation look"
                    let avatar = try await MusicVideoRepository.shared.generateAvatar(from: referenceImage, prompt: prompt)
            await MainActor.run {
                self.avatarUrl = avatar
                if (self.userRepo.profile.photoURL ?? "").isEmpty {
                    Task { await self.userRepo.updatePhotoURL(avatar) }
                }
            }
                } catch {
                    print("[MusicVideo] avatar generation failed (fallback): \(error)")
                    await MainActor.run { self.avatarUrl = created.referenceUrl }
                }
            }

            // Call backend to generate storyboard and enqueue scenes (WAN)
            let gcpId = (Bundle.main.object(forInfoDictionaryKey: "FirebaseProjectID") as? String) ?? "dategenie-dev"
            let url = URL(string: "https://us-central1-\(gcpId).cloudfunctions.net/generateMusicStoryboard")!
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.addValue("application/json", forHTTPHeaderField: "Content-Type")
            // Include prompt kit to guide storyboard generation
            let body: [String: Any] = [
                "uid": uid,
                "projectId": created.projectId,
                "settingId": settingId,
                "referenceImageUrl": avatarUrl ?? created.referenceUrl,
                "audioGsPath": created.audioGsPath,
                "promptKit": promptKitFor(settingId: settingId),
            ]
            req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
            let (data, _) = try await URLSession.shared.data(for: req)
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let sbId = obj["storyboardId"] as? String {
                storyboardId = sbId
                listenToStoryboard(uid: uid, projectId: created.projectId, storyboardId: sbId)
            }

            // Present idea capture step instead of auto‑routing to editor
            await MainActor.run { openIdea = true }
        } catch {
            print("[MusicVideo] generateStoryboard error: \(error)")
        }
    }

    private func generateAvatarIfNeeded() async {
        guard avatarUrl == nil && !isGeneratingAvatar else { return }
        isGeneratingAvatar = true
        defer { isGeneratingAvatar = false }
        do {
            let prompt = "make this a Highly stylized 3D render, cartoonish character portrait, exaggerated features, with a bold high-contrast color scheme, smooth CGI animation look"
            let avatar = try await MusicVideoRepository.shared.generateAvatar(from: referenceImage, prompt: prompt)
            await MainActor.run {
                self.avatarUrl = avatar
                if (self.userRepo.profile.photoURL ?? "").isEmpty {
                    Task { await self.userRepo.updatePhotoURL(avatar) }
                }
            }
        } catch {
            // Keep original image if avatar fails; storyboard step will handle fallback as well
            print("[MusicVideo] avatar generation onAppear failed: \(error)")
        }
    }

    // Ensure project upload (reference + audio) and avatar before opening Idea
    private func ensureUploadsAndAvatarThenOpenIdea() async {
        guard !isUploading else { return }
        isUploading = true
        defer { isUploading = false }
        do {
            if projectId == nil || audioGsPath == nil || referenceUrl == nil {
                guard let uid = Auth.auth().currentUser?.uid else { return }
                let imgData = referenceImage.jpegData(compressionQuality: 0.92) ?? Data()
                let created = try await MusicVideoRepository.shared.createProjectAndUpload(userId: uid, referenceImageData: imgData, audioURL: audioURL)
                await MainActor.run {
                    self.projectId = created.projectId
                    self.audioGsPath = created.audioGsPath
                    self.referenceUrl = created.referenceUrl
                }
            }
            await generateAvatarIfNeeded()
            await MainActor.run { self.openIdea = true }
        } catch {
            print("[MusicVideo] ensureUploadsAndAvatarThenOpenIdea error: \(error)")
        }
    }

    private func promptKitFor(settingId: String) -> [String: Any] {
        guard let cat = MusicVideoSettingsCatalog.all.first(where: { $0.id == settingId }) else { return [:] }
        return [
            "worldPillars": cat.promptKit.worldPillars,
            "formatBeats": cat.promptKit.formatBeats,
            "setPacks": cat.promptKit.setPacks,
            "loopGags": cat.promptKit.loopGags,
            "cameraGrammar": cat.promptKit.cameraGrammar,
            "fpsHint": cat.promptKit.fpsHint,
            "bio": cat.bio,
            "environment": cat.environment,
            "palette": cat.palette,
        ]
    }

    private func listenToStoryboard(uid: String, projectId: String, storyboardId: String) {
        listener?.remove()
        let db = Firestore.firestore()
        let base = db.collection("users").document(uid).collection("projects").document(projectId).collection("storyboards").document(storyboardId).collection("scenes")
        listener = base.order(by: "index").addSnapshotListener { snap, _ in
            guard let docs = snap?.documents else { return }
            var scenes: [PlanScene] = []
            for d in docs {
                let data = d.data()
                let idx = (data["index"] as? Int) ?? 0
                let action = data["action"] as? String
                let image = data["imageUrl"] as? String
                let video = (data["video"] as? [String: Any])
                let status = (video?["status"] as? String) ?? "idle"
                let prompt = action ?? ""
                var s = PlanScene(index: idx, prompt: prompt, script: prompt, durationSec: 3.0, wordsPerSec: nil, wordBudget: nil, imageUrl: image, action: action, speechType: nil, speech: nil, animation: nil, speakerSlot: nil)
                // Reuse animation field to reflect status for now
                s.animation = status
                scenes.append(s)
            }
            scenes.sort { $0.index < $1.index }
            self.storyboard = StoryboardPlan(character: PlanCharacter(id: "user"), settings: PlanSettings(aspectRatio: "9:16", style: settingId, camera: nil), scenes: scenes, referenceImageUrls: storyboard?.referenceImageUrls)
        }
    }
}

// MARK: - Music Video Scenes Editor (Action + Animation only)
private struct ScenesEditor: View {
    @Binding var storyboard: StoryboardPlan?

    var body: some View {
        if let sb = storyboard {
            VStack(spacing: 14) {
                ForEach(Array(sb.scenes.enumerated()), id: \.offset) { idx, _ in
                    MVSceneEditorRow(scene: Binding(get: { storyboard!.scenes[idx] }, set: { storyboard!.scenes[idx] = $0 }))
                        .padding(.horizontal, 24)
                }
            }
        }
    }
}

private struct MVSceneEditorRow: View {
    @Binding var scene: PlanScene
    @State private var actionText: String = ""
    @State private var animationText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(String(format: "#%02d", scene.index)).font(.system(size: 14, weight: .heavy)); Spacer() }
            if let urlStr = scene.imageUrl, let url = URL(string: urlStr), !urlStr.isEmpty {
                AsyncImage(url: url) { ph in
                    switch ph {
                    case .empty: ProgressView()
                    case .success(let img): img.resizable().scaledToFit()
                    case .failure: Image(systemName: "photo").resizable().scaledToFit().padding(30).foregroundColor(.black.opacity(0.4))
                    @unknown default: EmptyView()
                    }
                }
                .frame(maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // Action (keep)
            VStack(alignment: .leading, spacing: 6) {
                Text("Action").font(.system(size: 14, weight: .heavy))
                TextEditor(text: $actionText)
                    .frame(height: 72)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
            }

            // Animation (bring back)
            VStack(alignment: .leading, spacing: 6) {
                Text("Animation").font(.system(size: 14, weight: .heavy))
                TextEditor(text: $animationText)
                    .frame(height: 72)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
            }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
        .onAppear {
            actionText = scene.action ?? ""
            animationText = scene.animation ?? ""
        }
        .onChange(of: actionText) { newVal in
            scene.action = limitWordsMV(newVal, cap: 24)
        }
        .onChange(of: animationText) { newVal in
            scene.animation = limitWordsMV(newVal, cap: 24)
        }
    }
}

private func limitWordsMV(_ s: String, cap: Int) -> String {
    var words: [Substring] = s.split { !$0.isLetter && !$0.isNumber && $0 != "-" }
    if words.count <= cap { return s }
    let limited = words.prefix(cap).joined(separator: " ")
    return String(limited)
}


private struct AudioScrubber: View {
    let player: AVPlayer
    @State private var duration: Double = 0
    @State private var current: Double = 0
    @State private var isDragging: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button(action: toggle) {
                    Image(systemName: player.timeControlStatus == .playing ? "pause.fill" : "play.fill")
                        .foregroundColor(.black)
                }
                Slider(value: Binding(get: { current }, set: { newVal in
                    current = newVal
                    if isDragging { seek(to: newVal) }
                }), in: 0...max(duration, 0.001))
                Text(String(format: "%02d:%02d", Int(current) / 60, Int(current) % 60))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.black)
            }
        }
        .onAppear { setupObservers() }
        .onDisappear { NotificationCenter.default.removeObserver(self) }
        .gesture(DragGesture(minimumDistance: 0).onChanged { _ in isDragging = true }.onEnded { _ in isDragging = false })
    }

    private func setupObservers() {
        if let item = player.currentItem {
            duration = CMTimeGetSeconds(item.asset.duration)
        }
        player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main) { t in
            if !isDragging { current = CMTimeGetSeconds(t) }
        }
    }

    private func toggle() {
        if player.timeControlStatus == .playing { player.pause() } else { player.play() }
    }

    private func seek(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }
}


