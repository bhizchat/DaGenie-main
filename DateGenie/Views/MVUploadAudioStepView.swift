import SwiftUI
import AVFoundation
import FirebaseAuth

/// Second step: upload audio. Next is disabled until a file is picked; shows basic player.
struct MVUploadAudioStepView: View {
    let referenceImage: UIImage
    let settingId: String
    let initialAvatarUrl: String?

    init(referenceImage: UIImage, settingId: String, initialAvatarUrl: String? = nil) {
        self.referenceImage = referenceImage
        self.settingId = settingId
        self.initialAvatarUrl = initialAvatarUrl
    }

    @Environment(\.dismiss) private var navDismiss
    @State private var audioURL: URL? = nil
    @State private var isShowingAudioPicker: Bool = false
    @State private var durationText: String = ""
    @State private var player: AVAudioPlayer? = nil
    @State private var isPlaying: Bool = false
    @State private var audioDurationSec: Double? = nil
    @State private var openIdea: Bool = false
    @State private var projectId: String? = nil
    @State private var audioGsPath: String? = nil
    @State private var referenceUrl: String? = nil
    @State private var avatarUrl: String? = nil

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

                Text("Upload your song")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundColor(.black)

                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white)
                    .frame(width: 360, height: 260)
                    .overlay(
                        VStack(spacing: 16) {
                            Image("music-folder")
                                .resizable()
                                .renderingMode(.original)
                                .scaledToFit()
                                .frame(width: 140, height: 140)

                            if audioURL == nil {
                                Button(action: { isShowingAudioPicker = true }) {
                                    Text("Select Files")
                                        .font(.system(size: 16, weight: .bold))
                                        .padding(.vertical, 10)
                                        .padding(.horizontal, 18)
                                        .background(Color(red: 0xE9/255.0, green: 0x45/255.0, blue: 0x45/255.0))
                                        .foregroundColor(.white)
                                        .cornerRadius(14)
                                }
                            } else {
                                HStack(spacing: 12) {
                                    Button(action: { togglePlay() }) {
                                        Image(systemName: isPlaying ? "pause.fill" : "play.fill").foregroundColor(.black)
                                    }
                                    Rectangle().fill(Color.black).frame(height: 4)
                                    Text(durationText).font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.black)
                                }
                                .padding(.horizontal, 20)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    )

                Spacer()

                NavigationLink {
                    MusicVideoSettingsPickerView(onBack: nil, onPick: { item in
                        Task { await uploadAndOpenIdea(settingId: item.id) }
                    }, title: "Locations")
                } label: {
                    Text("NEXT")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                        .background(audioURL == nil ? Color.composerGray : Color.black)
                        .cornerRadius(32)
                        .padding(.horizontal, 24)
                }
                .disabled(audioURL == nil)

                // Hidden link -> Describe Music Video (idea) screen
                NavigationLink(isActive: $openIdea) {
                    if let uid = Auth.auth().currentUser?.uid,
                       let pid = projectId,
                       let audio = audioGsPath,
                       let ref = (avatarUrl ?? referenceUrl) {
                        MusicVideoIdeaView(
                            uid: uid,
                            projectId: pid,
                            settingId: settingId,
                            referenceImageUrl: ref,
                            audioGsPath: audio,
                            audioDurationSec: audioDurationSec ?? 0,
                            promptKit: promptKitFor(settingId: settingId)
                        )
                    } else {
                        EmptyView()
                    }
                } label: { EmptyView() }
                .hidden()

                Spacer().frame(height: 6)
            }
            }
        }
        .sheet(isPresented: $isShowingAudioPicker) {
            AudioPicker(onPick: { url in
                guard let u = url else { return }
                audioURL = u
                let asset = AVURLAsset(url: u, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
                let sec = CMTimeGetSeconds(asset.duration)
                audioDurationSec = sec
                durationText = format(seconds: sec)
                setupPlayer(with: u)
            })
        }
        .onAppear { self.avatarUrl = initialAvatarUrl }
    }

    private func setupPlayer(with url: URL) {
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
        } catch {
            player = nil
        }
        isPlaying = false
    }

    private func togglePlay() {
        guard let p = player else { return }
        if isPlaying { p.pause() } else { p.play() }
        isPlaying.toggle()
    }

    private func format(seconds: Double) -> String {
        let s = Int(seconds.rounded())
        let m = s / 60
        let r = s % 60
        return String(format: "%02d:%02d", m, r)
    }

    // MARK: - Progression helpers
    private func uploadAndOpenIdea(settingId: String) async {
        guard let aurl = audioURL, let uid = Auth.auth().currentUser?.uid else { return }
        do {
            await MainActor.run { LoadingOverlay.show(text: "Loading…") }
            let imgData = referenceImage.jpegData(compressionQuality: 0.92) ?? Data()
            let created = try await MusicVideoRepository.shared.createProjectAndUpload(userId: uid, referenceImageData: imgData, audioURL: aurl)
            await MainActor.run {
                self.projectId = created.projectId
                self.audioGsPath = created.audioGsPath
                self.referenceUrl = created.referenceUrl
                self.openIdea = true
                LoadingOverlay.hide()
            }
        } catch {
            // TODO: surface error if needed
            await MainActor.run { LoadingOverlay.hide() }
        }
    }

    private func promptKitFor(settingId: String) -> [String: Any] {
        guard let cat = MusicVideoSettingsCatalog.all.first(where: { $0.id == settingId }) else { return [:] }
        return [
            "setPacks": cat.promptKit.setPacks,
            "loopGags": cat.promptKit.loopGags,
            "cameraGrammar": cat.promptKit.cameraGrammar,
            "fpsHint": cat.promptKit.fpsHint,
            "bio": cat.bio,
            "environment": cat.environment,
            "palette": cat.palette,
            "storyTemplates": cat.promptKit.storyTemplates,
        ]
    }
}


