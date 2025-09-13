import SwiftUI

struct CreateOriginalCharacterView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var characterRepo = CharacterRepository.shared
    @StateObject private var uploadRepo = UploadRepository.shared

    @State private var pickedImage: UIImage? = nil
    @State private var showPicker: Bool = false
    @State private var name: String = ""
    @State private var personality: String = ""
    @State private var isGenerating: Bool = false
    @State private var errorMsg: String? = nil

    var body: some View {
        ZStack {
            Color(red: 0xF7/255.0, green: 0xB4/255.0, blue: 0x51/255.0)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("TAP BELOW TO UPLOAD A PHOTO REFERENCE")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black)

                    Button(action: { showPicker = true }) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(white: 0.88))
                            if let img = pickedImage {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFit()
                                    .padding(6)
                            } else {
                                VStack(spacing: 6) {
                                    if UIImage(named: "Enter") != nil {
                                        Image("Enter")
                                            .resizable()
                                            .scaledToFit()
                                            .padding(.horizontal, 24)
                                            .padding(.top, 30)
                                            .frame(height: 150)
                                    }
                                    if UIImage(named: "memeverse") != nil {
                                        Image("memeverse")
                                            .resizable()
                                            .scaledToFit()
                                            .padding(.horizontal, 24)
                                            .frame(height: 90)
                                    }
                                }
                            }
                        }
                        .frame(height: 310)
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("NAME OF CHARACTER")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.black)
                        TextField("What's the name of your character?", text: $name)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
                            .foregroundColor(.black)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("CHARACTER PERSONALITY")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.black)
                        ZStack(alignment: .topLeading) {
                            if personality.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("Describe your character's personality – if it's you, write about yourself")
                                    .foregroundColor(.gray)
                                    .font(.system(size: 13))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 10)
                            }
                            TextEditor(text: $personality)
                                .foregroundColor(.black)
                                .padding(2)
                        }
                            .frame(height: 160)
                            .scrollContentBackground(.hidden)
                            .background(Color(white: 0.9))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    Button(action: generateCharacter) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white)
                            Text(isGenerating ? "GENERATING…" : "GENERATE")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.black)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                    }
                    .disabled(isGenerating || pickedImage == nil || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .padding(.top, 10)
                }
                .padding(.horizontal, 20)
                .padding(.top, 56)
                .padding(.bottom, 40)
            }
        }
        .overlay(alignment: .topLeading) {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.black)
                    .padding(12)
                    .background(Color.white.opacity(0.85))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.top, 20)
            .padding(.leading, 25)
        }
        .sheet(isPresented: $showPicker) {
            ImagePicker(image: $pickedImage, sourceType: .photoLibrary)
        }
        .hideKeyboardOnTap()
        .alert("Generation failed", isPresented: Binding(get: { errorMsg != nil }, set: { _ in errorMsg = nil })) {
            Button("OK", role: .cancel) { errorMsg = nil }
        } message: {
            Text(errorMsg ?? "Unknown error. Please try again.")
        }
    }

    private func generateCharacter() {
        guard let img = pickedImage, !isGenerating else { return }
        isGenerating = true
        Task {
            do {
                let uploaded = try await uploadRepo.uploadUserReference(img)
                // Build request to character image generator (Flux Kontext Pixar-style)
                let base = "https://us-central1-\(VoiceAssistantVM.projectId()).cloudfunctions.net"
                guard let url = URL(string: "\(base)/generateCharacterImage") else { throw URLError(.badURL) }
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.addValue("application/json", forHTTPHeaderField: "Content-Type")
                let refs: [String] = [uploaded.gsPath, uploaded.url].compactMap { $0 }
                let body: [String: Any] = [
                    "referenceImageUrls": refs,
                    "name": name,
                    "bio": personality
                ]
                req.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                if !(200..<300).contains(http.statusCode) {
                    if let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let msg = o["message"] as? String {
                        throw NSError(domain: "Gen", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
                    }
                    throw URLError(.badServerResponse)
                }
                let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let firstUrl = obj?["imageUrl"] as? String
                let newId = "user_" + UUID().uuidString.lowercased()
                let gc = GenCharacter(id: newId, name: name, defaultImageUrl: firstUrl ?? "", assetImageUrls: [], localAssetName: nil, bio: personality)
                await MainActor.run {
                    characterRepo.addCustomCharacter(gc)
                    isGenerating = false
                    // After saving, go straight to the character chooser so the new
                    // character appears under "YOUR CHARACTERS"
                    let host = UIHostingController(rootView: MemeverseArchetypesView(presentEditorOnSend: true))
                    host.modalPresentationStyle = .overFullScreen
                    UIApplication.shared.topMostViewController()?.present(host, animated: true)
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    errorMsg = (error as NSError).localizedDescription
                }
            }
        }
    }
}


