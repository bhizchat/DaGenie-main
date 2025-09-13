import SwiftUI

/// Bottom overlay toolbar for adding media and brand logo overlays.
/// Mirrors sizing/spacing of `EditToolsBar` to avoid timeline jumps.
struct OverlayToolsBar: View {
    @ObservedObject var state: EditorState
    let onClose: () -> Void
    let onAddMedia: () -> Void
    // Removed logo picker per product direction – keep only media

    var body: some View {
        HStack(spacing: 10) {
            // Back/close tile — no label to match EditToolsBar
            EditToolsBarItem(assetName: "left-arrow", title: "", action: onClose)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    // Add Media button (uses play_triangle asset per spec)
                    OverlayToolsBarItem(assetName: "play_triangle", title: "Add Media", action: onAddMedia)
                    // Logo button removed – only Add Media remains
                }
                .padding(.vertical, 6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Color.editorToolbarBackground)
        .ignoresSafeArea(edges: .bottom)
    }
}

/// Visual style consistent with EditToolsBar items, but allows nil asset (text-only)
private struct OverlayToolsBarItem: View {
    let assetName: String?
    let title: String
    let action: () -> Void
    var previewImage: UIImage? = nil
    var isEnabled: Bool = true

    var body: some View {
        Button(action: { if isEnabled { action() } }) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isEnabled ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
                        .frame(width: 56, height: 56)
                    if let asset = assetName {
                        Image(asset)
                            .renderingMode(.original)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 26, height: 26)
                            .opacity(isEnabled ? 1.0 : 0.4)
                    } else if let ui = previewImage {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                            .opacity(isEnabled ? 1.0 : 0.4)
                    } else {
                        // Minimal placeholder if no asset
                        Text(title.prefix(1))
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white.opacity(isEnabled ? 0.9 : 0.4))
                    }
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(isEnabled ? 0.9 : 0.4))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}


