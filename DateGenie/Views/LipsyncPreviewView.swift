import SwiftUI
import AVKit

struct LipsyncPreviewView: View {
    let finalUrl: URL
    let onDownload: (() -> Void)?
    let onSend: (() -> Void)?
    let onClose: (() -> Void)?

    @State private var player: AVPlayer? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 28) {
                Text("PREVIEW")
                    .font(.system(size: 44, weight: .heavy))
                    .foregroundColor(.white)
                    .padding(.top, 24)

                ZStack {
                    if let p = player {
                        VideoPlayer(player: p)
                            .frame(height: 260)
                            .cornerRadius(10)
                            .onAppear {
                                p.seek(to: .zero)
                                p.play()
                            }
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 260)
                            .cornerRadius(10)
                    }

                    Circle()
                        .fill(Color.black.opacity(0.35))
                        .frame(width: 96, height: 96)
                        .overlay(
                            Image(systemName: "play.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 36, height: 36)
                                .foregroundColor(.white)
                        )
                        .onTapGesture { player?.play() }
                }
                .padding(.horizontal, 24)

                HStack(spacing: 64) {
                    VStack(spacing: 10) {
                        Button(action: { onDownload?() }) {
                            Image("preview_download")
                                .resizable()
                                .renderingMode(.original)
                                .frame(width: 44, height: 44)
                        }
                        Text("Download")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    VStack(spacing: 10) {
                        Button(action: { onSend?() }) {
                            Image("preview_send")
                                .resizable()
                                .renderingMode(.original)
                                .frame(width: 44, height: 44)
                        }
                        Text("Send")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }

                Spacer()

                Button(action: { onClose?() }) {
                    Text("Done")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(Color.white)
                        .cornerRadius(24)
                }

                Spacer().frame(height: 18)
            }
        }
        .onAppear {
            player = AVPlayer(url: finalUrl)
            // Start autoplay as soon as player is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { player?.play() }
        }
    }
}


