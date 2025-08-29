import SwiftUI
import AVKit

/// Placeholder track canvas that will display clips added to the editor.
/// For now it renders a solid rectangle with the requested color (999CA0).
struct EditorTrackArea: View {
    let player: AVPlayer
    var body: some View {
        VideoPlayer(player: player)
            .background(Color.black)
            .frame(maxWidth: .infinity)
    }
}


