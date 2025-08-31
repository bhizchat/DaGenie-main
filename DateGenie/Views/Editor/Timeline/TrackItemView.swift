import SwiftUI
import AVFoundation

struct TrackItemView: View {
    let kind: TrackKind
    let width: CGFloat
    let title: String?
    let samples: [Float]?
    let isSelected: Bool

    var body: some View {
        ZStack {
            switch kind {
            case .audio:
                WaveformView(samples: samples ?? [], color: isSelected ? .blue : .gray)
            case .text:
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.blue.opacity(0.2))
                    .overlay(Text(title ?? "").font(.system(size: 11, weight: .semibold)).foregroundColor(.white).padding(4), alignment: .leading)
            case .video:
                RoundedRectangle(cornerRadius: 2).stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            }
        }
        .frame(width: width, height: heightForKind(kind))
    }

    private func heightForKind(_ k: TrackKind) -> CGFloat {
        switch k {
        case .video: return TimelineStyle.videoRowHeight
        default: return TimelineStyle.laneRowHeight
        }
    }
}


