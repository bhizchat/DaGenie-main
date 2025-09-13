import SwiftUI
import AVFoundation

struct TimelineStripView: View {
    @Binding var currentTime: CMTime
    let duration: CMTime
    let thumbnails: [UIImage]
    let times: [CMTime]
    let onScrub: (CMTime) -> Void

    @State private var isDragging: Bool = false

    var body: some View {
        ZStack(alignment: .center) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(thumbnails.indices, id: \.self) { idx in
                        let img = thumbnails[idx]
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipped()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard idx < times.count else { return }
                                let t = times[idx]
                                currentTime = t
                                onScrub(t)
                            }
                    }
                }
                .padding(.horizontal, 48)
            }
            .frame(height: 72)
        }
        .background(Color.white.opacity(0.08))
        .gesture(DragGesture(minimumDistance: 4)
            .onChanged { value in
                isDragging = true
                let widthPerThumb: CGFloat = 72
                let total = Double(max(thumbnails.count - 1, 1))
                let deltaThumbs = value.translation.width / widthPerThumb
                let seconds = CMTimeGetSeconds(duration)
                let deltaSeconds = Double(deltaThumbs) * (seconds / total)
                let newTime = max(0, min(seconds, CMTimeGetSeconds(currentTime) + deltaSeconds))
                let t = CMTime(seconds: newTime, preferredTimescale: 600)
                currentTime = t
                onScrub(t)
            }
            .onEnded { _ in
                isDragging = false
            }
        )
        .ignoresSafeArea(edges: .bottom)
    }
}


