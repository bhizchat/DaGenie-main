import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct MusicVideoStoryboardContainerView: View {
    let uid: String
    let projectId: String
    let storyboardId: String
    let settingId: String
    let referenceUrl: String
    let audioGsPath: String
    let audioDurationSec: Double

    @State private var plan: StoryboardPlan? = nil
    @State private var listener: ListenerRegistration? = nil
    @State private var finishingStarted: Bool = false
    @State private var finishingSnapshot: [String: Any]? = nil
    @State private var isLipsyncing: Bool = false
    @State private var didSubmitLipsync: Bool = false

    var body: some View {
        ZStack {
            Group {
                if let p = plan {
                    // In music‑video flow, images are generated on the backend and written to Firestore.
                    // Disable client auto-render to prevent a blank intermediate state and ensure
                    // we immediately display server-generated images as they stream in.
                    StoryboardNavigatorView(plan: p, autoRenderMissingImages: false)
                        // Force a fresh view identity when scene image URLs change so the child
                        // re-initializes its local state from the latest parent plan.
                        .id(p.scenes.map { "\($0.index):\($0.imageUrl ?? "")" }.joined(separator: "|"))
                } else {
                    ZStack {
                        Color(hex: 0xF3B529).ignoresSafeArea()
                        ProgressView("Loading storyboard…")
                            .padding(16)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                    }
                }
            }

            if isLipsyncing {
                Text("Lipsyncing your song, this could take up to 15 minutes")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.1), lineWidth: 1))
            }
        }
        .onAppear(perform: startListener)
        .onDisappear { listener?.remove() }
    }

    private func startListener() {
        listener?.remove()
        let db = Firestore.firestore()
        let storyboardRef = db.collection("users").document(uid).collection("musicVideos").document(projectId).collection("storyboards").document(storyboardId)
        let base = storyboardRef.collection("scenes")
        // One-shot fetch to avoid perceived stall if network latency delays the first snapshot
        base.order(by: "index").getDocuments { snap, _ in
            guard let docs = snap?.documents else { return }
            print("[MV] initial_scenes_count=\(docs.count) uid=\(uid) projectId=\(projectId) storyboardId=\(storyboardId)")
            if docs.isEmpty { return }
            // Verbose per-doc logging to verify fields present
            for d in docs {
                let data = d.data()
                let idx = (data["index"] as? NSNumber)?.intValue ?? (data["index"] as? Int) ?? -1
                let image = data["imageUrl"] as? String ?? ""
                let action = data["action"] as? String ?? ""
                let anim = data["animation"] as? String ?? ""
                print("[MV] initial_scene id=\(d.documentID) idx=\(idx) imgLen=\(image.count) actionLen=\(action.count) animLen=\(anim.count)")
            }
            DispatchQueue.main.async { self.plan = buildPlan(from: docs) }
        }
        // Listen to scenes (existing)
        listener = base.order(by: "index").addSnapshotListener { snap, _ in
            guard let docs = snap?.documents else { return }
            print("[MV] snapshot_scenes_count=\(docs.count) uid=\(uid) projectId=\(projectId) storyboardId=\(storyboardId)")
            if docs.isEmpty { return }
            for d in docs {
                let data = d.data()
                let idx = (data["index"] as? NSNumber)?.intValue ?? (data["index"] as? Int) ?? -1
                let image = data["imageUrl"] as? String ?? ""
                let action = data["action"] as? String ?? ""
                let anim = data["animation"] as? String ?? ""
                print("[MV] snapshot_scene id=\(d.documentID) idx=\(idx) imgLen=\(image.count) actionLen=\(action.count) animLen=\(anim.count)")
            }
            DispatchQueue.main.async { self.plan = buildPlan(from: docs) }

            // If all scenes done and we haven't kicked off finishing yet, start it
            if !finishingStarted {
                let allDone = docs.allSatisfy { (d) -> Bool in
                    let video = d.data()["video"] as? [String: Any]
                    return ((video?["status"] as? String) ?? "") == "done"
                }
                if allDone {
                    finishingStarted = true
                    Task { await startFinishingIfPossible() }
                }
            }
        }

        // Listen to finishing status on the storyboard root for overlay logic
        storyboardRef.addSnapshotListener { snap, _ in
            guard let data = snap?.data() else { return }
            finishingSnapshot = data["finishing"] as? [String: Any]
            let finishing = finishingSnapshot
            let dur = ((finishing?["concat"] as? [String: Any])?["durationSec"] as? NSNumber)?.doubleValue ?? 0
            let status = ((finishing?["lipsync"] as? [String: Any])?["status"] as? String) ?? "idle"
            let muxFinal = ((finishing?["mux"] as? [String: Any])?["finalUrl"] as? String) ?? ""
            let shouldShow = dur >= 54 && status == "running" && muxFinal.isEmpty
            if shouldShow && !isLipsyncing { print("[Lipsync] HUD.show source=storyboard_overlay dur=\(dur)") }
            if !shouldShow && isLipsyncing { print("[Lipsync] HUD.hide source=storyboard_overlay") }
            isLipsyncing = shouldShow
            if !muxFinal.isEmpty {
                print("[MV] mux.finalUrl.applied url=\(muxFinal)")
            }

            // Auto-submit lipsync when concat ready and not yet submitted
            if dur >= 54 && status == "idle" && !didSubmitLipsync {
                didSubmitLipsync = true
                if let user = Auth.auth().currentUser {
                    let runId = RunManager.shared.currentRunId ?? RunManager.shared.startNewRun()
                    print("[MV] lipsync.auto_submit runId=\(runId) dur=\(dur)")
                    Task {
                        _ = try? await LipsyncSingleFlight.shared.performOnce(runId: runId) {
                            // Reuse centralized pipeline inside the editor if needed; here we only submit since finishing started earlier
                            try await MusicVideoRepository.shared.submitLipsync(uid: user.uid, projectId: projectId, storyboardId: storyboardId, runId: runId)
                            return true
                        }
                    }
                }
            }
        }
    }

    private func buildPlan(from docs: [QueryDocumentSnapshot]) -> StoryboardPlan {
        var scenes: [PlanScene] = []
        for d in docs {
            let data = d.data()
            let idx = (data["index"] as? NSNumber)?.intValue ?? (data["index"] as? Int) ?? 0
            let action = data["action"] as? String
            let anim = data["animation"] as? String
            let image = data["imageUrl"] as? String
            var s = PlanScene(index: idx, prompt: action ?? "", script: action ?? "", durationSec: 5.0, wordsPerSec: nil, wordBudget: nil, imageUrl: image, action: action, speechType: nil, speech: nil, animation: anim, speakerSlot: nil)
            scenes.append(s)
        }
        scenes.sort { $0.index < $1.index }
        return StoryboardPlan(character: PlanCharacter(id: "user"), settings: PlanSettings(aspectRatio: "9:16", style: settingId, camera: nil), scenes: scenes, referenceImageUrls: [referenceUrl])
    }
}

extension MusicVideoStoryboardContainerView {
    private func startFinishingIfPossible() async {
        guard let user = Auth.auth().currentUser else { return }
        let runId = RunManager.shared.currentRunId ?? RunManager.shared.startNewRun()
        do {
            try await MusicVideoRepository.shared.startMusicFinishing(uid: user.uid, projectId: projectId, storyboardId: storyboardId, runId: runId, audioGsPath: audioGsPath, audioDurationSec: audioDurationSec)
            // Trigger lipsync; mux will be run after lipsync completes (server-side)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                Task {
                    _ = try? await LipsyncSingleFlight.shared.performOnce(runId: runId) {
                        try await MusicVideoRepository.shared.submitLipsync(uid: user.uid, projectId: projectId, storyboardId: storyboardId, runId: runId)
                        return true
                    }
                }
            }
        } catch {
            print("[MV] startMusicFinishing error: \(error)")
        }
    }
}


