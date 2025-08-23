//  ThemeSwipeView.swift – matches screenshot #2
import SwiftUI
import AVFoundation
import UIKit

struct ThemeSwipeView: View {
    @Environment(\.dismiss) private var dismiss
    let themes: [CampusTheme]
    @State private var likedIds: Set<String> = []
    @State private var showMap = false
    @EnvironmentObject var savedPlansVM: SavedPlansVM

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(Array(themes.enumerated()), id: \.element.id) { index, theme in
                        PostCardView(theme: theme,
                                     isLiked: likedIds.contains(theme.id),
                                     onLike: { toggleLike(theme) },
                                     onCamera: { openCaptureDirect(for: theme, missionIndex: index) })
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            // Ensure a run exists so media can be saved under a runId
            let level = LevelStore.shared.currentLevel
            if RunManager.shared.currentRunId == nil {
                _ = RunManager.shared.resumeLastRun(level: level)
                if RunManager.shared.currentRunId == nil {
                    _ = RunManager.shared.startNewRun(level: level)
                }
            }
            JourneyPersistence.shared.saveLevelHeader(level: level)
            UserDefaults.standard.set(true, forKey: "seen_theme_swipe_onboarding")
        }
    }

    private func destinations() -> [CampusTheme] {
        let liked = themes.filter { likedIds.contains($0.id) }
        if !liked.isEmpty { return liked }
        return []
    }

    private func toggleLike(_ theme: CampusTheme) {
        if likedIds.contains(theme.id) {
            likedIds.remove(theme.id)
        } else {
            likedIds.insert(theme.id)
            // Convert the current card into a DatePlan preserving the text exactly as shown
            let milesText: String? = {
                if let meters = theme.distanceMeters {
                    let miles = Double(meters) / 1609.34
                    return String(format: "%.1f miles away from Campus", miles)
                }
                return nil
            }()
            // Compose itinerary snippet from curated missionLines when available
            let snippet: String = {
                if let lines = theme.missionLines, !lines.isEmpty {
                    return lines.joined(separator: "\n")
                }
                return "Pop into \(theme.venueName) for milk or fruit tea, chat about anything while you wait, then snap a quick neon pic under the glowing sign—recreate a boyband album cover, awkward hands included."
            }()
            let plan = DatePlan(
                id: theme.id,
                title: theme.title,
                itinerary: snippet,
                heroImgUrl: theme.photoUrl,
                venue: Venue(name: theme.venueName, address: theme.address, rating: nil, photoUrl: theme.photoUrl, mapsUrl: nil),
                scores: nil,
                distanceMeters: theme.distanceMeters
            )
            savedPlansVM.toggleSave(plan: plan)
        }
    }

    private func openCaptureDirect(for theme: CampusTheme, missionIndex: Int) {
        let vc = UIHostingController(rootView: CameraSheet { media in
            guard let media = media else { return }
            let stepKey = "date_plan"
            var duration: Int? = nil
            if media.type == .video {
                let asset = AVURLAsset(url: media.localURL)
                duration = Int(CMTimeGetSeconds(asset.duration).rounded())
            }

            // Present immediate preview for share/download
            if media.type == .video {
                let preview = UIHostingController(rootView: ReelPreviewView(url: media.localURL))
                preview.modalPresentationStyle = .overFullScreen
                preview.isModalInPresentation = true
                preview.view.backgroundColor = .black
                UIApplication.shared.topMostViewController()?.present(preview, animated: true)
            } else {
                let preview = UIHostingController(rootView: PhotoPreviewView(url: media.localURL))
                preview.modalPresentationStyle = .overFullScreen
                preview.isModalInPresentation = true
                preview.view.backgroundColor = .black
                UIApplication.shared.topMostViewController()?.present(preview, animated: true)
            }

            // Persist into mission timeline as before
            _ = MediaUploadManager.shared.upload(media: media, step: stepKey, progress: { _ in }, completion: { result in
                if case .success(let url) = result {
                    let persisted = CapturedMedia(localURL: media.localURL, type: media.type, caption: media.caption, remoteURL: url, uploadProgress: 1.0, cameraSource: media.cameraSource)
                    JourneyPersistence.shared.saveNode(step: stepKey, missionIndex: missionIndex, media: persisted, durationSeconds: duration)
                    NotificationCenter.default.post(name: Notification.Name("missionProgressUpdated"), object: nil)
                }
            })

            // Also add to Highlights in background
            Task.detached {
                let level = LevelStore.shared.currentLevel
                let runId = RunManager.shared.currentRunId ?? UUID().uuidString
                do {
                    if media.type == .video {
                        let asset = AVURLAsset(url: media.localURL)
                        let gen = AVAssetImageGenerator(asset: asset)
                        gen.appliesPreferredTrackTransform = true
                        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
                        let imageRef = try? gen.copyCGImage(at: time, actualTime: nil)
                        let jpegData = imageRef.flatMap { UIImage(cgImage: $0).jpegData(compressionQuality: 0.8) } ?? Data()
                        _ = try await HighlightReelRepository.shared.create(fromExportURL: media.localURL, thumbnail: jpegData, level: level, runId: runId, title: nil, cameraSource: media.cameraSource?.rawValue)
                    } else {
                        _ = try await HighlightReelRepository.shared.createPhoto(fromLocalURL: media.localURL, level: level, runId: runId, title: nil, cameraSource: media.cameraSource?.rawValue)
                    }
                } catch {
                    print("[ThemeSwipeView] add-to-highlights failed: \(error)")
                }
            }
        })
        UIApplication.shared.topMostViewController()?.present(vc, animated: true)
    }
}

// MARK: - Swipeable Card
// MARK: - Swipeable Card (refactored)
struct ThemeCard: View {
    let theme: CampusTheme

    var body: some View {
        VStack(spacing: 12) {
            headerImage
            Text(theme.title)
                .font(.vt323(22))
                .multilineTextAlignment(.center)
            Text("Venue: \(theme.venueName)")
                .font(.vt323(20))
            missionList
        }
    }

    // MARK: - Sub-Views
    @ViewBuilder private var headerImage: some View {
        // Show only the venue image (no extra illustrations)
        AsyncImage(url: URL(string: theme.photoUrl)) { phase in
            switch phase {
            case .empty:
                ProgressView().frame(maxHeight: 250)
            case .success(let image):
                image.resizable()
                    .scaledToFit()
                    .frame(maxHeight: 250)
                    .cornerRadius(8)
            default:
                Color.gray.frame(maxHeight: 250)
            }
        }
    }

    @ViewBuilder private var missionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Date Plan")
                .font(.title3)
                .bold()
                .foregroundColor(.white)
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 6) {
                        Color.clear.frame(height: 0).id("top")
                        ForEach(theme.missions.gamesToPlay + [theme.missions.checkpointPhoto], id: \.self) { item in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•").bold()
                                Text(item).fixedSize(horizontal: false, vertical: true)
                            }
                            .foregroundColor(.white)
                        }
                    }
                }
                .frame(maxHeight: 180)
                .onChange(of: theme.id) { _ in
                    withAnimation { proxy.scrollTo("top", anchor: .top) }
                }
            }
        }
        .padding()
        .background(Color.missionCard)
        .cornerRadius(8)
    }

    // removed X/Check/Undo; bottom buttons now live below the card
}

// New compact post-like card matching the desired layout
struct PostCardView: View {
    let theme: CampusTheme
    let isLiked: Bool
    let onLike: () -> Void
    let onCamera: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title on top
            Text("\(theme.title)")
                .font(.system(.largeTitle, design: .rounded))
                .foregroundColor(.white)
                .padding(.top, 12)

            // Photo
            AsyncImage(url: URL(string: theme.photoUrl)) { phase in
                switch phase {
                case .empty: ProgressView().frame(height: 180)
                case .success(let img): img.resizable().scaledToFit().cornerRadius(8)
                default: Color.gray.frame(height: 180).cornerRadius(8)
                }
            }

            // Distance + Address under photo
            if let meters = theme.distanceMeters {
                let miles = Double(meters) / 1609.34
                Text(String(format: "%.1f miles away from Campus", miles))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
            if let addr = theme.address, !addr.isEmpty {
                Text(addr)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(.white)
            } else {
                Text(theme.venueName)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(.white)
            }

            // Snippet: prefer curated missionLines if present
            let snippet: String = {
                if let lines = theme.missionLines, !lines.isEmpty {
                    return lines.joined(separator: "\n")
                }
                return "Pop into \(theme.venueName) for milk or fruit tea, chat about anything while you wait, then snap a quick neon pic under the glowing sign—recreate a boyband album cover, awkward hands included."
            }()
            Text(snippet)
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 22) {
                Button(action: onLike) {
                    Image(isLiked ? "icon_save_filled" : "icon_save")
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                }
                Button(action: onCamera) {
                    Image("icon_camera_solid")
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                }
            }
            .padding(.vertical, 8)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .background(Color(red: 242/255, green: 109/255, blue: 100/255)) // #F26D64
        .cornerRadius(12)
        .shadow(radius: 1)
    }
}

// MARK: - Scroll-bounce shim
private extension View {
    func bounceDisabled() -> some View {
        self // currently no-op; replace with scrollBounceBehavior when targeting iOS 17+
    }
}

#if DEBUG
struct ThemeSwipeView_Previews: PreviewProvider {
    static var previews: some View {
        ThemeSwipeView(themes: Array(repeating: CampusTheme.sample, count: 3))
    }
    }
#endif
