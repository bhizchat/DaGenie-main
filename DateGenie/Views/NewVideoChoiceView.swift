import SwiftUI
import PhotosUI
import FirebaseAuth

struct NewVideoChoiceView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedVideoItem: PhotosPickerItem? = nil
    @State private var isHandlingPick: Bool = false
    @State private var showEditor: Bool = false
    @State private var pickedURL: URL? = nil

    var body: some View {
        ZStack {
            Color(red: 0xF7/255.0, green: 0xB4/255.0, blue: 0x51/255.0)
                .ignoresSafeArea()

            VStack(spacing: 36) {
                Spacer().frame(height: 40)

                VStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white)
                        .frame(width: 220, height: 220)
                        .overlay(
                            PhotosPicker(selection: $selectedVideoItem, matching: .videos, photoLibrary: .shared()) {
                                VStack(spacing: 16) {
                                    if UIImage(named: "folder") != nil {
                                        Image("folder")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 140, height: 140)
                                    } else {
                                        Image(systemName: "folder.fill")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 120, height: 120)
                                            .foregroundColor(.yellow)
                                    }
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                            .buttonStyle(.plain)
                        )
                    Text("ADD A VIDEO CLIP FROM DEVICE")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.black)
                }

                Text("OR")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.black)

                VStack(spacing: 12) {
                    Button(action: openAIComposer) {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white)
                            .frame(width: 220, height: 220)
                            .overlay(
                                Group {
                                    if UIImage(named: "welcome_genie") != nil {
                                        Image("welcome_genie")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 140, height: 140)
                                    } else if UIImage(named: "Logo_DG") != nil {
                                        Image("Logo_DG")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 140, height: 140)
                                    } else {
                                        Image(systemName: "wand.and.stars")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 120, height: 120)
                                            .foregroundColor(.yellow)
                                    }
                                }
                            )
                    }
                    .buttonStyle(.plain)
                    Text("GENERATE AD CLIP WITH AI")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.black)
                }

                Spacer()
            }
        }
        .onChange(of: selectedVideoItem) { _ in
            Task { await handlePickedVideo() }
        }
        .fullScreenCover(isPresented: $showEditor) {
            if let url = pickedURL {
                CapcutEditorView(url: url)
            }
        }
        .overlay(alignment: .topLeading) {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.black)
                    .padding(12)
                    .background(Color.white.opacity(0.8))
                    .clipShape(Circle())
            }
            .padding(20)
        }
        .overlay {
            if isHandlingPick { ProgressView().scaleEffect(1.2) }
        }
    }

    private func openAIComposer() {
        let host = UIHostingController(rootView: CustomCameraView()
            .environmentObject(UserRepository.shared))
        host.modalPresentationStyle = .overFullScreen
        UIApplication.shared.topMostViewController()?.present(host, animated: true)
    }

    private func presentEditor(with url: URL, attachTo project: Project?) {
        let host = UIHostingController(rootView: CapcutEditorView(url: url))
        host.modalPresentationStyle = .overFullScreen
        UIApplication.shared.topMostViewController()?.present(host, animated: true)
    }

    private func handlePickedVideo() async {
        guard let item = selectedVideoItem, !isHandlingPick else { return }
        isHandlingPick = true
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "mov"
                let dest = docs.appendingPathComponent("picked_\(UUID().uuidString).\(ext)")
                try data.write(to: dest, options: .atomic)

                // Present the editor immediately (no waiting on uploads)
                await MainActor.run {
                    pickedURL = dest
                    showEditor = true
                    selectedVideoItem = nil
                    isHandlingPick = false
                }

                // Create/attach project in the background so it shows up in the list later
                Task {
                    if let uid = Auth.auth().currentUser?.uid,
                       let project = await ProjectsRepository.shared.create(userId: uid) {
                        await ProjectsRepository.shared.attachVideo(userId: uid, projectId: project.id, localURL: dest)
                    }
                }
            }
        } catch {
            print("[NewVideoChoiceView] picker error: \(error.localizedDescription)")
            isHandlingPick = false
        }
    }
}


