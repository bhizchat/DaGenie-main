import SwiftUI

struct CharacterComposerView: View {
    let characterId: String

    @StateObject private var characterRepo = CharacterRepository.shared
    @StateObject private var uploadRepo = UploadRepository.shared
    @State private var character: GenCharacter? = nil
    @State private var userRefs: [ImageAttachment] = []
    // Map attachment id -> uploaded asset metadata (for later phases)
    @State private var uploadedByAttachmentId: [UUID: UploadedImage] = [:]
    @State private var ideaText: String = ""
    @State private var showPicker: Bool = false
    @State private var pickedImage: UIImage? = nil
    @State private var isSubmitting: Bool = false

    var body: some View {
        VStack(spacing: 12) {
            ScrollView {
                VStack(spacing: 12) {
                    if let character { characterHeader(character) }
                }
                .padding(.horizontal, 16)
            }
            CreativeInputBar(
                text: $ideaText,
                attachments: $userRefs,
                onAddTapped: { if !isSubmitting { showPicker = true } },
                onSend: { submitPlan() },
                isUploading: uploadRepo.isUploading
            )
            .disabled(uploadRepo.isUploading || isSubmitting)
        }
        .background(Color.white.ignoresSafeArea())
        .overlay {
            if isSubmitting {
                ZStack {
                    Color.black.opacity(0.15).ignoresSafeArea()
                    Text("Loading…")
                        .font(.system(size: 16, weight: .semibold))
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                }
            }
        }
        .overlay(alignment: .topLeading) {
            Button(action: { UIApplication.shared.topMostViewController()?.dismiss(animated: true) }) {
                Image("back_arrow")
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .padding(14)
                    .background(Color.white.opacity(0.85))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.top, 20)
            .padding(.leading, 20)
        }
        .task { await loadCharacter() }
        .sheet(isPresented: $showPicker, onDismiss: handlePicked) {
            ImagePicker(image: $pickedImage, sourceType: .photoLibrary)
        }
    }

    private func loadCharacter() async {
        character = await characterRepo.fetchCharacter(id: characterId)
    }

    @ViewBuilder private func characterHeader(_ c: GenCharacter) -> some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 160, height: 160)
                Group {
                    if let url = URL(string: c.defaultImageUrl), !c.defaultImageUrl.isEmpty {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                Color.clear
                            case .success(let img):
                                img.resizable().scaledToFit()
                            case .failure:
                                if let local = c.localAssetName, let ui = UIImage(named: local) {
                                    Image(uiImage: ui).resizable().scaledToFit()
                                } else {
                                    Image(systemName: "photo").resizable().scaledToFit().padding(20).foregroundColor(.gray)
                                }
                            @unknown default:
                                Color.clear
                            }
                        }
                    } else if let local = c.localAssetName, let ui = UIImage(named: local) {
                        Image(uiImage: ui).resizable().scaledToFit()
                    } else {
                        Image(systemName: "photo").resizable().scaledToFit().padding(20).foregroundColor(.gray)
                    }
                }
                .frame(width: 160, height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            Text(c.name)
                .font(.system(size: 24, weight: .heavy))
                .foregroundColor(.black)
                .padding(.top, 2)

            if let desc = characterDescription(for: c) {
                Text(desc)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.top, 2)
                    .padding(.horizontal, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private func handlePicked() {
        guard let img = pickedImage else { return }
        pickedImage = nil
        if userRefs.count >= 3 { return }
        let attachment = ImageAttachment(image: img)
        userRefs.append(attachment)
        Task {
            if let uploaded = try? await uploadRepo.uploadUserReference(img) {
                uploadedByAttachmentId[attachment.id] = uploaded
            }
        }
    }

    private func submitPlan() {
        // Gate sending while uploads in progress or unresolved attachments
        guard !uploadRepo.isUploading, !isSubmitting else { return }
        isSubmitting = true
        let uploaded = userRefs.compactMap { uploadedByAttachmentId[$0.id] }
        let ids: [String] = uploaded.map { $0.id }
        let urls: [String] = uploaded.map { $0.url }
        let background = character.flatMap { characterDescription(for: $0) }
        let req = GenerationRequest(characterId: characterId, ideaText: ideaText, userReferenceImageIds: ids, characterBackground: background, userReferenceImageUrls: urls)
        Task {
            do {
                let plan = try await PlannerService.shared.plan(request: req)
                let vc = UIHostingController(rootView: StoryboardNavigatorView(plan: plan))
                vc.modalPresentationStyle = .overFullScreen
                UIApplication.shared.topMostViewController()?.present(vc, animated: true)
                isSubmitting = false
            } catch {
                // TODO: surface error UI
                isSubmitting = false
            }
        }
    }
    private func characterDescription(for c: GenCharacter) -> String? {
        if c.id == "cory" {
            return "Cory the Lion is the official Mascot for Campus Burgers , he eats about 25 Campus Cheese Burgers everyday and holds the record for the most burgers eaten in america for a year. In his free time Cory like to play competitive top golf with other mascots in various campuses and is also a gymnast"
        }
        return nil
    }
}


