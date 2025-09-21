import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct MusicVideoIdeaView: View {
    let uid: String
    let projectId: String
    let settingId: String
    let referenceImageUrl: String
    let audioGsPath: String
    let promptKit: [String: Any]

    @State private var ideaText: String = ""
    @State private var isSubmitting: Bool = false
    @State private var storyboardId: String? = nil
    @State private var openStoryboard: Bool = false

    var body: some View {
        VStack(spacing: 24) {
            TextEditor(text: $ideaText)
                .frame(height: 160)
                .padding(12)
                .foregroundColor(.black)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.08)))
                .overlay(alignment: .topLeading) {
                    Text("Describe Music Video Idea...")
                        .foregroundColor(Color(hex: 0x999CA0))
                        .opacity(ideaText.isEmpty ? 1 : 0)
                        .padding(20)
                }
                .scrollContentBackground(.hidden)

            Button(action: { Task { await submit() } }) {
                Text("Create Video Visuals")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.black)
                    .cornerRadius(14)
            }
            .disabled(isSubmitting)

            if let sbId = storyboardId {
                NavigationLink(isActive: $openStoryboard) {
                    MusicVideoStoryboardContainerView(uid: uid, projectId: projectId, storyboardId: sbId, settingId: settingId, referenceUrl: referenceImageUrl)
                } label: { EmptyView() }
                .hidden()
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .background(Color(hex: 0xF7B451).ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { isSubmitting = false }
        .overlay {
            if isSubmitting {
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    ProgressView("Preparing storyboard…")
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                }
            }
        }
    }

    private func submit() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { /* we'll turn this off manually once we navigate */ }
        do {
            // Create a storyboard id immediately so we can navigate without waiting for HTTP
            let localId: String = storyboardId ?? UUID().uuidString
            // Optimistically create the header doc to make the path visible; scenes will arrive via Cloud Function
            let db = Firestore.firestore()
            let now = Date()
            let env = (promptKit["environment"] as? String) ?? ""
            let bio = (promptKit["bio"] as? String) ?? ""
            let styleDesc = bio.isEmpty ? "3D stylized" : "3D stylized — \(bio)"
            try await db.collection("users").document(uid)
                .collection("musicVideos").document(projectId)
                .collection("storyboards").document(localId)
                .setData([
                    "status": "created",
                    "createdAt": Timestamp(date: now),
                    "environment": env,
                    "style": styleDesc,
                    "ideaText": ideaText.trimmingCharacters(in: .whitespacesAndNewlines),
                    "referenceImageUrls": [referenceImageUrl]
                ], merge: true)
            // Seed placeholder scenes (1..12) so the container shows immediately with "Rendering..." tiles
            do {
                let scenes = db.collection("users").document(uid)
                    .collection("musicVideos").document(projectId)
                    .collection("storyboards").document(localId)
                    .collection("scenes")
                let batch = db.batch()
                for i in 1...12 {
                    let id4 = String(format: "%04d", i)
                    let doc = scenes.document(id4)
                    batch.setData([
                        "index": i,
                        "action": "",
                        "imageUrl": "",
                        "video": ["status": "idle"],
                        "environment": env,
                        "ideaText": ideaText.trimmingCharacters(in: .whitespacesAndNewlines),
                        "referenceImageUrls": [referenceImageUrl],
                        "createdAt": FieldValue.serverTimestamp(),
                        "updatedAt": FieldValue.serverTimestamp(),
                    ], forDocument: doc, merge: true)
                }
                try await batch.commit()
            } catch { /* non-fatal; CF will still write scenes */ }
            await MainActor.run {
                storyboardId = localId
                openStoryboard = true
                isSubmitting = false
            }
            let gcpId = (Bundle.main.object(forInfoDictionaryKey: "FirebaseProjectID") as? String) ?? "dategenie-dev"
            let url = URL(string: "https://us-central1-\(gcpId).cloudfunctions.net/generateMusicStoryboardV2")!
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.addValue("application/json", forHTTPHeaderField: "Content-Type")
            var body: [String: Any] = [
                "uid": uid,
                "projectId": projectId,
                "settingId": settingId,
                "referenceImageUrl": referenceImageUrl,
                "audioGsPath": audioGsPath,
                "promptKit": promptKit,
                "ideaText": ideaText.trimmingCharacters(in: .whitespacesAndNewlines)
            ]
            // If we already created an ID locally, pass it through so the backend uses the same one
            body["storyboardId"] = localId
            
            req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
            // Fire the request with simple retries; do not block UI
            Task.detached {
                let attempts = 3
                for attempt in 1...attempts {
                    do {
                        print("[MV] generateMusicStoryboard attempt=\(attempt) uid=\(uid) projectId=\(projectId) storyboardId=\(localId)")
                        let (_, resp) = try await URLSession.shared.data(for: req)
                        if let http = resp as? HTTPURLResponse { print("[MV] generateMusicStoryboard status=\(http.statusCode)") }
                        break
                    } catch {
                        print("[MV] generateMusicStoryboard error attempt=\(attempt) \(error.localizedDescription)")
                        if attempt < attempts { try? await Task.sleep(nanoseconds: 1_500_000_000) }
                    }
                }
            }
        } catch {
            // Keep user on this screen; optionally show an error
            await MainActor.run { isSubmitting = false }
        }
    }
}


