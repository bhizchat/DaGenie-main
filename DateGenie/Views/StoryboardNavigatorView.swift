import SwiftUI
import UIKit
import FirebaseFirestore
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

struct StoryboardNavigatorView: View {
    @AppStorage("hasSeenStoryboardOnboarding") private var hasSeenStoryboardOnboarding: Bool = false
    @State var plan: StoryboardPlan
    @State private var isRendering: Bool = false
    @State private var index: Int = 0
    @State private var scriptHeight: CGFloat = 140
    @State private var actionHeight: CGFloat = 96
    @State private var speechHeight: CGFloat = 96
    @State private var focusAction: Bool = false
    @State private var focusSpeech: Bool = false
    @State private var isGenerating: Bool = false
    @State private var showDone: Bool = false
    @State private var editingSceneId: Int? = nil
    @State private var editingText: String = ""
    @State private var showStoryboardOnboarding: Bool = false
    // Dirty/save tracking
    @State private var planIsDirty: Bool = false
    @State private var autosaveTask: Task<Void, Never>? = nil
    
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
                // Lock editing unless the blue Edit button was tapped
                .allowsHitTesting(isEditing.wrappedValue)
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
        var lines: [String] = []
        if !a.isEmpty { lines.append("Action: \(a)") }
        if !sp.isEmpty { lines.append("\(label): \(sp)") }
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
                    ForEach($plan.scenes) { $s in
                        let idx = plan.scenes.firstIndex(where: { $0.id == s.id }) ?? 0
                        SceneEditorRow(
                            scene: $s,
                            isLast: idx == plan.scenes.count - 1,
                            onDelete: {
                                withAnimation { removeScene(withId: s.id) }
                            },
                            onEdit: {
                                openEdit(for: s)
                            }
                        )
                    }
                }
            .padding(.horizontal, 16)

                // Final CTA on last scene
            VStack(spacing: 0) {
                    Button(action: exportWebcomic) {
                        Image("export_web").resizable().renderingMode(.original).scaledToFit().frame(height: 104)
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
        .fullScreenCover(isPresented: $showStoryboardOnboarding) {
            StoryboardFirstRunOnboarding {
                hasSeenStoryboardOnboarding = true
                showStoryboardOnboarding = false
            }
        }
        .sheet(item: Binding(get: { editingSceneBinding() }, set: { _ in })) { item in
            let sid = item.value
            if let i = plan.scenes.firstIndex(where: { $0.id == sid }) {
                SceneEditSheet(
                    scene: $plan.scenes[i],
                    initialText: editingText,
                    onDismiss: { editingSceneId = nil },
                    onRegenerate: { updatedAction in
                        Task { await regenerateScene(id: sid, actionText: updatedAction) }
                    }
                )
            }
        }
        .onAppear {
            if !hasSeenStoryboardOnboarding {
                showStoryboardOnboarding = true
            }
        }
    }
    // Close body

    fileprivate func next() { if index < plan.scenes.count-1 { index += 1 } }
    fileprivate func prev() { if index > 0 { index -= 1 } }

    private func removeScene(withId id: Int) {
        // Remove the scene and keep indices stable for remaining items by reassigning indices
        var updated = plan.scenes.filter { $0.id != id }
        for i in 0..<updated.count {
            // Rebuild with updated index in-place while preserving other fields
            var s = updated[i]
            if s.index != i { s = PlanScene(index: i, prompt: s.prompt, script: s.script, durationSec: s.durationSec, wordsPerSec: s.wordsPerSec, wordBudget: s.wordBudget, imageUrl: s.imageUrl, action: s.action, speechType: s.speechType, speech: s.speech, animation: s.animation) }
            updated[i] = s
        }
        plan.scenes = updated
        if index >= plan.scenes.count { index = max(0, plan.scenes.count - 1) }
    }

    private func openEdit(for scene: PlanScene) {
        editingSceneId = scene.id
        editingText = scene.action ?? ""
    }

    private func editingSceneBinding() -> IdentifiableInt? {
        if let id = editingSceneId { return IdentifiableInt(value: id) }
        return nil
    }

    private func regenerateScene(id: Int, actionText: String) async {
        guard let idx = plan.scenes.firstIndex(where: { $0.id == id }) else { return }
        // Update action and set placeholder state
        plan.scenes[idx].action = actionText
        plan.scenes[idx].imageUrl = ""
        do {
            if let url = try await RenderService.shared.renderOne(scene: plan.scenes[idx], plan: plan) {
                plan.scenes[idx].imageUrl = url
                // Mark dirty and autosave the latest storyboard snapshot
                planIsDirty = true
                await autosaveStoryboard()
            }
        } catch {
            // Restore previous image is not necessary; leave empty to indicate failure
        }
        editingSceneId = nil
    }

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
        // Persist the latest rendered state so downstream flows see the current snapshot
        await persistStoryboard(reason: "batch_render")
    }

    fileprivate func persistStoryboardIfNeeded() async {
        // Backward-compat wrapper – delegate to general saver
        await persistStoryboard(reason: "compat_if_needed")
    }

    @MainActor
    fileprivate func persistStoryboard(reason: String) async {
        // Require at least one generated image (partial saves allowed)
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
            let reqId = "save:\(reason):\(UUID().uuidString)"
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
            planIsDirty = false
            await ProjectsRepository.shared.attachStoryboardContext(userId: uid, projectId: pid, storyboardId: sbId, currentSceneIndex: 0, totalScenes: plan.scenes.count)
        } catch {
            print("[Storyboard] persist failed: \(error)")
        }
    }

    private func autosaveStoryboard() async {
        autosaveTask?.cancel()
        let snapshot = plan
        autosaveTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            await MainActor.run { [snapshot] in
                if planIsDirty { Task { await persistStoryboard(reason: "autosave") } }
            }
        }
    }

    fileprivate func generateClip() {
        Task { @MainActor in
            // Emergency guard: block generation if kill switch enabled
            if FeatureFlags.disableVeoStoryboards {
                showDone = true
                return
            }
            // Ensure no text field retains focus; prevent keyboard from auto-showing
            focusAction = false
            focusSpeech = false
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            isGenerating = true
            do {
                // Ensure the latest storyboard is persisted before enqueueing
                if !FeatureFlags.disableProjectSaving { await persistStoryboard(reason: "single_clip_pre_enqueue") }
                if !FeatureFlags.disableProjectSaving,
                   let uid = Auth.auth().currentUser?.uid,
                   let sbId = storyboardId,
                   let pid = projectId {
                    let sceneId = String(format: "%04d", plan.scenes[index].index)
                    try await StoryboardsRepository.shared.enqueueSceneVideo(userId: uid, projectId: pid, storyboardId: sbId, sceneId: sceneId, provider: "veo", requestId: UUID().uuidString)
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
                // If kill switch is on, don't kick off remote job creation
                if FeatureFlags.disableVeoStoryboards {
                    showDone = true
                    return
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
            // Emergency guard: block generation if kill switch enabled
            if FeatureFlags.disableVeoStoryboards {
                showDone = true
                return
            }
            // Extra tap guard: if already generating, bail immediately
            if isGenerating { return }
            isGenerating = true
            defer { isGenerating = false }
            do {
                // Ensure storyboard is persisted (always flush latest)
                await persistStoryboard(reason: "generate_all_pre_enqueue")
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
                        provider: "veo",
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

    fileprivate func exportWebcomic() {
        Task { @MainActor in
            isGenerating = true
            defer { isGenerating = false }
            do {
                // Ensure all images available; try rendering missing ones
                if plan.scenes.contains(where: { ($0.imageUrl ?? "").isEmpty }) {
                    _ = try? await RenderService.shared.render(plan: plan)
                }
                let url = try await WebcomicExporter.export(plan: plan, width: 800)
                // Present share sheet
                if let vc = UIApplication.shared.topMostViewController() {
                    let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                    vc.present(av, animated: true)
                }
            } catch {
                print("[Storyboard] exportWebcomic failed: \(error)")
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
// Lightweight identifiable wrapper for sheet presentation
private struct IdentifiableInt: Identifiable { let value: Int; var id: Int { value } }

// MARK: - Edit sheet
private struct SceneEditSheet: View {
    @Binding var scene: PlanScene
    let initialText: String
    let onDismiss: () -> Void
    let onRegenerate: (String) -> Void

    @State private var text: String = ""

    var body: some View {
        VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.15))
                .frame(height: 1)
                .opacity(0)
            if let urlStr = scene.imageUrl, let url = URL(string: urlStr), !urlStr.isEmpty {
                AsyncImage(url: url) { ph in
                    switch ph {
                    case .empty: ProgressView()
                    case .success(let img): img.resizable().scaledToFit()
                    case .failure: Image(systemName: "photo").resizable().scaledToFit().padding(30).foregroundColor(.black.opacity(0.4))
                    @unknown default: EmptyView()
                    }
                }
                .frame(maxHeight: 240)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                ZStack { RoundedRectangle(cornerRadius: 14).fill(Color.gray.opacity(0.2)); Text("Rendering…").foregroundColor(.black.opacity(0.6)) }
                .frame(height: 200)
            }

            GeometryReader { geo in
                let width = geo.size.width - 16
                GrowingTextViewFixed(text: $text, height: .constant(120), availableWidth: width, minHeight: 96, maxHeight: 240, trailingInset: 0, isFirstResponder: .constant(true))
                    .frame(height: 140)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.08)))
            }
            .frame(height: 160)
            .contentShape(Rectangle())
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }

            HStack {
                Button("Cancel") { onDismiss() }
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.2)))
                Spacer()
                Button(action: { onRegenerate(text) }) {
                    Text("Regenerate Scene")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.blue))
                }
            }
        }
        .padding(16)
        .onAppear { text = initialText }
    }
}

// MARK: - Scene row (vertical)
private struct SceneEditorRow: View {
    @Binding var scene: PlanScene
    let isLast: Bool
    let onDelete: () -> Void
    let onEdit: () -> Void

    @State private var actionHeight: CGFloat = 96
    @State private var speechHeight: CGFloat = 96
    @State private var focusAction: Bool = false
    @State private var focusSpeech: Bool = false
    @State private var showDeleteControl: Bool = false

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
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .onLongPressGesture {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation { showDeleteControl = true }
            }
            // Swallow taps on the image so that outer row tap (which hides the delete control)
            // doesn't fire when tapping inside the image region
            .highPriorityGesture(TapGesture().onEnded({ }))
            .overlay(alignment: .topLeading) {
                if showDeleteControl {
                    Button(action: onDelete) {
                        Image("minus-button")
                            .resizable()
                            .renderingMode(.original)
                            .frame(width: 28, height: 28)
                    }
                    .padding(8)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .overlay(alignment: .topTrailing) {
                if showDeleteControl {
                    Button(action: onEdit) {
                        Image("edit_button")
                            .resizable()
                            .renderingMode(.original)
                            .frame(width: 28, height: 28)
                    }
                    .padding(8)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(height: 300)

            // Removed heavy SCRIPT label to reduce repetition
            VStack(alignment: .leading, spacing: 18) {
                // Action
                GrowingField(title: "Action", text: Binding(get: { scene.action ?? "" }, set: { v in
                    scene.action = limitWords(v, cap: 20)
                }), isEditing: $focusAction, height: $actionHeight, onEdit: onEdit)
                .onChange(of: scene.action ?? "") { _ in
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
        // Tapping anywhere in the row outside of the image dismisses the delete control
        .contentShape(Rectangle())
        .onTapGesture {
            if showDeleteControl {
                withAnimation { showDeleteControl = false }
            }
        }
    }

    private func composeForRow(_ s: PlanScene) -> String {
        let label = s.speechType ?? "Dialogue"
        let a = s.action?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sp = s.speech?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var lines: [String] = []
        if !a.isEmpty { lines.append("Action: \(a)") }
        if !sp.isEmpty { lines.append("\(label): \(sp)") }
        return lines.joined(separator: "\n")
    }
}

private struct GrowingField: View {
    let title: String
    @Binding var text: String
    @Binding var isEditing: Bool
    @Binding var height: CGFloat
    var onEdit: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 14, weight: .heavy)).foregroundColor(.black)
                Spacer()
                Button("Edit") {
                    if let onEdit = onEdit { onEdit() }
                    else { isEditing = true }
                }
                .font(.system(size: 13, weight: .semibold))
            }
            GeometryReader { geo in
                let width = geo.size.width - 16
                GrowingTextViewFixed(text: $text, height: $height, availableWidth: width, minHeight: 72, maxHeight: 200, trailingInset: 0, isFirstResponder: $isEditing)
                    .frame(height: min(max(72, height), 200))
                    // Lock editing unless the blue Edit button was tapped
                    .allowsHitTesting(isEditing)
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

// MARK: - Storyboard First-run Onboarding
private struct StoryboardFirstRunOnboarding: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page: Int = 0
    let onFinish: () -> Void

    var body: some View {
        ZStack {
            Color(hex: 0xF7B451).ignoresSafeArea()
            VStack {
                Spacer()
                Image(page == 0 ? "story_onboard" : "story_onboard2")
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(maxWidth: 520)
                    .padding(.horizontal, 24)
                Spacer()
                Button(action: next) {
                    Text("NEXT")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundColor(.black)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
                }
                .padding(.bottom, 30)
            }
        }
    }

    private func next() {
        if page == 0 { page = 1 } else { onFinish(); dismiss() }
    }
}
