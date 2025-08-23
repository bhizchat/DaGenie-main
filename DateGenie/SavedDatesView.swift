//
//  SavedDatesView.swift
//  DateGenie
//
//  Lists user's saved date plans using the same IG-style feed UI as ThemeSwipeView,
//  with the top header bar (media bubbles + Generate Reel).
//

import SwiftUI
import AVFoundation
import UIKit

struct SavedDatesView: View {
    @EnvironmentObject var saved: SavedPlansVM
    @State private var runId: String? = RunManager.shared.currentRunId

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(Array(saved.savedPlans.enumerated()), id: \.element.id) { index, plan in
                        SavedPostCardView(plan: plan,
                                          onToggleSave: { saved.toggleSave(plan: plan) },
                                          onCamera: { openCaptureDirect(missionIndex: index) })
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Saved Dates")
        .onAppear {
            // Ensure a run exists so captured media can be saved under a runId
            let level = LevelStore.shared.currentLevel
            if RunManager.shared.currentRunId == nil {
                _ = RunManager.shared.resumeLastRun(level: level)
                if RunManager.shared.currentRunId == nil {
                    _ = RunManager.shared.startNewRun(level: level)
                }
            }
            runId = RunManager.shared.currentRunId
            JourneyPersistence.shared.saveLevelHeader(level: level)
        }
    }

    private func openCaptureDirect(missionIndex: Int) {
        let vc = UIHostingController(rootView: CameraSheet { media in
            guard let media = media else { return }
            let stepKey = "date_plan"
            var duration: Int? = nil
            if media.type == .video {
                // Use synchronous duration to avoid introducing async in this path (feature currently deprioritized)
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
                    print("[SavedDatesView] add-to-highlights failed: \(error)")
                }
            }
        })
        UIApplication.shared.topMostViewController()?.present(vc, animated: true)
    }
}

private struct SavedPostCardView: View {
    let plan: DatePlan
    let onToggleSave: () -> Void
    let onCamera: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(plan.title)
                .font(.system(.largeTitle, design: .rounded))
                .foregroundColor(.white)
                .padding(.top, 12)

            if let urlString = plan.heroImgUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty: ProgressView().frame(height: 180)
                    case .success(let img): img.resizable().scaledToFit().cornerRadius(8)
                    default: Color.gray.frame(height: 180).cornerRadius(8)
                    }
                }
            }

            // Distance + Address under photo
            if let meters = plan.distanceMeters {
                let miles = Double(meters) / 1609.34
                Text(String(format: "%.1f miles away from Campus", miles))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
            // Address (or venue name fallback) under photo
            if let addr = plan.venue?.address, !addr.isEmpty {
                Text(addr)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(.white)
            } else if let venueName = plan.venue?.name {
                Text(venueName)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(.white)
            }

            Text(plan.itinerary)
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 22) {
                Button(action: onToggleSave) {
                    Image("icon_save_filled")
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
        .background(Color(red: 242/255, green: 109/255, blue: 100/255))
        .cornerRadius(12)
        .shadow(radius: 1)
    }
}
