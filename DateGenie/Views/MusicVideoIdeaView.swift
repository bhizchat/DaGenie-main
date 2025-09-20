import SwiftUI
import FirebaseAuth

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

            NavigationLink(isActive: $openStoryboard) {
                if let sbId = storyboardId {
                    MusicVideoStoryboardContainerView(uid: uid, projectId: projectId, storyboardId: sbId, settingId: settingId, referenceUrl: referenceImageUrl)
                } else { EmptyView() }
            } label: { EmptyView() }

            Spacer()
        }
        .padding(.horizontal, 24)
        .background(Color(hex: 0xF7B451).ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let gcpId = (Bundle.main.object(forInfoDictionaryKey: "FirebaseProjectID") as? String) ?? "dategenie-dev"
            let url = URL(string: "https://us-central1-\(gcpId).cloudfunctions.net/generateMusicStoryboard")!
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
            
            req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
            let (data, _) = try await URLSession.shared.data(for: req)
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let sbId = obj["storyboardId"] as? String {
                storyboardId = sbId
                openStoryboard = true
            } else {
                openStoryboard = true // optimistic
            }
        } catch {
            openStoryboard = true // still open; Firestore may sync later
        }
    }
}


