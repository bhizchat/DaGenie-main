import SwiftUI

// MARK: - CustomCameraView Filter Picker Extension
// With only one sticker, we no longer need swipe index changes.
extension CustomCameraView { enum PickerDirection { case next, prev } }

// MARK: - Circular Picker Button
struct FilterPickerButton: View {
    // Name of a UI Image Set (not a Texture Set) for the thumbnail
    let uiThumbnailName: String?
    let size: CGFloat
    var showThumbnail: Bool = true
    let onSwipe: (CustomCameraView.PickerDirection) -> Void

    @State private var offsetX: CGFloat = 0

    var body: some View {
        ZStack {
            if showThumbnail,
               let name = uiThumbnailName,
               let ui = UIImage(named: name) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .transition(.opacity)
            }
            Circle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: size, height: size)
        }
        .offset(x: offsetX)
        .contentShape(Circle())
        .animation(.easeInOut(duration: 0.2), value: showThumbnail)
        .onTapGesture { onSwipe(.next) }
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    offsetX = max(-100, min(value.translation.width, 100))
                }
                .onEnded { value in
                    let threshold: CGFloat = 40
                    if abs(value.translation.width) > threshold { onSwipe(.next) }
                    withAnimation(.spring()) { offsetX = 0 }
                }
        )
    }
}
