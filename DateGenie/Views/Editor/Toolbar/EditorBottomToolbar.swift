import SwiftUI

struct EditorBottomToolbar: View {
    let onEdit: () -> Void
    let onAudio: () -> Void
    let onText: () -> Void
    // Overlay removed per request
    // let onOverlay: () -> Void
    let onAspect: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                item(icon: "scissors", label: "Edit", action: onEdit)
                item(icon: "music.note", label: "Audio", action: onAudio)
                item(letter: "T", label: "Text", action: onText)
                item(icon: "rectangle.portrait", label: "Ratio", action: onAspect)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .background(Color.editorToolbarBackground)
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func item(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: { UIImpactFeedbackGenerator(style: .light).impactOccurred(); action() }) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(.white)
                    .font(.system(size: 20, weight: .semibold))
                Text(label)
                    .foregroundColor(.white)
                    .font(.system(size: 12, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func item(letter: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: { UIImpactFeedbackGenerator(style: .light).impactOccurred(); action() }) {
            VStack(spacing: 6) {
                Text(letter)
                    .foregroundColor(.white)
                    .font(.system(size: 20, weight: .semibold))
                Text(label)
                    .foregroundColor(.white)
                    .font(.system(size: 12, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func safeBottomInset() -> CGFloat {
        guard let w = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
            .first else { return 0 }
        return w.safeAreaInsets.bottom
    }
}


