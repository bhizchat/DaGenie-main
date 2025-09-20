import SwiftUI
import UniformTypeIdentifiers

/// Entry screen for the music video workflow.
/// Users upload a reference image, choose an audio file, pick a setting, then proceed.
struct CreateMusicVideoView: View {
    // Inputs
    @State private var referenceImage: UIImage? = nil
    @State private var audioURL: URL? = nil
    @State private var isShowingImagePicker: Bool = false
    @State private var isShowingAudioPicker: Bool = false
    @State private var selectedSettingId: String = ""
    @State private var showSettingSheet: Bool = false

    // Simple placeholder settings; designer will provide final catalog
    private let settings: [MusicVideoSetting] = MusicVideoSettingsCatalog.all

    var body: some View {
        NavigationView {
            ZStack {
                Color(hex: 0xF7B451).ignoresSafeArea()
                VStack(spacing: 28) {
                    Spacer().frame(height: 24)
                    Text("CREATE MUSIC VIDEO")
                        .font(.system(size: 28, weight: .heavy))
                        .foregroundColor(.black)

                    // Reference image
                    VStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white)
                            .frame(width: 260, height: 260)
                            .overlay(
                                Group {
                                    if let ui = referenceImage {
                                        Image(uiImage: ui)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 260, height: 260)
                                            .clipped()
                                            .cornerRadius(16)
                                    } else {
                                        Button(action: { isShowingImagePicker = true }) {
                                            Text("Upload Reference\nImage")
                                                .font(.system(size: 16, weight: .bold))
                                                .multilineTextAlignment(.center)
                                                .foregroundColor(.black)
                                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        }
                                    }
                                }
                            )
                    }

                    // Audio upload area
                    VStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 220)
                            .overlay(
                                VStack(spacing: 16) {
                                    Image("music-folder")
                                        .resizable()
                                        .renderingMode(.original)
                                        .scaledToFit()
                                        .frame(width: 120, height: 120)
                                    Button(action: { isShowingAudioPicker = true }) {
                                        Text(audioURL == nil ? "UPLOAD AUDIO FILES" : audioURL!.lastPathComponent)
                                            .font(.system(size: 16, weight: .bold))
                                            .padding(.vertical, 12)
                                            .padding(.horizontal, 16)
                                            .background(Color(red: 0xE9/255.0, green: 0x45/255.0, blue: 0x45/255.0))
                                            .foregroundColor(.white)
                                            .cornerRadius(10)
                                    }
                                }
                                .padding(.vertical, 24)
                            )
                            .padding(.horizontal, 24)
                    }

                    // Setting picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Setting")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white)
                            .frame(height: 56)
                            .overlay(
                                HStack {
                                    HStack {
                                        Text(selectedSettingId.isEmpty ? "Select" : (settings.first(where: { $0.id == selectedSettingId })?.name ?? "Select"))
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.black)
                                        Spacer()
                                        Button(action: { showSettingSheet = true }) {
                                            Image("down-arrow")
                                                .resizable()
                                                .renderingMode(.original)
                                                .scaledToFit()
                                                .frame(width: 22, height: 22)
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                            )
                            .padding(.horizontal, 24)
                    }

                    Spacer()

                    NavigationLink(
                        destination: {
                            if let ui = referenceImage, let url = audioURL {
                                MusicVideoStoryboardView(referenceImage: ui, audioURL: url, settingId: selectedSettingId)
                            } else {
                                EmptyView()
                            }
                        },
                        label: {
                            Text("NEXT")
                                .font(.system(size: 22, weight: .heavy))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 64)
                                .background(Color.black)
                                .cornerRadius(14)
                                .padding(.horizontal, 24)
                        }
                    )
                    .disabled(referenceImage == nil || audioURL == nil || selectedSettingId.isEmpty)
                    .simultaneousGesture(TapGesture().onEnded {
                        // Future: could kick avatar gen prefetch here
                    })

                    Spacer().frame(height: 16)
                }
            }
        }
        .sheet(isPresented: $isShowingImagePicker) {
            ImagePicker(image: $referenceImage, sourceType: .photoLibrary)
        }
        .sheet(isPresented: $isShowingAudioPicker) {
            AudioPicker(onPick: { url in
                audioURL = url
            })
        }
        .sheet(isPresented: $showSettingSheet) {
            MusicVideoSettingsPickerView(onBack: { showSettingSheet = false }, onPick: { chosen in
                selectedSettingId = chosen.id
                showSettingSheet = false
            })
        }
    }
}


