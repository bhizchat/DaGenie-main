import SwiftUI
import AVFoundation

struct SingleQuestView: View {
    let questText: String
    let missionIndex: Int
    let mediaType: MediaType? // preferred, nil = allow both
    let imageURL: String?

    // UI state
    @State private var captured: CapturedMedia? = nil
    @State private var showingCamera = false
    @State private var showingPlayer = false
    @State private var pendingMedia: CapturedMedia? = nil
    @State private var showPhotoEditor = false
    @State private var showVideoCaption = false

    var body: some View {
        VStack(spacing: 16) {
            if let urlStr = imageURL, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty: ProgressView()
                    case .success(let img): img.resizable().scaledToFit().cornerRadius(8)
                    case .failure: Color.gray.frame(height: 180).cornerRadius(8)
                    @unknown default: EmptyView()
                    }
                }
                .padding(.horizontal)
            }
            VStack(spacing: 8) {
                Text("DATE PLAN")
                    .font(.pressStart(20))
                    .foregroundColor(.white)
                HStack(spacing: 6) {
                    Text("STATUS :")
                        .font(.pressStart(16))
                        .foregroundColor(.white)
                    Text(captured != nil ? "COMPLETED" : "UNDONE")
                        .font(.pressStart(16))
                        .foregroundColor(captured != nil ? .green : .white)
                }
            }

            Text(questText)
                .font(.system(size: 20, weight: .regular, design: .rounded))
                .foregroundColor(.white)
                .padding()
                .fixedSize(horizontal: false, vertical: true)

            Button(action: { if captured != nil { showingPlayer = true } }) {
                HStack(spacing: 10) {
                    Text("PLAY  MEDIA")
                        .font(.vt323(22))
                        .foregroundColor(.white)
                    Image("play_triangle")
                        .resizable()
                        .renderingMode(.template)
                        .foregroundColor(.white)
                        .frame(width: 18, height: 18)
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color(red: 242/255, green: 109/255, blue: 100/255))
                .cornerRadius(6)
            }
            .padding(.horizontal, 24)
            .opacity(captured != nil ? 1 : 0.001)
            .allowsHitTesting(captured != nil)

            Spacer()

            Button(action: { showingCamera = true }) {
                HStack(spacing: 8) {
                    Text("OPEN  CAMERA")
                        .font(.vt323(22))
                        .foregroundColor(.white)
                    Image("icon_camera")
                        .resizable()
                        .frame(width: 28, height: 28)
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .padding(.horizontal, 16)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white, lineWidth: 2)
                )
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: $showingCamera) {
            CameraSheet { media in
                guard let media = media else { return }
                // Hold while we route to editor/caption
                pendingMedia = media
                if media.type == .photo {
                    showPhotoEditor = true
                } else {
                    showVideoCaption = true
                }
            }
        }
        .sheet(isPresented: $showingPlayer, onDismiss: { /* no-op */ }) {
            if let media = captured {
                MediaPlayerView(media: media)
            }
        }
        .fullScreenCover(isPresented: $showPhotoEditor, onDismiss: { pendingMedia = nil }) {
            if let pending = pendingMedia, pending.type == .photo {
                PhotoEditorView(originalURL: pending.localURL, onCancel: {
                    showPhotoEditor = false
                }, onExport: { editedURL in
                    let finalized = CapturedMedia(localURL: editedURL, type: .photo)
                    assignAndSave(finalized)
                    showPhotoEditor = false
                })
            }
        }
        .sheet(isPresented: $showVideoCaption, onDismiss: { pendingMedia = nil }) {
            if let pending = pendingMedia, pending.type == .video {
                VideoCaptionSheet(onCancel: { showVideoCaption = false }, onSave: { caption in
                    var finalized = CapturedMedia(localURL: pending.localURL, type: .video, caption: caption)
                    assignAndSave(finalized)
                    showVideoCaption = false
                })
            }
        }
    }

    private func assignAndSave(_ media: CapturedMedia) {
        captured = media
        // Start background upload and persist under step="quest"
        _ = MediaUploadManager.shared.upload(media: media, step: "date_plan", progress: { _ in }, completion: { result in
            if case .success(let url) = result {
                captured?.remoteURL = url
                var duration: Int? = nil
                if media.type == .video {
                    let asset = AVURLAsset(url: media.localURL)
                    duration = Int(CMTimeGetSeconds(asset.duration).rounded())
                }
                JourneyPersistence.shared.saveNode(step: "date_plan", missionIndex: missionIndex, media: CapturedMedia(localURL: media.localURL, type: media.type, caption: media.caption, remoteURL: url, uploadProgress: 1.0), durationSeconds: duration)
            }
        })
    }
}


