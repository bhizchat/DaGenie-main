import SwiftUI
import PhotosUI

struct AddClipChoiceView: View {
    var onPickedVideo: (URL) -> Void
    var onChooseAI: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var item: PhotosPickerItem? = nil
    @State private var isHandling: Bool = false

    var body: some View {
        ZStack {
            Color(red: 0xF7/255.0, green: 0xB4/255.0, blue: 0x51/255.0).ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer().frame(height: 40)
                VStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 16).fill(Color.white)
                        .frame(width: 220, height: 220)
                        .overlay(
                            PhotosPicker(selection: $item, matching: .videos, photoLibrary: .shared()) {
                                Image("folder").resizable().scaledToFit().frame(width: 140, height: 140)
                            }
                        )
                    Text("ADD A VIDEO CLIP FROM DEVICE")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.black)
                }
                Text("OR").font(.system(size: 16, weight: .bold)).foregroundColor(.black)
                VStack(spacing: 12) {
                    Button(action: {
                        onChooseAI()
                        let host = UIHostingController(rootView: AdGenChoiceView())
                        host.modalPresentationStyle = .overFullScreen
                        UIApplication.shared.topMostViewController()?.present(host, animated: true)
                        dismiss()
                    }) {
                        RoundedRectangle(cornerRadius: 16).fill(Color.white)
                            .frame(width: 220, height: 220)
                            .overlay(
                                Group {
                                    if UIImage(named: "welcome_genie") != nil {
                                        Image("welcome_genie")
                                            .renderingMode(.original)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 140, height: 140)
                                    } else if UIImage(named: "Logo_DG") != nil {
                                        Image("Logo_DG")
                                            .renderingMode(.original)
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
                    }.buttonStyle(.plain)
                    Text("GENERATE AD CLIP WITH AI")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.black)
                }
                Spacer()
            }
        }
        .onChange(of: item) { _ in Task { await handlePicked() } }
        .overlay { if isHandling { ProgressView().scaleEffect(1.2) } }
        .overlay(alignment: .topLeading) {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark").font(.system(size: 18, weight: .bold)).foregroundColor(.black)
                    .padding(12).background(Color.white.opacity(0.85)).clipShape(Circle())
            }.padding(20)
        }
    }

    private func handlePicked() async {
        guard let item else { return }
        isHandling = true
        defer { isHandling = false }
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "mov"
                let dest = docs.appendingPathComponent("picked_\(UUID().uuidString).\(ext)")
                try data.write(to: dest, options: .atomic)
                onPickedVideo(dest)
                dismiss()
            }
        } catch {
            print("[AddClipChoice] picker error: \(error.localizedDescription)")
        }
    }
}


