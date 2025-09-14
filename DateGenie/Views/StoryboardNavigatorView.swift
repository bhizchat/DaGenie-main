import SwiftUI
import UIKit
import FirebaseFirestore
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

struct StoryboardNavigatorView: View {
    @State var plan: StoryboardPlan
    @State private var isRendering: Bool = false
    @State private var index: Int = 0
    @State private var scriptHeight: CGFloat = 140
    @State private var actionHeight: CGFloat = 96
    @State private var animationHeight: CGFloat = 96
    @State private var speechHeight: CGFloat = 96
    @State private var focusAction: Bool = false
    @State private var focusAnimation: Bool = false
    @State private var focusSpeech: Bool = false
    @State private var isGenerating: Bool = false
    @State private var showDone: Bool = false
    
    // Scene updates listener
    @State private var scenesListener: ListenerRegistration? = nil
    @State private var processedSceneIds: Set<String> = []
    // Persistence context
    @State private var storyboardId: String? = nil
    @State private var projectId: String? = nil
    @Environment(\.dismiss) private var dismiss

    private var scene: PlanScene { plan.scenes[index] }

    private func sectionEditor(title: String, isEditing: Binding<Bool>, text: Binding<String>, height: Binding<CGFloat>, limit: Int) -> some View {
        let count = wordCount(text.wrappedValue)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundColor(.black)
                Spacer()
                Button("Edit") { isEditing.wrappedValue = true }
                    .font(.system(size: 13, weight: .semibold))
            }
            GeometryReader { geo in
                let width = geo.size.width - 16
                GrowingTextViewFixed(
                    text: text,
                    height: height,
                    availableWidth: width,
                    minHeight: 72,
                    maxHeight: 200,
                    trailingInset: 0,
                    isFirstResponder: isEditing
                )
                .frame(height: min(max(72, height.wrappedValue), 200))
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.08)))
                .overlay(alignment: .bottomTrailing) {
                    Text("\(count)/\(limit)")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(count <= limit ? Color.gray : Color.red)
                        .padding(.trailing, 6)
                        .padding(.bottom, 2)
                }
            }
            .frame(minHeight: 72)
        }
    }

    private func composeScript(for s: PlanScene) -> String {
        let label = s.speechType ?? "Dialogue"
        let a = s.action?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sp = s.speech?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let an = s.animation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var lines: [String] = []
        if !a.isEmpty { lines.append("Action: \(a)") }
        if !sp.isEmpty { lines.append("\(label): \(sp)") }
        if !an.isEmpty { lines.append("Animation: \(an)") }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                ZStack {
                    HStack { Button(action: { dismiss() }) { Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).foregroundColor(.black).padding(8) }; Spacer() }
                    HStack { Spacer(); Text("STORYBOARD").font(.system(size: 22, weight: .heavy)).foregroundColor(.black); Image("storyboard").resizable().renderingMode(.original).scaledToFit().frame(width: 28, height: 28); Spacer() }
                }

                // Vertical scenes list
                VStack(spacing: 22) {
                    ForEach(plan.scenes.indices, id: \.self) { i in
                        SceneEditorRow(scene: $plan.scenes[i], isLast: i == plan.scenes.count - 1)
                    }
                }
            .padding(.horizontal, 16)

                // Final CTA on last scene
            VStack(spacing: 0) {
                    Button(action: generateAll) {
                        Image("createanimation").resizable().renderingMode(.original).scaledToFit().frame(height: 104)
                }
                .disabled(isGenerating)
                .padding(.vertical, 12)
            }
            .padding(.horizontal, 24)
            .background(RoundedRectangle(cornerRadius: 25).fill(Color.white))
            .shadow(color: Color.black.opacity(0.08), radius: 1, x: 0, y: 1)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        }
        .background(Color(hex: 0xF7B451).ignoresSafeArea())
        .task { await renderIfNeeded() }
        .overlay(alignment: .center) {
            if isGenerating { ZStack { Color.black.opacity(0.25).ignoresSafeArea(); ProgressView("Preparing…").padding(16).background(RoundedRectangle(cornerRadius: 12).fill(Color.white)) } }
        }
        .hideKeyboardOnTap()
        .alert("Generation failed", isPresented: $showDone) { Button("OK", role: .cancel) {} } message: { Text("Couldn't start video generation. Please try again.") }
    }
    // Close body

    fileprivate func next() { if index < plan.scenes.count-1 { index += 1 } }
    fileprivate func prev() { if index > 0 { index -= 1 } }

    fileprivate func renderIfNeeded() async {
        // Render scenes one-by-one; update UI after each successful image
        guard !isRendering else { return }
        isRendering = true
        defer { isRendering = false }
        var safety = 0
        while plan.scenes.contains(where: { ($0.imageUrl ?? "").isEmpty }) {
            if let rendered = try? await RenderService.shared.render(plan: plan) {
                // Update both the source-of-truth state and our local copy used in the loop
                await MainActor.run { self.plan = rendered }
                plan = rendered
            } else {
                // Do not abort entire loop on transient failure; yield and retry next
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
            safety += 1
            if safety > (plan.scenes.count + 2) { break }
        }
        await persistStoryboardIfNeeded()
    }

    fileprivate func persistStoryboardIfNeeded() async {
        // Save only once; require at least one generated image (partial saves allowed)
        guard storyboardId == nil else { return }
        let hasAtLeastOneImage = plan.scenes.contains { !($0.imageUrl ?? "").isEmpty }
        guard hasAtLeastOneImage else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            // Ensure a project exists
            if projectId == nil {
                let name = await ProjectsRepository.shared.nextNewVideoName()
                if let project = await ProjectsRepository.shared.create(userId: uid, name: name) {
                    self.projectId = project.id
                }
            }
            guard let pid = projectId else { return }
            let reqId = UUID().uuidString
            let idem = UUID().uuidString
            let sbId = try await StoryboardsRepository.shared.saveStoryboardSet(
                userId: uid,
                projectId: pid,
                plan: plan,
                requestId: reqId,
                idempotencyKey: idem,
                bumpVersion: true
            )
            self.storyboardId = sbId
            await ProjectsRepository.shared.attachStoryboardContext(userId: uid, projectId: pid, storyboardId: sbId, currentSceneIndex: 0, totalScenes: plan.scenes.count)
        } catch {
            print("[Storyboard] persist failed: \(error)")
        }
    }

    fileprivate func generateClip() {
        Task { @MainActor in
            // Ensure no text field retains focus; prevent keyboard from auto-showing
            focusAction = false
            focusAnimation = false
            focusSpeech = false
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            isGenerating = true
            do {
                // If storyboard is saved, enqueue via fast WAN flow
                if !FeatureFlags.disableProjectSaving,
                   let uid = Auth.auth().currentUser?.uid,
                   let sbId = storyboardId,
                   let pid = projectId {
                    let sceneId = String(format: "%04d", plan.scenes[index].index)
                    try await StoryboardsRepository.shared.enqueueSceneVideo(userId: uid, projectId: pid, storyboardId: sbId, sceneId: sceneId, provider: "wan", requestId: UUID().uuidString)
                    isGenerating = false
                    return
                }
                // Prepare scenes JSON (explicit steps to help type-checker)
                var scenesPayload: [[String: Any]] = []
                for s in plan.scenes {
                    let action = (s.action ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let animation = (s.animation ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let speechType = (s.speechType ?? "Dialogue")
                    let speech = (s.speech ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let accent = (extractAccent(from: speech) ?? "American")
                    let image = s.imageUrl ?? ""
                    let obj: [String: Any] = [
                        "index": s.index,
                        "action": action,
                        "animation": animation,
                        "speechType": speechType,
                        "speech": speech,
                        "accent": accent,
                        "imageUrl": image,
                    ]
                    scenesPayload.append(obj)
                }
                let modelName: String = "wan-video"
                let body: [String: Any] = [
                    "data": [
                        "character": plan.character.id,
                        "model": modelName,
                        "aspectRatio": plan.settings.aspectRatio,
                        // Send currently selected scene index so server can honor anchoring intent
                        "selectedIndex": plan.scenes[index].index,
                        "scenes": scenesPayload
                    ]
                ]
                print("[Storyboard] payload model=\(modelName) scenes=\(scenesPayload.count) firstImage=\(plan.scenes.first?.imageUrl ?? "<none>")")
                let url = URL(string: "https://us-central1-\(VoiceAssistantVM.projectId()).cloudfunctions.net/createStoryboardJobV2")!
                let json = try await callCallable(url: url, payload: body)
                let jobId = (json["result"] as? [String: Any])? ["jobId"] as? String ?? json["jobId"] as? String
                print("[Storyboard] job enqueued id=\(jobId ?? "<nil>")")
                if let jobId = jobId {
                    let startUrl = URL(string: "https://us-central1-\(VoiceAssistantVM.projectId()).cloudfunctions.net/startStoryboardJobV2")!
                    let startPayload: [String: Any] = ["data": ["jobId": jobId]]
                    _ = try? await callCallable(url: startUrl, payload: startPayload)
                    // Optional: background listener to auto-swap to final when ready
                    let db = Firestore.firestore()
                    db.collection("adJobs").document(jobId).addSnapshotListener { snap, _ in
                        guard let data = snap?.data() else { return }
                        let status = data["status"] as? String ?? ""
                        if status == "ready" {
                            if let urlStr = (data["finalVideoUrl"] as? String) ?? (data["videoUrl"] as? String) ?? (data["outputUrl"] as? String), let u = URL(string: urlStr) {
                                if !FeatureFlags.disableProjectSaving, let uid = Auth.auth().currentUser?.uid {
                                    Task {
                                        let name = await MainActor.run { ProjectsRepository.shared.nextNewVideoName() }
                                        if let project = await ProjectsRepository.shared.create(userId: uid, name: name) {
                                            await ProjectsRepository.shared.attachVideoURL(userId: uid, projectId: project.id, remoteURL: u)
                                            if let img = await ThumbnailGenerator.firstFrameFromRemote(url: u) ?? ThumbnailGenerator.firstFrame(for: u) {
                                                await ProjectsRepository.shared.uploadThumbnail(userId: uid, projectId: project.id, image: img)
                                            }
                                            NotificationCenter.default.post(name: Notification.Name("ActiveProjectIdCreated"), object: project.id)
                                        }
                                    }
                                }
                                NotificationCenter.default.post(name: .AdGenComplete, object: nil, userInfo: ["url": u])
                            }
                        }
                    }
                }

                // Immediately open the Capcut-style editor in generating state (single instance)
                if let vc = UIApplication.shared.topMostViewController() {
                    if let _ = vc.presentedViewController as? UIHostingController<CapcutEditorView> {
                        NotificationCenter.default.post(name: .AdGenBegin, object: nil)
                    } else {
                        let host = UIHostingController(rootView: CapcutEditorView(url: URL(fileURLWithPath: "/dev/null"), initialGenerating: true))
                        vc.present(host, animated: true) {
                            NotificationCenter.default.post(name: .AdGenBegin, object: nil)
                        }
                    }
                }

                // No extra listener needed here for veoDirect path
            } catch {
                print("[Storyboard] createStoryboardJob error: \(error.localizedDescription)")
                if let top = UIApplication.shared.topMostViewController() {
                    top.presentedViewController?.dismiss(animated: true)
                }
                showDone = true
            }
            isGenerating = false
        }
    }

    fileprivate func generateAll() {
        Task { @MainActor in
            isGenerating = true
            defer { isGenerating = false }
            do {
                // Ensure storyboard is persisted
                if storyboardId == nil { await persistStoryboardIfNeeded() }
                guard let uid = Auth.auth().currentUser?.uid, let sbId = storyboardId, let pid = projectId else { return }
                // Enqueue all scenes with images sequentially with spacing
                let spacing = 6 // base seconds between scheduled tasks (reduced from 15)
                let runId = Int(Date().timeIntervalSince1970)
                let scenesWithImages = plan.scenes.enumerated().filter { !($0.element.imageUrl ?? "").isEmpty }
                for (iTuple, pair) in scenesWithImages.enumerated() {
                    let i = iTuple
                    let s = pair.element
                    let sid = String(format: "%04d", s.index)
                    // add small jitter (0..3s) to avoid micro-bursts
                    let jitter = Int.random(in: 0...3)
                    try await StoryboardsRepository.shared.enqueueSceneVideo(
                        userId: uid,
                        projectId: pid,
                        storyboardId: sbId,
                        sceneId: sid,
                        provider: "wan",
                        requestId: UUID().uuidString,
                        delaySeconds: i * spacing + jitter,
                        nameSuffix: "r\(runId)-\(i)"
                    )
                }

                // Open the editor; compute generating state from Firestore and let editor rehydrate timeline
                if let vc = UIApplication.shared.topMostViewController() {
                    let host = UIHostingController(rootView: CapcutEditorView(url: URL(fileURLWithPath: "/dev/null"), initialGenerating: false))
                    vc.present(host, animated: true)
                }

                // Start listening for scene completion updates and append clips as they arrive
                startScenesListener(uid: uid, projectId: pid, storyboardId: sbId)
            } catch {
                print("[Storyboard] generateAll failed: \(error)")
                showDone = true
            }
        }
    }

    fileprivate func startScenesListener(uid: String, projectId: String, storyboardId: String) {
        // Remove existing listener if any
        scenesListener?.remove()
        processedSceneIds.removeAll()
        let coll = Firestore.firestore()
            .collection("users").document(uid)
            .collection("projects").document(projectId)
            .collection("storyboards").document(storyboardId)
            .collection("scenes")
            .order(by: "index")
        scenesListener = coll.addSnapshotListener { snap, _ in
            guard let docs = snap?.documents else { return }
            for doc in docs {
                let data = doc.data()
                let video = data["video"] as? [String: Any]
                let status = (video?["status"] as? String) ?? (data["videoStatus"] as? String) ?? ""
                guard status.lowercased() == "done" else { continue }
                guard let urlStr = video?["outputUrl"] as? String, let url = URL(string: urlStr) else { continue }
                if !processedSceneIds.contains(doc.documentID) {
                    processedSceneIds.insert(doc.documentID)
                    let doneCount = processedSceneIds.count
                    let totalCount = plan.scenes.count
                    NotificationCenter.default.post(name: .AdGenComplete, object: nil, userInfo: ["url": url, "doneCount": doneCount, "totalCount": totalCount])
                }
            }
        }
    }
}

// MARK: - Scene row (vertical)
private struct SceneEditorRow: View {
    @Binding var scene: PlanScene
    let isLast: Bool

    @State private var actionHeight: CGFloat = 96
    @State private var animationHeight: CGFloat = 96
    @State private var speechHeight: CGFloat = 96
    @State private var focusAction: Bool = false
    @State private var focusAnimation: Bool = false
    @State private var focusSpeech: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Color.gray.opacity(0.2))
                if let urlStr = scene.imageUrl, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { ph in
                        switch ph {
                        case .empty: ProgressView()
                        case .success(let img): img.resizable().scaledToFit()
                        case .failure: Image(systemName: "photo").resizable().scaledToFit().padding(30).foregroundColor(.black.opacity(0.4))
                        @unknown default: EmptyView()
                        }
                    }
                    .id(scene.imageUrl ?? "")
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                } else {
                    Text("Rendering…").foregroundColor(.black.opacity(0.5))
                }
            }
            .frame(height: 300)

            Text("SCRIPT").font(.system(size: 18, weight: .heavy)).foregroundColor(.black)

            VStack(alignment: .leading, spacing: 18) {
                // Action
                GrowingField(title: "Action", text: Binding(get: { scene.action ?? "" }, set: { v in
                    scene.action = limitWords(v, cap: 20)
                }), isEditing: $focusAction, height: $actionHeight)
                .onChange(of: scene.action ?? "") { _ in
                    DispatchQueue.main.async { scene.script = composeForRow(scene) }
                }

                // Animation
                GrowingField(title: "Animation", text: Binding(get: { scene.animation ?? "" }, set: { v in
                    scene.animation = limitWords(v, cap: 20)
                }), isEditing: $focusAnimation, height: $animationHeight)
                .onChange(of: scene.animation ?? "") { _ in
                    DispatchQueue.main.async { scene.script = composeForRow(scene) }
                }

                // Dialogue/Narration
                let label = (scene.speechType ?? "Dialogue")
                GrowingField(title: label, text: Binding(get: { scene.speech ?? "" }, set: { v in
                    let trimmed = limitWords(v, cap: 20); scene.speech = trimmed; if scene.speechType == nil { scene.speechType = "Dialogue" }
                }), isEditing: $focusSpeech, height: $speechHeight)
                .onChange(of: scene.speech ?? "") { _ in
                    DispatchQueue.main.async { scene.script = composeForRow(scene) }
                }

                // Single model (WAN); Veo removed from UI
            }
        }
    }

    private func composeForRow(_ s: PlanScene) -> String {
        let label = s.speechType ?? "Dialogue"
        let a = s.action?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sp = s.speech?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let an = s.animation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var lines: [String] = []
        if !a.isEmpty { lines.append("Action: \(a)") }
        if !sp.isEmpty { lines.append("\(label): \(sp)") }
        if !an.isEmpty { lines.append("Animation: \(an)") }
        return lines.joined(separator: "\n")
    }
}

private struct GrowingField: View {
    let title: String
    @Binding var text: String
    @Binding var isEditing: Bool
    @Binding var height: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(title).font(.system(size: 14, weight: .heavy)).foregroundColor(.black); Spacer(); Button("Edit") { isEditing = true }.font(.system(size: 13, weight: .semibold)) }
            GeometryReader { geo in
                let width = geo.size.width - 16
                GrowingTextViewFixed(text: $text, height: $height, availableWidth: width, minHeight: 72, maxHeight: 200, trailingInset: 0, isFirstResponder: $isEditing)
                    .frame(height: min(max(72, height), 200))
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.08)))
            }.frame(minHeight: 72)
        }
    }
}
fileprivate func wordCount(_ s: String) -> Int {
    s.split { !$0.isLetter && !$0.isNumber && $0 != "-" }.count
}


// Simple callable invoker reused here to talk to Cloud Functions v2 onCall endpoints
fileprivate func callCallable(url: URL, payload: [String: Any]) async throws -> [String: Any] {
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.addValue("application/json", forHTTPHeaderField: "Content-Type")
    // Auth optional for now; if available, attach Firebase ID token
    if let token = try? await VoiceAssistantVM.currentIdTokenStatic() {
        req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    req.httpBody = try JSONSerialization.data(withJSONObject: payload)
    let (data, resp) = try await URLSession.shared.data(for: req)
    guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        let body = String(data: data, encoding: .utf8) ?? "<no body>"
        throw NSError(domain: "callCallable", code: (resp as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: body])
    }
    let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    return json ?? [:]
}


fileprivate func limitWords(_ s: String, cap: Int) -> String {
    var words: [Substring] = s.split { !$0.isLetter && !$0.isNumber && $0 != "-" }
    if words.count <= cap { return s }
    // Reconstruct using original spacing as best-effort by joining with spaces
    let limited = words.prefix(cap).joined(separator: " ")
    return String(limited)
}

fileprivate func ensureAccentSuffix(_ s: String) -> String {
    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return trimmed }
    if trimmed.contains("(") && trimmed.contains(")") { return trimmed }
    return trimmed + " (American Accent)"
}

// Extract an accent token from text like "... (American Accent)"; returns nil if none
fileprivate func extractAccent(from text: String) -> String? {
    let t = text
    guard let l = t.lastIndex(of: "(") , let r = t.lastIndex(of: ")"), l < r else { return nil }
    let inside = String(t[t.index(after: l)..<r]).trimmingCharacters(in: .whitespacesAndNewlines)
    if inside.lowercased().contains("accent") {
        return inside.replacingOccurrences(of: "Accent", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return nil
}

// Veo model and picker removed; WAN is the only path
