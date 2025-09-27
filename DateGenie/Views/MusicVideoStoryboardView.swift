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
    @Environment(\.dismiss) private var navDismiss
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
    @State private var audioDurationSec: Double? = nil
    @State private var showAvatarEdit: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ZStack {
                    HStack {
                        Button(action: { /* no-op back hidden here */ }) { EmptyView() }
                        Spacer()
                    }
                    Text("Tap to Edit your Avatar")
                        .font(.system(size: 26, weight: .heavy))
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
                    .contentShape(Rectangle())
                    .onTapGesture { showAvatarEdit = true }
                    .overlay(alignment: .topTrailing) {
                        Button(action: { UIApplication.shared.topMostViewController()?.dismiss(animated: true) }) {
                            ZStack {
                                Circle().fill(Color.white).frame(width: 24, height: 24)
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.black)
                            }
                        }
                        .padding(.top, 8)
                        .padding(.trailing, 13)
                    }
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
                        .contentShape(Rectangle())
                        .onTapGesture { showAvatarEdit = true }
                }

                // Helper bullets
                VStack(alignment: .leading, spacing: 12) {
                    bullet("Your avatar is the star of your music video and appears in every scene.")
                    bullet("Tap the avatar to customize: change your fit or add accessories (chains, durag, glasses).")
                    bullet("Edits apply throughout music video, if you don't like you avatar change your reference photo")
                }
                .padding(.horizontal, 24)

                // Select Avatar button -> go to upload song step
                Button(action: { openUploadSong() }) {
                    Text(isGeneratingAvatar || isUploading ? "Selecting Avatar..." : "SELECT AVATAR")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                        .background((isGeneratingAvatar || isUploading) ? Color.composerGray : Color.black)
                        .cornerRadius(32)
                        .padding(.horizontal, 24)
                }
                .disabled(isGeneratingAvatar)

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
                            audioDurationSec: audioDurationSec ?? 0,
                            promptKit: promptKitFor(settingId: settingId)
                        )
                    } else { EmptyView() }
                } label: { EmptyView() }

                Spacer().frame(height: 16)
            }
        }
        .background(Color(hex: 0xF3B529).ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            let asset = AVURLAsset(url: audioURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
            self.audioDurationSec = CMTimeGetSeconds(asset.duration)
            // Kick off avatar generation immediately so the user lands on a stylized preview
            Task { await generateAvatarIfNeeded() }
        }
        // Removed loading overlay by request
        .overlay(alignment: .topLeading) {
            Button(action: { navDismiss() }) {
                Image("back_arrow")
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(width: 28, height: 28)
            }
            .padding(.leading, 6)
            .padding(.top, 6)
        }
        .sheet(isPresented: $showAvatarEdit) {
            AvatarEditSheet(referenceImage: referenceImage, currentAvatarUrl: avatarUrl, onDismiss: { showAvatarEdit = false }, onRegenerate: { prompt, done in
                Task {
                    let ok = await regenerateAvatar(prompt: prompt)
                    await MainActor.run { done(ok) }
                }
            })
        }
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
            let url = URL(string: "https://us-central1-\(gcpId).cloudfunctions.net/generateMusicStoryboardV2")!
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
            "setPacks": cat.promptKit.setPacks,
            "loopGags": cat.promptKit.loopGags,
            "cameraGrammar": cat.promptKit.cameraGrammar,
            "fpsHint": cat.promptKit.fpsHint,
            "bio": cat.bio,
            "environment": cat.environment,
            "palette": cat.palette,
            "storyTemplates": cat.promptKit.storyTemplates,
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

    // MARK: - Navigation to Upload Song
    private func openUploadSong() {
        // Present a lightweight upload-song screen using a hosting controller
        let host = UIHostingController(rootView: MVUploadAudioStepView(referenceImage: referenceImage, settingId: settingId, initialAvatarUrl: avatarUrl))
        host.modalPresentationStyle = .overFullScreen
        UIApplication.shared.topMostViewController()?.present(host, animated: true)
    }

    // MARK: - Helpers
    @ViewBuilder
    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").font(.system(size: 18, weight: .heavy))
            Text(text).font(.system(size: 15, weight: .semibold)).foregroundColor(.black)
            Spacer()
        }
    }

    // MARK: - Avatar regenerate
    private func regenerateAvatar(prompt: String?) async -> Bool {
        isGeneratingAvatar = true
        defer { isGeneratingAvatar = false }
        do {
            let newUrl: String
            if let existing = avatarUrl, !existing.isEmpty {
                newUrl = try await MusicVideoRepository.shared.generateAvatar(referenceImageUrl: existing, prompt: prompt)
            } else {
                newUrl = try await MusicVideoRepository.shared.generateAvatar(from: referenceImage, prompt: prompt)
            }
            await MainActor.run {
                self.avatarUrl = newUrl
                self.showAvatarEdit = false
            }
            return true
        } catch {
            print("[Avatar] regenerate failed: \(error.localizedDescription)")
            return false
        }
    }
}

// MARK: - Avatar Edit Sheet
private struct AvatarEditSheet: View {
    let referenceImage: UIImage
    let currentAvatarUrl: String?
    let onDismiss: () -> Void
    let onRegenerate: (String?, @escaping (Bool) -> Void) -> Void

    @State private var prompt: String = ""
    @State private var isRegenerating: Bool = false

    var body: some View {
        VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.15)).frame(height: 1).opacity(0)
            if let a = currentAvatarUrl, let url = URL(string: a), !a.isEmpty {
                AsyncImage(url: url) { ph in
                    switch ph {
                    case .empty: ProgressView()
                    case .success(let img): img.resizable().scaledToFit()
                    case .failure: Image(uiImage: referenceImage).resizable().scaledToFit()
                    @unknown default: Image(uiImage: referenceImage).resizable().scaledToFit()
                    }
                }
                .frame(maxHeight: 240)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                Image(uiImage: referenceImage).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 14))
            }

            GeometryReader { geo in
                let width = geo.size.width - 16
                GrowingTextViewFixed(text: $prompt, height: .constant(120), availableWidth: width, minHeight: 96, maxHeight: 200, trailingInset: 0, isFirstResponder: .constant(true))
                    .frame(height: 140)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.08)))
            }
            .frame(height: 160)

            HStack {
                Button("Cancel") { if !isRegenerating { onDismiss() } }
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.2)))
                Spacer()
                Button(action: {
                    guard !isRegenerating else { return }
                    isRegenerating = true
                    onRegenerate(prompt.trimmingCharacters(in: .whitespacesAndNewlines)) { ok in
                        if !ok {
                            // Show a clear failure toast inline
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    }
                }) {
                    Text(isRegenerating ? "Regenerating Avatar…" : "Regenerate Avatar")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(isRegenerating ? Color.gray : Color.blue))
                }
                .disabled(isRegenerating)
            }
            .overlay(alignment: .center) {
                if isRegenerating {
                    ZStack {
                        Color.black.opacity(0.4).ignoresSafeArea()
                        ProgressView("Regenerating Avatar…")
                            .padding(16)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                    }
                }
            }
        }
        .padding(16)
        .overlay(alignment: .bottom) {
            if !isRegenerating && prompt.lowercased().contains("ovo") {
                Text("Your edit may be blocked due to sensitive brand terms.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.7)))
                    .padding(.bottom, 8)
            }
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


