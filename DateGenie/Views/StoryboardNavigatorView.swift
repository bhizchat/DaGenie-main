import SwiftUI
import UIKit
import FirebaseFirestore

struct StoryboardNavigatorView: View {
    @State var plan: StoryboardPlan
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
    // Video model picker state (default: Veo 3)
    @State private var selectedVideoModel: VideoModel = .veo3
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
            VStack(spacing: 14) {
                ZStack {
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.black)
                                .padding(8)
                        }
                        Spacer()
                    }
                    HStack(spacing: 8) {
                        Spacer()
                        Text("STORYBOARD")
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundColor(.black)
                        Image("storyboard").resizable().renderingMode(.original).scaledToFit().frame(width: 28, height: 28)
                        Spacer()
                    }
                }

                Text("\(index+1)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.black)

            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.gray.opacity(0.2))
                if let urlStr = scene.imageUrl, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { ph in
                        switch ph {
                        case .empty: ProgressView()
                        case .success(let img): img.resizable().scaledToFit()
                        case .failure: Image(systemName: "photo").resizable().scaledToFit().padding(30).foregroundColor(.black.opacity(0.4))
                        @unknown default: EmptyView()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                } else {
                    Text("Rendering…").foregroundColor(.black.opacity(0.5))
                }
            }
            .frame(height: 300)
            .padding(.horizontal, 16)

            HStack(spacing: 8) {
                Text("SCRIPT")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundColor(.black)
                Image("script").resizable().renderingMode(.original).scaledToFit().frame(width: 22, height: 22)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 18) {
                // Action
                sectionEditor(title: "Action", isEditing: $focusAction, text: Binding(get: {
                    plan.scenes[index].action ?? ""
                }, set: { newVal in
                    plan.scenes[index].action = limitWords(newVal, cap: 20)
                    plan.scenes[index].script = composeScript(for: plan.scenes[index])
                }), height: $actionHeight, limit: 20)

                // Animation
                sectionEditor(title: "Animation", isEditing: $focusAnimation, text: Binding(get: {
                    plan.scenes[index].animation ?? ""
                }, set: { newVal in
                    plan.scenes[index].animation = limitWords(newVal, cap: 20)
                    plan.scenes[index].script = composeScript(for: plan.scenes[index])
                }), height: $animationHeight, limit: 20)

                // Dialogue/Narration
                let label = (plan.scenes[index].speechType ?? "Dialogue")
                sectionEditor(title: label, isEditing: $focusSpeech, text: Binding(get: {
                    plan.scenes[index].speech ?? ""
                }, set: { newVal in
                    // Ensure default accent appears if user hasn't typed any accent
                    let trimmed = limitWords(newVal, cap: 20)
                    plan.scenes[index].speech = ensureAccentSuffix(trimmed)
                    if plan.scenes[index].speechType == nil { plan.scenes[index].speechType = "Dialogue" }
                    plan.scenes[index].script = composeScript(for: plan.scenes[index])
                }), height: $speechHeight, limit: 20)

                // Video Model Picker
                VideoModelPicker(selected: $selectedVideoModel)


                // Word budget
                if true {
                    let budget = 60
                    let total = wordCount((plan.scenes[index].action ?? "") + " " + (plan.scenes[index].speech ?? "") + " " + (plan.scenes[index].animation ?? ""))
                    Text("\(total)/60 words")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(total <= budget ? .green : .red)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 8)
                }
            }
            .padding(.horizontal, 16)

            HStack {
                if index > 0 {
                    VStack(spacing: 6) {
                        Text("BACK").font(.system(size: 12, weight: .heavy)).foregroundColor(.black)
                        Button(action: prev) { Image("left_arrow").resizable().renderingMode(.original).scaledToFit().frame(width: 33, height: 33) }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 5)
                } else { Spacer() }
                Spacer()
                VStack(spacing: 6) {
                    Text("NEXT").font(.system(size: 12, weight: .heavy)).foregroundColor(.black)
                    Button(action: next) { Image("right-arrow").resizable().renderingMode(.original).scaledToFit().frame(width: 28, height: 28) }
                        .buttonStyle(.plain)
                        .disabled(index >= plan.scenes.count-1)
                        .opacity(index >= plan.scenes.count-1 ? 0.4 : 1)
                }
                .padding(.top, 5)
            }
            .padding(.horizontal, 24)

            VStack(spacing: 0) {
                Button(action: generateClip) {
                    Image("generate_clip")
                        .resizable()
                        .renderingMode(.original)
                        .scaledToFit()
                        .frame(height: 54)
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
        .overlay(alignment: .center, content: {
            if isGenerating {
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    ProgressView("Preparing…")
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                }
            } else {
                EmptyView()
            }
        })
        // Tap to dismiss keyboard anywhere outside
        .hideKeyboardOnTap()
        .alert(
            "Generation failed",
            isPresented: $showDone,
            actions: {
                Button("OK", role: .cancel) {}
            },
            message: {
                Text("Couldn't start video generation. Please try again.")
            }
        )
    }
    // Close body

    fileprivate func next() { if index < plan.scenes.count-1 { index += 1 } }
    fileprivate func prev() { if index > 0 { index -= 1 } }

    fileprivate func renderIfNeeded() async {
        guard !plan.scenes.contains(where: { $0.imageUrl != nil }) else { return }
        if let rendered = try? await RenderService.shared.render(plan: plan) {
            self.plan = rendered
        }
    }

    fileprivate func generateClip() {
        Task { @MainActor in
            isGenerating = true
            do {
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
                let modelName: String = {
                    switch selectedVideoModel {
                    case .veo3: return "veo-3.0-generate-preview"
                    case .wan: return "wan-video"
                    case .hunyan: return "hunyan-video"
                    }
                }()
                let body: [String: Any] = [
                    "data": [
                        "character": plan.character.id,
                        "model": modelName,
                        "aspectRatio": plan.settings.aspectRatio,
                        "scenes": scenesPayload
                    ]
                ]
                print("[Storyboard] payload model=\(modelName) scenes=\(scenesPayload.count) firstImage=\(plan.scenes.first?.imageUrl ?? "<none>")")
                let url = URL(string: "https://us-central1-\(VoiceAssistantVM.projectId()).cloudfunctions.net/createStoryboardJob")!
                let json = try await callCallable(url: url, payload: body)
                let jobId = (json["result"] as? [String: Any])? ["jobId"] as? String ?? json["jobId"] as? String
                print("[Storyboard] job enqueued id=\(jobId ?? "<nil>")")

                // Immediately open the Capcut-style editor in generating state (restore original flow)
                if let vc = UIApplication.shared.topMostViewController() {
                    let presented = vc.presentedViewController
                    let isAlreadyCapcut = presented is UIHostingController<CapcutEditorView>
                    if !isAlreadyCapcut {
                        let host = UIHostingController(rootView: CapcutEditorView(url: URL(fileURLWithPath: "/dev/null"), initialGenerating: true))
                        vc.present(host, animated: true)
                    }
                }

                // Optional: background listener to auto-swap to final when ready
                if let jobId = jobId {
                    let db = Firestore.firestore()
                    db.collection("adJobs").document(jobId).addSnapshotListener { snap, _ in
                        guard let data = snap?.data() else { return }
                        let status = data["status"] as? String ?? ""
                        if status == "ready" {
                            if let urlStr = (data["finalVideoUrl"] as? String) ?? (data["videoUrl"] as? String) ?? (data["outputUrl"] as? String), let u = URL(string: urlStr) {
                                if let top = UIApplication.shared.topMostViewController() {
                                    top.presentedViewController?.dismiss(animated: false)
                                    let host = UIHostingController(rootView: CapcutEditorView(url: u))
                                    top.present(host, animated: true)
                                }
                            }
                        }
                    }
                }
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

// MARK: - Video Model Picker
enum VideoModel: String, CaseIterable, Identifiable {
    case veo3 = "VEO 3"
    case wan = "Wan Video"
    case hunyan = "Hunyan Video"
    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .veo3: return "Veo"
        case .wan: return "Wan"
        case .hunyan: return "Hunyan"
        }
    }
}

struct VideoModelPicker: View {
    @Binding var selected: VideoModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Video Model")
                .font(.system(size: 14, weight: .heavy))
                .foregroundColor(.black)
            Menu {
                ForEach(VideoModel.allCases) { model in
                    Button(action: { selected = model }) {
                        HStack(spacing: 10) {
                            Image(model.iconName)
                                .resizable()
                                .renderingMode(.original)
                                .scaledToFit()
                                .frame(width: 22, height: 22)
                            Text(model.rawValue)
                        }
                    }
                }
            } label: {
                HStack {
                    HStack(spacing: 10) {
                        Image(selected.iconName)
                            .resizable()
                            .renderingMode(.original)
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                        Text(selected.rawValue)
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundColor(.black)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.black)
                }
                .padding(.horizontal, 12)
                .frame(height: 56)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.08)))
            }
        }
    }
}
