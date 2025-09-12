import SwiftUI

struct CheckpointPhotoView: View {
    let promptText: String
    let isCompleted: Bool
    let uploadProgress: Double?
    let hasRemote: Bool
    let onOpenCamera: () -> Void
    let onPlay: (() -> Void)?
    let onBack: () -> Void
    let onFinish: () -> Void
    let isReplay: Bool = false
    @Environment(\.dismiss) private var dismiss
    @State private var statusDone = false

    var body: some View {
        VStack(spacing: 16) {
            // Header
            VStack(spacing: 8) {
                Text("CHECKPOINT PHOTO")
                    .kerning(-1)
                    .font(.pressStart(20))
                    .foregroundColor(.white)
                HStack(spacing: 4) {
                    Text("STATUS :")
                        .font(.pressStart(16))
                        .foregroundColor(.white)
                    Text(isCompleted ? "COMPLETED" : "UNDONE")
                        .font(.pressStart(16))
                        .foregroundColor(isCompleted ? .green : .white)
                    Group {
                        if isCompleted {
                            Image("status_check")
                                .resizable()
                                .frame(width: 18, height: 18)
                        } else {
                            Image("icon_close_red")
                                .resizable()
                                .frame(width: 18, height: 18)
                        }
                    }
                }
            }
            .padding(.top, 8)

            // prompt
            Text(promptText)
                .font(.system(size: 20, weight: .regular, design: .rounded))
                .foregroundColor(.white)
                .padding()
                .fixedSize(horizontal: false, vertical: true)

            Button(action: { onPlay?() }) {
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
                    .overlay(
                        Group {
                            if let p = uploadProgress, !hasRemote, p < 1.0 {
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Rectangle()
                                            .fill(Color.white.opacity(0.15))
                                            .frame(height: 4)
                                            .offset(y: geo.size.height - 6)
                                        Rectangle()
                                            .fill(Color(red: 242/255, green: 109/255, blue: 100/255))
                                            .frame(width: max(8, CGFloat(p) * geo.size.width), height: 4)
                                            .offset(y: geo.size.height - 6)
                                    }
                                }
                            }
                        }
                    )
            }
            .padding(.horizontal, 24)
            .opacity(isCompleted && onPlay != nil ? 1 : 0.001)
            .allowsHitTesting(isCompleted && onPlay != nil)

            Spacer()

            VStack(alignment: .trailing, spacing: 12) {
                if !isReplay {
                Button(action: {
                    onOpenCamera()
                }) {
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
                }

                HStack(spacing: 16) {
                    Button(action: { onBack() }) {
                        Text("BACK")
                            .font(.vt323(24))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.white, lineWidth: 2)
                            )
                    }

                    Button(action: { onFinish() }) {
                        Text("FINISH MISSION")
                            .font(.vt323(24))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.white, lineWidth: 2)
                            )
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }
}
