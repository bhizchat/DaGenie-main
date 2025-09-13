import SwiftUI
import AVKit

/// Read-only, distortion-free map card for a completed level.
struct JourneyLevelCard: View {
    let level: Int
    let runId: String

    @State private var missionSteps: [Int: Set<JourneyStep>] = [:]
    @State private var selectedMedia: CapturedMedia? = nil

    private let nodeCount: Int = 5
    // Normalized positions (0..1) across the card canvas, tuned to mimic live layout
    private let normalizedPositions: [(CGFloat, CGFloat)] = [
        (0.55, 0.14), // node 0 (Start)
        (0.35, 0.33), // node 1
        (0.66, 0.50), // node 2
        (0.37, 0.72), // node 3
        (0.58, 0.88)  // node 4 (End)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(level == 1 ? "Fall 2025" : "Level \(level)")
                .font(.pressStart(24))
                .foregroundColor(.white)

            GeometryReader { geo in
                ZStack {
                    // Dotted connector behind nodes
                    DottedConnector(points: absolutePoints(size: geo.size))
                        .stroke(style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [6, 8]))
                        .foregroundColor(Color.gray.opacity(0.6))
                    ForEach(0..<nodeCount, id: \.self) { idx in
                        let pos = normalizedPositions[min(idx, normalizedPositions.count - 1)]
                        let x = pos.0 * geo.size.width
                        let y = pos.1 * geo.size.height
                        let hasAny = (missionSteps[idx]?.isEmpty == false)
                        let status: MapNodeView.NodeStatus = hasAny ? .done : .pending

                        VStack(spacing: 4) {
                            if idx == 0 { Text("Start").font(.vt323(14)).foregroundColor(.white) }
                            MapNodeView(size: 70, status: status)
                                .overlay(
                                    Group {
                                        if hasAny {
                                            Image(systemName: "play.fill")
                                                .font(.caption)
                                                .foregroundColor(.white)
                                                .offset(y: 42)
                                        }
                                    }
                                )
                                .onTapGesture { if hasAny { openBestMedia(for: idx) } }
                            if idx == nodeCount - 1 { Text("End").font(.vt323(14)).foregroundColor(.white) }
                        }
                        .position(x: x, y: y)
                    }
                }
            }
            .frame(height: 480)
            .background(Color.black)
            .cornerRadius(8)
        }
        .padding(.vertical, 8)
        .onAppear { fetchPresence() }
        .sheet(item: $selectedMedia, content: { media in
            JourneyMediaSheet(media: media)
        })
    }

    private func absolutePoints(size: CGSize) -> [CGPoint] {
        normalizedPositions.map { CGPoint(x: $0.0 * size.width, y: $0.1 * size.height) }
    }

    private func fetchPresence() {
        JourneyPersistence.shared.aggregateStepsForRun(level: level, runId: runId) { map in
            self.missionSteps = map
        }
    }

    private func openBestMedia(for missionIndex: Int) {
        JourneyPersistence.shared.loadFor(level: level, runId: runId, missionIndex: missionIndex) { g, t, c in
            if let best = chooseBestMedia(game: g, task: t, checkpoint: c) {
                self.selectedMedia = best
            }
        }
    }
}

private func chooseBestMedia(game: CapturedMedia?, task: CapturedMedia?, checkpoint: CapturedMedia?) -> CapturedMedia? {
    return checkpoint ?? task ?? game
}

// Sheet for viewing a single media item in read-only mode
struct JourneyMediaSheet: View {
    let media: CapturedMedia
    @State private var player: AVPlayer? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
        }
        .onAppear {
            if media.type == .video, let url = media.remoteURL ?? URL(string: media.localURL.absoluteString) {
                player = AVPlayer(url: url)
                player?.play()
            }
        }
        .onDisappear { player?.pause(); player = nil }
    }

    @ViewBuilder private var content: some View {
        switch media.type {
        case .photo:
            let url = media.remoteURL ?? media.localURL
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty: ProgressView().tint(.white)
                case .success(let img): img.resizable().scaledToFit()
                case .failure: Image(systemName: "photo").foregroundColor(.white)
                @unknown default: EmptyView()
                }
            }
            .padding()
        case .video:
            if let player = player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView().tint(.white)
            }
        }
    }
}

// Shared dotted connector from AdventureMapView
fileprivate struct DottedConnector: Shape {
    let points: [CGPoint]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard points.count > 1 else { return p }
        p.move(to: points[0])
        for pt in points.dropFirst() { p.addLine(to: pt) }
        return p
    }
}


