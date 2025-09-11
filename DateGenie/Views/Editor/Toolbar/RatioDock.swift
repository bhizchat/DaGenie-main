import SwiftUI

struct RatioDock: View {
    @Binding var selected: AspectRatio
    var onDismiss: (() -> Void)? = nil

    private struct Preset: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let icon: String
        let aspect: AspectRatio
    }

    private var presets: [Preset] {
        [
            Preset(title: "Vertical 9:16", icon: "tiktok", aspect: .nineBySixteen),
            Preset(title: "Horizontal 4:3", icon: "youtube", aspect: .fourByThree)
        ]
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("Ratio")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: { onDismiss?() }) {
                    Image("white_check")
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .padding(6)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
            .padding(.horizontal, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(presets) { p in
                        chip(title: p.title, icon: p.icon, isSelected: p.aspect == selected) {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            selected = p.aspect
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
            .frame(height: 74)
        }
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func chip(title: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.18) : Color.white.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}


