import SwiftUI

/// First step: upload a reference image only. Next is disabled until an image is chosen.
struct MVUploadImageStepView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var referenceImage: UIImage? = nil
    @State private var showPicker: Bool = false

    @Environment(\.dismiss) private var navDismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: 0xF3B529).ignoresSafeArea()
                VStack(spacing: 22) {
                    HStack {
                        Button(action: { navDismiss() }) {
                            Image("back_arrow")
                                .resizable()
                                .renderingMode(.original)
                                .scaledToFit()
                                .frame(width: 28, height: 28)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 18)

                    Text("Create your Avatar")
                        .font(.system(size: 28, weight: .heavy))
                        .foregroundColor(.black)

                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white)
                        .frame(width: 300, height: 300)
                        .overlay(
                            Group {
                                if let ui = referenceImage {
                                    Image(uiImage: ui)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 300, height: 300)
                                        .clipped()
                                        .cornerRadius(16)
                                        .overlay(alignment: .topTrailing) {
                                            Button(action: { referenceImage = nil }) {
                                                ZStack {
                                                    Circle().fill(Color.white).frame(width: 24, height: 24)
                                                    Image(systemName: "xmark")
                                                        .font(.system(size: 12, weight: .bold))
                                                        .foregroundColor(.black)
                                                }
                                            }
                                            .padding(8)
                                        }
                                } else {
                                    Button(action: { showPicker = true }) {
                                        VStack(spacing: 8) {
                                            Image(systemName: "photo.on.rectangle")
                                                .resizable()
                                                .scaledToFit()
                                                .foregroundColor(.black.opacity(0.5))
                                                .frame(width: 180, height: 150)
                                            Text("Upload Reference\nImage")
                                                .font(.system(size: 16, weight: .bold))
                                                .multilineTextAlignment(.center)
                                                .foregroundColor(.black.opacity(0.7))
                                        }
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    }
                                }
                            }
                        )

                    // Helper bullets (Audiomack-style)
                    VStack(alignment: .leading, spacing: 10) {
                        bullet("Turn a Portrait photo into your music‑video avatar.")
                        bullet("One person per photo with good lighting.")
                        bullet("Keep your face and shoulders in view; avoid extreme close‑ups.")
                    }
                    .padding(.horizontal, 30)

                    Spacer()

                    NavigationLink {
                        // Build destination only when we actually have an image to avoid unwrapping crashes
                        if let img = referenceImage {
                            MusicVideoStoryboardView(referenceImage: img, audioURL: URL(fileURLWithPath: "/dev/null"), settingId: "placeholder")
                        } else {
                            EmptyView()
                        }
                    } label: {
                        Text("NEXT")
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 64)
                            .background(referenceImage == nil ? Color.composerGray : Color.black)
                            .cornerRadius(32)
                            .padding(.horizontal, 24)
                    }
                    .disabled(referenceImage == nil)

                    Spacer().frame(height: 6)
                }
            }
        }
        .sheet(isPresented: $showPicker) {
            ImagePicker(image: $referenceImage, sourceType: .photoLibrary)
        }
    }

    @ViewBuilder private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").font(.system(size: 18, weight: .heavy))
            Text(text).font(.system(size: 15, weight: .semibold)).foregroundColor(.black)
            Spacer()
        }
    }
}


