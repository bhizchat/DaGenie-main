import SwiftUI
import FirebaseFirestore

struct MusicVideoStoryboardContainerView: View {
    let uid: String
    let projectId: String
    let storyboardId: String
    let settingId: String
    let referenceUrl: String

    @State private var plan: StoryboardPlan? = nil
    @State private var listener: ListenerRegistration? = nil

    var body: some View {
        Group {
            if let p = plan {
                // In music‑video flow, images are generated on the backend and written to Firestore.
                // Disable client auto-render to prevent a blank intermediate state and ensure
                // we immediately display server-generated images as they stream in.
                StoryboardNavigatorView(plan: p, autoRenderMissingImages: false)
            } else {
                ZStack {
                    Color(hex: 0xF7B451).ignoresSafeArea()
                    ProgressView("Loading storyboard…")
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                }
            }
        }
        .onAppear(perform: startListener)
        .onDisappear { listener?.remove() }
    }

    private func startListener() {
        listener?.remove()
        let db = Firestore.firestore()
        let base = db.collection("users").document(uid).collection("musicVideos").document(projectId).collection("storyboards").document(storyboardId).collection("scenes")
        // One-shot fetch to avoid perceived stall if network latency delays the first snapshot
        base.order(by: "index").getDocuments { snap, _ in
            guard let docs = snap?.documents else { return }
            print("[MV] initial_scenes_count=\(docs.count) uid=\(uid) projectId=\(projectId) storyboardId=\(storyboardId)")
            if docs.isEmpty { return }
            self.plan = buildPlan(from: docs)
        }
        listener = base.order(by: "index").addSnapshotListener { snap, _ in
            guard let docs = snap?.documents else { return }
            print("[MV] snapshot_scenes_count=\(docs.count) uid=\(uid) projectId=\(projectId) storyboardId=\(storyboardId)")
            if docs.isEmpty { return }
            self.plan = buildPlan(from: docs)
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


